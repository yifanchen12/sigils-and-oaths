extends SceneTree
const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const GoalAI = preload("res://scripts/objective_ai.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func fresh(side: int = 0, cells: Array = [[4, 4], [7, 5]]) -> Battle:
	var battle: Battle = Model.new(3317, "ridgepass", "warden", "warden")
	for cell: Vector2i in battle.terrain: battle.terrain[cell] = "plain"
	battle.configure_objective({"cells": cells, "required": 2, "round_limit": 10})
	for player: Dictionary in battle.players: player.hand.clear(); player.mana = 0
	battle.active_side = side; battle.turn = 3 + side
	battle.objective.last_check = 3
	battle.commander(0).pos = Vector2i(0, 9); battle.commander(1).pos = Vector2i(11, 0)
	return battle
func troop(battle: Battle, kind: String, cell: Vector2i, side: int) -> Dictionary:
	return Fixture.troop(battle, kind, cell, side)
func attackable_control() -> Battle:
	var battle: Battle = fresh(1)
	battle.commander(1).pos = Vector2i(4, 1)
	troop(battle, "archer", Vector2i(4, 2), 1)
	troop(battle, "healer", Vector2i(4, 4), 0)
	troop(battle, "spear", Vector2i(7, 5), 0)
	battle.objective.streak = 1
	return battle
func test_take_and_hold() -> void:
	var battle: Battle = fresh()
	var resident: Dictionary = troop(battle, "spear", Vector2i(4, 4), 0)
	var arriving: Dictionary = troop(battle, "sword", Vector2i(7, 7), 0)
	var action: Dictionary = AI.choose(battle)
	check(action.type == "move" and action.unit_id == arriving.id and action.target == Vector2i(7, 5), "capture second point without vacating first")
	check(battle.apply_action(action).ok, "capture uses a real legal move")
	arriving.attacked = true
	resident.attacked = true
	var held: Dictionary = AI.choose(battle)
	check(held.type == "end_turn", "occupied objectives are held instead of chasing a distant commander")
	var defender: Battle = fresh(1)
	var blocker: Dictionary = troop(defender, "sword", Vector2i(4, 3), 1)
	var seize: Dictionary = AI.choose(defender)
	check(seize.type == "move" and seize.unit_id == blocker.id and seize.target == Vector2i(4, 4), "defender proactively occupies an empty objective")
	defender.apply_action(seize); blocker.moved = false; blocker.attacked = true
	check(AI.choose(defender).type == "end_turn", "sole defender does not abandon its blocking point")
func test_deploy() -> void:
	var battle: Battle = fresh()
	battle.commander(0).pos = Vector2i(4, 3)
	battle.players[0].mana = 1
	battle.add_generated_card(0, "sword")
	var action: Dictionary = AI.choose(battle)
	check(action.type == "play" and action.target == Vector2i(4, 4), "legal adjacent reinforcement can claim a point immediately")
	check(battle.apply_action(action).ok and battle.unit_at(Vector2i(4, 4)).summoning, "newborn deployment counts without granting premature attacks")
func test_guard_and_spells() -> void:
	var battle: Battle = attackable_control()
	battle.unit_at(Vector2i(4, 4)).hp = 2
	var guard: Dictionary = troop(battle, "spear", Vector2i(5, 4), 0); guard.guarding = true
	var shooter: Dictionary = battle.unit_at(Vector2i(4, 2))
	var attack: Dictionary = {"type": "attack", "unit_id": shooter.id, "target": Vector2i(4, 4)}
	var context: Dictionary = GoalAI.prepare(battle)
	check(GoalAI.value(battle, attack, context) == 0, "guard interception does not fabricate removal of the protected objective occupant")
	battle.players[1].mana = 3
	battle.add_generated_card(1, "frostbind"); battle.add_generated_card(1, "bolt")
	var root_card: Dictionary = battle.players[1].hand[0]
	var root_action: Dictionary = {"type": "play", "card_uid": root_card.uid, "target": Vector2i(4, 4)}
	check(GoalAI.value(battle, root_action, context) == 0, "rooting a point occupant does not break control")
	var choice: Dictionary = AI.choose(battle)
	check(choice.type == "play" and battle.hand_card(1, choice.card_uid).card_id == "bolt", "defender uses bypassing spell to interrupt imminent control victory")
	check(battle.apply_action(choice).ok and battle.unit_at(Vector2i(4, 4)).is_empty() and guard.hp == guard.max_hp, "spell removes actual occupant, not the guard")
	battle.end_turn()
	check(battle.winner == -1 and battle.objective.streak == 0, "denial prevents the otherwise winning next checkpoint")
func test_repulse() -> void:
	var battle: Battle = attackable_control()
	battle.players[1].mana = 3
	battle.add_generated_card(1, "repulse")
	var card: Dictionary = battle.players[1].hand[0]
	var action: Dictionary = {"type": "play", "card_uid": card.uid, "target": Vector2i(4, 4)}
	var before: Dictionary = GoalAI.prepare(battle)
	check(GoalAI.value(battle, action, before) > 0, "legal knockback receives value for opening a control point")
	var target: Dictionary = battle.unit_at(Vector2i(4, 4))
	var blocker: Dictionary = troop(battle, "spear", Vector2i(4, 5), 0)
	check(GoalAI.value(battle, action, GoalAI.prepare(battle)) == 0, "blocked nonlethal knockback does not fabricate displacement")
	battle.units.erase(blocker)
	var choice: Dictionary = AI.choose(battle)
	check(choice.type == "play" and choice.card_uid == card.uid and choice.target == target.pos, "defender chooses knockback before ending a lost turn")
	check(battle.apply_action(choice).ok and target.hp > 0 and target.pos == Vector2i(4, 5), "knockback interrupts ownership without requiring a kill")
func test_win_and_counter() -> void:
	var battle: Battle = attackable_control()
	battle.commander(0).pos = Vector2i(4, 3); battle.commander(0).hp = 1
	var action: Dictionary = AI.choose(battle)
	check(action.type == "attack" and action.target == battle.commander(0).pos, "immediate commander victory outranks objective manoeuvres")
	check(battle.apply_action(action).ok and battle.winner == 1, "chosen victory resolves through actual combat rules")
	battle = fresh()
	var weak: Dictionary = troop(battle, "mage", Vector2i(4, 4), 0); weak.hp = 1; weak.moved = true
	troop(battle, "spear", Vector2i(7, 5), 0).attacked = true
	troop(battle, "spear", Vector2i(4, 3), 1)
	check(AI.choose(battle).type == "end_turn", "do not surrender a held point to a losing counterattack")
func test_area_swap_support() -> void:
	var battle: Battle = fresh(1, [[4, 4], [5, 4]])
	battle.commander(1).pos = Vector2i(4, 1)
	var exposed: Dictionary = troop(battle, "healer", Vector2i(4, 4), 0); exposed.hp = 3
	var shielded: Dictionary = troop(battle, "spear", Vector2i(5, 4), 0); shielded.shield = 2
	battle.players[1].mana = 4; battle.add_generated_card(1, "nova"); battle.objective.streak = 1
	var action: Dictionary = {"type": "play", "card_uid": battle.players[1].hand[0].uid, "target": exposed.pos}
	var context: Dictionary = GoalAI.prepare(battle)
	var predicted: float = GoalAI.value(battle, action, context)
	check(battle.apply_action(action).ok, "area denial is a legal in-range spell")
	check(battle.unit_at(Vector2i(4, 4)).is_empty() and shielded.hp == 6 and shielded.shield == 0, "area forecast respects each occupant's independent shield and health")
	var after: Array[int] = GoalAI.ownership(battle.units, context.cells)
	check(predicted == GoalAI.position_value(after, 1, 1) - GoalAI.position_value(context.owners, 1, 1), "area objective utility matches actual surviving occupants")
	battle = fresh()
	battle.commander(0).pos = Vector2i(4, 3)
	troop(battle, "spear", Vector2i(4, 4), 0); troop(battle, "spear", Vector2i(7, 5), 0)
	battle.players[0].mana = 2; battle.add_generated_card(0, "exchange")
	action = {"type": "play", "card_uid": battle.players[0].hand[0].uid, "target": Vector2i(4, 4)}
	check(GoalAI.value(battle, action, GoalAI.prepare(battle)) == 0, "commander exchange keeps control and cannot manufacture a new capture")
	check(battle.apply_action(action).ok and battle.commander(0).pos == Vector2i(4, 4), "real exchange preserves both occupied points")
	battle = fresh()
	battle.commander(0).pos = Vector2i(4, 3)
	var resident: Dictionary = troop(battle, "spear", Vector2i(4, 4), 0)
	var other: Dictionary = troop(battle, "spear", Vector2i(5, 3), 0)
	for unit: Dictionary in [resident, other]: unit.hp = 1; unit.moved = true; unit.attacked = true
	battle.players[0].mana = 2; battle.players[0].skill_cooldown = 1; battle.add_generated_card(0, "heal")
	action = AI.choose(battle)
	check(action.type == "play" and action.target == resident.pos, "equally hurt units prioritize keeping the objective defender alive")
	check(battle.apply_action(action).ok and resident.hp == 6 and other.hp == 1, "support choice executes actual capped healing without moving occupants")
func test_path_and_information() -> void:
	var battle: Battle = fresh(0, [[8, 2], [9, 2]])
	var walker: Dictionary = troop(battle, "sword", Vector2i(4, 2), 0)
	for y: int in range(7): battle.terrain[Vector2i(5, y)] = "mountain"
	var before: String = var_to_str([battle.units, battle.players, battle.terrain, battle.objective, battle.rng.state])
	var action: Dictionary = AI.choose(battle)
	check(action.type == "move" and action.target.y > walker.pos.y and battle.apply_action(action).ok, "goal approach follows a real gap instead of straight-line wall distance")
	before = var_to_str([battle.units, battle.players, battle.terrain, battle.objective, battle.rng.state])
	var first: Dictionary = AI.choose(battle)
	check(before == var_to_str([battle.units, battle.players, battle.terrain, battle.objective, battle.rng.state]), "objective decision is read-only including RNG")
	battle.players[1].hand = [{"uid": 99999, "card_id": "bolt"}]
	battle.players[1].deck.reverse(); battle.players[0].deck.reverse()
	check(first == AI.choose(battle), "opponent hand and hidden deck orders cannot affect objective choice")
func run() -> void:
	test_take_and_hold(); test_deploy(); test_guard_and_spells(); test_repulse(); test_win_and_counter(); test_area_swap_support(); test_path_and_information()
	print("OBJECTIVE AI CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
