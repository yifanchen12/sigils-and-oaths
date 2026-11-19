extends "res://tests/test_campaign_playthrough_ui.gd"

const Settings = preload("res://scripts/settings_store.gd")
const PRIMARY := "res://.tools/v049-native-replay-main.json"
const SOURCE := "res://tests/fixtures/v048-completed-main.json"
const ACTIVE_PRIMARY := "res://.tools/v049-native-active-main.json"
const ACTIVE_SOURCE := "res://tests/fixtures/v047-court-encounter.json"
const BRANCH_TRACE := "res://.tools/v049-replay-trace.json"
var primary_path: String = PRIMARY
var main_hash: String
var backup_hash: String

func branch_path() -> String:
	return Session.replay_path(primary_path)

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	create_timer(180.0, true, false, true).timeout.connect(func() -> void:
		push_error("Native chapter replay timed out")
		quit(2))
	var check_active_main: bool = args.has("--active")
	if not args.has("--open") and not args.has("--finish") and not args.has("--verify") and not check_active_main:
		push_error("Choose one chapter replay acceptance stage")
		quit(2)
		return
	Engine.time_scale = 3.0
	DisplayServer.window_set_size(Vector2i(1008, 700))
	var fixture: String = ACTIVE_SOURCE if check_active_main else SOURCE
	if check_active_main: primary_path = ACTIVE_PRIMARY
	if args.has("--open") or check_active_main:
		for destination: String in [primary_path, primary_path + ".bak"]:
			check(DirAccess.copy_absolute(ProjectSettings.globalize_path(fixture), ProjectSettings.globalize_path(destination)) == OK, "use the earned main fixture in an isolated slot")
		for suffix: String in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(branch_path() + suffix): DirAccess.remove_absolute(branch_path() + suffix)
	main_hash = FileAccess.get_sha256(primary_path)
	backup_hash = FileAccess.get_sha256(primary_path + ".bak")
	check(main_hash == FileAccess.get_sha256(fixture), "native acceptance starts with the verified prior save")
	if failures > 0: quit(1); return
	if not check_active_main:
		row = JSON.parse_string(FileAccess.get_file_as_string(BRANCH_TRACE))
		var restored: Dictionary = Snapshot.restore(row.initial)
		check(restored.ok, "actual branch initial encounter fixture validates")
		if not restored.ok: quit(1); return
		shadow = restored.battle
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v049-native-replay-deck.json")
	game.settings_store = Settings.new("user://v049-replay-native-settings.cfg")
	check(game.settings_store.save_preferences({"reading_size": 130, "music": 0, "effects": 0}).ok, "use real 130 percent reading preferences")
	game.campaign_session = Session.new(primary_path)
	root.add_child(game)
	current_scene = game
	await settle()
	if check_active_main: await verify_active_main()
	elif args.has("--open"): await open_first_branch()
	elif args.has("--finish"): await resume_and_finish()
	else: await verify_slots()
	check(FileAccess.get_sha256(primary_path) == main_hash and FileAccess.get_sha256(primary_path + ".bak") == backup_hash, "the main save, including its backup, stays byte-for-byte unchanged")
	print("CHAPTER REPLAY NATIVE %d CHECKS | %d FAILURES | %s | BATTLE ACTIONS %d" % [checks, failures, ",".join(args), cursor])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func click_control(node: Control) -> void:
	await click(node.get_global_rect().get_center())

