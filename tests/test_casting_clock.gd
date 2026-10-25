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

func fresh(hero: String = "warden", seconds: float = 90.0) -> Battle:
	var game: Battle = BattleModel.new(42, "greenwood", hero, "pyromancer", "balanced", "balanced", seconds)
	game.terrain.clear()
	game.players[0].mana = 10
	game.players[0].max_mana = 10
	game.commander(0).pos = Vector2i(1, 8)
	game.commander(1).pos = Vector2i(10, 1)
	return game

func give(game: Battle, card_id: String) -> Dictionary:
	for card: Dictionary in game.players[0].hand:
		if card.card_id == card_id: return card
	for card: Dictionary in game.players[0].deck:
		if card.card_id == card_id:
			game.players[0].deck.erase(card)
			game.players[0].hand.append(card)
			return card
	game.add_generated_card(0, card_id)
	return game.players[0].hand.back()

func troop(game: Battle, kind: String, cell: Vector2i, side: int = 0) -> Dictionary:
	return game.get_unit(game._spawn(game.definition(kind), cell, side))

func run() -> void:
	test_reach()
	test_local_heroes_and_exchange()
	test_clock()
	print("CASTING/CLOCK CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_reach() -> void:
	var game: Battle = fresh()
	var target: Dictionary = game.commander(1)
	var card: Dictionary = give(game, "bolt")
	var before: String = var_to_str([game.players, game.units, game.terrain])
	check(not game.card_targets(card.uid, 0).has(target.pos), "remote enemy absent from spell targets")
	check(not game.apply_action({"type": "play", "card_uid": card.uid, "target": target.pos}).ok, "global damage cast rejected")
	check(before == var_to_str([game.players, game.units, game.terrain]), "out-of-range spell rejection is atomic")
	var mage: Dictionary = troop(game, "mage", Vector2i(6, 1))
	check(game.unit_cast_range(mage) == 4 and game.card_targets(card.uid, 0).has(target.pos), "newly summoned mage provides four-cell reach")
	check(not game.can_cast_at(Vector2i(11, 1), 0), "mage cannot cover fifth cell")
	mage.hp = 0
	game._cleanup()
	check(not game.can_cast_at(target.pos, 0), "dead caster removes forward spell reach")
	var sword: Dictionary = troop(game, "sword", Vector2i(6, 1))
	check(game.unit_cast_range(sword) == 3 and not game.can_cast_at(target.pos, 0), "ordinary troop cannot cover fourth cell")
	sword.pos = Vector2i(7, 1)
	check(game.apply_action({"type": "play", "card_uid": card.uid, "target": target.pos}).ok and target.hp == 16, "ordinary troop casts at exact three-cell boundary")
	var terrain_card: Dictionary = give(game, "trail")
	check(not game.card_targets(terrain_card.uid, 0).has(Vector2i(11, 9)), "terrain manipulation obeys local reach")
	check(game.spell_cells(game.definition("rain"), 0) == [Vector2i(-1, -1)], "weather remains a global no-target card")
	var splash: Battle = fresh()
	troop(splash, "mage", Vector2i(5, 1))
	var center: Dictionary = troop(splash, "sword", Vector2i(9, 1), 1)
	var nova: Dictionary = give(splash, "nova")
	check(splash.apply_action({"type": "play", "card_uid": nova.uid, "target": center.pos}).ok, "area center respects caster reach")
	check(splash.commander(1).hp == 17, "legal area splash may extend one cell beyond center reach")

func test_local_heroes_and_exchange() -> void:
	var pyro: Battle = fresh("pyromancer")
	check(not pyro.hero_targets(0).has(pyro.commander(1).pos), "hero cannot strike across whole map")
	pyro.commander(1).pos = Vector2i(1, 4)
	check(pyro.apply_action({"type": "hero", "target": pyro.commander(1).pos}).ok, "fire commander skill reaches exactly four cells")
	var warden: Battle = fresh()
	var distant: Dictionary = troop(warden, "sword", Vector2i(5, 8))
	check(not warden.hero_targets(0).has(distant.pos), "warden blessing uses commander reach, not target self coverage")
	var grove: Battle = fresh("grove")
	var nearby: Dictionary = troop(grove, "sword", Vector2i(3, 8))
	var far: Dictionary = troop(grove, "sword", Vector2i(6, 8))
	nearby.hp = 1
	far.hp = 1
	check(grove.apply_action({"type": "hero", "target": Vector2i(-1, -1)}).ok, "local renewal can be activated")
	check(nearby.hp == 3 and far.hp == 1, "renewal heals only allies within commander radius")
	var exhausted: Battle = fresh("grove")
	exhausted.players[0].deck.clear()
	exhausted.players[0].fatigue = 5
	exhausted.commander(0).hp = 1
	check(EnemyAI.evaluate(exhausted, {"type": "hero", "target": Vector2i(-1, -1)}) < 0, "AI avoids renewal when its draw would cause lethal fatigue after healing")
	var swap: Battle = fresh()
	var ally: Dictionary = troop(swap, "sword", Vector2i(8, 8))
	var exchange: Dictionary = give(swap, "exchange")
	check(not swap.card_targets(exchange.uid, 0).has(ally.pos), "exchange cannot use distant unit to teleport commander across map")
	ally.pos = Vector2i(4, 8)
	check(swap.apply_action({"type": "play", "card_uid": exchange.uid, "target": ally.pos}).ok, "exchange works at commander three-cell boundary")

func test_clock() -> void:
	var game: Battle = fresh("warden", 1.0)
	check(is_equal_approx(game.time_remaining, 1.0), "new game starts with configured turn duration")
	check(not game.advance_clock(0.4) and is_equal_approx(game.time_remaining, 0.6), "partial elapsed time keeps current turn")
	check(game.advance_clock(0.7) and game.turn == 2 and game.active_side == 1, "expired turn hands over exactly once")
	check(is_equal_approx(game.time_remaining, 1.0), "new side receives full time")
	check(not game.advance_clock(-1) and not game.advance_clock(NAN), "invalid elapsed time cannot alter clock")
	game.advance_clock(1000)
	check(game.turn == 3 and game.active_side == 0, "large elapsed value cannot fast-forward multiple turns")
	game.advance_clock(0.5)
	game.end_turn()
	check(is_equal_approx(game.time_remaining, 1.0), "manual end turn also resets time")
	game.winner = 0
	check(not game.advance_clock(5) and is_equal_approx(game.time_remaining, 1.0), "finished game stops time")
