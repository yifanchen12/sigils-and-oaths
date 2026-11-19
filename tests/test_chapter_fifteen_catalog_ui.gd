extends "res://tests/test_chapter_fourteen_catalog_ui.gd"
## Native rendering of every reachable fifteenth story page.

func prepare_fifteen() -> void:
	for plan: String in ["joint", "split", "hold"]:
		for order: String in ["seal", "metered"]:
			for repair: String in ["recast", "sleeve"]:
				var source: String = "res://.tools/v038-test14-%s-%s-%s.json" % [plan, "upstream" if order == "seal" else "tower", order]
				var session: RefCounted = Session.new(source)
				var loaded: bool = session.load_campaign().ok and session.current().type == "end" and session.campaign.story.graph.id == "chapter_14"
				check(loaded, "load completed fourteenth route for catalogue")
				if not loaded: return
				var earlier: RefCounted = Campaign.new()
				var resumed: bool = earlier.restore(session.campaign.snapshot()).ok and earlier.advance_chapter().ok
				check(resumed, "catalogue replays fifteenth from inherited history")
				if not resumed: return
				for step: int in range(160):
					var page: Dictionary = earlier.story.current()
					var id: String = page.get("line_id", "chapter_15." + page.node)
					if not pages.has(id): pages[id] = {"page": page, "scenario": {}}
					match page.type:
						"dialogue": earlier.story.advance(page.revision)
						"choice": earlier.story.choose(repair, page.revision)
						"end": break

func run() -> void:
	create_timer(300).timeout.connect(func() -> void: push_error("fifteenth native UI timeout"); quit(2))
	prepare_fifteen()
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_15.json"))
	var expected: Dictionary = {}
	for node_id: String in graph.nodes:
		var node: Dictionary = graph.nodes[node_id]
		for line: Dictionary in node.get("lines", []): expected[line.id] = true
		if node.type == "end": expected["chapter_15." + node_id] = true
	for id: String in expected: check(pages.has(id), "authored page has native catalogue entry: " + id)
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v039-catalog-deck.json")
	game.campaign_session = Session.new("res://.tools/v039-catalog-save.json")
	root.add_child(game); current_scene = game
	await settle()
	var view: Control = game.story_view
	var empty_history: Array[Dictionary] = []
	var rendered: Dictionary = {}
	for id: String in pages:
		if not id.begins_with("c15.") and not id.begins_with("chapter_15."): continue
		var page: Dictionary = pages[id].page
		view.open(page, {}, {}, empty_history, "第十五章页面检查", false)
		await settle()
		check_layout(view, id)
		if page.type in ["dialogue", "end"]:
			check(view.text_body.text == page.text and view.Art.get_texture(page.background) != null, "fifteenth text and backdrop render: " + id)
			rendered[id] = true
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	for id: String in ["c15.mill_dawn.01", "c15.tower_floor.01", "c15.trial_break.01", "chapter_15.recast_end", "chapter_15.sleeve_end"]:
		var page: Dictionary = pages[id].page
		view.open(page, {}, {}, empty_history, "第十五章页面检查", false)
		await settle()
		check_layout(view, "small " + id)
	view.open(pages["c15.mill_dawn.01"].page, {}, {}, empty_history, "第十五章页面检查", false)
	await settle(); await capture("v039-mill-morning-small")
	view.open(pages["c15.trial_break.01"].page, {}, {}, empty_history, "第十五章页面检查", false)
	await settle(); await capture("v039-tower-valve-small")
	print("FIFTEENTH CATALOGUE UI: %d CHECKS | FAILURES: %d | BODY PAGES: %d" % [checks, failures, rendered.size()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 and rendered.size() == expected.size() else 1)
