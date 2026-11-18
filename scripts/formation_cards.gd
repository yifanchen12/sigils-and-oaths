extends RefCounted
## Local effects share recipients and projections with the card preview and AI.

static func _axes_match(delta: Vector2i, shape: String) -> bool:
	match shape:
		"row": return delta.y == 0
		"column": return delta.x == 0
		"cross": return delta.x == 0 or delta.y == 0
	return true

static func covers(center: Vector2i, cell: Vector2i, radius: int, shape: String = "") -> bool:
	var delta: Vector2i = cell - center
	return absi(delta.x) + absi(delta.y) <= radius and _axes_match(delta, shape)

static func footprint(battle: RefCounted, center: Vector2i, radius: int, shape: String = "") -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy: int in range(-radius, radius + 1):
		var reach: int = radius - absi(dy)
		for dx: int in range(-reach, reach + 1):
			var cell: Vector2i = center + Vector2i(dx, dy)
			if battle.inside(cell) and (shape.is_empty() or _axes_match(Vector2i(dx, dy), shape)): cells.append(cell)
	return cells

static func recipients(battle: RefCounted, card: Dictionary, center: Vector2i, side: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ally: bool = card.get("target_side", "ally") == "ally"
	var radius: int = int(card.get("radius", 1))
	var shape: String = str(card.get("shape", ""))
	var grounds: Array = card.get("grounds", [])
	for unit: Dictionary in battle.units:
		if unit.hp <= 0 or not covers(center, unit.pos, radius, shape): continue
		if unit.side == side:
			if ally and not _helps(card, unit): continue
			if not ally and (int(card.get("rally_shield", 0)) == 0 or unit.shield >= 5): continue
		else:
			if ally or (not grounds.is_empty() and not grounds.has(battle.ground(unit.pos))): continue
			if not _hinders(card, unit): continue
		result.append(unit)
	return result

static func _helps(card: Dictionary, unit: Dictionary) -> bool:
	return (int(card.get("healing", 0)) > 0 and unit.hp < unit.max_hp
		or int(card.get("shield", 0)) > 0 and unit.shield < 5
		or card.get("cleanse", false) and unit.rooted_turns > 0
		or can_refresh_move(card, unit)
		or can_refresh_attack(card, unit))

static func _hinders(card: Dictionary, unit: Dictionary) -> bool:
	return int(card.get("damage", 0)) > 0 or (card.get("root", false) and unit.kind != "commander" and unit.rooted_turns < 2)

static func can_refresh_move(card: Dictionary, unit: Dictionary) -> bool:
	return (card.get("refresh_move", false) and unit.kind != "commander" and not unit.summoning
		and unit.moved and not unit.attacked and (unit.rooted_turns == 0 or card.get("cleanse", false)))

static func can_refresh_attack(card: Dictionary, unit: Dictionary) -> bool:
	return card.get("refresh_attack", false) and unit.kind != "commander" and not unit.summoning and unit.attacked

static func damage(battle: RefCounted, card: Dictionary, side: int, commander: bool = false) -> int:
	var base: int = int(card.get("damage", 0))
	if commander: base = int(card.get("commander_damage", base))
	return battle.spell_damage({"amount": base}, side) if card.get("fire", false) else base

static func changes(battle: RefCounted, card: Dictionary, center: Vector2i, side: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for unit: Dictionary in recipients(battle, card, center, side):
		var friendly: bool = unit.side == side
		var amount: int = 0 if friendly else damage(battle, card, side, unit.kind == "commander")
		var shield: int = 0 if not friendly and card.get("clear_shield", false) else unit.shield
		var gained_shield: int = int(card.get("rally_shield", card.get("shield", 0))) if friendly else 0
		var hp: int = maxi(0, int(unit.hp) - maxi(0, amount - shield))
		shield = mini(5, maxi(0, shield - amount) + gained_shield)
		if friendly: hp = mini(int(unit.max_hp), hp + int(card.get("healing", 0)))
		results.append({"unit_id": unit.id, "name": unit.name, "position_before": unit.pos, "damage": amount, "friendly": friendly,
			"hp_before": unit.hp, "hp_after": hp, "hp_loss": maxi(0, int(unit.hp) - hp), "healing": maxi(0, hp - int(unit.hp)),
			"shield_before": unit.shield, "shield_after": shield, "shield_delta": shield - int(unit.shield),
			"root": not friendly and hp > 0 and unit.kind != "commander" and card.get("root", false) and unit.rooted_turns < 2,
			"cleanse": friendly and card.get("cleanse", false) and unit.rooted_turns > 0,
			"refresh_move": friendly and can_refresh_move(card, unit), "refresh_attack": friendly and can_refresh_attack(card, unit)})
	return results

static func resolve(battle: RefCounted, card: Dictionary, center: Vector2i, side: int) -> void:
	for change: Dictionary in changes(battle, card, center, side):
		var unit: Dictionary = battle.get_unit(change.unit_id)
		if unit.hp <= 0: continue
		if change.damage > 0:
			if card.get("clear_shield", false): unit.shield = 0
			battle._spell_hit(unit, change.damage)
		if not change.friendly:
			# A hidden spell ward may keep a unit alive through a lethal preview.
			if unit.hp > 0 and unit.kind != "commander" and card.get("root", false): unit.rooted_turns = maxi(2, int(unit.rooted_turns))
			continue
		unit.hp = mini(int(unit.max_hp), int(unit.hp) + int(change.healing))
		unit.shield = mini(5, int(unit.shield) + int(change.shield_delta))
		if change.cleanse: unit.rooted_turns = 0
		if change.refresh_move: unit.moved = false
		if change.refresh_attack: unit.attacked = false
