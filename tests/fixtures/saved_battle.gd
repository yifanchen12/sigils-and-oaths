extends RefCounted
const Model = preload("res://scripts/battle.gd")

static func give(battle: RefCounted, kind: String, side: int = 0) -> Dictionary:
	for card: Dictionary in battle.players[side].hand:
		if card.card_id == kind: return card
	if battle.players[side].hand.size() == Model.HAND_LIMIT: battle.players[side].discard.append(battle.players[side].hand.pop_back())
	for card: Dictionary in battle.players[side].deck:
		if card.card_id == kind:
			battle.players[side].deck.erase(card)
			battle.players[side].hand.append(card)
			return card
	battle.add_generated_card(side, kind)
	return battle.players[side].hand.back()

static func troop(battle: RefCounted, kind: String, cell: Vector2i, side: int = 0) -> Dictionary:
	var card: Dictionary = {}
	for zone: String in ["deck", "hand"]:
		for item: Dictionary in battle.players[side][zone]:
			if item.card_id == kind:
				card = item
				battle.players[side][zone].erase(item)
				break
		if not card.is_empty(): break
	if card.is_empty():
		card = {"uid": battle._id(), "card_id": kind}
		battle.players[side].card_total += 1
	battle.terrain[cell] = "plain"
	var id: int = battle._spawn(battle.definition(kind), cell, side)
	card["unit_id"] = id
	var unit: Dictionary = battle.get_unit(id)
	unit["card"] = card
	unit.summoning = false
	unit.attacked = false
	unit.moved = false
	return unit

static func rich() -> RefCounted:
	var battle: RefCounted = Model.new(1317, "greenwood", "warden", "pyromancer", "balanced", "assault")
	battle.set_commander_identity(1, "军道扣车队长", "terrain_fort")
	var kinds: Array[String] = ["sword", "spear", "cavalry", "archer", "mage", "healer"]
	for index: int in range(kinds.size()): troop(battle, kinds[index], Vector2i(4 + index % 3, 4 + index / 3))
	var enemy: Dictionary = troop(battle, "sword", Vector2i(5, 3), 1)
	enemy.rooted_turns = 1
	var guard: Dictionary = troop(battle, "spear", Vector2i(4, 3), 1)
	guard.guarding = true; guard.skill_used = true; guard.attacked = true; guard.moved = true
	var later_guard: Dictionary = troop(battle, "spear", Vector2i(6, 3), 1)
	later_guard.guarding = true; later_guard.skill_used = true; later_guard.attacked = true; later_guard.moved = true
	for unit: Dictionary in battle.units:
		if unit.side != 0: continue
		match unit.kind:
			"sword": unit.hp = 3; unit.shield = 3; unit.skill_used = true; unit.attacked = true; unit.moved = true
			"spear": unit.guarding = true; unit.skill_used = true; unit.attacked = true; unit.moved = true
			"cavalry": unit.moved = true; unit.last_move_distance = 3; unit.skill_used = true
			"archer": unit.rooted_turns = 2; battle.terrain[unit.pos] = "fort"
			"mage": unit.skill_used = true
			"healer": unit.hp = 2; unit.shield = 2
	battle.players[0].mana = 4; battle.players[0].max_mana = 7
	battle.players[1].mana = 3; battle.players[1].max_mana = 5
	battle.players[1].fatigue = 2; battle.players[1].skill_cooldown = 2; battle.players[1].spell_boost_used = true
	battle.turn = 13
	battle.weather = "snow"; battle.weather_remaining = 3
	battle.time_remaining = 22.31251234567
	battle.rng.randi()
	return battle
