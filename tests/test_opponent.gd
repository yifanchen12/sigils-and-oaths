extends SceneTree

const BattleModel = preload("res://scripts/battle.gd")
const EnemyAI = preload("res://scripts/opponent.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func fresh() -> Battle:
	var game: Battle = BattleModel.new(77, "greenwood", "grove", "warden")
	game.terrain.clear()
	game.players[0].hand.clear()
	game.players[0].mana = 0
	game.commander(0).pos = Vector2i(0, 9)
	game.commander(1).pos = Vector2i(11, 0)
	return game

func troop(game: Battle, kind: String, at: Vector2i, side: int) -> Dictionary:
	var unit: Dictionary = game.get_unit(game._spawn(game.definition(kind), at, side))
	unit.summoning = false
	unit.moved = false
	unit.attacked = false
	return unit

func run() -> void:
	test_ranged_position()
	test_safe_draw()
	test_healer_support()
	test_public_information()
	print("OPPONENT CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_ranged_position() -> void:
	var game: Battle = fresh()
	var archer: Dictionary = troop(game, "archer", Vector2i(4, 4), 0)
	var enemy: Dictionary = troop(game, "sword", Vector2i(4, 3), 1)
	var before: String = var_to_str([game.players, game.units, game.turn])
	var action: Dictionary = EnemyAI.choose(game)
	check(before == var_to_str([game.players, game.units, game.turn]), "choosing a position does not mutate battle")
	check(action.type == "move" and action.get("unit_id", -1) == archer.id, "adjacent archer repositions before attacking")
	if action.type == "move":
		check(game.apply_action(action).ok and game.distance(archer.pos, enemy.pos) > 1, "reposition legally leaves melee range")
		var follow: Dictionary = EnemyAI.choose(game)
		check(follow.type == "attack" and follow.get("unit_id", -1) == archer.id, "ranged reposition preserves same-turn attack")
		if follow.type == "attack":
			game.apply_action(follow)
			check(archer.hp == archer.max_hp and enemy.hp < enemy.max_hp, "ranged attack lands without avoidable melee retaliation")
	var victory: Battle = fresh()
	victory.commander(1).pos = Vector2i(4, 3)
	victory.commander(1).hp = 1
	troop(victory, "archer", Vector2i(4, 4), 0)
	var winning: Dictionary = EnemyAI.choose(victory)
	check(winning.type == "attack" and victory.apply_action(winning).ok and victory.winner == 0, "immediate commander kill takes priority over retreat")

func test_safe_draw() -> void:
	var game: Battle = fresh()
	game.players[0].deck.resize(1)
	game.players[0].fatigue = 3
	game.commander(0).hp = 2
	game.players[0].mana = 10
	game.add_generated_card(0, "insight")
	var draw: Dictionary = game.players[0].hand[0]
	check(EnemyAI.evaluate(game, {"type": "play", "card_uid": draw.uid, "target": Vector2i(-1, -1)}) < 0, "AI refuses draw-two with one card left and lethal fatigue")

func test_public_information() -> void:
	var game: Battle = fresh()
	troop(game, "sword", Vector2i(5, 6), 0)
	var first: Dictionary = EnemyAI.choose(game)
	for card: Dictionary in game.players[1].hand: card.card_id = "bolt"
	game.players[1].deck.reverse()
	check(first == EnemyAI.choose(game), "enemy hidden hand and deck order cannot influence decision")

func test_healer_support() -> void:
	var game: Battle = fresh()
	var healer: Dictionary = troop(game, "healer", Vector2i(3, 7), 0)
	var wounded: Dictionary = troop(game, "sword", Vector2i(6, 7), 0)
	wounded.hp = 1
	wounded.moved = true
	wounded.attacked = true
	var action: Dictionary = EnemyAI.choose(game)
	check(action.type == "move" and action.get("unit_id", -1) == healer.id, "healer seeks reachable support position")
	if action.type == "move":
		check(game.apply_action(action).ok and game.distance(healer.pos, wounded.pos) <= 1, "healer moves adjacent to wounded ally rather than rushing past")
