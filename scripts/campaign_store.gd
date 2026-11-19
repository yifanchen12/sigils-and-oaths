extends RefCounted
## Versioned plain JSON with last-good backup. Player saves never load script objects.

const Campaign = preload("res://scripts/campaign.gd")
const Story = preload("res://scripts/story_runner.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Difficulty = preload("res://scripts/campaign_difficulty.gd")
const VERSION: int = 7
const MAX_BYTES: int = 1048576
var path: String

func _init(save_path: String = "user://campaign_autosave.json") -> void:
	path = save_path

func _read_path(source: String) -> Dictionary:
	if not FileAccess.file_exists(source): return {"ok": false, "missing": true, "message": "尚无战役进度。"}
	var file: FileAccess = FileAccess.open(source, FileAccess.READ)
	if file == null: return {"ok": false, "message": "无法读取战役存档。"}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok": false, "message": "战役存档过大，未载入。"}
	var parser := JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary: return {"ok": false, "message": "战役存档格式损坏。"}
	var data: Dictionary = parser.data
	var version: Variant = data.get("version")
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(version)) or float(version) != floorf(float(version)) or version < 1:
		return {"ok": false, "message": "战役存档版本无效。"}
	if data.version > VERSION: return {"ok": false, "future": true, "message": "存档来自较新版本，当前版本不会覆盖。"}
	var progress: Variant = data.get("progress")
	var encounter: Variant = {} if int(version) == 1 else data.get("encounter")
	if int(data.version) < 4 and progress is Dictionary and progress.has("requisition"):
		return {"ok": false, "message": "旧版战役档不能包含战前军需。"}
	if int(data.version) < 5 and _has_progress_field(progress, "armory"):
		return {"ok": false, "message": "旧版战役档不能包含战役军备。"}
	if int(version) < 6 and (_has_progress_field(progress, "difficulty") or (encounter is Dictionary and encounter.has("difficulty"))):
		return {"ok": false, "message": "旧版战役档不能包含战役难度。"}
	if int(version) < 7 and data.has("last_attempt"):
		return {"ok": false, "message": "旧版战役档不能包含战局复盘。"}
	var validated: Dictionary = _validate(progress, encounter, data.get("last_attempt", {}))
	if validated.ok and int(data.version) < VERSION: validated["migrated"] = true
	return validated

static func _has_progress_field(progress: Variant, key: String) -> bool:
	if not progress is Dictionary: return false
	var records: Variant = progress.get("completed")
	return progress.has(key) or (records is Array and records.any(func(record: Variant) -> bool: return record is Dictionary and record.has(key)))

func _validate(progress: Variant, encounter: Variant, last_attempt: Variant = {}) -> Dictionary:
	var campaign: RefCounted = Campaign.new()
	var restored: Dictionary = campaign.restore(progress)
	if not restored.ok: return restored
	if not encounter is Dictionary or not last_attempt is Dictionary or (not encounter.is_empty() and not last_attempt.is_empty()):
		return {"ok": false, "message": "战役的出征与复盘资料不一致。"}
	var validated := {"ok": true, "progress": campaign.snapshot(), "encounter": {}, "last_attempt": {}}
	var page: Dictionary = campaign.story.current()
	if not encounter.is_empty():
		var live := _field(campaign, encounter, campaign.difficulty, campaign.requisition, campaign.armory, page.revision)
		if not live.ok: return live
		validated.encounter = live.record
	if last_attempt.is_empty(): return validated
	if page.type != "battle" or page.last_outcome not in ["defeat", "draw"] or not Story._whole(last_attempt.get("attempt")) or last_attempt.attempt != page.attempts:
		return {"ok": false, "message": "复盘与当前任务的上次战果不一致。"}
	var mode: Variant = last_attempt.get("difficulty", Difficulty.STANDARD)
	var requisition: Variant = last_attempt.get("requisition", "")
	var picks: Variant = last_attempt.get("armory", {})
	if not Difficulty.is_valid(mode) or not requisition is String or not Campaign.Requisition.allows(campaign.scenario(), requisition):
		return {"ok": false, "message": "复盘的难度或军需无效。"}
	var issue: String = Campaign.Armory.validate(picks, campaign.completed.size())
	if not issue.is_empty(): return {"ok": false, "message": issue}
	var archived := _field(campaign, last_attempt, mode, requisition, picks, int(page.revision) - 1)
	if not archived.ok: return archived
	var record: Dictionary = archived.record
	if record.battle.winner != (2 if page.last_outcome == "draw" else 1):
		return {"ok": false, "message": "复盘必须是本次失利或平局的终局棋盘。"}
	record["attempt"] = int(page.attempts)
	if not requisition.is_empty(): record["requisition"] = requisition
	if not picks.is_empty(): record["armory"] = picks.duplicate()
	validated.last_attempt = record
	return validated

