extends "res://tests/test_campaign_playthrough_ui.gd"

const Preferences = preload("res://scripts/settings_store.gd")
const PRIOR := "res://tests/fixtures/v045-c07-eastward.json"
const NATIVE_SAVE := "res://.tools/v046-saltlane-native.json"
const TRACE := "res://.tools/continuous-campaign-road-pump-focus-nursery-focus-court-focus-late-route-focus-saltlane-kiln.json"

func open_from_prior() -> bool:
	var seed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PRIOR))
	var sixth: Dictionary = seed.completed.back()
	var campaign: RefCounted = game.campaign_session.campaign
	if not campaign.restore({"chapter_id": "chapter_06", "story": sixth.story, "completed": seed.completed.slice(0, 5)}).ok: return false
	if not campaign.advance_chapter().ok: return false
	for step: int in range(300):
		var page: Dictionary = campaign.story.current()
		if page.node == "saltlane_call": return game.campaign_session.save().ok
		if page.type == "dialogue": campaign.story.advance(page.revision)
		elif page.node == "camp": campaign.story.choose("clinic", page.revision)
		else: return false
	return false

func read_until(destination: String) -> bool:
	for step: int in range(48):
		var page: Dictionary = game.campaign_session.current()
		if page.node == destination: return true
		if page.type != "dialogue": return false
		var action: Control = game.story_view.actions.get_child(0)
		check(root.get_visible_rect().encloses(action.get_global_rect()), "continue button fits the small view")
		await click(action.get_global_rect().get_center())
	return false

func run() -> void:
	create_timer(220).timeout.connect(func() -> void: push_error("saltlane native timeout"); quit(2))
	Engine.time_scale = 2.2
	DisplayServer.window_set_size(Vector2i(1008, 700))
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v046-saltlane-native-deck.json")
	game.settings_store = Preferences.new("user://v046-saltlane-native.cfg")
	game.campaign_session = Session.new(NATIVE_SAVE)
	root.add_child(game); current_scene = game
	await settle()
	check(open_from_prior(), "authentic sixth chapter history leads to current seventh chapter")
	if failures > 0: quit(1); return
	game._open_council()
	await settle()
	var resume: Button = button(game.council, "继续战役")
	check(resume != null, "continue command exists")
	if resume == null: quit(1); return
	await click(resume.get_global_rect().get_center())
	check(game.story_view.visible and game.campaign_session.current().node == "saltlane_call" and game.story_view.actions.get_child_count() == 2, "visible rescue choice at 1008 by 700")
	if failures > 0: quit(1); return
	await click(game.story_view.actions.get_child(1).get_global_rect().get_center())
	check(game.story_view.background_id == "scene_saltlane_yard" and game.story_view.Art.get_texture(game.story_view.background_id) != null, "original side-story artwork is loaded")
	await capture("v046-saltlane-story-small")
	check(await read_until("saltlane_route") and game.story_view.actions.get_child_count() == 2, "read all new common pages with visible controls")
	if failures > 0: quit(1); return
	await click(game.story_view.actions.get_child(1).get_global_rect().get_center())
	check(await read_until("saltlane_kiln_battle") and game.story_view.text_body.text.contains("N3") and not game.story_view.stage.visible, "east briefing has space and announces its own exit")
	if failures > 0: quit(1); return
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TRACE))
	for match_row: Dictionary in recorded.games:
		if match_row.scenario == "c07_saltlane_kiln": row = match_row; break
	check(not row.is_empty() and row.winner == 0 and row.final.objective.streak == 1, "reference has real escort delivery")
	if failures > 0: quit(1); return
	var setup: Dictionary = game.campaign_session.campaign.scenario()
	shadow = Battle.new(int(setup.seed), setup.map, setup.hero, setup.enemy_class, setup.deck, setup.enemy_deck, 90)
	shadow.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
	shadow.add_generated_card(0, setup.bonus_card)
	shadow.configure_objective(setup.control)
	await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
	check(game.campaign_active and game.battle.width == 16 and game.battle.height == 12 and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "native battle starts with the authored map, crew and sentry")
	if failures > 0: quit(1); return
	DisplayServer.window_set_size(Vector2i(1296, 900))
	if not game.expanded_battlefield: game._toggle_battlefield()
	await settle()
	await click_cell(game.battle.escort_unit().pos)
	check(game.selected_unit == game.battle.escort_unit().id and game.board.moves.size() > 0 and game.get_node("%MapName").text.contains("N3"), "marked crew selection exposes movement and exit")
	check(game.get_node("%MapName").get_parent().subtitle_text().contains("护送至 N3"), "painted battle header shows the actual escort objective")
	await capture("v046-saltlane-battle")
	while cursor < row.trace.size() and failures == 0:
		if row.trace[cursor].side == 1:
			advance_shadow()
			continue
		if not await wait_for_player(): break
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "native enemy uses the production route decisions")
		if failures > 0: break
		var action: Dictionary = Replay.action_from(row.trace[cursor].action)
		await player_action(action)
		advance_shadow()
		if action.type != "end_turn":
			check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "visible input performs the expected action")
	if failures == 0 and await wait_for_player():
		check(game.battle.winner == 0 and game.battle.objective.streak == 1 and game.get_node("%ResultDetail").text.contains("已抵达"), "native delivery triggers immediate victory and result text")
		await capture("v046-saltlane-victory")
		await click(game.get_node("%PlayAgain").get_global_rect().get_center())
		check(game.story_view.visible and game.campaign_session.current().node == "saltlane_kiln_after", "native victory opens the earned aftermath")
		var reload = Session.new(NATIVE_SAVE)
		check(reload.load_campaign().ok and reload.current().node == "saltlane_kiln_after", "actual native aftermath restores from disk")
		await check_retreat_button()
	print("SALTLANE NATIVE UI: %d CHECKS | FAILURES: %d | PLAYED ACTIONS: %d" % [checks, failures, cursor])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 and cursor == row.trace.size() else 1)

func check_retreat_button() -> void:
	game.campaign_session = Session.new(NATIVE_SAVE + ".retreat")
	check(open_from_prior(), "restore initial clinic checkpoint for withdrawal")
	if failures > 0: return
	var session: RefCounted = game.campaign_session
	var runner: RefCounted = session.campaign.story
	while runner.current().type != "battle":
		var page: Dictionary = runner.current()
		if page.type == "dialogue": runner.advance(page.revision)
		elif page.node == "saltlane_call": runner.choose("answer_call", page.revision)
		elif page.node == "saltlane_route": runner.choose("school", page.revision)
		else: check(false, "withdrawal fixture reached unexpected page"); return
	check(session.begin_battle(session.token()).ok, "begin actual battle for deadline check")
	if failures > 0: return
	var battle: Battle = session.encounter
	while battle.winner == -1: battle.end_turn()
	check(battle.winner == 1 and session.finish_battle(battle).ok, "pass legal turns to the real deadline loss")
	DisplayServer.window_set_size(Vector2i(1008, 700))
	game._show_story()
	await settle()
	check(game.story_view.actions.get_child_count() == 2 and game.story_view.actions.get_child(0).text == "重新出征", "defeat offers both retry and a return to the main story")
	if failures > 0: return
	var retreat: Button = game.story_view.actions.get_child(1)
	check(root.get_visible_rect().encloses(retreat.get_global_rect()), "withdraw action fits the small window")
	await click(retreat.get_global_rect().get_center())
	check(game.campaign_session.current().node == "saltlane_retreat", "visible withdrawal action opens its own aftermath")
