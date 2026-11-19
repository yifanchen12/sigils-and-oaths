extends RefCounted
## Coordinates the real rules model, story and persistence without a scene tree.

const Campaign = preload("res://scripts/campaign.gd")
const Store = preload("res://scripts/campaign_store.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Difficulty = preload("res://scripts/campaign_difficulty.gd")
const AUTOSAVE_INTERVAL: float = 5.0
var campaign: RefCounted = Campaign.new()
var store: RefCounted
var epoch: int = 0
var encounter: RefCounted
var encounter_revision: int = -1
var last_attempt: Dictionary = {}
var notice: String = ""
var unsaved: bool = false
var suspended: bool = false
var autosave_elapsed: float = 0.0

func _init(save_path: String = "user://campaign_autosave.json") -> void:
	store = Store.new(save_path)

func current() -> Dictionary:
	if campaign.story == null: return {"ok": false, "message": "尚未开始战役。"}
	var page: Dictionary = campaign.story.current()
	if page.type == "end": page["next_chapter"] = campaign.next_chapter()
	return page

func token() -> Dictionary:
	return {"session": get_instance_id(), "epoch": epoch, "revision": current().get("revision", -1)}

func _guard(expected: Dictionary) -> Dictionary:
	if expected != token() or campaign.story == null: return {"ok": false, "message": "页面已更新，请按当前页面操作。"}
	if encounter != null: return {"ok": false, "message": "请先完成当前战斗。"}
	return {"ok": true}

func new_campaign() -> Dictionary:
	var candidate: RefCounted = Campaign.new()
	var result: Dictionary = candidate.start()
	if not result.ok: return result
	return _start_saved_campaign(candidate, "新战役已保存。")

static func replay_path(primary_path: String) -> String:
	return primary_path.get_basename() + "_branch.json"

func start_replay_from(primary: RefCounted, chapter_id: String, at_covenant: bool = false) -> Dictionary:
	if ProjectSettings.globalize_path(store.path).simplify_path().nocasecmp_to(ProjectSettings.globalize_path(primary.store.path).simplify_path()) == 0:
		return {"ok": false, "message": "请为重走章节选择独立的分支存档。"}
	var saved: Dictionary = primary.store.load_progress()
	if not saved.ok: return saved
	var original: RefCounted = Campaign.new()
	var opened: Dictionary = original.restore(saved.progress)
	if not opened.ok: return opened
	var checkpoint: Dictionary = original.replay_from(chapter_id, at_covenant)
	if not checkpoint.ok: return checkpoint
	return _start_saved_campaign(checkpoint.campaign, "分支已保存。")

func _start_saved_campaign(candidate: RefCounted, saved_notice: String) -> Dictionary:
	# A failed/newer-version save must not replace the running campaign either.
	var result: Dictionary = store.save_progress(candidate.snapshot())
	if not result.ok: return result
	campaign = candidate
	epoch += 1
	encounter = null
	encounter_revision = -1
	last_attempt = {}
	suspended = false
	autosave_elapsed = 0.0
	notice = saved_notice
	unsaved = false
	return {"ok": true}

func load_campaign() -> Dictionary:
	var loaded: Dictionary = store.load_progress()
	if not loaded.ok: return loaded
	var candidate: RefCounted = Campaign.new()
	var result: Dictionary = candidate.restore(loaded.progress)
	if not result.ok: return result
	var loaded_battle: RefCounted = null
	if not loaded.encounter.is_empty():
		result = Snapshot.restore(loaded.encounter.battle)
		if not result.ok: return result
		loaded_battle = result.battle
	campaign = candidate
	epoch += 1
	encounter = loaded_battle
	last_attempt = loaded.get("last_attempt", {})
	encounter_revision = int(current().revision) if encounter != null else -1
	suspended = false
	autosave_elapsed = 0.0
	notice = loaded.get("message", "旧版存档已兼容载入。" if loaded.get("migrated", false) else "战役进度已恢复。")
	unsaved = false
	if encounter != null and encounter.winner != -1: return finish_battle(encounter)
	return {"ok": true}

func save() -> Dictionary:
	var saved_encounter: Dictionary = {}
	if encounter != null:
		saved_encounter = {"scenario": current().get("scenario", ""), "revision": encounter_revision, "battle": Snapshot.capture(encounter)}
		if campaign.difficulty != Difficulty.STANDARD: saved_encounter["difficulty"] = campaign.difficulty
	var result: Dictionary = store.save_progress(campaign.snapshot(), saved_encounter, last_attempt)
	unsaved = not result.ok
	autosave_elapsed = 0.0
	notice = ("战局已保存，可从当前局面继续。" if encounter != null else "剧情进度已保存。") if result.ok else result.message
	return result

func autosave_tick(delta: float) -> Dictionary:
	if encounter == null or suspended or delta <= 0 or not is_finite(delta): return {"ok": true, "saved": false}
	autosave_elapsed += delta
	if autosave_elapsed < AUTOSAVE_INTERVAL: return {"ok": true, "saved": false}
	var result: Dictionary = save()
	return {"ok": result.ok, "saved": result.ok, "message": notice}

func _after_action(result: Dictionary) -> Dictionary:
	if not result.ok: return result
	var saved: Dictionary = save()
	return {"ok": true, "saved": saved.ok, "message": notice}

func advance(expected: Dictionary) -> Dictionary:
	var result: Dictionary = _guard(expected)
	if not result.ok: return result
	return _after_action(campaign.story.advance(int(expected.revision)))

func choose(option_id: String, expected: Dictionary) -> Dictionary:
	var result: Dictionary = _guard(expected)
	if not result.ok: return result
	return _after_action(campaign.story.choose(option_id, int(expected.revision)))

func choose_requisition(card_id: String, expected: Dictionary) -> Dictionary:
	var result: Dictionary = _guard(expected)
	if not result.ok: return result
	var setup: Dictionary = campaign.scenario()
	if not setup.has("requisition") or not Campaign.Requisition.allows(setup, card_id):
		return {"ok": false, "message": "当前关卡没有这项军需。"}
	var previous: String = campaign.requisition
	if card_id == previous: return {"ok": true}
	if not campaign.armory.is_empty():
		var prepared: Dictionary = Campaign.Armory.prepare(setup, card_id, campaign.armory)
		if not prepared.ok: return prepared
	campaign.requisition = card_id
	result = save()
	if not result.ok:
		campaign.requisition = previous
		return result
	epoch += 1
	return result

func choose_difficulty(mode: String, expected: Dictionary) -> Dictionary:
	var result: Dictionary = _guard(expected)
	if not result.ok: return result
	if current().type != "battle" or not Difficulty.is_valid(mode):
		return {"ok": false, "message": "请在出征简报中选择标准或剧情难度。"}
	if mode == campaign.difficulty: return {"ok": true}
	var progress: Dictionary = campaign.snapshot()
	if mode == Difficulty.STANDARD: progress.erase("difficulty")
	else: progress["difficulty"] = mode
	result = store.save_progress(progress, {}, last_attempt)
	if not result.ok: return result
	campaign.difficulty = mode
	epoch += 1
	unsaved = false
	autosave_elapsed = 0.0
	notice = "已保存剧情难度。" if mode == Difficulty.STORY else "已保存标准难度。"
	return result

func configure_armory(picks: Dictionary, expected: Dictionary) -> Dictionary:
	var result: Dictionary = _guard(expected)
	if not result.ok: return result
	if current().type != "battle": return {"ok": false, "message": "请在出征前编成军备。"}
	var issue: String = Campaign.Armory.validate(picks, campaign.completed.size())
	if not issue.is_empty(): return {"ok": false, "message": issue}
	if picks == campaign.armory: return {"ok": true}
	var prepared: Dictionary = Campaign.Armory.prepare(campaign.scenario(), campaign.requisition, picks)
	if not prepared.ok: return prepared
	var progress: Dictionary = campaign.snapshot()
	if picks.is_empty(): progress.erase("armory")
	else: progress["armory"] = picks.duplicate()
	result = store.save_progress(progress, {}, last_attempt)
	if not result.ok: return result
	campaign.armory = picks.duplicate()
	epoch += 1
	notice = "军备已保存，之后的战斗会按这份编成准备牌库。"
	unsaved = false
	autosave_elapsed = 0.0
	return result

func retreat(expected: Dictionary) -> Dictionary:
	var result: Dictionary = _guard(expected)
	if not result.ok: return result
	result = campaign.story.retreat(int(expected.revision))
	if result.ok:
		campaign.requisition = ""
		last_attempt = {}
	return _after_action(result)

func next_chapter(expected: Dictionary) -> Dictionary:
	var result: Dictionary = _guard(expected)
	if not result.ok: return result
	var candidate: RefCounted = Campaign.new()
	result = candidate.restore(campaign.snapshot())
	if not result.ok: return result
	result = candidate.advance_chapter()
	if not result.ok: return result
	result = store.save_progress(candidate.snapshot())
	if not result.ok:
		unsaved = true
		notice = result.message
		return result
	campaign = candidate
	epoch += 1
	unsaved = false
	notice = "上一章的选择已保留，新章起点已保存。"
	for slot: Dictionary in Campaign.Armory.SLOTS:
		if campaign.completed.size() == int(slot.unlock_after):
			notice = "已开放「%s」。可在出征简报底部打开战役军备。" % slot.name
			break
	return {"ok": true}

func begin_battle(expected: Dictionary) -> Dictionary:
	var result: Dictionary = _guard(expected)
	if not result.ok: return result
	if current().type != "battle": return {"ok": false, "message": "当前没有待出征的战斗。"}
	result = save()
	if not result.ok: return result
	var setup: Dictionary = campaign.scenario()
	result = create_encounter(setup, campaign.requisition, campaign.armory, campaign.difficulty)
	if not result.ok: return result
	encounter = result.battle
	encounter_revision = int(current().revision)
	suspended = false
	var prior: Dictionary = last_attempt
	last_attempt = {}
	result = save()
	if not result.ok:
		encounter = null
		encounter_revision = -1
		last_attempt = prior
		return result
	return {"ok": true, "battle": encounter, "scenario": setup}

func inspect_field(expected: Dictionary, previous: bool) -> Dictionary:
	var access: Dictionary = _guard(expected)
	if not access.ok: return access
	if current().type != "battle": return {"ok": false, "message": "当前没有可查看的作战简报。"}
	var setup: Dictionary = campaign.scenario()
	var mode: String = campaign.difficulty
	var field: Dictionary
	if previous:
		if last_attempt.is_empty(): return {"ok": false, "message": "这场战斗还没有留下终局棋盘。"}
		field = Snapshot.restore(last_attempt.battle)
		mode = last_attempt.get("difficulty", Difficulty.STANDARD)
	else:
		field = create_encounter(setup, campaign.requisition, campaign.armory, mode)
	if field.ok:
		field["difficulty"] = mode
		field["scenario"] = setup
	return field

static func create_encounter(setup: Dictionary, requisition: String = "", armory: Dictionary = {}, mode: String = Difficulty.STANDARD) -> Dictionary:
	if not Difficulty.is_valid(mode): return {"ok": false, "message": "战役难度无效。"}
	var result: Dictionary = Campaign.Armory.prepare(setup, requisition, armory)
	if not result.ok: return result
	var battle: Battle = result.battle
	battle.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
	if setup.has("commander_shield"): battle.commander(0).shield = int(setup.commander_shield)
	if setup.has("bonus_card") and not battle.add_generated_card(0, str(setup.bonus_card)):
		return {"ok": false, "message": "关卡增援牌无法加入手牌。"}
	if mode == Difficulty.STORY: Difficulty.support(battle)
	result = battle.configure_objective(Difficulty.control_for(setup, mode))
	return {"ok": true, "battle": battle} if result.ok else result

func finish_battle(completed: RefCounted) -> Dictionary:
	if suspended or completed == null or completed != encounter: return {"ok": false, "message": "这场战斗已过期或暂挂。"}
	if completed.winner not in [0, 1, 2]: return {"ok": false, "message": "战斗尚未结束。"}
	var result: Dictionary = campaign.story.resolve_battle(completed.winner, encounter_revision)
	if not result.ok: return result
	last_attempt = {}
	if completed.winner == 0:
		campaign.requisition = ""
	else:
		var page: Dictionary = current()
		last_attempt = {"scenario":page.scenario, "attempt":page.attempts, "revision":encounter_revision, "battle":Snapshot.capture(completed)}
		if campaign.difficulty != Difficulty.STANDARD: last_attempt["difficulty"] = campaign.difficulty
		if not campaign.requisition.is_empty(): last_attempt["requisition"] = campaign.requisition
		if not campaign.armory.is_empty(): last_attempt["armory"] = campaign.armory.duplicate()
	encounter = null
	encounter_revision = -1
	return _after_action(result)

func leave_battle() -> Dictionary:
	if campaign.story != null:
		var result: Dictionary = save()
		if not result.ok: return result
	suspended = true
	epoch += 1
	return {"ok": true}

func resume_encounter() -> Dictionary:
	if encounter == null: return {"ok": false, "message": "没有进行中的战斗。"}
	suspended = false
	epoch += 1
	return {"ok": true, "battle": encounter, "scenario": campaign.scenario()}

func backlog() -> Array[Dictionary]:
	return campaign.backlog()
