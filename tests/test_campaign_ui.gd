extends "res://tests/test_unit_skills_ui.gd"
## Native renderer and real controls. Battle victories used to reach chapter ends
## are fixtures; this is not a normal-difficulty campaign playthrough.
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const PATH: String = "res://.tools/native_campaign.json"
var pages: Dictionary = {}
var chapter_ends: Dictionary = {}
func collect(campaign: RefCounted) -> void:
	var runner: RefCounted = campaign.story
	var page: Dictionary = runner.current()
	var id: String = page.get("line_id", runner.graph.id + "." + page.node)
	if not pages.has(id): pages[id] = {"page": page, "scenario": campaign.scenario(), "snapshot": campaign.snapshot()}
	match page.type:
		"dialogue": runner.advance(page.revision); collect(campaign)
		"choice":
			for option: Dictionary in page.options:
				var branch: RefCounted = Campaign.new()
				branch.restore(campaign.snapshot()); branch.story.choose(option.id, page.revision); collect(branch)
		"battle": runner.resolve_battle(0, page.revision); collect(campaign)
		"end":
			if not chapter_ends.has(runner.graph.id): chapter_ends[runner.graph.id] = campaign.snapshot()
			if not campaign.next_chapter().is_empty(): campaign.advance_chapter(); collect(campaign)
func find_button(parent: Node, text_part: String) -> Button:
	if parent is Button and parent.text.contains(text_part): return parent
	for child: Node in parent.get_children():
		var found: Button = find_button(child, text_part)
		if found != null: return found
	return null
func click_named(parent: Node, text_part: String) -> void:
	var button: Button = find_button(parent, text_part)
	check(button != null and button.is_visible_in_tree(), "visible button: " + text_part)
	if button != null: await click(button.get_global_rect().get_center())
func check_layout(view: Control, label: String) -> void:
	var viewport: Rect2 = game.get_viewport_rect()
	check(view.text_body.size.x >= 400 and view.text_body.size.y >= 160, "useful reading area: " + label)
	check(view.text_body.get_content_width() <= view.text_body.size.x + 1, "text wraps without horizontal overflow: " + label)
	check(view.heading.get_global_rect().end.x <= viewport.end.x, "title within viewport: " + label)
	for caption: String in ["已读回看", "返回战前页", "保存进度"]:
		var toolbar: Button = find_button(view, caption)
		check(toolbar != null and toolbar.size.x >= 90 and toolbar.size.y <= 64 and viewport.encloses(toolbar.get_global_rect()), "toolbar text has usable bounds: " + caption + " / " + label)
	for action: Control in view.actions.get_children():
		check(viewport.encloses(action.get_global_rect()) and action.size.y <= 150, "action remains inside viewport: " + label)
func restore_page(id: String) -> void:
	check(game.campaign_session.campaign.restore(pages[id].snapshot).ok, "restore authored page " + id)
	game.campaign_session.encounter = null
	game.campaign_active = true
	game.campaign_session.save()
	game._show_story()
	await settle()
