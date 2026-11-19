extends "res://tests/test_ui.gd"

const Settings = preload("res://scripts/settings_store.gd")
const CENTER := Vector2i(5, 5)

func run() -> void:
	DisplayServer.window_set_size(Vector2i(1296, 900))
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v053-glassroad-native-deck.json")
	game.settings_store = Settings.new("user://v053-glassroad-native-settings.cfg")
	root.add_child(game)
	current_scene = game
	await settle()
	await verify_library()
	if failures == 0:
		select_preset(game.council.deck_choice, "glassroad_reserve")
		select_preset(game.council.opponent_choice, "glassroad_edict")
		await click(game.council.start_button.get_global_rect().get_center())
		check(game.battle.deck(0).id == "glassroad_reserve" and game.battle.deck(1).id == "glassroad_edict", "both new decks start from the normal council")
		await verify_table()
	print("GLASSROAD NATIVE UI: %d CHECKS | FAILURES: %d" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func select_preset(choice: OptionButton, id: String) -> void:
	var index: int = option_index(choice, id)
	check(index >= 0, "preset can be selected: " + id)
	if index < 0: return
	choice.select(index)
	choice.item_selected.emit(index)

func verify_library() -> void:
	await click(game.council.library_button.get_global_rect().get_center())
	var dialog: Window = game.get_node("%CardsDialog")
	var sets: OptionButton = game.get_node("%LibrarySet")
	var costs: OptionButton = game.get_node("%LibraryCost")
	var grid: GridContainer = game.get_node("%CardGrid")
	var index: int = option_index(sets, "glassroad")
	check(dialog.visible and index >= 0 and game.get_node("%LibraryIntro").text.contains("248 种可组牌"), "catalog displays all collectible cards and Glassroad filter")
	if index < 0: return
	sets.select(index)
	sets.item_selected.emit(index)
	await settle()
	check(grid.get_child_count() == 48, "all 48 new illustrations display under their own set")
	for view: CardView in grid.get_children():
		check(view.card.set_id == "glassroad" and view.illustration != null, "native collection paints " + view.card.id)
	await capture("v053-glassroad-library.png", dialog)
	var ten: int = costs.get_item_index(11)
	costs.select(ten)
	costs.item_selected.emit(ten)
	await settle()
	check(grid.get_child_count() == 4, "ten-mana filter shows four different finishers")
	for view: CardView in grid.get_children():
		if view.card.id != "all_banner_call": continue
		await click_window(dialog, view.get_global_rect().get_center())
		var details: String = game.get_node("%LibraryDetails").text
		check(details.contains("5费、4费、3费") and details.contains("全军最多6支"), "catalog shows the reserve cohorts and deployment cap")
		await capture("v053-glassroad-ten-mana.png", dialog)
	dialog.hide()
	await settle()

func verify_table() -> void:
	if not game.expanded_battlefield: game._toggle_battlefield()
	var battle: Battle = game.battle
	for cell: Vector2i in [CENTER, CENTER + Vector2i.UP, CENTER + Vector2i.DOWN]: battle.terrain[cell] = "plain"
	var ally: Dictionary = Fixture.troop(battle, "mage", CENTER + Vector2i.LEFT)
	var foe: Dictionary = Fixture.troop(battle, "spear", CENTER + Vector2i.RIGHT, 1)
	var hand_card: Dictionary = Fixture.give(battle, "crossroads_whistle")
	battle.players[0].mana = 5
	battle.players[0].max_mana = 5
	game._refresh()
	await settle()
	var view: CardView = hand_view(hand_card.uid)
	check(view != null and not view.escalation_lit, "hand badge is dormant before the threshold")
	battle.players[0].max_mana = 10
	game._refresh()
	await settle()
	view = hand_view(hand_card.uid)
	check(view != null and view.escalation_lit and view.tooltip_text.contains("强化已就绪"), "badge lights with spare, capped-out mana")
	if view == null: return
	await click(view.get_global_rect().get_center())
	hover(board_point(ally.pos))
	await settle()
	check(game._effect_context().get("note", "").contains("急哨护身"), "hovering a friendly target previews the shield mode")
	hover(board_point(foe.pos))
	await settle()
	check(game._effect_context().get("note", "").contains("压低哨音") and game.board.predicted_losses.get(foe.id, 0) == 2, "hovering a hostile target switches to damage")
	await capture("v053-glassroad-dual-order.png")
	var hp: int = foe.hp
	await click(board_point(foe.pos))
	check(foe.hp == hp - 2 and ally.shield == 0 and battle.players[0].mana == 4, "click resolves the announced mode at printed cost")

	# Set up the next card with an empty front and three known troops in reserve.
	battle.players[0].mana = 10
	for id: String in ["breakline_sappers", "mage", "hinge_lancer"]:
		var reserve: Dictionary = Fixture.give(battle, id)
		battle.players[0].hand.erase(reserve)
		battle.players[0].deck.append(reserve)
	var muster: Dictionary = Fixture.give(battle, "all_banner_call")
	game._refresh()
	await settle()
	view = hand_view(muster.uid)
	check(view != null and view.affordable, "ten mana pays for the reserve order in the normal hand")
	if view == null: return
	await click(view.get_global_rect().get_center())
	hover(board_point(CENTER))
	await settle()
	var preview: Dictionary = game._effect_context()
	check(preview.get("note", "").contains("裂垛破障队") and preview.get("note", "").contains("折桥枪卫")
		and preview.get("cells", []).size() == 3 and game.board.predicted_area.size() == 3, "board displays all three predicted landings and their names")
	await capture("v053-glassroad-muster.png")
	var army: int = battle.army_count(0)
	await click(board_point(CENTER))
	check(battle.army_count(0) == army + 3 and battle.players[0].mana == 0 and battle.unit_at(CENTER).summoning,
		"single board click deploys all three with summoning delay")

func hand_view(uid: int) -> CardView:
	for view: CardView in game.get_node("%CompactHand").get_children():
		if view.card_uid == uid: return view
	return null

func board_point(cell: Vector2i) -> Vector2:
	return game.board.global_position + game.board.cell_center(cell)
