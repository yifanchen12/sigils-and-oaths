extends RefCounted
## Coordinates the real rules model, story and persistence without a scene tree.

const Campaign = preload("res://scripts/campaign.gd")
const Store = preload("res://scripts/campaign_store.gd")
const BattleModel = preload("res://scripts/battle.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const AUTOSAVE_INTERVAL: float = 5.0
var campaign: RefCounted = Campaign.new()
var store: RefCounted
var epoch: int = 0
var encounter: RefCounted
var encounter_revision: int = -1
var notice: String = ""
var unsaved: bool = false
var suspended: bool = false
var autosave_elapsed: float = 0.0

func _init(save_path: String = "user://campaign_autosave.json") -> void:
	store = Store.new(save_path)

func current() -> Dictionary:
	return campaign.story.current() if campaign.story != null else {"ok": false, "message": "尚未开始战役。"}

func token() -> Dictionary:
	return {"epoch": epoch, "revision": current().get("revision", -1)}

func _guard(expected: Dictionary) -> Dictionary:
	if expected != token() or campaign.story == null: return {"ok": false, "message": "页面已更新，请按当前页面操作。"}
	if encounter != null: return {"ok": false, "message": "请先完成当前战斗。"}
	return {"ok": true}

func new_campaign() -> Dictionary:
	var candidate: RefCounted = Campaign.new()
	var result: Dictionary = candidate.start()
	if not result.ok: return result
	# A failed/newer-version save must not replace the running campaign either.
	result = store.save_progress(candidate.snapshot())
	if not result.ok: return result
	campaign = candidate
	epoch += 1
	encounter = null
	encounter_revision = -1
	suspended = false
	autosave_elapsed = 0.0
	notice = "新战役已保存。"
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
	encounter_revision = int(current().revision) if encounter != null else -1
	suspended = false
	autosave_elapsed = 0.0
	notice = loaded.get("message", "旧版剧情存档已兼容载入；本关将从战前开始。" if loaded.get("migrated", false) else "战役进度已恢复。")
	unsaved = false
	if encounter != null and encounter.winner != -1: return finish_battle(encounter)
	return {"ok": true}

func save() -> Dictionary:
	var saved_encounter: Dictionary = {}
	if encounter != null: saved_encounter = {"scenario": current().get("scenario", ""), "revision": encounter_revision, "battle": Snapshot.capture(encounter)}
	var result: Dictionary = store.save_progress(campaign.snapshot(), saved_encounter)
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

func begin_battle(expected: Dictionary) -> Dictionary:
	var result: Dictionary = _guard(expected)
	if not result.ok: return result
	if current().type != "battle": return {"ok": false, "message": "当前没有待出征的战斗。"}
	result = save()
	if not result.ok: return result
	var setup: Dictionary = campaign.scenario()
	encounter = BattleModel.new(int(setup.seed), setup.map, setup.hero, setup.enemy_class, setup.deck, setup.enemy_deck, 90)
	encounter.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
	encounter_revision = int(current().revision)
	suspended = false
	result = save()
	if not result.ok:
		encounter = null
		encounter_revision = -1
		return result
	return {"ok": true, "battle": encounter, "scenario": setup}

func finish_battle(completed: RefCounted) -> Dictionary:
	if suspended or completed == null or completed != encounter: return {"ok": false, "message": "这场战斗已过期或暂挂。"}
	if completed.winner not in [0, 1, 2]: return {"ok": false, "message": "战斗尚未结束。"}
	var result: Dictionary = campaign.story.resolve_battle(completed.winner, encounter_revision)
	if not result.ok: return result
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
	var result: Array[Dictionary] = []
	if campaign.story == null: return result
	for id: String in campaign.story.state.history:
		result.append({"id": id, "text": campaign.story.graph.strings[id]})
	return result
