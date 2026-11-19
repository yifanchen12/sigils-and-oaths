extends "res://tests/test_rivergate_relief_ui.gd"

const Landscape = preload("res://scripts/battlefield_art.gd")

func run() -> void:
	DisplayServer.window_set_size(Vector2i(1296, 900))
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/frontier-qa-deck.json")
	game.settings_store = Settings.new("res://.tools/frontier-qa-settings.cfg")
	check(game.settings_store.save_preferences({"reduce_motion": true}).ok, "isolated settings")
	root.add_child(game)
	game.audio.stop_playback()
	current_scene = game
	await settle()
	if await enter_map("greenwood"):
		await test_forest()
	game._open_council()
	await settle()
	if await enter_map("harbor"):
		await test_harbor()
		if DisplayServer.get_name() != "headless": await test_water_pixels()
	print("FRONTIER RELIEF UI: %d CHECKS | FAILURES: %d" % [checks, failures])
	await finish_relief_test()

func enter_map(id: String) -> bool:
	var index: int = game.council.map_options.find_custom(func(item: Dictionary) -> bool: return item.id == id)
	check(index >= 0, "selectable map " + id)
	if index < 0: return false
	await click(game.council.map_buttons[index].get_global_rect().get_center())
	await click(game.council.start_button.get_global_rect().get_center())
	var model: Battle = game.battle
	var painting := Artwork.texture(model)
	check(model.map_definition.id == id and painting != null, "council opens " + id)
	if model.map_definition.id != id or painting == null: return false
	check(painting.resource_path.ends_with(id + "-relief-v1.png") and painting.get_size() == Vector2(2160, 1800), "full diorama for " + id)
	check(Artwork.changed_cells(model).is_empty(), "no changes to the authored terrain")
	game.board.zoom_at(game.board.size / 2, 1.32)
	game.board.pan_by(Vector2(28,-24))
	await settle()
	for y: int in range(model.height):
		for x: int in range(model.width):
			var cell := Vector2i(x,y)
			check(game.board.cell_from_point(game.board.cell_center(cell)) == cell, "zoomed tile " + str(cell))
	game.board.fit_map()
	model.players[0].mana = 10
	model.players[0].max_mana = 10
	return true

func place(model: Battle, id: String, cell: Vector2i, side: int = 0) -> Dictionary:
	var initial := model.ground(cell)
	var unit := Fixture.troop(model, id, cell, side)
	model.terrain[cell] = initial
	return unit

func test_forest() -> void:
	var model: Battle = game.battle
	var forest := Vector2i(2,3)
	var hill := Vector2i(5,4)
	var crag := Vector2i(3,3)
	var sword := place(model, "sword", forest)
	var archer := place(model, "archer", Vector2i(4,4))
	var distant := place(model, "spear", Vector2i(9,4), 1)
	var close_foe := place(model, "spear", Vector2i(6,5), 1)
	game._refresh()
	await settle()
	await click(board_point(forest))
	check(model.terrain_defense(sword) == 1 and not game.board.moves.has(crag), "forest cover and impassable slate")
	await click(board_point(archer.pos))
	check(game.board.moves.has(hill), "the pictured escarpment permits ascent")
	await click(board_point(hill))
	check(archer.pos == hill and model.attack_range(archer) == 4, "archer gains the hill range in play")
	check(model.attack_targets(archer).has(distant.pos), "fourth tile becomes a valid basic shot")
	var bolt := Fixture.give(model, "bolt")
	game._refresh()
	await settle()
	await select_hand(bolt.uid)
	check(game.board.spell_targets.has(close_foe.pos) and not game.board.spell_targets.has(distant.pos),
		"local spell retains its own three-tile range")
	hover(board_point(close_foe.pos))
	await settle()
	var hp: int = close_foe.hp
	check(game.board.predicted_losses.get(close_foe.id, 0) == 4, "damage preview reaches the pictured tile")
	await click(board_point(close_foe.pos))
	check(close_foe.hp == hp - 4, "aimed spell resolved on that tile")
	var trail := Fixture.give(model, "trail")
	game._refresh()
	await settle()
	await select_hand(trail.uid)
	await click(board_point(forest))
	check(model.ground(forest) == "road" and Artwork.changed_cells(model) == [forest], "a hand card cuts a road through the occupied grove")

func test_harbor() -> void:
	var model: Battle = game.battle
	for y: int in [2,7]:
		var start := Vector2i(3,y)
		var entry := Vector2i(4,y)
		var sailor := place(model, "sword", start)
		game._refresh()
		await settle()
		await click(board_point(start))
		check(game.board.moves.has(entry) and not model.passable(entry+Vector2i.UP), "the bridge admits troops and the adjacent canal excludes them")
		await click(board_point(entry))
		check(sailor.pos == entry and sailor.moved, "entered the actual crossing in row " + str(y))
	for x: int in range(4,8):
		check(not Landscape.bridge_is_vertical(model, Vector2i(x,6)), "each stage of the new harbor route runs between the east and west banks")
	var berth := Vector2i(4,6)
	var kit := Fixture.give(model, "span_kit")
	game._refresh()
	await settle()
	await select_hand(kit.uid)
	check(game.board.spell_targets.has(berth), "an occupied decorative berth accepts a hand-played temporary bridge")
	await click(board_point(berth))
	check(model.ground(berth) == "bridge" and Artwork.changed_cells(model) == [berth], "temporary bridge is a walkable change in the expected berth")
	var coastal := place(model, "spear", Vector2i(3,6))
	game._refresh()
	await settle()
	await click(board_point(coastal.pos))
	await click(board_point(berth))
	check(coastal.pos == berth, "troop used the new crossing beside the wooden drawbridge")
	var river: Battle = Battle.new(9, "rivergate")
	check(Landscape.bridge_is_vertical(river, Vector2i(4,4)), "Rivergate's temporary deck follows the opposite axis")

func test_water_pixels() -> void:
	var model := Battle.new(9, "harbor")
	var surface := SubViewport.new()
	var tile := 180
	surface.size = Vector2i(model.width, model.height) * tile
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(surface)
	var layer := Node2D.new()
	surface.add_child(layer)
	layer.draw.connect(func() -> void: Artwork.draw_map(layer, model, Rect2(Vector2.ZERO, Vector2(surface.size))))
	for berth: Vector2i in Artwork.MOORINGS:
		model.terrain[berth] = "bridge"
	await settle()
	await RenderingServer.frame_post_draw
	var canvas := surface.get_texture().get_image()
	var empty := Artwork.EMPTY_MOORINGS.get_image()
	var occupied := Artwork.texture(model).get_image()
	for index: int in range(Artwork.MOORINGS.size()):
		var cell: Vector2i = Artwork.MOORINGS[index]
		var berth_tile := Vector2i(index % 2, floori(index / 2.0))
		var clean_error := 0.0
		var old_error := 0.0
		for y: int in range(9, tile - 9, 3):
			if y > 32 and y < 148: continue # keep only the water outside the railings
			for x: int in range(5, tile-5, 3):
				var offset := Vector2i(x,y)
				var actual := canvas.get_pixelv(cell*tile+offset)
				var expected := empty.get_pixelv(berth_tile*tile+offset)
				var boat := occupied.get_pixelv(cell*tile+offset)
				clean_error += absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)
				old_error += absf(actual.r-boat.r)+absf(actual.g-boat.g)+absf(actual.b-boat.b)
		check(clean_error < 12.0 and clean_error + 4.0 < old_error, "visible water replaces the vessel outside the bridge rails at " + str(cell) + " errors " + str([clean_error,old_error]))
	surface.queue_free()
	await process_frame
