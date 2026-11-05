extends RefCounted
## Coordinates the real rules model, story and persistence without a scene tree.

const Campaign = preload("res://scripts/campaign.gd")
const Store = preload("res://scripts/campaign_store.gd")
const BattleModel = preload("res://scripts/battle.gd")
var campaign: RefCounted = Campaign.new()
var store: RefCounted
var epoch: int = 0
var encounter: RefCounted
var encounter_revision: int = -1
var notice: String = ""
var unsaved: bool = false

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
	notice = "新战役已保存。"
	unsaved = false
	return {"ok": true}

func load_campaign() -> Dictionary:
	var loaded: Dictionary = store.load_progress()
	if not loaded.ok: return loaded
	var candidate: RefCounted = Campaign.new()
	var result: Dictionary = candidate.restore(loaded.progress)
	if not result.ok: return result
	campaign = candidate
	epoch += 1
	encounter = null
	encounter_revision = -1
	notice = loaded.get("message", "战役进度已恢复。")
	unsaved = false
	return {"ok": true}

func save() -> Dictionary:
	var result: Dictionary = store.save_progress(campaign.snapshot())
	unsaved = not result.ok
	notice = "剧情已保存；战斗中退出将从战前重新开始。" if result.ok else result.message
	return result

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
	return {"ok": true, "battle": encounter, "scenario": setup}

func finish_battle(completed: RefCounted) -> Dictionary:
	if completed == null or completed != encounter: return {"ok": false, "message": "这场战斗已过期。"}
	if completed.winner not in [0, 1, 2]: return {"ok": false, "message": "战斗尚未结束。"}
	var result: Dictionary = campaign.story.resolve_battle(completed.winner, encounter_revision)
	if not result.ok: return result
	encounter = null
	encounter_revision = -1
	return _after_action(result)

func leave_battle() -> void:
	# Returning to a skirmish keeps the existing pre-battle checkpoint.
	encounter = null
	encounter_revision = -1
	epoch += 1

func backlog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if campaign.story == null: return result
	for id: String in campaign.story.state.history:
		result.append({"id": id, "text": campaign.story.graph.strings[id]})
	return result
