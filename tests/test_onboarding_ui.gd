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

func check_music_playback(player: AudioStreamPlayer) -> void:
	if DisplayServer.get_name() == "headless": return
	var bus := AudioServer.get_bus_index("Music")
	var slot := AudioServer.get_bus_effect_count(bus)
	var recorder := AudioEffectCapture.new()
	recorder.buffer_length = 0.8
	AudioServer.add_bus_effect(bus, recorder)
	var original := player.get_playback_position()
	player.seek(36.0)
	await create_timer(0.45).timeout
	var peak := 0.0
	for sample: Vector2 in recorder.get_buffer(recorder.get_frames_available()):
		peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	check(peak > 0.001 and peak < 1.0, "native Music bus produces an unclipped audible passage of " + player.stream.resource_path.get_file())
	player.seek(player.stream.get_length()-0.25)
	await create_timer(0.54).timeout
	check(player.playing and player.get_playback_position() < 1.4, "the actual music stream wraps to its beginning")
	player.seek(original)
	AudioServer.remove_bus_effect(bus,slot)

func place_order_and_snare(site: Vector2i) -> void:
	check(game.training.lesson == 4 and game.battle.players[0].mana == 10 and game.board.training_route == [
		Course.RIDER_START, Course.SNARE_SITES[0], Course.SNARE_SITES[1], Course.RIDER_DEST], "rider announces the actual four-cell movement path")
	await select_hand("hollow_hammer")
	await cell(Course.ORDER_CENTER)
	var order: Dictionary = game.battle.Orders.for_side(game.battle, 0)
	var area: Array = game.battle.Orders.footprint(game.battle, order)
	check(game.training.step_index == 1 and game.battle.players[0].mana == 2 and area.size() == 9
		and not area.has(Course.SNARE_SITES[0]) and area.has(Course.SNARE_SITES[1]), "the eight-mana order covers only the second trap site")
	await select_hand("anchor_snare")
	check(game.board.spell_targets.size() == 2 and game.board.spell_targets.has(site), "both trap choices appear on the tactical board")
	await cell(Course.ORDER_CENTER)
	check(game.training.step_index == 1 and game.battle.players[0].mana == 2 and game.battle.traps.is_empty(), "a trap placed off the rider route is rejected without payment")
	await cell(site)
	check(game.battle.players[0].mana == 0 and game.battle.traps.size() == 1 and game.battle.last_order_event.is_empty(), "hand placement spends two mana and the hammer has not hit")

