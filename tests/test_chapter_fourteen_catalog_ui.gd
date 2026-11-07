extends "res://tests/test_chapter_thirteen_catalog_ui.gd"
## All authored fourteenth pages render from earned prior history.

func prepare_fourteen() -> void:
	for plan: String in ["joint", "split", "hold"]:
		for watch: String in ["upstream", "tower"]:
			for order: String in ["seal", "metered"]:
				var session: RefCounted = Session.new("res://.tools/v037-test13-%s-%s.json" % [plan, watch])
				var loaded: bool = session.load_campaign().ok and session.current().type == "end"
				check(loaded, "load earned thirteenth ending for catalogue")
				if not loaded: return
				var campaign: RefCounted = Campaign.new()
				var advanced: bool = campaign.restore(session.campaign.snapshot()).ok and campaign.advance_chapter().ok
				check(advanced, "catalogue enters fourteenth from earned history")
				if not advanced: return
				for step: int in range(150):
					var page: Dictionary = campaign.story.current()
					var id: String = page.get("line_id", "chapter_14." + page.node)
					if not pages.has(id): pages[id] = {"page": page, "scenario": campaign.scenario()}
					match page.type:
						"dialogue": campaign.story.advance(page.revision)
						"choice": campaign.story.choose(order, page.revision)
						"battle": campaign.story.resolve_battle(0, page.revision)
						"end": break

func run() -> void:
	create_timer(300).timeout.connect(func() -> void: push_error("fourteenth catalogue UI timeout"); quit(2))
	prepare_fourteen()
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_14.json"))
	var expected: Dictionary = {}
	for node_id: String in graph.nodes:
		var node: Dictionary = graph.nodes[node_id]
		for line: Dictionary in node.get("lines", []): expected[line.id] = true
		if node.type == "end": expected["chapter_14." + node_id] = true
	for id: String in expected: check(pages.has(id), "authored paragraph has native page: " + id)
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v038-catalog-deck.json")
	game.campaign_session = Session.new("res://.tools/v038-catalog-save.json")
	root.add_child(game); current_scene = game
	await settle()
	var view: Control = game.story_view
	var empty_history: Array[Dictionary] = []
	var rendered: Dictionary = {}
	for id: String in pages:
		if not id.begins_with("c14.") and not id.begins_with("chapter_14."): continue
		var page: Dictionary = pages[id].page
		view.open(page, {}, pages[id].scenario, empty_history, "第十四章页面检查", false)
		await settle()
		check_layout(view, id)
		if page.type in ["dialogue", "end"]:
			check(view.text_body.text == page.text and view.Art.get_texture(page.background) != null, "text and original scene render: " + id)
			rendered[id] = true
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	for id: String in ["c14.before_dawn.01", "c14.gate_brief.01", "c14.after_battle.01", "chapter_14.seal_end", "chapter_14.metered_end"]:
		var page: Dictionary = pages[id].page
		view.open(page, {}, pages[id].scenario, empty_history, "第十四章页面检查", false)
		await settle()
		check_layout(view, "small " + id)
	view.open(pages["c14.gate_brief.01"].page, {}, pages["c14.gate_brief.01"].scenario, empty_history, "第十四章页面检查", false)
	await settle(); await capture("v038-channel-brief-small")
	print("FOURTEENTH CATALOGUE UI: %d CHECKS | FAILURES: %d | BODY PAGES: %d" % [checks, failures, rendered.size()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 and rendered.size() == expected.size() else 1)
