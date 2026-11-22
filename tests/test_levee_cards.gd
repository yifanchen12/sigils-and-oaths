extends "res://tests/test_expansion_cards.gd"

const Art = preload("res://scripts/art_library.gd")
const Tactical = preload("res://scripts/tactical_ai.gd")
const NO_TARGET := Vector2i(-1, -1)

func test_catalog() -> void:
	var mana_curve: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var first: Dictionary = Model.DECKS.find("weir_breakers").cards
	var second: Dictionary = Model.DECKS.find("levee_relief").cards
	var counts: Dictionary = {}
	for card: Dictionary in Model.CATALOG.cards:
		if card.get("set_id", "") != "levee": continue
		mana_curve[int(card.cost) - 1] += 1
		counts[card.type] = int(counts.get(card.type, 0)) + 1
		var texture: AtlasTexture = Art.get_texture(card.id) as AtlasTexture
		check(texture != null and texture.region.size.x > 300 and texture.region.size.y > 300, "distinct atlas panel " + card.id)
		check(first.has(card.id) or second.has(card.id), "included in a normal preset: " + card.id)
	check(mana_curve == [1, 2, 2, 2, 2, 3, 2, 1, 1, 2], "all ten costs with nine cards at six and above")
	check(counts == {"unit": 8, "spell": 5, "environment": 3, "trap": 2}, "four playable card types")
	check(Model.DECKS.validate_counts(first, Model.CATALOG.cards).is_empty(), "attack preset is a legal 30-card deck")
	check(Model.DECKS.validate_counts(second, Model.CATALOG.cards).is_empty(), "relief preset is a legal 30-card deck")

func reserve(battle: Battle, card_id: String, side: int = 0) -> Dictionary:
	var card: Dictionary = {"card_id": card_id, "uid": battle._id()}
	battle.players[side].deck.append(card)
	battle.players[side].card_total += 1
	return card

func test_targeted_supply() -> void:
	var battle := arena()
	var older: Dictionary = reserve(battle, "lamp_patrol")
	var trap: Dictionary = reserve(battle, "severed_pullcord")
	var recruit: Dictionary = reserve(battle, "reed_watch")
	var expensive: Dictionary = reserve(battle, "dawn_weir")
	var deck: Array = battle.players[0].deck
	var previous: Array = deck.duplicate()
	var rng_state: int = battle.rng.state
	check(play(battle, "troop_receipt", NO_TARGET).ok, "supply played from hand as a global card")
	check(battle.players[0].hand == [recruit, trap], "finds the first qualifying card for each requested group")
	previous.erase(recruit)
	previous.erase(trap)
	check(deck == previous and deck.has(older) and deck.back() == expensive and battle.rng.state == rng_state, "complement stays in the original order without advancing RNG")
	check(play(battle, "chalk_route", NO_TARGET).ok and battle.players[0].hand.back() == older, "one-cost spell finds the next low-cost unit")
	while battle.players[0].hand.size() < Model.HAND_LIMIT - 1:
		battle.add_generated_card(0, "heal")
	recruit = reserve(battle, "lamp_patrol")
	trap = reserve(battle, "reed_toll")
	check(play(battle, "troop_receipt", NO_TARGET).ok and battle.players[0].hand.back() == recruit, "resolves the first instruction into the only free hand slot")
	check(deck.back() == trap and battle.players[0].fatigue == 0, "uncollected supply stays in its original deck slot")
	valid(battle, "typed draws at the hand cap")
	battle = arena()
	battle.players[0].discard.append_array(battle.players[0].deck)
	battle.players[0].deck.clear()
	battle.add_generated_card(0, "chalk_route")
	var before: Dictionary = Snapshot.capture(battle)
	var action: Dictionary = {"type": "play", "card_uid": battle.players[0].hand.back().uid, "target": NO_TARGET}
	check(not battle.apply_action(action).ok and Snapshot.capture(battle) == before, "search with no match does not pay, discard or cause fatigue")

