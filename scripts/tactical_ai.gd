extends RefCounted
## Public-board risk heuristic, not a full simulation of the enemy's next turn.
## Future cards and random draws are deliberately unknown to this evaluator.

static func prepare(battle: Battle, movement_weight: float = 0.45) -> Dictionary:
	var threats: Array[Dictionary] = []
	for unit: Dictionary in battle.units:
		if unit.side == battle.active_side: continue
		var ready: Dictionary = unit.duplicate(true)
		ready.moved = false; ready.attacked = false; ready.summoning = false
		ready.rooted_turns = maxi(0, int(ready.get("rooted_turns", 0)) - 1)
		ready.last_move_distance = 0
		var origins: Array[Vector2i] = [ready.pos]
		origins.append_array(battle.movement_cells(ready))
		threats.append({"unit": ready, "origins": origins})
	return {"enemies": threats, "layouts": {}, "cache": {}, "movement_weight": movement_weight}

static func exposure(battle: Battle, unit: Dictionary, context: Dictionary) -> float:
	var source: Dictionary = battle.get_unit(int(unit.get("id", -1)))
	var occupancy: Dictionary = {}
	var layout_key: String = "current"
	if source.is_empty() or source.pos != unit.pos:
		if not source.is_empty(): occupancy[source.pos] = false
		occupancy[unit.pos] = true
		layout_key = "%s>%s" % [str(source.get("pos", "deployment")), str(unit.pos)]
	var key: String = "%s:%s:%d:%s:%d:%d:%d:%s" % [layout_key, unit.kind, unit.side, str(unit.pos), unit.defense, unit.hp, unit.shield, int(unit.get("last_move_distance", 0)) > 0]
	if context.cache.has(key): return float(context.cache[key])
	var threats: Array = context.enemies
	if not occupancy.is_empty():
		if not context.layouts.has(layout_key):
			var projected: Array[Dictionary] = []
			for entry: Dictionary in context.enemies:
				var origins: Array[Vector2i] = [entry.unit.pos]
				origins.append_array(battle.movement_cells(entry.unit, occupancy))
				projected.append({"unit": entry.unit, "origins": origins})
			context.layouts[layout_key] = projected
		threats = context.layouts[layout_key]
	var incoming: float = 0.0
	for entry: Dictionary in threats:
		var enemy: Dictionary = entry.unit
		var worst: float = 0.0
		for origin: Vector2i in entry.origins:
			if origin == unit.pos: continue
			var attacker: Dictionary = enemy.duplicate()
			attacker.pos = origin
			var distance: int = battle.distance(origin, unit.pos)
			# Moving threats require the enemy to commit its position. This is a
			# utility weight, not a probability or an exact damage prediction.
			var mobility_weight: float = 1.0 if origin == enemy.pos else float(context.movement_weight)
			if distance <= battle.attack_range(attacker):
				var amount: int = battle.damage_preview(attacker, unit)
				# Opposing cavalry will be active when this future attack occurs.
				if enemy.kind == "cavalry" and battle.distance(enemy.pos, origin) >= 3: amount += 1
				if enemy.kind == "archer": amount += 1
				worst = maxf(worst, amount * mobility_weight)
			if enemy.kind == "mage" and distance <= 2: worst = maxf(worst, battle.fire_damage(3) * mobility_weight)
		incoming += worst
	var loss: float = maxf(0.0, incoming - int(unit.shield))
	var score: float = minf(loss, int(unit.hp)) * 10.0 + (65.0 + int(battle.definition(unit.kind).get("cost", 0)) * 9.0 if loss >= int(unit.hp) else 0.0)
	context.cache[key] = score
	return score

static func value(battle: Battle, action: Dictionary, context: Dictionary) -> float:
	if action.type == "play":
		var card: Dictionary = battle.definition(battle.hand_card(battle.active_side, action.card_uid).card_id)
		if card.type != "unit": return 0.0
		var unit: Dictionary = card.duplicate(true)
		unit.merge({"id": -1, "kind": card.id, "side": battle.active_side, "pos": action.target, "shield": 0, "last_move_distance": 0})
		return -exposure(battle, unit, context)
	if action.type == "move":
		var unit: Dictionary = battle.get_unit(action.unit_id)
		var candidate: Dictionary = unit.duplicate()
		candidate.pos = action.target; candidate.last_move_distance = battle.distance(unit.pos, action.target)
		return (exposure(battle, unit, context) - exposure(battle, candidate, context)) * 0.6
	return 0.0
