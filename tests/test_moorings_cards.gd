extends "res://tests/test_expansion_cards.gd"

const Art = preload("res://scripts/art_library.gd")
const NO_TARGET := Vector2i(-1, -1)
const CENTER := Vector2i(4, 3)

func give_action(battle: Battle, id: String, target: Vector2i) -> Dictionary:
	check(battle.add_generated_card(battle.active_side, id), "fixture gained " + id)
	return {"type": "play", "card_uid": battle.players[battle.active_side].hand.back().uid, "target": target}

func stash(battle: Battle, id: String, side: int = 0) -> Dictionary:
	check(battle.add_generated_card(side, id), "fixture placed in discard " + id)
	var card: Dictionary = battle.players[side].hand.pop_back()
	battle.players[side].discard.append(card)
	return card

func test_catalog() -> void:
	var counts: Dictionary = {}
	var curves: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var regions: Dictionary = {}
	var pressure: Dictionary = Model.DECKS.find("breakwater_line")
	var recovery: Dictionary = Model.DECKS.find("ember_quarter")
	for card: Dictionary in Model.CATALOG.cards:
		if card.get("set_id", "") != "moorings": continue
		counts[card.type] = int(counts.get(card.type, 0)) + 1
		curves[int(card.cost) - 1] += 1
		var art: AtlasTexture = Art.get_texture(card.id) as AtlasTexture
		check(art != null and art.region.size.x >= 450 and art.region.size.y >= 450, "distinct illustrated card " + card.id)
		if art != null:
			var key: String = art.atlas.resource_path + str(art.region)
			check(not regions.has(key), "no reused atlas cell " + card.id)
			regions[key] = true
		check(pressure.cards.has(card.id) or recovery.cards.has(card.id), "card occurs in a selectable preset: " + card.id)
	check(curves == [2, 3, 2, 3, 2, 3, 2, 2, 2, 3], "all ten costs including twelve cards at 6 or above")
	check(counts == {"unit": 10, "spell": 8, "environment": 3, "trap": 3}, "four actual card types")
	check(Model.CATALOG.cards.size() == 165 and Model.DECKS.decks.size() == 16, "164 collectible cards and 16 presets")
	for deck: Dictionary in [pressure, recovery]:
		check(Model.DECKS.validate_counts(deck.cards, Model.CATALOG.cards).is_empty(), "legal 30-card preset " + deck.id)

