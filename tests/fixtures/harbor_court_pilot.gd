extends "res://tests/fixtures/bridge_focus_pilot.gd"
## Test-only player for the harbor and court. Focus public wounded/support
## targets; the court's central fortifications favor a compact formation.
## No enemy hand, future draw order, seed or turn-specific script is used.
static func choose(battle: Battle) -> Dictionary:
	var best: Dictionary = {"type": "end_turn"}
	var fields: Dictionary = {}
	var objectives: Dictionary = Objectives.prepare(battle)
	var threats: Dictionary = Tactics.prepare(battle, 0.45 if battle.map_definition.id == "citadel" else 1.0)
	var best_score: float = AI.evaluate(battle, best, fields, objectives, threats)
	for unit: Dictionary in battle.units:
		if unit.side == battle.active_side and not battle.movement_cells(unit).is_empty(): fields[unit.id] = AI._approach_field(battle, unit)
	for action: Dictionary in battle.get_legal_actions(battle.active_side):
		var score: float = AI.evaluate(battle, action, fields, objectives, threats) + Tactics.value(battle, action, threats) + focus_action(battle, action) + formation(battle, action)
		if score > best_score: best = action; best_score = score
	return best

static func formation(battle: Battle, action: Dictionary) -> float:
	if battle.map_definition.id != "citadel": return 0.0
	# Midline of the visible central fortifications.
	var center: float = 5.5
	if action.type == "play":
		var card: Dictionary = battle.definition(battle.hand_card(battle.active_side, action.card_uid).card_id)
		if card.type == "unit": return -absf(action.target.x - center) * 8.0
	if action.type == "move":
		var unit: Dictionary = battle.get_unit(action.unit_id)
		return (absf(unit.pos.x - center) - absf(action.target.x - center)) * 12.0
	return 0.0
