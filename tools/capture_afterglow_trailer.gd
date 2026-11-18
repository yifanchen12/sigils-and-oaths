extends "res://tools/capture_store.gd"
## Use with --write-movie <file>.avi --fixed-fps 30 --resolution 1920x1080.

const TRAILER_SAVE = "user://afterglow-trailer-v043.json"
const TrainingLesson = preload("res://scripts/training.gd")

func run() -> void:
	if not require(DisplayServer.get_name() != "headless" and OS.has_feature("movie"), "Run with a native viewport and Godot Movie Maker"):
		quit(2)
		return
	root.content_scale_size = Vector2i(1778, 1000)
	root.size = SIZE
	var river := Model.new(4386, "rivergate", "warden", "warden", "relay_watch", "balanced")
	var strike: Dictionary = await reach_action(river, func(battle: Battle, action: Dictionary) -> bool:
		return action.type == "attack" and battle.turn >= 12 and battle.units.size() >= 6)
	var field := Model.new(4307, "greenwood", "warden", "warden", "hearth_compact", "balanced")
	var bell: Dictionary = await reach_action(field, func(battle: Battle, action: Dictionary) -> bool:
		return action.type == "play" and battle.hand_card(0, action.card_uid).card_id == "last_bell")
	if not require(not strike.is_empty() and not bell.is_empty(), "The normal seeded matches must reach both trailer actions"):
		quit(2)
		return
	game = MainScene.instantiate()
	game.campaign_session = Campaign.new(TRAILER_SAVE)
	game.settings_store = Preferences.new("user://afterglow-trailer-defaults-v043.cfg")
	root.add_child(game)
	await process_frame
	if not require(root.size == SIZE, "Trailer viewport must be 1920x1080"):
		quit(2)
		return

	mount_battle(river)
	game.selected_unit = strike.unit_id
	hover_cell(strike.target)
	await create_timer(2.0).timeout
	game._commit(strike)
	require(river.get_unit(strike.unit_id).is_empty() or not river.last_combat.is_empty(), "River strike must resolve")
	await create_timer(3.4).timeout

	game._open_council()
	game._start_training()
	game._load_training_lesson(1)
	var trap_uid: int = game.battle.players[0].hand[0].uid
	game._select_card(trap_uid)
	hover_cell(TrainingLesson.GUARD)
	await create_timer(2.1).timeout
	game._commit({"type": "play", "card_uid": trap_uid, "target": TrainingLesson.GUARD})
	await create_timer(1.0).timeout
	var guard: Dictionary = game.battle.unit_at(TrainingLesson.GUARD)
	game._commit({"type": "unit_skill", "unit_id": guard.id, "target": guard.pos})
	await create_timer(1.1).timeout
	game._end_turn()
	require(game.training.complete() and game.battle.traps.is_empty(), "Training attack must trigger the hand trap")
	await create_timer(2.7).timeout
	game._leave_training()

	mount_battle(field)
	game._select_card(bell.card_uid)
	hover_cell(bell.target)
	await create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	var capture_path: String = ProjectSettings.globalize_path("res://docs/screenshots/v043-afterglow-bell.png")
	require(root.get_texture().get_image().save_png(capture_path) == OK, "Save the native Bell preview")
	game._commit(bell)
	require(field.players[0].mana == 0 and field.players[0].discard.back().card_id == "last_bell", "Bell must spend ten natural mana")
	print("TRAILER BELL ", field.turn, " ", field.cell_name(bell.target))
	await create_timer(4.1).timeout

	game._new_campaign()
	for index: int in range(44):
		var page: Dictionary = game.campaign_session.current()
		if page.get("speaker_id", "") == "warden" and game.story_view.illustration.visible: break
		if page.get("type", "") != "dialogue": break
		game._advance_story(game.campaign_session.token())
	require(game.story_view.visible and game.story_view.illustration.visible, "Illustrated campaign dialogue must be visible")
	await create_timer(4.0).timeout
	game._advance_story(game.campaign_session.token())
	await create_timer(2.5).timeout

	var card_image := Image.load_from_file(ProjectSettings.globalize_path("res://docs/release/steam/graphics/store-main.jpg"))
	if require(card_image != null, "Original title artwork was not found"):
		var end_card := TextureRect.new()
		end_card.texture = ImageTexture.create_from_image(card_image)
		end_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		end_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		root.add_child(end_card)
		end_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await create_timer(3.4).timeout

	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TRAILER_SAVE + suffix): DirAccess.remove_absolute(TRAILER_SAVE + suffix)
	game.queue_free()
	await process_frame
	print("AFTERGLOW TRAILER | FAILURES ", failures)
	quit(0 if failures == 0 else 1)

func hover_cell(cell: Vector2i) -> void:
	game.board.hover_cell = cell
	game._on_cell_hovered(cell)
