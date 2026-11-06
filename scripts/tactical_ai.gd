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

static func _future_attack_damage(battle: Battle, attacker: Dictionary, origin: Vector2i, defender: Dictionary) -> int:
	var candidate: Dictionary = attacker.duplicate()
	candidate.pos = origin
	var parts: Dictionary = battle.damage_breakdown(candidate, defender)
	# The forecast attacker will be active next turn. Add its charge before
	# minimum-damage clamping, using the real path for short detours.
	var charge: int = 0
	if attacker.kind == "cavalry" and origin != attacker.pos:
		if battle.distance(attacker.pos, origin) >= 3 or battle.movement_path(attacker, origin).size() >= 4: charge = 1
	var raw: int = parts.base + parts.advantage + parts.elevation + charge - parts.close_penalty - parts.armor - parts.terrain - parts.aura - parts.stance + parts.pierce
	return maxi(1, raw) + (1 if attacker.kind == "archer" else 0)

static func _loss_value(battle: Battle, unit: Dictionary, incoming: int) -> float:
	var loss: int = mini(int(unit.hp), maxi(0, incoming - int(unit.shield)))
	var value: float = loss * (14.0 if unit.kind == "commander" else 10.0)
	if loss >= int(unit.hp): value += 2000.0 if unit.kind == "commander" else 65.0 + int(battle.definition(unit.kind).get("cost", 0)) * 9.0
	return value

static func defense_value(battle: Battle, caster: Dictionary, context: Dictionary = {}) -> float:
	if context.is_empty(): context = prepare(battle)
	if not context.has("defense_cache"): context.defense_cache = {}
	if context.defense_cache.has(caster.id): return float(context.defense_cache[caster.id])
	var value: float = -2.0 # One mana and the unit's remaining actions.
	if caster.kind == "sword":
		var incoming: int = 0
		for entry: Dictionary in context.enemies:
			var worst: int = 0
			for origin: Vector2i in entry.origins:
				var attacker: Dictionary = entry.unit.duplicate(); attacker.pos = origin
				var distance: int = battle.distance(origin, caster.pos)
				if distance <= battle.attack_range(attacker) and battle.attack_defender(attacker, caster).id == caster.id:
					worst = maxi(worst, _future_attack_damage(battle, entry.unit, origin, caster))
				if attacker.kind == "mage" and distance <= 2: worst = maxi(worst, battle.fire_damage(3))
			incoming += worst
		var shielded: Dictionary = caster.duplicate(); shielded.shield = maxi(3, int(caster.shield))
		# Shield persists: a small preparation value remains even without an
		# immediate threat, but cannot outweigh normal movement or attacks.
		value += (int(shielded.shield) - int(caster.shield)) * 2.0 + _loss_value(battle, caster, incoming) - _loss_value(battle, shielded, incoming)
	elif caster.kind == "spear":
		var protected_damage: Dictionary = {}
		var incoming: int = 0
		for entry: Dictionary in context.enemies:
			var best: float = 0.0
			var selected: Dictionary = {}
			for ally: Dictionary in battle.units:
				if ally.side != caster.side or ally.id == caster.id or battle.distance(caster.pos, ally.pos) != 1: continue
				for origin: Vector2i in entry.origins:
					var attacker: Dictionary = entry.unit.duplicate(); attacker.pos = origin
					if battle.distance(origin, ally.pos) > battle.attack_range(attacker): continue
					var defender: Dictionary = battle.attack_defender(attacker, ally)
					# Existing guards with lower IDs keep the interception.
					if defender.id != ally.id and defender.id < caster.id: continue
					var before: int = _future_attack_damage(battle, entry.unit, origin, defender)
					var after: int = _future_attack_damage(battle, entry.unit, origin, caster)
					if attacker.kind == "mage" and battle.distance(origin, ally.pos) <= 2 and _loss_value(battle, ally, battle.fire_damage(3)) >= _loss_value(battle, defender, before): continue
					var benefit: float = _loss_value(battle, defender, before) - _loss_value(battle, caster, after)
					if benefit > best:
						best = benefit; selected = {"id":defender.id, "before":before, "after":after}
			# One enemy gets one ordinary attack, even if it can reach several
			# protected allies. Shields and casualties are counted once per unit.
			if not selected.is_empty():
				protected_damage[selected.id] = int(protected_damage.get(selected.id, 0)) + int(selected.before)
				incoming += int(selected.after)
		for id: int in protected_damage: value += _loss_value(battle, battle.get_unit(id), protected_damage[id])
		value -= _loss_value(battle, caster, incoming)
	context.defense_cache[caster.id] = value
	return value