func test_deployment_and_departure() -> void:
	var battle := arena()
	var site := Vector2i(3, 3)
	battle.terrain[site] = "road"
	var large_spell: Dictionary = reserve(battle, "dawn_weir")
	check(play(battle, "rain_saddle", site).ok, "roadside cavalry legally deploys")
	var cavalry: Dictionary = battle.unit_at(site)
	check(battle.players[0].hand == [large_spell] and battle.can_vanguard_move(cavalry), "road entry fetches the right spell and unlocks a move")
	check(battle.attack_targets(cavalry).is_empty() and battle.skill_targets(cavalry).is_empty(), "entry does not grant an instant strike")
	battle = arena()
	check(play(battle, "rain_saddle", site).ok and not battle.can_vanguard_move(battle.unit_at(site)) and battle.players[0].hand.is_empty(), "same unit on a plain has no terrain entry")
	battle = arena()
	battle.terrain[site] = "hill"
	check(play(battle, "lamp_patrol", site).ok and battle.unit_at(site).shield == 2, "hill patrol gets two starting shields")
	battle = arena()
	var clerk: Dictionary = troop(battle, "slate_quartermaster", site, 0)
	var mage: Dictionary = troop(battle, "mage", Vector2i(4, 3), 1)
	large_spell = reserve(battle, "floodline_warning")
	battle.end_turn()
	check(play(battle, "bolt", clerk.pos).ok and battle.get_unit(clerk.id).is_empty(), "actual enemy spell takes out the quartermaster")
	check(battle.players[0].hand == [large_spell] and battle.players[1].hand.size() == 1 and mage.hp > 0, "fall reward goes to the casualty's side")
	valid(battle, "terrain entry and typed fall")

func test_scheduled_fields() -> void:
	var battle := arena()
	var center := Vector2i(4, 3)
	var retreating: Dictionary = troop(battle, "cavalry", Vector2i(5, 3), 1)
	var staying: Dictionary = troop(battle, "spear", Vector2i(4, 2), 1)
	var ally: Dictionary = troop(battle, "sword", Vector2i(3, 3), 0)
	battle.add_generated_card(0, "floodline_warning")
	var action: Dictionary = {"type": "play", "card_uid": battle.players[0].hand.back().uid, "target": center}
	var projection: Dictionary = Effects.predict(battle, action)
	check(projection.get("cells", []).size() == 5 and projection.changes.is_empty() and projection.note.contains("第 3 回合"), "preview marks deferred footprint and never projects an immediate hit")
	var before: Dictionary = Snapshot.capture(battle)
	var outside: Dictionary = action.duplicate()
	outside.target = Vector2i(11, 9)
	check(not battle.apply_action(outside).ok and Snapshot.capture(battle) == before, "far order is illegal and atomic")
	var discard_size: int = battle.players[0].discard.size()
	check(battle.apply_action(action).ok and battle.pending_orders.size() == 1 and battle.players[0].discard.size() == discard_size, "paid order enters a public zone without damage")
	check(battle.last_order_event.is_empty() and retreating.hp == retreating.max_hp and staying.hp == staying.max_hp and battle.pending_orders[0].due_turn == 3, "placement gives the other side a full response turn")
	battle.add_generated_card(0, "stretcher_signal")
	before = Snapshot.capture(battle)
	check(not battle.apply_action({"type": "play", "card_uid": battle.players[0].hand.back().uid, "target": center}).ok and Snapshot.capture(battle) == before, "second order is rejected without paying")
	battle.end_turn()
	var risk: Dictionary = Tactical.prepare(battle)
	var move_out: Dictionary = {"type": "move", "unit_id": retreating.id, "target": Vector2i(6, 3)}
	check(Tactical.value(battle, move_out, risk) > 0.0, "public order increases AI value for leaving the blast")
	check(battle.apply_action(move_out).ok and retreating.hp == retreating.max_hp, "opponent takes legal action before the field fires")
	check(play(battle, "stretcher_signal", center).ok and battle.pending_orders.size() == 2, "opponent may set its own order at the same public center")
	valid(battle, "two opposing pending fields")
	var raw: Dictionary = Snapshot.capture(battle)
	raw.pending_orders[0].due_turn += 1
	check(not Snapshot.validate(raw).ok, "forged deadline rejected")
	raw = Snapshot.capture(battle)
	raw.players[0].discard.append(raw.pending_orders[0].card)
	check(not Snapshot.validate(raw).ok, "pending duplicate instance rejected")
	var resumed: Dictionary = Snapshot.restore(JSON.parse_string(JSON.stringify(Snapshot.capture(battle))))
	check(resumed.ok, "reload before detonation")
	if not resumed.ok: return
	battle.end_turn()
	resumed.battle.end_turn()
	check(Snapshot.capture(battle) == Snapshot.capture(resumed.battle), "reloaded round resolves identically")
	check(staying.hp == staying.max_hp - 4 and staying.rooted_turns == 2 and ally.hp == ally.max_hp and retreating.hp == retreating.max_hp, "current enemy positions, friendly fire immunity and root apply")
	check(battle.pending_orders.size() == 1 and battle.players[0].discard.back().uid == action.card_uid and battle.last_order_event.pos == center, "only the due order is discarded and animated")
	check(battle.last_order_event.result == "命中 1 支敌军" and battle.log_lines.any(func(line: String) -> bool: return line.contains("命中 1 支敌军")), "one enemy remaining in the footprint is reported in the saved battle log")
	battle.end_turn()
	check(battle.pending_orders.is_empty() and staying.hp == staying.max_hp and staying.shield == 2 and staying.rooted_turns == 1, "red order fires and heals its current allies")
	valid(battle, "both orders consumed")
	var open_field := arena()
	check(play(open_field, "floodline_warning", open_field.commander(0).pos).ok, "an empty attack footprint can be marked")
	open_field.end_turn()
	open_field.end_turn()
	var saved: Dictionary = Snapshot.restore(Snapshot.capture(open_field))
	check(saved.ok and open_field.last_order_event.result == "命中 0 支敌军" and saved.battle.log_lines.any(func(line: String) -> bool: return line.contains("命中 0 支敌军")), "an order with no enemy at impact remains a visible miss after saving and loading")

