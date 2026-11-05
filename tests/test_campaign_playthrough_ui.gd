extends "res://tests/test_unit_skills_ui.gd"
## Two independent native processes. Previous chapter victories are narrative
## fixtures only; this encounter is played from its untouched initial state.
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const Replay = preload("res://tests/test_campaign_replays.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const SAVE: String = "res://.tools/native_encounter_playthrough.json"
const CURSOR: String = "res://.tools/native_encounter_cursor.json"
var row: Dictionary
var shadow: Battle
var cursor: int = 0
var writing: bool = false

func checkpoint() -> RefCounted:
	var campaign: RefCounted = Campaign.new(); campaign.start()
	while true:
		var page: Dictionary = campaign.story.current()
		if campaign.story.graph.id == "chapter_03" and page.type == "battle": return campaign
		match page.type:
			"dialogue": campaign.story.advance(page.revision)
			"choice": campaign.story.choose(page.options[0].id, page.revision)
			"battle": campaign.story.resolve_battle(0, page.revision)
			"end": campaign.advance_chapter()
	return campaign

func button(parent: Node, caption: String) -> Button:
	if parent is Button and parent.text.contains(caption): return parent
	for child: Node in parent.get_children():
		var found: Button = button(child, caption)
		if found != null: return found
	return null

func wait_for_player() -> bool:
	var deadline: int = Time.get_ticks_msec() + 30000
	while game.battle.winner == -1 and (game.battle.active_side != 0 or game.ai_running or game.board.is_presenting()):
		if Time.get_ticks_msec() >= deadline: check(false, "live AI/animation completes within bounded time"); return false
		await create_timer(0.03).timeout
	# The turn-end refresh rebuilds cards; container layout is deferred until
	# the next frame. Wait for real screen positions before pointer input.
	await settle()
	return true

func click_cell(cell: Vector2i) -> void:
	await click(game.board.global_position + game.board.cell_center(cell))

func player_action(action: Dictionary) -> void:
	# Use visible card, skill, turn buttons and real board pointer events.
	match String(action.type):
		"play":
			var found: Button = null
			for view: Control in game.get_node("%CompactHand").get_children():
				if view.card_uid == action.card_uid: found = view; break
			check(found != null and found.is_visible_in_tree(), "recorded card is in the real hand")
			if found == null: return
			await click(found.get_global_rect().get_center())
			if action.target != Vector2i(-1, -1):
				check(game.selected_card == action.card_uid, "visible pointer selects the intended card")
				if game.selected_card != action.card_uid: return
				await click_cell(action.target)
		"move", "attack", "unit_skill":
			var unit: Dictionary = game.battle.get_unit(action.unit_id)
			check(not unit.is_empty(), "recorded actor still exists")
			if unit.is_empty(): return
			await click_cell(unit.pos)
			if action.type == "unit_skill":
				await click(game.unit_skill_button.get_global_rect().get_center())
				if unit.kind not in ["sword", "spear"]: await click_cell(action.target)
			else: await click_cell(action.target)
		"hero":
			await click(game.get_node("%ViewSkill").get_global_rect().get_center())
			if action.target != Vector2i(-1, -1): await click_cell(action.target)
		"end_turn": await click(game.get_node("%ViewEnd").get_global_rect().get_center())

func advance_shadow() -> void:
	var step: Dictionary = row.trace[cursor]
	shadow.advance_clock(float(step.elapsed))
	check(shadow.apply_action(Replay.action_from(step.action)).ok, "shadow trace remains legal")
	cursor += 1

func run() -> void:
	create_timer(180).timeout.connect(func() -> void: push_error("native encounter playthrough timeout"); quit(2))
	writing = OS.get_cmdline_user_args().has("--write")
	if not writing and not OS.get_cmdline_user_args().has("--read"): check(false, "choose writer then reader"); quit(1); return
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Replay.PATH))
	for candidate: Dictionary in report.games:
		if candidate.scenario == "c03_vent": row = candidate
	var campaign: RefCounted = checkpoint()
	var config: Dictionary = campaign.scenario()
	shadow = Battle.new(int(config.seed), config.map, config.hero, config.enemy_class, config.deck, config.enemy_deck, 90)
	shadow.set_commander_identity(1, config.enemy_name, config.enemy_portrait); shadow.configure_objective(config.control)
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/native_play_deck.json")
	game.campaign_session = Session.new(SAVE)
	if writing:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(SAVE + suffix): DirAccess.remove_absolute(SAVE + suffix)
		game.campaign_session.campaign = campaign
		check(game.campaign_session.save().ok, "save narrative-only encounter checkpoint")
		game.campaign_active = true
	root.add_child(game); current_scene = game; await settle()
	if writing:
		game._show_story(); await settle()
		await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
		check(game.battle.turn == 1 and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "native encounter starts with exact authored resources, card order and empty army")
	else:
		var resume: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CURSOR))
		var loaded: RefCounted = Session.new(SAVE)
		check(loaded.load_campaign().ok and loaded.encounter != null, "new native process can load full saved battle")
		if loaded.encounter == null: quit(1); return
		check(Snapshot.capture(loaded.encounter).time_remaining == resume.snapshot.time_remaining, "saved real-time clock survives process exit")
		while cursor < int(resume.cursor): advance_shadow()
		check(Replay.state_without_clock(loaded.encounter) == Replay.state_without_clock(shadow), "exit saved the expected unmodified enemy-turn position")
		var continue_button: Button = button(game.council, "继续战役")
		check(continue_button != null, "native continue button exists")
		await click(continue_button.get_global_rect().get_center())
		check(game.campaign_active and game.ai_running and game.battle.active_side == 1, "native continue resumes the pending enemy AI turn")
	while cursor < row.trace.size():
		if int(row.trace[cursor].side) == 1:
			advance_shadow()
			continue
		if not await wait_for_player(): break
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "actual enemy AI reaches the expected public position")
		if failures > 0: break
		var action: Dictionary = Replay.action_from(row.trace[cursor].action)
		await player_action(action)
		advance_shadow()
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "native player input executes the recorded legal action")
		if failures > 0:
			var diagnostic: FileAccess = FileAccess.open("res://.tools/native-play-failure.json", FileAccess.WRITE)
			diagnostic.store_string(JSON.stringify({"cursor": cursor, "action": action, "actual": Snapshot.capture(game.battle), "expected": Snapshot.capture(shadow)}, "\t", true, true)); diagnostic.close()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.tools/native-play-failure.png")
			break
		if writing and game.battle.turn == 8 and game.battle.active_side == 1:
			game._open_council(); await settle()
			check(game.campaign_session.save().ok and game.battle.active_side == 1, "menu pauses and saves before pending AI action")
			var file: FileAccess = FileAccess.open(CURSOR, FileAccess.WRITE)
			check(file != null, "write independent-process continuation cursor")
			if file == null: quit(1); return
			file.store_string(JSON.stringify({"cursor": cursor, "snapshot": Snapshot.capture(game.battle)}, "", true, true)); file.close()
			await capture("campaign-native-before-exit")
			print("NATIVE PLAYTHROUGH WRITER: %d CHECKS | FAILURES: %d | ACTIONS: %d | ENEMY TURN: %d" % [checks, failures, cursor, game.battle.turn])
			if failures > 0: quit(1); return
			# Same handler as the real window close signal; next invocation starts
			# a different OS process and loads the on-disk save through the menu.
			game.get_window().close_requested.emit()
			return
	if writing: check(false, "writer reached intended exit checkpoint")
	else:
		await wait_for_player()
		await create_timer(0.8).timeout
		check(game.battle.winner == 0 and game.battle.objective.streak == 2 and game.battle.turn == 17, "real native battle wins by control from its initial state")
		check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "final native state matches independently replayed rules result")
		check(game.campaign_session.current().node == "vent_after" and game.campaign_session.campaign.story.state.flags.supply_route == "maintenance", "actual victory advances and saves only the selected story branch")
		await capture("campaign-native-control-victory")
		await click(game.get_node("%PlayAgain").get_global_rect().get_center())
		check(game.story_view.visible and game.story_view.page.line_id == "c03.vent_after.01", "real continue-story button opens postbattle prose")
		await capture("campaign-native-victory-story")
		var fresh: RefCounted = Session.new(SAVE)
		check(fresh.load_campaign().ok and fresh.current().line_id == "c03.vent_after.01" and fresh.encounter == null, "saved victory resumes as dialogue without replaying rewards")
	print("NATIVE PLAYTHROUGH %s: %d CHECKS | FAILURES: %d | ACTIONS: %d | DISPLAY: %s" % ["WRITER" if writing else "READER", checks, failures, cursor, DisplayServer.get_name()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
