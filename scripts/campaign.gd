extends RefCounted
## Loads authored chapters and battle configurations; no scene or renderer dependency.

const Story = preload("res://scripts/story_runner.gd")
const BattleModel = preload("res://scripts/battle.gd")
const Requisition = preload("res://scripts/campaign_requisition.gd")
const Armory = preload("res://scripts/campaign_armory.gd")
const Difficulty = preload("res://scripts/campaign_difficulty.gd")
const INDEX_PATH: String = "res://data/campaign.json"
const GATE_VARIANTS: Dictionary = {"joint": "c10_joint_gate", "split": "c10_split_gate", "hold": "c10_hold_gate"}
const DEPOT_VARIANTS: Dictionary = {"joint": "c12_joint_depot", "split": "c12_split_depot", "hold": "c12_hold_depot"}
const CHANNEL_VARIANTS: Dictionary = {"upstream": "c14_upstream_channel", "tower": "c14_tower_channel"}
var index: Dictionary = {}
var story: RefCounted
var completed: Array[Dictionary] = []
var requisition: String = ""
var armory: Dictionary = {}
var difficulty: String = Difficulty.STANDARD
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
				var scenario_ids: Array = GATE_VARIANTS.values() if node.scenario == "c10_gate" else (DEPOT_VARIANTS.values() if node.scenario == "c12_depot" else (CHANNEL_VARIANTS.values() if node.scenario == "c14_channel" else [node.scenario]))
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
	if value.has("bonus_card") and BattleModel.CATALOG.find(str(value.bonus_card)).is_empty(): return "关卡增援牌不存在。"
	if value.has("commander_shield") and not Story._whole(value.commander_shield, 1, 5): return "开场指挥官护盾无效。"
	var map: Dictionary = BattleModel.MAPS.find(value.map)
	var problem: String = BattleModel.ControlObjective.validate_config(value.get("control", {}), map)
	if not problem.is_empty(): return problem
	if value.has("story_control"):
		problem = BattleModel.ControlObjective.validate_config(value.story_control, map)
		if not problem.is_empty(): return problem
		if value.story_control.is_empty(): return "剧情难度需要有效的关卡目标。"
	if value.has("story_brief") and (not value.story_brief is String or value.story_brief.is_empty()):
		return "剧情难度简报无效。"
	return Requisition.validate_setup(value)

func start(chapter_id: String = "chapter_01") -> Dictionary:
	if index.is_empty() or index.chapters.is_empty() or chapter_id != index.chapters[0].id:
		return {"ok": false, "message": "新战役必须从首章开始；后续章节承接已完成的选择。"}
	var loaded: Dictionary = _source(chapter_id)
	if not loaded.ok: return loaded
	if not loaded.source.get("inherits", []).is_empty() or not loaded.source.get("optional_inherits", []).is_empty(): return {"ok": false, "message": "首章不能依赖上一章事实。"}
	story = Story.new(loaded.source)
	completed.clear()
	requisition = ""
	armory.clear()
	difficulty = Difficulty.STANDARD
	return {"ok": true}

func next_chapter() -> Dictionary:
	if story == null or story.current().type != "end": return {}
	var next_index: int = completed.size() + 1
	if next_index >= index.chapters.size(): return {}
	return index.chapters[next_index].duplicate(true)

static func _inherit(target: RefCounted, previous: RefCounted, verify: bool) -> String:
	var optional: Array = target.graph.get("optional_inherits", [])
	for key: String in target.graph.get("inherits", []) + optional:
		if previous == null: return "继承事实缺少上一章：" + key
		if not previous.state.flags.has(key) and key not in optional: return "上一章缺少有效的继承事实：" + key
		var fact: Variant = previous.state.flags.get(key, target.graph.defaults[key])
		if not Story._same_type(fact, target.graph.defaults[key]): return "上一章缺少有效的继承事实：" + key
		if verify and target.state.flags[key] != fact: return "跨章继承事实与上一章结局不一致：" + key
		if not verify: target.state.flags[key] = fact
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
	var record: Dictionary = {"chapter_id": story.graph.id, "story": story.snapshot()}
	if not armory.is_empty(): record["armory"] = armory.duplicate()
	if difficulty != Difficulty.STANDARD: record["difficulty"] = difficulty
	completed.append(record)
	story = candidate
	requisition = ""
	return {"ok": true}

func completed_chapter_count() -> int:
	return completed.size() + int(story != null and story.current().type == "end")

func replay_chapters() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var unlocked: int = completed_chapter_count()
	for position: int in range(index.get("chapters", []).size()):
		var chapter: Dictionary = index.chapters[position]
		entries.append({"id": chapter.id, "title": chapter.title, "number": position + 1, "unlocked": position < unlocked})
	return entries

