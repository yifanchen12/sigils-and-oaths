extends "res://tests/test_chapter_twelve_catalog_ui.gd"
## Native StoryView coverage from saves earned by actual chapter-twelve battles.

func prepare_thirteen() -> void:
	for plan: String in ["joint", "split", "hold"]:
		for watch: String in ["upstream", "tower"]:
			var session: RefCounted = Session.new("res://.tools/v036-earned-chapter12-%s.json" % plan)
			var loaded: bool = session.load_campaign().ok and session.current().type == "end"
			check(loaded, "load earned depot result for catalogue: " + plan)
			if not loaded: return
			var campaign: RefCounted = Campaign.new()
			var advanced: bool = campaign.restore(session.campaign.snapshot()).ok and campaign.advance_chapter().ok
			check(advanced, "enter chapter thirteen from earned result")
			if not advanced: return
			for step: int in range(150):
				var page: Dictionary = campaign.story.current()
				var id: String = page.get("line_id", "chapter_13." + page.node)
				if not pages.has(id): pages[id] = {"page": page, "scenario": campaign.scenario()}
				match page.type:
					"dialogue": campaign.story.advance(page.revision)
					"choice": campaign.story.choose(watch, page.revision)
					"end": break

func run() -> void:
	create_timer(300).timeout.connect(func() -> void: push_error("thirteenth catalogue UI timeout"); quit(2))
	prepare_thirteen()
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_13.json"))
	var expected: Dictionary = {}
	for node: Dictionary in graph.nodes.values():
		for line: Dictionary in node.get("lines", []): expected[line.id] = true
		if node.type == "end": expected["chapter_13." + node.ending.replace("pressure_wait_", "end_")] = true
	for id: String in expected: check(pages.has(id), "thirteenth conditional paragraph has native page: " + id)
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v037-catalog-deck.json")
	game.campaign_session = Session.new("res://.tools/v037-catalog-save.json")
	root.add_child(game); current_scene = game
	await settle()
	var view: Control = game.story_view
	var empty_history: Array[Dictionary] = []
	var rendered: Dictionary = {}
	for id: String in pages:
		if not id.begins_with("c13.") and not id.begins_with("chapter_13."): continue
		var page: Dictionary = pages[id].page
		view.open(page, {}, pages[id].scenario, empty_history, "第十三章页面检查", false)
		await settle()
		check_layout(view, id)
		if page.type in ["dialogue", "end"]:
			check(view.text_body.text == page.text and view.Art.get_texture(page.background) != null, "thirteenth text and art render: " + id)
			rendered[id] = true
	check(rendered.size() == 97, "all 95 paragraphs and two endings render in native UI")
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	for id: String in ["c13.mill_dawn.01", "c13.forge_floor.01", "chapter_13.end_tower"]:
		var page: Dictionary = pages[id].page
		view.open(page, {}, pages[id].scenario, empty_history, "第十三章页面检查", false)
		await settle()
		check_layout(view, "small " + id)
	var mill: Dictionary = pages["c13.mill_dawn.01"].page
	view.open(mill, {}, pages["c13.mill_dawn.01"].scenario, empty_history, "第十三章页面检查", false)
	await settle()
	await capture("v037-northbank-mill-small")
	print("THIRTEENTH CATALOGUE UI: %d CHECKS | FAILURES: %d | PARAGRAPHS: %d" % [checks, failures, rendered.size()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
