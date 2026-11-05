extends SceneTree

const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Model = preload("res://scripts/battle.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(label)

func roundtrip(battle: RefCounted) -> Dictionary:
	return Snapshot.restore(JSON.parse_string(JSON.stringify(Snapshot.capture(battle), "", true, true)))

func invalid(data: Dictionary, label: String) -> void:
	var result: Dictionary = Snapshot.restore(data)
	check(not result.ok and result.has("message"), label)

func test_roundtrip() -> bool:
	var original: RefCounted = Fixture.rich()
	var data: Dictionary = Snapshot.capture(original)
	check(data.rng_seed is String and data.rng_state is String, "RNG uses exact decimal strings")
	var result: Dictionary = roundtrip(original)
	check(result.ok, "rich snapshot validates after JSON conversion")
	if not result.ok: push_error(result.message); return false
	var restored: RefCounted = result.battle
	check(Snapshot.capture(restored) == data, "all authoritative fields survive JSON roundtrip")
	check(restored.units != [] and restored.units[0].pos is Vector2i and restored.units[0].id is int, "engine coordinates and IDs reconstructed")
	check(restored.hero(1).name == "军道扣车队长" and Model.HEROES.find("pyromancer").name != restored.hero(1).name, "NPC identity restored without resource mutation")
	var target: Dictionary = restored.unit_at(Vector2i(5, 3))
	check(restored.attack_defender(restored.unit_at(Vector2i(5, 5)), target).id == restored.unit_at(Vector2i(4, 3)).id, "earlier guard still selected when two guards can intercept")
	for index: int in range(12): check(original.rng.randi() == restored.rng.randi(), "next RNG sample matches " + str(index))
	data.players[0].hand.clear(); data.units[0].hp = 1; data.terrain[0] = "water"
	check(not original.players[0].hand.is_empty() and original.units[0].hp != 1 and original.ground(Vector2i.ZERO) != "water", "capture does not alias model")
	var same: Dictionary = Snapshot.capture(original)
	for step: int in range(12):
		var actions: Array = original.get_legal_actions(original.active_side)
		check(actions == restored.get_legal_actions(restored.active_side), "legal actions match after restore")
		var action: Dictionary = {"type": "end_turn"} if step % 3 == 0 else actions[0]
		check(original.apply_action(action).ok and restored.apply_action(action).ok, "same continued action succeeds")
		check(Snapshot.capture(original) == Snapshot.capture(restored), "continued state stays identical")
		if original.winner != -1: break
	check(original.advance_clock(0.375) == restored.advance_clock(0.375) and Snapshot.capture(original) == Snapshot.capture(restored), "fractional clock continues identically")
	check(original.advance_clock(100) == restored.advance_clock(100) and Snapshot.capture(original) == Snapshot.capture(restored), "timeout hands over identically")
	check(not same.is_empty(), "baseline captured")
	return true

func test_skills_and_special_states() -> bool:
	for kind: String in ["sword", "spear", "cavalry", "archer", "mage", "healer"]:
		var game: RefCounted = Model.new(51)
		game.players[0].mana = 10; game.players[0].max_mana = 10
		var unit: Dictionary = Fixture.troop(game, kind, Vector2i(5, 5))
		Fixture.troop(game, "sword", Vector2i(5, 4), 1)
		unit.hp = 1
		if kind == "cavalry": unit.moved = true; unit.last_move_distance = 3
		var targets: Array = game.skill_targets(unit)
		check(not targets.is_empty(), "skill fixture has target " + kind)
		if targets.is_empty(): return false
		check(game.apply_action({"type": "unit_skill", "unit_id": unit.id, "target": targets[0]}).ok, "actual skill before save " + kind)
		var loaded: Dictionary = roundtrip(game)
		check(loaded.ok and Snapshot.capture(loaded.battle) == Snapshot.capture(game), "actual skill state survives " + kind)
		if not loaded.ok: push_error(loaded.message); return false
		game.end_turn(); loaded.battle.end_turn(); game.end_turn(); loaded.battle.end_turn()
		check(Snapshot.capture(game) == Snapshot.capture(loaded.battle), "next own turn resets skill/guard identically " + kind)
	for outcome: int in [0, 1, 2]:
		var game: RefCounted = Model.new(52)
		if outcome in [1, 2]: game.commander(0).hp = 0
		if outcome in [0, 2]: game.commander(1).hp = 0
		game._cleanup(); game._check_winner()
		var loaded: Dictionary = roundtrip(game)
		check(loaded.ok and loaded.battle.winner == outcome, "terminal state roundtrip " + str(outcome))
	var custom: RefCounted = Model.new(57, "rivergate", "grove", "warden", "custom", "bastion", 90, Model.DECKS.find("assault"))
	check(roundtrip(custom).ok and roundtrip(custom).battle.deck(0).cards == custom.deck(0).cards, "custom deck definition retained")
	var fatigue: RefCounted = Model.new(58)
	fatigue.players[0].discard.append_array(fatigue.players[0].deck)
	fatigue.players[0].deck.clear()
	fatigue.players[0].fatigue = 2
	var loaded: Dictionary = roundtrip(fatigue)
	check(loaded.ok, "empty deck and fatigue validate")
	fatigue.end_turn(); loaded.battle.end_turn(); fatigue.end_turn(); loaded.battle.end_turn()
	check(Snapshot.capture(fatigue) == Snapshot.capture(loaded.battle) and fatigue.players[0].fatigue == 3, "fatigue damage and draw order retained")
	return true

func test_invalid() -> bool:
	var base: Dictionary = Snapshot.capture(Fixture.rich())
	for key: String in ["version", "map_id", "rules", "rng_state", "rng_seed", "turn", "next_id", "players", "units", "terrain", "log", "time_remaining"]:
		var data: Dictionary = base.duplicate(true); data.erase(key); invalid(data, "missing " + key)
	for value: Variant in [-1, 1.2, "1", true, NAN, INF]:
		var data: Dictionary = base.duplicate(true); data.turn = value; invalid(data, "bad turn")
	for value: Variant in [1.0, "9223372036854775808", "-9223372036854775809", "1e2", "001", " 42", "-0"]:
		var data: Dictionary = base.duplicate(true); data.rng_state = value; invalid(data, "bad exact RNG state")
	for value: String in ["9223372036854775807", "-9223372036854775808", "0"]:
		var data: Dictionary = base.duplicate(true); data.rng_state = value
		var loaded: Dictionary = Snapshot.restore(data)
		check(loaded.ok and Snapshot.capture(loaded.battle).rng_state == value, "full signed 64-bit state roundtrips")
	var data: Dictionary = base.duplicate(true); data.version = 99
	check(Snapshot.restore(data).get("protected", false), "future snapshot version is protected")
	data = base.duplicate(true); data.rules = "f".repeat(64)
	check(Snapshot.restore(data).get("protected", false), "different rules cannot be silently reinterpreted")
	data = base.duplicate(true); data.active_side = 1; invalid(data, "turn parity")
	data = base.duplicate(true); data.winner = 0; invalid(data, "invented victory")
	data = base.duplicate(true); data.map_id = "absent"; invalid(data, "unknown map")
	data = base.duplicate(true); data.units[1].pos = data.units[0].pos; invalid(data, "overlapping units")
	data = base.duplicate(true); data.units[0].pos = [-1, 2]; invalid(data, "off-map position")
	data = base.duplicate(true); data.units[0].pos = [1.5, 2]; invalid(data, "fractional position")
	data = base.duplicate(true); data.units[0].hp = 0; invalid(data, "unresolved death")
	data = base.duplicate(true); data.units[0].hp = 999; invalid(data, "health above maximum")
	data = base.duplicate(true); data.units[0].attacked = 1; invalid(data, "numeric action flag")
	data = base.duplicate(true); data.units[2].card.unit_id = 1; invalid(data, "wrong deployed association")
	data = base.duplicate(true); data.units[2].erase("card"); invalid(data, "missing deployed card")
	data = base.duplicate(true); data.players[0].hand[0].uid = data.units[0].id; invalid(data, "card ID collides with unit")
	data = base.duplicate(true); data.players[0].hand.append(data.players[0].hand[0]); invalid(data, "duplicate card across zones")
	data = base.duplicate(true); data.players[0].card_total += 1; invalid(data, "lost card")
	data = base.duplicate(true); data.players[0].hand[0].card_id = "missing"; invalid(data, "unknown card")
	data = base.duplicate(true); data.players[0].hero_id = "missing"; invalid(data, "unknown hero")
	data = base.duplicate(true); data.players[0].deck_counts.sword = 100; invalid(data, "illegal original deck")
	data = base.duplicate(true); data.players[0].mana = 11; invalid(data, "excess mana")
	data = base.duplicate(true); data.time_remaining = 91; invalid(data, "timer overflow")
	data = base.duplicate(true); data.weather = "clear"; invalid(data, "inconsistent weather duration")
	data = base.duplicate(true); data.terrain[0] = "unknown"; invalid(data, "unknown terrain")
	data = base.duplicate(true); data.terrain.pop_back(); invalid(data, "missing map cell")
	check(Snapshot.restore(base).ok, "rejections do not mutate valid source snapshot")
	return true

func test_spells_and_heroes() -> bool:
	for card_id: String in ["rampart", "trail", "rain", "fog", "sun", "snow", "clear_skies", "frostbind", "exchange", "onslaught", "march", "ward", "insight"]:
		var game: RefCounted = Model.new(63)
		game.players[0].mana = 10; game.players[0].max_mana = 10
		var ally: Dictionary = Fixture.troop(game, "sword", Vector2i(5, 5))
		var enemy: Dictionary = Fixture.troop(game, "spear", Vector2i(5, 4), 1)
		var target: Vector2i = ally.pos
		match card_id:
			"rain", "fog", "sun", "snow", "insight": target = Vector2i(-1, -1)
			"clear_skies": game.weather = "rain"; game.weather_remaining = 3; target = Vector2i(-1, -1)
			"frostbind": target = enemy.pos
			"exchange": game.commander(0).pos = Vector2i(3, 5); game.terrain[Vector2i(3, 5)] = "plain"
			"onslaught": ally.moved = true; ally.attacked = true
			"march": ally.moved = true
		var card: Dictionary = Fixture.give(game, card_id)
		if card_id == "insight":
			while game.players[0].hand.size() < Model.HAND_LIMIT: game.add_generated_card(0, "bolt")
		check(game.apply_action({"type": "play", "card_uid": card.uid, "target": target}).ok, "real spell before save " + card_id)
		var loaded: Dictionary = roundtrip(game)
		check(loaded.ok and Snapshot.capture(loaded.battle) == Snapshot.capture(game), "spell result preserved " + card_id)
		if not loaded.ok: return false
		game.end_turn(); loaded.battle.end_turn()
		check(Snapshot.capture(game) == Snapshot.capture(loaded.battle), "spell state survives next turn " + card_id)
	for hero: String in ["warden", "pyromancer", "grove"]:
		var game: RefCounted = Model.new(64, "greenwood", hero)
		game.players[0].mana = 10; game.players[0].max_mana = 10
		game.commander(0).hp = 12
		var cell: Vector2i = game.commander(0).pos + Vector2i.RIGHT
		Fixture.troop(game, "sword", cell, 1)
		var target: Vector2i = cell if hero == "pyromancer" else (Vector2i(-1, -1) if hero == "grove" else game.commander(0).pos)
		check(game.apply_action({"type": "hero", "target": target}).ok, "real hero skill before save " + hero)
		var loaded: Dictionary = roundtrip(game)
		check(loaded.ok and Snapshot.capture(loaded.battle) == Snapshot.capture(game), "hero cooldown, heal and draw preserved " + hero)
	return true

func run() -> void:
	for method: String in ["test_roundtrip", "test_skills_and_special_states", "test_invalid", "test_spells_and_heroes"]:
		check(call(method) == true, method + " completed without runtime interruption")
	print("BATTLE SNAPSHOT CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
