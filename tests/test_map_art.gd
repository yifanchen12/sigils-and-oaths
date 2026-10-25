extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const Model = preload("res://scripts/battle.gd")
const Painted = preload("res://scripts/map_artwork.gd")
const Store = preload("res://scripts/deck_store.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame: int in range(4): await process_frame

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://docs/screenshots/" + filename) == OK, "painted map screenshot")

func run() -> void:
	create_timer(60).timeout.connect(func() -> void: push_error("Map art test timed out"); quit(2))
	for map: Dictionary in Model.MAPS.available():
		var battle: Battle = Model.new(31, map.id)
		var texture: Texture2D = Painted.texture(battle)
		# During art production, only the map families already imported are checked.
		if texture == null:
			check(not OS.get_cmdline_user_args().has("--complete"), "required production map painting exists: " + str(map.id))
			continue
		check(absf(texture.get_size().aspect() - 1.2) < 0.015, "painting preserves 12x10 aspect: " + str(map.id))
		check(Painted.changed_cells(battle).is_empty(), "initial terrain exactly matches authored map: " + str(map.id))
		var sample: Vector2i = Painted.floor_sample(battle)
		check(battle.inside(sample), "dynamic terrain sample stays in source map")
		var point := Vector2i(0, 0)
		var previous: String = battle.ground(point)
		battle.terrain[point] = "fort" if previous != "fort" else "road"
		check(Painted.changed_cells(battle) == [point], "only altered cell receives dynamic terrain overlay")
		battle.terrain[point] = previous
		check(Painted.changed_cells(battle).is_empty(), "restoring terrain removes overlay")
	var game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/map_art_test_deck.json")
	root.add_child(game)
	current_scene = game
	game.council.hide()
	game.has_started = true
	if not game.expanded_battlefield: game._toggle_battlefield()
	await settle()
	check(Painted.texture(game.battle) != null, "opening map uses illustrated terrain")
	var before: String = var_to_str([game.battle.terrain, game.battle.units, game.battle.players])
	game.grid_button.button_pressed = true
	await settle()
	check(game.board.grid_visible, "grid button enables tactical terrain overlay")
	check(before == var_to_str([game.battle.terrain, game.battle.units, game.battle.players]), "grid is presentation only")
	await capture("painted-greenwood-grid.png")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_G
	root.push_input(key, true)
	await settle()
	check(not game.board.grid_visible and not game.grid_button.button_pressed, "G hotkey and button stay synchronized")
	game._open_council()
	root.push_input(key, true)
	check(not game.board.grid_visible, "menu blocks battlefield grid hotkey")
	game._resume_battle()
	game.battle.players[0].mana = 10
	game.battle.players[0].max_mana = 10
	var terrain_card: Dictionary = {}
	for instance: Dictionary in game.battle.players[0].deck:
		if instance.card_id == "rampart": terrain_card = instance; break
	check(not terrain_card.is_empty(), "fortification card fixture exists")
	game.battle.players[0].deck.erase(terrain_card)
	game.battle.players[0].hand.append(terrain_card)
	# Reach the forest through legal adjacent reinforcement, including new summons.
	var unit_cards: Array[Dictionary] = []
	for instance: Dictionary in game.battle.players[0].hand + game.battle.players[0].deck:
		if game.battle.definition(instance.card_id).type == "unit": unit_cards.append(instance)
	unit_cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return game.battle.definition(a.card_id).cost < game.battle.definition(b.card_id).cost)
	var deployed: bool = true
	for index: int in range(3):
		var instance: Dictionary = unit_cards[index]
		if game.battle.players[0].deck.has(instance):
			game.battle.players[0].deck.erase(instance)
			game.battle.players[0].hand.append(instance)
		var spawn: Dictionary = game.battle.apply_action({"type": "play", "card_uid": instance.uid, "target": Vector2i(6 + index, 9)})
		if not spawn.ok: deployed = false
	check(deployed, "legal forward reinforcement reaches painted forest")
	var forest := Vector2i(8, 9)
	check(game.battle.ground(forest) == "forest", "terrain edit starts on authored forest")
	var result: Dictionary = game.battle.apply_action({"type": "play", "card_uid": terrain_card.uid, "target": forest})
	check(result.ok and game.battle.ground(forest) == "fort", "real terrain card changes forest into fort")
	check(Painted.changed_cells(game.battle) == [forest], "painted forest is replaced at exact edited cell")
	await settle()
	await capture("painted-greenwood-fort.png")
	var road_card: Dictionary = {}
	for instance: Dictionary in game.battle.players[0].hand + game.battle.players[0].deck:
		if instance.card_id == "trail": road_card = instance; break
	check(not road_card.is_empty(), "road card fixture exists")
	if game.battle.players[0].deck.has(road_card):
		game.battle.players[0].deck.erase(road_card)
		game.battle.players[0].hand.append(road_card)
	var road := Vector2i(9, 9)
	var road_result: Dictionary = game.battle.apply_action({"type": "play", "card_uid": road_card.uid, "target": road})
	check(road_result.ok and game.battle.ground(road) == "road", "real road card creates a visible dynamic route")
	check(Painted.changed_cells(game.battle) == [forest, road], "fort and road overlays match exactly the edited cells")
	await settle()
	await capture("painted-greenwood-terrain-cards.png")
	game.board.zoom_at(game.board.size / 2, 2)
	game.board.pan_by(Vector2(-170, -80))
	var correct: bool = true
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(5, 4), Vector2i(11, 9)]:
		if game.board.cell_from_point(game.board.cell_center(cell)) != cell: correct = false
	check(correct, "painted map zoom/pan preserves exact cell hit testing")
	game.board.fit_map()
	for map: Dictionary in Model.MAPS.available():
		game.current_map = map.id
		game._new_match(31)
		if Painted.texture(game.battle) == null: continue
		var state: String = var_to_str([game.battle.units, game.battle.players, game.battle.terrain, game.battle.rng.state])
		await settle()
		await capture("painted-" + str(map.id) + ".png")
		check(state == var_to_str([game.battle.units, game.battle.players, game.battle.terrain, game.battle.rng.state]), "rendering never mutates battle rules: " + str(map.id))
	print("MAP ART CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
