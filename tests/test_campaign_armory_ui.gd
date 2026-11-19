extends "res://tests/test_campaign_requisition_ui.gd"

const Armory = preload("res://scripts/campaign_armory.gd")
const ARMORY_SLOT := "res://.tools/v050-native-armory.json"
const MAIN_STORY := "res://tests/fixtures/v048-completed-main.json"
const OLD_ACTIVE := "res://tests/fixtures/v049-active-court.json"
const LEGACY_SLOT := "res://.tools/v050-native-legacy-court.json"
const PICKS: Dictionary = {"vanguard": "quiet_net", "company": "shoal_arbalest", "reserve": "copper_boltline"}

func prepare_briefing() -> bool:
	var session = Session.new(ARMORY_SLOT)
	var opened: Dictionary = session.start_replay_from(Session.new(MAIN_STORY), "chapter_08")
	check(opened.ok, "build an earned chapter-eight branch on disk")
	if not opened.ok: return false
	for page_index: int in range(160):
		var page: Dictionary = session.current()
		if page.type == "battle": return true
		var result: Dictionary
		if page.type == "dialogue": result = session.advance(session.token())
		elif page.type == "choice": result = session.choose(page.options[0].id, session.token())
		else: break
		if not result.ok: return false
	return false

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var phase: String = args[0] if not args.is_empty() else ""
	if phase not in ["--write", "--read", "--resume", "--legacy"]:
		push_error("Choose an armory UI stage")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1008, 700))
	var preferences = Settings.new("user://v050-armory-ui.cfg")
	check(preferences.save_preferences({"reading_size": 130, "music": 0, "effects": 0}).ok, "test actual 130 percent reading settings")
	if phase == "--write":
		check(prepare_briefing(), "use actual chapter dialogue to reach its battle briefing")
	if phase == "--legacy":
		check(DirAccess.copy_absolute(OLD_ACTIVE, LEGACY_SLOT) == OK, "test uses an isolated copy of the published active save")
	if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v050-native-armory-deck.json")
	game.settings_store = preferences
	game.campaign_session = Session.new(LEGACY_SLOT if phase == "--legacy" else ARMORY_SLOT)
	root.add_child(game)
	current_scene = game
	await settle()
	var continue_button: Button = find_button(game.council, "继续战役")
	check(continue_button != null and continue_button.is_visible_in_tree(), "normal continue route is available")
	if continue_button != null:
		await click(continue_button.get_global_rect().get_center())
		match phase:
			"--write": await change_equipment()
			"--read": await draw_and_use()
			"--resume":
				check(game.has_started and not game.story_view.visible and game.battle.turn == 5, "fresh process resumes directly in the same equipped battle")
				check(game.campaign_session.campaign.armory == PICKS and game.battle.visible_traps(0).size() == 1, "the chosen equipment and placed trap are restored")
				if game.battle.visible_traps(0).size() == 1:
					check(game.battle.visible_traps(0)[0].card_id == "quiet_net", "actual equipped card instance remains on the board")
			"--legacy":
				check(game.has_started and game.battle.turn == 3 and game.campaign_session.current().scenario == "c06_court", "published v0.49 battle resumes on its old board")
				check(game.campaign_session.campaign.armory.is_empty() and not game.armory_view.visible, "legacy encounter resumes with empty equipment")
	print("ARMORY NATIVE %d CHECKS | %d FAILURES | %s" % [checks, failures, phase])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	root.push_input(event, true)
	await settle()

func pick_card(slot: String, card: String) -> void:
	var choice: OptionButton = game.armory_view.slots[slot].choice
	var index: int = option_index(choice, card)
	check(index > 0 and not choice.disabled, "desired card is in the unlocked tier")
	if index <= 0: return
	await click(choice.get_global_rect().get_center())
	var popup: PopupMenu = choice.get_popup()
	check(popup.visible, "real popup opens by pointer")
	if not popup.visible: return
	var center := Vector2(popup.size.x * 0.5, popup.size.y * (index + 0.5) / popup.item_count)
	await click_window(popup, center)
	check(game.armory_view.draft.get(slot) == card, "real popup click selects the desired card")

