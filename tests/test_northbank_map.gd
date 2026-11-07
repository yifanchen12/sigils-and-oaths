extends "res://tests/test_towergate_map.gd"
## Rule-first blockout: three independent warehouse approaches and legacy saves.

func run() -> void:
	var battle: Battle = Model.new(12031, "northbank")
	check(battle.width == 16 and battle.height == 12, "northbank expands the campaign battlefield to sixteen by twelve")
	var painting: Texture2D = Painted.texture(battle)
	check(painting != null and absf(painting.get_size().aspect() - float(battle.width) / battle.height) < 0.002, "depot painting matches the sixteen by twelve rule grid")
	check(battle.map_definition.get("campaign_only", false) and not battle.MAPS.available().any(func(map: Dictionary) -> bool: return map.id == "northbank"), "depot remains a campaign-only map")
	check(battle.commander(0).pos == Vector2i(7, 11) and battle.commander(1).pos == Vector2i(8, 0), "commanders start at passable opposite entries")
	for row: String in battle.map_definition.rows: check(row.length() == 16, "each depot row keeps exact sixteen-cell art alignment")
	check(battle.cell_name(Vector2i(5, 3)) == "F9" and battle.cell_name(Vector2i(10, 3)) == "K9", "worksite coordinates agree with the briefing")
	for x: int in range(16):
		var ground: String = battle.ground(Vector2i(x, 5))
		check((ground not in ["water", "mountain"]) == (x in [4, 7, 8, 11]), "ridge has only three traversable approaches")
	var start: Vector2i = battle.commander(0).pos
	for opening: Array in [[4], [7, 8], [11]]:
		var blockout: Battle = Model.new(12031, "northbank")
		for x: int in [4, 7, 8, 11]:
			if x not in opening: blockout.terrain[Vector2i(x, 5)] = "mountain"
		check(reachable(blockout, start, Vector2i(5, 3)) and reachable(blockout, start, Vector2i(10, 3)), "both work positions reachable through approach " + str(opening))
	for x: int in [4, 7, 8, 11]: battle.terrain[Vector2i(x, 5)] = "mountain"
	check(not reachable(battle, start, Vector2i(5, 3)) and not reachable(battle, start, Vector2i(10, 3)), "closed ridge blocks both work positions")
	var old_gate: Dictionary = Snapshot.capture(Model.new(10341, "towergate"))
	old_gate.rules = Snapshot.pre_northbank_signature()
	check(Snapshot.restore(old_gate).ok, "0.35 running gate battle survives additive depot map")
	var old_field: Dictionary = Snapshot.capture(Model.new(10341, "greenwood"))
	old_field.rules = Snapshot.pre_northbank_signature()
	check(Snapshot.restore(old_field).ok, "0.35 running original battle survives additive depot map")
	var forged: Dictionary = Snapshot.capture(Model.new(12031, "northbank"))
	forged.rules = Snapshot.pre_northbank_signature()
	check(not Snapshot.validate(forged).ok, "new depot cannot claim the older map signature")
	if DisplayServer.get_name() != "headless":
		var game: Node = MainScene.instantiate()
		game.deck_store = Store.new("res://.tools/v036-northbank-deck.json")
		root.add_child(game)
		current_scene = game
		var config: Dictionary = Campaign.new().index.scenarios.c12_joint_depot
		var prepared: Battle = Model.new(int(config.seed), config.map, config.hero, config.enemy_class, config.deck, config.enemy_deck)
		check(prepared.configure_objective(config.control).ok, "native depot uses real campaign objective")
		prepared.set_commander_identity(1, config.enemy_name, config.enemy_portrait)
		game._new_match(12031, prepared)
		game.council.hide()
		game.has_started = true
		if not game.expanded_battlefield: game._toggle_battlefield()
		for frame: int in range(8): await process_frame
		check(game.battle.width == 16 and game.battle.height == 12 and game.board.grid_rect().size.x > 600, "native battle board shows full sixteen by twelve depot")
		for cell: Vector2i in [Vector2i(0, 0), Vector2i(5, 3), Vector2i(10, 3), Vector2i(15, 11)]:
			check(game.board.cell_from_point(game.board.cell_center(cell)) == cell, "native pointer hits exact depot cell")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/screenshots/v036-northbank-map.png") == OK, "native depot screenshot saved")
		DisplayServer.window_set_size(Vector2i(1008, 700))
		for frame: int in range(8): await process_frame
		check(game.board.grid_rect().size.x > 400, "small native window retains usable depot board width")
		for cell: Vector2i in [Vector2i(5, 3), Vector2i(10, 3)]:
			check(game.board.cell_from_point(game.board.cell_center(cell)) == cell, "small native window still hits both work positions")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/screenshots/v036-northbank-map-small.png") == OK, "small native depot screenshot saved")
		game.queue_free()
		await process_frame
	print("NORTHBANK BLOCKOUT: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
