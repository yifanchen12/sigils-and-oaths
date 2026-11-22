extends "res://tests/test_ui.gd"

const Settings = preload("res://scripts/settings_store.gd")
const CENTER := Vector2i(5, 5)

func run() -> void:
	DisplayServer.window_set_size(Vector2i(1296, 900))
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v051-pilgrim-native-deck.json")
	game.settings_store = Settings.new("user://v051-pilgrim-native-settings.cfg")
	root.add_child(game)
	current_scene = game
	await settle()
	await verify_collection()
	if failures == 0:
		choose_preset(game.council.deck_choice, "chalkline_vanguard")
		choose_preset(game.council.opponent_choice, "cairn_watch")
		await click(game.council.start_button.get_global_rect().get_center())
		check(game.battle.deck(0).id == "chalkline_vanguard" and game.battle.deck(1).id == "cairn_watch", "new presets are playable through the usual council")
		await verify_combo_hand()
	print("PILGRIM NATIVE UI: %d CHECKS | FAILURES: %d" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func choose_preset(choice: OptionButton, id: String) -> void:
	var index: int = option_index(choice, id)
	check(index >= 0, "preset visible: " + id)
	if index < 0: return
	choice.select(index)
	choice.item_selected.emit(index)

func verify_collection() -> void:
	await click(game.council.library_button.get_global_rect().get_center())
	var dialog: Window = game.get_node("%CardsDialog")
	var sets: OptionButton = game.get_node("%LibrarySet")
	var costs: OptionButton = game.get_node("%LibraryCost")
	var grid: GridContainer = game.get_node("%CardGrid")
	var index: int = option_index(sets, "pilgrim")
	check(dialog.visible and index >= 0 and game.get_node("%LibraryIntro").text.contains("%d 种可组牌" % (Battle.CATALOG.cards.size() - 1)), "full card count and series filter are visible")
	if index < 0: return
	sets.select(index)
	sets.item_selected.emit(index)
	await settle()
	check(grid.get_child_count() == 36, "series filter returns 36 cards with artwork")
	for view: CardView in grid.get_children():
		check(view.card.set_id == "pilgrim" and view.illustration != null, "collection paints " + view.card.id)
	await capture("v051-pilgrim-library.png", dialog)
	var ten: int = costs.get_item_index(11)
	costs.select(ten)
	costs.item_selected.emit(ten)
	await settle()
	check(grid.get_child_count() == 3, "cost filter keeps three ten-mana choices")
	if grid.get_child_count() != 3: return
	for view: CardView in grid.get_children():
		if view.card.id != "thousand_steps": continue
		await click_window(dialog, view.get_global_rect().get_center())
		var text: String = game.get_node("%LibraryDetails").text
		check(text.contains("纵列3格") and text.contains("获2护盾"), "ten-cost card shows both halves of the same column effect")
	await capture("v051-pilgrim-ten-mana.png", dialog)
	dialog.hide()
	await settle()

func verify_combo_hand() -> void:
	if not game.expanded_battlefield: game._toggle_battlefield()
	var battle: Battle = game.battle
	var troop: Dictionary = Fixture.troop(battle, "archer", CENTER + Vector2i.RIGHT)
	battle.terrain[CENTER] = "plain"
	battle.players[0].mana = 7
	battle.players[0].max_mana = 7
	var page: Dictionary = Fixture.give(battle, "page_of_ash")
	var petals: Dictionary = Fixture.give(battle, "petal_signal")
	game._refresh()
	await settle()
	var view: CardView = hand_view(petals.uid)
	check(view != null and not view.combo_lit, "the follow-up is unlit before any card is played")
	await click(board_point(troop.pos))
	await click(board_point(CENTER))
	check(troop.pos == CENTER and troop.moved and not battle.hand_played_this_turn, "real movement leaves combo unavailable")
	var opener: CardView = hand_view(page.uid)
	if opener == null:
		check(false, "opener is visible in the hand")
		return
	await click(opener.get_global_rect().get_center())
	await click(board_point(battle.commander(0).pos))
	check(battle.commander(0).shield == 1 and battle.players[0].mana == 6, "the first card pays and gives its base shield")
	view = hand_view(petals.uid)
	check(view != null and view.combo_lit and view.tooltip_text.contains("连携已就绪"), "a remaining hand card visibly becomes ready")
	if view == null: return
	await click(view.get_global_rect().get_center())
	var point: Vector2 = board_point(CENTER)
	hover(point)
	await settle()
	var forecast: Dictionary = game._effect_context()
	check(game.battle_peek.heading.text == "花落便启程" and game.board.predicted_area.size() == 3 and forecast.note.contains("连携已就绪"),
		"hover shows the three-cell column and the live combo")
	await capture("v051-pilgrim-combo.png")
	await click(point)
	check(troop.shield == 1 and not troop.moved and battle.players[0].mana == 3, "click executes the forecast and restores movement")
	await click(board_point(CENTER))
	await click(board_point(CENTER + Vector2i.RIGHT))
	check(troop.pos == CENTER + Vector2i.RIGHT and troop.moved, "restored movement works through the normal mouse controls")

func hand_view(uid: int) -> CardView:
	for view: CardView in game.get_node("%CompactHand").get_children():
		if view.card_uid == uid: return view
	return null

func board_point(cell: Vector2i) -> Vector2:
	return game.board.global_position + game.board.cell_center(cell)
