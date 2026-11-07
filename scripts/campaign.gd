extends RefCounted
## Loads authored chapters and battle configurations; no scene or renderer dependency.

const Story = preload("res://scripts/story_runner.gd")
const BattleModel = preload("res://scripts/battle.gd")
const INDEX_PATH: String = "res://data/campaign.json"
const GATE_VARIANTS: Dictionary = {"joint": "c10_joint_gate", "split": "c10_split_gate", "hold": "c10_hold_gate"}
const DEPOT_VARIANTS: Dictionary = {"joint": "c12_joint_depot", "split": "c12_split_depot", "hold": "c12_hold_depot"}
var index: Dictionary = {}
var story: RefCounted
var completed: Array[Dictionary] = []
var error_message: String = ""

func _init() -> void:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if not value is Dictionary or value.get("version") != 1 or not value.get("chapters") is Array or not value.get("scenarios") is Dictionary:
		error_message = "战役目录无法读取。"
		return
	index = value

func _source(chapter_id: String) -> Dictionary:
	if not error_message.is_empty(): return {"ok": false, "message": error_message}
	for chapter: Dictionary in index.chapters:
		if chapter.id != chapter_id: continue
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(chapter.path))
		var problem: String = Story.validate(source)
		if not problem.is_empty(): return {"ok": false, "message": problem}
		if source.id != chapter_id: return {"ok": false, "message": "章节编号与目录不一致。"}
		for node: Dictionary in source.nodes.values():
			if node.type == "battle":
				var scenario_ids: Array = GATE_VARIANTS.values() if node.scenario == "c10_gate" else (DEPOT_VARIANTS.values() if node.scenario == "c12_depot" else [node.scenario])
				for scenario_id: String in scenario_ids:
					problem = validate_scenario(index.scenarios.get(scenario_id))
					if not problem.is_empty(): return {"ok": false, "message": problem}
		return {"ok": true, "source": source}
	return {"ok": false, "message": "没有找到该章节。"}

static func validate_scenario(value: Variant) -> String:
	if not value is Dictionary: return "关卡配置不存在。"
	for key: String in ["title", "brief", "objective", "map", "hero", "enemy_class", "deck", "enemy_deck", "enemy_name", "enemy_portrait"]:
		if not value.get(key) is String or value[key].is_empty(): return "关卡配置缺少" + key
	if not Story._whole(value.get("seed"), 1, 999999): return "关卡种子无效。"
	var maps: Array = []
	for map: Dictionary in BattleModel.MAPS.maps:
		if map.get("selectable", true) or map.get("campaign_only", false): maps.append(map.id)
	if not maps.has(value.map): return "关卡地图不存在。"
	var heroes: Array = []
	for hero: Dictionary in BattleModel.HEROES.heroes: heroes.append(hero.id)
	if not heroes.has(value.hero) or not heroes.has(value.enemy_class): return "关卡指挥官职业不存在。"
	var decks: Array = []
	for deck: Dictionary in BattleModel.DECKS.decks: decks.append(deck.id)
	if not decks.has(value.deck) or not decks.has(value.enemy_deck): return "关卡预组套牌不存在。"
	var problem: String = BattleModel.ControlObjective.validate_config(value.get("control", {}), BattleModel.MAPS.find(value.map))
	if not problem.is_empty(): return problem
	return ""

func start(chapter_id: String = "chapter_01") -> Dictionary:
	if index.is_empty() or index.chapters.is_empty() or chapter_id != index.chapters[0].id:
		return {"ok": false, "message": "新战役必须从首章开始；后续章节承接已完成的选择。"}
	var loaded: Dictionary = _source(chapter_id)
	if not loaded.ok: return loaded
	if not loaded.source.get("inherits", []).is_empty(): return {"ok": false, "message": "首章不能依赖上一章事实。"}
	story = Story.new(loaded.source)
	completed.clear()
	return {"ok": true}

func next_chapter() -> Dictionary:
	if story == null or story.current().type != "end": return {}
	var next_index: int = completed.size() + 1
	if next_index >= index.chapters.size(): return {}
	return index.chapters[next_index].duplicate(true)

static func _inherit(target: RefCounted, previous: RefCounted, verify: bool) -> String:
	for key: String in target.graph.get("inherits", []):
		if previous == null or not previous.state.flags.has(key) or not Story._same_type(previous.state.flags[key], target.graph.defaults[key]): return "上一章缺少有效的继承事实：" + key
		if verify and target.state.flags[key] != previous.state.flags[key]: return "跨章继承事实与上一章结局不一致：" + key
		if not verify: target.state.flags[key] = previous.state.flags[key]
	return ""

