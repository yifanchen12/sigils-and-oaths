extends "res://tests/test_campaign_ui.gd"
## Render every ninth-chapter source page in the real StoryView at two window sizes.
## Earlier battles are resolved as fixtures by the inherited page catalogue.

func run() -> void:
	create_timer(240).timeout.connect(func() -> void: push_error("ninth catalogue UI timeout"); quit(2))
	var catalog: RefCounted = Campaign.new()
	catalog.start()
	prepare_page_catalog(catalog)
	collect(catalog, true)
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_09.json"))
	var expected: Dictionary = {}
	for node: Dictionary in graph.nodes.values():
		for line: Dictionary in node.get("lines", []): expected[line.id] = true
		if node.type == "end": expected["chapter_09.end"] = true
	for id: String in expected: check(pages.has(id), "conditional ninth paragraph has a catalogue page: " + id)
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v033-catalog-deck.json")
	game.campaign_session = Session.new("res://.tools/v033-catalog-save.json")
	root.add_child(game)
	current_scene = game
	await settle()
	var view: Control = game.story_view
	var rendered: Dictionary = {}
	var empty_history: Array[Dictionary] = []
	for id: String in pages:
		if not id.begins_with("c09.") and not id.begins_with("chapter_09."): continue
		var page: Dictionary = pages[id].page
		view.open(page, {}, pages[id].scenario, empty_history, "第九章页面检查", false)
		await settle()
		check_layout(view, id)
		if page.type in ["dialogue", "end"]:
			check(view.text_body.text == page.text and view.Art.get_texture(page.background) != null, "ninth source text and scene render: " + id)
			rendered[id] = true
	check(rendered.size() == expected.size(), "every distinct ninth body paragraph renders")
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	for id: String in pages:
		if not id.begins_with("c09.") and not id.begins_with("chapter_09."): continue
		var page: Dictionary = pages[id].page
		if page.type != "choice": continue
		view.open(page, {}, pages[id].scenario, empty_history, "第九章页面检查", false)
		await settle()
		check_layout(view, "small ninth governance choice")
		check(view.actions.get_child_count() == 3, "all three governance options fit small window")
	print("NINTH CATALOGUE UI: %d CHECKS | FAILURES: %d | PARAGRAPHS: %d" % [checks, failures, rendered.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
