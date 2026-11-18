extends RefCounted
## Utility for public objectives. Never mutates Battle, inspects
## opposing cards, or treats a root/guarded hit as removal from a point.
const Effects = preload("res://scripts/effect_forecast.gd")
const Tactical = preload("res://scripts/tactical_ai.gd")

static func prepare(battle: Battle, threats: Dictionary = {}) -> Dictionary:
	if battle.objective.is_empty() or battle.winner != -1: return {}
	if battle.ControlObjective.is_escort(battle.objective):
		var escort: Dictionary = battle.escort_unit()
		if escort.is_empty(): return {}
		var exit_cell: Vector2i = battle.ControlObjective.position(battle.objective.cells[0])
		var goals: Array[Vector2i] = [exit_cell]
		if battle.active_side != 0: return {"escort": escort, "exit": exit_cell}
		var route: Dictionary = field(battle, escort, goals, true)
		var advancing: bool = false
		for cell: Vector2i in battle.movement_cells(escort):
			if route.get(cell, 9999) < route.get(escort.pos, 9999): advancing = true; break
		if threats.is_empty(): threats = Tactical.prepare(battle)
		var ready: Dictionary = escort.duplicate()
		ready.moved = false
		ready.attacked = false
		ready.rooted_turns = 0
		return {"escort": escort, "exit": exit_cell, "route": route, "advancing": advancing, "threats": threats,
			"ready": ready, "advance_cost": _advance_cost(battle, ready, route, {})}
	var cells: Array[Vector2i] = []
	var relay: bool = battle.ControlObjective.is_relay(battle.objective)
	var first: int = int(battle.objective.streak) if relay else 0
	var limit: int = first + 1 if relay else battle.objective.cells.size()
	for index: int in range(first, limit):
		var raw: Array = battle.objective.cells[index]
		cells.append(Vector2i(int(raw[0]), int(raw[1])))
	var owners: Array[int] = ownership(battle.units, cells)
	var goals: Array[Vector2i] = []
	for i: int in range(cells.size()):
		if owners[i] != battle.active_side: goals.append(cells[i])
	if relay and battle.active_side == 0 and goals.is_empty() and limit < battle.objective.cells.size():
		var next: Array = battle.objective.cells[limit]
		goals.append(Vector2i(int(next[0]), int(next[1])))
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
		unit.merge({"id": -1, "side": battle.active_side}, true)
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
	var reaches: bool = blue == owners.size()
	if side == 0: return blue * 180.0 + (260.0 + streak * 90.0 if reaches else 0.0)
	return red * 140.0 + (130.0 if red > 0 else 0.0) - blue * 60.0 - (260.0 + streak * 180.0 if reaches else 0.0)

static func value(battle: Battle, action: Dictionary, context: Dictionary) -> float:
	if context.is_empty(): return 0.0
	if context.has("escort"): return _escort_value(battle, action, context)
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
		var card: Dictionary = battle.card_for_play(battle.definition(battle.hand_card(side, action.card_uid).card_id), side)
		if card.type == "unit":
			projected.append({"id": -1, "kind": card.kind, "hp": card.hp, "side": side, "pos": action.target})
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
	elif action.type == "end_turn" and side == 1 and after.count(0) == cells.size() and int(goal.streak) + 1 >= int(goal.required):
		score -= 4000.0
	return score

