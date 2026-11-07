extends SceneTree
const Model = preload("res://scripts/battle.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const CONFIG: Dictionary = {"cells": [[3, 5], [8, 5]], "required": 2, "round_limit": 12}
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func fresh() -> RefCounted:
	var battle: RefCounted = Model.new(2317, "rivergate")
	check(battle.configure_objective(CONFIG).ok, "authored control target configures")
	return battle
func occupy(battle: RefCounted) -> void:
	Fixture.troop(battle, "spear", Vector2i(3, 5), 0)
	Fixture.troop(battle, "sword", Vector2i(8, 5), 0)
func full_round(battle: RefCounted) -> void:
	battle.end_turn(); battle.end_turn()
func run() -> void:
	var battle: RefCounted = fresh()
	check(battle.objective.streak == 0 and battle.objective.last_check == 0, "initial position gets no free control credit")
	check(not battle.configure_objective(CONFIG).ok, "goal cannot reset its own progress")
	occupy(battle)
	battle.end_turn()
	check(battle.objective.streak == 0, "opponent turn does not count")
	battle.end_turn()
	check(battle.objective.streak == 1 and battle.winner == -1, "first full round yields one control credit")
	Model.ControlObjective.check_turn(battle)
	check(battle.objective.streak == 1, "same turn cannot count twice")
	var saved: Dictionary = Snapshot.capture(battle)
	var restored: Dictionary = Snapshot.restore(JSON.parse_string(JSON.stringify(saved, "", true, true)))
	check(restored.ok, "intermediate control state round trips")
	if restored.ok:
		check(Snapshot.capture(restored.battle) == saved, "restore performs no extra objective or turn resolution")
		full_round(restored.battle)
		check(restored.battle.winner == 0 and restored.battle.objective.streak == 2, "resumed next full round wins by control")
		check(Snapshot.restore(Snapshot.capture(restored.battle)).ok, "objective win validates with both commanders alive")
	battle.unit_at(Vector2i(3, 5)).pos = Vector2i(3, 6)
	full_round(battle)
	check(battle.objective.streak == 0 and battle.winner == -1, "missing one bridgehead breaks consecutive streak")
	battle = fresh()
	for round_index: int in range(11): full_round(battle)
	check(battle.winner == -1 and battle.turn == 23, "deadline does not fire a full round early")
	full_round(battle)
	check(battle.winner == 1 and battle.turn == 25, "twelfth full round without control loses")
	check(Snapshot.restore(Snapshot.capture(battle)).ok, "deadline loss round trips with living commanders")
	battle = fresh()
	for round_index: int in range(10): full_round(battle)
	occupy(battle); full_round(battle); full_round(battle)
	check(battle.winner == 0, "achieving required control on deadline wins")
	battle = fresh(); occupy(battle); full_round(battle)
	battle.commander(0).hp = 0; battle._cleanup(); battle._check_winner()
	Model.ControlObjective.check_turn(battle)
	check(battle.winner == 1, "commander defeat takes priority over objective credit")
	check(Snapshot.restore(Snapshot.capture(battle)).ok, "commander loss preserves valid objective state")
	battle = fresh(); battle.commander(1).hp = 0; battle._cleanup(); battle._check_winner()
	check(battle.winner == 0 and Snapshot.restore(Snapshot.capture(battle)).ok, "defeating opposing commander remains an alternate victory")
	for changed: Variant in [null, {"cells": [[3, 5], [3, 5]], "required": 2, "round_limit": 12}, {"cells": [[0, 4], [8, 5]], "required": 2, "round_limit": 12}, {"cells": [[3, 5], [8, 5]], "required": true, "round_limit": 12}]:
		check(not Model.ControlObjective.validate_config(changed, Model.MAPS.find("rivergate")).is_empty(), "bad target config rejected")
	for fields: Dictionary in [{"streak": 2}, {"last_check": 2}, {"last_check": 0}, {"streak": -1}]:
		var bad: Dictionary = saved.duplicate(true); bad.objective.merge(fields, true)
		check(not Snapshot.restore(bad).ok, "inconsistent objective progress rejected")
	var classic: RefCounted = Model.new()
	var legacy: Dictionary = Snapshot.capture(classic); legacy.version = 1; legacy.erase("objective")
	check(Snapshot.restore(legacy).ok and Snapshot.restore(legacy).battle.objective.is_empty(), "v1 skirmish snapshot migrates without inventing an objective")
	legacy.version = 2
	check(not Snapshot.restore(legacy).ok, "new snapshot requires objective field even for skirmish")
	print("CONTROL OBJECTIVE CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