func advance_chapter() -> Dictionary:
	var next: Dictionary = next_chapter()
	if next.is_empty(): return {"ok": false, "message": "当前没有可进入的下一章。"}
	var loaded: Dictionary = _source(next.id)
	if not loaded.ok: return loaded
	var candidate: RefCounted = Story.new(loaded.source)
	var problem: String = _inherit(candidate, story, false)
	if not problem.is_empty(): return {"ok": false, "message": problem}
	# Re-seek from the authored start after facts have been inherited.
	candidate._enter(candidate.graph.start)
	completed.append({"chapter_id": story.graph.id, "story": story.snapshot()})
	story = candidate
	return {"ok": true}

func scenario() -> Dictionary:
	if story == null or story.current().type != "battle": return {}
	var scenario_id: String = story.current().scenario
	if scenario_id == "c10_gate": scenario_id = GATE_VARIANTS.get(str(story.state.flags.get("governance_plan", "")), "")
	if scenario_id == "c12_depot": scenario_id = DEPOT_VARIANTS.get(str(story.state.flags.get("governance_plan", "")), "")
	return index.scenarios.get(scenario_id, {}).duplicate(true)

func snapshot() -> Dictionary:
	if story == null: return {}
	return {"chapter_id": story.graph.id, "story": story.snapshot(), "completed": completed.duplicate(true)}

func restore(payload: Variant) -> Dictionary:
	if not payload is Dictionary or not payload.get("chapter_id") is String: return {"ok": false, "message": "战役存档缺少章节。"}
	var records: Variant = payload.get("completed", [])
	if not records is Array or records.size() >= index.get("chapters", []).size(): return {"ok": false, "message": "已完成章节记录无效。"}
	var restored_records: Array[Dictionary] = []
	var previous: RefCounted = null
	for position: int in range(records.size()):
		var record: Variant = records[position]
		if not record is Dictionary or record.get("chapter_id") != index.chapters[position].id: return {"ok": false, "message": "已完成章节的顺序不正确。"}
		var historical: Dictionary = _source(record.chapter_id)
		if not historical.ok: return historical
		var old_story: RefCounted = Story.new(historical.source)
		for key: String in historical.source.get("inherits", []):
			if not record.get("story") is Dictionary or not record.story.get("flags") is Dictionary or not record.story.flags.has(key): return {"ok": false, "message": "已完成章节缺少继承事实。"}
		var restored: Dictionary = old_story.restore(record.get("story"))
		if not restored.ok: return restored
		if old_story.current().type != "end": return {"ok": false, "message": "前一章尚未完成。"}
		var issue: String = _inherit(old_story, previous, true)
		if not issue.is_empty(): return {"ok": false, "message": issue}
		restored_records.append({"chapter_id": record.chapter_id, "story": old_story.snapshot()})
		previous = old_story
	if payload.chapter_id != index.chapters[records.size()].id: return {"ok": false, "message": "当前章节未承接已完成章节。"}
	var loaded: Dictionary = _source(payload.chapter_id)
	if not loaded.ok: return loaded
	var candidate: RefCounted = Story.new(loaded.source)
	for key: String in loaded.source.get("inherits", []):
		if not payload.get("story") is Dictionary or not payload.story.get("flags") is Dictionary or not payload.story.flags.has(key): return {"ok": false, "message": "当前章节缺少继承事实。"}
	var result: Dictionary = candidate.restore(payload.get("story"))
	if not result.ok: return result
	var problem: String = _inherit(candidate, previous, true)
	if not problem.is_empty(): return {"ok": false, "message": problem}
	story = candidate
	completed = restored_records
	return {"ok": true}

func backlog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in completed:
		var loaded: Dictionary = _source(record.chapter_id)
		if not loaded.ok: continue
		for id: String in record.story.history:
			result.append({"id": id, "text": loaded.source.strings[id], "chapter": loaded.source.title})
		var end: Dictionary = loaded.source.nodes[record.story.node]
		result.append({"id": end.text, "text": loaded.source.strings[end.text], "chapter": loaded.source.title})
	if story != null:
		for id: String in story.state.history:
			result.append({"id": id, "text": story.graph.strings[id], "chapter": story.graph.title})
	return result
