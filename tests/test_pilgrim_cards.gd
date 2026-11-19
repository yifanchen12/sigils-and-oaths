extends SceneTree

const Model = preload("res://scripts/battle.gd")
const Forecast = preload("res://scripts/effect_forecast.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Art = preload("res://scripts/art_library.gd")
const Armory = preload("res://scripts/campaign_armory.gd")
const Session = preload("res://scripts/campaign_session.gd")
const LEGACY := "res://tests/fixtures/v050-active-armory.json"
const CENTER := Vector2i(5, 5)
const GLOBAL := Vector2i(-1, -1)

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
	return condition

func run() -> void:
	verify_catalog()
	verify_combo()
	verify_conditional_supply()
	verify_kill_refund(false)
	verify_kill_refund(true)
	verify_fall_chain(false)
	verify_fall_chain(true)
	verify_step_traps()
	verify_old_campaign()
	print("PILGRIM CARDS: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func field() -> Battle:
	var battle := Model.new(5101, "greenwood", "warden", "warden", "bellfoundry_column", "cairn_watch")
	for y: int in range(3, 8):
		for x: int in range(3, 9): battle.terrain[Vector2i(x, y)] = "plain"
	for player: Dictionary in battle.players:
		player.mana = 10
		player.max_mana = 10
	return battle

func action(battle: Battle, card_id: String, target: Vector2i) -> Dictionary:
	var card: Dictionary = Fixture.give(battle, card_id, battle.active_side)
	return {"type": "play", "card_uid": card.uid, "target": target}

func verify_catalog() -> void:
	var counts: Dictionary = {}
	var seen: Dictionary = {}
	var presets: int = 0
	for preset: Dictionary in Model.DECKS.decks:
		if preset.get("set_id", "") != "pilgrim": continue
		presets += 1
		check(Model.DECKS.validate_counts(preset.cards, Model.CATALOG.cards).is_empty(), "legal 30-card preset: " + preset.id)
		seen.merge(preset.cards)
	check(presets == 3, "all three Pilgrim March presets remain selectable")
	var armory_cards: Array[String] = []
	for slot: Dictionary in Armory.SLOTS:
		for candidate: Dictionary in Armory.options(slot): armory_cards.append(candidate.id)
	for card: Dictionary in Model.CATALOG.cards:
		if card.get("set_id", "") != "pilgrim": continue
		counts[card.cost] = int(counts.get(card.cost, 0)) + 1
		check(seen.has(card.id) and armory_cards.has(card.id), "usable in a preset and a campaign armory slot: " + card.id)
		var art: Texture2D = Art.get_texture(card.id)
		check(art is AtlasTexture and art.get_width() >= 400 and art.get_height() >= 400, "card face loads: " + card.id)
		if card.has("combo"):
			check(card.effect in ["verdict", "formation", "weather", "roadwork", "supply"] if card.type != "unit" else card.combo.has("entry"), "combo resolves on play: " + card.id)
		var battle: Battle = field()
		var ally: Dictionary = Fixture.troop(battle, "mage", CENTER + Vector2i.LEFT)
		ally.hp -= 1
		var enemy: Dictionary = Fixture.troop(battle, "spear", CENTER + Vector2i.RIGHT, 1)
		enemy.hp -= 1
		enemy.shield = 1
		var environment: Dictionary = Fixture.give(battle, "cedar_keel")
		battle.players[0].hand.erase(environment)
		battle.players[0].deck.append(environment)
		var instance: Dictionary = Fixture.give(battle, card.id)
		var legal: Array[Vector2i] = battle.card_targets(instance.uid, 0)
		if not check(not legal.is_empty(), "a legal play exists: " + card.id): continue
		check(battle.apply_action({"type": "play", "card_uid": instance.uid, "target": legal[0]}).ok and battle.hand_card(0, instance.uid).is_empty(),
			"normal action commits: " + card.id)
		check(Snapshot.validate(Snapshot.capture(battle)).ok, "post-play snapshot is consistent: " + card.id)
	for cost: int in range(1, 11):
		check(counts.get(cost, 0) == (4 if cost <= 6 else 3), "mana bracket %d has the expected variety" % cost)

func verify_combo() -> void:
	var battle: Battle = field()
	var ally: Dictionary = Fixture.troop(battle, "spear", CENTER)
	var runner: Dictionary = Fixture.troop(battle, "cavalry", CENTER + Vector2i.DOWN)
	runner.moved = true
	runner.rooted_turns = 2
	var opener: Dictionary = action(battle, "page_of_ash", CENTER)
	var followup: Dictionary = action(battle, "petal_signal", CENTER)
	var before: Dictionary = Snapshot.capture(battle)
	check(not battle.apply_action(opener.merged({"target": GLOBAL}, true)).ok and Snapshot.capture(battle) == before,
		"an illegal hand action changes neither zones nor combo")
	check(battle.apply_action({"type": "unit_skill", "unit_id": ally.id, "target": CENTER}).ok and not battle.hand_played_this_turn,
		"a unit ability does not prime the combo")
	check(not Forecast.predict(battle, followup).changes.any(func(change: Dictionary) -> bool: return change.refresh_move), "unprimed preview has no extra movement")
	check(battle.apply_action(opener).ok and ally.shield == 1 and battle.hand_played_this_turn, "the first card gives its base effect")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Snapshot.capture(battle), "", true, true))
	var loaded: Dictionary = Snapshot.restore(saved)
	if not check(loaded.ok and loaded.battle.hand_played_this_turn, "a mid-turn load retains the combo"): return
	var resumed: Battle = loaded.battle
	var prediction: Dictionary = Forecast.predict(resumed, followup)
	check(prediction.note.contains("连携已就绪") and prediction.changes.any(func(change: Dictionary) -> bool: return change.refresh_move and change.cleanse),
		"preview uses the upgraded effect after reload")
	var old_mana: int = resumed.players[0].mana
	check(resumed.apply_action(followup).ok and resumed.players[0].mana == old_mana - 3, "combo does not change mana cost")
	var renewed: Dictionary = resumed.get_unit(runner.id)
	check(not renewed.moved and renewed.rooted_turns == 0 and renewed.shield == 1, "upgraded movement, cleanse and shield resolve together")
	resumed.end_turn()
	check(not resumed.hand_played_this_turn, "new action turn resets the combo")
	saved.hand_played_this_turn = "true"
	check(not Snapshot.validate(saved).ok, "invalid combo flag is rejected")

