extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const Store = preload("res://scripts/deck_store.gd")
var game: Control
var checks: int = 0
var failures: int = 0
var recording: bool = false

func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(label)

func settle() -> void:
	for frame: int in range(5): await process_frame

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point; root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
	await settle()

func key(code: Key) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true
	root.push_input(event, true)
	await settle()

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://docs/screenshots/" + name + ".png") == OK, "screenshot " + name)

func stage() -> void:
	game._new_match(71)
	game.has_started = true
	game.council.hide()
	if not game.expanded_battlefield: game._toggle_battlefield()
	game.battle.players[0].mana = 10; game.battle.players[0].max_mana = 10
	game.battle.players[1].mana = 10; game.battle.players[1].max_mana = 10
	game._refresh()
	await settle()

func troop(kind: String, cell: Vector2i, side: int = 0) -> Dictionary:
	var result: Dictionary = game.battle.get_unit(game.battle._spawn(game.battle.definition(kind), cell, side))
	result.summoning = false; result.moved = false; result.attacked = false
	return result

func select(unit: Dictionary) -> void:
	game._refresh()
	await settle()
	await click(game.board.global_position + game.board.cell_center(unit.pos))
	check(game.selected_unit == unit.id, "real click selects unit")
	check(game.unit_skill_button.is_visible_in_tree(), "unit skill button is visible")

func immutable_state() -> String:
	return var_to_str([game.battle.units, game.battle.players, game.battle.terrain, game.battle.rng.state, game.battle.log_lines])

func pause_for_demo() -> void:
	if recording: await create_timer(1.2).timeout

