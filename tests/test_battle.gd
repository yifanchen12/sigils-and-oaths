extends SceneTree

const BattleModel = preload("res://scripts/battle.gd")
const EnemyAI = preload("res://scripts/opponent.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func give(battle: Battle, card_id: String, side: int = 0) -> Dictionary:
	# Move an actual existing card to hand; keep the exactly-one-zone invariant.
	for zone_name: String in ["deck", "discard"]:
		for instance: Dictionary in battle.players[side][zone_name]:
			if instance.card_id == card_id:
				battle.players[side][zone_name].erase(instance)
				battle.players[side].hand.append(instance)
				return instance
	for instance: Dictionary in battle.players[side].hand:
		if instance.card_id == card_id: return instance
	return {}

func fresh() -> Battle:
	var battle: Battle = BattleModel.new(42, "classic_greenwood")
	battle.players[0].mana = 10
	battle.players[0].max_mana = 10
	return battle

func summon(battle: Battle, card_id: String, pos: Vector2i) -> Dictionary:
	var card: Dictionary = give(battle, card_id)
	var outcome: Dictionary = battle.apply_action({"type": "play", "card_uid": card.uid, "target": pos})
	check(outcome.ok, "summon " + card_id)
	return battle.unit_at(pos)

func zone_invariants(battle: Battle) -> bool:
	var ids: Dictionary = {}
	var occupied: Dictionary = {}
	for side: int in range(2):
		var count: int = 0
		for zone_name: String in ["deck", "hand", "discard"]:
			for card: Dictionary in battle.players[side][zone_name]:
				if ids.has(card.uid): return false
				ids[card.uid] = true
				count += 1
		for unit: Dictionary in battle.units:
			if unit.side != side or not unit.has("card"): continue
			if ids.has(unit.card.uid): return false
			ids[unit.card.uid] = true
			count += 1
		if count != int(battle.players[side].card_total): return false
	for unit: Dictionary in battle.units:
		if occupied.has(unit.pos): return false
		occupied[unit.pos] = true
	return true

func run() -> void:
	var battle: Battle = fresh()
	check(battle.CATALOG.cards.size() == 25 and battle.deck_size == 30, "24 collectible definitions plus initiative and 30-card deck")
	check(battle.players[0].hand.size() == 5 and battle.players[1].hand.size() == 6, "second player opening compensation")
	check(zone_invariants(battle), "initial zones")
	var duplicate: Battle = BattleModel.new(42, "classic_greenwood")
	check(battle.players[0].deck == duplicate.players[0].deck, "seeded shuffle")
	check(battle.deployment_cells(0).has(Vector2i(3, 4)), "commander is deployment anchor")
	check(not battle.deployment_cells(0).has(Vector2i(2, 4)), "no diagonal deployment")
	var sword_card: Dictionary = give(battle, "sword")
	var snapshot: String = var_to_str([battle.players, battle.units, battle.next_id, battle.log_lines])
	var invalid: Dictionary = battle.apply_action({"type": "play", "card_uid": sword_card.uid, "target": Vector2i(0, 0)})
	check(not invalid.ok, "illegal deployment rejected")
	check(snapshot == var_to_str([battle.players, battle.units, battle.next_id, battle.log_lines]), "invalid action is atomic")
	var unit: Dictionary = summon(battle, "sword", Vector2i(3, 4))
	check(battle.players[0].mana == 9, "deployment pays exact cost")
	check(battle.movement_cells(unit).is_empty() and battle.attack_targets(unit).is_empty(), "summoning sickness")
	check(battle.deployment_cells(0).has(Vector2i(3, 3)), "new troop extends front-line deployment")
	var forward: Dictionary = summon(battle, "spear", Vector2i(3, 3))
	check(not forward.is_empty(), "deploy beyond original back ranks")
	check(not battle.deployment_cells(0).has(Vector2i(2, 2)), "mountain cannot be deployed onto")
	check(zone_invariants(battle), "summoned cards occupy board zone")
	battle.end_turn()
	battle.end_turn()
	check(not unit.summoning and not unit.moved, "own next turn refreshes units")
	check(not battle.movement_cells(unit).has(Vector2i(3, 3)), "occupied movement blocked")
	check(not battle.movement_cells(unit).has(Vector2i(2, 2)), "mountain blocks movement")
	var moved: Dictionary = battle.apply_action({"type": "move", "unit_id": unit.id, "target": Vector2i(4, 4)})
	check(moved.ok, "legal movement")
	check(battle.movement_cells(unit).is_empty(), "one move per turn")
	battle.players[0].mana = 10
	var march: Dictionary = give(battle, "march")
	check(battle.apply_action({"type": "play", "card_uid": march.uid, "target": unit.pos}).ok, "march refreshes movement")
	check(not battle.movement_cells(unit).is_empty(), "extra movement available")
	var enemy: Dictionary = battle.commander(1)
	enemy.pos = Vector2i(5, 4)
	unit.pos = Vector2i(4, 4)
	var leader_hp: int = enemy.hp
	var soldier_hp: int = unit.hp
	check(battle.apply_action({"type": "attack", "unit_id": unit.id, "target": enemy.pos}).ok, "adjacent attack")
	check(enemy.hp < leader_hp and unit.hp < soldier_hp, "surviving defender counterattacks once")
	check(battle.movement_cells(unit).is_empty() and battle.attack_targets(unit).is_empty(), "attack ends both actions")
	check(not battle.spell_cells(battle.definition("march"), 0).has(unit.pos), "march cannot bypass attacked state")

	test_damage_and_spells()
	test_limits_and_endgame()
	var simulated: int = 0
	for seed_value: int in range(12):
		var game: Battle = BattleModel.new(seed_value, "classic_greenwood")
		var steps: int = 0
		while game.winner == -1 and steps < 1600:
			var action: Dictionary = EnemyAI.choose(game)
			var outcome: Dictionary = game.apply_action(action)
			if not outcome.ok:
				check(false, "AI chose illegal action at seed %d: %s" % [seed_value, outcome.message])
				break
			steps += 1
			if not zone_invariants(game):
				check(false, "zone/occupancy invariant during AI match")
				break
		check(game.winner != -1, "full AI game terminates, seed %d" % seed_value)
		simulated += 1
	print("CHECKS: %d | FAILURES: %d | COMPLETE AI MATCHES: %d" % [checks, failures, simulated])
	quit(0 if failures == 0 else 1)

func test_damage_and_spells() -> void:
	var battle: Battle = fresh()
	var sword: Dictionary = summon(battle, "sword", Vector2i(3, 4))
	var spear: Dictionary = summon(battle, "spear", Vector2i(3, 3))
	battle.terrain[sword.pos] = "plain"
	check(battle.damage_preview(sword, spear) == 1, "class bonus, forest and spear stance")
	spear.pos = Vector2i(4, 4)
	check(battle.damage_preview(sword, spear) == 2, "class bonus and spear stance on plain")
	spear.kind = "archer"
	spear.defense = 99
	check(battle.damage_preview(sword, spear) == 1, "minimum attack damage")
	var ward: Dictionary = give(battle, "ward")
	check(battle.apply_action({"type": "play", "card_uid": ward.uid, "target": sword.pos}).ok, "shield spell")
	check(sword.shield == 3, "shield value")
	var leader: Dictionary = battle.commander(1)
	battle._hurt(sword, 4)
	check(sword.shield == 0 and sword.hp == 4, "shield absorbs before hp")
	battle.players[0].mana = 10
	var heal: Dictionary = give(battle, "heal")
	check(battle.apply_action({"type": "play", "card_uid": heal.uid, "target": sword.pos}).ok, "healing spell")
	check(sword.hp == sword.max_hp, "healing capped at maximum")
	summon(battle, "mage", Vector2i(4, 3)) # Forward caster supplies local reach.
	var bolt: Dictionary = give(battle, "bolt")
	check(battle.apply_action({"type": "play", "card_uid": bolt.uid, "target": leader.pos}).ok, "single target spell")
	check(leader.hp == 16, "spell damage ignores defense")
	battle.players[0].mana = 10
	var nova: Dictionary = give(battle, "nova")
	spear.side = 1
	spear.pos = Vector2i(4, 1)
	var before: int = spear.hp
	check(battle.apply_action({"type": "play", "card_uid": nova.uid, "target": leader.pos}).ok, "area spell")
	check(spear.hp == before - 3 and leader.hp == 13, "area hits adjacent enemy")
	var medic_battle: Battle = fresh()
	var medic: Dictionary = summon(medic_battle, "healer", Vector2i(3, 4))
	var ally: Dictionary = summon(medic_battle, "sword", Vector2i(3, 3))
	ally.hp = 2
	medic.hp = 3
	medic_battle.end_turn()
	medic_battle.end_turn()
	check(ally.hp == 3 and medic.hp == 4, "medic heals self and adjacent allies on own turn")

func test_limits_and_endgame() -> void:
	var battle: Battle = fresh()
	var card: Dictionary = give(battle, "mage")
	battle.players[0].mana = 0
	var before: String = var_to_str([battle.players, battle.units])
	check(not battle.apply_action({"type": "play", "card_uid": card.uid, "target": Vector2i(3, 4)}).ok, "insufficient mana rejected")
	check(before == var_to_str([battle.players, battle.units]), "insufficient mana leaves state unchanged")
	check(not battle.apply_action({"type": "move", "unit_id": battle.commander(1).id, "target": Vector2i(4, 1)}).ok, "cannot control enemy")
	check(not battle.apply_action({"type": "play", "target": "bad"}).ok, "invalid coordinate type rejected")
	battle._draw(0, battle.players[0].deck.size())
	check(battle.players[0].hand.size() == 8, "hand limit enforced")
	check(zone_invariants(battle), "overdraw cards enter discard")
	battle._draw(0, 1)
	var hp: int = battle.commander(0).hp
	battle._draw(0, 2)
	check(battle.players[0].fatigue == 3 and battle.commander(0).hp == hp - 5, "empty deck increments fatigue")
	battle.commander(0).hp = 1
	battle._draw(0, 1)
	battle._cleanup()
	battle._check_winner()
	check(battle.winner == 1, "leader death resolves victory")
	check(not battle.apply_action({"type": "end_turn"}).ok, "finished game rejects actions")
	var tied: Battle = fresh()
	tied.commander(0).hp = 0
	tied.commander(1).hp = 0
	tied._cleanup()
	tied._check_winner()
	check(tied.winner == 2, "simultaneous leader deaths draw")
	var capped: Battle = fresh()
	for card_id: String in ["sword", "spear", "cavalry", "archer", "mage", "healer"]:
		capped.players[0].mana = 10
		summon(capped, card_id, capped.deployment_cells(0)[0])
	check(capped.army_count(0) == 6 and capped.deployment_cells(0).is_empty(), "six-unit cap")
	var extra: Dictionary = give(capped, "sword")
	var capped_before: String = var_to_str([capped.players, capped.units])
	check(not capped.apply_action({"type": "play", "card_uid": extra.uid, "target": Vector2i(7, 5)}).ok, "seventh troop rejected")
	check(capped_before == var_to_str([capped.players, capped.units]), "unit cap rejection is atomic")
