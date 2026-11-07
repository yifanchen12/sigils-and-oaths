class_name Opponent
extends RefCounted
## A small deterministic heuristic, using only its own cards and the public board.
const ObjectiveAI = preload("res://scripts/objective_ai.gd")
const TacticalAI = preload("res://scripts/tactical_ai.gd")

static func choose(battle: Battle) -> Dictionary:
	var best: Dictionary = {"type": "end_turn"}
	var fields: Dictionary = {}
	var objective: Dictionary = ObjectiveAI.prepare(battle)
	var threats: Dictionary = TacticalAI.prepare(battle)
	# Keep end-turn as the tie winner. In a control emergency its value can be
	# negative, but ordinary zero-value actions still must not replace waiting.
	var best_score: float = evaluate(battle, best, fields, objective, threats)
	for unit: Dictionary in battle.units:
		if unit.side == battle.active_side and not battle.movement_cells(unit).is_empty(): fields[unit.id] = _approach_field(battle, unit)
	for action: Dictionary in battle.get_legal_actions(battle.active_side):
		var score: float = evaluate(battle, action, fields, objective, threats) + TacticalAI.value(battle, action, threats)
		if score > best_score:
			best = action
			best_score = score
	return best

static func evaluate(battle: Battle, action: Dictionary, fields: Dictionary = {}, objective: Dictionary = {}, threats: Dictionary = {}) -> float:
	if not battle.objective.is_empty() and objective.is_empty(): objective = ObjectiveAI.prepare(battle)
	return _combat_value(battle, action, fields, threats) + ObjectiveAI.value(battle, action, objective)

