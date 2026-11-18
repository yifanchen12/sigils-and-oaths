class_name Opponent
extends RefCounted
## A small deterministic heuristic, using only its own cards and the public board.
const ObjectiveAI = preload("res://scripts/objective_ai.gd")
const TacticalAI = preload("res://scripts/tactical_ai.gd")

static func choose(battle: Battle) -> Dictionary:
	var best: Dictionary = {"type": "end_turn"}
	var fields: Dictionary = {}
	var threats: Dictionary = TacticalAI.prepare(battle)
	var objective: Dictionary = ObjectiveAI.prepare(battle, threats)
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
	if not battle.objective.is_empty() and objective.is_empty(): objective = ObjectiveAI.prepare(battle, threats)
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
				var score: float = 50.0 + int(card.cost) * 2.0 - battle.distance(action.target, enemy_leader.pos) * 1.5 + (2.0 if battle.ground(action.target) == "forest" else 0.0)
				if card.has("entry") and battle.entry_active(card.entry, action.target): score += _entry_score(battle, card.entry, action.target)
				if card.has("fall"):
					score += _reserve_value(battle, side, int(card.fall.get("draw", 0))) * 0.5
					score += _supply_value(battle, side, card.fall) * 0.5
					score += _reclaim_value(battle, side, card.fall, 0) * 0.5
					score += _formation_score(battle, card.fall, action.target) * 0.2
				return score
			if card.type == "trap":
				var draw_bonus: float = _trap_supply_value(battle, card, side)
				if threats.is_empty(): threats = TacticalAI.prepare(battle)
				if card.trigger != "step":
					var guarded: Dictionary = battle.unit_at(action.target)
					var healing: float = mini(int(card.get("healing", 0)), int(guarded.max_hp) - int(guarded.hp)) * 5.0
					var pressure: float = 0.0
					if card.trigger in ["spell", "either"]:
						for enemy: Dictionary in battle.units:
							if enemy.side != side and enemy.kind == "mage" and battle.distance(enemy.pos, guarded.pos) <= 2: pressure = 15.0
						if battle.hero(1 - side).effect == "firestrike" and battle.distance(battle.commander(1 - side).pos, guarded.pos) <= battle.hero_cast_range(1 - side): pressure = maxf(pressure, 12.0)
					if card.trigger == "spell":
						return 11.0 + pressure + draw_bonus + healing + (8.0 if int(guarded.hp) <= 3 else 0.0) - mini(3, int(guarded.shield)) * 2.0
					var exposure: float = minf(42.0, TacticalAI.exposure(battle, guarded, threats))
					var retort: float = int(card.get("retort", 0)) * (3.0 if exposure > 0.0 else 0.0)
					return maxf(exposure, pressure) + retort + 6.0 + draw_bonus + healing - mini(3, int(guarded.shield)) * 2.0
				var value: float = -1.0
				for entry: Dictionary in threats.enemies:
					if not entry.origins.has(action.target): continue
					var nearest: int = 999
					for ally: Dictionary in battle.units:
						if ally.side == side: nearest = mini(nearest, battle.distance(ally.pos, action.target))
					var shatter: float = int(entry.unit.shield) * 3.0 if card.get("clear_shield", false) else 0.0
					var cutoff: float = 13.0 if card.get("disarm", false) and nearest <= battle.attack_range(entry.unit) + 1 else 0.0
					value = maxf(value, 28.0 - nearest * 4.0 + shatter + cutoff + (6.0 if card.get("root", false) and entry.unit.kind == "cavalry" else 0.0))
				if value < 0.0: return value
				if card.has("rally"): value += _formation_score(battle, card.rally, action.target) * 0.5
				return value + draw_bonus
			var target: Dictionary = battle.unit_at(action.target)
			match String(card.effect):
				"supply": return _supply_value(battle, side, card) - int(card.cost) * 1.5
				"reclaim": return _reclaim_value(battle, side, card) - int(card.cost) * 1.5
				"scheduled": return _scheduled_value(battle, card, action.target)
				"commission":
					var loss: int = mini(int(target.hp), maxi(0, int(card.amount) - int(target.shield)))
					var followup: float = 43.0 + _supply_value(battle, side, card) if loss >= int(target.hp) else 0.0
					return loss * 8.0 + mini(int(card.amount), int(target.shield)) * 4.0 + followup - 9.0
				"formation": return _formation_score(battle, card, action.target) + _reserve_value(battle, side, int(card.get("draw", 0))) + _reclaim_value(battle, side, card)
				"recall": return _recall_value(battle, target, card, threats)
				"recall_fallen":
					var room: int = Battle.HAND_LIMIT - battle.players[side].hand.size() + 1
					var count: int = mini(room, battle.fallen_cards(card, side).size())
					return count * 18.0 - int(card.cost) * 1.5 - (10.0 if room == 1 else 0.0)
				"redeploy":
					var troop: Dictionary = battle.definition(battle.fallen_cards(card, side)[0].card_id)
					return 43.0 + int(troop.cost) * 4.5 - int(card.cost) * 2.0 + int(card.get("self_shield", 0)) * 3.0 - battle.distance(action.target, enemy_leader.pos) * 1.5
				"pullback":
					var landing: Vector2i = battle.pullback_destination(target, side, int(card.steps))
					var healing: int = mini(int(card.healing), int(target.max_hp) - int(target.hp))
					var safety: float = _danger(battle, side, target.pos) - _danger(battle, side, landing)
					var release: float = 12.0 if card.get("cleanse", false) and target.rooted_turns > 0 else 0.0
					return healing * 7.0 + safety * 7.0 + release - (10.0 if not target.attacked and not target.summoning and landing != target.pos else 0.0)
				"verdict":
					var damage: int = battle.verdict_damage(card, target)
					var shield: int = int(target.shield)
					var removed: int = shield if card.get("shatter", false) else 0
					var loss: int = mini(int(target.hp), maxi(0, damage - shield + removed))
					var bonus: float = 0.0
					if loss >= int(target.hp):
						bonus = 43.0 + _reserve_value(battle, side, int(card.get("kill_draw", 0)))
					return loss * 9.0 + (removed + mini(damage, shield - removed)) * 4.0 + bonus - 6.0
				"roadwork":
					var benefit: float = -3.0
					var ground: String = card.get("terrain", "road")
					for cell: Vector2i in battle.roadwork_cells(action.target, card):
						var occupant: Dictionary = battle.unit_at(cell)
						if occupant.is_empty(): continue
						if ground == "fort":
							var defense_gain: int = 2 - battle.terrain_defense(occupant)
							if occupant.side == side: benefit += defense_gain * 8.0 + mini(5 - int(occupant.shield), int(card.reinforce)) * 5.0
							else: benefit -= defense_gain * 8.0
						elif occupant.side != side: benefit += battle.terrain_defense(occupant) * 8.0
						elif occupant.kind == "cavalry" and not occupant.moved: benefit += 12.0 - battle.terrain_defense(occupant) * 5.0
					return benefit
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
				"weather":
					var value: float = _weather_score(battle, side, card.weather) + _reserve_value(battle, side, int(card.get("draw", 0)))
					if card.has("rally"): value += _formation_score(battle, card.rally, battle.commander(side).pos)
					return value + _supply_value(battle, side, card) + _reclaim_value(battle, side, card)
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
			if not unit.attacked and not unit.summoning and not battle.is_escort_unit(unit.id):
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

