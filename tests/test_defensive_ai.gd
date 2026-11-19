extends "res://tests/test_opponent.gd"
const Snapshot = preload("res://scripts/battle_snapshot.gd")

func skill(unit: Dictionary) -> Dictionary:
	return {"type":"unit_skill", "unit_id":unit.id, "target":unit.pos}

func run() -> void:
	test_guard_paths()
	test_shield_gain()
	test_existing_guard()
	test_magic_bypass()
	test_forecast_against_real_attacks()
	print("DEFENSIVE AI CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_guard_paths() -> void:
	var game: Battle = fresh(); game.players[0].mana = 1
	var leader: Dictionary = game.commander(0); leader.pos = Vector2i(4, 6); leader.hp = 1
	var guard: Dictionary = troop(game, "spear", Vector2i(5, 6), 0)
	var enemy: Dictionary = troop(game, "sword", Vector2i(4, 3), 1)
	for x: int in range(game.width): game.terrain[Vector2i(x, 4)] = "mountain"
	var before: Dictionary = Snapshot.capture(game)
	check(EnemyAI.evaluate(game, skill(guard)) <= 0, "a wall-blocked enemy gives no guard benefit")
	check(Snapshot.capture(game) == before, "guard scoring leaves the real battle unchanged")
	game.terrain[Vector2i(4, 4)] = "hill"
	check(EnemyAI.evaluate(game, skill(guard)) <= 0, "a costly gap still prevents the enemy reaching attack range")
	game.terrain[Vector2i(4, 4)] = "plain"; enemy.rooted_turns = 2
	check(EnemyAI.evaluate(game, skill(guard)) <= 0, "a root that lasts through the next turn prevents the approach")
	enemy.rooted_turns = 1; enemy.summoning = true; enemy.moved = true; enemy.attacked = true
	check(EnemyAI.evaluate(game, skill(guard)) > 0, "expiring root and newborn status permit a real threat next turn")
	check(game.apply_action(skill(guard)).ok, "use actual guard rather than a forecast-only flag")
	game.end_turn()
	check(game.apply_action({"type":"move", "unit_id":enemy.id, "target":Vector2i(4, 5)}).ok, "enemy actually reaches the opened gap after refreshing")
	check(game.apply_action({"type":"attack", "unit_id":enemy.id, "target":leader.pos}).ok and leader.hp == 1 and guard.hp < guard.max_hp and game.winner == -1, "guard actually intercepts the commander-lethal attack")

func test_shield_gain() -> void:
	var game: Battle = fresh(); game.players[0].mana = 1
	var sword: Dictionary = troop(game, "sword", Vector2i(4, 6), 0)
	var enemy: Dictionary = troop(game, "healer", Vector2i(4, 4), 1)
	sword.shield = 2
	var before: Dictionary = Snapshot.capture(game)
	check(game.damage_preview(enemy, sword) == 1, "existing shield can absorb this enemy's ordinary attack")
	check(EnemyAI.evaluate(game, skill(sword)) <= 0, "do not spend the whole action topping up an already sufficient shield")
	check(Snapshot.capture(game) == before, "defense scoring leaves cards, flags, clock and RNG untouched")
	game.end_turn()
	check(game.apply_action({"type":"attack", "unit_id":enemy.id, "target":sword.pos}).ok and sword.hp == sword.max_hp and sword.shield == 1, "without topping up, the actual attack causes no health loss")
	game = fresh(); game.players[0].mana = 1
	sword = troop(game, "sword", Vector2i(4, 6), 0)
	enemy = troop(game, "sword", Vector2i(4, 4), 1)
	for x: int in range(game.width): game.terrain[Vector2i(x, 5)] = "mountain"
	var blocked_value: float = EnemyAI.evaluate(game, skill(sword))
	enemy.pos = Vector2i(11, 1)
	check(blocked_value == EnemyAI.evaluate(game, skill(sword)), "wall-blocked melee does not add an urgent shield bonus beyond ordinary preparation")
	game = fresh(); game.players[0].mana = 1
	sword = troop(game, "sword", Vector2i(4, 6), 0); sword.hp = 1
	enemy = troop(game, "archer", Vector2i(4, 4), 1)
	enemy.rooted_turns = 2
	check(EnemyAI.evaluate(game, skill(sword)) > 0 and game.apply_action(skill(sword)).ok, "shield still has value against a real ranged threat")
	game.end_turn()
	check(game.apply_action({"type":"attack", "unit_id":enemy.id, "target":sword.pos}).ok and sword.hp == 1, "the shield really prevents an otherwise lethal ranged hit")

func test_existing_guard() -> void:
	var game: Battle = fresh(); game.players[0].mana = 1
	var leader: Dictionary = game.commander(0); leader.pos = Vector2i(4, 6); leader.hp = 1
	var first: Dictionary = troop(game, "spear", Vector2i(5, 6), 0); first.guarding = true
	var second: Dictionary = troop(game, "spear", Vector2i(3, 6), 0)
	troop(game, "archer", Vector2i(4, 3), 1).rooted_turns = 2
	check(EnemyAI.evaluate(game, skill(second)) <= 0, "a second guard earns no credit for an ally already covered by the earlier guard")

func test_magic_bypass() -> void:
	var game: Battle = fresh(); game.players[0].mana = 1
	var leader: Dictionary = game.commander(0); leader.pos = Vector2i(4, 6); leader.hp = 1
	var guard: Dictionary = troop(game, "spear", Vector2i(5, 6), 0)
	var mage: Dictionary = troop(game, "mage", Vector2i(4, 4), 1); mage.rooted_turns = 2
	check(EnemyAI.evaluate(game, skill(guard)) <= 0, "guard gets no survival credit against a mage with an equally lethal bypass spell")
	check(game.apply_action(skill(guard)).ok, "guard remains legal for a human choosing it")
	game.end_turn()
	check(game.apply_action({"type":"unit_skill", "unit_id":mage.id, "target":leader.pos}).ok and game.winner == 1 and guard.hp == guard.max_hp, "actual fire bypasses the guard and kills the exposed commander")

func test_forecast_against_real_attacks() -> void:
	for kind: String in ["sword", "spear", "cavalry", "archer", "mage", "healer"]:
		for ground: String in ["plain", "hill", "fort"]:
			var game: Battle = fresh()
			var target: Dictionary = troop(game, "spear", Vector2i(4, 6), 0)
			var enemy: Dictionary = troop(game, kind, Vector2i(4, 3), 1)
			var destination := Vector2i(4, 5)
			game.terrain[destination] = ground; game.terrain[target.pos] = "fort"
			# Start closer when the uphill cost would exceed a slow unit's move.
			if ground == "hill" and enemy.move == 2: enemy.pos = Vector2i(4, 4)
			var forecast: int = EnemyAI.TacticalAI._future_attack_damage(game, enemy, destination, target)
			game.end_turn()
			check(game.apply_action({"type":"move", "unit_id":enemy.id, "target":destination}).ok, "forecast firing position is actually reachable: " + kind + "/" + ground)
			var attack: Dictionary = {"type":"unit_skill" if kind == "archer" else "attack", "unit_id":enemy.id, "target":target.pos}
			check(game.apply_action(attack).ok and target.hp == maxi(0, int(target.max_hp) - forecast), "future attack estimate matches real armor, elevation and precision damage: " + kind + "/" + ground)
	for kind: String in ["sword", "spear"]:
		var game: Battle = fresh()
		var target: Dictionary = troop(game, kind, Vector2i(4, 5), 0)
		var enemy: Dictionary = troop(game, "cavalry", Vector2i(4, 2), 1)
		game.terrain[Vector2i(4, 3)] = "mountain"
		game.terrain[target.pos] = "fort"
		var destination := Vector2i(4, 4)
		var forecast: int = EnemyAI.TacticalAI._future_attack_damage(game, enemy, destination, target)
		game.end_turn()
		check(game.apply_action({"type":"move", "unit_id":enemy.id, "target":destination}).ok and enemy.last_move_distance == 4, "short-distance cavalry destination actually requires four steps around the blocker")
		check(game.apply_action({"type":"attack", "unit_id":enemy.id, "target":target.pos}).ok and target.hp == maxi(0, int(target.max_hp) - forecast), "detour charge is counted before minimum-damage clamping")
