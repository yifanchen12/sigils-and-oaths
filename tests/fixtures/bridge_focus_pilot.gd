extends RefCounted
## Test-only player strategy for c01_bridge: full movement risk, visible
## wounded/healer targets and a fixed left-bridge approach. Never shipped as enemy AI.
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
		var score: float = AI.evaluate(battle, action, fields, objectives) + Tactics.value(battle, action, threats) + focus_action(battle, action) + lane_value(battle, action)
		if score > best_score: best = action; best_score = score
	return best
static func target_value(battle: Battle, target: Dictionary, damage: int, actor: int) -> float:
	var value: float = (int(target.max_hp) - int(target.hp)) * 2.0
	if target.kind == "healer":
		value += 24.0
		for ally: Dictionary in battle.units:
			if ally.side == target.side and ally.id != target.id and battle.distance(ally.pos, target.pos) <= 1: value += 5.0
	var pressure: int = damage
	var contributors: int = 0
	for ally: Dictionary in battle.units:
		if ally.side != battle.active_side or ally.id == actor or ally.summoning or ally.attacked: continue
		if battle.distance(ally.pos, target.pos) > battle.attack_range(ally): continue
		var forecast: Dictionary = battle.attack_forecast(ally, target)
		if forecast.defender_id != target.id: continue
		pressure += int(forecast.damage); contributors += 1
	if contributors > 0 and damage < int(target.hp) + int(target.shield) and pressure >= int(target.hp) + int(target.shield): value += 30.0
	return value
static func focus_action(battle: Battle, action: Dictionary) -> float:
	var unit: Dictionary = battle.get_unit(int(action.get("unit_id", -1)))
	if action.type == "attack" or (action.type == "unit_skill" and unit.kind == "archer"):
		var forecast: Dictionary = battle.attack_forecast(unit, battle.unit_at(action.target), 1 if action.type == "unit_skill" else 0)
		return target_value(battle, battle.get_unit(forecast.defender_id), forecast.damage, unit.id)
	if action.type == "unit_skill" and unit.kind == "mage": return target_value(battle, battle.unit_at(action.target), battle.fire_damage(3), unit.id)
	if action.type == "play":
		var card: Dictionary = battle.definition(battle.hand_card(battle.active_side, action.card_uid).card_id)
		if card.get("effect", "") not in ["damage", "area"]: return 0.0
		var score: float = 0.0
		for enemy: Dictionary in battle.units:
			if enemy.side != battle.active_side and (enemy.pos == action.target or (card.effect == "area" and battle.distance(enemy.pos, action.target) <= 1)):
				score += target_value(battle, enemy, battle.spell_damage(card, battle.active_side), -1)
		return score
	if action.type == "move" and not unit.attacked:
		var candidate: Dictionary = unit.duplicate(); candidate.pos = action.target; candidate.last_move_distance = battle.distance(unit.pos, action.target)
		var score: float = 0.0
		for enemy: Dictionary in battle.units:
			if enemy.side == battle.active_side or battle.distance(candidate.pos, enemy.pos) > battle.attack_range(candidate): continue
			var forecast: Dictionary = battle.attack_forecast(candidate, enemy)
			score = maxf(score, target_value(battle, battle.get_unit(forecast.defender_id), forecast.damage, unit.id))
		return score
	return 0.0

static func lane_value(battle: Battle, action: Dictionary) -> float:
	if battle.map_definition.id != "rivergate" or not battle.objective.is_empty(): return 0.0
	var lane: int = 3
	if action.type == "play":
		var card: Dictionary = battle.definition(battle.hand_card(battle.active_side, action.card_uid).card_id)
		if card.type == "unit" and action.target.y >= 4: return -absf(action.target.x - lane) * 8.0
	if action.type == "move":
		var unit: Dictionary = battle.get_unit(action.unit_id)
		if unit.pos.y >= 4:
			return (absf(unit.pos.x - lane) - (absf(action.target.x - lane) if action.target.y >= 4 else 0.0)) * 12.0
	return 0.0