static func _reserve_value(battle: Battle, side: int, draws: int, room_for_play: int = 1) -> float:
	var player: Dictionary = battle.players[side]
	var capacity: int = Battle.HAND_LIMIT - player.hand.size() + room_for_play
	return mini(draws, mini(player.deck.size(), capacity)) * 9.0

static func _supply_value(battle: Battle, side: int, source: Dictionary) -> float:
	if not source.has("supply"): return 0.0
	var room: int = Battle.HAND_LIMIT + 1 - battle.players[side].hand.size()
	return mini(room, battle.supply_cards(side, source.supply).size()) * 13.0

static func _reclaim_value(battle: Battle, side: int, source: Dictionary, room_for_play: int = 1) -> float:
	if not source.has("reclaim"): return 0.0
	var room: int = Battle.HAND_LIMIT - battle.players[side].hand.size() + room_for_play
	var matches: Array[Dictionary] = battle.reclaim_cards(side, source.reclaim)
	var value: float = 0.0
	for index: int in range(mini(room, matches.size())):
		value += 12.0 + int(battle.definition(matches[index].card_id).cost) * 1.5
	return value

static func _scheduled_value(battle: Battle, card: Dictionary, center: Vector2i) -> float:
	var value: float = -7.0
	for change: Dictionary in battle.Formation.changes(battle, card, center, battle.active_side):
		var unit: Dictionary = battle.get_unit(change.unit_id)
		if change.friendly:
			value += int(change.healing) * 4.0 + int(change.shield_delta) * 3.0 + (5.0 if change.cleanse else 0.0)
			continue
		var impact: float = int(change.hp_loss) * 8.0 - int(change.shield_delta) * 3.0 + (9.0 if change.root else 0.0)
		if change.hp_after == 0: impact += 100.0 if unit.kind == "commander" else 31.0
		value += impact * (0.85 if unit.move == 0 or unit.rooted_turns > 1 else 0.54)
	return value

