extends "res://tests/test_ui.gd"

const Settings = preload("res://scripts/settings_store.gd")

func run() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("Moorings UI timed out"); quit(2))
	DisplayServer.window_set_size(Vector2i(1296, 900))
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v049-moorings-native-deck.json")
	game.settings_store = Settings.new("user://v049-moorings-native-settings.cfg")
	root.add_child(game)
	current_scene = game
	await settle()
	var own: int = option_index(game.council.deck_choice, "breakwater_line")
	var rival: int = option_index(game.council.opponent_choice, "ember_quarter")
	check(own >= 0 and rival >= 0, "both presets can be selected in the War Council")
	if failures > 0: quit(1); return
	game.council.deck_choice.select(own)
	game.council.deck_choice.item_selected.emit(own)
	game.council.opponent_choice.select(rival)
	game.council.opponent_choice.item_selected.emit(rival)
	await verify_library()
	if failures == 0:
		await click(game.council.start_button.get_global_rect().get_center())
		check(game.battle.deck(0).id == "breakwater_line" and game.battle.deck(1).id == "ember_quarter", "normal menu starts the two real preset lists")
		if not game.expanded_battlefield: game._toggle_battlefield()
		await verify_spell()
	print("MOORINGS NATIVE UI: %d CHECKS | FAILURES: %d" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func verify_library() -> void:
	await click(game.council.library_button.get_global_rect().get_center())
	var dialog: Window = game.get_node("%CardsDialog")
	var sets: OptionButton = game.get_node("%LibrarySet")
	var costs: OptionButton = game.get_node("%LibraryCost")
	var grid: GridContainer = game.get_node("%CardGrid")
	var index: int = option_index(sets, "moorings")
	check(dialog.visible and index >= 0 and game.get_node("%LibraryIntro").text.contains("%d 种可组牌" % (Battle.CATALOG.cards.size() - 1)), "visible collection count and new set filter")
	if index < 0: return
	sets.select(index)
	sets.item_selected.emit(index)
	await settle()
	check(grid.get_child_count() == 24, "new set filter shows 24 cards")
	for view: CardView in grid.get_children():
		check(view.card.set_id == "moorings" and view.illustration != null, "illustrated from the new set: " + view.card.id)
	var ten: int = costs.get_item_index(11)
	costs.select(ten)
	costs.item_selected.emit(ten)
	await settle()
	check(grid.get_child_count() == 3, "the ten-cost filter displays three different cards")
	if grid.get_child_count() != 3: return
	var order: CardView = grid.get_child(1)
	await click_window(dialog, order.get_global_rect().get_center())
	var details: String = game.get_node("%LibraryDetails").text
	check(order.card.id == "sunken_weir_breach" and details.contains("十字") and details.contains("下回合"), "rules panel describes direction and response time")
	await capture("v049-moorings-ten-mana.png", dialog)
	dialog.hide()
	await settle()

func verify_spell() -> void:
	var center := Vector2i(5, 5)
	var commander: Dictionary = game.battle.commander(1)
	commander.pos = center + Vector2i.RIGHT * 3
	commander.shield = 3
	var caster_pos: Vector2i = center + Vector2i.LEFT * 3
	var enemy_pos: Vector2i = center + Vector2i.RIGHT
	var diagonal: Vector2i = center + Vector2i.UP + Vector2i.RIGHT
	for tile: Vector2i in [commander.pos, caster_pos, enemy_pos, diagonal]:
		game.battle.terrain[tile] = "plain"
	Fixture.troop(game.battle, "mage", caster_pos, 0)
	var hit: Dictionary = Fixture.troop(game.battle, "spear", enemy_pos, 1)
	var safe: Dictionary = Fixture.troop(game.battle, "spear", diagonal, 1)
	hit.shield = 4
	var card: Dictionary = Fixture.give(game.battle, "copper_boltline")
	game.battle.players[0].mana = 8
	game.battle.players[0].max_mana = 8
	game._refresh()
	await settle()
	var hand_card: CardView
	for view: CardView in game.get_node("%CompactHand").get_children():
		if view.card_uid == card.uid: hand_card = view; break
	check(hand_card != null and hand_card.affordable and hand_card.illustration != null, "real hand shows the cost and art")
	if hand_card == null: return
	await click(hand_card.get_global_rect().get_center())
	var point: Vector2 = game.board.global_position + game.board.cell_center(center)
	hover(point)
	await settle()
	check(game.selected_card == card.uid and game.battle_peek.heading.text == "八响破阵弦", "mouse selection opens the prescribed damage forecast")
	check(game.board.predicted_area.size() == 7 and game.board.predicted_area.has(commander.pos) and not game.board.predicted_area.has(diagonal), "game board highlights the horizontal strip only")
	await capture("v049-moorings-row-preview.png")
	await click(point)
	check(game.battle.players[0].mana == 0 and game.battle.hand_card(0, card.uid).is_empty(), "real click pays and removes the card from hand")
	check(hit.hp == hit.max_hp - 5 and hit.shield == 0 and commander.hp == commander.max_hp - 2 and commander.shield == 0, "board recipients take shieldbreak and damage")
	check(safe.hp == safe.max_hp, "off-row enemy remains unharmed")
