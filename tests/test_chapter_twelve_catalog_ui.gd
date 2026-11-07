extends "res://tests/test_chapter_eleven_catalog_ui.gd"
## Native StoryView coverage; prior wins in this catalogue are fixtures.

func prepare_twelve() -> void:
	for plan: String in ["joint", "split", "hold"]:
		for custody: String in ["loaned", "northbank"]:
			var campaign: RefCounted = Campaign.new()
			check(campaign.start().ok, "twelfth catalogue starts valid campaign")
			var choices: Dictionary = {
				"chapter_01.route": "road", "chapter_02.priority": "relief",
				"chapter_03.route": "vent", "chapter_04.terms": "sale",
				"chapter_05.water": "nursery", "chapter_05.mandate": "shared",
				"chapter_06.disclosure": "open", "chapter_07.camp": "bridge",
				"chapter_08.pressure": "isolate", "chapter_09.governance": plan,
				"chapter_12.custody": custody
			}
			for step: int in range(2100):
				var page: Dictionary = campaign.story.current()
				if campaign.story.graph.id == "chapter_12":
					var id: String = page.get("line_id", "chapter_12." + page.node + "." + plan + "." + custody)
					if not pages.has(id): pages[id] = {"page": page, "scenario": campaign.scenario()}
				match page.type:
					"dialogue": campaign.story.advance(page.revision)
					"choice": campaign.story.choose(choices.get(campaign.story.graph.id + "." + page.node, page.options[0].id), page.revision)
					"battle": campaign.story.resolve_battle(0, page.revision)
					"end":
						if campaign.story.graph.id == "chapter_12": break
						check(campaign.advance_chapter().ok, "catalogue enters next chapter")

func run() -> void:
	create_timer(300).timeout.connect(func() -> void: push_error("twelfth catalogue UI timeout"); quit(2))
	prepare_twelve()
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_12.json"))
	var expected: Dictionary = {}
	for node: Dictionary in graph.nodes.values():
		for line: Dictionary in node.get("lines", []): expected[line.id] = true
		if node.type == "end": expected["chapter_12.end.joint.loaned"] = true
	for id: String in expected: check(pages.has(id), "twelfth conditional paragraph has native page: " + id)
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v036-catalog-deck.json")
	game.campaign_session = Session.new("res://.tools/v036-catalog-save.json")
	root.add_child(game); current_scene = game
	await settle()
	var view: Control = game.story_view
	var empty_history: Array[Dictionary] = []
	var rendered: Dictionary = {}
	for id: String in pages:
		if not id.begins_with("c12.") and not id.begins_with("chapter_12."): continue
		var page: Dictionary = pages[id].page
		view.open(page, {}, pages[id].scenario, empty_history, "第十二章页面检查", false)
		await settle()
		check_layout(view, id)
		if page.type in ["dialogue", "end"]:
			check(view.text_body.text == page.text and view.Art.get_texture(page.background) != null, "twelfth text and source art render: " + id)
			rendered[id] = true
	check(rendered.size() == 73, "all twelfth body paragraphs and six ending variants render in native UI")
	for id: String in ["c12.arrival.01", "c12.after.01", "c12.measure.01"]:
		var page: Dictionary = pages[id].page
		view.open(page, {}, pages[id].scenario, empty_history, "第十二章页面检查", false)
		await settle()
		await capture("v036-" + id.replace(".", "-"))
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	for id: String in ["c12.arrival.01", "c12.measure.01", "chapter_12.end.joint.loaned"]:
		var page: Dictionary = pages[id].page
		view.open(page, {}, pages[id].scenario, empty_history, "第十二章页面检查", false)
		await settle()
		check_layout(view, "small " + id)
	await capture("v036-chapter12-end-small")
	print("TWELFTH CATALOGUE UI: %d CHECKS | FAILURES: %d | PARAGRAPHS: %d" % [checks, failures, rendered.size()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