func test_line_cast_and_ai() -> void:
	var battle := arena()
	var ally: Dictionary = troop(battle, "sword", CENTER + Vector2i.LEFT, 0)
	var enemy: Dictionary = troop(battle, "spear", CENTER + Vector2i.RIGHT * 2, 1)
	var outside: Dictionary = troop(battle, "spear", CENTER + Vector2i.UP, 1)
	var leader: Dictionary = battle.commander(1)
	leader.pos = CENTER + Vector2i.RIGHT * 3
	enemy.shield = 5
	leader.shield = 3
	var action: Dictionary = give_action(battle, "copper_boltline", CENTER)
	battle.players[0].mana = 7
	var before: Dictionary = Snapshot.capture(battle)
	check(not battle.apply_action(action).ok and before == Snapshot.capture(battle), "cannot play eight-cost spell with seven mana")
	battle.players[0].mana = 8
	var forecast: Dictionary = Effects.predict(battle, action)
	check(forecast.cells.size() == 7 and forecast.changes.size() == 2 and forecast.cells.has(enemy.pos), "horizontal preview identifies two possible victims")
	check(not forecast.cells.has(outside.pos) and forecast.changes.any(func(change: Dictionary) -> bool: return change.unit_id == enemy.id and change.hp_loss == 5 and change.shield_after == 0), "damage preview breaks shield and excludes off-axis cells")
	var split_value: float = AI.evaluate(battle, action)
	outside.pos = CENTER
	check(AI.evaluate(battle, action) > split_value, "AI values a row with three victims more than a split formation")
	outside.pos = CENTER + Vector2i.UP
	check(battle.apply_action(action).ok and battle.players[0].mana == 0, "eight-cost card pays the full amount")
	check(enemy.hp == enemy.max_hp - 5 and enemy.shield == 0 and leader.hp == leader.max_hp - 2 and leader.shield == 0, "line damage agrees with the preview")
	check(outside.hp == outside.max_hp and ally.hp == ally.max_hp, "off-axis and friendly units are safe")
	valid(battle, "horizontal shieldbreaking")

	battle = arena()
	enemy = troop(battle, "spear", Vector2i(7, 3), 1)
	action = give_action(battle, "seam_shot", Vector2i(6, 3))
	var distant: Dictionary = Snapshot.capture(battle)
	check(not battle.apply_action(action).ok and Snapshot.capture(battle) == distant, "line spells forbid distant cast centers")
	var mage: Dictionary = troop(battle, "mage", Vector2i(2, 4), 0)
	action.target = Vector2i(7, 4)
	enemy.pos = Vector2i(8, 4)
	check(not battle.card_targets(action.card_uid, 0).has(action.target), "five squares still outside a mage's cast range")
	action.target = Vector2i(6, 3)
	enemy.pos = Vector2i(7, 3)
	battle.commander(0).pos = Vector2i(1, 3)
	mage.pos = Vector2i(2, 3)
	check(battle.get_legal_actions(0).has(action) and battle.apply_action(action).ok and enemy.hp == enemy.max_hp - 2, "mage casts four squares to the center, then the line extends")

func test_terrain_and_deployment() -> void:
	var battle := arena()
	var site := Vector2i(3, 3)
	battle.terrain[site] = "forest"
	check(play(battle, "saltfield_runner", site).ok and battle.can_vanguard_move(battle.unit_at(site)) and battle.unit_at(site).shield == 1, "1-cost scout advances immediately in the woods")
	check(battle.attack_targets(battle.unit_at(site)).is_empty(), "terrain vanguard does not attack on entry")
	battle.terrain[Vector2i(4, 3)] = "bridge"
	check(play(battle, "bank_pikeman", Vector2i(4, 3)).ok and battle.unit_at(Vector2i(4, 3)).guarding, "2-cost spearman provides immediate bridge guard")

	battle = arena()
	var ally: Dictionary = troop(battle, "spear", CENTER + Vector2i.RIGHT, 0)
	battle.terrain[CENTER + Vector2i.LEFT] = "bridge"
	battle.terrain[CENTER + Vector2i.RIGHT * 2] = "water"
	var action: Dictionary = give_action(battle, "sluice_flags", CENTER)
	var forecast: Dictionary = Effects.predict(battle, action)
	check(forecast.cells == [CENTER + Vector2i.LEFT * 2, CENTER, ally.pos], "road preview includes only changeable cells on the chosen row")
	check(battle.apply_action(action).ok and ally.shield == 1 and battle.ground(ally.pos) == "road", "row roadwork reinforces the ally standing on the changed tile")
	check(battle.ground(CENTER + Vector2i.UP) == "plain" and battle.ground(CENTER + Vector2i.LEFT) == "bridge" and battle.ground(CENTER + Vector2i.RIGHT * 2) == "water", "roadwork preserves off-axis tiles and crossings")

	battle = arena()
	var friend: Dictionary = troop(battle, "spear", Vector2i(3, 2), 0)
	var diagonal: Dictionary = troop(battle, "sword", Vector2i(4, 4), 0)
	friend.hp = 2
	diagonal.hp = 2
	friend.rooted_turns = 2
	diagonal.rooted_turns = 2
	var place: Vector2i = Vector2i(3, 3)
	action = give_action(battle, "oathroad_mender", place)
	forecast = Effects.predict(battle, action)
	check(forecast.cells.size() == 5 and forecast.changes.size() == 1 and forecast.changes[0].unit_id == friend.id, "deployment shows its vertical assistance")
	check(battle.apply_action(action).ok and friend.hp == 5 and friend.rooted_turns == 0 and diagonal.hp == 2 and diagonal.rooted_turns == 2, "the medic heals and frees only in its column")
	valid(battle, "directional unit entry")

