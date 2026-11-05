extends RefCounted
## Loads authored chapters and battle configurations; no scene or renderer dependency.

const Story = preload("res://scripts/story_runner.gd")
const BattleModel = preload("res://scripts/battle.gd")
const INDEX_PATH: String = "res://data/campaign.json"
var index: Dictionary = {}
var story: RefCounted
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
				problem = validate_scenario(index.scenarios.get(node.scenario))
				if not problem.is_empty(): return {"ok": false, "message": problem}
		return {"ok": true, "source": source}
	return {"ok": false, "message": "没有找到该章节。"}

static func validate_scenario(value: Variant) -> String:
	if not value is Dictionary: return "关卡配置不存在。"
	for key: String in ["title", "brief", "objective", "map", "hero", "enemy_class", "deck", "enemy_deck", "enemy_name", "enemy_portrait"]:
		if not value.get(key) is String or value[key].is_empty(): return "关卡配置缺少" + key
	if not Story._whole(value.get("seed"), 1, 999999): return "关卡种子无效。"
	var maps: Array = []
	for map: Dictionary in BattleModel.MAPS.available(): maps.append(map.id)
	if not maps.has(value.map): return "关卡地图不存在。"
	var heroes: Array = []
	for hero: Dictionary in BattleModel.HEROES.heroes: heroes.append(hero.id)
	if not heroes.has(value.hero) or not heroes.has(value.enemy_class): return "关卡指挥官职业不存在。"
	var decks: Array = []
	for deck: Dictionary in BattleModel.DECKS.decks: decks.append(deck.id)
	if not decks.has(value.deck) or not decks.has(value.enemy_deck): return "关卡预组套牌不存在。"
	return ""

func start(chapter_id: String = "chapter_01") -> Dictionary:
	var loaded: Dictionary = _source(chapter_id)
	if not loaded.ok: return loaded
	story = Story.new(loaded.source)
	return {"ok": true}

func scenario() -> Dictionary:
	if story == null or story.current().type != "battle": return {}
	return index.scenarios[story.current().scenario].duplicate(true)

func snapshot() -> Dictionary:
	if story == null: return {}
	return {"chapter_id": story.graph.id, "story": story.snapshot()}

func restore(payload: Variant) -> Dictionary:
	if not payload is Dictionary or not payload.get("chapter_id") is String: return {"ok": false, "message": "战役存档缺少章节。"}
	var loaded: Dictionary = _source(payload.chapter_id)
	if not loaded.ok: return loaded
	var candidate: RefCounted = Story.new(loaded.source)
	var result: Dictionary = candidate.restore(payload.get("story"))
	if not result.ok: return result
	story = candidate
	return {"ok": true}
