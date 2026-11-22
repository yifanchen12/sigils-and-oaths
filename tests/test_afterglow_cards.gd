extends "res://tests/test_expansion_cards.gd"

const Art = preload("res://scripts/art_library.gd")
const Threats = preload("res://scripts/tactical_ai.gd")
const NO_TARGET := Vector2i(-1, -1)
const PRESETS: Array[String] = ["relay_watch", "hearth_compact"]

func action_for(b: Battle, card_id: String, target: Vector2i) -> Dictionary:
	check(b.add_generated_card(b.active_side, card_id), "give " + card_id)
	return {"type": "play", "card_uid": b.players[b.active_side].hand.back().uid, "target": target}

func test_catalog() -> bool:
	var costs: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var types: Dictionary = {"unit": 0, "spell": 0, "trap": 0, "environment": 0}
	for card: Dictionary in Model.CATALOG.cards:
		if card.get("set_id", "") != "afterglow": continue
		costs[card.cost] += 1
		types[card.type] += 1
		var art: Texture2D = Art.get_texture(card.id)
		check(art != null and art.get_width() >= 300 and art.get_height() >= 300, "unique atlas cell for " + card.id)
		check(PRESETS.any(func(id: String) -> bool: return Model.DECKS.find(id).cards.has(card.id)), "available in a preset: " + card.id)
	check(types == {"unit": 12, "spell": 10, "trap": 4, "environment": 2}, "all four types")
	check(costs == [0, 3, 4, 4, 3, 3, 3, 2, 2, 2, 2], "at least two choices at every cost")
	for deck: Dictionary in Model.DECKS.decks:
		check(Model.DECKS.validate_counts(deck.cards, Model.CATALOG.cards).is_empty(), "legal preset " + deck.id)
	var counts: Dictionary = Model.DECKS.find(PRESETS[0]).cards
	var b := Model.new(431, "rivergate", "warden", "warden", "custom", PRESETS[1], 90.0, {"cards": counts})
	check(b.deck(0).id == "custom" and b.deck(0).cards == counts and b.deck(1).id == PRESETS[1], "custom and new preset through the regular battle constructor")
	valid(b, "full new preset and custom deck")
	return true

func test_recall_and_fall() -> bool:
	var b := arena()
	var pos := Vector2i(3, 3)
	check(play(b, "lantern_bearer", pos).ok, "normal deployment from hand")
	var unit: Dictionary = b.unit_at(pos)
	unit.hp = 1
	unit.rooted_turns = 1
	var card_uid: int = unit.card.uid
	var old_id: int = unit.id
	check(play(b, "oath_ward", pos).ok, "place a reaction on the returning unit")
	var action: Dictionary = action_for(b, "recall_writ", pos)
	while b.players[0].hand.size() < Battle.HAND_LIMIT: b.add_generated_card(0, "ward")
	var deck_size: int = b.players[0].deck.size()
	check(Effects.predict(b, action).note.contains("返回手牌"), "preview distinguishes recall from death")
	check(not b.card_targets(action.card_uid, 0).has(b.commander(0).pos), "commander cannot be recalled")
	check(b.apply_action(action).ok and b.get_unit(old_id).is_empty(), "recall pays normally and frees a tile")
	check(not b.hand_card(0, card_uid).has("unit_id") and b.players[0].hand.size() == Battle.HAND_LIMIT, "same card UID returns after the spent spell frees the eighth slot")
	check(b.traps.is_empty() and b.last_trap_events.back().reason.contains("失效") and b.players[0].deck.size() == deck_size, "attached trap is removed and death draw does not fire")
	check(b.apply_action({"type": "play", "card_uid": card_uid, "target": pos}).ok, "replay the exact returned instance")
	var replayed: Dictionary = b.unit_at(pos)
	check(replayed.id != old_id and replayed.hp == replayed.max_hp and replayed.rooted_turns == 0 and replayed.summoning, "replay pays printed cost and enters as a fresh unit")
	valid(b, "recalled and replayed unit")

	b = arena()
	var a: Dictionary = troop(b, "ash_notary", Vector2i(4, 3), 0)
	a.hp = 2
	var c: Dictionary = troop(b, "lantern_bearer", Vector2i(5, 3), 0)
	c.hp = 1
	var survivor: Dictionary = troop(b, "spear", Vector2i(4, 2), 0)
	survivor.hp = 5
	troop(b, "mage", Vector2i(7, 3), 1)
	deck_size = b.players[0].deck.size()
	b.end_turn()
	check(play(b, "nova", a.pos).ok, "an enemy spell can trigger both casualties at once")
	check(b.get_unit(a.id).is_empty() and b.get_unit(c.id).is_empty() and survivor.hp == 3, "fall support cannot restore simultaneous casualties")
	check(b.players[0].deck.size() == deck_size - 2 and b.players[0].hand.size() == 2, "both fall draws go to their owner during enemy turn")
	valid(b, "simultaneous fall effects")
	return true

