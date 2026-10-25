extends SceneTree
## Runs the real main scene, sends pointer events, and captures the actual viewport.

const MainScene = preload("res://scenes/main.tscn")
const EnemyAI = preload("res://scripts/opponent.gd")
const Store = preload("res://scripts/deck_store.gd")
const DECK_TEST_PATH: String = "res://.tools/ui_custom_deck.json"
var checks: int = 0
var failures: int = 0
var game: Control

func _initialize() -> void:
	call_deferred("run")
	create_timer(90.0).timeout.connect(func() -> void: push_error("UI test timed out"); quit(2))

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func settle() -> void:
	for frame: int in range(3): await process_frame

func click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var down := InputEventMouseButton.new()
	down.position = point
	down.global_position = point
	down.button_index = button
	down.button_mask = 1 << (button - 1) if button <= 3 else 0
	down.pressed = true
	root.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.position = point
	up.global_position = point
	up.button_index = button
	up.pressed = false
	root.push_input(up, true)
	await settle()

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var directory: String = ProjectSettings.globalize_path("res://docs/screenshots")
	DirAccess.make_dir_recursive_absolute(directory)
	var image: Image = root.get_texture().get_image()
	check(image.save_png(directory.path_join(filename)) == OK, "screenshot " + filename)

func check_layout() -> void:
	var viewport: Rect2 = game.get_global_rect()
	for node_name: String in ["Board", "Hand", "EndTurn", "InfoTitle", "BlueStatus", "RedStatus", "Hint"]:
		var control: Control = game.get_node("%" + node_name)
		check(viewport.grow(1).encloses(control.get_global_rect()), "within viewport: " + node_name)
	var panel: Control = game.get_node("Margin/Layout/HandPanel")
	for card: Control in game.hand.get_children():
		check(panel.get_global_rect().grow(1).encloses(card.get_global_rect()), "hand fits panel")