static func _combat_value(battle: Battle, action: Dictionary, fields: Dictionary = {}, threats: Dictionary = {}) -> float:
	var side: int = battle.active_side
	var enemy_leader: Dictionary = battle.commander(1 - side)
	match String(action.type):
		"unit_skill":
			var caster: Dictionary = battle.get_unit(action.unit_id)
			var victim: Dictionary = battle.unit_at(action.target)
			match String(caster.kind):
				"sword", "spear":
					return TacticalAI.defense_value(battle, caster, threats)
				"cavalry":
					var before_distance: int = battle.distance(caster.pos, enemy_leader.pos)
					var after_distance: int = battle.distance(action.target, enemy_leader.pos)
					return 12.0 + (before_distance - after_distance) * 5.0 if after_distance < before_distance else -1.0
				"archer":
					var forecast: Dictionary = battle.attack_forecast(caster, victim, 1)
					var defender: Dictionary = battle.get_unit(forecast.defender_id)
					return _attack_value(battle, caster, defender, forecast) - 2.0
				"mage":
					# Compare spells and ordinary attacks on the same scale. Fire
					# bypasses armor/guard and does not provoke retaliation.
					var damage: int = battle.fire_damage(3)
					var loss: int = mini(int(victim.hp), maxi(0, damage - int(victim.shield)))
					return _attack_value(battle, caster, victim, {"damage": damage, "target_loss": loss, "attacker_loss": 0}) - 2.0
				# Meaningful healing should beat a nonlethal one-point poke. A
				# finishing attack retains its separate kill/victory priority.
				"healer": return 52.0 + mini(3, int(victim.max_hp) - int(victim.hp)) * 8.0
		"hero":
			var leader: Dictionary = battle.hero(side)
			var target: Dictionary = battle.unit_at(action.target)
			match String(leader.effect):
				"blessing": return 8.0 + mini(2, int(target.max_hp) - int(target.hp)) * 7.0 + mini(3, 5 - int(target.shield)) * 4.0
				"firestrike":
					var damage: int = battle.fire_damage(leader.amount)
					return 30.0 + mini(damage, int(target.hp) + int(target.shield)) * 5.0 + (2000.0 if target.kind == "commander" and damage >= int(target.hp) + int(target.shield) else 0.0)
				"renewal":
					var score: float = 0.0
					for unit: Dictionary in battle.units:
						if unit.side == side and battle.distance(battle.commander(side).pos, unit.pos) <= battle.hero_cast_range(side): score += mini(2, int(unit.max_hp) - int(unit.hp)) * 6.0
					if battle.players[side].hand.size() < 6 and not battle.players[side].deck.is_empty(): score += 10.0
					if battle.players[side].deck.is_empty():
						var fatigue: int = int(battle.players[side].fatigue) + 1
						var caster: Dictionary = battle.commander(side)
						var healed_hp: int = mini(int(caster.max_hp), int(caster.hp) + 2)
						if fatigue >= healed_hp + int(caster.shield): return -2000.0
						score -= fatigue * 6.0
					return score
		"attack":
			var unit: Dictionary = battle.get_unit(action.unit_id)
			var target: Dictionary = battle.unit_at(action.target)
			var forecast: Dictionary = battle.attack_forecast(unit, target)
			return _attack_value(battle, unit, battle.get_unit(forecast.defender_id), forecast)
		"play":
			var instance: Dictionary = battle.hand_card(side, action.card_uid)
			var card: Dictionary = battle.definition(instance.card_id)
			if card.type == "unit":
				return 50.0 + int(card.cost) * 2.0 - battle.distance(action.target, enemy_leader.pos) * 1.5 + (2.0 if battle.ground(action.target) == "forest" else 0.0)
			if card.type == "trap":
				if threats.is_empty(): threats = TacticalAI.prepare(battle)
				if card.trigger in ["attack", "spell"]:
					var guarded: Dictionary = battle.unit_at(action.target)
					if card.trigger == "spell":
						var pressure: float = 0.0
						for enemy: Dictionary in battle.units:
							if enemy.side != side and enemy.kind == "mage" and battle.distance(enemy.pos, guarded.pos) <= 2: pressure = 15.0
						if battle.hero(1 - side).effect == "firestrike" and battle.distance(battle.commander(1 - side).pos, guarded.pos) <= battle.hero_cast_range(1 - side): pressure = maxf(pressure, 12.0)
						return 11.0 + pressure + (8.0 if int(guarded.hp) <= 3 else 0.0) - mini(3, int(guarded.shield)) * 2.0
					return minf(42.0, TacticalAI.exposure(battle, guarded, threats)) + 6.0 - mini(3, int(guarded.shield)) * 2.0
				var value: float = -1.0
				for entry: Dictionary in threats.enemies:
					if not entry.origins.has(action.target): continue
					var nearest: int = 999
					for ally: Dictionary in battle.units:
						if ally.side == side: nearest = mini(nearest, battle.distance(ally.pos, action.target))
					value = maxf(value, 28.0 - nearest * 4.0 + (6.0 if card.get("root", false) and entry.unit.kind == "cavalry" else 0.0))
				return value
			var target: Dictionary = battle.unit_at(action.target)
			match String(card.effect):
				"shatter_bolt":
					var damage: int = battle.spell_damage(card, side)
					return 35.0 + damage * 5.0 + int(target.shield) * 6.0 + (3000.0 if target.kind == "commander" else 40.0) * float(damage >= int(target.hp))
				"rally_heal":
					var healing: int = 0
					for ally: Dictionary in battle.units:
						if ally.side == side and battle.distance(ally.pos, action.target) <= 1: healing += mini(int(card.amount), int(ally.max_hp) - int(ally.hp))
					return 12.0 + healing * 7.0
				"cleanse_root": return 15.0 + mini(1, int(target.max_hp) - int(target.hp)) * 5.0 + (16.0 if int(target.rooted_turns) > 0 else 0.0)
				"reveal_traps":
					# Search from public army positions only. Never read enemy trap
					# identity, protected unit, position or future cards.
					if battle.Traps.count(battle, 1 - side) == 0: return -1.0
					var proximity: int = 999
					for enemy: Dictionary in battle.units:
						if enemy.side != side: proximity = mini(proximity, battle.distance(enemy.pos, action.target))
					return 20.0 - proximity * 2.0
				"damage", "area":
					var score: float = 35.0
					var amount: int = battle.spell_damage(card, side)
					for victim: Dictionary in battle.units:
						if victim.side == side: continue
						if victim.pos != action.target and (card.effect != "area" or battle.distance(victim.pos, action.target) > 1): continue
						score += mini(amount, int(victim.hp) + int(victim.shield)) * 5.0
						if amount >= int(victim.hp) + int(victim.shield): score += 40.0 if victim.kind != "commander" else 3000.0
					return score
				"heal": return 25.0 + mini(int(card.amount), int(target.max_hp) - int(target.hp)) * 4.0
				"shield": return 12.0 + (8.0 if target.kind == "commander" else 0.0)
				"draw":
					var fatigue: int = _draw_fatigue(battle, side, int(card.amount))
					var caster: Dictionary = battle.commander(side)
					if fatigue >= int(caster.hp) + int(caster.shield): return -2000.0
					return 18.0 - fatigue * 6.0 if battle.players[side].hand.size() < 6 and battle.players[side].deck.size() > 0 else -1.0
				"mana":
					for other: Dictionary in battle.players[side].hand:
						var option: Dictionary = battle.definition(other.card_id)
						if option.cost == battle.players[side].mana + 1 and not battle.card_targets(other.uid, side).is_empty(): return 45.0
					if battle.players[side].skill_cooldown == 0 and battle.hero(side).cost == battle.players[side].mana + 1: return 20.0
					return -1.0

				"march": return 5.0 if battle.distance(target.pos, enemy_leader.pos) > int(target.range) else -1.0
				"terrain":
					if card.terrain == "bridge":
						var own_distance: int = 999
						var enemy_distance: int = 999
						for unit: Dictionary in battle.units:
							if unit.side == side: own_distance = mini(own_distance, battle.distance(unit.pos, action.target))
							else: enemy_distance = mini(enemy_distance, battle.distance(unit.pos, action.target))
						if own_distance > enemy_distance: return -1.0
						return 18.0 + (3 - own_distance) * 3.0 - mini(enemy_distance, 5)
					if card.terrain == "forest":
						if target.is_empty(): return -1.0
						if target.side == side: return 10.0 + (1 - battle.terrain_defense(target)) * 8.0 - (15.0 if target.kind == "cavalry" else 0.0)
						return 12.0 if target.kind == "cavalry" else -1.0
					if card.terrain == "fort":
						return 12.0 + (10.0 if target.kind == "commander" else 0.0)
					if not target.is_empty():
						if target.side != side: return battle.terrain_defense(target) * 8.0
						if target.kind == "cavalry" and not target.moved: return 15.0
					return -1.0
				"weather": return _weather_score(battle, side, card.weather)
				"clear_weather":
					# Score the current weather without the duplicate-weather rejection.
					var opposite_value: float = _weather_score_for(battle, side, battle.weather)
					return 18.0 - opposite_value if opposite_value < 0.0 else -1.0
				"repulse":
					var destination: Vector2i = battle.repulse_destination(target, side)
					var amount: int = int(card.amount) + (1 if destination == target.pos else 0)
					return 25.0 + mini(amount, int(target.hp) + int(target.shield)) * 5.0 + (35.0 if amount >= int(target.hp) + int(target.shield) else 0.0) + (12.0 if battle.distance(target.pos, battle.commander(side).pos) <= 2 else 0.0)
				"root":
					return 10.0 + int(target.move) * 3.0 + (10.0 if battle.distance(target.pos, battle.commander(side).pos) <= 3 else 0.0)
				"dispel": return 12.0 + int(target.shield) * 6.0 + (8.0 if target.kind == "commander" else 0.0)
				"exchange":
					var leader: Dictionary = battle.commander(side)
					var old_risk: float = _danger(battle, side, leader.pos)
					var new_risk: float = _danger(battle, side, target.pos)
					return (old_risk - new_risk) * 5.0 if new_risk < old_risk else -1.0
				"onslaught":
					var ready: Dictionary = target.duplicate()
					ready.attacked = false
					var best: float = -1.0
					for cell: Vector2i in battle.attack_targets(ready):
						var victim: Dictionary = battle.unit_at(cell)
						var amount: int = battle.damage_preview(ready, victim)
						var value: float = 25.0 + amount * 4.0 + (100.0 if amount >= int(victim.hp) + int(victim.shield) else 0.0)
						if victim.kind == "commander": value += 40.0
						best = maxf(best, value)
					return best
		"move":
			var unit: Dictionary = battle.get_unit(action.unit_id)
			var old_distance: int = 999
			var new_distance: int = 999
			for enemy: Dictionary in battle.units:
				if enemy.side == side: continue
				old_distance = mini(old_distance, battle.distance(unit.pos, enemy.pos))
				new_distance = mini(new_distance, battle.distance(action.target, enemy.pos))
			var field: Dictionary = fields.get(unit.id, {})
			var old_path: int = int(field.get(unit.pos, old_distance))
			var new_path: int = int(field.get(action.target, new_distance))
			var score: float = (old_path - new_path) * 7.0
			var candidate: Dictionary = unit.duplicate()
			candidate.pos = action.target
			candidate.moved = true
			candidate.last_move_distance = battle.distance(unit.pos, action.target)
			if not unit.attacked:
				var shot: float = _firing_position(battle, candidate)
				if shot > -INF: score += 40.0 + shot
			score += battle.terrain_defense(candidate) * 1.5
			if battle.ground(action.target) == "ruins" and unit.hp < unit.max_hp: score += 3.0
			if battle.hero(side).id == "grove" and battle.ground(action.target) == "forest" and unit.hp < unit.max_hp: score += 4.0
			if unit.kind == "healer": score += (_support_value(battle, candidate) - _support_value(battle, unit)) * 2.0
			score += (battle.distance(unit.pos, enemy_leader.pos) - battle.distance(action.target, enemy_leader.pos)) * 0.6
			return score
	return 0.0