func test_reclaim() -> void:
	var battle := arena()
	var discard: Array = battle.players[0].discard
	battle.players[0].deck.append_array(discard)
	discard.clear()
	var no_reserves: Dictionary = give_action(battle, "ledger_patch", NO_TARGET)
	var before: Dictionary = Snapshot.capture(battle)
	check(not battle.apply_action(no_reserves).ok and Snapshot.capture(battle) == before, "no legal candidate means no payment")
	battle.players[0].discard.append(battle.players[0].hand.pop_back())
	var spell: Dictionary = stash(battle, "seam_shot")
	var ground: Dictionary = stash(battle, "sluice_flags")
	var trap: Dictionary = stash(battle, "quiet_net")
	var excluded: Dictionary = stash(battle, "levee_echo")
	var high: Dictionary = stash(battle, "copper_boltline")
	var competing_trap: Dictionary = stash(battle, "cress_ribbon")
	stash(battle, "fog", 1)
	var action: Dictionary = give_action(battle, "unbroken_ember_line", NO_TARGET)
	var state: int = battle.rng.state
	check(Model.is_global_card(battle.definition("unbroken_ember_line")) and battle.apply_action(action).ok, "ten-mana recycle uses the global hand action")
	check(battle.players[0].hand == [spell, ground, trap], "priority is spell, terrain then trap; latest matching original UID in each category")
	check(discard.has(excluded) and discard.has(high) and discard.has(competing_trap) and battle.rng.state == state and battle.players[0].fatigue == 0, "reclaim cards, high costs, other player's discard and RNG stay excluded")
	valid(battle, "three restored instances")

	battle = arena()
	ground = stash(battle, "sluice_flags")
	trap = stash(battle, "quiet_net")
	while battle.players[0].hand.size() < Model.HAND_LIMIT - 1:
		battle.add_generated_card(0, "spear")
	action = give_action(battle, "ledger_patch", NO_TARGET)
	check(battle.apply_action(action).ok and battle.players[0].hand.back().uid == ground.uid, "only the first reclaim fits a nearly full hand")
	check(battle.players[0].discard.has(trap) and battle.players[0].hand.size() == Model.HAND_LIMIT, "overflow remains where it was in discard")
	valid(battle, "capped reclaim")

	battle = arena()
	var medic: Dictionary = troop(battle, "sill_physician", CENTER, 0)
	medic.hp = 1
	troop(battle, "mage", CENTER + Vector2i.RIGHT, 1)
	spell = stash(battle, "seam_shot")
	battle.end_turn()
	check(play(battle, "bolt", CENTER).ok and battle.get_unit(medic.id).is_empty(), "an actual kill triggers the medic's recovery")
	check(battle.players[0].hand == [spell], "death returns a card to the casualty's side")
	valid(battle, "off-turn reclaim")

