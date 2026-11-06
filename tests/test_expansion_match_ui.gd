extends "res://tests/test_campaign_playthrough_ui.gd"
## Full native skirmish from untouched initial resources. The fixed first
## matchup is declared before running the suite, including when it loses.
const Model = preload("res://scripts/battle.gd")
func run() -> void:
	create_timer(600).timeout.connect(func() -> void: push_error("native expansion match timeout"); quit(2))
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.tools/expansion-matchups-v029.json"))
	check(report.get("failures", -1) == 0 and report.rules == Snapshot.rules_signature(), "complete expansion diagnostic matches the current rules")
	if failures > 0: quit(1); return
	row = report.games[0]
	check(row.map == "greenwood" and row.expansion_side == 0 and row.opponent == "balanced" and row.seed == 2901, "native test uses the predetermined first matchup, without choosing a winner")
	shadow = Model.new(2901, "greenwood", "warden", "warden", "ambush", "balanced", 90)
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/expansion_match_deck.json")
	game.campaign_session = Session.new("res://.tools/expansion_match_campaign.json")
	root.add_child(game); current_scene = game; await settle()
	game._new_match(2901, Model.new(2901, "greenwood", "warden", "warden", "ambush", "balanced", 90))
	game.has_started = true; game.council.hide()
	if not game.expanded_battlefield: game._toggle_battlefield()
	await settle()
	check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "unmodified ordinary thirty-card initial state")
	await capture("v029-expansion-match-opening")
	var armed_saved: bool = false
	while cursor < row.trace.size() and failures == 0:
		if int(row.trace[cursor].side) == 1: advance_shadow(); continue
		if not await wait_for_player(): break
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "real enemy AI reaches recorded expansion position")
		if failures > 0: break
		await player_action(Replay.action_from(row.trace[cursor].action))
		advance_shadow()
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "native hand/board input matches expansion rules")
		if not armed_saved and game.battle.Traps.count(game.battle, 0) > 0:
			await create_timer(0.9).timeout
			await capture("v029-expansion-match-armed")
			armed_saved = true
	if failures == 0:
		await wait_for_player(); await create_timer(0.8).timeout
		check(game.battle.winner == int(row.winner) and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "complete native expansion game reaches its real terminal result")
		check(armed_saved, "new hand trap was actually deployed during this normal match")
		check(Snapshot.validate(Snapshot.capture(game.battle)).ok, "final native card zones and full state remain valid")
		await capture("v029-expansion-match-result")
	print("EXPANSION NATIVE MATCH: %d CHECKS | FAILURES: %d | ACTIONS: %d | WINNER: %d | TURN: %d" % [checks, failures, cursor, game.battle.winner, game.battle.turn])
	game.queue_free(); await process_frame; quit(0 if failures == 0 else 1)