static func _attack_value(_battle: Battle, unit: Dictionary, target: Dictionary, forecast: Dictionary) -> float:
	var score: float = 60.0 + mini(int(forecast.damage), int(target.hp) + int(target.shield)) * 4.0
	if forecast.target_loss >= int(target.hp): score += 50.0
	if target.kind == "commander": score += 60.0
	if forecast.target_loss >= int(target.hp) and target.kind == "commander": score += 2000.0
	score -= int(forecast.attacker_loss) * 6.0
	if forecast.attacker_loss >= int(unit.hp): score -= 35.0
	return score

static func _draw_fatigue(battle: Battle, side: int, amount: int) -> int:
	var missing: int = maxi(0, amount - battle.players[side].deck.size())
	var result: int = 0
	for index: int in range(missing): result += int(battle.players[side].fatigue) + index + 1
	return result

static func _firing_position(battle: Battle, candidate: Dictionary) -> float:
	var best: float = -INF
	for target: Dictionary in battle.units:
		if target.side == candidate.side or battle.distance(candidate.pos, target.pos) > battle.attack_range(candidate): continue
		var damage: int = battle.damage_preview(candidate, target)
		var kills: bool = damage >= int(target.hp) + int(target.shield)
		var value: float = mini(damage, int(target.hp) + int(target.shield)) * 4.0 + (40.0 if kills else 0.0)
		if target.kind == "commander": value += 2000.0 if kills else 12.0
		if not kills and battle.distance(candidate.pos, target.pos) <= battle.attack_range(target):
			value -= maxi(0, battle.damage_preview(target, candidate) - int(candidate.shield)) * 6.0
		best = maxf(best, value)
	return best

