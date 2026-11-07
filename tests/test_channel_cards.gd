extends "res://tests/test_expansion_cards.gd"
## New hand cards: local bridge construction and a unit-anchored spell ward.

func test_bridge() -> void:
	var b := arena()
	b.terrain[Vector2i(3, 3)] = "water"
	b.terrain[Vector2i(4, 3)] = "water"
	var scout: Dictionary = troop(b, "sword", Vector2i(3, 4), 0)
	check(b.add_generated_card(0, "span_kit"), "bridge kit enters hand as an original card")
	var uid: int = b.players[0].hand.back().uid
	var before: Dictionary = Snapshot.capture(b)
	check(not b.apply_action({"type": "play", "card_uid": uid, "target": Vector2i(6, 3)}).ok and Snapshot.capture(b) == before, "isolated river cell rejects bridge without spending resources")
	check(not b.apply_action({"type": "play", "card_uid": uid, "target": Vector2i(3, 4)}).ok and Snapshot.capture(b) == before, "existing land rejects bridge without spending resources")
	check(b.apply_action({"type": "play", "card_uid": uid, "target": Vector2i(3, 3)}).ok and b.ground(Vector2i(3, 3)) == "bridge", "first span connects to shore within local cast range")
	check(b.players[0].mana == 7 and b.players[0].discard.back().card_id == "span_kit", "bridge is paid from hand and moved to discard")
	check(play(b, "span_kit", Vector2i(4, 3)).ok and b.ground(Vector2i(4, 3)) == "bridge", "second span can extend from the first")
	check(b.movement_cells(scout).has(Vector2i(3, 3)), "troops can enter a newly built bridge")
	check(b.apply_action({"type": "move", "unit_id": scout.id, "target": Vector2i(3, 3)}).ok, "new bridge is used by ordinary movement")
	valid(b, "two connected bridges")

func test_spell_ward() -> void:
	var b := arena()
	var ally: Dictionary = troop(b, "mage", Vector2i(4, 3), 0)
	var foe: Dictionary = troop(b, "mage", Vector2i(5, 3), 1)
	check(play(b, "countercurrent_ward", ally.pos).ok, "spell ward is placed from hand on friendly unit")
	check(b.traps.size() == 1 and b.players[0].mana == 8 and b.visible_traps(1).is_empty(), "spell ward occupies hidden trap zone and pays mana")
	valid(b, "armed spell ward")
	b.end_turn()
	check(b.apply_action({"type": "unit_skill", "unit_id": foe.id, "target": ally.pos}).ok, "enemy mage can cast on warded ally")
	check(ally.hp == ally.max_hp and b.traps.is_empty() and b.players[0].discard.back().card_id == "countercurrent_ward", "first enemy damage skill consumes ward and shields the hit")
	valid(b, "spell ward triggered by mage")

	b = arena(); ally = troop(b, "mage", Vector2i(4, 3), 0); foe = troop(b, "sword", Vector2i(5, 3), 1)
	check(play(b, "countercurrent_ward", ally.pos).ok, "place ward before normal attack")
	b.end_turn()
	check(b.apply_action({"type": "attack", "unit_id": foe.id, "target": ally.pos}).ok and b.traps.size() == 1, "normal attack cannot consume spell ward")
	valid(b, "ward persists after ordinary attack")

	b = arena(); ally = troop(b, "mage", Vector2i(4, 3), 0); foe = troop(b, "mage", Vector2i(5, 3), 1)
	ally.shield = 5
	check(play(b, "countercurrent_ward", ally.pos).ok, "place spell ward before shield-shattering spell")
	b.end_turn(); b.players[1].mana = 10
	check(play(b, "shatter_bolt", ally.pos).ok and ally.hp == ally.max_hp and b.traps.is_empty(), "shatter removes old shield, then ward absorbs damage")
	valid(b, "ward and shatter order")

func test_old_save() -> void:
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v037-compat-battle.json"))
	check(prior.rules == Snapshot.pre_v038_signature(), "0.37 battle signature is reconstructed exactly")
	var restored: Dictionary = Snapshot.restore(prior)
	check(restored.ok and Snapshot.capture(restored.battle).map_id == "northbank", "0.37 battle continues under additive 0.38 cards and deck")
	if restored.ok: valid(restored.battle, "restored 0.37 battle")
	var forged: Dictionary = Snapshot.capture(Model.new(14031, "spillway"))
	forged.rules = Snapshot.pre_towergate_signature()
	check(not Snapshot.validate(forged).ok, "new spillway cannot claim pre-gate rules")
	forged.rules = Snapshot.pre_northbank_signature()
	check(not Snapshot.validate(forged).ok, "new spillway cannot claim pre-depot rules")
	forged.rules = Snapshot.pre_v038_signature()
	check(not Snapshot.validate(forged).ok, "new spillway cannot claim version 0.37 rules")

func run() -> void:
	check(not Model.CATALOG.find("span_kit").is_empty() and not Model.CATALOG.find("countercurrent_ward").is_empty(), "two original hand cards are registered")
	if failures > 0: quit(1); return
	check(Model.DECKS.validate_counts(Model.DECKS.find("channel").cards, Model.CATALOG.cards).is_empty(), "new channel deck has thirty legal cards")
	test_bridge(); test_spell_ward(); test_old_save()
	print("CHANNEL CARDS: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
