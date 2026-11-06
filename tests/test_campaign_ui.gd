extends "res://tests/test_unit_skills_ui.gd"
## Native renderer and real controls. Battle victories used to reach chapter ends
## are fixtures; this is not a normal-difficulty campaign playthrough.
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const PATH: String = "res://.tools/native_campaign.json"
var pages: Dictionary = {}
var chapter_ends: Dictionary = {}
var future_condition_keys: Dictionary = {}
var collected_entries: Dictionary = {}
func prepare_page_catalog(campaign: RefCounted) -> void:
	# Native rendering needs distinct pages, not every completed history. Keep
	# conditions from this AND later chapters so a later inherited branch is never
	# lost when earlier chapters converge. Exhaustive history checks stay separate.
	var keys: Dictionary = {}
	for index: int in range(campaign.index.chapters.size() - 1, -1, -1):
		var entry: Dictionary = campaign.index.chapters[index]
		var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.path))
		for node: Dictionary in graph.nodes.values():
			var rows: Array = node.get("lines", []) + node.get("options", [])
			for row: Dictionary in rows:
				for key: String in row.get("when", {}): keys[key] = true
		future_condition_keys[entry.id] = keys.keys()
func collect(campaign: RefCounted, entering: bool = false) -> void:
	var runner: RefCounted = campaign.story
	if entering:
		var relevant: Dictionary = {}
		for key: String in future_condition_keys[runner.graph.id]:
			if runner.state.flags.has(key): relevant[key] = runner.state.flags[key]
		var signature: String = runner.graph.id + JSON.stringify(relevant, "", true, true)
		if collected_entries.has(signature): return
		collected_entries[signature] = true
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
			if not campaign.next_chapter().is_empty(): campaign.advance_chapter(); collect(campaign, true)
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
	create_timer(450).timeout.connect(func() -> void: push_error("campaign native UI timeout"); quit(2))
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
	var catalog: RefCounted = Campaign.new(); catalog.start(); prepare_page_catalog(catalog); collect(catalog, true)
	var expected_dialogues: int = 0
	for entry: Dictionary in catalog.index.chapters:
		var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.path))
		for node: Dictionary in graph.nodes.values():
			expected_dialogues += node.get("lines", []).size()
			for line: Dictionary in node.get("lines", []): check(pages.has(line.id), "every conditional authored paragraph has a native page: " + line.id)
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
			var has_portrait: bool = view.Art.HERO_ORDER.has(item.page.speaker_id) or view.Art.UNIT_ORDER.has(item.page.speaker_id)
			check(view.text_body.text == item.page.text and view.Art.get_texture(item.page.background) != null, "authored text and scene render: " + id)
			check(view.illustration.visible == has_portrait and (not has_portrait or view.illustration.texture != null), "only the actual named companion displays a portrait: " + id)
		elif item.page.type == "end":
			check(view.text_body.text == item.page.text, "authored ending paragraph renders: " + id)
	check(rendered == expected_dialogues, "every distinct authored dialogue rendered; ending paragraphs checked separately")
	# Real chapter-end buttons save history and advance through the session.
	for chapter: String in ["chapter_01", "chapter_02", "chapter_03", "chapter_04", "chapter_05", "chapter_06", "chapter_07"]:
		check(game.campaign_session.campaign.restore(chapter_ends[chapter]).ok, "load end fixture " + chapter)
		game._show_story(); await settle()
		await click_named(view.actions, "进入")
		check(game.campaign_session.campaign.completed.size() == int(chapter.right(2)), "native next-chapter button saves preceding history")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.current().line_id == "c08.rope.01", "native cross-chapter save resumes eighth chapter in a fresh session")
	await restore_page("c08.rope.01")
	check(view.background_id == "scene_waterpass", "eighth opening uses water passage scene")
	await capture("v025-waterpass")
	await restore_page("c08.ashes.01")
	check(view.background_id == "scene_oldfurnace", "old furnace testimony has its own room")
	await capture("v025-old-furnace")
	DisplayServer.window_set_size(Vector2i(1008, 700)); await settle()
	for index: int in range(2):
		var plan: String = ["isolate", "buffer"][index]
		await restore_page("chapter_08.pressure")
		check_layout(view, "small window pressure choice")
		if index == 0: await capture("v025-pressure-small")
		await click(view.actions.get_child(index).get_global_rect().get_center())
		check(view.page.line_id == "c08." + plan + ".01" and game.campaign_session.campaign.story.state.flags.pressure_plan == plan, "actual pressure choice enters correct prose")
		fresh = Session.new(PATH)
		check(fresh.load_campaign().ok and fresh.current().line_id == view.page.line_id and not fresh.campaign.story.state.flags.sunspire_stable, "plan saved before battle without victory facts")
	DisplayServer.window_set_size(Vector2i(1296, 900)); await settle()
	for plan: String in ["isolate", "buffer"]:
		await restore_page("chapter_08." + plan + "_battle")
		await click_named(view.actions, "率军出征")
		check(not view.visible and game.battle.map_definition.id == "sunspire" and game.battle.players[0].hero_id == "pyromancer", "native Sunspire deployment " + plan)
		check((game.battle.objective.get("cells") == [[4, 4], [7, 5]] and game.battle.objective.round_limit == 12) if plan == "isolate" else game.battle.objective.is_empty(), "native route objective " + plan)
		await capture("v025-" + plan + "-opening")
	await restore_page("chapter_08.end")
	check(find_button(view.actions, "进入") == null, "unwritten ninth chapter has no native entry button")
	await restore_page("c07.arrival.01")
	await capture("v024-eaststreet")
	await restore_page("c07.father.16")
	await capture("v024-father-trail")
	await restore_page("c07.transfer.01")
	check(view.background_id == "scene_school_day", "resident transfer uses daylight school")
	await capture("v024-school-day")
	DisplayServer.window_set_size(Vector2i(1008, 700)); await settle()
	for index: int in range(3):
		var camp: String = ["bridge", "clinic", "watch"][index]
		await restore_page("chapter_07.camp")
		check_layout(view, "small window three-way camp choice")
		if index == 0: await capture("v024-camp-small")
		await click(view.actions.get_child(index).get_global_rect().get_center())
		check(game.campaign_session.campaign.story.state.flags.camp_company == camp and view.page.line_id == "c07." + camp + ".01", "actual camp button enters " + camp)
		check_layout(view, "small window camp opening " + camp)
		fresh = Session.new(PATH)
		check(fresh.load_campaign().ok and fresh.current().line_id == view.page.line_id and fresh.campaign.story.state.flags.camp_company == camp and fresh.encounter == null, "actual camp choice persists to disk " + camp)
	DisplayServer.window_set_size(Vector2i(1296, 900)); await settle()
	await restore_page("c07.bridge.01")
	await capture("v024-river-camp")
	await restore_page("c07.clinic.01")
	check(view.background_id == "scene_school_ward", "temporary ward uses matching night interior")
	await capture("v024-school-ward")
	await restore_page("c07.watch.01")
	await capture("v024-gallery-camp")
	await restore_page("chapter_07.end")
	check(find_button(view.actions, "进入") != null, "installed eighth chapter is offered at seventh ending")
	await restore_page("c06.teacher.03")
	await capture("v022-teacher")
	await restore_page("c06.archive.07")
	await capture("v022-father-record")
	await restore_page("chapter_06.disclosure")
	DisplayServer.window_set_size(Vector2i(1008, 700)); await settle()
	check_layout(view, "small window evidence choice")
	await capture("v022-evidence-small")
	await click(view.actions.get_child(1).get_global_rect().get_center())
	check(game.campaign_session.campaign.story.state.flags.evidence_council == "witnessed" and view.page.line_id == "c06.witnessed.01", "actual evidence choice opens time-limited witnessed review")
	await restore_page("chapter_06.letter_choice")
	check_layout(view, "small window personal letter choice")
	await capture("v022-letter-small")
	await click(view.actions.get_child(1).get_global_rect().get_center())
	check(game.campaign_session.campaign.story.state.flags.letter_company == "companions" and view.page.line_id == "c06.companions.01", "actual letter choice asks companions to remain")
	fresh = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.campaign.story.state.flags.letter_company == "companions", "personal choice persists to disk")
	DisplayServer.window_set_size(Vector2i(1296, 900)); await settle()
	await restore_page("c06.companions.06")
	await capture("v022-family-letter")
	await restore_page("chapter_06.court_battle")
	check(view.text_body.text.contains("陶因"), "court briefing names actual opponent")
	await click_named(view.actions, "率军出征")
	check(not view.visible and game.battle.map_definition.id == "citadel" and game.battle.players[0].hero_id == "warden" and game.battle.objective.is_empty(), "actual sixth-chapter deployment uses court and ordinary commander objective")
	await capture("v022-court-opening")
	await restore_page("c05.arrival.10")
	await capture("v021-syla-home")
	await restore_page("c05.house.09")
	await capture("v021-mother")
	await restore_page("chapter_05.water")
	DisplayServer.window_set_size(Vector2i(1008, 700)); await settle()
	check_layout(view, "small window water choice")
	await capture("v021-water-small")
	await click(view.actions.get_child(0).get_global_rect().get_center())
	check(game.campaign_session.campaign.story.state.flags.water_plan == "nursery" and view.page.line_id == "c05.nursery.01", "real water choice selects nursery consequences")
	await restore_page("chapter_05.mandate")
	check_layout(view, "small window mandate choice")
	await capture("v021-mandate-small")
	await click(view.actions.get_child(1).get_global_rect().get_center())
	check(game.campaign_session.campaign.story.state.flags.grove_mandate == "witness" and view.page.line_id == "c05.witness.01", "real mandate choice relinquishes authority without erasing earlier water choice")
	fresh = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.campaign.story.state.flags.grove_mandate == "witness", "chosen witness status persists to disk")
	DisplayServer.window_set_size(Vector2i(1296, 900)); await settle()
	await restore_page("chapter_05.nursery_battle")
	check(view.text_body.text.contains("F6、G5") and view.text_body.text.contains("12个完整轮次"), "grove briefing shows actual control coordinates and deadline")
	await click_named(view.actions, "率军出征")
	check(not view.visible and game.battle.map_definition.id == "greenwood" and game.battle.players[0].hero_id == "grove" and game.battle.objective.cells == [[5, 4], [6, 5]], "real chapter-five deployment starts grove commander with the authored objective")
	await capture("v021-grove-battle")
	await restore_page("c04.home.07")
	await capture("v020-clinic-dialogue")
	await restore_page("c04.eastbank.02")
	await capture("v020-harbor-locked")
	await restore_page("c04.ashore.02")
	await capture("v020-harbor-open")
	await restore_page("c04.night.01")
	await capture("v020-clinic-night")
	await click(view.backlog_button.get_global_rect().get_center())
	check(view.showing_history and not view.stage.visible and view.text_body.size.y > 400, "backlog expands reading space and hides stale portrait")
	await capture("v020-backlog")
	await click(view.backlog_button.get_global_rect().get_center())
	await restore_page("chapter_04.shelter")
	await capture("v020-shelter")
	await click(view.actions.get_child(1).get_global_rect().get_center())
	check(game.campaign_session.campaign.story.state.flags.harbor_shelter == "households" and view.page.line_id == "c04.households.01", "native shelter choice enters its actual branch")
	await restore_page("chapter_04.terms")
	DisplayServer.window_set_size(Vector2i(1008, 700)); await settle()
	check_layout(view, "small window harbor terms")
	await capture("v020-foundry-choice-small")
	await click(view.actions.get_child(1).get_global_rect().get_center())
	check(game.campaign_session.campaign.story.state.flags.foundry_terms == "lease" and view.page.line_id == "c04.lease.01", "native terms choice records the stated debt consequence")
	DisplayServer.window_set_size(Vector2i(1296, 900)); await settle()
	await restore_page("c04.pump.05")
	check(view.background_id == "scene_pump_closed", "line-specific transition reaches the closed pump house")
	await capture("v020-pump-closed")
	await restore_page("c04.after_pump.01")
	check(view.background_id == "scene_pump_open", "postbattle prose displays the open pump house")
	await capture("v020-pump-open")
	await restore_page("chapter_04.pump_battle")
	await click_named(view.actions, "率军出征")
	check(not view.visible and game.battle.map_definition.id == "harbor" and game.battle.players[0].hero_id == "pyromancer", "native harbor briefing starts its actual authored encounter")
	await capture("v020-pump-battle-opening")
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
