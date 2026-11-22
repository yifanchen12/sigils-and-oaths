extends "res://tests/test_ui.gd"

const Settings = preload("res://scripts/settings_store.gd")

func run() -> void:
	DisplayServer.window_set_size(Vector2i(1296, 900))
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v047-native-deck.json")
	game.settings_store = Settings.new("user://v047-native-settings.cfg")
	root.add_child(game)
	current_scene = game
	await settle()
	var own_index: int = option_index(game.council.deck_choice, "weir_breakers")
	var rival_index: int = option_index(game.council.opponent_choice, "levee_relief")
	check(own_index >= 0 and rival_index >= 0, "both presets appear in the actual menu")
	if failures > 0: quit(1); return
	game.council.deck_choice.select(own_index)
	game.council.deck_choice.item_selected.emit(own_index)
	game.council.opponent_choice.select(rival_index)
	game.council.opponent_choice.item_selected.emit(rival_index)
	await click(game.council.library_button.get_global_rect().get_center())
	var dialog: Window = game.get_node("%CardsDialog")
	var set_filter: OptionButton = game.get_node("%LibrarySet")
	var cost: OptionButton = game.get_node("%LibraryCost")
	var grid: GridContainer = game.get_node("%CardGrid")
	var set_index: int = option_index(set_filter, "levee")
	check(dialog.visible and set_index >= 0, "library exposes the Levee Orders set")
	if failures > 0: quit(1); return
	set_filter.select(set_index)
	set_filter.item_selected.emit(set_index)
	await settle()
	check(grid.get_child_count() == 18, "new set displays every card")
	for view: CardView in grid.get_children():
		check(view.illustration != null and view.card.set_id == "levee", "correct illustrated filter card: " + view.card.id)
	var min_index: int = cost.get_item_index(11)
	cost.select(min_index)
	cost.item_selected.emit(min_index)
	await settle()
	check(grid.get_child_count() == 2 and grid.get_child(1).card.id == "dawn_weir", "10-mana filter offers healer and the weir")
	if failures > 0: quit(1); return
	var weir: CardView = grid.get_child(1)
	await click_window(dialog, weir.get_global_rect().get_center())
	check(game.get_node("%LibraryDetails").text.contains("天明决堤") and game.get_node("%LibraryDetails").text.contains("下回合"), "card library exposes the printed timing")
	await capture("v047-levee-ten-mana.png", dialog)
	dialog.hide()
	await settle()
	await click(game.council.start_button.get_global_rect().get_center())
	check(game.battle.deck(0).id == "weir_breakers" and game.battle.deck(1).id == "levee_relief", "menus start the two actual decks")
	if not game.expanded_battlefield: game._toggle_battlefield()
	await verify_order()
	print("LEVEE NATIVE UI: %d CHECKS | FAILURES: %d" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func verify_order() -> void:
	var center := Vector2i(5, 6)
	var red: Dictionary = game.battle.commander(1)
	red.pos = center + Vector2i.RIGHT
	game.battle.terrain[red.pos] = "plain"
	game.battle.terrain[center] = "plain"
	var left: Dictionary = Fixture.troop(game.battle, "mage", center + Vector2i.LEFT * 3)
	var forward: Dictionary = Fixture.troop(game.battle, "spear", center + Vector2i.UP, 1)
	# Pin the next draw to a ten-cost card so the test isolates the fixed
	# commander's incoming damage while the remote spearman can still act.
	var opponent: Dictionary = game.battle.players[1]
	opponent.discard.append_array(opponent.hand)
	opponent.hand.clear()
	Fixture.give(game.battle, "lantern_surgeon", 1)
	opponent.deck.append(opponent.hand.pop_back())
	var order: Dictionary = Fixture.give(game.battle, "dawn_weir")
	game.battle.players[0].mana = 10
	game.battle.players[0].max_mana = 10
	game._refresh()
	await settle()
	var selected: CardView
	for card: CardView in game.get_node("%CompactHand").get_children():
		if card.card_uid == order.uid: selected = card; break
	check(selected != null and selected.affordable and selected.illustration != null, "a real hand card has payable cost and its own artwork")
	if selected == null: return
	await click(selected.get_global_rect().get_center())
	var point: Vector2 = game.board.global_position + game.board.cell_center(center)
	hover(point)
	await settle()
	check(game.selected_card == order.uid and game.battle_peek.heading.text == "天明决堤" and game.board.predicted_area.size() == 13, "pointer preview paints the 13-cell area and shows the card")
	check(game.board.predicted_losses.is_empty(), "preview shows no immediate damage bars")
	await click(point)
	check(game.battle.pending_orders.size() == 1 and game.battle.players[0].mana == 0 and red.hp == 20 and forward.hp == 7, "real click pays 10 and leaves current health intact")
	await create_timer(0.45).timeout
	hover(point)
	await settle()
	check(game._orders_at(center).contains("第3回合结算") and game.battle_peek.heading.text == "天明决堤", "published alert names the order and due turn")
	await capture("v047-levee-marked-order.png")
	await click(game.get_node("%ViewEnd").get_global_rect().get_center())
	var until: int = Time.get_ticks_msec() + 12000
	while game.ai_running and Time.get_ticks_msec() < until: await create_timer(0.05).timeout
	check(not game.ai_running and game.battle.turn == 3 and game.battle.pending_orders.is_empty(), "production opponent gets its real turn before automatic settlement")
	check(red.hp == 17 and left.hp > 0 and game.battle.last_order_event.get("card_id", "") == "dawn_weir", "order resolves against fixed commander health %d, shield %d, friendly HP %d" % [red.hp, red.shield, left.hp])
