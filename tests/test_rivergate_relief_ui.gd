extends "res://tests/test_ui.gd"

const Artwork = preload("res://scripts/map_artwork.gd")
const Settings = preload("res://scripts/settings_store.gd")
const SOUTH_ROAD := Vector2i(3, 6)
const NORTH_ROAD := Vector2i(3, 3)
const WEST_BRIDGE := Vector2i(3, 5)
const SHALLOWS := Vector2i(4, 4)

func run() -> void:
	DisplayServer.window_set_size(Vector2i(1296, 900))
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/rivergate-relief-qa-deck.json")
	game.settings_store = Settings.new("res://.tools/rivergate-relief-qa-prefs.cfg")
	check(game.settings_store.save_preferences({"reduce_motion": true}).ok, "set isolated preferences")
	root.add_child(game)
	game.audio.stop_playback()
	current_scene = game
	await settle()
	var index: int = game.council.map_options.find_custom(func(map: Dictionary) -> bool: return map.id == "rivergate")
	check(index >= 0, "Rivergate is offered in the normal match setup")
	if index >= 0:
		await click(game.council.map_buttons[index].get_global_rect().get_center())
		await click(game.council.start_button.get_global_rect().get_center())
		await verify_board()
	print("RIVERGATE RELIEF UI: %d CHECKS | FAILURES: %d" % [checks, failures])
	await finish_relief_test()

func finish_relief_test() -> void:
	game.audio.stop_playback()
	await create_timer(0.15, true, false, true).timeout
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func verify_board() -> void:
	var battle: Battle = game.battle
	var texture: Texture2D = Artwork.texture(battle)
	check(battle.map_definition.id == "rivergate" and texture != null, "the normal entry loads the new Rivergate artwork")
	if texture == null: return
	check(texture.resource_path.ends_with("rivergate-relief-v1.png") and texture.get_size() == Vector2(2160, 1800),
		"loads the full orthographic render with the board aspect ratio")
	check(Artwork.changed_cells(battle).is_empty() and battle.width == 12 and battle.height == 10, "all original terrain cells remain authoritative")
	game.board.zoom_at(game.board.cell_center(WEST_BRIDGE), 1.12)
	game.board.pan_by(Vector2(17, -12))
	await settle()
	for y: int in range(battle.height):
		for x: int in range(battle.width):
			var cell := Vector2i(x, y)
			check(game.board.cell_from_point(game.board.cell_center(cell)) == cell, "pan and zoom preserve cell mapping " + str(cell))
	game.board.fit_map()
	var swords: Dictionary = Fixture.troop(battle, "sword", SOUTH_ROAD)
	var spears: Dictionary = Fixture.troop(battle, "spear", NORTH_ROAD, 1)
	battle.terrain[SOUTH_ROAD] = "road"
	battle.terrain[NORTH_ROAD] = "road"
	battle.players[0].mana = 6
	battle.players[0].max_mana = 6
	game._refresh()
	await settle()
	await click(board_point(SOUTH_ROAD))
	check(game.board.moves.has(WEST_BRIDGE) and not game.board.moves.has(SHALLOWS), "movement highlights the bridge and excludes water")
	await click(board_point(WEST_BRIDGE))
	check(swords.pos == WEST_BRIDGE and swords.moved, "real pointer click moves onto the rendered bridge")

	var bolt: Dictionary = Fixture.give(battle, "bolt")
	game._refresh()
	await settle()
	await select_hand(bolt.uid)
	hover(board_point(NORTH_ROAD))
	await settle()
	var hp: int = spears.hp
	check(game.board.predicted_losses.get(spears.id, 0) == 4, "spell preview matches the opposing unit on the north bank")
	await click(board_point(NORTH_ROAD))
	check(spears.hp == hp - 4 and battle.players[0].mana == 4, "spell resolves on the same grid cell")

	var kit: Dictionary = Fixture.give(battle, "span_kit")
	game._refresh()
	await settle()
	await select_hand(kit.uid)
	check(game.board.spell_targets.has(SHALLOWS), "the shoreline still accepts a temporary bridge card")
	await click(board_point(SHALLOWS))
	check(battle.ground(SHALLOWS) == "bridge" and Artwork.changed_cells(battle) == [SHALLOWS], "the new crossing is drawn over the rendered river")

func select_hand(uid: int) -> void:
	for view: CardView in game.get_node("%CompactHand").get_children():
		if view.card_uid != uid: continue
		await click(view.get_global_rect().get_center())
		return
	check(false, "expected card in the native hand")

func board_point(cell: Vector2i) -> Vector2:
	return game.board.global_position + game.board.cell_center(cell)
