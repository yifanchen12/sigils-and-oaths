extends "res://tests/test_campaign_ui.gd"
## Render every tenth-chapter conditional paragraph in Godot StoryView.
## Earlier victories in this catalogue are narrative fixtures only.

func prepare_tenth() -> void:
	# Iterative representative histories avoid recursively traversing all
	# 147,456 prior branches on Godot's GDScript call stack.
	for variant: int in range(8):
		for plan: String in ["joint", "split", "hold"]:
			var campaign: RefCounted = Campaign.new()
			check(campaign.start().ok, "catalogue starts a valid campaign")
			var choices: Dictionary = {
				"chapter_01.route": "road", "chapter_02.priority": "relief",
				"chapter_03.route": "vent", "chapter_04.terms": "sale" if variant % 2 == 0 else "lease",
				"chapter_05.water": "nursery", "chapter_05.mandate": "shared" if variant % 4 < 2 else "witness",
				"chapter_06.disclosure": "open" if variant % 2 == 0 else "witnessed",
				"chapter_07.camp": ["bridge", "clinic", "watch"][variant % 3],
				"chapter_08.pressure": "isolate" if variant < 4 else "buffer", "chapter_09.governance": plan
			}
			for step: int in range(1800):
				var page: Dictionary = campaign.story.current()
				if campaign.story.graph.id == "chapter_10":
					var id: String = page.get("line_id", "chapter_10." + page.node)
					if not pages.has(id): pages[id] = {"page": page, "scenario": campaign.scenario(), "snapshot": campaign.snapshot()}
				match page.type:
					"dialogue": campaign.story.advance(page.revision)
					"choice": campaign.story.choose(choices.get(campaign.story.graph.id + "." + page.node, page.options[0].id), page.revision)
					"battle": campaign.story.resolve_battle(0, page.revision)
					"end":
						if campaign.story.graph.id == "chapter_10": break
						check(campaign.advance_chapter().ok, "catalogue enters next earned chapter")

func run() -> void:
	create_timer(240).timeout.connect(func() -> void: push_error("tenth catalogue UI timeout"); quit(2))
	prepare_tenth()
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_10.json"))
	var expected: Dictionary = {}
	for node: Dictionary in graph.nodes.values():
		for line: Dictionary in node.get("lines", []): expected[line.id] = true
		if node.type == "end": expected["chapter_10.end"] = true
	for id: String in expected: check(pages.has(id), "tenth conditional paragraph has a native page: " + id)
	check(pages.has("chapter_10.gate_battle"), "plan-specific gate battle has a native briefing page")
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v034-catalog-deck.json")
	game.campaign_session = Session.new("res://.tools/v034-catalog-save.json")
	root.add_child(game)
	current_scene = game
	await settle()
	var view: Control = game.story_view
	var empty_history: Array[Dictionary] = []
	var rendered: Dictionary = {}
	for id: String in pages:
		if not id.begins_with("c10.") and not id.begins_with("chapter_10."): continue
		var page: Dictionary = pages[id].page
		view.open(page, {}, pages[id].scenario, empty_history, "第十章页面检查", false)
		await settle()
		check_layout(view, id)
		if page.type in ["dialogue", "end"]:
			check(view.text_body.text == page.text and view.Art.get_texture(page.background) != null, "tenth text and source art render: " + id)
			rendered[id] = true
	check(rendered.size() == expected.size(), "every distinct tenth body paragraph renders")
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	var item: Dictionary = pages["chapter_10.gate_battle"]
	view.open(item.page, {}, item.scenario, empty_history, "第十章页面检查", false)
	await settle()
	check_layout(view, "small tower gate briefing")
	check(view.text_body.text.contains("D9") and view.text_body.text.contains("K9") and view.text_body.text.begins_with("作战目标\n"), "small briefing shows exact northern objective coordinates first")
	await capture("v034-gate-briefing-small")
	print("TENTH CATALOGUE UI: %d CHECKS | FAILURES: %d | PARAGRAPHS: %d" % [checks, failures, rendered.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
