extends SceneTree
const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const Tactics = preload("res://scripts/tactical_ai.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func fresh() -> Battle:
	var battle = Model.new(1319, "rivergate", "warden", "warden")
	for cell: Vector2i in battle.terrain: battle.terrain[cell] = "plain"
	for player: Dictionary in battle.players: player.hand.clear(); player.mana = 0
	battle.commander(0).pos = Vector2i(4, 7); battle.commander(1).pos = Vector2i(4, 0)
	return battle
func recruit(battle: Battle, cell: Vector2i) -> Dictionary:
	var unit: Dictionary = battle.definition("mage").duplicate(true)
	unit.merge({"id": -1, "kind": "mage", "side": 0, "pos": cell, "shield": 0, "last_move_distance": 0})
	return unit
func test_deployment() -> void:
	var battle: Battle = fresh()
	Fixture.troop(battle, "mage", Vector2i(4, 3), 1)
	battle.players[0].mana = 4; battle.add_generated_card(0, "mage")
	var before: String = var_to_str([battle.units, battle.players, battle.terrain, battle.rng.state])
	var threats: Dictionary = Tactics.prepare(battle)
	check(Tactics.exposure(battle, recruit(battle, Vector2i(4, 6)), threats) > Tactics.exposure(battle, recruit(battle, Vector2i(4, 8)), threats), "newborn frontline has greater next-turn exposure than rear deployment")
	var action: Dictionary = AI.choose(battle)
	check(action.type == "play" and action.target != Vector2i(4, 6), "deploy a fragile recruit outside the obvious enemy advance and shot")
	check(before == var_to_str([battle.units, battle.players, battle.terrain, battle.rng.state]), "risk evaluation does not move or refresh actual enemy troops")
	check(battle.apply_action(action).ok and battle.unit_at(action.target).summoning, "safer deployment still respects real newborn rules")
func test_paths_and_status() -> void:
	var battle: Battle = fresh()
	var enemy: Dictionary = Fixture.troop(battle, "sword", Vector2i(4, 3), 1)
	enemy.summoning = true; enemy.moved = true; enemy.attacked = true; enemy.rooted_turns = 1
	var prepared: Dictionary = Tactics.prepare(battle)
	var entry: Dictionary = prepared.enemies[1] if prepared.enemies[0].unit.kind == "commander" else prepared.enemies[0]
	check(entry.origins.has(Vector2i(4, 5)), "newborn and one-turn root wear off before the coming enemy action")
	enemy.rooted_turns = 2
	prepared = Tactics.prepare(battle)
	entry = prepared.enemies[1] if prepared.enemies[0].unit.kind == "commander" else prepared.enemies[0]
	check(entry.origins.size() == 1, "a root still active next turn prevents forecast movement")
	enemy.rooted_turns = 0
	for x: int in range(battle.width): battle.terrain[Vector2i(x, 4)] = "mountain"
	prepared = Tactics.prepare(battle)
	check(Tactics.exposure(battle, recruit(battle, Vector2i(4, 6)), prepared) == 0, "melee threat cannot cross an impassable wall")
	battle.terrain[Vector2i(4, 4)] = "hill"
	prepared = Tactics.prepare(battle)
	check(Tactics.exposure(battle, recruit(battle, Vector2i(4, 6)), prepared) == 0, "two-cost hill prevents a two-movement unit from reaching the firing tile")
	battle.terrain[Vector2i(4, 4)] = "plain"
	check(Tactics.exposure(battle, recruit(battle, Vector2i(4, 6)), Tactics.prepare(battle)) > 0, "opening a reachable gap creates a real next-turn threat")
func test_hidden_information() -> void:
	var battle: Battle = fresh()
	Fixture.troop(battle, "mage", Vector2i(4, 3), 1)
	battle.players[0].mana = 4; battle.add_generated_card(0, "mage")
	var before: Dictionary = AI.choose(battle)
	battle.players[1].hand = [{"card_id": "nova", "uid": 99999}]
	battle.players[1].deck.reverse(); battle.players[0].deck.reverse()
	check(AI.choose(battle) == before, "unseen enemy cards and both deck orders do not alter tactical choice")
func test_healer_action_budget() -> void:
	var battle: Battle = fresh()
	var healer: Dictionary = Fixture.troop(battle, "healer", Vector2i(4, 6), 0); healer.moved = true
	var ally: Dictionary = Fixture.troop(battle, "archer", Vector2i(3, 6), 0); ally.hp = 1; ally.moved = true; ally.attacked = true
	Fixture.troop(battle, "spear", Vector2i(4, 4), 1)
	battle.players[0].mana = 1
	var action: Dictionary = AI.choose(battle)
	check(action.type == "unit_skill" and action.unit_id == healer.id and action.target == ally.pos, "healer restores three health instead of consuming its action on one damage")
	check(battle.apply_action(action).ok and ally.hp == 4 and healer.attacked and battle.players[0].mana == 0, "support decision pays mana and consumes the actual unit action")
func test_vacated_cell() -> void:
	var battle: Battle = fresh()
	for cell: Vector2i in battle.terrain: battle.terrain[cell] = "mountain"
	for cell: Vector2i in [Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 5)]: battle.terrain[cell] = "plain"
	var ally: Dictionary = Fixture.troop(battle, "healer", Vector2i(4, 5), 0)
	var enemy: Dictionary = Fixture.troop(battle, "sword", Vector2i(4, 3), 1)
	var candidate: Dictionary = ally.duplicate(true)
	candidate.pos = Vector2i(5, 5); candidate.last_move_distance = 1
	var before: String = var_to_str([battle.units, battle.players, battle.terrain, battle.rng.state])
	var predicted: float = Tactics.exposure(battle, candidate, Tactics.prepare(battle, 1.0))
	check(predicted > 0, "moving aside forecasts the enemy entering the vacated tile")
	check(before == var_to_str([battle.units, battle.players, battle.terrain, battle.rng.state]), "candidate occupancy does not mutate the real board")
	check(battle.apply_action({"type":"move", "unit_id":ally.id,"target":candidate.pos}).ok, "the forecast move is actually legal")
	check(predicted == Tactics.exposure(battle, ally, Tactics.prepare(battle, 1.0)), "hypothetical move agrees with fresh risk after executing that move")
	battle.end_turn()
	check(battle.apply_action({"type":"move","unit_id":enemy.id,"target":Vector2i(4, 5)}).ok, "enemy really can enter the vacated tile")
	var health: int = ally.hp
	check(battle.apply_action({"type":"attack","unit_id":enemy.id,"target":ally.pos}).ok and ally.hp == health - 3, "the previously missed route deals real three-point damage")
