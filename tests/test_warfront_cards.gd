extends "res://tests/test_expansion_cards.gd"

const Art = preload("res://scripts/art_library.gd")
const PRESETS = ["reed_legion", "frost_engine", "lantern_convoy"]
const NO_TARGET := Vector2i(-1, -1)

func test_catalog() -> void:
	var types: Dictionary = {"unit": 0, "spell": 0, "trap": 0, "environment": 0}
	var costs: Array[int] = []
	for card: Dictionary in Model.CATALOG.cards:
		if card.get("set_id", "") != "warfront": continue
		types[card.type] += 1
		if not costs.has(card.cost): costs.append(card.cost)
		var art: Texture2D = Art.get_texture(card.id)
		check(art != null and art.get_width() >= 300 and art.get_height() >= 300, "original illustration for " + card.id)
	costs.sort()
	check(types == {"unit": 8, "spell": 10, "trap": 3, "environment": 3}, "twenty-four expansion definitions in four card types")
	check(costs == range(1, 11), "every paid cost from one to ten has new choices")
	for id: String in PRESETS:
		var deck: Dictionary = Model.DECKS.find(id)
		check(Model.DECKS.validate_counts(deck.cards, Model.CATALOG.cards).is_empty(), "valid thirty-card preset " + id)
	var counts: Dictionary = Model.DECKS.find("frost_engine").cards
	var custom := Model.new(2951, "rivergate", "warden", "pyromancer", "custom", "lantern_convoy", 90.0, {"cards": counts})
	check(custom.deck(0).id == "custom" and custom.deck(0).cards == counts, "all high-cost variants accepted by the custom deck entry point")
	valid(custom, "custom expansion deck")

func test_entry_effects() -> void:
	var b := arena()
	var start: int = b.players[0].deck.size()
	var first := Vector2i(3, 3)
	check(play(b, "reed_scout", first).ok, "deploy variant from hand beside commander")
	var scout: Dictionary = b.unit_at(first)
	check(scout.kind == "sword" and scout.card.card_id == "reed_scout" and b.players[0].mana == 8 and b.players[0].deck.size() == start - 1, "unit uses its own identity and immediately draws after paying")
	check(b.movement_cells(scout).is_empty() and b.attack_targets(scout).is_empty() and b.skill_targets(scout).is_empty(), "deployment does not bypass sickness")
	check(play(b, "scribe_warden", Vector2i(4, 3)).ok and b.players[0].deck.size() == start - 3, "six-cost mage enters the new front line and draws two")
	check(b.unit_cast_range(b.unit_at(Vector2i(4, 3))) == 4, "variant mage retains class cast range")
	valid(b, "deployed variants, including class and original card ids")

	b = arena()
	var friend: Dictionary = troop(b, "sword", Vector2i(3, 3), 0)
	var enemy: Dictionary = troop(b, "cavalry", Vector2i(4, 3), 1)
	check(play(b, "bronze_watch", Vector2i(3, 4)).ok, "nine-cost lance deployed")
	var guard: Dictionary = b.unit_at(Vector2i(3, 4))
	check(guard.guarding and guard.shield == 3 and guard.summoning and b.players[0].mana == 1, "entry grants three shield and immediate guard with regular sickness")
	b.end_turn()
	check(b.apply_action({"type": "attack", "unit_id": enemy.id, "target": friend.pos}).ok and b.last_combat.defender_id == guard.id and friend.hp == friend.max_hp, "entry guard intercepts an ordinary attack on the adjacent ally")
	b.end_turn()
	check(not guard.guarding and not guard.summoning, "entry guard expires at the next owner turn")
	b.players[0].mana = 10
	check(play(b, "gate_veteran", Vector2i(2, 4)).ok and b.unit_at(Vector2i(2, 4)).shield == 1 and b.unit_at(Vector2i(2, 4)).guarding, "three-cost lance has its smaller entry guard")
	valid(b, "entry guard and intercepted attack")

	b = arena()
	friend = troop(b, "sword", Vector2i(3, 3), 0)
	friend.moved = true
	check(play(b, "ridge_courier", Vector2i(3, 4)).ok and not friend.moved, "mounted courier restores adjacent eligible movement")
	friend.hp = 1
	friend.rooted_turns = 1
	check(play(b, "shore_medic", Vector2i(4, 3)).ok and friend.hp == 4 and friend.rooted_turns == 0, "medic treats and frees its adjacent ally immediately")
	b.players[0].mana = 10
	check(play(b, "breakwater_guard", Vector2i(3, 2)).ok and friend.shield == 2 and b.unit_at(Vector2i(3, 2)).shield == 2 and b.commander(0).shield == 0, "heavy infantry shields its cross including itself and excludes diagonal units")

	b = arena()
	enemy = troop(b, "mage", Vector2i(5, 3), 1)
	b.end_turn()
	check(play(b, "silt_snare", Vector2i(4, 3)).ok and play(b, "tidal_oath", enemy.pos).ok, "enemy has separate ground and unit traps")
	b.end_turn()
	check(play(b, "ridge_archer", first).ok and b.traps.size() == 1 and b.traps[0].unit_id == enemy.id, "recon removes adjacent ground trap and leaves distant unit trap intact")
	check(b.players[1].discard.back().card_id == "silt_snare" and b.last_trap_events.size() == 1, "recon discards without firing trap draw")
	valid(b, "after reconnaissance deployment")