func _field(campaign: RefCounted, encounter: Dictionary, mode: String, requisition: String, picks: Dictionary, expected_revision: int) -> Dictionary:
	var page: Dictionary = campaign.story.current()
	if page.type != "battle" or encounter.get("scenario") != page.scenario or not Story._whole(encounter.get("revision")) or encounter.revision != expected_revision:
		return {"ok": false, "message": "战斗与当前剧情进度不一致。"}
	if encounter.get("difficulty", Difficulty.STANDARD) != mode:
		return {"ok": false, "message": "当前战斗难度与战前选择不一致。"}
	var restored: Dictionary = Snapshot.restore(encounter.get("battle"))
	if not restored.ok: return restored
	var battle: RefCounted = restored.battle
	var setup: Dictionary = campaign.scenario()
	var control: Dictionary = Difficulty.control_for(setup, mode)
	if battle.ControlObjective.config(battle.objective) != battle.ControlObjective.config(control):
		return {"ok": false, "message": "战斗目标与关卡不一致。"}
	if battle.map_definition.id != setup.map or battle.match_seed != int(setup.seed) or battle.turn_time_limit != 90:
		return {"ok": false, "message": "战斗地图、种子或时限与关卡不一致。"}
	# Preserve only published encounters whose opponent deck changed;
	# retry always starts with the current campaign setup.
	var previous_enemy_deck: String = {"c01_bridge": "bastion", "c02_relief_bridge": "assault", "c08_isolate": "bastion"}.get(page.scenario, "")
	var old_encounter: bool = setup.enemy_deck == "balanced" and battle.deck(1).id == previous_enemy_deck
	var old_dispatch_deck: bool = page.scenario == "c02_dispatch" and setup.deck == "bastion" and battle.deck(0).id == "assault"
	var correct_deck: bool = battle.deck(0).id == setup.deck or old_dispatch_deck
	if not picks.is_empty():
		var expected: Dictionary = Campaign.Armory.prepare(setup, requisition, picks)
		if not expected.ok: return expected
		correct_deck = battle.deck(0).id == "custom" and battle.deck(0).cards == expected.battle.deck(0).cards
	elif not requisition.is_empty():
		correct_deck = battle.deck(0).id == "custom" and battle.deck(0).cards == Campaign.Requisition.counts_for(setup, requisition)
	if battle.players[0].hero_id != setup.hero or battle.players[1].hero_id != setup.enemy_class or not correct_deck or (battle.deck(1).id != setup.enemy_deck and not old_encounter):
		return {"ok": false, "message": "战斗军势与关卡不一致。"}
	if battle.players[0].has("hero_display") or battle.hero(1).name != setup.enemy_name or battle.hero(1).portrait != setup.enemy_portrait:
		return {"ok": false, "message": "战斗指挥官身份与关卡不一致。"}
	var saved_encounter: Dictionary = {"scenario": page.scenario, "revision": expected_revision, "battle": Snapshot.capture(battle)}
	if mode != Difficulty.STANDARD: saved_encounter["difficulty"] = mode
	return {"ok": true, "record": saved_encounter}

func load_progress() -> Dictionary:
	var primary: Dictionary = _read_path(path)
	if primary.ok or _protected(primary): return primary
	var backup: Dictionary = _read_path(path + ".bak")
	if _protected(backup): return backup
	if backup.ok:
		backup["recovered"] = true
		backup["message"] = "已从上次有效备份恢复战役进度。"
		return backup
	return primary

func _protected(result: Dictionary) -> bool:
	return result.get("future", false) or result.get("protected", false)

func save_progress(progress: Variant, encounter: Dictionary = {}, last_attempt: Dictionary = {}) -> Dictionary:
	var validated: Dictionary = _validate(progress, encounter, last_attempt)
	if not validated.ok: return validated
	var primary: Dictionary = _read_path(path)
	var backup: Dictionary = _read_path(path + ".bak")
	if _protected(primary): return primary
	if _protected(backup): return backup
	var envelope := {"version": VERSION, "progress": validated.progress, "encounter": validated.encounter}
	if not validated.last_attempt.is_empty(): envelope["last_attempt"] = validated.last_attempt
	var encoded: String = JSON.stringify(envelope, "\t", true, true)
	if encoded.to_utf8_buffer().size() > MAX_BYTES: return {"ok": false, "message": "战役进度过大，未覆盖原档。"}
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return {"ok": false, "message": "保存失败：无法写入临时战役文件。"}
	var stored: bool = file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not stored or write_error != OK: return {"ok": false, "message": "保存失败：写入未完成，原档保留。"}
	if primary.ok:
		var backup_error: Error = DirAccess.copy_absolute(path, path + ".bak")
		if backup_error != OK: return {"ok": false, "message": "保存失败：无法备份，原档保留。"}
	var rename_error: Error = DirAccess.rename_absolute(path + ".tmp", path)
	if rename_error != OK: return {"ok": false, "message": "保存失败：无法替换文件，仍可从备份恢复。"}
	return {"ok": true}
