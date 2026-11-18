extends "res://tests/test_ui.gd"
## Real scene inputs and a private settings/campaign path, including a second main scene.

const Preferences = preload("res://scripts/settings_store.gd")
const Campaign = preload("res://scripts/campaign_session.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Course = preload("res://scripts/training.gd")
const SETTINGS_PATH = "user://test-native-v042-settings.cfg"
const CAMPAIGN_PATH = "user://test-native-v042-campaign.json"

func clear_fixtures() -> void:
	for path: String in [SETTINGS_PATH, CAMPAIGN_PATH]:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func open_scene() -> void:
	game = MainScene.instantiate()
	game.settings_store = Preferences.new(SETTINGS_PATH)
	game.campaign_session = Campaign.new(CAMPAIGN_PATH)
	root.add_child(game)
	current_scene = game
	await settle()

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await settle()

func select_hand(card_id: String) -> void:
	for card: CardView in game.get_node("%CompactHand").get_children():
		if card.card.id != card_id: continue
		await click(card.get_global_rect().get_center())
		return
	check(false, "missing visible card " + card_id)

func cell(at: Vector2i) -> void:
	await click(game.board.global_position + game.board.cell_center(at))

func run() -> void:
	clear_fixtures()
	if DisplayServer.get_name() != "headless": AudioServer.set_bus_mute(0, true)
	await open_scene()
	check(game.council.training_button.visible and game.council.settings_button.visible, "public entry points on the first screen")
	check(game.audio.scene_index == 0 and game.audio.music_players[0].stream.get_length() > 60.0, "music controller starts with the council composition")
	await click(game.council.settings_button.get_global_rect().get_center())
	check(game.options.visible and not game._player_can_act(), "settings are an exclusive window")
	game.options.reading.select(2)
	game.options.effects.value = 0
	await click_window(game.options, game.options.motion.get_global_rect().get_center())
	await capture("v042-settings.png", game.options)
	await click_window(game.options, game.options.get_ok_button().get_global_rect().get_center())
	check(not game.options.visible and game.settings.values.reading_size == 130 and game.board.reduced_motion, "save applies reading and motion immediately")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "effect mute and music are separate")
	await click(game.council.settings_button.get_global_rect().get_center())
	await click_window(game.options, game.options.defaults_button.get_global_rect().get_center())
	await click_window(game.options, game.options.get_cancel_button().get_global_rect().get_center())
	check(game.settings.values.reading_size == 130 and game.board.reduced_motion, "cancel discards the unsaved reset")

	game._new_campaign()
	await settle()
	check(game.story_view.visible and game.story_view.text_body.get_theme_font_size("normal_font_size") == 29, "story body uses the saved reading setting")
	var page_before: Dictionary = game.campaign_session.token()
	await click(game.story_view.settings_button.get_global_rect().get_center())
	await key(KEY_SPACE)
	check(game.options.visible and game.campaign_session.token() == page_before, "dialogue does not advance under modal settings")
	await click_window(game.options, game.options.get_cancel_button().get_global_rect().get_center())
	game._open_council()
	await settle()
	await click(game.council.start_button.get_global_rect().get_center())
	await click(game.get_node("%Restart").get_global_rect().get_center())
	var campaign_digest: String = FileAccess.get_sha256(CAMPAIGN_PATH)
	var course_entry_token: Dictionary = game.campaign_session.token()
	check(not campaign_digest.is_empty(), "an actual campaign checkpoint was written before training")
	var suspended: Battle = game.battle
	var old_state: Dictionary = Snapshot.capture(suspended)
	check(game.council.resume_button.visible, "there is a live skirmish before entering the course")
	await click(game.council.training_button.get_global_rect().get_center())
	check(game.training_panel.visible and game.training.lesson == 0 and game.battle != suspended, "lesson opens a separate battle from the real menu")
	check(game.audio.scene_index == 1 and game.audio.music_players[1].stream.get_length() > 55.0, "practice starts the battle composition")
	await create_timer(0.16).timeout
	check(game.battle.time_remaining == 90.0 and game.get_node("%TurnClock").text.contains("不限时"), "course does not spend real turn time")
	await key(KEY_F10)
	check(game.options.visible, "F10 opens the same settings from battle")
	await click_window(game.options, game.options.get_cancel_button().get_global_rect().get_center())
	await key(KEY_SPACE)
	check(game.training.step_index == 0 and game.battle.turn == 1, "out-of-order end turn leaves the lesson unchanged")
	await select_hand("spear")
	check(game.board.deploy.has(Course.DEPLOY) and game.board.training_target == Course.DEPLOY, "native deployment and guide point to the same grid cell")
	await capture("v042-training-deploy.png")
	await cell(Course.DEPLOY)
	check(game.training.step_index == 1 and game.battle.unit_at(Course.DEPLOY).summoning, "real deployment advances the lesson and leaves sickness")
	await click(game.get_node("%ViewEnd").get_global_rect().get_center())
	check(game.training.step_index == 2 and game.battle.turn == 3 and not game.battle.unit_at(Course.DEPLOY).summoning, "real side changes clear sickness")
	await cell(Course.DEPLOY)
	await cell(Course.SPEAR_PATH)
	check(game.training.step_index == 3 and game.board.motion_unit == -1, "reduced motion skips moving sprites while committing the same move")
	await cell(Course.CAVALRY)
	check(game.training.complete() and game.battle.unit_at(Course.CAVALRY).hp == 1 and game.battle.last_combat.counter_damage > 0, "first lesson observes counter damage and class/terrain modifiers")
	await click(game.training_panel.continue_button.get_global_rect().get_center())
	check(game.training.lesson == 1, "next lesson loads the interception fixture")
	await key(KEY_F10)
	game.options.effects.value = 50
	await click_window(game.options, game.options.get_ok_button().get_global_rect().get_center())
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "restoring effects reopens its own bus")
	await select_hand("oath_ward")
	await cell(Course.GUARD)
	check(game.battle.Traps.count(game.battle, 0) == 1, "trap paid and placed from the real hand")
	if DisplayServer.get_name() != "headless":
		check(game.audio.sfx.get_children().any(func(player: Node) -> bool: return player.playing and player.stream == game.audio.CUES.trap), "native trap playback is routed to the real effects player")
	await cell(Course.GUARD)
	await key(KEY_Q)
	await cell(Course.GUARD)
	check(game.training.step_index == 2 and game.battle.unit_at(Course.GUARD).guarding, "Q enters the production skill targeting flow")
	await click(game.get_node("%ViewEnd").get_global_rect().get_center())
	var saved_unit: Dictionary = game.battle.unit_at(Course.PROTECTED)
	check(game.training.complete() and saved_unit.hp == saved_unit.max_hp and game.battle.traps.is_empty(), "actual enemy attack is intercepted and consumes the ward")
	check(game.board.combat.forecast.intercepted and game.battle.unit_at(Course.GUARD).shield == 2, "guard receipt and post-hit shield are visible in real combat state")
	await click(game.training_panel.continue_button.get_global_rect().get_center())
	check(game.training.lesson == 2 and not game.battle.can_cast_at(Course.FIRE_CENTER, 0), "capstone center starts outside all friendly cast ranges")
	await cell(Course.MAGE_START)
	await cell(Course.MAGE_FINISH)
	check(game.battle.can_cast_at(Course.FIRE_CENTER, 0), "moving the mage extends legal spell coverage")
	await select_hand("last_hearth")
	hover(game.board.global_position + game.board.cell_center(Course.FIRE_CENTER))
	await settle()
	check(game.board.predicted_area.size() == 13 and game.board.predicted_losses.size() == 2, "real multi-target preview lights thirteen cells and two units")
	await capture("v042-training-cast.png")
	await cell(Course.FIRE_CENTER)
	check(game.training.complete() and game.battle.players[0].mana == 0 and game.battle.unit_at(Course.FIRE_EDGE).hp == 4 and game.battle.unit_at(Course.FIRE_SAFE).hp == 7, "capstone spends ten and hits only the proper footprint")
	await click(game.training_panel.continue_button.get_global_rect().get_center())
	check(game.training.lesson == 3 and game.training_panel.lesson_choice.item_count == 4 and game.board.predicted_area.size() == 13, "new lesson shows the public training blast")
	await select_hand("quiet_veil")
	await cell(Course.COUNTER_CENTER)
	var spear_uid: int = game.battle.unit_at(Course.COUNTER_CENTER).card.uid
	check(game.training.step_index == 1 and game.battle.Traps.count(game.battle, 0) == 1, "spell ward from the regular hand")
	await cell(Course.COUNTER_ARCHER)
	var unsafe := Vector2i(7, 6)
	var north := Vector2i(7, 4)
	var east := Vector2i(8, 5)
	check(game.battle.movement_cells(game.battle.unit_at(Course.COUNTER_ARCHER)).has(unsafe) and not game.board.moves.has(unsafe)
		and game.board.moves.has(north) and game.board.moves.has(east), "guide marks both legal escape routes")
	await capture("v044-counterplay-drill.png")
	await cell(unsafe)
	check(game.training.step_index == 1 and not game.battle.unit_at(Course.COUNTER_ARCHER).moved, "guided movement inside the warning area is rejected")
	await cell(north)
	check(game.training.step_index == 2 and game.battle.unit_at(north).kind == "archer", "a legal retreat advances course")
	await click(game.get_node("%ViewEnd").get_global_rect().get_center())
	var patient: Dictionary = game.battle.unit_at(Course.COUNTER_CENTER)
	check(game.training.step_index == 3 and patient.hp == 1 and game.battle.unit_at(north).hp == 4 and game.battle.traps.is_empty(),
		"actual ten-cost response consumes the ward and the dispersed unit avoids the hit")
	await select_hand("recall_writ")
	await cell(Course.COUNTER_CENTER)
	check(game.training.step_index == 4 and game.battle.unit_at(Course.COUNTER_CENTER).is_empty() and game.battle.hand_card(0, spear_uid).card_id == "spear",
		"the same wounded unit card returns to the real hand")
	await select_hand("spear")
	check(game.board.deploy.has(Course.DEPLOY) and game.board.deploy.all(func(where: Vector2i) -> bool: return game.training.outside_blast(game.battle, where)), "deployment guidance offers multiple safe cells")
	await cell(Course.DEPLOY)
	var healed: Dictionary = game.battle.unit_at(Course.DEPLOY)
	check(game.training.complete() and healed.hp == healed.max_hp and healed.summoning and game.board.predicted_area.is_empty(), "recall and new deployment restore health and apply summoning")
	await click(game.training_panel.continue_button.get_global_rect().get_center())
	check(game.council.visible and game.training == null and game.battle == suspended and Snapshot.capture(game.battle) == old_state, "completion resumes the identical suspended battle from its original menu")
	check(FileAccess.get_sha256(CAMPAIGN_PATH) == campaign_digest, "training left the campaign checkpoint bytes unchanged")
	check(game.campaign_session.token() == course_entry_token, "training left the campaign session at its original cursor")

	await stop_music_for_scene_change()
	game.queue_free()
	await settle()
	await open_scene()
	check(game.settings.values.reading_size == 130 and game.settings.values.effects == 50 and game.board.reduced_motion, "fresh main scene reloads saved player settings")
	check(game.campaign_session.load_campaign().ok and game.campaign_session.token().revision == page_before.revision, "campaign remains resumable after training")
	if DisplayServer.get_name() != "headless":
		await click(game.council.settings_button.get_global_rect().get_center())
		game.options.display.select(1)
		await click_window(game.options, game.options.get_ok_button().get_global_rect().get_center())
		check(root.mode == Window.MODE_FULLSCREEN, "display option enters native fullscreen")
		await key(KEY_F10)
		game.options.display.select(0)
		await click_window(game.options, game.options.get_ok_button().get_global_rect().get_center())
		check(root.mode == Window.MODE_WINDOWED, "retains a working return from fullscreen")
		root.size = Vector2i(1008, 700)
		await settle()
		await key(KEY_F10)
		check(game.options.visible and game.options.size.x <= root.size.x and game.options.size.y <= root.size.y, "settings window fits the minimum-size Windows layout")
		await click_window(game.options, game.options.get_cancel_button().get_global_rect().get_center())
	await stop_music_for_scene_change()
	game.queue_free()
	await settle()
	clear_fixtures()
	print("ONBOARDING UI: %d CHECKS | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)

func stop_music_for_scene_change() -> void:
	game.audio.stop_playback()
	if DisplayServer.get_name() != "headless": await create_timer(0.12).timeout