func test_volley() -> void:
	var b := arena()
	var center := Vector2i(6, 3)
	var target: Dictionary = troop(b, "bronze_watch", center, 1)
	var edge: Dictionary = troop(b, "breakwater_guard", Vector2i(7, 4), 1)
	var outside: Dictionary = troop(b, "breakwater_guard", Vector2i(9, 3), 1)
	var friend: Dictionary = troop(b, "sword", Vector2i(5, 3), 0)
	var caster: Dictionary = troop(b, "mage", Vector2i(6, 7), 0)
	var hand: Dictionary
	check(b.add_generated_card(0, "last_hearth"), "ten-cost card in hand")
	hand = b.players[0].hand.back()
	var action: Dictionary = {"type": "play", "card_uid": hand.uid, "target": center}
	friend.pos = Vector2i(4, 1)
	check(b.card_targets(hand.uid, 0).has(center), "mage reaches a center four cells away")
	caster.kind = "sword"
	check(not b.card_targets(hand.uid, 0).has(center), "ordinary troops cannot reach that center at four cells")
	caster.kind = "mage"
	friend.pos = Vector2i(5, 3)
	b.players[0].mana = 9
	var before: Dictionary = Snapshot.capture(b)
	check(Effects.predict(b, action).is_empty() and not b.apply_action(action).ok and before == Snapshot.capture(b), "nine mana cannot spend ten or mutate the board")
	b.players[0].mana = 10
	b.weather = "sun"
	b.weather_remaining = 3
	target.shield = 2
	var commander: Dictionary = b.commander(1)
	commander.pos = Vector2i(8, 3)
	var forecast: Dictionary = Effects.predict(b, action)
	check(forecast.get("amount") == 7 and forecast.get("commander_amount") == 4 and forecast.get("changes", []).size() == 3 and forecast.get("cells", []).size() == 13, "sun empowers both kinds of damage in the radius-two forecast")
	check(b.apply_action(action).ok and b.players[0].mana == 0, "ten-cost card consumes a full turn's mana")
	check(target.hp == 6 and target.shield == 0 and edge.hp == 3 and outside.hp == outside.max_hp and friend.hp == friend.max_hp, "damage and shields match the forecast, leaving friendly units and range-three enemy untouched")
	check(commander.hp == commander.max_hp - 4, "commander takes its separately forecast and weather-adjusted damage")
	check(b.players[0].discard.back().card_id == "last_hearth", "ten-cost spell moves to discard")
	valid(b, "after ten-cost area spell")

	b = arena()
	target = troop(b, "breakwater_guard", Vector2i(4, 3), 1)
	edge = troop(b, "breakwater_guard", Vector2i(4, 5), 1)
	commander = b.commander(1)
	commander.pos = Vector2i(6, 3)
	check(play(b, "signal_torrent", target.pos).ok and b.players[0].mana == 2 and target.hp == 6 and edge.hp == 6 and commander.hp == commander.max_hp - 2, "eight-cost shock hits the radius-two edge, with reduced commander damage")
	b.players[0].mana = 10
	check(play(b, "mist_spike", target.pos).ok and target.hp == 4 and target.rooted_turns == 2 and edge.rooted_turns == 0, "four-cost cross roots only its own footprint")
	b.end_turn()
	check(target.rooted_turns == 1 and b.movement_cells(target).is_empty(), "mist root survives into the affected side's next turn")
	b.end_turn()
	b.end_turn()
	check(target.rooted_turns == 0 and not b.movement_cells(target).is_empty(), "end of root restores legal movement")
	valid(b, "expiring formation root")

	b = arena()
	target = troop(b, "breakwater_guard", Vector2i(4, 3), 1)
	b.weather = "rain"
	b.weather_remaining = 3
	check(play(b, "kiln_lance", target.pos).ok and target.hp == 4 and b.players[0].mana == 5, "rain reduces five-cost single-target fire by one")
	var deck_before: int = b.players[0].deck.size()
	check(play(b, "dispatch_bundle", NO_TARGET).ok and b.players[0].deck.size() == deck_before - 3 and b.players[0].mana == 2, "three-cost supply draws three from the deck and pays from hand")