static func _recall_value(battle: Battle, target: Dictionary, card: Dictionary, threats: Dictionary) -> float:
	var side: int = battle.active_side
	var definition: Dictionary = battle.definition(target.card.card_id)
	var player: Dictionary = battle.players[side]
	var replay_now: bool = int(definition.cost) + int(card.cost) <= int(player.mana)
	var replay_later: bool = int(definition.cost) <= int(player.max_mana) + 1
	if not replay_now and not replay_later: return -1.0
	var lost_hp: int = int(target.max_hp) - int(target.hp)
	var score: float = lost_hp * 4.5 + (9.0 if int(target.rooted_turns) > 0 else 0.0)
	if not target.attacked and not target.summoning: score -= 13.0
	score -= int(target.shield) * 3.0 + 12.0
	if replay_now and definition.has("entry") and battle.entry_active(definition.entry, target.pos): score += minf(22.0, _entry_score(battle, definition.entry, target.pos))
	if lost_hp > 0:
		var context: Dictionary = threats if not threats.is_empty() else TacticalAI.prepare(battle)
		score += minf(22.0, TacticalAI.exposure(battle, target, context) * 0.17)
	return score + _reserve_value(battle, side, int(card.get("draw", 0)), 0)

static func _formation_score(battle: Battle, card: Dictionary, center: Vector2i) -> float:
	var score: float = 0.0
	var side: int = battle.active_side
	for change: Dictionary in battle.Formation.changes(battle, card, center, side):
		var unit: Dictionary = battle.get_unit(change.unit_id)
		if unit.side != side:
			score += int(change.hp_loss) * 9.0 - int(change.shield_delta) * 4.0
			if change.hp_after == 0: score += 3000.0 if unit.kind == "commander" else 40.0
			if change.root: score += 14.0 if unit.kind == "cavalry" else 8.0
		else:
			score += int(change.healing) * 7.0 + int(change.shield_delta) * 5.0
			if change.cleanse: score += 12.0
			if change.refresh_move: score += 12.0
			if change.refresh_attack:
				for enemy: Dictionary in battle.units:
					if enemy.side != side and battle.distance(unit.pos, enemy.pos) <= battle.attack_range(unit):
						score += 30.0; break
	return score

static func _entry_score(battle: Battle, entry: Dictionary, center: Vector2i) -> float:
	var side: int = battle.active_side
	var fatigue: int = _draw_fatigue(battle, side, int(entry.get("draw", 0)))
	var leader: Dictionary = battle.commander(side)
	if fatigue >= int(leader.hp) + int(leader.shield): return -3000.0
	var cards: int = mini(int(entry.get("draw", 0)), battle.players[side].deck.size())
	var advance: float = 5.0 if entry.get("vanguard", false) else 0.0
	return _formation_score(battle, entry, center) + cards * 6.0 + int(entry.get("self_shield", 0)) * 3.0 + advance - fatigue * 7.0 + _supply_value(battle, side, entry) + _reclaim_value(battle, side, entry)

static func _trap_supply_value(battle: Battle, card: Dictionary, side: int) -> float:
	var draws: int = int(card.get("draw", 0))
	if draws == 0: return (_supply_value(battle, side, card) + _reclaim_value(battle, side, card, 0)) * 0.65
	var available: int = battle.players[side].deck.size()
	return mini(draws, available) * 5.0 - (12.0 if available < draws else 0.0)

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
			"tailwind":
				if unit.kind == "cavalry": score -= sign_value * 9.0
	if weather == "sun":
		for instance: Dictionary in battle.players[side].hand:
			var card: Dictionary = battle.definition(instance.card_id)
			if card.get("effect", "") in ["damage", "area"] or (card.get("effect", "") == "formation" and card.get("fire", false)): score += 12.0
		if battle.hero(side).id == "pyromancer": score += 6.0
		if battle.hero(1 - side).id == "pyromancer": score -= 6.0
	if weather == "lanterns":
		for instance: Dictionary in battle.players[side].hand:
			if battle.definition(instance.card_id).type == "unit": score += 5.0
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
