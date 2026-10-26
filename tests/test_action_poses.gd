extends "res://tests/test_unit_skills_ui.gd"

const Art = preload("res://scripts/art_library.gd")

func inspect_atlas() -> void:
	for kind: String in Art.ACTION_SHEETS:
		var fingerprints: Array[int] = []
		for frame: int in range(3):
			var texture: Texture2D = Art.get_action_texture(kind, frame)
			check(texture is AtlasTexture, "%s frame %d has a native atlas region" % [kind, frame])
			if texture == null: continue
			check(texture.filter_clip and Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), "clipped region stays inside raw source")
			check(Rect2(Vector2.ZERO, texture.get_size()).has_point(Art.action_feet(kind, frame)), "foot pivot stays inside its frame")
			var image: Image = texture.get_image()
			check(image != null and not image.is_invisible(), "frame contains visible artwork")
			check(image.detect_alpha() != Image.ALPHA_NONE, "frame retains transparent background")
			var clear_edges: bool = true
			for y: int in range(image.get_height()):
				if image.get_pixel(0, y).a > 0.04 or image.get_pixel(image.get_width() - 1, y).a > 0.04: clear_edges = false
			for x: int in range(image.get_width()):
				if image.get_pixel(x, 0).a > 0.04 or image.get_pixel(x, image.get_height() - 1).a > 0.04: clear_edges = false
			check(clear_edges, "no clipped or neighboring figure at frame edges")
			fingerprints.append(hash(image.get_data()))
		check(fingerprints.size() == 3 and fingerprints[0] != fingerprints[1] and fingerprints[1] != fingerprints[2] and fingerprints[0] != fingerprints[2], "three different pose images for " + kind)
	check(Art.get_action_texture("sword", -1) == null and Art.get_action_texture("spear", 3) == null, "rest and invalid frames use standing fallback")
	check(Art.get_action_texture("mage", 0) == null and Art.get_action_texture("unknown", 0) == null, "unconverted characters keep standing artwork")

func inspect_timing(attacker_id: int, defender_id: int, guarding: bool) -> void:
	game.board.set_process(false)
	var state: String = immutable_state()
	for sample: Array in [[0.0, 0], [0.119, 0], [0.12, 1], [0.349, 1], [0.35, 2], [0.489, 2], [0.49, -1], [0.99, -1]]:
		game.board.combat.age = sample[0]
		check(game.board.combat_pose(attacker_id) == sample[1], "primary pose boundary " + str(sample[0]))
	game.board.combat.age = 0.20
	check(game.board.combat_pose(defender_id) == (0 if guarding else -1), "guard braces while ordinary defender stays at rest")
	if game.board.combat.forecast.counter_damage > 0:
		for sample: Array in [[0.50, 0], [0.55, 1], [0.72, 2], [0.90, -1]]:
			game.board.combat.age = sample[0]
			check(game.board.combat_pose(defender_id) == sample[1], "counter pose boundary " + str(sample[0]))
	check(game.board.combat_pose(-999) == -1 and state == immutable_state(), "pose sampling never changes battle state")
	game.board.combat.age = 0
	game.board.queue_redraw()
	game.board.set_process(true)

func show_strike(kind: String, target_kind: String, reverse: bool = false) -> void:
	await stage()
	var actor: Dictionary = troop(kind, Vector2i(5 if reverse else 4, 5))
	var target: Dictionary = troop(target_kind, Vector2i(4 if reverse else 5, 5), 1)
	# A high-health fixture keeps both actors visible through the whole native animation.
	actor.hp = 30; actor.max_hp = 30; target.hp = 30; target.max_hp = 30
	game.board.zoom_at(game.board.cell_center(actor.pos), 1.75)
	game.board.reveal_cell(actor.pos)
	await select(actor)
	await pause_for_demo()
	await click(game.board.global_position + game.board.cell_center(target.pos))
	check(not game.board.combat.is_empty(), "real attack starts pose animation for " + kind)
	inspect_timing(actor.id, target.id, false)
	var state: String = immutable_state()
	await create_timer(0.19).timeout
	await capture("action-pose-" + kind + ("-left" if reverse else ""))
	await create_timer(1.1).timeout
	check(state == immutable_state() and game.board.combat.is_empty() and game.board.combat_pose(actor.id) == -1, "animation completes without another rules action")
	await pause_for_demo()

func run() -> void:
	create_timer(70).timeout.connect(func() -> void: push_error("action pose timeout"); quit(2))
	recording = OS.get_cmdline_user_args().has("--record")
	inspect_atlas()
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/action_pose_deck.json")
	root.add_child(game); current_scene = game
	await show_strike("sword", "spear")
	await show_strike("spear", "cavalry")
	await show_strike("cavalry", "sword")
	await show_strike("sword", "spear", true)
	await stage()
	var actor: Dictionary = troop("sword", Vector2i(4, 5))
	var guard: Dictionary = troop("spear", Vector2i(5, 5), 1)
	var ally: Dictionary = troop("mage", Vector2i(4, 4), 1)
	guard.pos = Vector2i(5, 4)
	actor.hp = 30; actor.max_hp = 30; guard.hp = 30; guard.max_hp = 30
	game.battle.end_turn()
	check(game.battle.apply_action({"type": "unit_skill", "unit_id": guard.id, "target": guard.pos}).ok, "real guard fixture")
	game.battle.end_turn()
	game.board.zoom_at(game.board.cell_center(actor.pos), 1.75)
	await select(actor)
	await click(game.board.global_position + game.board.cell_center(ally.pos))
	check(not game.board.combat.is_empty() and game.board.combat.forecast.intercepted, "guard uses interception timeline")
	inspect_timing(actor.id, guard.id, true)
	await create_timer(0.19).timeout; await capture("action-pose-guard")
	game.board.reset_effects()
	check(game.board.combat_pose(actor.id) == -1 and not game.board.is_presenting(), "reset cancels all pose state")
	await stage()
	actor = troop("sword", Vector2i(4, 5))
	var target: Dictionary = troop("spear", Vector2i(5, 5), 1)
	await select(actor)
	await click(game.board.global_position + game.board.cell_center(target.pos))
	check(not game.board.combat.is_empty(), "restart fixture has a live attack presentation")
	game._new_match(72)
	check(game.board.combat.is_empty() and game.board.combat_pose(actor.id) == -1, "restart cannot retain an earlier character pose")
	await stage()
	actor = troop("sword", Vector2i(4, 5)); target = troop("spear", Vector2i(5, 5), 1); target.hp = 1
	await select(actor); await click(game.board.global_position + game.board.cell_center(target.pos))
	check(game.battle.get_unit(target.id).is_empty() and game.board.combat.forecast.counter_damage == 0, "lethal action removes defender once and has no counter")
	var final_state: String = immutable_state()
	await create_timer(0.38).timeout
	check(not game.board.combat.is_empty(), "defeated actor keeps its finite impact presentation")
	await create_timer(1.0).timeout
	check(game.board.combat.is_empty() and final_state == immutable_state(), "death fade finishes without reviving or damaging another unit")
	print("ACTION POSE CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
