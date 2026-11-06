extends "res://tests/test_campaign_playthrough_ui.gd"
## No checkpoint() calls: enter through New Campaign, read the actual pages,
## execute every encountered battle, then reload the first real defeat.
const CONTINUOUS_SAVE: String = "res://.tools/native_continuous_save.json"
const CONTINUOUS_CURSOR: String = "res://.tools/native_continuous_cursor.json"
const REPORT: String = "res://.tools/continuous-campaign-road.json"
var continuous_report: Dictionary
var game_index: int = 0
var choice_index: int = 0
var read_ids: Array[String] = []
var total_actions: int = 0

func portable_progress() -> Dictionary:
	# JSON restores numeric values as floats. Compare serialized state with
	# serialized state, retaining every field instead of dropping revisions.
	return JSON.parse_string(JSON.stringify(game.campaign_session.campaign.snapshot(), "", true, true))

func fight_current() -> bool:
	if not check_row(): return false
	shadow = Battle.new(int(game.campaign_session.campaign.scenario().seed), game.campaign_session.campaign.scenario().map, game.campaign_session.campaign.scenario().hero, game.campaign_session.campaign.scenario().enemy_class, game.campaign_session.campaign.scenario().deck, game.campaign_session.campaign.scenario().enemy_deck, 90)
	var config: Dictionary = game.campaign_session.campaign.scenario()
	shadow.set_commander_identity(1, config.enemy_name, config.enemy_portrait)
	shadow.configure_objective(config.get("control", {}))
	cursor = 0
	await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
	check(game.campaign_active and game.campaign_session.encounter == game.battle and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "new campaign battle starts with untouched authored state")
	while cursor < row.trace.size() and failures == 0:
		if int(row.trace[cursor].side) == 1: advance_shadow(); continue
		if not await wait_for_player(): return false
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "live enemy actions agree with the current continuous diagnostic")
		if failures > 0: return false
		await player_action(Replay.action_from(row.trace[cursor].action))
		advance_shadow()
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "visible player input performs the expected legal action")
	if failures > 0: return false
	if not await wait_for_player(): return false
	await create_timer(0.8).timeout
	check(game.battle.winner == int(row.winner) and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "terminal result comes from the complete native battle")
	check(portable_progress() == row.story_after, "native outcome commits exactly the earned story state")
	await capture("v028-continuous-" + row.scenario + ("-victory" if row.winner == 0 else "-defeat"))
	total_actions += cursor; game_index += 1
	print("NATIVE CONTINUOUS BATTLE: %s | WINNER %d | ACTIONS %d" % [row.scenario, row.winner, cursor])
	await click(game.get_node("%PlayAgain").get_global_rect().get_center())
	check(game.story_view.visible, "actual result button returns to the earned story or retry page")
	return row.winner == 0 and failures == 0

func check_row() -> bool:
	check(game_index < continuous_report.games.size(), "every battle has a continuous diagnostic record")
	if failures > 0: return false
	row = continuous_report.games[game_index]
	check(row.scenario == game.campaign_session.current().scenario, "actual story determines the next battle")
	check(portable_progress() == row.story_before, "no chapter, dialogue or earlier battle was skipped")
	return failures == 0

