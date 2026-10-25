extends SceneTree
## Compare the read-only UI forecast with the authoritative attack resolution.

const MainScene = preload("res://scenes/main.tscn")
const Store = preload("res://scripts/deck_store.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/forecast_deck.json")
	root.add_child(game)
	current_scene = game
	create_timer(30.0).timeout.connect(func() -> void: push_error("Forecast test timed out"); quit(2))
	game.council.hide()
	game.has_started = true
	if not game.expanded_battlefield: game._toggle_battlefield()
	for scenario: int in range(4):
		game._new_match(19)
		var attacker: Dictionary = game.battle.commander(0)
		var target: Dictionary = game.battle.commander(1)
		var combatants: Array[Dictionary] = [attacker, target]
		game.battle.units = combatants
		attacker.pos = Vector2i(4, 8)
		target.pos = Vector2i(4, 7) if scenario != 3 else Vector2i(4, 6)
		attacker.hp = 10
		attacker.shield = 2
		attacker.atk = 7
		attacker.range = 3
		target.hp = 3 if scenario == 1 else 12
		target.shield = 20 if scenario == 2 else 1
		target.atk = 5
		game.selected_unit = attacker.id
		game._refresh()
		await verify_prediction(game, attacker, target, "attack-forecast.png" if scenario == 0 else "")
	var scenarios: Array = [
		["sword", "spear", 1, "plain", "forest", "clear", 0, "克制 +2"],
		["spear", "cavalry", 1, "plain", "plain", "clear", 0, "克制 +2"],
		["cavalry", "sword", 1, "plain", "plain", "clear", 3, "冲锋 +1"],
		["archer", "sword", 1, "plain", "plain", "clear", 0, "近战惩罚"],
		["archer", "sword", 3, "plain", "plain", "clear", 0, "射程不足"],
		["mage", "spear", 2, "plain", "fort", "clear", 0, "穿透 +1"],
		["archer", "spear", 4, "hill", "plain", "clear", 0, "高地 +1"],
		["archer", "mage", 2, "hill", "plain", "fog", 0, "高地 +1"],
		["archer", "spear", 2, "plain", "forest", "snow", 0, "地形防御 2"]
	]
	for index: int in range(scenarios.size()):
		game._new_match(19)
		var spec: Array = scenarios[index]
		var attacker: Dictionary = troop(game, 0, spec[0], Vector2i(4, 7))
		var target: Dictionary = troop(game, 1, spec[1], attacker.pos + Vector2i.UP * int(spec[2]))
		game.battle.units.append(attacker)
		game.battle.units.append(target)
		game.battle.terrain[attacker.pos] = spec[3]
		game.battle.terrain[target.pos] = spec[4]
		game.battle.weather = spec[5]
		attacker.last_move_distance = spec[6]
		game.selected_unit = attacker.id
		game._refresh()
		game._on_cell_hovered(target.pos)
		check(game.battle_peek.details.text.contains(spec[7]), "forecast exposes the active modifier: " + str(spec[7]))
		await verify_prediction(game, attacker, target, "attack-forecast-terrain.png" if index == 0 else "")
	print("FORECAST CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func troop(game, side: int, kind: String, at: Vector2i) -> Dictionary:
	var result: Dictionary = game.battle.commander(side).duplicate(true)
	var definition: Dictionary = game.battle.definition(kind)
	for key: String in ["name", "short", "atk", "defense", "move", "range", "hp"]: result[key] = definition[key]
	result.max_hp = result.hp
	result.kind = kind
	result.pos = at
	result.id = 10000 + side
	return result

func verify_prediction(game, attacker: Dictionary, target: Dictionary, screenshot: String) -> void:
	var before: String = var_to_str([game.battle.units, game.battle.players, game.battle.rng.state, game.battle.log_lines])
	var prediction: Dictionary = game.attack_prediction(attacker, target)
	game._on_cell_hovered(target.pos)
	check(before == var_to_str([game.battle.units, game.battle.players, game.battle.rng.state, game.battle.log_lines]), "forecast never mutates battle state")
	check(game.board.predicted_losses.get(target.id, -1) == prediction.target_loss, "board loss strip matches target forecast")
	check(game.battle_peek.subtitle.text.begins_with("攻击预估"), "portrait card explains attack forecast")
	if prediction.target_loss >= target.hp:
		check(game.battle_peek.details.text.contains("被击破，不会反击"), "lethal forecast explains no retaliation before attack")
	elif game.battle.distance(attacker.pos, target.pos) > game.battle.attack_range(target):
		check(game.battle_peek.details.text.contains("射程不足"), "safe ranged forecast explains no retaliation")
	if not screenshot.is_empty():
		game._refresh()
		check(game.board.predicted_losses.get(target.id, -1) == prediction.target_loss, "refresh preserves valid loss overlay")
		check(game.get_node("%Hint").text.contains("攻击预览"), "refresh preserves concise attack hint")
		game._on_cell_hovered(attacker.pos)
		check(game.board.predicted_losses.is_empty(), "friendly hover clears forecast")
		game._on_cell_hovered(target.pos)
		game._open_council()
		check(game.board.predicted_losses.is_empty(), "menu suspends forecast")
		game._resume_battle()
		check(game.board.predicted_losses.get(target.id, -1) == prediction.target_loss, "resume restores valid forecast")
		game._toggle_battlefield()
		check(game.info_body.text.contains("目标生命"), "detailed view shares forecast content")
		game._toggle_battlefield()
		if DisplayServer.get_name() != "headless":
			for frame: int in range(4): await process_frame
			check(game.battle_peek.visible, "forecast fits battlefield gutter")
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://docs/screenshots/" + screenshot) == OK, "forecast screenshot saved")
		game._cancel()
		check(game.board.predicted_losses.is_empty(), "cancel clears loss overlay")
		game.selected_unit = attacker.id
		game._refresh()
	var old_attacker_hp: int = attacker.hp
	var old_target_hp: int = target.hp
	var result: Dictionary = game.battle.apply_action({"type": "attack", "unit_id": attacker.id, "target": target.pos})
	check(result.ok, "forecast scenario is a legal attack")
	check(old_target_hp - maxi(0, int(target.hp)) == prediction.target_loss, "target forecast equals resolved HP loss")
	check(old_attacker_hp - maxi(0, int(attacker.hp)) == prediction.attacker_loss, "counter forecast equals resolved HP loss")
