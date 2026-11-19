extends "res://tests/test_ui.gd"

const Session = preload("res://scripts/campaign_session.gd")
const Save = preload("res://scripts/campaign_store.gd")
const Settings = preload("res://scripts/settings_store.gd")
const Campaign = preload("res://scripts/campaign.gd")
const LEGACY := "res://tests/fixtures/v047-court-encounter.json"
const PATH := "res://.tools/v048-native-requisition.json"

func find_button(parent: Node, caption: String) -> Button:
	if parent is Button and parent.text == caption: return parent
	for child: Node in parent.get_children():
		var found: Button = find_button(child, caption)
		if found != null: return found
	return null

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--prepare") and not args.has("--launch") and not args.has("--resume"):
		push_error("Choose the native save stage")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1008, 700))
	var settings = Settings.new("user://v048-requisition-ui.cfg")
	check(settings.save_preferences({"reading_size": 130, "music": 0, "effects": 0}).ok, "native QA preferences")
	if args.has("--prepare"):
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
		check(Save.new(PATH).save_progress(old.progress).ok, "earned court briefing written to isolated acceptance slot")
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v048-native-requisition-deck.json")
	game.settings_store = settings
	game.campaign_session = Session.new(PATH)
	root.add_child(game)
	current_scene = game
	await settle()
	var resume: Button = find_button(game.council, "继续战役")
	check(resume != null and resume.is_visible_in_tree(), "standard continue button available")
	if failures > 0: quit(1); return
	await click(resume.get_global_rect().get_center())
	if args.has("--prepare"):
		await choose_at_briefing()
		if failures == 0: await verify_briefing_layouts()
	elif args.has("--launch"):
		await launch_after_restart()
	else:
		check(game.has_started and not game.story_view.visible and game.campaign_session.campaign.requisition == "dawn_weir", "app restarts directly into the saved formation")
		check(has_card("dawn_weir") and not has_card("exchange") and game.battle.deck(0).id == "custom", "selected hand preserved after active-match restart")
	print("REQUISITION NATIVE %d CHECKS | %d FAILURES | %s" % [checks, failures, ",".join(args)])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func choose_at_briefing() -> void:
	var view: Control = game.story_view
	check(view.visible and view.requisition_panel.visible and view.requisition_choice.item_count == 4, "actual court briefing shows three offers and default option")
	check(view.requisition_art.texture != null and view.requisition_text.text.contains("移形军令"), "default shows new illustration and the actual outgoing card")
	if failures > 0: return
	await capture("v048-requisition-default.png")
	await click(view.requisition_choice.get_global_rect().get_center())
	var popup: PopupMenu = view.requisition_choice.get_popup()
	check(popup.visible, "visible popup opens by pointer")
	if not popup.visible: return
	var row: int = option_index(view.requisition_choice, "dawn_weir")
	check(row == 2 and popup.item_count == 4, "ten-mana option is in the real popup")
	if failures > 0: return
	var item_center := Vector2(popup.size.x * 0.5, popup.size.y * (row + 0.5) / popup.item_count)
	await click_window(popup, item_center)
	check(game.campaign_session.campaign.requisition == "dawn_weir" and view.requisition_choice.selected == row, "click commits the offered card through the normal view and store")
	check(view.requisition_art.texture == view.Art.get_texture("dawn_weir") and view.requisition_text.text.contains("7伤害"), "selected capstone art and tactically relevant card text rendered")
	check(not game.campaign_session.unsaved and game.campaign_session.encounter == null, "selection is saved before starting battle")
	if failures == 0: await capture("v048-requisition-selected-small.png")

func launch_after_restart() -> void:
	var view: Control = game.story_view
	check(view.visible and view.requisition_choice.selected == 2 and game.campaign_session.campaign.requisition == "dawn_weir", "fresh process loads the chosen offer before deployment")
	if failures > 0: return
	var start: Button = view.actions.get_child(0)
	await click(start.get_global_rect().get_center())
	check(not view.visible and game.battle.turn == 1 and game.battle.players[0].mana == 1, "normal battle button launches at the actual first turn")
	check(has_card("dawn_weir") and not has_card("exchange") and game.battle.players[0].hand.size() == 5, "ten-mana card is in the displayed hand in place of the exchange")
	if failures > 0: return
	if not game.expanded_battlefield: game._toggle_battlefield()
	await settle()
	for card: CardView in game.get_node("%CompactHand").get_children():
		if card.card.id == "dawn_weir":
			check(not card.affordable and card.illustration != null and card.is_visible_in_tree(), "chosen card has artwork and still costs normal mana")
			await capture("v048-court-hand.png")
			break
	await click(game.get_node("%Restart").get_global_rect().get_center())
	var persisted: Dictionary = Save.new(PATH).load_progress()
	check(game.council.visible and not game.campaign_session.unsaved and persisted.ok, "real menu safely saves the active prepared battle")
	if persisted.ok:
		check(persisted.progress.requisition == "dawn_weir" and persisted.encounter.battle.players[0].deck_counts.dawn_weir == 1, "saved active encounter contains the prepared deck")

func has_card(id: String) -> bool:
	return game.battle.players[0].hand.any(func(card: Dictionary) -> bool: return card.card_id == id)

func verify_briefing_layouts() -> void:
	var catalog = Campaign.new()
	var view: Control = game.story_view
	var page: Dictionary = {"type": "battle", "chapter": "战前军议", "attempts": 1, "last_outcome": "defeat", "can_retreat": false}
	var history: Array[Dictionary] = []
	for id: String in catalog.index.scenarios:
		var setup: Dictionary = catalog.index.scenarios[id].duplicate(true)
		if not setup.has("requisition"): continue
		page.can_retreat = id.begins_with("c07_saltlane_")
		for offer: String in setup.requisition.offers:
			setup["selected_requisition"] = offer
			view.open(page, {}, setup, history, "", false)
			await settle()
			var viewport: Rect2 = root.get_visible_rect().grow(1)
			check(viewport.encloses(view.requisition_panel.get_global_rect()) and viewport.encloses(view.requisition_choice.get_global_rect()), "130% reading size fits requisition selector " + id + " " + offer)
			var scroll: ScrollBar = view.requisition_text.get_v_scroll_bar()
			check(scroll.max_value <= scroll.page + 1.0, "130% reading size shows complete card rule " + id + " " + offer)
			for action: Control in view.actions.get_children():
				check(viewport.encloses(action.get_global_rect()), "130% reading size fits briefing actions " + id + " " + offer)