func open_first_branch() -> void:
	var view: Control = game.replay_view
	await click_control(game.council.replay_button)
	check(view.visible and view.chapters.item_count == 18 and view.unlocked_count.text.contains("18 / 18"), "real menu shows all chapters earned by the main save")
	check(view.selected_chapter() == "chapter_18" and view.continue_button.disabled, "chapter list offers the most recent completed chapter and empty branch state")
	var bounds: Rect2 = root.get_visible_rect().grow(1)
	for control: Control in [view.shell, view.chapters, view.start_button, view.continue_button, view.close_button]:
		check(bounds.encloses(control.get_global_rect()), "replay control is visible at 1008 by 700")
	if failures > 0: return
	await key(KEY_UP)
	check(view.selected_chapter() == "chapter_17", "keyboard can select chapter seventeen in the live list")
	if failures > 0: return
	await capture("v049-chapter-replay-small")
	await click_control(view.start_button)
	check(game.story_view.visible and game.story_view.heading.text.begins_with("分支") and game.campaign_session.campaign.story.graph.id == "chapter_17", "separate branch starts on the actual first line")
	if failures > 0: return
	if not await read_to("kit"): return
	if not await choose_story_option("screen"): return
	if not await read_to("screen_battle"): return
	await click_control(game.story_view.actions.get_child(0))
	check(game.battle != null and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "branch entered exact normal rescue match")
	check(game.get_node("%MapName").get_parent().subtitle_text().begins_with("分支"), "battle header shows the active save")
	if failures > 0: return
	DisplayServer.window_set_size(Vector2i(1296, 900))
	await settle()
	if not await play_until(int(row.checkpoint_at)): return
	await click_control(game.get_node("%Restart"))
	var saved: Dictionary = Session.Store.new(branch_path()).load_progress()
	check(game.council.visible and saved.ok and not saved.encounter.is_empty(), "menu saves the branch mid-battle")
	if saved.ok and not saved.encounter.is_empty():
		check(saved.encounter.battle.turn == shadow.turn and saved.progress.chapter_id == "chapter_17", "separate file contains earned match checkpoint")

func resume_and_finish() -> void:
	DisplayServer.window_set_size(Vector2i(1296, 900))
	await settle()
	var view: Control = game.replay_view
	await click_control(game.council.replay_button)
	check(view.visible and not view.continue_button.disabled and view.branch_status.text.contains("战斗中"), "fresh process discovers the in-progress branch")
	if failures > 0: return
	await click_control(view.continue_button)
	for _i: int in range(int(row.checkpoint_at)):
		if not advance_model(): return
	check(game.has_started and Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "visible resume restores the same legal battle state")
	if failures > 0: return
	if not await play_until(row.trace.size()): return
	check(game.battle.winner == 0 and game.battle.objective.streak == 3 and game.get_node("%ResultOverlay").visible, "native controls complete all evacuation points")
	if failures > 0: return
	await click_control(game.get_node("%PlayAgain"))
	if not await read_to("covenant"): return
	if not await choose_story_option("hold"): return
	if not await read_to("hold_end"): return
	check(game.story_view.heading.text.contains("分支") and game.campaign_session.campaign.story.state.flags.rescue_kit == "screen", "read and earn the alternative ending via actual victory")
	DisplayServer.window_set_size(Vector2i(1008, 700))
	await settle()
	await capture("v049-replayed-hold-ending")

func verify_slots() -> void:
	var view: Control = game.replay_view
	var resume: Button = button(game.council, "继续战役")
	check(resume != null, "main resume available at launch")
	if resume == null: return
	await click_control(resume)
	check(game.campaign_session.current().node == "joint_end" and not game.story_view.heading.text.contains("分支"), "main opens original ending after branch completion")
	if failures > 0: return
	await click_control(game.story_view.actions.get_child(0))
	check(view.visible and view.selected_chapter() == "chapter_18" and not view.continue_button.disabled, "original epilogue has a direct chapter replay entry")
	if failures > 0: return
	var previous: String = FileAccess.get_sha256(branch_path())
	await click_control(view.start_button)
	check(game.replay_confirmation.visible, "existing branch requires confirmation before replacement")
	if failures > 0: return
	await click_dialog_button(game.replay_confirmation, game.replay_confirmation.get_cancel_button())
	check(view.visible and not game.replay_confirmation.visible and FileAccess.get_sha256(branch_path()) == previous, "cancel saves the branch verbatim")
	if failures > 0: return
	await click_control(view.continue_button)
	check(game.campaign_session.current().node == "hold_end" and game.story_view.heading.text.contains("分支"), "other ending persists across two native exits")
	if failures > 0: return
	await key(KEY_ESCAPE)
	check(game.council.visible, "branch can return to standard battle council")
	await click_control(resume)
	check(game.campaign_session.current().node == "joint_end", "switch back to the main ending in the same process")
	if failures > 0: return
	await click_control(game.story_view.actions.get_child(0))
	await click_control(view.start_button)
	await click_dialog_button(game.replay_confirmation, game.replay_confirmation.get_ok_button())
	check(game.story_view.visible and game.story_view.heading.text.contains("分支") and game.campaign_session.current().node == "house", "confirmation replaces only the branch with the selected chapter's start")