func test_candidate_cache_occupancy() -> void:
	var battle: Battle = fresh()
	for cell: Vector2i in battle.terrain: battle.terrain[cell] = "mountain"
	for cell: Vector2i in [Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(3, 5), Vector2i(5, 5)]: battle.terrain[cell] = "plain"
	var gatekeeper: Dictionary = Fixture.troop(battle, "healer", Vector2i(4, 4), 0)
	var rear: Dictionary = Fixture.troop(battle, "healer", Vector2i(3, 5), 0)
	Fixture.troop(battle, "sword", Vector2i(4, 3), 1)
	var candidate_a: Dictionary = gatekeeper.duplicate(true)
	var candidate_b: Dictionary = rear.duplicate(true)
	candidate_a.pos = Vector2i(5, 5); candidate_b.pos = candidate_a.pos
	candidate_a.last_move_distance = 2; candidate_b.last_move_distance = 2
	var context: Dictionary = Tactics.prepare(battle, 1.0)
	var opened: float = Tactics.exposure(battle, candidate_a, context)
	var blocked: float = Tactics.exposure(battle, candidate_b, context)
	check(opened > 0 and blocked == 0, "same stats and destination differ when only one move opens the chokepoint")
	check(Tactics.exposure(battle, candidate_a, context) == opened, "cached candidate risk retains its own vacated-cell context")
	var reverse: Dictionary = Tactics.prepare(battle, 1.0)
	check(Tactics.exposure(battle, candidate_b, reverse) == blocked and Tactics.exposure(battle, candidate_a, reverse) == opened, "candidate enumeration order cannot change risk")
func test_occupied_destination() -> void:
	var battle: Battle = fresh()
	for cell: Vector2i in battle.terrain: battle.terrain[cell] = "mountain"
	for cell: Vector2i in [Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 4), Vector2i(5, 5)]: battle.terrain[cell] = "plain"
	var ally: Dictionary = Fixture.troop(battle, "healer", Vector2i(5, 4), 0)
	var enemy: Dictionary = Fixture.troop(battle, "sword", Vector2i(4, 3), 1)
	var candidate: Dictionary = ally.duplicate(true)
	candidate.pos = Vector2i(4, 4); candidate.last_move_distance = 1
	var before: String = var_to_str([battle.units, battle.players, battle.terrain, battle.rng.state])
	var projected: Array[Vector2i] = battle.movement_cells(enemy, {ally.pos: false, candidate.pos: true})
	check(not projected.has(Vector2i(4, 5)) and not projected.has(candidate.pos), "projected enemy movement cannot walk through the newly occupied chokepoint")
	var predicted: float = Tactics.exposure(battle, candidate, Tactics.prepare(battle, 1.0))
	check(before == var_to_str([battle.units, battle.players, battle.terrain, battle.rng.state]), "occupied-destination forecast leaves actual units, cards, terrain and RNG untouched")
	check(battle.apply_action({"type":"move", "unit_id":ally.id, "target":candidate.pos}).ok, "occupying the forecast chokepoint is a legal move")
	check(projected == battle.movement_cells(enemy), "forecast reachable cells match the real board after occupying the chokepoint")
	check(predicted == Tactics.exposure(battle, ally, Tactics.prepare(battle, 1.0)), "occupied-destination risk agrees with risk after the real move")
