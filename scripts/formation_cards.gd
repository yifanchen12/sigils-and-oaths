extends RefCounted
## Local effects share recipients and projections with the card preview and AI.

static func footprint(battle: RefCounted, center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy: int in range(-radius, radius + 1):
		var reach: int = radius - absi(dy)
		for dx: int in range(-reach, reach + 1):
			var cell: Vector2i = center + Vector2i(dx, dy)
			if battle.inside(cell): cells.append(cell)
	return cells

static func recipients(battle: RefCounted, card: Dictionary, center: Vector2i, side: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ally: bool = card.get("target_side", "ally") == "ally"
	var radius: int = int(card.get("radius", 1))
	for unit: Dictionary in battle.units:
		if (unit.side == side) != ally or unit.hp <= 0 or battle.distance(unit.pos, center) > radius: continue
		if ally and not _helps(card, unit): continue
		result.append(unit)
	return result

static func _helps(card: Dictionary, unit: Dictionary) -> bool:
	return (int(card.get("healing", 0)) > 0 and unit.hp < unit.max_hp
		or int(card.get("shield", 0)) > 0 and unit.shield < 5
		or card.get("cleanse", false) and unit.rooted_turns > 0
		or can_refresh_move(card, unit)
		or can_refresh_attack(card, unit))

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
		var amount: int = damage(battle, card, side, unit.kind == "commander")
		var shield: int = 0 if card.get("clear_shield", false) else unit.shield
		var hp: int = maxi(0, int(unit.hp) - maxi(0, amount - shield))
		shield = mini(5, maxi(0, shield - amount) + int(card.get("shield", 0)))
		hp = mini(int(unit.max_hp), hp + int(card.get("healing", 0)))
		results.append({"unit_id": unit.id, "name": unit.name, "position_before": unit.pos, "damage": amount,
			"hp_before": unit.hp, "hp_after": hp, "hp_loss": maxi(0, int(unit.hp) - hp), "healing": maxi(0, hp - int(unit.hp)),
			"shield_before": unit.shield, "shield_after": shield, "shield_delta": shield - int(unit.shield),
			"root": hp > 0 and unit.kind != "commander" and card.get("root", false) and unit.rooted_turns < 2,
			"cleanse": card.get("cleanse", false) and unit.rooted_turns > 0,
			"refresh_move": can_refresh_move(card, unit), "refresh_attack": can_refresh_attack(card, unit)})
	return results

static func resolve(battle: RefCounted, card: Dictionary, center: Vector2i) -> void:
	for change: Dictionary in changes(battle, card, center, battle.active_side):
		var unit: Dictionary = battle.get_unit(change.unit_id)
		if change.damage > 0:
			if card.get("clear_shield", false): unit.shield = 0
			battle._spell_hit(unit, change.damage)
			if unit.hp > 0 and unit.kind != "commander" and card.get("root", false):
				unit.rooted_turns = maxi(2, int(unit.rooted_turns))
			continue
		unit.hp = change.hp_after
		unit.shield = change.shield_after
		if change.cleanse: unit.rooted_turns = 0
		if change.refresh_move: unit.moved = false
		if change.refresh_attack: unit.attacked = false
