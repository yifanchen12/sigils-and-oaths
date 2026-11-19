extends SceneTree

const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const Forecast = preload("res://scripts/effect_forecast.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Armory = preload("res://scripts/campaign_armory.gd")
const Art = preload("res://scripts/art_library.gd")
const AI = preload("res://scripts/opponent.gd")
const LEGACY := "res://tests/fixtures/v052-active-bellfoundry.json"
const CENTER := Vector2i(5, 5)

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	return condition

func run() -> void:
	verify_catalog()
	verify_choice()
	verify_muster()
	verify_opponent()
	verify_legacy()
	print("GLASSROAD CARDS: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func field() -> Battle:
	var battle := Battle.new(5301, "greenwood", "warden", "warden", "glassroad_reserve", "glassroad_edict")
	for y: int in range(2, 9):
		for x: int in range(2, 10): battle.terrain[Vector2i(x, y)] = "plain"
	for player: Dictionary in battle.players:
		player.mana = 10
		player.max_mana = 10
	return battle

func play(battle: Battle, card: String, cell: Vector2i) -> Dictionary:
	return {"type": "play", "card_uid": Fixture.give(battle, card, battle.active_side).uid, "target": cell}

func lodge(battle: Battle, id: String, zone: String) -> Dictionary:
	var instance: Dictionary = Fixture.give(battle, id)
	battle.players[0].hand.erase(instance)
	battle.players[0][zone].append(instance)
	return instance

func verify_catalog() -> void:
	var frequencies: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var preset_ids: Dictionary = {}
	var presets: int = 0
	for preset: Dictionary in Battle.DECKS.decks:
		if preset.get("set_id", "") != "glassroad": continue
		presets += 1
		check(Battle.DECKS.validate_counts(preset.cards, Battle.CATALOG.cards).is_empty(), "legal 30-card preset: " + preset.id)
		preset_ids.merge(preset.cards)
	check(presets == 4 and Battle.DECKS.decks.size() == 23 and Battle.CATALOG.cards.size() == 249, "four new presets and 248 collectible cards")
	var armory_ids: Dictionary = {}
	for slot: Dictionary in Armory.SLOTS:
		for card: Dictionary in Armory.options(slot): armory_ids[card.id] = slot.id
	var copy: Dictionary = {}
	for card: Dictionary in Battle.CATALOG.cards:
		check(not copy.has(card.id), "card ID is unique: " + card.id)
		copy[card.id] = true
		if card.get("set_id", "") != "glassroad": continue
		frequencies[int(card.cost) - 1] += 1
		check(preset_ids.has(card.id) and armory_ids.has(card.id), "available in a preset and campaign armory: " + card.id)
		var portrait: Texture2D = Art.get_texture(card.id)
		check(portrait is AtlasTexture and portrait.get_width() >= 220 and portrait.get_height() >= 220, "distinct card artwork exists: " + card.id)
		var battle: Battle = field()
		var near_ally: Dictionary = Fixture.troop(battle, "mage", CENTER + Vector2i.LEFT)
		var near_enemy: Dictionary = Fixture.troop(battle, "spear", CENTER + Vector2i.RIGHT, 1)
		near_ally.hp -= 2
		near_ally.rooted_turns = 2
		near_enemy.shield = 2
		battle.terrain[near_enemy.pos] = "hill"
		var fallen: Dictionary = Fixture.troop(battle, "sword", CENTER + Vector2i(0, 2))
		fallen.hp = 0
		battle._cleanup()
		for id: String in ["sword", "archer", "cavalry", "mage", "breakline_sappers", "sill_chalk"]: lodge(battle, id, "deck")
		for id: String in ["bolt", "anchor_snare"]: lodge(battle, id, "discard")
		var action: Dictionary = play(battle, card.id, CENTER)
		var legal: Array[Vector2i] = battle.card_targets(action.card_uid, 0)
		if not check(not legal.is_empty(), "regular targeting offers a valid play: " + card.id): continue
		action.target = legal[0]
		check(battle.apply_action(action).ok and battle.hand_card(0, action.card_uid).is_empty(), "regular play spends the card: " + card.id)
		check(Snapshot.validate(Snapshot.capture(battle)).ok, "valid save after playing " + card.id)
	check(frequencies == [5, 5, 5, 5, 5, 5, 5, 5, 4, 4], "every mana bracket has 4–5 new cards")

func verify_choice() -> void:
	var battle: Battle = field()
	var ally: Dictionary = Fixture.troop(battle, "mage", CENTER)
	var enemy: Dictionary = Fixture.troop(battle, "spear", CENTER + Vector2i(4, 0), 1)
	var distant: Dictionary = Fixture.troop(battle, "spear", CENTER + Vector2i(5, 0), 1)
	ally.rooted_turns = 2
	battle.players[0].max_mana = 5
	battle.players[0].mana = 1
	var action: Dictionary = play(battle, "crossroads_whistle", CENTER)
	var options: Array[Vector2i] = battle.card_targets(action.card_uid, 0)
	check(options.has(CENTER) and options.has(enemy.pos) and not options.has(distant.pos), "both branches use caster radius; a mage reaches four cells")
	var low: Dictionary = Forecast.predict(battle, action)
	if not check(not low.is_empty(), "ally branch can be forecast"): return
	check(low.changes[0].shield_after == 1 and not low.changes[0].cleanse, "base ally branch has one shield")
	var before: Dictionary = Snapshot.capture(battle)
	check(not battle.apply_action(action.merged({"target": distant.pos}, true)).ok and Snapshot.capture(battle) == before,
		"invalid choice leaves mana, hand and combo unchanged")
	battle.players[0].max_mana = 6
	var high: Dictionary = Forecast.predict(battle, action)
	check(high.changes[0].shield_after == 2 and high.changes[0].cleanse and high.note.contains("急哨护身"), "raised mana cap improves the ally branch")
	var foe_action: Dictionary = action.merged({"target": enemy.pos}, true)
	var attack: Dictionary = Forecast.predict(battle, foe_action)
	check(attack.changes[0].hp_loss == 2 and attack.note.contains("压低哨音"), "same card previews an enhanced attack at enemy target")
	var foe_hp: int = enemy.hp
	var copy: Dictionary = Snapshot.restore(JSON.parse_string(JSON.stringify(Snapshot.capture(battle))))
	if check(copy.ok, "save restores the hand, exact thresholds and target positions"):
		check(copy.battle.apply_action(foe_action).ok and copy.battle.get_unit(enemy.id).hp == foe_hp - 2 and copy.battle.get_unit(ally.id).rooted_turns == 2,
			"enemy branch resolves independently after loading")
	check(battle.apply_action(action).ok and ally.rooted_turns == 0 and ally.shield == 2 and enemy.hp == foe_hp and battle.players[0].mana == 0,
		"ally mode matches preview and costs one mana with none spare")

func verify_muster() -> void:
	var battle: Battle = field()
	Fixture.troop(battle, "mage", CENTER + Vector2i.LEFT)
	Fixture.troop(battle, "rook_pickets", Vector2i(3, 3))
	Fixture.troop(battle, "glassroad_runner", Vector2i(3, 4))
	Fixture.troop(battle, "reedglass_bow", Vector2i(3, 5))
	var enemy: Dictionary = Fixture.troop(battle, "spear", CENTER + Vector2i.RIGHT, 1)
	enemy.shield = 2
	battle.end_turn()
	check(battle.apply_action(play(battle, "sill_chalk", CENTER)).ok, "opposing hidden trap is actually armed")
	battle.end_turn()
	battle.weather = "lanterns"
	battle.weather_remaining = 3
	var first: Dictionary = lodge(battle, "breakline_sappers", "deck")
	var second: Dictionary = lodge(battle, "mage", "deck")
	var third: Dictionary = lodge(battle, "cinder_coxswain", "deck")
	var action: Dictionary = play(battle, "all_banner_call", CENTER)
	var prediction: Dictionary = Forecast.predict(battle, action)
	if not check(not prediction.is_empty() and prediction.cells == [CENTER, CENTER + Vector2i.UP], "foe and cap limit reinforcement from three to two"): return
	check(prediction.note.contains("裂垛破障队") and prediction.note.contains("星火术士") and not prediction.note.contains("余炭舵手"), "preview lists only the actual two deck units")
	var deck_size: int = battle.players[0].deck.size()
	var instance_total: int = battle.players[0].card_total
	check(battle.apply_action(action).ok and battle.players[0].mana == 0 and battle.army_count(0) == 6, "normal play fills remaining slots at the cost of ten mana")
	check(battle.players[0].deck.size() == deck_size - 2 and battle.players[0].deck.has(third) and battle.players[0].card_total == instance_total,
		"muster moves from deck without creating extra copies or removing unplaced cards")
	check(battle.unit_at(CENTER).card.uid == first.uid and battle.unit_at(CENTER + Vector2i.UP).card.uid == second.uid, "placements match the predicted instance IDs")
	check(battle.unit_at(CENTER).shield == 2 and battle.unit_at(CENTER).summoning and battle.movement_cells(battle.unit_at(CENTER)).is_empty(),
		"weather shield applies and recruits cannot act early")
	check(enemy.shield == 2 and battle.traps.size() == 1 and battle.last_trap_events.is_empty(), "muster skips the arrival attack and does not step on hidden traps")
	var saved: Dictionary = Snapshot.capture(battle)
	var restored: Dictionary = Snapshot.restore(JSON.parse_string(JSON.stringify(saved)))
	check(restored.ok and Snapshot.capture(restored.battle) == saved, "deployed reserve, unspent reserve and concealed enemy trap survive reload")
	battle.players[0].mana = 10
	var follow_up: Dictionary = play(battle, "twin_rearguard", CENTER + Vector2i.DOWN)
	var full: Dictionary = Snapshot.capture(battle)
	check(battle.card_targets(follow_up.card_uid, 0).is_empty() and not battle.apply_action(follow_up).ok and Snapshot.capture(battle) == full,
		"no available troop slots leaves mana and zones untouched")
	battle = field()
	Fixture.troop(battle, "mage", CENTER + Vector2i.LEFT)
	for reserve: Dictionary in battle.players[0].deck.duplicate():
		var troop: Dictionary = battle.definition(reserve.card_id)
		if troop.type != "unit" or int(troop.cost) not in [3, 4, 5]: continue
		battle.players[0].deck.erase(reserve)
		battle.players[0].discard.append(reserve)
	var stranded: Dictionary = play(battle, "all_banner_call", CENTER)
	var empty: Dictionary = Snapshot.capture(battle)
	check(battle.deployment_cells(0).has(CENTER) and battle.card_targets(stranded.card_uid, 0).is_empty()
		and not battle.apply_action(stranded).ok and Snapshot.capture(battle) == empty, "an empty reserve cannot spend mana or create a troop")

func verify_opponent() -> void:
	var battle: Battle = field()
	var leader: Dictionary = battle.commander(1)
	leader.pos = CENTER
	leader.hp = 2
	Fixture.troop(battle, "mage", CENTER + Vector2i(-4, 0))
	var row: Dictionary = play(battle, "glass_treaty", CENTER)
	var planned: Dictionary = AI.choose(battle)
	check(planned == row and battle.apply_action(planned).ok and battle.winner == 0, "AI can finish a commander using the ten-mana attack branch")
	battle = field()
	for instance: Dictionary in battle.players[0].hand.duplicate():
		battle.players[0].hand.erase(instance)
		battle.players[0].discard.append(instance)
	for id: String in ["breakline_sappers", "mage", "cavalry"]: lodge(battle, id, "deck")
	var card: Dictionary = Fixture.give(battle, "all_banner_call")
	var recruit: Dictionary = AI.choose(battle)
	if check(recruit.get("card_uid", -1) == card.uid, "AI sees a worthwhile high-cost muster"):
		check(battle.apply_action(recruit).ok and battle.army_count(0) == 3, "AI deploys three legitimate reserves without bypassing rules")

func verify_legacy() -> void:
	var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
	if not check(old is Dictionary and old.version == 11 and old.rules == Snapshot.v052_rules_signature(), "exact published 0.52 rules signature remains recognized"): return
	var result: Dictionary = Snapshot.restore(old)
	if not check(result.ok, "real mid-match v0.52 save opens"): return
	var adapted: Dictionary = old.duplicate(true)
	adapted.version = float(Snapshot.VERSION)
	adapted.rules = Snapshot.rules_signature()
	var battle: Battle = result.battle
	check(JSON.parse_string(JSON.stringify(Snapshot.capture(battle))) == adapted and battle.hand_played_this_turn and battle.time_remaining == 81.75,
		"old snapshot keeps the complete board, decks, mana, timer, turn and combo")
	for step: int in range(12):
		if battle.winner != -1: break
		check(battle.apply_action(AI.choose(battle)).ok, "resumed old match still takes legal action %d" % step)
	check(Snapshot.validate(Snapshot.capture(battle)).ok, "old match can be saved with the new rules")
