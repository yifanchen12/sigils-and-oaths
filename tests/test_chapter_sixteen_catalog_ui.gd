extends "res://tests/test_chapter_fifteen_catalog_ui.gd"
## Render every authored sixteenth-chapter page at normal and small windows.
const Story16 = preload("res://scripts/story_runner.gd")

func run() -> void:
	create_timer(300).timeout.connect(func() -> void: push_error("sixteenth native UI timeout"); quit(2))
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_16.json"))
	var scenario: Dictionary = Campaign.new().index.scenarios.c16_bridge
	for repair: String in ["recast", "sleeve"]:
		for terms: String in ["sale", "lease"]:
			for decision: String in ["hearing", "service"]:
				var story: RefCounted = Story16.new(graph)
				story.state.flags.repair_plan = repair
				story.state.flags.foundry_terms = terms
				for step: int in range(100):
					var page: Dictionary = story.current()
					var id: String = page.get("line_id", "chapter_16." + page.node)
					if not pages.has(id): pages[id] = {"page": page, "scenario": scenario}
					match page.type:
						"dialogue": story.advance(page.revision)
						"choice": story.choose(decision, page.revision)
						"battle": story.resolve_battle(0, page.revision)
						"end": break
	var expected: Dictionary = {}
	for node_id: String in graph.nodes:
		var node: Dictionary = graph.nodes[node_id]
		for line: Dictionary in node.get("lines", []): expected[line.id] = true
		if node.type == "end": expected["chapter_16." + node_id] = true
	for id: String in expected: check(pages.has(id), "authored page has catalogue entry: " + id)
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v040-catalog-deck.json")
	game.campaign_session = Session.new("res://.tools/v040-catalog-save.json")
	root.add_child(game); current_scene = game
	await settle()
	var view: Control = game.story_view
	var history: Array[Dictionary] = []
	var rendered: Dictionary = {}
	for id: String in pages:
		if not id.begins_with("c16.") and not id.begins_with("chapter_16."): continue
		var page: Dictionary = pages[id].page
		view.open(page, {}, scenario, history, "第十六章页面检查", false)
		await settle()
		check_layout(view, id)
		if page.type in ["dialogue", "end"]:
			check(view.text_body.text == page.text and view.Art.get_texture(page.background) != null, "text and backdrop render: " + id)
			rendered[id] = true
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	for id: String in ["c16.queue.01", "c16.claim.01", "c16.after.01", "chapter_16.hearing_end", "chapter_16.service_end"]:
		view.open(pages[id].page, {}, scenario, history, "第十六章页面检查", false)
		await settle()
		check_layout(view, "small " + id)
	view.open(pages["c16.queue.01"].page, {}, scenario, history, "第十六章页面检查", false)
	await settle(); await capture("v040-bridge-queue-small")
	print("SIXTEENTH CATALOGUE UI: %d CHECKS | FAILURES: %d | BODY PAGES: %d" % [checks, failures, rendered.size()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 and rendered.size() == expected.size() else 1)
