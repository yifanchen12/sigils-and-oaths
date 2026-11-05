extends RefCounted
## Utility for the public two-point objective. Never mutates Battle, inspects
## opposing cards, or treats a root/guarded hit as removal from a point.
const Effects = preload("res://scripts/effect_forecast.gd")

static func prepare(battle: Battle) -> Dictionary:
	if battle.objective.is_empty() or battle.winner != -1: return {}
	var cells: Array[Vector2i] = []
	for raw: Array in battle.objective.cells: cells.append(Vector2i(int(raw[0]), int(raw[1])))
	var owners: Array[int] = ownership(battle.units, cells)
	var goals: Array[Vector2i] = []
	for i: int in range(cells.size()):
		if owners[i] != battle.active_side: goals.append(cells[i])
	var paths: Dictionary = {}
	for unit: Dictionary in battle.units:
		if unit.side != battle.active_side or unit.kind == "commander": continue
		if not battle.movement_cells(unit).is_empty() or (unit.kind == "cavalry" and not battle.skill_targets(unit).is_empty()):
			paths[unit.id] = field(battle, unit, goals)
	var deployment: Dictionary = {}
	for instance: Dictionary in battle.players[battle.active_side].hand:
		var card: Dictionary = battle.definition(instance.card_id)
		if card.type != "unit" or card.cost > battle.players[battle.active_side].mana or deployment.has(card.id): continue
		var unit: Dictionary = card.duplicate()
		unit.merge({"id": -1, "kind": card.id, "side": battle.active_side}, true)
		deployment[card.id] = field(battle, unit, goals)
	return {"cells": cells, "owners": owners, "paths": paths, "deployment": deployment}

static func ownership(units: Array, cells: Array[Vector2i]) -> Array[int]:
	var result: Array[int] = []
	for cell: Vector2i in cells:
		var owner: int = -1
		for unit: Dictionary in units:
			if unit.hp > 0 and unit.pos == cell: owner = unit.side; break
		result.append(owner)
	return result

static func position_value(owners: Array[int], side: int, streak: int) -> float:
	var blue: int = owners.count(0)
	var red: int = owners.count(1)
	if side == 0: return blue * 180.0 + (260.0 + streak * 90.0 if blue == 2 else 0.0)
	return red * 140.0 + (130.0 if red > 0 else 0.0) - blue * 60.0 - (260.0 + streak * 180.0 if blue == 2 else 0.0)

