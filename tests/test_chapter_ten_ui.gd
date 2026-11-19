extends "res://tests/test_campaign_playthrough_ui.gd"
## Native pointer replay from a real ten-win campaign save, followed by a
## separate OS process that reads the earned tenth-chapter ending.
var plan: String = "joint"
var source_save: String = ""
var tenth_lines: int = 0

func writer() -> void:
	var resume: Button = button(game.council, "继续战役")
	check(resume != null, "real prior campaign offers continue")
	if failures > 0: return
	await click(resume.get_global_rect().get_center())
	check(game.campaign_session.campaign.story.graph.id == "chapter_09" and game.campaign_session.current().type == "end", "actual ten-win save resumes at ninth ending")
	check(game.campaign_session.campaign.story.state.flags.governance_plan == plan, "real save carries selected plan")
	if failures > 0: return
	await click(button(game.story_view.actions, "进入").get_global_rect().get_center())
	check(game.campaign_session.campaign.story.graph.id == "chapter_10" and game.campaign_session.campaign.completed.size() == 9, "ninth chapter advances to tenth from actual history")
	for step: int in range(200):
		var page: Dictionary = game.campaign_session.current()
		if page.type == "battle": break
		check(page.type == "dialogue" and game.story_view.text_body.text == page.text, "native tenth opening shows source paragraph")
		if failures > 0: return
		tenth_lines += 1
		await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
	check(game.campaign_session.current().type == "battle" and game.campaign_session.current().scenario == "c10_gate", "actual history reaches tower gate")
	var config: Dictionary = game.campaign_session.campaign.scenario()
	check(config.map == "towergate" and config.hero == {"joint": "warden", "split": "pyromancer", "hold": "grove"}[plan], "inherited plan determines real battle setup")
	check(int(config.control.round_limit) == {"joint": 18, "split": 16, "hold": 20}[plan] and int(config.control.cells[0][0]) == 3, "deadline and bridgehead are authored")
	if failures > 0: return
	shadow = Battle.new(int(config.seed), config.map, config.hero, config.enemy_class, config.deck, config.enemy_deck, 90)
	shadow.set_commander_identity(1, config.enemy_name, config.enemy_portrait)
	shadow.configure_objective(config.get("control", {}))
	await capture("v034-" + plan + "-gate-briefing")
	await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
	check(game.battle.turn == 1 and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "actual native battle begins at exact benchmark state")
	if failures > 0: return
	while cursor < row.trace.size():
		if int(row.trace[cursor].side) == 1:
			advance_shadow()
			continue
		if not await wait_for_player(): return
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "native opponent resolves expected public state")
		if failures > 0: return
		var action: Dictionary = Replay.action_from(row.trace[cursor].action)
		await player_action(action)
		advance_shadow()
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "pointer action matches legal shadow action")
		if failures > 0: return
	await wait_for_player()
	await create_timer(0.8).timeout
	check(game.battle.winner == 0 and game.battle.turn == int(row.turn), "actual native gate battle wins on recorded turn")
	check(game.campaign_session.current().node == "after" and game.campaign_session.campaign.story.state.flags.tower_gate_secured, "real victory unlocks only earned gate aftermath")
	if failures > 0: return
	await capture("v034-" + plan + "-gate-victory")
	await click(game.get_node("%PlayAgain").get_global_rect().get_center())
	for step: int in range(200):
		var page: Dictionary = game.campaign_session.current()
		if page.type == "end": break
		check(page.type == "dialogue" and game.story_view.text_body.text == page.text, "earned aftermath displays native source text")
		if failures > 0: return
		tenth_lines += 1
		await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
	check(game.campaign_session.current().type == "end" and game.campaign_session.campaign.story.graph.id == "chapter_10", "real battle reaches authored chapter ending")
	check(game.campaign_session.save().ok, "earned end is saved to disk")
	await capture("v034-" + plan + "-gate-ending")
	print("TENTH NATIVE WRITER: %d CHECKS | FAILURES: %d | PLAN: %s | ACTIONS: %d | PARAGRAPHS: %d" % [checks, failures, plan, cursor, tenth_lines])

func reader() -> void:
	var resume: Button = button(game.council, "继续战役")
	check(resume != null, "independent process offers actual tenth ending")
	if failures > 0: return
	await click(resume.get_global_rect().get_center())
	var campaign: RefCounted = game.campaign_session.campaign
	check(game.story_view.visible and game.campaign_session.encounter == null and campaign.story.graph.id == "chapter_10" and game.campaign_session.current().type == "end", "independent process restores earned ending")
	check(campaign.completed.size() == 9 and campaign.story.state.flags.governance_plan == plan and campaign.story.state.flags.tower_gate_secured, "all earlier chapters, plan and gate victory persist")
	await capture("v034-" + plan + "-gate-resumed")
	print("TENTH NATIVE READER: %d CHECKS | FAILURES: %d | PLAN: %s" % [checks, failures, plan])

func run() -> void:
	create_timer(720).timeout.connect(func() -> void: push_error("tenth native UI timeout"); quit(2))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--plan="): plan = arg.trim_prefix("--plan=")
	writing = OS.get_cmdline_user_args().has("--write")
	check(plan in ["joint", "split", "hold"] and (writing or OS.get_cmdline_user_args().has("--read")), "choose supported governance and process mode")
	if failures > 0: quit(1); return
	source_save = "res://.tools/v033-native-chapter-nine-" + plan + ".json"
	var save_path: String = "res://.tools/v034-native-chapter-ten-" + plan + ".json"
	var trace_path: String = "res://.tools/v034-" + plan + "-final-benchmark.json"
	check(FileAccess.file_exists(source_save) and FileAccess.file_exists(trace_path), "actual prior save and winning gate trace exist")
	if failures > 0: quit(1); return
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(trace_path))
	for candidate: Dictionary in report.games:
		if candidate.scenario == "c10_" + plan + "_gate": row = candidate
	check(not row.is_empty() and row.winner == 0, "selected plan has a real initial state winning trace")
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v034-native-deck.json")
	game.campaign_session = Session.new(save_path)
	root.add_child(game); current_scene = game; await settle()
	if writing: await writer()
	else: await reader()
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