func test_new_traps() -> void:
	var battle := arena()
	var blue: Dictionary = troop(battle, "sword", CENTER + Vector2i.DOWN, 0)
	var beside: Dictionary = troop(battle, "spear", CENTER + Vector2i.UP + Vector2i.LEFT, 0)
	var enemy: Dictionary = troop(battle, "cavalry", CENTER + Vector2i.RIGHT * 2, 1)
	check(play(battle, "quiet_net", CENTER).ok and battle.visible_traps(1).is_empty(), "new ground trap is laid from hand without exposing its location")
	battle.end_turn()
	check(battle.apply_action({"type": "move", "unit_id": enemy.id, "target": CENTER + Vector2i.LEFT}).ok, "real enemy traverses the marked grid")
	check(enemy.hp == enemy.max_hp - 1 and blue.shield == 1 and beside.shield == 0 and battle.traps.is_empty(), "step one deals damage, shields only the correct line and consumes the trap")
	valid(battle, "trap's friendly column")

	battle = arena()
	var target: Dictionary = troop(battle, "spear", CENTER, 0)
	troop(battle, "mage", CENTER + Vector2i.RIGHT, 1)
	var ground: Dictionary = stash(battle, "sluice_flags")
	target.hp = 3
	check(play(battle, "cress_ribbon", CENTER).ok, "counter trap comes from hand")
	battle.end_turn()
	var incoming: int = battle.spell_damage(battle.definition("bolt"), 1)
	check(play(battle, "bolt", CENTER).ok and target.hp == 7 - incoming and target.shield == 0, "trap heals and shields before the incoming spell hits")
	check(battle.players[0].hand.has(ground) and not battle.players[1].hand.has(ground) and battle.players[0].discard.back().card_id == "cress_ribbon", "reactive reclaim belongs to the trap's owner and cannot recycle itself")
	valid(battle, "spell counter recovery")

func test_deferred_cross() -> void:
	var battle := arena()
	var side_arm: Dictionary = troop(battle, "spear", CENTER + Vector2i.RIGHT * 3, 1)
	var diagonal: Dictionary = troop(battle, "spear", CENTER + Vector2i.DOWN + Vector2i.RIGHT, 1)
	var ally: Dictionary = troop(battle, "spear", CENTER + Vector2i.UP, 0)
	var action: Dictionary = give_action(battle, "sunken_weir_breach", CENTER)
	var forecast: Dictionary = Effects.predict(battle, action)
	check(forecast.cells.size() == 13 and forecast.changes.is_empty() and not forecast.cells.has(diagonal.pos), "ten-cost order publicly previews the cross without instant damage")
	check(battle.apply_action(action).ok and battle.Orders.footprint(battle, battle.pending_orders[0]) == forecast.cells, "public board uses the same cross as the cursor")
	battle.end_turn()
	check(battle.Orders.incoming(battle, side_arm) == 7 and battle.Orders.incoming(battle, diagonal) == 0, "opposing AI sees cross risk but considers the diagonal safe")
	check(side_arm.hp == side_arm.max_hp, "opponent has a complete response turn")
	var restored: Dictionary = Snapshot.restore(JSON.parse_string(JSON.stringify(Snapshot.capture(battle), "", true, true)))
	check(restored.ok, "pending cross can be reloaded before resolution")
	if not restored.ok: return
	battle.end_turn()
	restored.battle.end_turn()
	check(Snapshot.capture(battle) == Snapshot.capture(restored.battle), "cross resolves identically after reload")
	check(battle.get_unit(side_arm.id).is_empty() and diagonal.hp == diagonal.max_hp and ally.hp == ally.max_hp, "only enemies actually in the cross are damaged")
	check(battle.pending_orders.is_empty() and battle.last_order_event.cells == forecast.cells, "spell resolves once and animates the actual field")
	valid(battle, "resolved ten-cost cross")

func test_v048_compatibility() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v047-court-encounter.json"))
	var raw: Dictionary = source.encounter.battle
	var restored: Dictionary = Snapshot.restore(raw)
	check(raw.version == 9 and raw.rules == Snapshot.v048_rules_signature() and restored.ok, "original v9 save migrates with exact old catalog signature")
	if not restored.ok: return
	var updated: Dictionary = JSON.parse_string(JSON.stringify(Snapshot.capture(restored.battle), "", true, true))
	for key: String in ["units", "players", "turn", "pending_orders", "time_remaining", "objective", "rng_state"]:
		check(raw[key] == updated[key], "old active battle preserves " + key)

func run() -> void:
	test_catalog()
	test_line_cast_and_ai()
	test_terrain_and_deployment()
	test_reclaim()
	test_new_traps()
	test_deferred_cross()
	test_v048_compatibility()
	print("MOORINGS RULES: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