static func value(battle: Battle, action: Dictionary, context: Dictionary) -> float:
	if context.is_empty(): return 0.0
	var side: int = battle.active_side
	var goal: Dictionary = battle.objective
	var cells: Array[Vector2i] = context.cells
	var projected: Array = battle.units.duplicate(true)
	var unit: Dictionary = battle.get_unit(int(action.get("unit_id", -1)))
	var moved: bool = action.type == "move" or (action.type == "unit_skill" and unit.kind == "cavalry")
	var shield_value: float = 0.0
	var added: String = ""
	if moved:
		for copy: Dictionary in projected:
			if copy.id == unit.id: copy.pos = action.target
	elif action.type == "attack" or (action.type == "unit_skill" and unit.kind == "archer"):
		var forecast: Dictionary = battle.attack_forecast(unit, battle.unit_at(action.target), 1 if action.type == "unit_skill" else 0)
		for copy: Dictionary in projected:
			if copy.id == forecast.defender_id: copy.hp -= int(forecast.target_loss)
			if copy.id == unit.id: copy.hp -= int(forecast.attacker_loss)
	elif action.type == "play":
		var card: Dictionary = battle.definition(battle.hand_card(side, action.card_uid).card_id)
		if card.type == "unit":
			projected.append({"id": -1, "kind": card.id, "hp": card.hp, "side": side, "pos": action.target})
			added = card.id
		elif card.effect == "exchange":
			var leader: Dictionary = battle.commander(side)
			var ally: Dictionary = battle.unit_at(action.target)
			for copy: Dictionary in projected:
				if copy.id == leader.id: copy.pos = ally.pos
				elif copy.id == ally.id: copy.pos = leader.pos
	# Spell/skill projections reuse the same shield, area and repulse forecasts
	# that the UI uses. Guard intercepts are handled by attack_forecast above.
	if not moved and action.type != "attack":
		var effect: Dictionary = Effects.predict(battle, action)
		for change: Dictionary in effect.get("changes", []):
			for copy: Dictionary in projected:
				if copy.id != change.unit_id: continue
				copy.hp = change.hp_after
				if change.has("position_after"): copy.pos = change.position_after
				if copy.side == side and cells.has(copy.pos):
					shield_value += maxi(0, int(change.healing)) * 6.0 + maxi(0, int(change.shield_delta)) * 4.0
	for copy: Dictionary in projected:
		if copy.kind == "commander" and copy.hp <= 0: return 6000.0 if copy.side != side else -6000.0
	var after: Array[int] = ownership(projected, cells)
	var score: float = position_value(after, side, int(goal.streak)) - position_value(context.owners, side, int(goal.streak)) + shield_value
	if moved:
		var path: Dictionary = context.paths.get(unit.id, {})
		if path.has(unit.pos) and path.has(action.target):
			var weight: float = 9.0 if side == 0 else (3.0 if context.owners.has(1) else 6.0)
			score += (int(path[unit.pos]) - int(path[action.target])) * weight
		if cells.has(unit.pos) and after.count(side) <= context.owners.count(side): score -= 300.0
	elif not added.is_empty():
		var path: Dictionary = context.deployment.get(added, {})
		if path.has(action.target): score += maxf(0.0, 20.0 - float(path[action.target])) * 1.4
	elif action.type == "unit_skill" and unit.kind == "spear":
		for ally: Dictionary in battle.units:
			if ally.side == side and cells.has(ally.pos) and battle.distance(ally.pos, unit.pos) == 1: score += 35.0
	elif action.type == "end_turn" and side == 1 and after.count(0) == 2 and int(goal.streak) + 1 >= int(goal.required):
		score -= 4000.0
	return score

static func field(battle: Battle, unit: Dictionary, goals: Array[Vector2i]) -> Dictionary:
	# Reverse Dijkstra on passable, unoccupied tiles. An occupied hostile point
	# is approached from a legal firing tile; empty points are occupied directly.
	var costs: Dictionary = {}
	var queue: Array[Vector2i] = []
	for goal: Vector2i in goals:
		var occupant: Dictionary = battle.unit_at(goal)
		if occupant.is_empty() or occupant.id == unit.id:
			costs[goal] = 0; queue.append(goal)
		elif occupant.side != unit.side:
			for y: int in range(battle.height):
				for x: int in range(battle.width):
					var cell := Vector2i(x, y)
					if not _open_cell(battle, unit, cell): continue
					var candidate: Dictionary = unit.duplicate(); candidate.pos = cell
					if battle.distance(cell, goal) <= battle.attack_range(candidate) and not costs.has(cell):
						costs[cell] = 0; queue.append(cell)
	while not queue.is_empty():
		var cheapest: int = 0
		for i: int in range(1, queue.size()):
			if int(costs[queue[i]]) < int(costs[queue[cheapest]]): cheapest = i
		var current: Vector2i = queue.pop_at(cheapest)
		for direction: Vector2i in battle.DIRECTIONS:
			var cell: Vector2i = current + direction
			if not _open_cell(battle, unit, cell): continue
			var cost: int = int(costs[current]) + battle.movement_cost(unit, current)
			if not costs.has(cell) or cost < int(costs[cell]):
				costs[cell] = cost
				if not queue.has(cell): queue.append(cell)
	return costs

static func _open_cell(battle: Battle, unit: Dictionary, cell: Vector2i) -> bool:
	if not battle.passable(cell): return false
	var occupant: Dictionary = battle.unit_at(cell)
	return occupant.is_empty() or occupant.id == unit.id
