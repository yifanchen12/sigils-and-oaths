extends RefCounted
## Diagnostic player policy only. Uses the same public information and rules,
## but values potential enemy movement at full weight instead of 0.45.
const AI = preload("res://scripts/opponent.gd")
const Objectives = preload("res://scripts/objective_ai.gd")
const Tactics = preload("res://scripts/tactical_ai.gd")
static func choose(battle: Battle) -> Dictionary:
	var best: Dictionary = {"type": "end_turn"}
	var fields: Dictionary = {}
	var objectives: Dictionary = Objectives.prepare(battle)
	var threats: Dictionary = Tactics.prepare(battle, 1.0)
	var best_score: float = AI.evaluate(battle, best, fields, objectives)
	for unit: Dictionary in battle.units:
		if unit.side == battle.active_side and not battle.movement_cells(unit).is_empty(): fields[unit.id] = AI._approach_field(battle, unit)
	for action: Dictionary in battle.get_legal_actions(battle.active_side):
		var score: float = AI.evaluate(battle, action, fields, objectives) + Tactics.value(battle, action, threats)
		if score > best_score: best = action; best_score = score
	return best