func run() -> void:
	create_timer(75).timeout.connect(func() -> void: push_error("unit skill UI timeout"); quit(2))
	recording = OS.get_cmdline_user_args().has("--record")
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/unit_skill_ui_deck.json")
	root.add_child(game); current_scene = game
	await stage()
	var guard: Dictionary = troop("spear", Vector2i(5, 6))
	var ally: Dictionary = troop("mage", Vector2i(4, 6))
	await select(guard)
	check(game.unit_skill_button.text.contains("援护") and not game.unit_skill_button.disabled, "selected spear exposes guard button")
	await pause_for_demo()
	await key(KEY_Q)
	check(guard.get("guarding", false) and game.battle.players[0].mana == 9, "Q activates guard and pays mana")
	check(game.unit_skill_button.disabled and not game.using_unit_skill, "guard ends action and exits target mode")
	await capture("spear-guard-ready")
	await pause_for_demo()
	# Blue archer attacks a red mage, whose adjacent spear intercepts and retaliates.
	await stage()
	var archer: Dictionary = troop("archer", Vector2i(4, 4))
	guard = troop("spear", Vector2i(4, 5), 1)
	ally = troop("mage", Vector2i(5, 5), 1)
	game.battle.end_turn()
	check(game.battle.apply_action({"type": "unit_skill", "unit_id": guard.id, "target": guard.pos}).ok, "enemy activates real guard skill")
	game.battle.end_turn()
	await select(archer)
	await key(KEY_Q)
	check(game.using_unit_skill and game.board.spell_targets.has(ally.pos), "precise shot target mode uses legal range")
	var hover := InputEventMouseMotion.new(); hover.position = game.board.global_position + game.board.cell_center(ally.pos)
	root.push_input(hover, true); await settle()
	var forecast: Dictionary = game.attack_prediction(archer, ally)
	check(forecast.intercepted and game.board.predicted_losses.has(guard.id) and not game.board.predicted_losses.has(ally.id), "forecast loss strip points to actual guard")
	check(game.battle_peek.details.text.contains("援护") and game.battle_peek.details.text.contains("精准射击 +1"), "portrait explains interception and skill bonus")
	await capture("spear-guard-forecast")
	await pause_for_demo()
	var old_guard_hp: int = guard.hp
	await click(game.board.global_position + game.board.cell_center(ally.pos))
	check(guard.hp == old_guard_hp - forecast.target_loss and ally.hp == ally.max_hp, "UI click resolves exactly predicted interception")
	check(not game.board.combat.is_empty() and game.board.combat.forecast.intercepted, "guard creates combat presentation")
	var frozen: String = immutable_state()
	await create_timer(0.12).timeout
	await capture("spear-guard-projectile")
	await create_timer(0.17).timeout
	await capture("spear-guard-impact")
	await create_timer(0.27).timeout
	await capture("spear-guard-counter")
	await create_timer(0.65).timeout
	check(game.board.combat.is_empty() and frozen == immutable_state(), "animation completes without mutating rule state")
	check(guard.pos == Vector2i(4, 5) and ally.pos == Vector2i(5, 5), "guard returns visually without changing positions")
	await pause_for_demo()
	# Real melee attacks animate the acting figure, show triangle advantage and return fire.
	await stage()
	var swordsman: Dictionary = troop("sword", Vector2i(4, 5))
	var spearman: Dictionary = troop("spear", Vector2i(5, 5), 1)
	await select(swordsman)
	await pause_for_demo()
	await click(game.board.global_position + game.board.cell_center(spearman.pos))
	check(not game.board.combat.is_empty() and game.board.combat.forecast.counter_damage > 0, "melee presentation includes retaliation")
	check(game.battle.log_lines.any(func(line: String) -> bool: return line.contains("克制 +2")), "actual melee log exposes unit advantage")
	await create_timer(0.12).timeout; await capture("melee-attack-lunge")
	await create_timer(0.40).timeout; await capture("melee-attack-counter")
	await create_timer(0.6).timeout
	await pause_for_demo()
	await stage()
	swordsman = troop("sword", Vector2i(4, 5))
	await select(swordsman); await key(KEY_Q)
	check(swordsman.shield == 3 and swordsman.attacked, "sword shield is usable from actual UI")
	await pause_for_demo()
	await stage()
	var mage: Dictionary = troop("mage", Vector2i(4, 5))
	var cavalry: Dictionary = troop("cavalry", Vector2i(6, 5), 1)
	await select(mage); await key(KEY_Q)
	await click(game.board.global_position + game.board.cell_center(cavalry.pos))
	check(cavalry.hp == 2 and mage.attacked, "mage fire skill is usable from actual UI")
	await create_timer(0.12).timeout; await capture("mage-active-skill")
	await pause_for_demo()
	# Skill target cancellation, healing and cavalry motion use the same real input route.
	await stage()
	var medic: Dictionary = troop("healer", Vector2i(4, 6)); ally = troop("sword", Vector2i(5, 6)); ally.hp = 1
	await select(medic); await key(KEY_Q)
	check(game.using_unit_skill, "healing enters target mode")
	await key(KEY_ESCAPE)
	check(not game.using_unit_skill and game.board.spell_targets.is_empty(), "Escape cancels skill without paying")
	await select(medic); await click(game.unit_skill_button.get_global_rect().get_center())
	await click(game.board.global_position + game.board.cell_center(ally.pos))
	check(ally.hp == 4 and medic.get("skill_used", false), "button and cell click perform real healing")
	await create_timer(0.20).timeout; await capture("medic-active-skill")
	await pause_for_demo()
	await stage()
	var rider: Dictionary = troop("cavalry", Vector2i(4, 6))
	check(game.battle.apply_action({"type": "move", "unit_id": rider.id, "target": Vector2i(4, 5)}).ok, "rider first move fixture")
	await select(rider); await key(KEY_Q)
	var destination: Vector2i = game.battle.skill_targets(rider).front()
	await click(game.board.global_position + game.board.cell_center(destination))
	check(rider.pos == destination and not rider.attacked and game.board.motion_unit == rider.id, "cavalry extra movement animates and retains attack")
	game._new_match(72)
	check(game.board.combat.is_empty() and game.board.effects.is_empty() and game.board.motion_unit == -1, "restart clears old combat and movement")
	# Both battlefield layouts and minimum supported window keep the action button accessible.
	var dimensions_to_check: Array = [] if recording else [Vector2i(1008, 700), Vector2i(1440, 1000)]
	for dimensions: Vector2i in dimensions_to_check:
		root.size = dimensions; await settle()
		for expanded: bool in [false, true]:
			if game.expanded_battlefield != expanded: game._toggle_battlefield()
			await settle()
			check(game.get_global_rect().encloses(game.unit_skill_button.get_global_rect()), "skill button fits logical viewport at requested physical resolution")
	game._open_council(); await key(KEY_Q)
	check(not game.using_unit_skill, "menu blocks Q")
	print("UNIT SKILL UI CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
