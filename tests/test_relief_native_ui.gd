extends "res://tests/test_campaign_playthrough_ui.gd"
## Isolate the third battle from the continuous report without forging a win.
const CONTINUOUS_REPORT = "res://.tools/continuous-campaign-road.json"

func run() -> void:
	create_timer(300).timeout.connect(func() -> void: push_error("relief native timeout"); quit(2))
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTINUOUS_REPORT))
	check(report.games.size() >= 3 and report.games[2].scenario == "c02_relief_bridge", "use the actual third continuous encounter")
	if failures > 0: quit(1); return
	row = report.games[2]
	var config: Dictionary = Campaign.new().index.scenarios.c02_relief_bridge
	shadow = Battle.new(config.seed, config.map, config.hero, config.enemy_class, config.deck, config.enemy_deck, 90)
	shadow.set_commander_identity(1, config.enemy_name, config.enemy_portrait)
	shadow.configure_objective(config.control)
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/relief_native_deck.json")
	game.campaign_session = Session.new("res://.tools/relief_native_campaign.json")
	root.add_child(game); current_scene = game; await settle()
	var live: Battle = Battle.new(config.seed, config.map, config.hero, config.enemy_class, config.deck, config.enemy_deck, 90)
	live.set_commander_identity(1, config.enemy_name, config.enemy_portrait); live.configure_objective(config.control)
	game._new_match(config.seed, live); game.has_started = true; game.council.hide()
	if not game.expanded_battlefield: game._toggle_battlefield()
	await settle()
	check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "unchanged scenario opening")
	while cursor < row.trace.size() and failures == 0:
		if int(row.trace[cursor].side) == 1: advance_shadow(); continue
		if not await wait_for_player(): break
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "enemy AI reaches the expected position")
		if failures > 0: break
		await player_action(Replay.action_from(row.trace[cursor].action))
		advance_shadow()
		if row.trace[cursor - 1].action.type != "end_turn":
			check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "visible player action matches the model")
	await wait_for_player()
	check(game.battle.winner == 1 and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "real objective deadline defeat matches complete model trace")
	await capture("v030-relief-deadline")
	print("RELIEF NATIVE: %d CHECKS | FAILURES: %d | ACTIONS: %d" % [checks, failures, cursor])
	game.queue_free(); await process_frame; quit(0 if failures == 0 else 1)
