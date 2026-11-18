extends "res://tests/test_campaign_ui.gd"
## Render all newly authored body pages and check the real relief map.
const StoryFinale = preload("res://scripts/story_runner.gd")
const PaintedFinale = preload("res://scripts/map_artwork.gd")

func collect_finale() -> void:
	var profiles: Array[Dictionary] = [
		{"repair_plan": "recast", "escort_terms": "hearing", "foundry_terms": "sale", "letter_company": "alone", "camp_company": "bridge", "governance_plan": "joint", "grove_mandate": "shared", "letter_reply": "return"},
		{"repair_plan": "sleeve", "escort_terms": "service", "foundry_terms": "lease", "letter_company": "companions", "camp_company": "clinic", "governance_plan": "split", "grove_mandate": "witness", "letter_reply": "unscheduled"},
		{"repair_plan": "recast", "escort_terms": "service", "foundry_terms": "sale", "letter_company": "alone", "camp_company": "watch", "governance_plan": "hold", "grove_mandate": "shared", "letter_reply": "return"},
		{"repair_plan": "sleeve", "escort_terms": "hearing", "foundry_terms": "lease", "letter_company": "companions", "camp_company": "watch", "governance_plan": "hold", "grove_mandate": "witness", "letter_reply": "unscheduled"},
	]
	var catalog: RefCounted = Campaign.new()
	for chapter: String in ["chapter_17", "chapter_18"]:
		var source: Dictionary = catalog._source(chapter)
		check(source.ok, "authored finale graph loads " + chapter)
		if not source.ok: return
		var branches: Array = ["runner", "screen"] if chapter == "chapter_17" else ["joint", "split", "hold"]
		for profile: Dictionary in profiles:
			for branch: String in branches:
				var story: RefCounted = StoryFinale.new(source.source)
				story.state.flags.merge(profile, true)
				for page_index: int in range(200):
					var page: Dictionary = story.current()
					var id: String = page.get("line_id", chapter + "." + page.node)
					if not pages.has(id):
						pages[id] = {"page": page, "scenario": catalog.index.scenarios.get(page.get("scenario", ""), {})}
					match page.type:
						"dialogue": story.advance(page.revision)
						"choice": story.choose(branch, page.revision)
						"battle": story.resolve_battle(0, page.revision)
						"end": break
		for node_id: String in source.source.nodes:
			var node: Dictionary = source.source.nodes[node_id]
			for line: Dictionary in node.get("lines", []):
				check(pages.has(line.id), "distinct body page available: " + line.id)
			if node.type == "end": check(pages.has(chapter + "." + node_id), "ending available: " + node_id)

func show_page(id: String) -> void:
	var item: Dictionary = pages[id]
	var view: Control = game.story_view
	var history: Array[Dictionary] = []
	view.open(item.page, {}, item.scenario, history, "页面检查", false)
	await settle()
	check_layout(view, id)
	if item.page.type in ["dialogue", "end"]:
		check(view.text_body.text == item.page.text and view.Art.get_texture(item.page.background) != null, "authored text and scene render " + id)
	if item.page.has("ending_title"):
		check(view.speaker.text == item.page.ending_title, "authored conclusion title renders")

func run() -> void:
	create_timer(240).timeout.connect(func() -> void: push_error("finale UI catalogue timed out"); quit(2))
	collect_finale()
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.campaign_session = Session.new("res://.tools/v041-finale-ui-save.json")
	game.deck_store = Store.new("res://.tools/v041-finale-ui-deck.json")
	root.add_child(game)
	current_scene = game
	await settle()
	var body_pages: int = 0
	for id: String in pages:
		await show_page(id)
		if pages[id].page.type in ["dialogue", "end"]: body_pages += 1
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	for id: String in ["chapter_17.kit", "chapter_17.runner_battle", "chapter_18.covenant", "chapter_18.joint_end", "chapter_18.split_end", "chapter_18.hold_end"]:
		await show_page(id)
	await capture("v041-hold-ending-small")
	check(game.story_view.actions.get_child_count() == 1, "conclusion has a return action without a phantom next chapter")
	var scenario: Dictionary = Campaign.new().index.scenarios.c17_runner
	var battle := Battle.new(int(scenario.seed), scenario.map, scenario.hero, scenario.enemy_class, scenario.deck, scenario.enemy_deck)
	battle.set_commander_identity(1, scenario.enemy_name, scenario.enemy_portrait)
	check(battle.add_generated_card(0, scenario.bonus_card) and battle.configure_objective(scenario.control).ok, "use the complete authored opening")
	game._mount_campaign_encounter({"scenario": scenario, "battle": battle})
	await settle()
	var ribbon: Control = game.get_node("%MapName").get_parent()
	check(PaintedFinale.texture(battle) != null and ribbon.hud_visible and ribbon.subtitle_text().contains("接应 0/3") and ribbon.subtitle_text().contains("下一站 E4"), "imported map and visible relay HUD display")
	for cell: Vector2i in [Vector2i(4, 8), Vector2i(8, 6), Vector2i(11, 4)]:
		check(game.board.cell_from_point(game.board.cell_center(cell)) == cell, "pointer maps to exact relay checkpoint")
	await capture("v041-lamplanding-small")
	DisplayServer.window_set_size(Vector2i(1440, 1000))
	await settle()
	await capture("v041-lamplanding")
	print("FINALE UI: %d CHECKS | FAILURES: %d | BODY PAGES: %d" % [checks, failures, body_pages])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