func run() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(DECK_TEST_PATH + suffix): DirAccess.remove_absolute(DECK_TEST_PATH + suffix)
	game = MainScene.instantiate()
	game.deck_store = Store.new(DECK_TEST_PATH)
	root.add_child(game)
	current_scene = game
	await settle()
	check(game.council.visible, "war council opens on first launch")
	for button: Button in game.council.map_buttons + game.council.hero_buttons:
		check(game.get_global_rect().encloses(button.get_global_rect()), "war council choice within viewport")
	for index: int in range(game.council.hero_buttons.size()):
		await click(game.council.hero_buttons[index].get_global_rect().get_center())
		check(game.council.selected_hero == game.battle.HEROES.heroes[index].id, "commander portrait button selects matching hero")
		await create_timer(0.2).timeout
		check(is_equal_approx(game.council.hero_showcase.modulate.a, 1.0), "commander showcase fade finishes")
	await click(game.council.hero_buttons[0].get_global_rect().get_center())
	await create_timer(0.2).timeout
	for index: int in range(game.council.map_buttons.size()):
		await click(game.council.map_buttons[index].get_global_rect().get_center())
		check(game.council.selected_map == game.council.map_options[index].id, "terrain preview selects matching map")
	await click(game.council.map_buttons[0].get_global_rect().get_center())
	await capture("war-council.png")
	await click(game.council.start_button.get_global_rect().get_center())
	check(not game.council.visible and game.has_started, "start button enters battle")
	check(game.expanded_battlefield, "large battlefield opens expanded by default")
	await click(game.get_node("%ExpandBoard").get_global_rect().get_center())
	print("OPENING HAND: ", game.battle.players[0].hand.map(func(card: Dictionary) -> String: return game.battle.definition(card.card_id).name))
	check_layout()
	# Choose a reproducible legal opening with a 1-mana troop for pointer interaction.
	var chosen_index: int = -1
	for seed_value: int in range(1, 100):
		chosen_index = -1
		game._new_match(seed_value)
		await settle()
		# A real AI may use its initiative to remove the first troop. Keep this
		# movement fixture deterministic and test that independent scenario separately.
		var opening_removal: bool = false
		var enemy_opening: Array = game.battle.players[1].hand.duplicate()
		enemy_opening.append(game.battle.players[1].deck.back())
		for enemy_card: Dictionary in enemy_opening:
			var definition: Dictionary = game.battle.definition(enemy_card.card_id)
			if definition.get("effect", "") in ["damage", "area"] and definition.cost <= 2: opening_removal = true
		if opening_removal: continue
		for index: int in range(game.battle.players[0].hand.size()):
			var instance: Dictionary = game.battle.players[0].hand[index]
			if game.battle.definition(instance.card_id).id == "sword": chosen_index = index; break
		if chosen_index != -1: break
	check(chosen_index != -1, "find a playable troop opening")
	print("TUTORIAL SEED: ", game.battle.match_seed)
	var card_button: Control = game.hand.get_child(chosen_index)
	await click(card_button.get_global_rect().get_center())
	check(game.selected_card != -1, "pointer selects card")
	check(not game.board.deploy.is_empty(), "deployment highlight visible")
	if game.board.deploy.is_empty():
		print("BUTTON RECT: ", card_button.get_global_rect(), " VIEWPORT: ", root.size, " GAME: ", game.size)
		quit(1)
		return
	await capture("deployment.png")
	var target: Vector2i = game.board.deploy[0]
	await click(game.board.global_position + game.board.cell_center(target))
	check(game.battle.army_count(0) == 1, "pointer deploys unit")
	check(game.selected_card == -1, "played card selection cleared")
	await click(game.board.global_position + game.board.cell_center(target))
	check(game.selected_unit != -1, "pointer selects deployed unit")
	check(game.board.moves.is_empty(), "new unit movement not offered")
	await click(game.get_node("%EndTurn").get_global_rect().get_center())
	check(game.battle.active_side == 1 or game.battle.turn >= 3, "end-turn button hands over to AI")
	var wait_frames: int = 0
	while game.ai_running and wait_frames < 100:
		await create_timer(0.1).timeout
		wait_frames += 1
	check(not game.ai_running and game.battle.active_side == 0, "AI returns control to player")
	check(game.battle.players[0].max_mana == 2, "UI turn resource progression")
	await click(game.board.global_position + game.board.cell_center(target))
	check(not game.board.moves.is_empty(), "movement available on next own turn")
	if game.board.moves.is_empty():
		quit(1)
		return
	var destination: Vector2i = game.board.moves[0]
	await click(game.board.global_position + game.board.cell_center(destination))
	check(game.battle.unit_at(destination).get("side", -1) == 0, "pointer moves troop")
	check(game.selected_unit != -1, "move keeps unit selected for attack")
	var soldier: Dictionary = game.battle.unit_at(destination)
	var foe: Dictionary = game.battle.commander(1)
	var adjacent: Vector2i = destination + Vector2i.UP
	if not game.battle.inside(adjacent) or not game.battle.unit_at(adjacent).is_empty(): adjacent = destination + Vector2i.RIGHT
	foe.pos = adjacent
	game._refresh()
	await settle()
	var motion := InputEventMouseMotion.new()
	motion.position = game.board.global_position + game.board.cell_center(adjacent)
	root.push_input(motion, true)
	await settle()
	check(game.get_node("%Hint").text.contains("攻击预览"), "hover provides attack and counter preview")
	var previous_durability: int = int(foe.hp) + int(foe.shield)
	await click(game.board.global_position + game.board.cell_center(adjacent))
	check(int(foe.hp) + int(foe.shield) < previous_durability and soldier.attacked, "pointer attacks enemy, including shield absorption")
	check(game.board.moves.is_empty() and game.board.attacks.is_empty(), "attack clears further action highlights")
	# A legal mid-game produced by the same AI/rules, used for a useful visual review.
	game._new_match(42)
	var steps: int = 0
	while game.battle.turn < 9 and game.battle.winner == -1 and steps < 250:
		game.battle.apply_action(EnemyAI.choose(game.battle))
		steps += 1
	game._cancel()
	await settle()
	check(game.battle.winner == -1, "midgame screenshot is an ongoing playable battle")
	check_layout()
	await capture("battle.png")
	await click(game.get_node("%ExpandBoard").get_global_rect().get_center())
	await capture("expanded-battle.png")
	await click(game.get_node("%ExpandBoard").get_global_rect().get_center())
	# Exercise the maximum hand layout and terminal state without invalid card duplication.
	game.battle._draw(0, 8)
	game._refresh()
	await settle()
	check(game.battle.players[0].hand.size() == 8, "full hand fixture")
	check_layout()
	await capture("full-hand.png")
	game.battle.commander(1).hp = 0
	game.battle._cleanup()
	game.battle._check_winner()
	game._refresh()
	await settle()
	check(game.get_node("%ResultOverlay").visible, "victory overlay displayed")
	await click(game.get_node("%PlayAgain").get_global_rect().get_center())
	check(game.battle.winner == -1 and not game.get_node("%ResultOverlay").visible, "result restart works")
	game._end_turn()
	game._restart()
	var fresh_seed: int = game.battle.match_seed
	await create_timer(0.8).timeout
	check(game.battle.turn == 1 and game.battle.match_seed == fresh_seed and not game.ai_running, "stale AI cannot modify restarted game")
	await test_evolution_ui()
	await test_decks_and_library()
	await test_large_map_views()
	await test_turn_clock_ui()
	await test_custom_deck_ui()
	# Same logical layout must fit a smaller desktop window and a wide screen.
	for window_size: Vector2i in [Vector2i(1008, 700), Vector2i(1920, 1080)]:
		root.size = window_size
		await settle()
		check_layout()
	print("UI CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(DECK_TEST_PATH + suffix): DirAccess.remove_absolute(DECK_TEST_PATH + suffix)
	game.queue_free()
	await settle()
	quit(0 if failures == 0 else 1)

func test_custom_deck_ui() -> void:
	game.current_deck = "balanced"
	game._new_match(87)
	game._open_council()
	await settle()
	var before: String = var_to_str([game.battle.players, game.battle.units, game.battle.turn])
	await click(game.council.editor_button.get_global_rect().get_center())
	var editor: DeckEditor = game.deck_editor
	check(editor.visible and not game._player_can_act(), "war council opens read-only-to-battle deck editor")
	check(editor.size.y <= root.size.y and editor.size.x <= root.size.x, "deck editor fits game viewport")
	await click(Vector2(editor.position) + editor.filter_buttons.unit.get_global_rect().get_center())
	var visible_cards: int = 0
	for row: Dictionary in editor.rows.values():
		if row.cell.visible: visible_cards += 1
	check(visible_cards == 6, "deck workshop troop filter shows six unit cards")
	await click(Vector2(editor.position) + editor.filter_buttons.all.get_global_rect().get_center())
	check(editor.rows.values().all(func(row: Dictionary) -> bool: return row.cell.visible), "all filter restores collectible catalog")
	check(editor.rows.size() == 24 and not editor.rows.has("initiative"), "editor excludes generated initiative")
	check(not editor.get_ok_button().disabled and editor._total() == 30, "valid preset starts as editable 30-card draft")
	# Dialog controls live in their own Window viewport, so inject there.
	await click_window(editor, editor.rows.sword.minus.get_global_rect().get_center())
	check(editor._total() == 29 and editor.get_ok_button().disabled, "removing one card blocks invalid save")
	await click_window(editor, editor.rows.mage.plus.get_global_rect().get_center())
	check(editor._total() == 30 and editor.draft.mage == 4 and editor.rows.mage.plus.disabled, "adding replacement respects total and four-copy cap")
	check(before == var_to_str([game.battle.players, game.battle.units, game.battle.turn]), "draft edits do not affect current battle")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(editor.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/screenshots/deck-editor.png")) == OK, "deck editor screenshot")
	await click_window(editor, editor.get_ok_button().get_global_rect().get_center())
	check(not editor.visible and game.council.selected_deck == "custom", "save selects custom for next battle")
	check(before == var_to_str([game.battle.players, game.battle.units, game.battle.turn]), "saving cannot reset live battle")
	var loaded: Dictionary = Store.new(DECK_TEST_PATH).load_deck()
	check(loaded.ok and loaded.definition.cards.mage == 4, "UI saved actual local counts")
	await click(game.council.start_button.get_global_rect().get_center())
	check(game.battle.deck(0).id == "custom" and game.battle.deck(0).cards.mage == 4 and game.battle.deck(1).id == "balanced", "next battle uses custom snapshot against balanced opponent")
	game._open_council()
	await settle()
	await click(game.council.editor_button.get_global_rect().get_center())
	check(editor.draft.mage == 4 and editor.draft.sword == 2, "reopening editor restores saved draft")
	await click_window(editor, editor.rows.sword.minus.get_global_rect().get_center())
	editor.source_choice.select(1)
	await click_window(editor, editor.copy_button.get_global_rect().get_center())
	check(editor.draft == game.battle.DECKS.find("assault").cards and editor._total() == 30, "copy preset replaces only unsaved draft")
	await click_window(editor, editor.get_cancel_button().get_global_rect().get_center())
	loaded = Store.new(DECK_TEST_PATH).load_deck()
	check(loaded.ok and loaded.definition.cards.sword == 2, "cancel discards unsaved draft changes")
	game._resume_battle()
	if game.expanded_battlefield: game._toggle_battlefield()
	await settle()

func click_window(window: Window, point: Vector2) -> void:
	var target: Viewport = window
	if window.is_embedded():
		point += Vector2(window.position)
		target = root
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	target.push_input(motion, true)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.global_position = point
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	target.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	up.global_position = point
	target.push_input(up, true)
	await settle()

func test_evolution_ui() -> void:
	var map_choice: OptionButton = game.get_node("%MapChoice")
	map_choice.select(1)
	map_choice.item_selected.emit(1)
	await settle()
	check(game.battle.map_definition.id == "rivergate", "map selector starts selected map")
	check(game.battle.ground(Vector2i(0, 4)) == "water", "selected map terrain is live")
	var hero_choice: OptionButton = game.get_node("%HeroChoice")
	for index: int in range(3):
		hero_choice.select(index)
		hero_choice.item_selected.emit(index)
		await settle()
		var hero: Dictionary = game.battle.hero(0)
		if hero.effect == "firestrike": game.battle.commander(1).pos = game.battle.commander(0).pos + Vector2i.UP * 3
		check(hero.id == game.battle.HEROES.heroes[index].id, "hero selector applies hero identity")
		game.battle.players[0].mana = 10
		game.battle.players[0].max_mana = 10
		game._refresh()
		await settle()
		await click(game.get_node("%HeroSkill").get_global_rect().get_center())
		if hero.effect != "renewal":
			check(game.using_hero and not game.board.spell_targets.is_empty(), "hero targeting UI highlights legal targets")
			var target: Vector2i = game.battle.commander(0).pos if hero.effect == "blessing" else game.battle.commander(1).pos
			await click(game.board.global_position + game.board.cell_center(target))
		check(game.battle.players[0].skill_cooldown > 0 and not game.using_hero, "pointer casts hero skill")
		check(game.get_node("%HeroSkill").disabled, "cooldown disables skill button")
	# Select actual cards by their real UID; moving one from deck preserves zones.
	for weather: String in ["rain", "fog", "sun", "snow"]:
		var found: Dictionary = {}
		for card: Dictionary in game.battle.players[0].hand:
			if card.card_id == weather: found = card; break
		if found.is_empty():
			for card: Dictionary in game.battle.players[0].deck:
				if card.card_id == weather:
					found = card
					game.battle.players[0].deck.erase(card)
					game.battle.players[0].hand.append(card)
					break
		check(not found.is_empty(), "weather fixture available")
		game.battle.players[0].mana = 10
		game._refresh()
		await settle()
		for view: Control in game.hand.get_children():
			if view.card_uid == found.uid:
				await click(view.get_global_rect().get_center())
				break
		check(game.battle.weather == weather and game.selected_card == -1, "pointer casts global weather " + weather)
		check(game.get_node("%WeatherStatus").text.contains(game.battle.WEATHER[weather].name), "weather HUD updates")
	await capture("river-snow.png")
	map_choice.select(2)
	map_choice.item_selected.emit(2)
	await settle()
	check(game.battle.map_definition.id == "sunspire", "third map selector works")
	await capture("sunspire.png")
	for index: int in [3, 4, 5]:
		map_choice.select(index)
		map_choice.item_selected.emit(index)
		await settle()
		check(game.battle.map_definition.id == game.battle.MAPS.maps[index].id, "extra map selection applies terrain")
		await capture(game.battle.map_definition.id + ".png")
		if index in [3, 4]:
			await click(game.get_node("%ExpandBoard").get_global_rect().get_center())
			await capture("expanded-" + game.battle.map_definition.id + ".png")
			await click(game.get_node("%ExpandBoard").get_global_rect().get_center())
	await click(game.get_node("%Help").get_global_rect().get_center())
	check(game.get_node("%RulesDialog").visible and not game._player_can_act(), "help dialog blocks battle actions")
	check(game.get_node("%RulesText").text.contains("战术先机") and game.get_node("%RulesText").text.contains("坚冰锁链"), "help includes current tactics and opening rules")
	game.get_node("%RulesDialog").hide()
	await settle()

func test_large_map_views() -> void:
	if game.expanded_battlefield: await click(game.get_node("%ExpandBoard").get_global_rect().get_center())
	var choice: OptionButton = game.get_node("%MapChoice")
	choice.select(5)
	choice.item_selected.emit(5)
	await settle()
	check(game.battle.width == 12 and game.battle.height == 10, "production map has 120 cells")
	var board: BoardView = game.board
	var snapshot: String = var_to_str([game.battle.players, game.battle.units, game.battle.turn])
	var before_size: Vector2 = board.size
	await click(game.get_node("%ExpandBoard").get_global_rect().get_center())
	check(game.expanded_battlefield and board.size.x > before_size.x and board.size.y > before_size.y, "expanded view gives battlefield more width and height")
	check(game.get_node("%CompactHand").get_child_count() == game.battle.players[0].hand.size(), "expanded view keeps every hand card accessible")
	check(game.get_node("%MapName").get_parent().hud_visible, "expanded battlefield shows commander health and mana HUD")
	for view: Control in game.get_node("%CompactHand").get_children():
		check(view is CardView and view.compact and view.illustration != null, "expanded hand uses illustrated native cards")
		check(game.get_node("%CompactHandPanel").get_global_rect().encloses(view.get_global_rect()), "illustrated hand stays in dock")
	check(game.get_node("%ViewEnd").visible and game.get_node("%ViewSkill").visible, "expanded view keeps turn and skill buttons")
	check(game.battle_peek.visible, "expanded fit view uses empty gutter for portrait inspection")
	check(Rect2(Vector2.ZERO, board.size).encloses(game.battle_peek.get_rect()), "inspection panel fits entirely inside battlefield gutter")
	check(game.battle_brief.visible and game.battle_brief.position.x > board.grid_rect().end.x + 10, "public enemy brief stays in right gutter")
	check(game.battle_brief.details.text.contains("手牌%d张" % game.battle.players[1].hand.size()), "expanded brief reports public hand count")
	check(game.battle_brief.details.text.contains(game.battle.hero(1).skill_text), "enemy skill effect and range remain readable during expanded battle")
	check(Rect2(Vector2.ZERO, board.size).encloses(game.battle_brief.get_rect()), "enemy brief fits inside gutter height")
	check(game.battle_peek.position.x + game.battle_peek.size.x < board.grid_rect().position.x - 20, "portrait inspection stays outside playable cells")
	var hover := InputEventMouseMotion.new()
	hover.position = board.global_position + board.cell_center(game.battle.commander(1).pos)
	root.push_input(hover, true)
	await settle()
	check(game.battle_peek.heading.text == game.battle.commander(1).name, "hovering enemy shows correct mature portrait and identity")
	var first_card: Dictionary = game.battle.players[0].hand[0]
	hover = InputEventMouseMotion.new()
	hover.position = game.get_node("%CompactHand").get_child(0).get_global_rect().get_center()
	root.push_input(hover, true)
	await settle()
	check(game.battle_peek.heading.text == game.battle.definition(first_card.card_id).name, "compact hand hover exposes full card illustration and rules")
	check(snapshot == var_to_str([game.battle.players, game.battle.units, game.battle.turn]), "inspection is read-only")
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(11, 9), Vector2i(5, 4), Vector2i(2, 8)]:
		check(board.cell_from_point(board.cell_center(cell)) == cell, "fit projection round trip " + str(cell))
	var anchor: Vector2 = board.size / 2
	var anchor_cell: Vector2i = board.cell_from_point(anchor)
	for step: int in range(3): await click(board.global_position + anchor, MOUSE_BUTTON_WHEEL_UP)
	check(board.zoom > 1.5 and game.get_node("%ZoomValue").text != "100%", "wheel zoom updates view and indicator")
	check(not game.battle_peek.visible, "zoom hides inspection when gutter no longer fits")
	check(board.cell_from_point(anchor) == anchor_cell, "wheel zoom retains anchored grid coordinate")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	down.pressed = true
	down.position = board.global_position + anchor
	root.push_input(down, true)
	var motion := InputEventMouseMotion.new()
	motion.position = board.global_position + anchor + Vector2(-80, 65)
	motion.relative = Vector2(-80, 65)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(motion, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_MIDDLE
	up.position = motion.position
	root.push_input(up, true)
	await settle()
	check(not board.dragging and board.pan.length() > 0, "middle drag pans map and releases")
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(11, 9), anchor_cell]:
		check(board.cell_from_point(board.cell_center(cell)) == cell, "zoomed and panned projection remains invertible")
	check(snapshot == var_to_str([game.battle.players, game.battle.units, game.battle.turn]), "camera gestures do not spend resources or take actions")
	await click(game.get_node("%FitMap").get_global_rect().get_center())
	check(is_equal_approx(board.zoom, 1.0) and board.pan.is_zero_approx(), "fit restores complete map")
	check(game.battle_peek.visible, "fit restores gutter inspection")
	await capture("expanded-harbor.png")
	await click(game.get_node("%ExpandBoard").get_global_rect().get_center())
	check(not game.expanded_battlefield and game.get_node("%HandPanel").visible, "restoring panels preserves normal hand")
	board.zoom_at(board.size / 2, 2.0)
	game._restart()
	check(is_equal_approx(board.zoom, 1.0) and board.pan.is_zero_approx(), "new match resets camera")

func test_turn_clock_ui() -> void:
	game._new_match(81)
	await settle()
	check(game.get_node("%TurnClock").text.contains("01:30"), "new battle displays full turn limit")
	game.battle.time_remaining = 0.05
	await create_timer(0.18).timeout
	check(game.battle.turn == 2 and game.battle.active_side == 1, "player timeout starts AI once")
	var frames: int = 0
	while game.ai_running and frames < 100:
		await create_timer(0.1).timeout
		frames += 1
	check(game.battle.turn == 3 and game.battle.active_side == 0 and not game.ai_running, "AI returns after timed-out player turn")
	game._end_turn()
	game.battle.time_remaining = 0.05
	await create_timer(0.18).timeout
	var returned_turn: int = game.battle.turn
	check(returned_turn == 5 and game.battle.active_side == 0, "AI timeout returns control to player")
	await create_timer(0.6).timeout
	check(game.battle.turn == returned_turn and not game.ai_running, "expired AI coroutine cannot act in later turn")
	game.battle.time_remaining = 0.08
	game.get_node("%RulesDialog").popup_centered()
	await create_timer(0.18).timeout
	check(game.battle.turn == returned_turn and game.battle.time_remaining > 0.07, "local help pauses turn clock")
	check(game.get_node("%TurnClock").text.begins_with("暂停"), "paused countdown is visibly labeled")
	game.get_node("%RulesDialog").hide()
	await create_timer(0.18).timeout
	check(game.battle.turn == 6 and game.battle.active_side == 1, "closing help resumes countdown and expiry")
	game._new_match(82)
	await settle()
	check(game.battle.turn == 1 and game.battle.time_remaining > 89, "restart restores full fresh countdown")

func test_decks_and_library() -> void:
	await click(game.get_node("%Restart").get_global_rect().get_center())
	check(game.council.visible and game.council.resume_button.visible, "war council can resume a live battle")
	game.council.deck_choice.select(1)
	game.council.deck_choice.item_selected.emit(1)
	await click(game.council.library_button.get_global_rect().get_center())
	check(game.get_node("%CardsDialog").visible, "menu library button opens compendium")
	check(game.get_node("%CardGrid").get_child_count() == 25, "compendium lists 24 collectible cards and initiative")
	for view: CardView in game.get_node("%CardGrid").get_children():
		check(view.illustration != null, "native illustration mapped for " + view.card.id)
	check(game.get_node("%LibraryIntro").text.contains("锋线突袭"), "library shows selected deck context")
	var before: String = var_to_str([game.battle.players, game.battle.units, game.battle.turn])
	game.get_node("%CardGrid").get_child(3).pressed.emit()
	check(game.get_node("%LibraryDetails").text.contains("暮林游侠"), "card selection updates detailed rules")
	check(before == var_to_str([game.battle.players, game.battle.units, game.battle.turn]), "browsing cards cannot mutate battle")
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image: Image = game.get_node("%CardsDialog").get_texture().get_image()
		check(image.save_png(ProjectSettings.globalize_path("res://docs/screenshots/card-library.png")) == OK, "compendium screenshot")
	game.get_node("%CardsDialog").hide()
	await settle()
	await click(game.council.start_button.get_global_rect().get_center())
	check(game.battle.deck(0).id == "assault" and not game.council.visible, "menu starts assault preset")
	check(game.battle.deck_size == 30, "preset keeps deck size")
	var deck_choice: OptionButton = game.get_node("%DeckChoice")
	deck_choice.select(2)
	deck_choice.item_selected.emit(2)
	await settle()
	check(game.battle.deck(0).id == "bastion", "in-battle deck selector starts bastion preset")
	game._end_turn()
	game._open_library()
	var paused_turn: int = game.battle.turn
	await create_timer(0.65).timeout
	check(game.battle.turn == paused_turn and game.battle.active_side == 1, "AI waits while compendium is open")
	game.get_node("%CardsDialog").hide()
	var frames: int = 0
	while game.ai_running and frames < 100:
		await create_timer(0.1).timeout
		frames += 1
	check(not game.ai_running and game.battle.active_side == 0, "AI resumes after closing compendium")