func test_movement_budget_search() -> void:
	for map: Dictionary in Model.MAPS.available():
		var battle = Model.new(1323, map.id, "warden", "pyromancer")
		for weather: String in ["clear", "rain", "snow", "fog"]:
			battle.weather = weather
			for kind: String in ["sword", "spear", "cavalry", "archer", "mage", "healer"]:
				var unit: Dictionary = battle.commander(0).duplicate(true)
				unit.kind = kind; unit.move = battle.definition(kind).move
				unit.moved = false; unit.attacked = false; unit.summoning = false
				var all_distances: Dictionary = battle.walk_distances(unit.pos, unit)
				var expected: Array[Vector2i] = []
				for cell: Vector2i in all_distances:
					if cell != unit.pos and int(all_distances[cell]) <= battle.movement_allowance(unit): expected.append(cell)
				check(battle.movement_cells(unit) == expected, "bounded movement preserves weighted reach and order: %s/%s/%s" % [map.id, weather, kind])

func test_order_footprints() -> void:
	var battle := fresh()
	Fixture.troop(battle, "mage", Vector2i(6, 4), 1)
	var anchor := Fixture.troop(battle, "archer", Vector2i(5, 4), 0)
	var mover := Fixture.troop(battle, "archer", Vector2i(4, 4), 0)
	var foe: Dictionary = battle.players[1]
	foe.deck_id = "glassroad_edict"
	foe.deck_definition = Model.DECKS.find(foe.deck_id).duplicate(true)
	foe.max_mana = 4
	var models: Array = Tactics.prepare(battle).formations
	var rain: Array[Dictionary] = []
	for model: Dictionary in models:
		if model.id == "rain_notch": rain.append(model)
	check(rain.size() == 1 and rain[0].radius == 1, "the affordable three-mana order has its printed row")
	if rain.is_empty(): return
	check(not models.any(func(m: Dictionary) -> bool: return m.id in ["glass_treaty", "crossroads_whistle", "hinge_order"]), "unaffordable and single-target orders have no group risk")
	var grouped := Tactics.FormationRisk.exposure(battle, mover, mover.pos, rain, mover.pos)
	var vacated := Tactics.FormationRisk.exposure(battle, mover, Vector2i(3, 4), rain, mover.pos)
	var diagonal := Tactics.FormationRisk.exposure(battle, mover, Vector2i(4, 5), rain, mover.pos)
	check(grouped > 0.0 and vacated == 0.0 and diagonal == 0.0, "a hostile order needs an occupied center on its printed row; vacating the middle tile breaks the pair")
	foe.max_mana = 6
	models = Tactics.prepare(battle).formations
	rain.clear()
	for model: Dictionary in models:
		if model.id == "rain_notch": rain.append(model)
	check(rain.size() == 1 and rain[0].radius == 2 and Tactics.FormationRisk.exposure(battle, mover, Vector2i(3, 4), rain, mover.pos) > 0.0,
		"next turn's seventh mana extends the hostile row to two without spending mana or changing the card")
	foe.max_mana = 9
	battle.terrain[anchor.pos] = "fort"
	var terrain_model: Array[Dictionary] = []
	for model: Dictionary in Tactics.prepare(battle).formations:
		if model.id == "scour_fulcrum": terrain_model.append(model)
	check(terrain_model.size() == 1, "known terrain-breaking formation is affordable")
	if terrain_model.is_empty(): return
	check(Tactics.FormationRisk.exposure(battle, mover, mover.pos, terrain_model, mover.pos) == 0.0, "a plain beside a fort does not expose its occupant to terrain-only damage")
	var ridge := Vector2i(4, 5)
	battle.terrain[ridge] = "hill"
	var future := Tactics.FormationRisk.exposure(battle, mover, ridge, terrain_model, mover.pos)
	check(future > 0.0, "stepping onto a nearby hill puts both troops at risk")
	check(battle.apply_action({"type":"move", "unit_id":mover.id, "target":ridge}).ok, "play the forecast move")
	terrain_model.clear()
	for model: Dictionary in Tactics.prepare(battle).formations:
		if model.id == "scour_fulcrum": terrain_model.append(model)
	check(future == Tactics.FormationRisk.exposure(battle, mover, ridge, terrain_model, ridge), "hypothetical terrain exposure agrees with the resolved move")
	foe.discard.append({"card_id":"glass_treaty", "uid":900})
	check(not Tactics.prepare(battle).formations.any(func(m: Dictionary) -> bool: return m.id == "glass_treaty"), "the last publicly spent copy stops affecting spacing")
	foe.deck_id = "custom"
	foe.discard.clear()
	foe.hand = [{"card_id":"glass_treaty", "uid":901}]
	check(Tactics.prepare(battle).formations.is_empty(), "an unseen custom order cannot change the defender's prediction")
	foe.discard.append({"card_id":"rain_notch", "uid":902})
	check(Tactics.prepare(battle).formations.any(func(m: Dictionary) -> bool: return m.id == "rain_notch"), "a publicly seen custom order can inform later formations")

func run() -> void:
	test_deployment(); test_paths_and_status(); test_hidden_information(); test_healer_action_budget(); test_vacated_cell(); test_candidate_cache_occupancy(); test_occupied_destination(); test_movement_budget_search()
	test_order_footprints()
	print("TACTICAL AI CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