func replay_from(chapter_id: String) -> Dictionary:
	var target: int = -1
	for position: int in range(completed_chapter_count()):
		if index.chapters[position].id == chapter_id:
			target = position
			break
	if target < 0: return {"ok": false, "message": "主线完成这一章后，即可从这里重走。"}
	var copy: RefCounted = get_script().new()
	if target == 0:
		var opened: Dictionary = copy.start()
		return {"ok": true, "campaign": copy} if opened.ok else opened
	var previous: Dictionary = completed[target - 1]
	var progress: Dictionary = {"chapter_id": previous.chapter_id, "story": previous.story, "completed": completed.slice(0, target - 1)}
	if previous.has("armory"): progress["armory"] = previous.armory
	if previous.has("difficulty"): progress["difficulty"] = previous.difficulty
	var restored: Dictionary = copy.restore(progress)
	if not restored.ok: return restored
	restored = copy.advance_chapter()
	return {"ok": true, "campaign": copy} if restored.ok else restored

func scenario() -> Dictionary:
	return _scenario_at(story)

func _scenario_at(cursor: RefCounted) -> Dictionary:
	if cursor == null or cursor.current().type != "battle": return {}
	var scenario_id: String = cursor.current().scenario
	if scenario_id == "c10_gate": scenario_id = GATE_VARIANTS.get(str(cursor.state.flags.get("governance_plan", "")), "")
	if scenario_id == "c12_depot": scenario_id = DEPOT_VARIANTS.get(str(cursor.state.flags.get("governance_plan", "")), "")
	if scenario_id == "c14_channel": scenario_id = CHANNEL_VARIANTS.get(str(cursor.state.flags.get("night_watch", "")), "")
	var setup: Dictionary = index.scenarios.get(scenario_id, {}).duplicate(true)
	if scenario_id in ["c08_isolate", "c08_buffer"]:
		var aid_text: String = ""
		match String(cursor.state.flags.get("saltlane_result", "none")):
			"school":
				setup["bonus_card"] = "lantern_stretcher"
				aid_text = "\n\n学堂援助 · 初始手牌加入「红灯担架」。"
			"kiln":
				setup["commander_shield"] = 3
				aid_text = "\n\n窑场援助 · 己方指挥官开场获得 3 护盾。"
		setup.brief += aid_text
		if setup.has("story_brief"): setup.story_brief += aid_text
	return setup

func snapshot() -> Dictionary:
	if story == null: return {}
	var progress: Dictionary = {"chapter_id": story.graph.id, "story": story.snapshot(), "completed": completed.duplicate(true)}
	if not requisition.is_empty(): progress["requisition"] = requisition
	if not armory.is_empty(): progress["armory"] = armory.duplicate()
	if difficulty != Difficulty.STANDARD: progress["difficulty"] = difficulty
	return progress

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
		var previous_armory: Variant = record.get("armory", {})
		issue = Armory.validate(previous_armory, position)
		if not issue.is_empty(): return {"ok": false, "message": issue}
		var previous_difficulty: Variant = record.get("difficulty", Difficulty.STANDARD)
		if not Difficulty.is_valid(previous_difficulty): return {"ok": false, "message": "已完成章节的难度无效。"}
		var restored_record: Dictionary = {"chapter_id": record.chapter_id, "story": old_story.snapshot()}
		if not previous_armory.is_empty(): restored_record["armory"] = previous_armory.duplicate()
		if previous_difficulty != Difficulty.STANDARD: restored_record["difficulty"] = previous_difficulty
		restored_records.append(restored_record)
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
	var choice: Variant = payload.get("requisition", "")
	if not choice is String or not Requisition.allows(_scenario_at(candidate), choice):
		return {"ok": false, "message": "保存的战前军需与当前关卡不一致。"}
	var picked_armory: Variant = payload.get("armory", {})
	problem = Armory.validate(picked_armory, records.size())
	if not problem.is_empty(): return {"ok": false, "message": problem}
	var selected_difficulty: Variant = payload.get("difficulty", Difficulty.STANDARD)
	if not Difficulty.is_valid(selected_difficulty): return {"ok": false, "message": "保存的战役难度无效。"}
	story = candidate
	completed = restored_records
	requisition = choice
	armory = picked_armory.duplicate()
	difficulty = selected_difficulty
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
		var current: Dictionary = story.graph.nodes[story.state.node]
		if current.type == "end":
			result.append({"id": current.text, "text": story.graph.strings[current.text], "chapter": story.graph.title})
	return result