func run() -> void:
	create_timer(150).timeout.connect(func() -> void: push_error("campaign native UI timeout"); quit(2))
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
	var catalog: RefCounted = Campaign.new(); catalog.start(); collect(catalog)
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/native_campaign_deck.json")
	game.campaign_session = Session.new(PATH)
	root.add_child(game); current_scene = game; await settle()
	await click_named(game.council, "新战役")
	var view: Control = game.story_view
	check(view.visible and game.campaign_session.current().line_id == "c01.a01", "real new-campaign button opens first authored page")
	var clock_before: float = game.battle.time_remaining
	await click(view.actions.get_child(0).get_global_rect().get_center())
	check(game.campaign_session.current().line_id != "c01.a01", "real continue button advances the story")
	await click(view.backlog_button.get_global_rect().get_center())
	check(view.showing_history and view.text_body.text.contains("别拔剑"), "backlog opens actual read history")
	await key(KEY_Q); await key(KEY_1)
	check(game.battle.time_remaining == clock_before, "reading and backlog pause the battle clock")
	await click(view.backlog_button.get_global_rect().get_center())
	var rendered: int = 0
	var empty_history: Array[Dictionary] = []
	for id: String in pages:
		var item: Dictionary = pages[id]
		view.open(item.page, {}, item.scenario, empty_history, "原生页面检查", false)
		await settle()
		check_layout(view, id)
		if item.page.type == "dialogue":
			rendered += 1
			check(view.text_body.text == item.page.text and view.illustration.texture != null, "authored text and artwork render: " + id)
		elif item.page.type == "end":
			check(view.text_body.text == item.page.text, "authored ending paragraph renders: " + id)
	check(rendered == 356, "all 356 distinct dialogue paragraphs rendered; four ending paragraphs checked separately")
	# Real chapter-end buttons save history and advance through the session.
	for chapter: String in ["chapter_01", "chapter_02", "chapter_03"]:
		check(game.campaign_session.campaign.restore(chapter_ends[chapter]).ok, "load end fixture " + chapter)
		game._show_story(); await settle()
		await click_named(view.actions, "进入")
		check(game.campaign_session.campaign.completed.size() == int(chapter.right(2)), "native next-chapter button saves preceding history")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.current().line_id == "c04.home.01", "native cross-chapter save resumes in a fresh session")
	await restore_page("c04.home.07")
	await capture("chapter4-home")
	await restore_page("chapter_04.shelter")
	await capture("chapter4-shelter")
	await click(view.actions.get_child(1).get_global_rect().get_center())
	check(game.campaign_session.campaign.story.state.flags.harbor_shelter == "households" and view.page.line_id == "c04.households.01", "native shelter choice enters its actual branch")
	await restore_page("chapter_04.terms")
	DisplayServer.window_set_size(Vector2i(1008, 700)); await settle()
	check_layout(view, "small window harbor terms")
	await capture("chapter4-terms-small")
	await click(view.actions.get_child(1).get_global_rect().get_center())
	check(game.campaign_session.campaign.story.state.flags.foundry_terms == "lease" and view.page.line_id == "c04.lease.01", "native terms choice records the stated debt consequence")
	DisplayServer.window_set_size(Vector2i(1296, 900)); await settle()
	await restore_page("chapter_04.pump_battle")
	await click_named(view.actions, "率军出征")
	check(not view.visible and game.battle.map_definition.id == "harbor" and game.battle.players[0].hero_id == "pyromancer", "native harbor briefing starts its actual authored encounter")
	await capture("chapter4-pump-opening")
	await restore_page("chapter_03.letter")
	await click(view.actions.get_child(1).get_global_rect().get_center())
	check(game.campaign_session.campaign.story.state.flags.letter_reply == "unscheduled" and game.campaign_session.campaign.story.state.flags.letter_delivered, "native second choice records letter without a return-date promise")
	await restore_page("c03.old_mine.04")
	await capture("chapter3-frey")
	await restore_page("chapter_03.route")
	await capture("chapter3-route")
	DisplayServer.window_set_size(Vector2i(1008, 700)); await settle()
	check_layout(view, "small window route")
	await capture("chapter3-route-small")
	DisplayServer.window_set_size(Vector2i(1296, 900)); await settle()
	await restore_page("chapter_03.vent_battle")
	check(view.text_body.text.contains("E6、H5") and view.text_body.text.contains("10个完整轮次"), "native briefing shows real wind-vent objective")
	await click_named(view.actions, "率军出征")
	check(not view.visible and game.campaign_active and game.battle.objective.round_limit == 10, "native deployment enters actual wind-vent battle")
	check(game.get_node("%MapName").text.contains("驻守") and game.get_node("%MapName").tooltip_text.contains("E6、H5"), "battle HUD shows generic control objective with correct cells")
	var ribbon: Control = game.get_node("%MapName").get_parent()
	check(ribbon.is_visible_in_tree() and ribbon.hud_visible and ribbon.subtitle_text().contains("驻守 0/2"), "visible painted HUD includes control progress")
	await capture("chapter3-wind-vents")
	Fixture.troop(game.battle, "spear", Vector2i(4, 4)); Fixture.troop(game.battle, "sword", Vector2i(7, 5))
	game.battle.end_turn(); game.battle.end_turn(); game._refresh(); await settle()
	check(ribbon.subtitle_text().contains("驻守 1/2") and ribbon.subtitle_text().contains("已过 1/10"), "visible HUD updates after a real objective checkpoint")
	await capture("chapter3-control-progress")
	await click(game.get_node("%Restart").get_global_rect().get_center())
	check(game.council.visible and not view.visible, "battle menu button opens council from campaign battle")
	await click_named(game.council, "继续战役")
	check(not game.council.visible and game.campaign_session.encounter == game.battle and game.battle.objective.round_limit == 10 and game.battle.objective.streak == 1, "native continue preserves the exact campaign encounter and control credit")
	print("CAMPAIGN NATIVE UI CHECKS: %d | FAILURES: %d | DIALOGUES: %d | DISPLAY: %s" % [checks, failures, rendered, DisplayServer.get_name()])
	game.queue_free(); await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
	quit(0 if failures == 0 else 1)