func test_support() -> void:
	var b := arena()
	var unit: Dictionary = troop(b, "sword", Vector2i(3, 3), 0)
	var enemy: Dictionary = troop(b, "breakwater_guard", Vector2i(4, 3), 1)
	unit.shield = 4
	unit.hp = 1
	unit.rooted_turns = 1
	unit.moved = true
	check(play(b, "field_signals", unit.pos).ok and unit.shield == 5 and b.commander(0).shield == 1 and enemy.shield == 0, "one-cost signal shields its local friendly cross")
	check(play(b, "detach_line", unit.pos).ok and unit.rooted_turns == 0 and not unit.moved and not unit.attacked, "unbinding resolves before restored movement")
	check(play(b, "warder_hymn", unit.pos).ok and unit.hp == 4 and unit.shield == 5 and b.commander(0).shield == 3, "six-cost song caps healing and shield per target")

	b = arena()
	unit = troop(b, "sword", Vector2i(3, 3), 0)
	enemy = troop(b, "bronze_watch", Vector2i(4, 3), 1)
	var fresh: Dictionary = troop(b, "cavalry", Vector2i(3, 4), 0)
	fresh.summoning = true
	fresh.attacked = true
	fresh.moved = true
	b.commander(0).attacked = true
	unit.skill_used = true
	unit.hp = 5
	unit.shield = 5
	check(b.apply_action({"type": "attack", "unit_id": unit.id, "target": enemy.pos}).ok, "ordinary attack consumes movement and attack")
	check(play(b, "second_watch", unit.pos).ok and not unit.attacked and unit.moved and unit.skill_used, "seven-cost re-attack keeps consumed movement and skill")
	check(fresh.attacked and b.commander(0).attacked and b.attack_targets(unit).has(enemy.pos), "re-attack never refreshes commanders or fresh units")
	check(b.apply_action({"type": "attack", "unit_id": unit.id, "target": enemy.pos}).ok and unit.attacked, "refreshed attack is accepted exactly once")
	valid(b, "extra attack and action tags")

