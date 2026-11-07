extends SceneTree
## Chapter-ten gate map: two real crossings, painting, zoom/pointer alignment.
const Model = preload("res://scripts/battle.gd")
const Painted = preload("res://scripts/map_artwork.gd")
const MainScene = preload("res://scenes/main.tscn")
const Store = preload("res://scripts/deck_store.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(reason)

func reachable(battle: Battle, start: Vector2i, goal: Vector2i) -> bool:
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == goal: return true
		for direction: Vector2i in battle.DIRECTIONS:
			var next: Vector2i = cell + direction
			if not battle.inside(next) or seen.has(next) or battle.ground(next) in ["water", "mountain"]: continue
			seen[next] = true
			queue.append(next)
	return false

func run() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("tower gate map timeout"); quit(2))
	var battle: Battle = Model.new(1034, "towergate")
	check(battle.width == 14 and battle.height == 12, "tower gate expands the tactical board to 14 by 12")
	check(not battle.MAPS.available().any(func(map: Dictionary) -> bool: return map.id == "towergate") and battle.map_definition.get("campaign_only", false), "asymmetric gate remains a campaign-only map")
	check(battle.commander(0).pos == Vector2i(6, 11) and battle.commander(1).pos == Vector2i(7, 0), "both commanders start on passable opposing approaches")
	var painting: Texture2D = Painted.texture(battle)
	check(painting != null and absf(painting.get_size().aspect() - float(battle.width) / battle.height) < 0.002, "source painting matches the 14 by 12 grid without stretching")
	for y: int in [4, 5]:
		for x: int in range(14):
			check(battle.ground(Vector2i(x, y)) == ("bridge" if x in [3, 4, 9, 10] else "water"), "each canal cell agrees with two painted crossings")
	var start: Vector2i = battle.commander(0).pos
	var gate: Vector2i = Vector2i(6, 2)
	check(battle.cell_name(Vector2i(3, 3)) == "D9" and battle.cell_name(Vector2i(10, 3)) == "K9", "briefing coordinates match the northern objective cells")
	var old_map_save: Dictionary = Snapshot.capture(Model.new(1034, "sunspire"))
	old_map_save.rules = Snapshot.pre_towergate_signature()
	check(Snapshot.restore(old_map_save).ok, "an unchanged old-map battle accepts the exact pre-gate rule signature")
	var invalid_gate_save: Dictionary = Snapshot.capture(battle)
	invalid_gate_save.rules = Snapshot.pre_towergate_signature()
	check(not Snapshot.validate(invalid_gate_save).ok, "the new gate cannot be forged with the older map signature")
	check(reachable(battle, start, gate), "gate reachable with both bridges open")
	for y: int in [4, 5]:
		for x: int in [3, 4]: battle.terrain[Vector2i(x, y)] = "water"
	check(reachable(battle, start, gate), "right bridge is an independent route")
	for y: int in [4, 5]:
		for x: int in [3, 4]: battle.terrain[Vector2i(x, y)] = "bridge"
		for x: int in [9, 10]: battle.terrain[Vector2i(x, y)] = "water"
	check(reachable(battle, start, gate), "left bridge is an independent route")
	for y: int in [4, 5]:
		for x: int in [3, 4]: battle.terrain[Vector2i(x, y)] = "water"
	check(not reachable(battle, start, gate), "water blocks passage when both bridges are shut")
	var campaign: RefCounted = Campaign.new()
	for plan: String in ["joint", "split", "hold"]:
		var scenario: Dictionary = campaign.index.scenarios["c10_" + plan + "_gate"]
		check(Campaign.validate_scenario(scenario).is_empty(), "plan-specific gate scenario validates: " + plan)
		var live: Battle = Model.new(int(scenario.seed), scenario.map, scenario.hero, scenario.enemy_class, scenario.deck, scenario.enemy_deck)
		check(live.configure_objective(scenario.control).ok and live.objective.cells == [[3, 3], [10, 3]], "plan-specific gate objective is active: " + plan)
	if DisplayServer.get_name() != "headless":
		var game: Node = MainScene.instantiate()
		game.deck_store = Store.new("res://.tools/v034-towergate-deck.json")
		root.add_child(game)
		current_scene = game
		game.current_map = "towergate"
		game._new_match(1034)
		game.council.hide()
		game.has_started = true
		if not game.expanded_battlefield: game._toggle_battlefield()
		for frame: int in range(8): await process_frame
		check(game.battle.width == 14 and game.battle.height == 12 and game.board.grid_rect().size.x > 600, "native battle board fits the larger gate map")
		for cell: Vector2i in [Vector2i(0, 0), Vector2i(3, 5), Vector2i(9, 5), Vector2i(13, 11)]:
			check(game.board.cell_from_point(game.board.cell_center(cell)) == cell, "native pointer hits exact gate map cell")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/screenshots/v034-towergate-map.png") == OK, "native gate map capture saved")
		game.queue_free()
		await process_frame
	print("TOWER GATE MAP: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