func test_lethal_timing() -> void:
	var battle := arena()
	var leader: Dictionary = battle.commander(1)
	leader.pos = Vector2i(4, 3)
	leader.hp = 3
	check(play(battle, "dawn_weir", leader.pos).ok, "ten-cost order is legal in range")
	battle.end_turn()
	check(battle.winner == -1 and leader.hp == 3, "marked commander lives through placement and entire next turn")
	var remaining: int = battle.players[0].deck.size()
	check(battle.advance_clock(battle.time_remaining) and battle.winner == 0 and battle.players[0].deck.size() == remaining, "lethal order resolves on timeout before drawing")
	valid(battle, "commander fell during scheduled start")

func test_trap_and_kill_supply() -> void:
	var battle := arena()
	var rider: Dictionary = troop(battle, "cavalry", Vector2i(6, 3), 1)
	check(play(battle, "severed_pullcord", Vector2i(4, 3)).ok, "disarm laid from hand onto empty ground")
	battle.end_turn()
	var destination := Vector2i(3, 3)
	check(battle.apply_action({"type": "move", "unit_id": rider.id, "target": destination}).ok and rider.pos == destination and rider.hp == 4, "surviving enemy finishes the path")
	check(rider.attacked and rider.rooted_turns == 0 and battle.attack_targets(rider).is_empty(), "movement left intact, attack opportunity spent")
	battle = arena()
	var target: Dictionary = troop(battle, "archer", Vector2i(4, 3), 1)
	var supply: Dictionary = reserve(battle, "rising_oath_watch")
	battle.end_turn()
	var red_supply: Dictionary = reserve(battle, "lamp_patrol", 1)
	check(play(battle, "reed_toll", target.pos).ok and battle.visible_traps(0).is_empty(), "hidden spell-capable ward placed by defender")
	reserve(battle, "heal")
	battle.end_turn()
	check(play(battle, "recommission_crew", target.pos).ok and target.hp == 2 and battle.players[0].deck.has(supply), "spell ward prevents a kill and thus the attacker's refill")
	check(battle.players[1].hand.has(red_supply), "the reactive defender draws its own low-cost reserve")
	battle.players[0].mana = 7
	check(play(battle, "recommission_crew", target.pos).ok and battle.get_unit(target.id).is_empty() and battle.players[0].hand.has(supply), "only actual kill draws an eligible high-cost unit")
	valid(battle, "guard interaction and commission")

func test_legacy_escort() -> void:
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v046-escort.json"))
	var old: Dictionary = Snapshot.restore(stored)
	check(stored.version == 8 and old.ok, "original v0.46 export restores under the expanded card catalog")
	if not old.ok: return
	var updated: Dictionary = Snapshot.capture(old.battle)
	check(updated.version == Snapshot.VERSION and updated.pending_orders.is_empty(), "legacy backfill starts without any pending order")
	updated = JSON.parse_string(JSON.stringify(updated, "", true, true))
	updated = preload("res://tests/fixtures/saved_battle.gd").legacy_labels(updated)
	for key: String in ["players", "units", "objective", "terrain", "rng_seed", "rng_state", "active_side", "time_remaining"]:
		check(updated[key] == stored[key], "restoration preserves " + key)

func run() -> void:
	test_catalog()
	test_targeted_supply()
	test_deployment_and_departure()
	test_scheduled_fields()
	test_lethal_timing()
	test_trap_and_kill_supply()
	test_legacy_escort()
	print("LEVEE RULES: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
