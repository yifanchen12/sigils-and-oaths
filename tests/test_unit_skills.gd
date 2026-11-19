extends SceneTree

const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func fresh() -> Battle:
	var game: Battle = Model.new(71)
	for cell: Vector2i in game.terrain: game.terrain[cell] = "plain"
	game.players[0].mana = 10
	game.players[0].max_mana = 10
	return game

func troop(game: Battle, kind: String, at: Vector2i, side: int = 0) -> Dictionary:
	var result: Dictionary = game.get_unit(game._spawn(game.definition(kind), at, side))
	result.moved = false; result.attacked = false; result.summoning = false
	return result

func use(game: Battle, unit: Dictionary, target: Vector2i) -> Dictionary:
	return game.apply_action({"type": "unit_skill", "unit_id": unit.id, "target": target})

func snapshot(game: Battle) -> String:
	return var_to_str([game.players, game.units, game.terrain, game.rng.state, game.log_lines, game.next_id])

func run() -> void:
	var game: Battle = fresh()
	var sword: Dictionary = troop(game, "sword", Vector2i(4, 5))
	check(game.unit_skill(game.commander(0)).is_empty(), "commander has no troop skill")
	check(use(game, sword, sword.pos).ok and sword.shield == 3, "sword grants three shield")
	check(sword.attacked and sword.moved and sword.skill_used and game.players[0].mana == 9, "skill pays exact mana and ends action")
	var before: String = snapshot(game)
	check(not use(game, sword, sword.pos).ok and before == snapshot(game), "repeat skill is rejected atomically")
	game.end_turn(); game.end_turn()
	check(not sword.skill_used and not sword.attacked, "next own turn resets skill and action")
	check(game.skill_targets(sword).is_empty(), "shield at cap does not waste action")
	for kind: String in ["sword", "spear", "cavalry", "archer", "mage", "healer"]:
		game = fresh()
		var unit: Dictionary = troop(game, kind, Vector2i(4, 5))
		unit.summoning = true
		before = snapshot(game)
		check(game.skill_targets(unit).is_empty() and not use(game, unit, unit.pos).ok and before == snapshot(game), kind + " newborn skill rejected without mutation")
		unit.summoning = false
		game.players[0].mana = 0
		before = snapshot(game)
		check(game.skill_targets(unit).is_empty() and not use(game, unit, unit.pos).ok and before == snapshot(game), kind + " insufficient mana is atomic")
	game = fresh()
	var rider: Dictionary = troop(game, "cavalry", Vector2i(3, 5))
	check(game.skill_targets(rider).is_empty(), "rider must move before extra movement")
	check(game.apply_action({"type": "move", "unit_id": rider.id, "target": Vector2i(4, 5)}).ok, "rider first move")
	game.terrain[Vector2i(5, 5)] = "forest"
	check(not game.skill_targets(rider).has(Vector2i(5, 5)), "extra move pays forest cost three")
	check(use(game, rider, Vector2i(4, 3)).ok and rider.pos == Vector2i(4, 3), "extra movement reaches two-cost destination")
	check(not rider.attacked and rider.last_move_distance == 3 and rider.skill_used, "extra move retains attack and charge distance")
	check(game.skill_targets(rider).is_empty(), "rider skill once per turn")
	game = fresh()
	var archer: Dictionary = troop(game, "archer", Vector2i(4, 5))
	var victim: Dictionary = troop(game, "sword", Vector2i(4, 2), 1)
	var expected: int = game.damage_preview(archer, victim) + 1
	check(use(game, archer, victim.pos).ok and victim.hp == victim.max_hp - expected, "archer precise shot adds one to normal damage")
	game = fresh()
	archer = troop(game, "archer", Vector2i(4, 5)); victim = troop(game, "sword", Vector2i(4, 2), 1)
	game.weather = "fog"
	check(not game.skill_targets(archer).has(victim.pos), "precise shot obeys fog range")
	for weather: String in ["clear", "rain", "sun"]:
		game = fresh(); game.weather = weather
		var mage: Dictionary = troop(game, "mage", Vector2i(4, 5))
		victim = troop(game, "spear", Vector2i(4, 3), 1); victim.shield = 1
		game.terrain[victim.pos] = "fort"
		expected = game.fire_damage(3) - 1
		check(use(game, mage, victim.pos).ok and victim.hp == victim.max_hp - expected, "mage ignores armor, shield absorbs, weather applies: " + weather)
	game = fresh()
	var healer: Dictionary = troop(game, "healer", Vector2i(4, 5))
	var ally: Dictionary = troop(game, "sword", Vector2i(4, 3)); ally.hp = 4
	check(use(game, healer, ally.pos).ok and ally.hp == 5, "healer respects health cap at range two")
	game = fresh(); healer = troop(game, "healer", Vector2i(4, 5)); healer.hp = 1
	check(use(game, healer, healer.pos).ok and healer.hp == 4, "healer may heal itself")
	guard_cases()
	ai_cases()
	print("UNIT SKILL CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func guard_cases() -> void:
	var game: Battle = fresh()
	var guard: Dictionary = troop(game, "spear", Vector2i(5, 5))
	var ally: Dictionary = troop(game, "mage", Vector2i(4, 5))
	var attacker: Dictionary = troop(game, "cavalry", Vector2i(4, 4), 1)
	check(use(game, guard, guard.pos).ok and guard.guarding, "spear activates guard")
	game.end_turn()
	check(guard.guarding, "guard survives opponent turn start")
	var before: String = snapshot(game)
	var forecast: Dictionary = game.attack_forecast(attacker, ally)
	check(snapshot(game) == before and forecast.intercepted and forecast.defender_id == guard.id, "read-only forecast selects guard")
	var initial_guard_hp: int = guard.hp
	var initial_attacker_hp: int = attacker.hp
	check(game.apply_action({"type": "attack", "unit_id": attacker.id, "target": ally.pos}).ok, "attack protected target remains legal")
	check(ally.hp == ally.max_hp and guard.hp == initial_guard_hp - forecast.target_loss, "only guard takes incoming damage")
	check(attacker.hp == initial_attacker_hp - forecast.attacker_loss and forecast.attacker_loss == 0, "guard cannot retaliate outside own range")
	check(guard.pos == Vector2i(5, 5) and ally.pos == Vector2i(4, 5), "guard never changes rule positions")
	game.end_turn()
	check(not guard.guarding and not guard.skill_used, "guard expires at next own turn")
	# Separate fixtures cover range, deterministic selection, disabling and lethal hits.
	game = fresh(); guard = troop(game, "spear", Vector2i(4, 4)); ally = troop(game, "mage", Vector2i(4, 5))
	attacker = troop(game, "sword", Vector2i(3, 4), 1)
	guard.guarding = true
	var other: Dictionary = troop(game, "spear", Vector2i(5, 5)); other.guarding = true
	check(game.attack_defender(attacker, ally).id == guard.id, "multiple guards choose lowest stable id")
	guard.rooted_turns = 2
	check(game.attack_defender(attacker, ally).id == other.id, "rooted guard cannot intercept")
	other.guarding = false
	check(game.attack_defender(attacker, ally).id == ally.id, "no eligible guard means original target")
	guard.rooted_turns = 0; guard.hp = 0
	check(game.attack_defender(attacker, ally).id == ally.id, "dead guard cannot intercept")
	guard.hp = 7; guard.pos = Vector2i(3, 3)
	check(game.attack_defender(attacker, ally).id == ally.id, "guard does not protect diagonal or distant ally")
	# Guard can intercept a legal distant shot, but defense and return range use its own cell.
	guard.pos = Vector2i(4, 4); game.terrain[guard.pos] = "fort"
	attacker.pos = Vector2i(3, 5); attacker.range = 3
	game.end_turn()
	forecast = game.attack_forecast(attacker, ally)
	check(forecast.damage == game.damage_preview(attacker, guard) and forecast.damage != game.damage_preview(attacker, ally), "guard uses own armor, terrain and unit counter")
	guard.hp = 1; attacker.atk = 20
	forecast = game.attack_forecast(attacker, ally)
	check(forecast.attacker_loss == 0, "lethal guard interception has no counter")
	check(game.apply_action({"type": "attack", "unit_id": attacker.id, "target": ally.pos}).ok and game.get_unit(guard.id).is_empty(), "lethal guard is cleaned up")
	check(ally.hp == ally.max_hp, "no spillover damage into protected ally")
	# Magic explicitly bypasses guard; freezing stops guard without preventing spell damage.
	game = fresh(); guard = troop(game, "spear", Vector2i(4, 4), 1); guard.guarding = true
	ally = troop(game, "mage", Vector2i(4, 3), 1)
	var mage: Dictionary = troop(game, "mage", Vector2i(4, 5))
	check(use(game, mage, ally.pos).ok and ally.hp == 1 and guard.hp == guard.max_hp, "mage skill bypasses guard")
	# A guard adjacent to a commander can protect it; a direct attack on a guard is not self-recursive.
	guard.side = 0; guard.pos = game.commander(0).pos + Vector2i.UP
	check(game.attack_defender(ally, game.commander(0)).id == guard.id, "guard may protect commander")
	check(game.attack_defender(ally, guard).id == guard.id, "direct guard target has no self interception")
	game = fresh(); guard = troop(game, "spear", Vector2i(4, 5), 1); guard.guarding = true
	ally = troop(game, "mage", Vector2i(5, 5), 1); attacker = troop(game, "archer", Vector2i(4, 4))
	forecast = game.attack_forecast(attacker, ally)
	var old_attacker_hp: int = attacker.hp
	check(forecast.counter_damage > 0 and game.apply_action({"type": "attack", "unit_id": attacker.id, "target": ally.pos}).ok and attacker.hp == old_attacker_hp - forecast.attacker_loss, "guard in return range retaliates exactly as predicted")

func ai_cases() -> void:
	var game: Battle = fresh()
	var medic: Dictionary = troop(game, "healer", Vector2i(4, 5))
	var ally: Dictionary = troop(game, "sword", Vector2i(4, 4)); ally.hp = 1
	var action: Dictionary = {"type": "unit_skill", "unit_id": medic.id, "target": ally.pos}
	check(game.get_legal_actions(0).has(action) and AI.evaluate(game, action) > 0, "AI sees useful legal healing skill")
	var before: String = snapshot(game)
	var chosen: Dictionary = AI.choose(game)
	check(snapshot(game) == before and game.get_legal_actions(0).has(chosen), "AI decision remains read-only and legal")