func verify_conditional_supply() -> void:
	var battle: Battle = field()
	var blue: Dictionary = battle.players[0]
	for instance: Dictionary in blue.deck.duplicate():
		var card: Dictionary = battle.definition(instance.card_id)
		if card.type == "environment" and card.cost <= 3:
			blue.deck.erase(instance)
			blue.discard.append(instance)
	var unit: Dictionary = Fixture.give(battle, "chalk_courier")
	blue.hand.erase(unit)
	blue.deck.append(unit)
	var supply_action: Dictionary = action(battle, "parcel_seal", GLOBAL)
	check(battle.card_targets(supply_action.card_uid, 0).is_empty() and not battle.apply_action(supply_action).ok, "unprimed supply requires a matching environment card")
	check(battle.apply_action(action(battle, "page_of_ash", battle.commander(0).pos)).ok, "a legal opener can make the supply playable")
	check(battle.card_targets(supply_action.card_uid, 0) == [GLOBAL], "the same card has a legal global target after priming")
	check(battle.apply_action(supply_action).ok and not battle.hand_card(0, unit.uid).is_empty(), "upgraded supply can pull a scout when no environment remains")

func verify_kill_refund(protected: bool) -> void:
	var battle: Battle = field()
	Fixture.troop(battle, "sword", CENTER + Vector2i.LEFT)
	Fixture.troop(battle, "spear", CENTER + Vector2i.RIGHT)
	var enemy: Dictionary = Fixture.troop(battle, "spear", CENTER, 1)
	enemy.hp = 4
	if protected:
		battle.end_turn()
		check(battle.apply_action(action(battle, "bellglass_cover", CENTER)).ok, "a hidden spell ward can be set from the hand")
		battle.end_turn()
	battle.players[0].mana = 6
	var cast: Dictionary = action(battle, "bridle_break", CENTER)
	var projected: Dictionary = Forecast.predict(battle, cast)
	check(projected.amount == 6 and projected.changes[0].hp_after == 0 and projected.note.contains("返还 2"),
		"two adjacent allies project the higher damage and refund without reading wards")
	check(battle.apply_action(cast).ok, "surrounded troop can be targeted")
	check(battle.players[0].mana == (0 if protected else 2), "only a real kill refunds this turn's mana")
	check(battle.get_unit(enemy.id).is_empty() == not protected, "hidden ward changes actual outcome")
	if protected: check(battle.last_trap_events.size() == 1 and battle.last_trap_events[0].side == 1, "ward triggered exactly once")