static func _escort_value(battle: Battle, action: Dictionary, context: Dictionary) -> float:
	var escort: Dictionary = context.escort
	var exit_cell: Vector2i = context.exit
	var side: int = battle.active_side
	var unit: Dictionary = battle.get_unit(int(action.get("unit_id", -1)))
	if action.type == "move" or (action.type == "unit_skill" and unit.kind == "cavalry"):
		var destination: Vector2i = action.target
		if unit.id == escort.id:
			if destination == exit_cell: return 5000.0
			var route: Dictionary = context.route
			if route.has(escort.pos) and route.has(destination):
				var projected: Dictionary = escort.duplicate()
				projected.pos = destination
				var relief: float = Tactical.exposure(battle, escort, context.threats) - Tactical.exposure(battle, projected, context.threats)
				return (int(route[escort.pos]) - int(route[destination])) * 28.0 + relief
			return 0.0
		var proximity: int = battle.distance(unit.pos, escort.pos) - battle.distance(destination, escort.pos)
		if side == 1: return proximity * 7.0 + (38.0 if destination == exit_cell else 0.0)
		if destination == exit_cell: return -70.0
		if unit.pos == exit_cell: return 70.0
		return proximity * 4.0 + _escort_clearance(battle, context, destination, unit.pos)
	if action.type == "attack" or (action.type == "unit_skill" and unit.kind == "archer"):
		if side == 0: return 0.0
		var hit: Dictionary = battle.attack_forecast(unit, battle.unit_at(action.target), 1 if action.type == "unit_skill" else 0)
		if hit.defender_id == escort.id: return _escort_hit(escort, int(hit.target_loss))
		return 0.0
	if action.type == "play":
		var card: Dictionary = battle.card_for_play(battle.definition(battle.hand_card(side, action.card_uid).card_id), side)
		if card.type == "unit" or card.get("effect", "") == "redeploy":
			if action.target == exit_cell: return -70.0 if side == 0 else 38.0
			var nearby: float = maxf(0.0, 5.0 - battle.distance(action.target, escort.pos))
			if card.get("entry", {}).get("guard", false) and side == 0 and battle.distance(action.target, escort.pos) == 1:
				nearby += 3.0
			var clearance: float = _escort_clearance(battle, context, action.target) if side == 0 else 0.0
			if card.get("entry", {}).get("target_side", "") != "enemy": return nearby * 3.0 + clearance
	if action.type == "unit_skill" and unit.kind == "spear" and side == 0 and battle.distance(unit.pos, escort.pos) == 1:
		return 21.0
	for change: Dictionary in Effects.predict(battle, action).get("changes", []):
		if change.unit_id != escort.id: continue
		if side == 1: return _escort_hit(escort, int(change.hp_loss))
		if change.get("position_after", Vector2i(-1, -1)) == exit_cell: return 5000.0
		var projected: Dictionary = escort.duplicate()
		projected.hp = change.hp_after
		projected.shield = change.shield_after
		var relief: float = Tactical.exposure(battle, escort, context.threats) - Tactical.exposure(battle, projected, context.threats)
		var waits: float = 88.0 if action.type == "unit_skill" and unit.id == escort.id and context.advancing else 0.0
		return int(change.healing) * 10.0 + maxi(0, int(change.shield_delta)) * 7.0 + relief * 2.4 + (22.0 if change.get("cleanse", false) else 0.0) - waits
	return 0.0

static func _escort_hit(escort: Dictionary, loss: int) -> float:
	return 4500.0 if loss >= int(escort.hp) else loss * 11.0

static func _advance_cost(battle: Battle, ready: Dictionary, route: Dictionary, overrides: Dictionary) -> int:
	var cost: int = int(route.get(ready.pos, 9999))
	for cell: Vector2i in battle.movement_cells(ready, overrides):
		cost = mini(cost, int(route.get(cell, 9999)))
	return cost

static func _escort_clearance(battle: Battle, context: Dictionary, destination: Vector2i, origin: Vector2i = Vector2i(-1, -1)) -> float:
	var ready: Dictionary = context.ready
	var reach: int = battle.movement_allowance(ready)
	if mini(battle.distance(destination, ready.pos), battle.distance(origin, ready.pos)) > reach: return 0.0
	var overrides: Dictionary = {destination: true}
	if battle.inside(origin): overrides[origin] = false
	var cost: int = _advance_cost(battle, ready, context.route, overrides)
	return clampi(int(context.advance_cost) - cost, -5, 5) * 30.0

static func field(battle: Battle, unit: Dictionary, goals: Array[Vector2i], ignore_friendlies: bool = false) -> Dictionary:
	# Reverse Dijkstra on passable, unoccupied tiles. An occupied hostile point
	# is approached from a legal firing tile; empty points are occupied directly.
	var costs: Dictionary = {}
	var queue: Array[Vector2i] = []
	for goal: Vector2i in goals:
		var occupant: Dictionary = battle.unit_at(goal)
		if _open_cell(battle, unit, goal, ignore_friendlies):
			costs[goal] = 0; queue.append(goal)
		elif occupant.side != unit.side:
			for y: int in range(battle.height):
				for x: int in range(battle.width):
					var cell := Vector2i(x, y)
					if not _open_cell(battle, unit, cell, ignore_friendlies): continue
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
			if not _open_cell(battle, unit, cell, ignore_friendlies): continue
			var cost: int = int(costs[current]) + battle.movement_cost(unit, current)
			if not costs.has(cell) or cost < int(costs[cell]):
				costs[cell] = cost
				if not queue.has(cell): queue.append(cell)
	return costs

static func _open_cell(battle: Battle, unit: Dictionary, cell: Vector2i, ignore_friendlies: bool) -> bool:
	if not battle.passable(cell): return false
	var occupant: Dictionary = battle.unit_at(cell)
	return occupant.is_empty() or occupant.id == unit.id or (ignore_friendlies and occupant.side == unit.side and occupant.kind != "commander")