func verify_active_main() -> void:
	var resume: Button = button(game.council, "继续战役")
	await click_control(resume)
	check(game.has_started and game.battle.turn == 3 and game.campaign_session.current().scenario == "c06_court", "original match opens from released 0.47 archive")
	if failures > 0: return
	await click_control(game.get_node("%Restart"))
	var paused: Dictionary = Replay.state_without_clock(game.battle)
	var time_at_pause: float = game.battle.time_remaining
	main_hash = FileAccess.get_sha256(primary_path)
	backup_hash = FileAccess.get_sha256(primary_path + ".bak")
	await click_control(game.council.replay_button)
	var view: Control = game.replay_view
	check(view.selected_chapter() == "chapter_05" and view.chapters.is_item_disabled(5), "active chapter and future entries are locked")
	if failures > 0: return
	await click_control(view.start_button)
	check(game.story_view.visible and game.campaign_session.campaign.story.graph.id == "chapter_05", "open a completed chapter while the original battle rests")
	await click_control(game.story_view.actions.get_child(0))
	await key(KEY_ESCAPE)
	await click_control(resume)
	check(game.has_started and game.campaign_session.current().scenario == "c06_court" and Replay.state_without_clock(game.battle) == paused, "return activates original board and restores its exact state")
	check(game.battle.time_remaining <= time_at_pause and game.battle.time_remaining > time_at_pause - 3.0, "main clock resumes from the saved pause")
	check(not game.get_node("%MapName").get_parent().subtitle_text().begins_with("分支"), "original battle displays its correct slot")

func click_dialog_button(dialog: Window, target: Button) -> void:
	if dialog.is_embedded():
		await click(Vector2(dialog.position) + target.get_global_rect().get_center())
	else:
		var center: Vector2 = target.get_global_rect().get_center()
		for pressed: bool in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = center
			event.button_index = MOUSE_BUTTON_LEFT
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			event.pressed = pressed
			dialog.push_input(event, true)
		await settle()

func read_to(target_node: String) -> bool:
	for _i: int in range(310):
		var page: Dictionary = game.campaign_session.current()
		if page.node == target_node: return true
		if page.type != "dialogue" and (page.type != "end" or page.get("next_chapter", {}).is_empty()):
			check(false, "route encountered unexpected page " + str(page.node))
			return false
		await click_control(game.story_view.actions.get_child(0))
	check(false, "cannot reach " + target_node)
	return false

func choose_story_option(id: String) -> bool:
	var page: Dictionary = game.campaign_session.current()
	for index: int in range(page.get("options", []).size()):
		if page.options[index].id != id: continue
		await click_control(game.story_view.actions.get_child(index))
		return true
	check(false, "missing branch choice " + id)
	return false

func advance_model() -> bool:
	var action: Dictionary = Replay.action_from(row.trace[cursor].action)
	var result: Dictionary = shadow.apply_action(action)
	check(result.ok, "recorded branch action is legal")
	cursor += 1
	return result.ok

func play_until(count: int) -> bool:
	while cursor < count and failures == 0:
		var step: Dictionary = row.trace[cursor]
		if step.side == 0:
			if not await wait_for_player(): return false
			check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "live match matches the legal replay up to player command")
			if failures > 0: return false
			await player_action(Replay.action_from(step.action))
		if not advance_model(): return false
	if not await wait_for_player(): return false
	check(Replay.state_without_clock(game.battle) == Replay.state_without_clock(shadow), "the visible board agrees at the end of this stage")
	return failures == 0
