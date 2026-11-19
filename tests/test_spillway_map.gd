extends "res://tests/test_towergate_map.gd"
## Native grid, painted river, new card art and dynamic bridge preview.

func run() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("spillway native map timed out"); quit(2))
	var battle: Battle = Model.new(14031, "spillway", "grove", "warden", "channel", "balanced")
	check(battle.width == 16 and battle.height == 12, "spillway uses full sixteen by twelve rule grid")
	check(Painted.texture(battle) != null and absf(Painted.texture(battle).get_size().aspect() - 16.0 / 12.0) < 0.002, "original painting fits the grid")
	for target: Vector2i in [Vector2i(5, 6), Vector2i(10, 3)]: check(reachable(battle, battle.commander(0).pos, target), "both work positions reachable over existing bridges")
	for y: int in [4, 5]:
		for x: int in range(16): check(battle.ground(Vector2i(x, y)) == ("bridge" if x in [3, 12] else "water"), "water band has precisely two existing bridges")
	if DisplayServer.get_name() != "headless":
		var game: Node = MainScene.instantiate()
		game.deck_store = Store.new("res://.tools/v038-spillway-deck.json")
		root.add_child(game); current_scene = game
		var setup: Dictionary = Campaign.new().index.scenarios.c14_upstream_channel
		check(battle.configure_objective(setup.control).ok, "native map shows real two-point objective")
		battle.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
		check(battle.add_generated_card(0, "span_kit") and battle.add_generated_card(0, "countercurrent_ward"), "new cards appear in battle hand")
		game._new_match(14031, battle); game.council.hide(); game.has_started = true
		if not game.expanded_battlefield: game._toggle_battlefield()
		for frame: int in range(8): await process_frame
		check(game.Art.get_texture("span_kit") != null and game.Art.get_texture("countercurrent_ward") != null, "original card art imports in native game")
		check(game.board.grid_rect().size.x > 600, "expanded map remains readable")
		for cell: Vector2i in [Vector2i(0, 0), Vector2i(5, 6), Vector2i(10, 3), Vector2i(15, 11)]: check(game.board.cell_from_point(game.board.cell_center(cell)) == cell, "pointer hits exact rule cell")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/screenshots/v038-spillway-map.png") == OK, "native full map screenshot saved")
		battle.commander(0).pos = Vector2i(7, 6)
		battle.players[0].mana = 10
		var uid: int = -1
		for card: Dictionary in battle.players[0].hand:
			if card.card_id == "span_kit": uid = card.uid; break
		check(uid >= 0 and game._apply_with_feedback({"type": "play", "card_uid": uid, "target": Vector2i(7, 5)}).ok and battle.ground(Vector2i(7, 5)) == "bridge", "real hand builds central bridge on painted water")
		for frame: int in range(8): await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/screenshots/v038-spillway-bridge.png") == OK, "native built bridge screenshot saved")
		DisplayServer.window_set_size(Vector2i(1008, 700))
		for frame: int in range(8): await process_frame
		for cell: Vector2i in [Vector2i(5, 6), Vector2i(10, 3), Vector2i(7, 5)]: check(game.board.cell_from_point(game.board.cell_center(cell)) == cell, "small window retains exact click mapping")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/screenshots/v038-spillway-small.png") == OK, "native small map screenshot saved")
		game.queue_free(); await process_frame
	print("SPILLWAY NATIVE: %d CHECKS | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
