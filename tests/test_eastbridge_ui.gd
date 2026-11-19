extends SceneTree
## Native map presentation, grid hit testing and local screenshot evidence.
const MainScene = preload("res://scenes/main.tscn")
const Store = preload("res://scripts/deck_store.gd")
const Painted = preload("res://scripts/map_artwork.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://docs/screenshots/" + label + ".png") == OK, "save map evidence")

func run() -> void:
	create_timer(120).timeout.connect(func() -> void: push_error("eastbridge UI timeout"); quit(2))
	var game: Control = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v040-map-deck.json")
	root.add_child(game); current_scene = game
	game.current_map = "eastbridge"
	game._new_match(16031)
	game.battle.set_commander_identity(1, "护运队长白祁", "terrain_fort")
	game.has_started = true
	game.council.hide()
	if not game.expanded_battlefield: game._toggle_battlefield()
	game._refresh()
	for frame: int in range(5): await process_frame
	check(Painted.texture(game.battle) != null, "painted East Bridge loaded")
	check(game.battle.width == 16 and game.battle.height == 12, "expanded map size")
	for cell: Vector2i in [Vector2i(3, 4), Vector2i(10, 5), Vector2i(7, 11)]:
		check(game.board.cell_from_point(game.board.cell_center(cell)) == cell, "cell click maps to rule coordinate")
	await capture("v040-eastbridge-map")
	DisplayServer.window_set_size(Vector2i(1008, 700))
	for frame: int in range(5): await process_frame
	game.board.fit_map()
	await capture("v040-eastbridge-small")
	print("EASTBRIDGE UI: %d CHECKS | FAILURES: %d" % [checks, failures])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