func test_traps_and_verdict() -> bool:
	var b := arena()
	var runner: Dictionary = troop(b, "cavalry", Vector2i(6, 3), 1)
	check(play(b, "drawwire", Vector2i(4, 3)).ok and b.visible_traps(1).is_empty(), "mana trap is hidden and played from hand")
	b.end_turn()
	b.players[1].mana = 1
	check(b.apply_action({"type": "move", "unit_id": runner.id, "target": Vector2i(3, 3)}).ok, "normal path crosses wire")
	check(b.players[1].mana == 0 and runner.pos == Vector2i(3, 3) and runner.hp == runner.max_hp and runner.rooted_turns == 0, "mana drain clamps at zero without stopping or harming the mover")
	b.end_turn()
	b.end_turn()
	check(b.players[1].mana == 10 and b.traps.is_empty(), "next turn refills and wire is consumed")
	valid(b, "mana trap aftermath")

	b = arena()
	var friend: Dictionary = troop(b, "sword", Vector2i(4, 3), 0)
	friend.hp = 2
	troop(b, "mage", Vector2i(7, 3), 1)
	check(play(b, "quiet_veil", friend.pos).ok, "arm spell-triggered healing")
	b.end_turn()
	var act: Dictionary = action_for(b, "split_sentence", friend.pos)
	var first_deck: int = b.players[1].deck.size()
	var preview: Dictionary = Effects.predict(b, act)
	check(preview.amount == 4 and preview.changes[0].hp_after == 0, "wounded verdict preview assumes no hidden trap")
	check(b.apply_action(act).ok and friend.hp == 1 and b.traps.is_empty(), "ward heals and shields before the four damage")
	check(b.players[1].deck.size() == first_deck, "forecast lethality does not award a draw if ward saves target")
	check(play(b, "split_sentence", friend.pos).ok and b.get_unit(friend.id).is_empty(), "execute unprotected wounded unit")
	check(b.players[1].deck.size() == first_deck - 1, "only the real kill draws one")

	b = arena()
	var armored: Dictionary = troop(b, "breakwater_guard", Vector2i(4, 3), 1)
	armored.shield = 3
	act = action_for(b, "valley_reckoner", armored.pos)
	preview = Effects.predict(b, act)
	check(preview.amount == 7 and preview.changes[0].shield_after == 0 and preview.changes[0].hp_after == 3, "shielded unit has seven damage after public shield removal")
	check(b.apply_action(act).ok and armored.hp == 3 and not b.players[0].spell_boost_used, "neutral verdict does not consume fire boost")
	valid(b, "conditional verdict and trap response")
	return true

func test_terrain_and_ten_mana() -> bool:
	var b := arena()
	var road: Dictionary = troop(b, "cavalry", Vector2i(4, 3), 1)
	var bridge: Dictionary = troop(b, "spear", Vector2i(4, 4), 1)
	var plain: Dictionary = troop(b, "sword", Vector2i(4, 2), 1)
	b.terrain[road.pos] = "road"
	b.terrain[bridge.pos] = "bridge"
	var act: Dictionary = action_for(b, "ford_lock", road.pos)
	var forecast: Dictionary = Effects.predict(b, act)
	check(forecast.changes.size() == 2 and forecast.amount == 0, "ford forecast marks the two valid terrain targets")
	check(b.apply_action(act).ok and road.rooted_turns == 2 and bridge.rooted_turns == 2 and plain.rooted_turns == 0,
		"local root hits roads and bridges and leaves plain units untouched")
	b.end_turn()
	check(b.movement_cells(road).is_empty() and not b.movement_cells(plain).is_empty(), "root blocks movement through the victim turn")
	valid(b, "terrain roots")

	b = arena()
	var ally: Dictionary = troop(b, "sword", Vector2i(4, 3), 0)
	ally.shield = 4
	var foe: Dictionary = troop(b, "spear", Vector2i(5, 3), 1)
	foe.shield = 1
	b.commander(1).pos = Vector2i(6, 3)
	act = action_for(b, "last_bell", foe.pos)
	forecast = Effects.predict(b, act)
	check(forecast.cells.size() == 13 and forecast.changes.size() == 3 and forecast.commander_amount == 1,
		"bell previews three affected units and a thirteen-tile footprint")
	check(b.apply_action(act).ok and b.players[0].mana == 0, "ten-cost card spends the full turn budget")
	check(ally.shield == 5 and foe.hp == 5 and foe.rooted_turns == 2 and b.commander(1).hp == b.commander(1).max_hp - 1,
		"friendly shield, opposing damage and root, commander damage cap all settle once")
	valid(b, "mixed area and ten mana")

	b = arena()
	foe = troop(b, "spear", Vector2i(4, 3), 1)
	act = action_for(b, "copper_gate_requiem", Vector2i(3, 3))
	forecast = Effects.predict(b, act)
	check(forecast.changes.size() == 1 and forecast.changes[0].hp_loss == 4, "offensive entry projected from deployment tile")
	check(b.apply_action(act).ok and foe.hp == 3 and foe.rooted_turns == 2 and b.unit_at(act.target).summoning,
		"ten-cost mage roots and damages on ordinary deployment, then waits")
	valid(b, "offensive entry")
	return true