func change_equipment() -> void:
	var story: Control = game.story_view
	var view: Control = game.armory_view
	var saved: String = FileAccess.get_sha256(ARMORY_SLOT)
	check(story.visible and story.armory_button.is_visible_in_tree() and story.armory_button.text.contains("0/3"), "briefing shows three earned slots")
	await click(story.armory_button.get_global_rect().get_center())
	check(view.visible and not story.visible and not game._player_can_act(), "armory is a focused pre-battle screen")
	await pick_card("vanguard", PICKS.vanguard)
	check(FileAccess.get_sha256(ARMORY_SLOT) == saved and game.campaign_session.campaign.armory.is_empty(), "draft clicks leave the previous save intact")
	await press_key(KEY_ESCAPE)
	check(story.visible and not view.visible and FileAccess.get_sha256(ARMORY_SLOT) == saved, "Escape discards draft and returns to the briefing")
	await click(story.armory_button.get_global_rect().get_center())
	for slot: String in PICKS: await pick_card(slot, PICKS[slot])
	if failures > 0: return
	var area: Rect2 = root.get_visible_rect().grow(1)
	for row: Dictionary in view.slots.values():
		check(area.encloses(row.choice.get_global_rect()) and area.encloses(row.rules.get_global_rect()), "130% rules and choice remain inside small window")
		check(row.picture.texture != null and row.swap.text.contains("换下") and not row.rules.text.is_empty(), "chosen card shows original art, outgoing card and effect")
	check(area.encloses(view.save_button.get_global_rect()) and not view.save_button.disabled, "save button fits and accepts the valid draft")
	await capture("v050-campaign-armory-small.png")
	await click(view.save_button.get_global_rect().get_center())
	check(story.visible and story.armory_button.text.contains("3/3") and game.campaign_session.campaign.armory == PICKS, "save commits three cards and returns to the same briefing")
	check(FileAccess.get_sha256(ARMORY_SLOT) != saved and Save.new(ARMORY_SLOT).load_progress().progress.armory == PICKS, "chosen kit is recorded in the intended file")

func draw_and_use() -> void:
	var story: Control = game.story_view
	check(story.visible and story.armory_button.text.contains("3/3") and game.campaign_session.campaign.armory == PICKS, "separate process restores the equipped briefing")
	var session: RefCounted = game.campaign_session
	var normal: Dictionary = Session.create_encounter(session.campaign.scenario(), session.campaign.requisition)
	await click(story.actions.get_child(0).get_global_rect().get_center())
	if not game.expanded_battlefield: game._toggle_battlefield()
	await settle()
	check(game.has_started and game.battle.turn == 1 and game.battle.players[0].hand == normal.battle.players[0].hand, "normal mission keeps its exact authored opener")
	if failures > 0: return
	var delivered: Dictionary = {}
	for slot: Dictionary in Armory.SLOTS:
		var instance: Dictionary = game.battle.players[0].deck[-int(slot.draw)]
		check(instance.card_id == PICKS[slot.id], "the specific reserved instance is in its promised pile position")
		delivered[slot.id] = int(instance.uid)
	var end_button: Button = game.get_node("%ViewEnd")
	Engine.time_scale = 3
	for pass_index: int in range(2):
		await click(end_button.get_global_rect().get_center())
		var limit: int = Time.get_ticks_msec() + 12000
		while game.ai_running and Time.get_ticks_msec() < limit: await create_timer(0.05).timeout
		check(not game.ai_running and game.battle.active_side == 0 and game.battle.winner == -1, "production opponent plays a real response")
		if failures > 0: return
	Engine.time_scale = 1
	check(game.battle.turn == 5 and game.battle.hand_card(0, delivered.vanguard).get("card_id", "") == "quiet_net", "second ordinary draw brings the reserved trap into the actual hand")
	var selected: CardView
	for view: CardView in game.get_node("%CompactHand").get_children():
		if view.card_uid == delivered.vanguard: selected = view; break
	check(selected != null and selected.affordable and selected.illustration != null, "dealt card is visible and payable")
	if selected == null or failures > 0: return
	var target: Vector2i = game.battle.card_targets(delivered.vanguard, 0)[0]
	await click(selected.get_global_rect().get_center())
	var mana: int = game.battle.players[0].mana
	var point: Vector2 = game.board.global_position + game.board.cell_center(target)
	await click(point)
	check(game.battle.visible_traps(0).size() == 1 and game.battle.players[0].mana == mana - 2, "real pointer plays the reserved trap for its normal cost")
	await capture("v050-campaign-armory-trap.png")
	check(session.save().ok, "save actual campaign state with the played equipment")
