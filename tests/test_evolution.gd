extends SceneTree

const BattleModel = preload("res://scripts/battle.gd")
const EnemyAI = preload("res://scripts/opponent.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")
	create_timer(180).timeout.connect(func() -> void: push_error("Evolution test timed out"); quit(2))

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func fixture(hero_id: String = "warden", map_id: String = "classic_greenwood") -> Battle:
	var game: Battle = BattleModel.new(10, map_id, hero_id, "pyromancer")
	game.players[0].mana = 10
	game.players[0].max_mana = 10
	return game

func give(game: Battle, card_id: String) -> Dictionary:
	for instance: Dictionary in game.players[0].hand:
		if instance.card_id == card_id: return instance
	for zone_name: String in ["deck", "discard"]:
		for instance: Dictionary in game.players[0][zone_name]:
			if instance.card_id == card_id:
				game.players[0][zone_name].erase(instance)
				game.players[0].hand.append(instance)
				return instance
	return {}

func play(game: Battle, card_id: String, cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var instance: Dictionary = give(game, card_id)
	check(not instance.is_empty(), "fixture contains " + card_id)
	if instance.is_empty(): return {"ok": false}
	game.players[0].mana = 10
	return game.apply_action({"type": "play", "card_uid": instance.uid, "target": cell})

func troop(game: Battle, card_id: String, cell: Vector2i, side: int = 0) -> Dictionary:
	var id: int = game._spawn(game.definition(card_id), cell, side)
	var unit: Dictionary = game.get_unit(id)
	unit.summoning = false
	unit.moved = false
	unit.attacked = false
	return unit

func run() -> void:
	test_maps_and_paths()
	test_geography_and_classes()
	test_heroes()
	test_environments()
	test_initiative()
	var reports: Array[Dictionary] = []
	for map: Dictionary in BattleModel.MAPS.maps:
		for hero_index: int in range(BattleModel.HEROES.heroes.size()):
			var blue_hero: String = BattleModel.HEROES.heroes[hero_index].id
			var red_hero: String = BattleModel.HEROES.heroes[(hero_index + 1) % 3].id
			var game: Battle = BattleModel.new(100 + hero_index, map.id, blue_hero, red_hero)
			var steps: int = 0
			var skills_used: int = 0
			while game.winner == -1 and steps < 1200:
				var action: Dictionary = EnemyAI.choose(game)
				var result: Dictionary = game.apply_action(action)
				if not result.ok:
					check(false, "AI illegal action in %s/%s: %s" % [map.id, blue_hero, result.message])
					break
				if action.type == "hero": skills_used += 1
				steps += 1
			check(game.winner != -1, "complete map/hero match: " + map.id + "/" + blue_hero)
			reports.append({"map": map.id, "blue_hero": blue_hero, "red_hero": red_hero, "winner": game.winner, "turn": game.turn, "actions": steps, "skills": skills_used})
	print("EVOLUTION CHECKS: %d | FAILURES: %d | MAP/HERO MATCHES: %d" % [checks, failures, reports.size()])
	var file: FileAccess = FileAccess.open("res://docs/evolution-matches.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(reports, "\t"))
	quit(0 if failures == 0 else 1)

func test_maps_and_paths() -> void:
	check(BattleModel.MAPS.available().size() == 6, "six authored maps")
	for map: Dictionary in BattleModel.MAPS.maps:
		var game: Battle = fixture("warden", map.id)
		var symmetric: bool = true
		for y: int in range(game.height):
			for x: int in range(game.width):
				if game.ground(Vector2i(x, y)) != game.ground(Vector2i(game.width - 1 - x, game.height - 1 - y)): symmetric = false
		check(symmetric, "rotationally fair terrain: " + map.id)
		var distances: Dictionary = game.walk_distances(game.commander(0).pos, {"kind": "sword"})
		var reachable: bool = false
		for direction: Vector2i in game.DIRECTIONS:
			if distances.has(game.commander(1).pos + direction): reachable = true
		check(reachable, "melee route connects commanders: " + map.id)
	var river: Battle = fixture("warden", "classic_rivergate")
	check(not river.passable(Vector2i(3, 2)) and river.passable(Vector2i(2, 2)), "river blocks and bridge passes")
	var game: Battle = fixture()
	game.terrain.clear()
	var cavalry: Dictionary = troop(game, "cavalry", Vector2i(1, 4))
	game.terrain[Vector2i(2, 4)] = "forest"
	check(game.movement_cost(cavalry, Vector2i(2, 4)) == 3, "cavalry forest costs three")
	check(game.walk_distances(cavalry.pos, cavalry)[Vector2i(2, 4)] == 3, "weighted path uses entry costs")
	check(game.movement_path(cavalry, Vector2i(2, 4)).size() == 2, "weighted path records one physical step")
	check(game.apply_action({"type": "move", "unit_id": cavalry.id, "target": Vector2i(2, 4)}).ok, "weighted move succeeds")
	check(cavalry.last_move_distance == 1, "terrain cost does not fake three-cell charge")
	game.terrain[cavalry.pos] = "road"
	check(game.movement_allowance(cavalry) == 5, "road grants cavalry movement")
	game.weather = "rain"
	check(game.movement_cost(cavalry, Vector2i(3, 4)) == 2, "rain slows cavalry off-road")
	check(game.movement_cost(cavalry, cavalry.pos) == 1, "road avoids rain penalty")
	game.weather = "snow"
	check(game.movement_allowance(cavalry) == 4, "snow combines with road bonus")
	var foot: Dictionary = troop(game, "sword", Vector2i(5, 4))
	game.terrain[Vector2i(5, 3)] = "forest"
	check(game.movement_cost(foot, Vector2i(5, 3)) == 1, "infantry specializes in forests")
	check(game.movement_allowance(foot) == 1, "snow movement floor")

func test_geography_and_classes() -> void:
	var game: Battle = fixture()
	game.terrain.clear()
	var archer: Dictionary = troop(game, "archer", Vector2i(4, 4))
	var enemy: Dictionary = troop(game, "sword", Vector2i(4, 1), 1)
	game.terrain[archer.pos] = "hill"
	check(game.attack_range(archer) == 4, "high ground increases ranged reach")
	check(game.damage_breakdown(archer, enemy).elevation == 1, "high ground damage bonus")
	game.weather = "fog"
	check(game.attack_range(archer) == 2 and not game.attack_targets(archer).has(enemy.pos), "fog caps high-ground range")
	game.weather = "clear"
	enemy.pos = Vector2i(4, 3)
	check(game.damage_breakdown(archer, enemy).close_penalty == 1, "archer has close-range weakness")
	var spear: Dictionary = troop(game, "spear", Vector2i(1, 2), 1)
	check(game.damage_breakdown(archer, spear).stance == 1, "stationary spear formation")
	spear.last_move_distance = 1
	check(game.damage_breakdown(archer, spear).stance == 0, "moving breaks spear formation")
	var mage: Dictionary = troop(game, "mage", Vector2i(0, 2))
	check(game.damage_breakdown(mage, spear).pierce == 1, "mage pierces one defense")
	var cavalry: Dictionary = troop(game, "cavalry", Vector2i(2, 3))
	cavalry.last_move_distance = 3
	check(game.damage_breakdown(cavalry, enemy).charge == 1, "three physical steps grant charge")
	game.active_side = 1
	check(game.damage_breakdown(cavalry, enemy).charge == 0, "charge does not persist into enemy counters")
	game.active_side = 0
	game.terrain[enemy.pos] = "forest"
	game.weather = "snow"
	check(game.terrain_defense(enemy) == 2, "snow strengthens forest defense")
	game.weather = "clear"
	game.terrain[archer.pos] = "ruins"
	archer.hp = 1
	game.end_turn()
	game.end_turn()
	check(archer.hp == 2, "ruins heal occupying unit on own turn")

func test_heroes() -> void:
	var game: Battle = fixture()
	var guard: Dictionary = troop(game, "sword", game.commander(0).pos + Vector2i.UP)
	check(game.aura_defense(guard) == 1 and game.aura_defense(game.commander(0)) == 0, "warden aura affects adjacent other allies")
	guard.hp = 1
	var before_mana: int = game.players[0].mana
	check(game.apply_action({"type": "hero", "target": guard.pos}).ok, "warden skill accepts friendly target")
	check(guard.hp == 3 and guard.shield == 3, "blessing heals and shields")
	check(game.players[0].mana == before_mana - 2 and game.players[0].skill_cooldown == 3, "hero skill pays and starts cooldown")
	var before: String = var_to_str([game.players, game.units])
	check(not game.apply_action({"type": "hero", "target": guard.pos}).ok, "cooldown rejects repeat activation")
	check(before == var_to_str([game.players, game.units]), "rejected hero action is atomic")
	game.end_turn()
	game.end_turn()
	check(game.players[0].skill_cooldown == 2, "cooldown ticks only on owner's turn")
	game.end_turn()
	game.end_turn()
	check(game.players[0].skill_cooldown == 1, "cooldown still unavailable after two own starts")
	game.end_turn()
	game.end_turn()
	check(game.players[0].skill_cooldown == 0, "cooldown becomes ready on third own start")
	var pyro: Battle = fixture("pyromancer")
	pyro.commander(1).pos = pyro.commander(0).pos + Vector2i.UP * 3
	check(pyro.spell_damage(pyro.definition("bolt"), 0) == 5, "first offensive spell gets pyromancer bonus")
	check(play(pyro, "bolt", pyro.commander(1).pos).ok, "pyromancer plays bolt")
	check(pyro.commander(1).hp == 15, "pyromancer bonus resolves")
	check(pyro.spell_damage(pyro.definition("nova"), 0) == 3, "second spell loses first-spell bonus")
	pyro.players[0].mana = 10
	check(pyro.apply_action({"type": "hero", "target": pyro.commander(1).pos}).ok, "firestrike targets enemy")
	check(pyro.commander(1).hp == 11, "active firestrike does not consume extra passive bonus")
	var grove: Battle = fixture("grove")
	var ally: Dictionary = troop(grove, "sword", Vector2i(2, 4))
	grove.terrain[ally.pos] = "forest"
	ally.hp = 1
	grove.end_turn()
	grove.end_turn()
	check(ally.hp == 2, "grove heals forest allies")
	grove.players[0].mana = 10
	var hand_before: int = grove.players[0].hand.size()
	check(grove.apply_action({"type": "hero", "target": Vector2i(-1, -1)}).ok, "renewal uses commander-centered area")
	check(ally.hp == 4 and grove.players[0].hand.size() == hand_before + 1, "renewal heals army and draws")

func test_environments() -> void:
	var game: Battle = fixture()
	check(play(game, "rain").ok, "environment card plays without board target")
	check(game.weather == "rain" and game.weather_remaining == 4, "weather state and duration")
	check(game.fire_damage(4) == 3, "rain suppresses fire damage")
	game.end_turn()
	check(game.weather_remaining == 3, "opponent turn counts toward weather")
	game.end_turn()
	check(play(game, "fog").ok and game.weather == "fog" and game.weather_remaining == 4, "new weather replaces old and resets duration")
	for index: int in range(4): game.end_turn()
	check(game.weather == "clear" and game.weather_remaining == 0, "weather expires after four turn transitions")
	check(play(game, "sun").ok and game.fire_damage(4) == 5, "sun boosts fire")
	var medic: Dictionary = troop(game, "healer", Vector2i(1, 4))
	medic.hp = 1
	game.end_turn()
	game.end_turn()
	check(medic.hp == 3, "sun improves medic healing")
	game.weather = "clear"
	var leader: Dictionary = game.commander(0)
	check(play(game, "rampart", leader.pos).ok and game.ground(leader.pos) == "fort", "terrain card creates persistent fort")
	check(game.terrain_defense(leader) == 2, "fort defense is live")
	check(play(game, "trail", leader.pos).ok and game.ground(leader.pos) == "road", "road card can replace fort")
	var river: Battle = fixture("warden", "classic_rivergate")
	var bridge_unit: Dictionary = troop(river, "sword", Vector2i(2, 3))
	var card: Dictionary = give(river, "rampart")
	var before: String = var_to_str([river.players, river.units, river.terrain])
	check(not river.apply_action({"type": "play", "card_uid": card.uid, "target": bridge_unit.pos}).ok, "fort cannot destroy bridge")
	check(before == var_to_str([river.players, river.units, river.terrain]), "illegal terraforming leaves map and resources unchanged")

func test_initiative() -> void:
	var game: Battle = fixture()
	var coin: Dictionary = {}
	for instance: Dictionary in game.players[1].hand:
		if instance.card_id == "initiative": coin = instance
	check(not coin.is_empty(), "second player receives one initiative card")
	check(game.players[1].card_total == 31 and game.players[0].card_total == 30, "generated card tracked separately from deck size")
	game.end_turn()
	check(game.apply_action({"type": "play", "card_uid": coin.uid, "target": Vector2i(-1, -1)}).ok, "initiative card is playable")
	check(game.players[1].mana == 2 and game.players[1].max_mana == 1, "initiative grants temporary mana without changing curve")
	check(game.hand_card(1, coin.uid).is_empty(), "initiative is consumed once")
	game.end_turn()
	game.end_turn()
	check(game.players[1].mana == 2 and game.players[1].max_mana == 2, "temporary mana expires by next own turn")
