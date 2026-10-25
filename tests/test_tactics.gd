extends SceneTree

const BattleModel = preload("res://scripts/battle.gd")
const EnemyAI = preload("res://scripts/opponent.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func fresh(deck_id: String = "balanced") -> Battle:
	var game: Battle = BattleModel.new(14, "classic_greenwood", "warden", "pyromancer", deck_id, deck_id)
	game.terrain.clear()
	game.players[0].mana = 10
	game.players[0].max_mana = 10
	return game

func take(game: Battle, card_id: String) -> Dictionary:
	for card: Dictionary in game.players[0].hand:
		if card.card_id == card_id: return card
	for card: Dictionary in game.players[0].deck:
		if card.card_id == card_id:
			game.players[0].deck.erase(card)
			game.players[0].hand.append(card)
			return card
	game.add_generated_card(0, card_id)
	for card: Dictionary in game.players[0].hand:
		if card.card_id == card_id: return card
	return {}

func cast(game: Battle, card_id: String, cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var card: Dictionary = take(game, card_id)
	if card.is_empty(): return {"ok": false}
	return game.apply_action({"type": "play", "card_uid": card.uid, "target": cell})

func troop(game: Battle, kind: String, cell: Vector2i, side: int) -> Dictionary:
	var id: int = game._spawn(game.definition(kind), cell, side)
	var unit: Dictionary = game.get_unit(id)
	unit.summoning = false
	unit.moved = false
	unit.attacked = false
	return unit

func run() -> void:
	for deck: Dictionary in BattleModel.DECKS.decks:
		var count: int = 0
		var valid: bool = true
		for card_id: String in deck.cards:
			count += int(deck.cards[card_id])
			if BattleModel.CATALOG.find(card_id).is_empty() or card_id == "initiative": valid = false
		check(count == 30 and valid, "valid 30-card deck: " + deck.id)
		var game: Battle = fresh(deck.id)
		check(game.deck_size == 30 and game.players[0].card_total == 30 and game.players[1].card_total == 31, "deck and generated-card counts: " + deck.id)
	test_repulse()
	test_root()
	test_dispel_exchange()
	test_onslaught_and_weather()
	for deck: Dictionary in BattleModel.DECKS.decks:
		for map: Dictionary in BattleModel.MAPS.maps:
			var game: Battle = BattleModel.new(319, map.id, "warden", "grove", deck.id, deck.id)
			var steps: int = 0
			while game.winner == -1 and steps < 1200:
				var result: Dictionary = game.apply_action(EnemyAI.choose(game))
				if not result.ok:
					check(false, "legal AI tactics: " + result.message)
					break
				steps += 1
			check(game.winner != -1, "deck-map match terminates: " + deck.id + "/" + map.id)
	print("TACTICS CHECKS: %d | FAILURES: %d | DECK/MAP MATCHES: 9" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_repulse() -> void:
	var game: Battle = fresh("assault")
	var enemy: Dictionary = troop(game, "sword", Vector2i(3, 3), 1)
	check(cast(game, "repulse", enemy.pos).ok, "repulse accepts enemy troop")
	check(enemy.pos == Vector2i(3, 2) and enemy.hp == 3, "repulse moves away from friendly commander and deals two")
	var blocked: Battle = fresh("assault")
	var target: Dictionary = troop(blocked, "sword", Vector2i(3, 3), 1)
	blocked.terrain[Vector2i(3, 2)] = "mountain"
	check(cast(blocked, "repulse", target.pos).ok, "blocked repulse still resolves")
	check(target.pos == Vector2i(3, 3) and target.hp == 2, "collision adds damage without illegal position")
	var invalid: Battle = fresh("assault")
	var card: Dictionary = take(invalid, "repulse")
	var before: String = var_to_str([invalid.units, invalid.players])
	check(not invalid.apply_action({"type": "play", "card_uid": card.uid, "target": invalid.commander(1).pos}).ok, "repulse excludes commanders")
	check(before == var_to_str([invalid.units, invalid.players]), "invalid repulse is atomic")

func test_root() -> void:
	var game: Battle = fresh("bastion")
	var enemy: Dictionary = troop(game, "cavalry", Vector2i(3, 3), 1)
	troop(game, "sword", Vector2i(3, 4), 0)
	check(cast(game, "frostbind", enemy.pos).ok, "frostbind applies")
	game.end_turn()
	check(enemy.rooted_turns == 1 and game.movement_cells(enemy).is_empty(), "root prevents next own-turn movement")
	check(not game.attack_targets(enemy).is_empty(), "root allows attack")
	game.end_turn()
	game.end_turn()
	check(enemy.rooted_turns == 0 and not game.movement_cells(enemy).is_empty(), "root expires before following own turn")

func test_dispel_exchange() -> void:
	var game: Battle = fresh("bastion")
	var foe: Dictionary = game.commander(1)
	foe.pos = game.commander(0).pos + Vector2i.UP * 3
	foe.shield = 5
	check(cast(game, "dispel", foe.pos).ok, "dispel targets shielded enemy commander")
	check(foe.shield == 0 and foe.hp == 20, "dispel strips shield without damaging health")
	var swap_game: Battle = fresh("assault")
	var ally: Dictionary = troop(swap_game, "archer", Vector2i(1, 4), 0)
	ally.rooted_turns = 2
	ally.moved = true
	ally.attacked = true
	var leader: Dictionary = swap_game.commander(0)
	var old_leader: Vector2i = leader.pos
	var old_ally: Vector2i = ally.pos
	check(cast(swap_game, "exchange", ally.pos).ok, "exchange accepts rooted ally")
	check(leader.pos == old_ally and ally.pos == old_leader, "exchange swaps positions")
	check(ally.moved and ally.attacked and ally.rooted_turns == 2, "exchange preserves action and status state")
	check(swap_game.unit_at(old_ally).id == leader.id and swap_game.unit_at(old_leader).id == ally.id, "exchange preserves one-unit-per-cell")

func test_onslaught_and_weather() -> void:
	var game: Battle = fresh("assault")
	var ally: Dictionary = troop(game, "sword", Vector2i(3, 3), 0)
	var foe: Dictionary = troop(game, "sword", Vector2i(3, 2), 1)
	ally.moved = true
	ally.attacked = true
	check(cast(game, "onslaught", ally.pos).ok, "onslaught accepts spent attacker")
	check(not ally.attacked and ally.moved and game.movement_cells(ally).is_empty(), "onslaught restores attack only")
	check(game.apply_action({"type": "attack", "unit_id": ally.id, "target": foe.pos}).ok, "extra attack resolves")
	var clear: Battle = fresh("assault")
	var card: Dictionary = take(clear, "clear_skies")
	var before: String = var_to_str(clear.players)
	check(not clear.apply_action({"type": "play", "card_uid": card.uid, "target": Vector2i(-1, -1)}).ok, "cannot clear already clear sky")
	check(before == var_to_str(clear.players), "invalid clear sky is atomic")
	clear.weather = "rain"
	clear.weather_remaining = 4
	check(clear.apply_action({"type": "play", "card_uid": card.uid, "target": Vector2i(-1, -1)}).ok, "clear sky removes weather")
	check(clear.weather == "clear" and clear.weather_remaining == 0, "weather modifiers and timer removed")
