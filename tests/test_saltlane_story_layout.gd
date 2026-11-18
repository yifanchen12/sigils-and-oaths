extends "res://tests/test_campaign_ui.gd"
## Native layout coverage uses authored pages as fixtures. Route and battle
## earnability are checked by the separate campaign and encounter tests.

const Story = preload("res://scripts/story_runner.gd")
const Preferences = preload("res://scripts/settings_store.gd")
const REPORT := "res://.tools/v046-story-layout.json"

func run() -> void:
	create_timer(200).timeout.connect(func() -> void: push_error("saltlane layout timeout"); quit(2))
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v046-story-layout-deck.json")
	game.settings_store = Preferences.new("user://v046-story-layout.cfg")
	game.campaign_session = Session.new("res://.tools/v046-story-layout-save.json")
	root.add_child(game); current_scene = game
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	var view: Control = game.story_view
	view.set_reading_size(130)
	var body_pages: Dictionary = {}
	var hashes: Dictionary = {}
	var empty_history: Array[Dictionary] = []
	for chapter: String in ["chapter_07", "chapter_08"]:
		var path: String = "res://data/narrative/chapters/" + chapter + ".json"
		var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var runner = Story.new(graph)
		check(runner.error_message.is_empty(), "load actual chapter graph " + chapter)
		body_pages[chapter] = 0
		hashes[chapter] = FileAccess.get_sha256(path)
		for node_id: String in graph.nodes:
			var node: Dictionary = graph.nodes[node_id]
			if node.type not in ["dialogue", "end"]: continue
			var count: int = node.lines.size() if node.type == "dialogue" else 1
			for line_index: int in range(count):
				var conditions: Dictionary = node.lines[line_index].get("when", {}) if node.type == "dialogue" else {}
				runner.state.node = node_id
				runner.state.line = line_index if node.type == "dialogue" else 0
				runner.state.flags = graph.defaults.merged(conditions, true)
				var page: Dictionary = runner.current()
				var label: String = page.get("line_id", chapter + "." + node_id)
				view.open(page, {}, {}, empty_history, "阅读排版检查", false)
				await settle()
				check_layout(view, label)
				check(view.text_body.text == page.text and view.Art.get_texture(view.background_id) != null, "exact page and runtime illustration: " + label)
				body_pages[chapter] += 1
	var file := FileAccess.open(REPORT, FileAccess.WRITE)
	check(file != null, "layout report writable")
	if file != null:
		file.store_line(JSON.stringify({"milestone": "0.46.0-dev", "passed": failures == 0, "chapter_sha256": hashes,
			"body_pages": body_pages, "checks": checks, "failures": failures, "window": [1008, 700], "reading_size": 130,
			"scope": "All authored body pages of C07 and C08 opened in the native StoryView from authored line fixtures. Runtime branch access and combat have separate tests."}, "\t"))
		file.close()
	print("SALTLANE STORY LAYOUT: %d CHECKS | %d FAILURES | %s" % [checks, failures, JSON.stringify(body_pages)])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