func test_actions_weather_and_legacy() -> bool:
	var b := arena()
	var marched: Dictionary = troop(b, "cavalry", Vector2i(4, 3), 0)
	marched.moved = true
	var spent: Dictionary = troop(b, "sword", Vector2i(3, 3), 0)
	spent.moved = true; spent.attacked = true; spent.skill_used = true
	check(play(b, "terrace_relay", Vector2i(4, 3)).ok and not marched.moved and not spent.attacked and spent.moved and spent.skill_used,
		"separate refresh paths cannot restore both actions or the unit skill")
	b = arena()
	var nearby: Dictionary = troop(b, "sword", Vector2i(3, 3), 0)
	var remote: Dictionary = troop(b, "sword", Vector2i(5, 3), 0)
	nearby.hp = 1; remote.hp = 1
	check(play(b, "lamplight_shift", NO_TARGET).ok and nearby.hp == 3 and remote.hp == 1 and b.weather_remaining == 4,
		"weather is global while the immediate heal remains near the commander")
	var draw_before: int = b.players[0].deck.size()
	check(play(b, "coast_drizzle", NO_TARGET).ok and b.weather == "rain" and b.players[0].deck.size() == draw_before - 1,
		"new weather replaces existing weather and draws one reserve")
	valid(b, "weather combinations")

	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v042-compat-battle.json"))
	check(raw.rules == Snapshot.pre_afterglow_signature(), "previous signature computed from exact previous rules")
	var loaded: Dictionary = Snapshot.restore(raw)
	check(loaded.ok, "actual 0.42 release snapshot keeps old Frost preset and campaign-only map")
	if loaded.ok:
		var upgraded: Dictionary = Snapshot.capture(loaded.battle)
		var normalized: Dictionary = JSON.parse_string(JSON.stringify(upgraded))
		raw.rules = normalized.rules
		raw.version = normalized.version
		raw.pending_orders = []
		check(raw == preload("res://tests/fixtures/saved_battle.gd").legacy_labels(normalized) and Snapshot.validate(upgraded).ok, "the older save gains an empty order queue and retains every battle field")
	return true

func test_formation_risk() -> bool:
	var b := arena()
	var ally: Dictionary = troop(b, "sword", Vector2i(5, 4), 0)
	troop(b, "mage", Vector2i(7, 4), 1)
	b.players[1].deck_id = "frost_engine"
	b.players[1].deck_definition = Model.DECKS.find("frost_engine").duplicate(true)
	b.players[1].max_mana = 8
	var visible: Array = Threats.prepare(b).formations
	check(visible.any(func(spec: Dictionary) -> bool: return spec.id == "signal_torrent")
		and not visible.any(func(spec: Dictionary) -> bool: return spec.id == "last_hearth"), "area risk uses only affordable cards in a public preset")
	var grouped: float = Threats.FormationRisk.exposure(b, ally, Vector2i(5, 3), visible)
	var separate: float = Threats.FormationRisk.exposure(b, ally, Vector2i(9, 2), visible, ally.pos)
	check(grouped > separate and grouped > 0.0, "separating units reduces shared impact")
	b.players[1].deck_id = "custom"
	b.players[1].discard.clear()
	b.players[1].hand = [{"card_id": "last_hearth", "uid": 991}]
	b.players[1].max_mana = 10
	check(Threats.prepare(b).formations.is_empty(), "a custom opponent's hidden hand is never inspected")
	return true

func run() -> void:
	for method: String in ["test_catalog", "test_recall_and_fall", "test_traps_and_verdict", "test_terrain_and_ten_mana",
		"test_actions_weather_and_legacy", "test_formation_risk"]:
		check(call(method) == true, method + " finished without script errors")
	print("AFTERGLOW CARDS: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