func test_new_traps() -> void:
	var b := arena()
	var enemy: Dictionary = troop(b, "cavalry", Vector2i(6, 3), 1)
	var owner_draw: int = b.players[0].deck.size()
	check(play(b, "silt_snare", Vector2i(4, 3)).ok and b.visible_traps(1).is_empty(), "two-cost snare is hidden, not a board action")
	b.end_turn()
	var mover_draw: int = b.players[1].deck.size()
	check(b.apply_action({"type": "move", "unit_id": enemy.id, "target": Vector2i(3, 3)}).ok and enemy.pos == Vector2i(4, 3), "snare cuts a legal multi-cell move short")
	check(enemy.hp == enemy.max_hp and enemy.rooted_turns == 1 and b.players[0].deck.size() == owner_draw - 1 and b.players[1].deck.size() == mover_draw, "silt snare draws for its owner and deals zero damage")
	check(b.traps.is_empty() and b.players[0].discard.back().card_id == "silt_snare", "trigger consumes the snare")

	b = arena()
	var friend: Dictionary = troop(b, "breakwater_guard", Vector2i(4, 3), 0)
	enemy = troop(b, "sword", Vector2i(5, 3), 1)
	owner_draw = b.players[0].deck.size()
	check(play(b, "fallback_horn", friend.pos).ok, "arm normal attack trap from hand")
	b.end_turn()
	var ordinary_damage: int = b.damage_preview(enemy, friend)
	check(b.apply_action({"type": "attack", "unit_id": enemy.id, "target": friend.pos}).ok and ordinary_damage == 2 and friend.hp == friend.max_hp and friend.shield == 0, "horn absorbs two damage before the ordinary hit")
	check(b.players[0].deck.size() == owner_draw - 2 and b.traps.is_empty(), "horn draws two and consumes itself")

	b = arena()
	friend = troop(b, "bronze_watch", Vector2i(4, 3), 0)
	var unwarded: Dictionary = troop(b, "breakwater_guard", Vector2i(4, 4), 0)
	enemy = troop(b, "mage", Vector2i(5, 3), 1)
	friend.shield = 4
	unwarded.shield = 5
	owner_draw = b.players[0].deck.size()
	check(play(b, "tidal_oath", friend.pos).ok, "arm heavy spell ward from hand")
	valid(b, "pending heavy spell ward on a variant")
	b.end_turn()
	check(play(b, "hammer_sweep", friend.pos).ok, "six-cost sweep casts through the nearby mage")
	check(friend.hp == friend.max_hp and friend.shield == 2 and unwarded.hp == 7 and unwarded.shield == 0, "sweep strips old shields before individually triggering the hidden ward")
	check(b.players[0].deck.size() == owner_draw - 1 and b.traps.is_empty(), "heavy ward draws only one for its owner")
	valid(b, "sweep and consumed heavy spell ward")

func test_new_environment() -> void:
	var b := arena()
	var friend: Dictionary = troop(b, "sword", Vector2i(3, 3), 0)
	var foe: Dictionary = troop(b, "cavalry", Vector2i(5, 3), 1)
	check(play(b, "open_wind", NO_TARGET).ok and b.weather == "tailwind" and b.weather_remaining == 4, "wind is global independent of cast range")
	check(b.movement_allowance(friend) == friend.move + 1 and b.movement_allowance(foe) == foe.move + 1 and b.movement_allowance(b.commander(0)) == b.commander(0).move, "both sides' troops receive the bonus")
	for turn_index: int in range(4): b.end_turn()
	check(b.weather == "clear" and b.movement_allowance(foe) == foe.move, "wind expires after four side turns")
	check(play(b, "night_muster", NO_TARGET).ok and b.weather_remaining == 6, "lantern weather persists for six side turns")
	check(play(b, "gate_veteran", Vector2i(3, 4)).ok and b.unit_at(Vector2i(3, 4)).shield == 2 and friend.shield == 0, "weather and entry shield stack on the new unit only")
	b.end_turn()
	check(play(b, "sword", Vector2i(5, 4)).ok and b.unit_at(Vector2i(5, 4)).shield == 1, "enemy deployment shares global weather benefit")
	valid(b, "new weather and both sides' deployments")

	b = arena()
	var center := Vector2i(4, 3)
	b.terrain[Vector2i(4, 2)] = "water"
	b.terrain[Vector2i(4, 4)] = "bridge"
	check(play(b, "reed_roads", center).ok and b.players[0].mana == 5, "roadwork is paid from hand using a local center")
	check(b.ground(center) == "road" and b.ground(Vector2i(3, 3)) == "road" and b.ground(Vector2i(5, 3)) == "road", "three viable cells become road")
	check(b.ground(Vector2i(4, 2)) == "water" and b.ground(Vector2i(4, 4)) == "bridge" and b.ground(Vector2i(5, 4)) == "plain", "water, existing bridge and diagonal terrain preserved")
	valid(b, "changed road terrain")

func run() -> void:
	test_catalog()
	test_entry_effects()
	test_volley()
	test_support()
	test_new_traps()
	test_new_environment()
	print("WARFRONT CARDS: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
