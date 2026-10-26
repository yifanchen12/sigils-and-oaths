extends SceneTree

const Model = preload("res://scripts/battle.gd")
const Forecast = preload("res://scripts/effect_forecast.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(label)

func fresh(hero: String = "warden") -> Battle:
	var game: Battle = Model.new(77, "greenwood", hero)
	game.players[0].mana = 10; game.players[0].max_mana = 10
	return game

func troop(game: Battle, kind: String, cell: Vector2i, side: int = 0) -> Dictionary:
	var unit: Dictionary = game.get_unit(game._spawn(game.definition(kind), cell, side))
	unit.summoning = false; unit.moved = false; unit.attacked = false
	return unit

func give(game: Battle, id: String) -> Dictionary:
	for zone: String in ["hand", "deck"]:
		for card: Dictionary in game.players[0][zone]:
			if card.card_id != id: continue
			if zone != "hand": game.players[0][zone].erase(card); game.players[0].hand.append(card)
			return card
	game.add_generated_card(0, id)
	return game.players[0].hand.back()

func state(game: Battle) -> String:
	return var_to_str([game.units, game.players, game.terrain, game.rng.state, game.log_lines, game.next_id])

func verify(game: Battle, action: Dictionary, label: String) -> Dictionary:
	var before: String = state(game)
	var preview: Dictionary = Forecast.predict(game, action)
	check(not preview.is_empty(), label + " has preview")
	if preview.is_empty(): return preview
	check(not Forecast.describe(preview, game).is_empty() and not Forecast.hint(preview).is_empty(), label + " has readable text")
	check(before == state(game), label + " preview and formatting do not mutate rules or RNG")
	check(game.apply_action(action).ok, label + " actual action succeeds")
	for change: Dictionary in preview.changes:
		var unit: Dictionary = game.get_unit(change.unit_id)
		check(int(unit.get("hp", 0)) == int(change.hp_after), label + " predicted health matches real result")
		check(int(unit.get("shield", 0)) == int(change.shield_after), label + " predicted shield matches real result")
		if change.has("position_after") and not unit.is_empty(): check(unit.pos == change.position_after, label + " predicted displacement matches actual")
	return preview

func run() -> void:
	for weather: String in ["clear", "rain", "sun"]:
		var game: Battle = fresh("pyromancer")
		game.weather = weather
		var caster: Dictionary = troop(game, "mage", Vector2i(4, 5))
		var victim: Dictionary = troop(game, "spear", Vector2i(4, 3), 1); victim.shield = 1
		game.terrain[victim.pos] = "fort"
		var preview: Dictionary = verify(game, {"type": "unit_skill", "unit_id": caster.id, "target": victim.pos}, "mage skill " + weather)
		check(preview.amount == game.fire_damage(3) and not game.players[0].spell_boost_used, "mage skill does not consume or apply commander card passive")
	for used: bool in [false, true]:
		for weather: String in ["clear", "rain", "sun"]:
			var game: Battle = fresh("pyromancer")
			game.weather = weather; game.players[0].spell_boost_used = used
			troop(game, "sword", Vector2i(4, 5))
			var victim: Dictionary = troop(game, "spear", Vector2i(4, 3), 1); victim.shield = 2
			var card: Dictionary = give(game, "bolt")
			var expected: int = game.spell_damage(game.definition("bolt"), 0)
			var preview: Dictionary = verify(game, {"type": "play", "card_uid": card.uid, "target": victim.pos}, "fire card " + weather + str(used))
			check(preview.amount == expected, "spell passive and weather use authoritative amount")
	var game: Battle = fresh()
	var caster: Dictionary = troop(game, "healer", Vector2i(4, 5)); caster.hp = 4
	verify(game, {"type": "unit_skill", "unit_id": caster.id, "target": caster.pos}, "healer caps self heal")
	game = fresh(); caster = troop(game, "sword", Vector2i(4, 5))
	var ally: Dictionary = troop(game, "sword", Vector2i(4, 3)); ally.hp = 1
	var card: Dictionary = give(game, "heal")
	verify(game, {"type": "play", "card_uid": card.uid, "target": ally.pos}, "healing card cap")
	game = fresh(); caster = troop(game, "sword", Vector2i(4, 5)); caster.shield = 1
	verify(game, {"type": "unit_skill", "unit_id": caster.id, "target": caster.pos}, "infantry self ward")
	game = fresh(); ally = troop(game, "sword", Vector2i(5, 8)); ally.shield = 1
	card = give(game, "ward")
	verify(game, {"type": "play", "card_uid": card.uid, "target": ally.pos}, "ward replaces rather than stacks")
	game = fresh(); ally = troop(game, "sword", Vector2i(5, 8)); ally.hp = 4; ally.shield = 4
	verify(game, {"type": "hero", "target": ally.pos}, "hero simultaneous capped heal and shield")
	game = fresh("pyromancer"); game.weather = "sun"
	var victim: Dictionary = troop(game, "spear", Vector2i(5, 6), 1); victim.shield = 1
	verify(game, {"type": "hero", "target": victim.pos}, "hero fire uses weather without card passive")
	game = fresh(); caster = troop(game, "sword", Vector2i(4, 6))
	var center := Vector2i(4, 4)
	for cell: Vector2i in [center, center + Vector2i.LEFT, center + Vector2i.RIGHT, center + Vector2i.DOWN]: troop(game, "archer", cell, 1)
	ally = troop(game, "sword", center + Vector2i.UP)
	var outside: Dictionary = troop(game, "sword", center + Vector2i.RIGHT * 2, 1)
	card = give(game, "nova")
	var preview: Dictionary = verify(game, {"type": "play", "card_uid": card.uid, "target": center}, "area fire")
	check(preview.changes.size() == 4 and ally.hp == ally.max_hp and outside.hp == outside.max_hp, "area forecast excludes allies and targets outside cross")
	for blocked: bool in [false, true]:
		game = fresh(); caster = troop(game, "sword", Vector2i(4, 6))
		victim = troop(game, "spear", Vector2i(4, 4), 1)
		if blocked: game.terrain[game.repulse_destination(victim, 0)] = "mountain"
		card = give(game, "repulse")
		verify(game, {"type": "play", "card_uid": card.uid, "target": victim.pos}, "repulse blocked=" + str(blocked))
	game = fresh(); caster = troop(game, "sword", Vector2i(4, 6)); victim = troop(game, "spear", Vector2i(4, 4), 1); victim.shield = 5
	card = give(game, "dispel")
	verify(game, {"type": "play", "card_uid": card.uid, "target": victim.pos}, "dispel only removes shield")
	game = fresh(); caster = troop(game, "mage", Vector2i(4, 6)); victim = troop(game, "sword", Vector2i(4, 3), 1)
	var before: String = state(game)
	check(Forecast.predict(game, {"type": "unit_skill", "unit_id": caster.id, "target": victim.pos}).is_empty(), "unit skill preview rejects range three")
	game.players[0].mana = 0; before = state(game)
	check(Forecast.predict(game, {"type": "unit_skill", "unit_id": caster.id, "target": Vector2i(4, 5)}).is_empty() and state(game) == before, "unaffordable or empty target produces no preview or mutation")
	print("EFFECT FORECAST CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