func resolve_order_drill(site: Vector2i, hits: int, health: int, shield: int) -> void:
	await place_order_and_snare(site)
	var cues: Array[String] = []
	var recorder := func(cue: String) -> void: cues.append(cue)
	game.audio.cue_started.connect(recorder)
	await click(game.get_node("%ViewEnd").get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 4500
	var saw_impact := false
	while not game.training.complete() and Time.get_ticks_msec() < deadline:
		if game.battle.turn == 3 and game.training.resolving:
			saw_impact = true
			if game._player_can_act() or game.training_panel.continue_button.visible:
				check(false,"a second action or a completed result was exposed before impact")
				break
		await process_frame
	check(saw_impact, "the tutorial leaves time for the actual impact before reporting its outcome")
	game.audio.cue_started.disconnect(recorder)
	var rider: Dictionary = game.battle.unit_at(site)
	var order: Dictionary = game.battle.last_order_event
	check(game.training.complete() and game.battle.turn == 3 and game.battle.traps.is_empty() and game.battle.pending_orders.is_empty(), "real movement and the next turn resolve both hand cards")
	check(rider.get("hp") == health and rider.get("shield") == shield and order.get("impacts",[]).size() == hits,
		"actual rider state for the trap on " + game.battle.cell_name(site))
	check(game.training_panel.instruction.text.contains("命中 %d 支敌军" % hits) and game.training_panel.instruction.text.contains("%d 生命、%d 护盾" % [health, shield]),
		"the conclusion reports actual damage, shield and target count")
	if DisplayServer.get_name() != "headless" and not game.board.reduced_motion:
		check(cues.has("trap") and cues.has("hammer") and cues.find("trap") < cues.find("hammer"), "the snare snaps before the falling hammer lands")

func resolve_bridge_drill(choice: int) -> void:
	var site: Vector2i = Course.MEDIC_SITES[choice]
	check(game.training.lesson == 5 and game.board.enemy_reach_visible and game.battle.ground(Course.MEDIC_SITES[1]) == "bridge", "sixth lesson opens on the two Rivergate approaches")
	await select_hand("healer")
	var uid: int = game.selected_card
	check(game.board.deploy.size() == 2 and game.board.deploy.has(site), "the single medic hand card offers both legal reinforcement sites")
	await key(KEY_V)
	check(not game.board.enemy_reach_visible and game.board.enemy_reach.is_empty() and game.selected_card == uid, "V hides the map without dropping the hand selection")
	await click(game.reach_button.get_global_rect().get_center())
	hover(game.board.global_position + game.board.cell_center(site))
	await settle()
	check(game.reach_button.button_pressed and game.selected_card == uid and game.map_legend.text.contains("够不到" if choice == 0 else game.battle.definition("archer").name), "pointer reads the actual threat beside the pending deployment")
	check(game.battle_brief.details.text.contains("够不到" if choice == 0 else "后可攻") and game.battle_brief.portrait.texture != null,
		"expanded scouting card pairs the tile with its terrain or a real attacker's portrait and firing point")
	check(not game.battle_brief.visible or not game.board.grid_rect().intersects(game.battle_brief.get_rect()),
		"scouting details never occupy a playable tile")
	await cell(site)
	await click(game.get_node("%ViewEnd").get_global_rect().get_center())
	var deadline := Time.get_ticks_msec() + 5000
	while not game.training.complete() and Time.get_ticks_msec() < deadline: await process_frame
	var medic: Dictionary = game.battle.unit_at(site)
	var target: String = game.battle.definition("spear" if choice == 0 else "healer").name
	check(game.training.complete() and game.battle.turn == 3 and game.training.bridge_target == target, "the animated archer selects and actually attacks the expected defender")
	check(medic.get("hp",-1) == [5,3][choice] and game.training_panel.instruction.text.contains(target), "the conclusion displays post-treatment health and actual shot recipient")
	check(game.battle.deployment_cells(0).has(Vector2i(3,4)) == (choice == 1), "only the exposed forward medic extends the reinforcement line onto D6")

func run() -> void:
	clear_fixtures()
	if DisplayServer.get_name() != "headless": AudioServer.set_bus_mute(0, true)
	await open_scene()
	check(game.council.training_button.visible and game.council.settings_button.visible, "public entry points on the first screen")
	var council_track: AudioStreamOggVorbis = game.audio.music_players[0].stream
	check(game.audio.scene_index == 0 and council_track.resource_path.ends_with("/evening.ogg") and absf(council_track.get_length()-186.25) < 0.3 and council_track.loop, "the council plays the full licensed Evening loop")
	await check_music_playback(game.audio.music_players[0])
	await click(game.council.settings_button.get_global_rect().get_center())
	check(game.options.visible and not game._player_can_act(), "settings are an exclusive window")
	var credits_button: Button = game.options.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "配乐署名")[0]
	await click_window(game.options, credits_button.get_global_rect().get_center())
	check(game.options.music_credits.visible and game.options.music_credits.dialog_text.contains("Kevin MacLeod")
		and game.options.music_credits.dialog_text.contains("USUAN1200110") and game.options.music_credits.dialog_text.contains("creativecommons.org/licenses/by/4.0/"), "player can read the bundled credits and license from the settings")
	if DisplayServer.get_name() == "headless":
		game.options.music_credits.get_ok_button().pressed.emit()
		await settle()
	else:
		await click_window(game.options.music_credits, game.options.music_credits.get_ok_button().get_global_rect().get_center())
	check(not game.options.music_credits.visible and game.options.visible, "closing the credits returns to the same settings dialog")
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
	game.board.zoom_at(game.board.size/2,1.30)
	game.board.pan_by(Vector2(0,15))
	var former_zoom: float = game.board.zoom
	var former_pan: Vector2 = game.board.pan
	var old_state: Dictionary = Snapshot.capture(suspended)
	check(game.council.resume_button.visible, "there is a live skirmish before entering the course")
	await click(game.council.training_button.get_global_rect().get_center())
	check(game.training_panel.visible and game.training.lesson == 0 and game.battle != suspended, "lesson opens a separate battle from the real menu")
	var field_track: AudioStreamOggVorbis = game.audio.music_players[1].stream
	check(game.audio.scene_index == 1 and field_track.resource_path.ends_with("/angevin.ogg") and absf(field_track.get_length()-280.56) < 0.3 and field_track.loop, "training switches to the licensed Angevin loop")
	await check_music_playback(game.audio.music_players[1])
	if DisplayServer.get_name() != "headless":
		var field_player: AudioStreamPlayer = game.audio.music_players[1]
		field_player.seek(42)
		game.audio.set_battle_music(false)
		await create_timer(1.60).timeout
		check(field_player.stream_paused and game.audio.music_players[0].playing, "return to council parks the faded-out battle track")
		game.audio.set_battle_music(true)
		await create_timer(0.24).timeout
		check(not field_player.stream_paused and field_player.get_playback_position() > 42 and field_player.get_playback_position() < 45,
			"returning to the battle resumes the same musical phrase")
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
	check(game.training.lesson == 3 and game.training_panel.lesson_choice.item_count == Course.LESSONS.size() and game.board.predicted_area.size() == 13, "new lesson shows the public training blast")
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
	await resolve_order_drill(Course.SNARE_SITES[0], 0, 8, 1)
	await click(game.training_panel.reset_button.get_global_rect().get_center())
	game.board.set_reduced_motion(false)
	await place_order_and_snare(Course.SNARE_SITES[1])
	await click(game.get_node("%ViewEnd").get_global_rect().get_center())
	check(not game.training.complete() and game.battle.active_side == 1, "the branch waits for the opposing movement to finish")
	await click(game.training_panel.reset_button.get_global_rect().get_center())
	await create_timer(1.25).timeout
	check(game.training.step_index == 0 and game.battle.turn == 1 and game.battle.last_order_event.is_empty(), "reset during movement cancels the old delayed resolution")
	await resolve_order_drill(Course.SNARE_SITES[1], 1, 3, 0)
	await click(game.training_panel.continue_button.get_global_rect().get_center())
	await resolve_bridge_drill(0)
	await click(game.training_panel.reset_button.get_global_rect().get_center())
	await resolve_bridge_drill(1)
	await click(game.training_panel.continue_button.get_global_rect().get_center())
	check(game.council.visible and game.training == null and game.battle == suspended and Snapshot.capture(game.battle) == old_state, "completion resumes the identical suspended battle from its original menu")
	check(not game.board.enemy_reach_visible, "return restores the suspended match's map layers")
	check(is_equal_approx(game.board.zoom,former_zoom) and game.board.pan.is_equal_approx(former_pan), "leaving training restores the suspended match camera")
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
