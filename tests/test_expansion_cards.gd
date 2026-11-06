extends SceneTree
const Model = preload("res://scripts/battle.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const AI = preload("res://scripts/opponent.gd")
const Effects = preload("res://scripts/effect_forecast.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func arena() -> Battle:
	var b := Model.new(2901)
	for cell: Vector2i in b.terrain: b.terrain[cell] = "plain"
	for side: int in [0, 1]:
		b.players[side].discard.append_array(b.players[side].hand); b.players[side].hand.clear()
		b.players[side].mana = 10; b.players[side].max_mana = 10
	b.commander(0).pos = Vector2i(2, 3); b.commander(1).pos = Vector2i(9, 7)
	return b
func troop(b: Battle, kind: String, at: Vector2i, side: int) -> Dictionary:
	var id: int = b._spawn(b.definition(kind), at, side)
	var u: Dictionary = b.get_unit(id)
	u.card = {"uid": b._id(), "card_id": kind, "unit_id": id}
	b.players[side].card_total += 1
	u.moved = false; u.attacked = false; u.summoning = false
	return u
func play(b: Battle, id: String, at: Vector2i) -> Dictionary:
	check(b.add_generated_card(b.active_side, id), "add fixture hand card " + id)
	return b.apply_action({"type": "play", "card_uid": b.players[b.active_side].hand.back().uid, "target": at})
func valid(b: Battle, label: String) -> void:
	check(Snapshot.validate(Snapshot.capture(b)).ok, "card conservation and full snapshot " + label)
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(Snapshot.capture(b), "", true, true))
	var restored: Dictionary = Snapshot.restore(decoded)
	check(restored.ok, "JSON restoration " + label)
	if restored.ok: check(Snapshot.capture(restored.battle) == Snapshot.capture(b), "exact restored state " + label)
func test_zones() -> void:
	var b := arena()
	var source: Dictionary = Snapshot.capture(b)
	check(play(b, "anchor_snare", Vector2i(4, 3)).ok, "trap is played from hand within friendly casting range")
	check(b.traps.size() == 1 and b.players[0].mana == 8 and b.players[0].hand.is_empty(), "hand pays cost and moves to trap zone")
	check(b.players[0].discard.size() == source.players[0].discard.size(), "untriggered trap is not already discarded")
	check(b.visible_traps(1).is_empty() and b.visible_traps(0).size() == 1, "viewer sees only own trap position and identity")
	check(not b.log_lines.back().contains("锚索") and not b.log_lines.back().contains(b.cell_name(Vector2i(4, 3))), "placement log reveals neither name nor coordinates")
	check(play(b, "oath_ward", b.commander(0).pos).ok, "hand can protect a commander")
	check(b.Traps.count(b, 0) == 2, "two combined trap slots")
	check(b.add_generated_card(0, "ember_mine"), "prepare third trap")
	var before: Dictionary = Snapshot.capture(b)
	check(not b.apply_action({"type": "play", "card_uid": b.players[0].hand.back().uid, "target": Vector2i(3, 3)}).ok and Snapshot.capture(b) == before, "full trap zone rejection is atomic")
	valid(b, "two occupied trap slots")
	var raw: Dictionary = Snapshot.capture(b)
	raw.traps.append(raw.traps[0].duplicate(true))
	check(not Snapshot.validate(raw).ok, "duplicate card and trap slot rejected")
	raw = Snapshot.capture(b); raw.traps[0].side = 3
	check(not Snapshot.validate(raw).ok, "invalid trap owner rejected")
	raw = Snapshot.capture(b); raw.traps[1].unit_id = 999999
	check(not Snapshot.validate(raw).ok, "missing protected unit rejected")
	raw = Snapshot.capture(b); raw.traps[0].pos = [0, -1]
	check(not Snapshot.validate(raw).ok, "invalid ground trap cell rejected")
func test_movement() -> void:
	var b := arena()
	var enemy: Dictionary = troop(b, "cavalry", Vector2i(6, 3), 1)
	check(play(b, "anchor_snare", Vector2i(4, 3)).ok, "set snare on the cavalry path")
	b.end_turn()
	check(b.apply_action({"type": "move", "unit_id": enemy.id, "target": Vector2i(3, 3)}).ok, "legal movement can encounter an unknown trap")
	check(enemy.pos == Vector2i(4, 3) and enemy.hp == 4 and enemy.rooted_turns == 1, "intermediate tile interrupts cavalry and inflicts one damage")
	check(b.last_movement_path == [Vector2i(6, 3), Vector2i(5, 3), Vector2i(4, 3)] and enemy.last_move_distance == 2, "animation and charge use only distance actually travelled")
	check(b.traps.is_empty() and b.players[0].discard.back().card_id == "anchor_snare", "trigger consumes trap once")
	check(b.movement_cells(enemy).is_empty() and b.skill_targets(enemy).is_empty(), "root blocks march and cavalry remaneuver during this turn")
	valid(b, "after snare trigger")
	b.end_turn(); b.end_turn()
	check(enemy.rooted_turns == 0 and not b.movement_cells(enemy).is_empty(), "snare expires at the mover's next own turn")
	for weather: String in ["clear", "rain", "sun"]:
		b = arena(); enemy = troop(b, "cavalry", Vector2i(6, 3), 1)
		for x: int in range(3, 7): b.terrain[Vector2i(x, 3)] = "road"
		check(play(b, "ember_mine", Vector2i(4, 3)).ok, "place mine " + weather)
		b.weather = weather; b.weather_remaining = 4 if weather != "clear" else 0
		b.end_turn(); var expected: int = enemy.hp - b.fire_damage(3)
		check(b.apply_action({"type": "move", "unit_id": enemy.id, "target": Vector2i(3, 3)}).ok, "move over mine " + weather)
		check(enemy.hp == expected and enemy.pos == Vector2i(3, 3), "surviving mine victim continues path with weather-adjusted damage " + weather)
		check(not b.players[0].spell_boost_used, "mine does not consume controller's first spell boost")
	b = arena(); enemy = troop(b, "archer", Vector2i(5, 3), 1); enemy.hp = 2
	check(play(b, "ember_mine", Vector2i(4, 3)).ok, "place lethal mine")
	b.end_turn(); check(b.apply_action({"type": "move", "unit_id": enemy.id, "target": Vector2i(3, 3)}).ok, "lethal trapped move resolves")
	check(b.get_unit(enemy.id).is_empty() and b.last_movement_path.back() == Vector2i(4, 3), "dead mover never continues past triggering tile")
	valid(b, "lethal mine")
func test_ward() -> void:
	var b := arena()
	var ally: Dictionary = troop(b, "mage", Vector2i(4, 3), 0)
	var enemy: Dictionary = troop(b, "sword", Vector2i(5, 3), 1)
	check(play(b, "oath_ward", ally.pos).ok, "protect ally from hand")
	var saved: Dictionary = Snapshot.capture(b)
	var restored: Dictionary = Snapshot.restore(JSON.parse_string(JSON.stringify(saved)))
	check(restored.ok, "armed ward survives save")
	if not restored.ok: return
	b = restored.battle; ally = b.get_unit(ally.id); enemy = b.get_unit(enemy.id)
	b.end_turn()
	var damage: int = b.damage_preview(enemy, ally)
	check(b.apply_action({"type": "attack", "unit_id": enemy.id, "target": ally.pos}).ok, "normal attack activates armed ward")
	check(ally.hp == ally.max_hp - maxi(0, damage - 3) and b.traps.is_empty(), "ward shields the actual hit and is consumed")
	check(b.last_combat.target_loss == maxi(0, damage - 3), "native feedback uses resolved shield rather than hidden pre-hit guess")
	valid(b, "ward attack")
	b = arena(); ally = troop(b, "mage", Vector2i(4, 3), 0)
	var guard: Dictionary = troop(b, "spear", Vector2i(4, 4), 0)
	enemy = troop(b, "sword", Vector2i(5, 3), 1)
	check(play(b, "oath_ward", ally.pos).ok, "place ward before guard interception")
	guard.guarding = true; b.end_turn()
	check(b.apply_action({"type": "attack", "unit_id": enemy.id, "target": ally.pos}).ok and b.traps.size() == 1, "ward on protected ally does not trigger when spear intercepts")
	b = arena(); ally = troop(b, "mage", Vector2i(4, 3), 0); enemy = troop(b, "mage", Vector2i(5, 3), 1)
	check(play(b, "oath_ward", ally.pos).ok, "place ward before spell")
	b.end_turn(); check(b.apply_action({"type": "unit_skill", "unit_id": enemy.id, "target": ally.pos}).ok and b.traps.size() == 1, "mage skill bypasses normal-attack ward")
	ally.hp = 0; b._cleanup()
	check(b.traps.is_empty() and b.players[0].discard.back().card_id == "oath_ward", "ward leaves zone if protected unit dies")
	valid(b, "protected unit removed")
func test_spells_and_information() -> void:
	var b := arena()
	var ally: Dictionary = troop(b, "sword", Vector2i(3, 3), 0)
	ally.hp = 2; ally.rooted_turns = 2; ally.moved = true; ally.attacked = true
	check(play(b, "cleanse_root", ally.pos).ok and ally.hp == 3 and ally.rooted_turns == 0 and ally.moved and ally.attacked, "cleanse heals and removes root without refreshing actions")
	b.commander(0).hp = 15
	check(b.add_generated_card(0, "rally_heal"), "group healing is a hand card")
	var action: Dictionary = {"type": "play", "card_uid": b.players[0].hand.back().uid, "target": Vector2i(3, 3)}
	var forecast: Dictionary = Effects.predict(b, action)
	check(forecast.changes.size() == 2 and b.apply_action(action).ok and ally.hp == 5 and b.commander(0).hp == 17, "plus-shaped healing preview matches actual recovery")
	var enemy: Dictionary = troop(b, "spear", Vector2i(4, 3), 1); enemy.shield = 5
	b.players[0].mana = 10
	check(b.add_generated_card(0, "shatter_bolt"), "prepare shattering spell")
	action = {"type": "play", "card_uid": b.players[0].hand.back().uid, "target": enemy.pos}
	forecast = Effects.predict(b, action)
	check(b.apply_action(action).ok and enemy.shield == 0 and enemy.hp == forecast.changes[0].hp_after, "shattering damage is previewed after removing shield")
	check(play(b, "seedwood", Vector2i(3, 4)).ok and b.ground(Vector2i(3, 4)) == "forest", "new local environment changes actual terrain")
	b = arena(); troop(b, "sword", Vector2i(4, 3), 0); b.commander(1).pos = Vector2i(6, 3)
	b.end_turn(); check(play(b, "anchor_snare", Vector2i(5, 3)).ok, "enemy places concealed trap")
	b.end_turn(); b.players[0].mana = 10; check(b.add_generated_card(0, "reveal_traps"), "prepare search lantern")
	var uid: int = b.players[0].hand.back().uid
	var targets: Array[Vector2i] = b.card_targets(uid, 0)
	var decision: Dictionary = AI.choose(b)
	b.traps[0].pos = Vector2i(6, 4); b.traps[0].card.card_id = "ember_mine"
	check(b.card_targets(uid, 0) == targets and AI.choose(b) == decision, "enemy trap position and identity cannot leak through legal targets or AI choice")
	b.traps[0].pos = Vector2i(5, 3)
	check(b.apply_action({"type": "play", "card_uid": uid, "target": Vector2i(4, 3)}).ok and b.traps.is_empty(), "search removes hidden enemy trap inside the plus radius")
	var mana: int = b.players[0].mana
	check(play(b, "reveal_traps", Vector2i(2, 3)).ok and b.players[0].mana == mana - 1, "empty search still spends card and mana")
	valid(b, "searched trap discarded")
func test_trigger_boundaries() -> void:
	var b := arena()
	var enemy: Dictionary = troop(b, "sword", Vector2i(4, 3), 1)
	check(play(b, "anchor_snare", Vector2i(5, 3)).ok, "prepare trap behind enemy")
	check(play(b, "repulse", enemy.pos).ok and enemy.pos == Vector2i(5, 3) and b.traps.size() == 1 and enemy.rooted_turns == 0, "forced knockback onto a trap does not count as stepping")
	b.end_turn()
	check(b.apply_action({"type": "move", "unit_id": enemy.id, "target": Vector2i(4, 3)}).ok and b.traps.size() == 1, "leaving a trap cell does not trigger an entry trap")
	b = arena()
	var ally: Dictionary = troop(b, "sword", Vector2i(4, 3), 0)
	enemy = troop(b, "sword", Vector2i(5, 3), 1)
	check(play(b, "oath_ward", ally.pos).ok, "protect an attacking soldier")
	check(b.apply_action({"type": "attack", "unit_id": ally.id, "target": enemy.pos}).ok and b.traps.size() == 1 and ally.hp < ally.max_hp, "retaliation damage does not trigger the attacker's ward")
	b = arena(); ally = troop(b, "mage", Vector2i(3, 3), 0)
	check(play(b, "oath_ward", ally.pos).ok, "prepare moving ward")
	check(b.apply_action({"type": "move", "unit_id": ally.id, "target": Vector2i(3, 4)}).ok and b.visible_traps(0)[0].pos == Vector2i(3, 4), "unit-anchored ward follows its protected ally")
	valid(b, "ward follows movement")
	b = arena(); ally = troop(b, "cavalry", Vector2i(3, 3), 0)
	check(play(b, "anchor_snare", Vector2i(4, 3)).ok, "prepare friendly path trap")
	check(b.apply_action({"type": "move", "unit_id": ally.id, "target": Vector2i(5, 3)}).ok and b.traps.size() == 1 and ally.hp == ally.max_hp, "friendly movement never activates own trap")
	b = arena(); enemy = troop(b, "cavalry", Vector2i(6, 3), 1)
	check(play(b, "anchor_snare", Vector2i(4, 3)).ok, "prepare remaneuver path")
	b.end_turn()
	check(b.apply_action({"type": "move", "unit_id": enemy.id, "target": Vector2i(5, 3)}).ok and b.traps.size() == 1, "ordinary move stops before trap")
	check(b.apply_action({"type": "unit_skill", "unit_id": enemy.id, "target": Vector2i(3, 3)}).ok and enemy.pos == Vector2i(4, 3) and b.traps.is_empty(), "cavalry skill is intercepted along its actual path")
	b = arena(); check(b.add_generated_card(0, "anchor_snare"), "prepare range rejection")
	var uid: int = b.players[0].hand.back().uid
	var before: Dictionary = Snapshot.capture(b)
	check(not b.apply_action({"type": "play", "card_uid": uid, "target": Vector2i(10, 8)}).ok and Snapshot.capture(b) == before, "out-of-range trap is rejected before charging cost")
	check(b.apply_action({"type": "play", "card_uid": uid, "target": Vector2i(5, 3)}).ok, "three-cell commander casting boundary is accepted")
	check(b.add_generated_card(0, "ember_mine"), "prepare duplicate square rejection")
	before = Snapshot.capture(b)
	check(not b.apply_action({"type": "play", "card_uid": b.players[0].hand.back().uid, "target": Vector2i(5, 3)}).ok and Snapshot.capture(b) == before, "one own ground trap per cell without charging invalid play")
func run() -> void:
	check(Model.DECKS.validate_counts(Model.DECKS.find("ambush").cards, Model.CATALOG.cards).is_empty(), "new preset contains thirty legal cards")
	for id: String in Snapshot.EXPANSION_CARDS: check(not Model.CATALOG.find(id).is_empty(), "new original card exists " + id)
	test_zones(); test_movement(); test_ward(); test_spells_and_information(); test_trigger_boundaries()
	var historical: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign_v028_selfplay.json")).games[0].final
	var migrated: Dictionary = Snapshot.restore(historical)
	check(migrated.ok and migrated.battle.traps.is_empty(), "actual pre-expansion battle snapshot migrates without adding traps")
	if migrated.ok: check(migrated.battle.rng.state == str(historical.rng_state).to_int() and migrated.battle.turn == int(historical.turn), "legacy migration preserves RNG and turn")
	print("EXPANSION CARD CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
