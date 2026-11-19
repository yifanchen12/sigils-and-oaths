extends RefCounted
## Test-only legal bridge assault policy; reads current public board and own hand.
const AI = preload("res://scripts/opponent.gd")
const Focus = preload("res://tests/fixtures/bridge_focus_pilot.gd")
const Objectives = preload("res://scripts/objective_ai.gd")
const Tactics = preload("res://scripts/tactical_ai.gd")

static func choose(battle: Battle) -> Dictionary:
	var best: Dictionary = {"type": "end_turn"}
	var fields: Dictionary = {}
	var objectives: Dictionary = Objectives.prepare(battle)
	var threats: Dictionary = Tactics.prepare(battle, 0.7)
	var south := Vector2i(5, 6)
	var stationed: Dictionary = battle.unit_at(south)
	var guard_needed: bool = stationed.is_empty() or stationed.side != battle.active_side
	var incursion: bool = battle.units.any(func(unit: Dictionary) -> bool: return unit.side != battle.active_side and unit.pos.y >= 7)
	var home_threat: Dictionary = {}
	for unit: Dictionary in battle.units:
		if unit.side == battle.active_side or unit.pos.y < 7: continue
		if home_threat.is_empty() or battle.distance(unit.pos, battle.commander(0).pos) < battle.distance(home_threat.pos, battle.commander(0).pos): home_threat = unit
	var best_score: float = AI.evaluate(battle, best, fields, objectives, threats)
	for unit: Dictionary in battle.units:
		if unit.side == battle.active_side and not battle.movement_cells(unit).is_empty(): fields[unit.id] = AI._approach_field(battle, unit)
	for action: Dictionary in battle.get_legal_actions(battle.active_side):
		var score: float = AI.evaluate(battle, action, fields, objectives, threats) + Tactics.value(battle, action, threats) + Focus.focus_action(battle, action)
		if action.type == "move":
			var unit: Dictionary = battle.get_unit(action.unit_id)
			if unit.kind != "commander":
				if unit.pos == south: score -= 250.0
				if guard_needed and action.target == south: score += 180.0
				if incursion and not home_threat.is_empty(): score += maxi(0, battle.distance(unit.pos, home_threat.pos) - battle.distance(action.target, home_threat.pos)) * 35.0
				if not guard_needed:
					score += maxi(0, unit.pos.y - action.target.y) * 22.0
					if action.target.y <= 5: score += 25.0
					if battle.objective.cells.has([action.target.x, action.target.y]): score += 80.0
		if action.type == "play":
			var card: Dictionary = battle.definition(battle.hand_card(battle.active_side, action.card_uid).card_id)
			if card.type == "unit":
				if guard_needed and action.target == south: score += 160.0
				if incursion and not home_threat.is_empty() and battle.distance(action.target, home_threat.pos) <= 2: score += 90.0
				if not guard_needed: score += maxi(0, 8 - action.target.y) * 3.0
		if incursion and action.type == "attack" and battle.unit_at(action.target).pos.y >= 7: score += 125.0
		if incursion and action.type == "unit_skill" and battle.unit_at(action.target).get("side", battle.active_side) != battle.active_side and action.target.y >= 7: score += 100.0
		if incursion and action.type == "play" and battle.unit_at(action.target).get("side", battle.active_side) != battle.active_side and action.target.y >= 7: score += 90.0
		if action.type == "hero" and action.target == battle.commander(0).pos and battle.commander(0).hp < battle.commander(0).max_hp: score += 35.0
		if score > best_score: best = action; best_score = score
	return best