func writer() -> void:
	var start: Button = button(game.council, "新战役")
	check(start != null, "native menu exposes new campaign")
	if failures > 0: return
	await click(start.get_global_rect().get_center())
	check(game.story_view.visible and game.campaign_session.campaign.completed.is_empty() and game.campaign_session.campaign.story.state.history.is_empty(), "new campaign opens at its first unread line")
	await capture("v028-continuous-opening")
	while failures == 0 and read_ids.size() < 5000:
		var page: Dictionary = game.campaign_session.current()
		match String(page.type):
			"dialogue":
				read_ids.append(page.line_id)
				await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
			"choice":
				check(choice_index < continuous_report.choices.size(), "native choice exists in the declared route")
				if failures > 0: return
				var expected: Dictionary = continuous_report.choices[choice_index]
				check(expected.node == page.node and expected.chapter == game.campaign_session.campaign.story.graph.id, "choice is reached in narrative order")
				var selected: int = -1
				for index: int in range(page.options.size()):
					if page.options[index].id == expected.option: selected = index
				check(selected >= 0, "declared choice is actually displayed")
				if failures > 0: return
				await click(game.story_view.actions.get_child(selected).get_global_rect().get_center()); choice_index += 1
			"battle":
				if not await fight_current(): break
			"end":
				if game.campaign_session.campaign.next_chapter().is_empty(): break
				await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
	if failures > 0: return
	check(read_ids == continuous_report.dialogue_ids and choice_index == continuous_report.choices.size(), "native route read exactly the continuous pages and choices")
	check(game_index == continuous_report.games.size() and continuous_report.stop == "defeat", "all recorded encounters were genuinely played up to the first defeat")
	check(portable_progress() == continuous_report.progress, "native route stops at the same complete campaign state")
	check(game.story_view.text_body.text.contains("上一战失利") and game.story_view.actions.get_child(0).text == "重新出征", "failed battle offers retry without pretending the story advanced")
	await capture("v028-continuous-retry")
	var file := FileAccess.open(CONTINUOUS_CURSOR, FileAccess.WRITE)
	check(file != null, "record native process handoff")
	if file == null: return
	file.store_string(JSON.stringify({"report_sha256": FileAccess.get_sha256(REPORT), "progress": game.campaign_session.campaign.snapshot(), "actions": total_actions}, "\t", true, true)); file.close()
	print("NATIVE CONTINUOUS WRITER: %d CHECKS | FAILURES: %d | BATTLES: %d | ACTIONS: %d | DIALOGUES: %d" % [checks, failures, game_index, total_actions, read_ids.size()])
	if failures == 0: game.get_window().close_requested.emit()

func reader() -> void:
	var handoff: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTINUOUS_CURSOR))
	check(handoff.get("report_sha256", "") == FileAccess.get_sha256(REPORT), "independent native process reads the same diagnostic")
	var resume: Button = button(game.council, "继续战役")
	check(resume != null, "fresh native process offers continue campaign")
	if failures > 0: return
	await click(resume.get_global_rect().get_center())
	check(game.story_view.visible and portable_progress() == handoff.progress, "continue reloads the exact real defeat without duplicate attempts or rewards")
	check(game.campaign_session.encounter == null and game.campaign_session.current().last_outcome == "defeat", "completed lost battle is not resumed as an active encounter")
	var previous: Dictionary = game.campaign_session.campaign.snapshot()
	var config: Dictionary = game.campaign_session.campaign.scenario()
	shadow = Battle.new(int(config.seed), config.map, config.hero, config.enemy_class, config.deck, config.enemy_deck, 90)
	shadow.set_commander_identity(1, config.enemy_name, config.enemy_portrait); shadow.configure_objective(config.get("control", {}))
	await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
	check(game.campaign_session.encounter == game.battle and game.battle.winner == -1 and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "actual retry rebuilds the unchanged opening without free resources")
	check(game.campaign_session.campaign.snapshot() == previous, "starting a retry preserves earlier earned choices and does not record an unplayed result")
	await capture("v028-continuous-restarted-battle")
	print("NATIVE CONTINUOUS READER: %d CHECKS | FAILURES: %d | RETRY: %s" % [checks, failures, game.campaign_session.current().scenario])

func run() -> void:
	create_timer(900).timeout.connect(func() -> void: push_error("continuous native flow timeout"); quit(2))
	writing = OS.get_cmdline_user_args().has("--write")
	check(writing or OS.get_cmdline_user_args().has("--read"), "choose writer then reader")
	check(FileAccess.file_exists(REPORT), "run the continuous headless diagnostic before native validation")
	if failures > 0: quit(1); return
	continuous_report = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	check(continuous_report.get("coverage", "") == "continuous_campaign" and continuous_report.get("failures", -1) == 0 and continuous_report.route == "road", "native source is a valid continuous road-route diagnostic")
	if failures > 0: quit(1); return
	if writing:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(CONTINUOUS_SAVE + suffix): DirAccess.remove_absolute(CONTINUOUS_SAVE + suffix)
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/native_continuous_deck.json")
	game.campaign_session = Session.new(CONTINUOUS_SAVE)
	root.add_child(game); current_scene = game; await settle()
	if writing: await writer()
	else: await reader()
	if writing and failures == 0: return
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
