extends "res://tests/test_expansion_cards.gd"

const Art = preload("res://scripts/art_library.gd")
const NO_TARGET := Vector2i(-1, -1)

func test_catalog() -> void:
	var curve: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var first: Dictionary = Model.DECKS.find("tideline_raiders").cards
	var second: Dictionary = Model.DECKS.find("reserve_company").cards
	var types: Dictionary = {}
	for card: Dictionary in Model.CATALOG.cards:
		if card.get("set_id", "") != "tidegate": continue
		curve[int(card.cost) - 1] += 1
		types[card.type] = int(types.get(card.type, 0)) + 1
		var texture: AtlasTexture = Art.get_texture(card.id) as AtlasTexture
		check(texture != null and texture.region.size == Vector2(358, 358), "illustration for " + card.id)
		check(first.has(card.id) or second.has(card.id), "discoverable in a preset: " + card.id)
	check(curve == [3, 4, 4, 4, 4, 4, 3, 3, 3, 4], "new cards cover all mana costs")
	check(types == {"unit": 12, "spell": 12, "trap": 8, "environment": 4}, "new cards span all roles")
	check(Model.DECKS.validate_counts(first, Model.CATALOG.cards).is_empty(), "attack preset is a legal 30-card deck")
	check(Model.DECKS.validate_counts(second, Model.CATALOG.cards).is_empty(), "reserve preset is a legal 30-card deck")

func test_vanguard_and_recovery() -> void:
	var battle := arena()
	var enemy: Dictionary = troop(battle, "archer", Vector2i(4, 3), 1)
	check(play(battle, "cinder_runner", Vector2i(3, 3)).ok, "vanguard deploys by commander")
	var cavalry: Dictionary = battle.unit_at(Vector2i(3, 3))
	if cavalry.is_empty(): return
	var original_card: int = cavalry.card.uid
	check(battle.attack_targets(cavalry).is_empty() and battle.skill_targets(cavalry).is_empty(), "vanguard cannot attack or use skills even when next to enemy")
	check(battle.apply_action({"type": "move", "unit_id": cavalry.id, "target": Vector2i(3, 5)}).ok, "new vanguard can make a standard legal move")
	check(battle.movement_cells(cavalry).is_empty() and battle.attack_targets(cavalry).is_empty(), "vanguard has only one movement this turn")
	valid(battle, "spent vanguard")
	battle.end_turn()
	battle.end_turn()
	check(not cavalry.summoning and not cavalry.moved and not cavalry.attacked, "vanguard becomes fully ready on its next turn")
	battle._hurt(cavalry, 20)
	battle._cleanup()
	check(battle.add_generated_card(0, "ridge_pioneer"), "supply a discarded but unplayed unit")
	battle.players[0].discard.append(battle.players[0].hand.pop_back())
	check(battle.add_generated_card(0, "field_muster"), "supply restart spell")
	var muster: Dictionary = battle.players[0].hand.back()
	var bad: Dictionary = {"type": "play", "card_uid": muster.uid, "target": Vector2i(8, 8)}
	var before: Dictionary = Snapshot.capture(battle)
	check(not battle.apply_action(bad).ok and Snapshot.capture(battle) == before, "out-of-formation redeploy pays nothing")
	var action: Dictionary = {"type": "play", "card_uid": muster.uid, "target": Vector2i(3, 3)}
	var forecast: Dictionary = Effects.predict(battle, action)
	check(not forecast.is_empty() and forecast.note.contains("灰岸传旗骑"), "forecast names the eligible casualty and ignores burned unit")
	check(battle.apply_action(action).ok, "recent casualty redeploys into a legal empty tile")
	var revived: Dictionary = battle.unit_at(Vector2i(3, 3))
	if revived.is_empty(): return
	check(revived.card.uid == original_card and revived.id != cavalry.id and revived.hp == revived.max_hp, "revival reuses card identity and grants a fresh unit at full health")
	check(battle.movement_cells(revived).is_empty() and battle.attack_targets(revived).is_empty(), "revival skips printed vanguard effect")
	check(battle.units.has(enemy), "redeployment leaves nearby enemy untouched")
	valid(battle, "redeployed card")

func test_recapture_hand_capacity() -> void:
	var battle := arena()
	var first: Dictionary = troop(battle, "sword", Vector2i(3, 3), 0)
	battle._hurt(first, 20)
	battle._cleanup()
	var second: Dictionary = troop(battle, "ridge_pioneer", Vector2i(3, 3), 0)
	battle._hurt(second, 20)
	battle._cleanup()
	for index: int in range(Model.HAND_LIMIT - 1): check(battle.add_generated_card(0, "heal"), "occupy a hand slot")
	check(play(battle, "remember_the_company", NO_TARGET).ok, "reserve search accepts a full hand because playing a card frees one slot")
	var hand: Array = battle.players[0].hand
	check(hand.size() == Model.HAND_LIMIT and hand.back().uid == second.card.uid and not hand.back().has("unit_id"), "latest casualty moves to hand without deployment association")
	check(battle.players[0].discard.has(first.card), "older casualty stays in discard at the hand cap")
	check(battle.fallen_cards(battle.definition("sealed_roll"), 0) == [first.card], "later recovery still finds the older low-cost casualty")
	valid(battle, "recovery and hand limit")