static func _support_value(battle: Battle, healer: Dictionary) -> float:
	var result: float = 0.0
	for ally: Dictionary in battle.units:
		if ally.side == healer.side and ally.id != healer.id and battle.distance(healer.pos, ally.pos) <= 1:
			result += mini(2, int(ally.max_hp) - int(ally.hp)) * 4.0
	return minf(20.0, result)

static func _weather_score(battle: Battle, side: int, weather: String) -> float:
	if battle.weather == weather: return -1.0
	return _weather_score_for(battle, side, weather)

static func _weather_score_for(battle: Battle, side: int, weather: String) -> float:
	var score: float = -2.0
	for unit: Dictionary in battle.units:
		var sign_value: float = 1.0 if unit.side != side else -1.0
		match weather:
			"rain":
				if unit.kind == "cavalry": score += sign_value * 10.0
			"fog":
				if battle.attack_range(unit) > 2: score += sign_value * 12.0
			"snow":
				if unit.kind == "cavalry": score += sign_value * 6.0
				if unit.side == side and battle.distance(unit.pos, battle.commander(side).pos) <= 2: score += 1.0
			"sun":
				if unit.kind == "healer": score -= sign_value * 5.0
	if weather == "sun":
		for instance: Dictionary in battle.players[side].hand:
			if battle.definition(instance.card_id).get("effect", "") in ["damage", "area"]: score += 12.0
		if battle.hero(side).id == "pyromancer": score += 6.0
		if battle.hero(1 - side).id == "pyromancer": score -= 6.0
	return score

static func _danger(battle: Battle, side: int, cell: Vector2i) -> float:
	var result: float = 0.0
	for enemy: Dictionary in battle.units:
		if enemy.side == side: continue
		var reach: int = battle.attack_range(enemy) + battle.movement_allowance(enemy)
		if battle.distance(enemy.pos, cell) <= reach: result += float(enemy.atk) / maxf(1.0, battle.distance(enemy.pos, cell) * 0.6)
	return result

static func _approach_field(battle: Battle, unit: Dictionary) -> Dictionary:
	# Reverse Dijkstra lets every candidate move use actual bridge/terrain paths.
	var costs: Dictionary = {}
	var queue: Array[Vector2i] = []
	for y: int in range(battle.height):
		for x: int in range(battle.width):
			var cell := Vector2i(x, y)
			if not battle.passable(cell): continue
			var occupant: Dictionary = battle.unit_at(cell)
			if not occupant.is_empty() and occupant.id != unit.id: continue
			var hypothetical: Dictionary = unit.duplicate()
			hypothetical.pos = cell
			for enemy: Dictionary in battle.units:
				if enemy.side != unit.side and battle.distance(cell, enemy.pos) <= battle.attack_range(hypothetical):
					costs[cell] = 0
					queue.append(cell)
					break
	while not queue.is_empty():
		var cheapest: int = 0
		for index: int in range(1, queue.size()):
			if int(costs[queue[index]]) < int(costs[queue[cheapest]]): cheapest = index
		var current: Vector2i = queue.pop_at(cheapest)
		for direction: Vector2i in battle.DIRECTIONS:
			var cell: Vector2i = current + direction
			if not battle.passable(cell): continue
			var occupant: Dictionary = battle.unit_at(cell)
			if not occupant.is_empty() and occupant.id != unit.id: continue
			var cost: int = int(costs[current]) + battle.movement_cost(unit, current)
			if not costs.has(cell) or cost < int(costs[cell]):
				costs[cell] = cost
				if not queue.has(cell): queue.append(cell)
	return costs
