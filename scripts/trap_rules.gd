extends RefCounted
## Traps are hand cards in their own zone until consumed. Opponents know only
## the count; placement legality and AI evaluation must not inspect enemy slots.
const LIMIT: int = 2

static func count(battle: RefCounted, side: int) -> int:
	var total: int = 0
	for trap: Dictionary in battle.traps:
		if trap.side == side: total += 1
	return total

static func position(battle: RefCounted, trap: Dictionary) -> Vector2i:
	if trap.unit_id == -1: return trap.pos
	var unit: Dictionary = battle.get_unit(trap.unit_id)
	return unit.get("pos", Vector2i(-1, -1))

static func targets(battle: RefCounted, card: Dictionary, side: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if count(battle, side) >= LIMIT: return result
	for cell: Vector2i in battle.casting_cells(side):
		var unit: Dictionary = battle.unit_at(cell)
		if card.trigger == "step" and (not battle.passable(cell) or not unit.is_empty()): continue
		if card.trigger in ["attack", "spell"] and (unit.is_empty() or unit.side != side): continue
		var occupied: bool = false
		for trap: Dictionary in battle.traps:
			if trap.side != side: continue
			if card.trigger == "step" and trap.unit_id == -1 and trap.pos == cell: occupied = true
			if card.trigger in ["attack", "spell"] and trap.unit_id == unit.id: occupied = true
		if not occupied: result.append(cell)
	return result

static func place(battle: RefCounted, instance: Dictionary, card: Dictionary, cell: Vector2i) -> void:
	var anchored: bool = card.trigger in ["attack", "spell"]
	battle.traps.append({"side": battle.active_side, "card": instance, "pos": Vector2i(-1, -1) if anchored else cell, "unit_id": battle.unit_at(cell).id if anchored else -1})
	battle._record("%s从手牌伏设了一张陷阱。" % battle.side_name(battle.active_side))

static func consume(battle: RefCounted, trap: Dictionary, reason: String) -> void:
	var cell: Vector2i = position(battle, trap)
	battle.traps.erase(trap)
	battle.players[trap.side].discard.append(trap.card)
	var card: Dictionary = battle.definition(trap.card.card_id)
	battle.last_trap_events.append({"cell": cell, "name": card.name, "reason": reason, "side": trap.side})
	battle._record("%s的「%s」%s。" % [battle.side_name(trap.side), card.name, reason])

static func stepped(battle: RefCounted, unit: Dictionary) -> void:
	# Resolve in placement order, consuming before effects. No recursive event
	# generation; forced displacement and deployment do not call this hook.
	for trap: Dictionary in battle.traps.duplicate():
		if unit.hp <= 0: break
		if trap.side == unit.side or trap.unit_id != -1 or trap.pos != unit.pos: continue
		var card: Dictionary = battle.definition(trap.card.card_id)
		consume(battle, trap, "触发")
		battle._hurt(unit, battle.fire_damage(int(card.amount)) if card.get("fire", false) else int(card.amount))
		if card.get("root", false): unit.rooted_turns = maxi(1, int(unit.rooted_turns))

static func attacked(battle: RefCounted, defender: Dictionary) -> void:
	for trap: Dictionary in battle.traps.duplicate():
		if trap.unit_id != defender.id: continue
		var card: Dictionary = battle.definition(trap.card.card_id)
		if card.trigger != "attack": continue
		consume(battle, trap, "触发")
		defender.shield = mini(5, int(defender.shield) + int(card.amount))

static func spelled(battle: RefCounted, defender: Dictionary) -> void:
	for trap: Dictionary in battle.traps.duplicate():
		if trap.unit_id != defender.id or trap.side == battle.active_side: continue
		var card: Dictionary = battle.definition(trap.card.card_id)
		if card.trigger != "spell": continue
		consume(battle, trap, "触发")
		defender.shield = mini(5, int(defender.shield) + int(card.amount))

static func reveal(battle: RefCounted, cell: Vector2i, side: int) -> void:
	var found: int = 0
	for trap: Dictionary in battle.traps.duplicate():
		if trap.side != side and battle.distance(position(battle, trap), cell) <= 1:
			consume(battle, trap, "被探明并拆除"); found += 1
	if found == 0: battle._record("探查范围内没有敌方陷阱。")

static func cleanup(battle: RefCounted) -> void:
	for trap: Dictionary in battle.traps.duplicate():
		if trap.unit_id != -1 and battle.get_unit(trap.unit_id).is_empty(): consume(battle, trap, "因保护对象离场而失效")