func verify_fall_chain(protected: bool) -> void:
	var battle: Battle = field()
	var blue: Dictionary = Fixture.troop(battle, "shale_lancer", CENTER)
	var nearby: Dictionary = Fixture.troop(battle, "healer", CENTER + Vector2i.RIGHT + Vector2i.DOWN)
	var red: Dictionary = Fixture.troop(battle, "cairn_colossus", CENTER + Vector2i.RIGHT, 1)
	blue.hp = 1
	red.hp = 2
	nearby.hp = 3
	battle.end_turn()
	if protected: check(battle.apply_action(action(battle, "bellglass_cover", red.pos)).ok, "set a ward on the active side before retaliation")
	check(battle.apply_action(action(battle, "bolt", CENTER)).ok and battle.get_unit(blue.id).is_empty(), "red defeats the defending lancer")
	check(battle.get_unit(red.id).is_empty() == not protected and battle.get_unit(nearby.id).is_empty() == not protected,
		"both casualty waves finish in the same action, and a ward can stop the first wave")
	if protected: check(battle.last_trap_events.size() == 1, "a ward opposes the source of death damage during its owner's turn")
	check(Snapshot.validate(Snapshot.capture(battle)).ok, "snapshots contain only survivors after the cascade")

func verify_step_traps() -> void:
	for id: String in ["twine_knot", "undertread_receipt"]:
		var battle: Battle = field()
		Fixture.troop(battle, "mage", CENTER + Vector2i.UP)
		var runner: Dictionary = Fixture.troop(battle, "cavalry", CENTER + Vector2i.RIGHT * 2, 1)
		var supply: Dictionary = Fixture.give(battle, "whetstone_order")
		battle.players[0].hand.erase(supply)
		battle.players[0].deck.append(supply)
		var crossing: Vector2i = CENTER + Vector2i.RIGHT
		check(battle.apply_action(action(battle, id, crossing)).ok and battle.hand_played_this_turn, "hand trap is a successful card play")
		check(battle.visible_traps(0).size() == 1 and battle.visible_traps(1).is_empty(), "opponent does not see the trap's position")
		battle.end_turn()
		check(battle.apply_action({"type": "move", "unit_id": runner.id, "target": CENTER}).ok and battle.last_trap_events.size() == 1, "a real move triggers exactly one trap")
		if id == "twine_knot":
			check(runner.pos == crossing and runner.rooted_turns == 1 and runner.hp == runner.max_hp and not runner.attacked, "twine stops movement without damaging or disarming")
		else:
			check(runner.pos == CENTER and runner.attacked and runner.hp == runner.max_hp - 2, "supply trap disarms without breaking the path")
			check(not battle.hand_card(0, supply.uid).is_empty(), "supply trap pulls the promised card from the deck")

func verify_old_campaign() -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
	var session = Session.new(LEGACY)
	if not check(original.encounter.battle.version == 10 and session.load_campaign().ok and session.encounter != null, "real 0.50 in-progress campaign loads"): return
	var restored: Dictionary = JSON.parse_string(JSON.stringify(Snapshot.capture(session.encounter), "", true, true))
	var expected: Dictionary = original.encounter.battle.duplicate(true)
	expected.version = float(Snapshot.VERSION)
	expected.rules = Snapshot.rules_signature()
	check(restored == expected and session.campaign.armory.vanguard == "quiet_net", "legacy board, hidden trap, card zones, clock and loadout are exact")