func test_retort_and_dual_ward() -> void:
	var battle := arena()
	var ward: Dictionary = troop(battle, "archer", Vector2i(3, 3), 0)
	var guard: Dictionary = troop(battle, "spear", Vector2i(3, 2), 0)
	var raider: Dictionary = troop(battle, "sword", Vector2i(4, 3), 1)
	guard.guarding = true
	guard.hp = 1
	raider.atk = 8
	raider.hp = 3
	check(play(battle, "seagate_sting", guard.pos).ok, "retort trap attaches to the future intercepting unit")
	valid(battle, "untriggered retort")
	battle.end_turn()
	var preview: Dictionary = battle.attack_forecast(raider, ward)
	check(preview.intercepted and not preview.has("retort_damage"), "attack forecast respects guard and hides enemy traps")
	check(battle.apply_action({"type": "attack", "unit_id": raider.id, "target": ward.pos}).ok, "intercepting guard is hit")
	check(battle.last_combat.defender_id == guard.id and battle.last_combat.retort_damage == 3, "trap reacts after the attack against the actual defender")
	check(battle.get_unit(guard.id).is_empty() and battle.get_unit(raider.id).is_empty() and ward.hp == ward.max_hp, "retort can finish the attacker even if the guard falls")
	check(battle.traps.is_empty() and battle.last_trap_events.size() == 1, "retort trap triggers exactly once")
	valid(battle, "simultaneous losses")
	for trigger: String in ["attack", "spell"]:
		battle = arena()
		ward = troop(battle, "spear", Vector2i(3, 3), 0)
		raider = troop(battle, "mage", Vector2i(4, 3), 1)
		check(play(battle, "rain_cloak", ward.pos).ok, "either-trigger trap plays from hand")
		check(not battle.Traps.targets(battle, battle.definition("rain_cloak"), 0).has(ward.pos), "same protected unit cannot have two wards")
		valid(battle, "pending dual trap")
		battle.end_turn()
		var ok: bool
		if trigger == "attack": ok = battle.apply_action({"type": "attack", "unit_id": raider.id, "target": ward.pos}).ok
		else: ok = play(battle, "bolt", ward.pos).ok
		check(ok and battle.traps.is_empty() and battle.last_trap_events.size() == 1 and battle.players[0].hand.size() == 1, "dual trap consumed by " + trigger)
		valid(battle, "dual trigger " + trigger)

func test_pull_back_and_terrain() -> void:
	var battle := arena()
	var ally: Dictionary = troop(battle, "sword", Vector2i(5, 3), 0)
	troop(battle, "mage", Vector2i(5, 2), 1)
	battle.end_turn()
	check(play(battle, "chalk_spike", Vector2i(3, 3)).ok, "red can place a trap on the retreat destination")
	battle.end_turn()
	ally.hp = 1
	ally.rooted_turns = 1
	ally.moved = true
	check(battle.add_generated_card(0, "lantern_stretcher"), "supply stretcher")
	var action: Dictionary = {"type": "play", "card_uid": battle.players[0].hand.back().uid, "target": ally.pos}
	var preview: Dictionary = Effects.predict(battle, action)
	check(not preview.is_empty() and preview.changes[0].position_after == Vector2i(3, 3), "pullback preview marks real destination")
	check(battle.apply_action(action).ok and ally.pos == Vector2i(3, 3) and ally.hp == 4, "stretcher retreats and heals")
	check(ally.moved and ally.rooted_turns == 0 and battle.traps.size() == 1, "forced movement skips step traps and preserves spent movement")
	battle.players[0].mana = 10
	var bridge := Vector2i(3, 2)
	var river := Vector2i(3, 4)
	battle.terrain[bridge] = "bridge"
	battle.terrain[river] = "water"
	check(play(battle, "slate_grid", ally.pos).ok, "nearby units can build fortifications")
	check(battle.ground(ally.pos) == "fort" and ally.shield == 2 and battle.terrain_defense(ally) == 2, "converted allied tile confers defense and shield")
	check(battle.ground(bridge) == "bridge" and battle.ground(river) == "water", "building preserves bridge and water")
	valid(battle, "fortification and trap in one cell")

func test_conditions_and_legacy() -> void:
	var battle := arena()
	var victim: Dictionary = troop(battle, "spear", Vector2i(5, 3), 1)
	var flanked: Dictionary = battle.definition("two_shore_claim")
	var isolated: Dictionary = battle.definition("stragglers_writ")
	check(battle.verdict_damage(flanked, victim) == 2 and battle.verdict_damage(isolated, victim) == 5, "one lone enemy is vulnerable to pursuit")
	troop(battle, "sword", Vector2i(4, 3), 0)
	troop(battle, "cavalry", Vector2i(5, 4), 0)
	troop(battle, "archer", Vector2i(6, 3), 1)
	check(battle.verdict_damage(flanked, victim) == 4 and battle.verdict_damage(isolated, victim) == 2, "separate formations satisfy different conditions")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v044-skirmish.json"))
	check(raw.version == 6 and raw.rules == Snapshot.v044_rules_signature(), "old rules signature matches prior exported Windows pack")
	var decoded: Dictionary = Snapshot.restore(raw)
	check(decoded.ok, "prior released 0.44 skirmish loads")
	if decoded.ok:
		check(decoded.battle.turn == 2 and is_equal_approx(decoded.battle.time_remaining, 77.75), "previous clock and stage restored")
		var migrated: Dictionary = Snapshot.capture(decoded.battle)
		migrated.erase("version")
		migrated.erase("rules")
		check(migrated.pending_orders.is_empty(), "legacy battle has no pending orders")
		migrated.erase("pending_orders")
		raw.erase("version")
		raw.erase("rules")
		check(JSON.parse_string(JSON.stringify(migrated, "", true, true)) == raw, "migration preserves prior zones, positions, presets and RNG")

func run() -> void:
	test_catalog()
	test_vanguard_and_recovery()
	test_recapture_hand_capacity()
	test_retort_and_dual_ward()
	test_pull_back_and_terrain()
	test_conditions_and_legacy()
	print("TIDEGATE CARDS CHECKS ", checks, " | FAILURES ", failures)
	quit(0 if failures == 0 else 1)
