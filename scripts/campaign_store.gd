extends RefCounted
## Versioned plain JSON with last-good backup. Player saves never load script objects.

const Campaign = preload("res://scripts/campaign.gd")
const Story = preload("res://scripts/story_runner.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const VERSION: int = 3
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
	var validated: Dictionary = _validate(data.get("progress"), {} if int(data.version) == 1 else data.get("encounter"))
	if validated.ok and int(data.version) < VERSION: validated["migrated"] = true
	return validated

func _validate(progress: Variant, encounter: Variant) -> Dictionary:
	var campaign: RefCounted = Campaign.new()
	var restored: Dictionary = campaign.restore(progress)
	if not restored.ok: return restored
	if not encounter is Dictionary: return {"ok": false, "message": "战役存档缺少战斗资料。"}
	var saved_encounter: Dictionary = {}
	if not encounter.is_empty():
		var page: Dictionary = campaign.story.current()
		if page.type != "battle" or encounter.get("scenario") != page.scenario or not Story._whole(encounter.get("revision")) or encounter.revision != page.revision:
			return {"ok": false, "message": "战斗与当前剧情进度不一致。"}
		restored = Snapshot.restore(encounter.get("battle"))
		if not restored.ok: return restored
		var battle: RefCounted = restored.battle
		var setup: Dictionary = campaign.scenario()
		if battle.ControlObjective.config(battle.objective) != battle.ControlObjective.config(setup.get("control", {})):
			return {"ok": false, "message": "战斗目标与关卡不一致。"}
		if battle.map_definition.id != setup.map or battle.match_seed != int(setup.seed) or battle.turn_time_limit != 90:
			return {"ok": false, "message": "战斗地图、种子或时限与关卡不一致。"}
		if battle.players[0].hero_id != setup.hero or battle.players[1].hero_id != setup.enemy_class or battle.deck(0).id != setup.deck or battle.deck(1).id != setup.enemy_deck:
			return {"ok": false, "message": "战斗军势与关卡不一致。"}
		if battle.players[0].has("hero_display") or battle.hero(1).name != setup.enemy_name or battle.hero(1).portrait != setup.enemy_portrait:
			return {"ok": false, "message": "战斗指挥官身份与关卡不一致。"}
		saved_encounter = {"scenario": page.scenario, "revision": page.revision, "battle": Snapshot.capture(battle)}
	return {"ok": true, "progress": campaign.snapshot(), "encounter": saved_encounter}

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

func save_progress(progress: Variant, encounter: Dictionary = {}) -> Dictionary:
	var validated: Dictionary = _validate(progress, encounter)
	if not validated.ok: return validated
	var primary: Dictionary = _read_path(path)
	var backup: Dictionary = _read_path(path + ".bak")
	if _protected(primary): return primary
	if _protected(backup): return backup
	var encoded: String = JSON.stringify({"version": VERSION, "progress": validated.progress, "encounter": validated.encounter}, "\t", true, true)
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
