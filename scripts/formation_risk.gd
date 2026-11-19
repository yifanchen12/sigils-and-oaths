extends RefCounted
## Estimate the cost of grouping under one reachable, affordable area spell.
## A selectable preset is public. A custom deck only contributes revealed cards.

static func prepare(battle: Battle, enemies: Array[Dictionary]) -> Array[Dictionary]:
	var source: int = 1 - battle.active_side
	var player: Dictionary = battle.players[source]
	var next_mana: int = mini(10, int(player.max_mana) + 1)
	var spent: Dictionary = {}
	for instance: Dictionary in player.discard:
		spent[instance.card_id] = int(spent.get(instance.card_id, 0)) + 1
	var public_preset: bool = player.deck_id != "custom"
	var card_counts: Dictionary = battle.deck(source).cards if public_preset else spent
	var legacy: bool = battle.tactics_revision == 1
	var models: Array[Dictionary] = []
	for id: String in card_counts:
		var card: Dictionary = battle.definition(id)
		if int(card.cost) > next_mana or (public_preset and int(card_counts[id]) <= int(spent.get(id, 0))): continue
		var type: String = card.get("effect", "")
		if type not in ["formation", "choice", "area"]: continue
		if legacy and type != "formation": continue
		var effect: Dictionary = card if legacy else battle.card_for_play(card, source, next_mana)
		if type == "choice": effect = effect.modes.enemy
		elif type == "area": effect = {"target_side":"enemy", "damage":effect.amount, "fire":true}
		if effect.get("target_side") != "enemy" or int(effect.get("damage", 0)) <= 0: continue
		if not legacy and int(effect.get("radius", 1)) == 0: continue
		models.append({"id":id, "radius":int(effect.get("radius", 1)), "shape":str(effect.get("shape", "")),
			"unit_center":type != "formation", "grounds":[] if legacy else effect.get("grounds", []), "legacy":legacy,
			"troop_damage":_next_damage(battle, effect, source, false), "leader_damage":_next_damage(battle, effect, source, true),
			"clear_shield":effect.get("clear_shield", false), "root":effect.get("root", false),
			"confidence": 1.0 if public_preset else 0.63, "centers": {}})
	if models.is_empty(): return models
	var reach: Dictionary = {}
	for enemy: Dictionary in enemies:
		var cast_range: int = battle.unit_cast_range(enemy.unit)
		for origin: Vector2i in enemy.origins:
			var weight: float = 1.0 if origin == enemy.unit.pos else 0.57
			for center: Vector2i in battle.Formation.footprint(battle, origin, cast_range):
				if float(reach.get(center, 0.0)) < weight: reach[center] = weight
	var occupied: Dictionary = {}
	for unit: Dictionary in battle.units:
		if unit.side == battle.active_side: occupied[unit.pos] = true
	for model: Dictionary in models:
		model["reach"] = reach
		model["occupied"] = occupied
		for ally: Dictionary in battle.units:
			if ally.side != battle.active_side: continue
			var loss: float = _impact(model, ally, battle.ground(ally.pos))
			if loss <= 0.0: continue
			for center: Vector2i in battle.Formation.footprint(battle, ally.pos, model.radius, model.shape):
				if reach.has(center): model.centers[center] = float(model.centers.get(center, 0.0)) + loss
	return models

static func _next_damage(battle: Battle, card: Dictionary, side: int, commander: bool) -> int:
	var amount: int = int(card.get("commander_damage", card.damage)) if commander else int(card.damage)
	if (amount <= 0 and battle.tactics_revision != 1) or not card.get("fire", false): return amount
	if battle.hero(side).id == "pyromancer": amount += 1
	return amount if battle.weather_remaining == 1 else battle.fire_damage(amount)

static func _impact(model: Dictionary, unit: Dictionary, ground: String) -> float:
	if not model.grounds.is_empty() and not model.grounds.has(ground): return 0.0
	var amount: int = model.leader_damage if unit.kind == "commander" else model.troop_damage
	if amount <= 0 and not model.legacy: return 0.0
	var shield: int = int(unit.get("shield", 0))
	var absorbed: int = shield if model.clear_shield else mini(amount, shield)
	var loss: int = mini(int(unit.hp), amount if model.clear_shield else maxi(0, amount - shield))
	var score: float = loss * 2.7 + absorbed * 0.8
	if loss >= int(unit.hp): score += 75.0 if unit.kind == "commander" else 14.0
	if model.root and unit.kind != "commander" and loss < int(unit.hp): score += 3.0
	return score

static func exposure(battle: Battle, unit: Dictionary, destination: Vector2i, models: Array[Dictionary], previous: Vector2i = Vector2i(-1, -1)) -> float:
	var risk: float = 0.0
	var on_board: bool = battle.inside(previous)
	var ground: String = battle.ground(destination)
	var old_ground: String = battle.ground(previous) if on_board else ground
	for model: Dictionary in models:
		var loss: float = _impact(model, unit, ground)
		if loss <= 0.0: continue
		var old_loss := loss if old_ground == ground else _impact(model, unit, old_ground)
		for center: Vector2i in battle.Formation.footprint(battle, destination, model.radius, model.shape):
			if not model.reach.has(center): continue
			# A two-way order takes its offensive branch only when centered on our unit.
			# Price the proposed move with its origin vacated and its destination occupied.
			if model.unit_center and center != destination and (center == previous or not model.occupied.has(center)): continue
			var allies: float = float(model.centers.get(center, 0.0))
			if on_board and battle.Formation.covers(previous, center, model.radius, model.shape): allies -= old_loss
			if allies <= 0.0: continue
			# Price sharing a cast center with a vulnerable ally. Opposing
			# spells can use only one center even when several overlap.
			var overlap: float = minf(loss, allies) + minf(allies, loss * 2.0) * 0.45
			risk = maxf(risk, overlap * float(model.reach[center]) * float(model.confidence))
	return risk

static func value(battle: Battle, action: Dictionary, models: Array[Dictionary]) -> float:
	if models.is_empty(): return 0.0
	if action.type == "move":
		var unit: Dictionary = battle.get_unit(action.unit_id)
		var before: float = exposure(battle, unit, unit.pos, models, unit.pos)
		return before - exposure(battle, unit, action.target, models, unit.pos)
	if action.type != "play": return 0.0
	var side: int = battle.active_side
	var card: Dictionary = battle.card_for_play(battle.definition(battle.hand_card(side, action.card_uid).card_id), side)
	if card.type != "unit": return 0.0
	var unit: Dictionary = {"kind": card.kind, "hp": card.hp,
		"shield": int(card.get("entry", {}).get("self_shield", 0)) + int(battle.weather == "lanterns")}
	return -0.65 * exposure(battle, unit, action.target, models)
