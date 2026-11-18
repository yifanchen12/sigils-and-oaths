extends "res://tests/test_campaign_requisition_ui.gd"

const Difficulty = preload("res://scripts/campaign_difficulty.gd")
const STORY_SLOT := "res://.tools/v052-native-story.json"
const LEGACY_BRIDGE := "res://tests/fixtures/v051-active-bridge.json"
const LEGACY_TRIAL := "res://.tools/v052-native-legacy-bridge.json"
const MODEL_SNAPSHOT = preload("res://scripts/battle_snapshot.gd")

func run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var phase: String = arguments[0] if not arguments.is_empty() else ""
	if phase not in ["--prepare", "--launch", "--resume", "--legacy"]:
		push_error("Choose a native difficulty verification stage")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1008, 700))
	var preferences = Settings.new("user://v052-difficulty-ui.cfg")
	check(preferences.save_preferences({"reading_size": 130, "music": 0, "effects": 0}).ok, "real large-reading setting recorded")
	var slot: String = LEGACY_TRIAL if phase == "--legacy" else STORY_SLOT
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_BRIDGE))
	if phase == "--prepare":
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(slot + suffix): DirAccess.remove_absolute(slot + suffix)
		check(Save.new(slot).save_progress(old.progress).ok, "the actual earned bridge briefing is prepared")
	elif phase == "--legacy": check(DirAccess.copy_absolute(LEGACY_BRIDGE, slot) == OK, "copy the real old save to an isolated slot")
	if failures > 0: quit(1); return
	var prelaunch: Dictionary = Save.new(slot).load_progress().get("encounter", {})
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v052-difficulty-native-deck.json")
	game.settings_store = preferences
	game.campaign_session = Session.new(slot)
	root.add_child(game)
	current_scene = game
	await settle()
	var continue_button: Button = find_button(game.council, "继续战役")
	check(continue_button != null and continue_button.is_visible_in_tree(), "the main menu presents the normal continue route")
	if continue_button != null:
		await click(continue_button.get_global_rect().get_center())
		match phase:
			"--prepare":
				await choose_mode()
				if failures == 0: await verify_story_layouts()
			"--launch": await launch_story()
			"--resume", "--legacy": verify_live_save(prelaunch, phase == "--legacy")
	print("DIFFICULTY NATIVE %d CHECKS | %d FAILURES | %s" % [checks, failures, phase])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func choose_mode() -> void:
	var view: Control = game.story_view
	var selector: OptionButton = view.difficulty_choice
	check(view.visible and view.speaker.text == "桥头的两道印" and selector.selected == 0, "standard mode is shown on the old briefing")
	check(view.text_body.text.contains("击败敌方指挥官，控制桥头。"), "standard goal uses the authored commander objective")
	check(not view.backlog_button.disabled, "earned briefing has readable history")
	await click(view.backlog_button.get_global_rect().get_center())
	check(view.showing_history and not selector.is_visible_in_tree(), "history has no live battle setting")
	await click(view.backlog_button.get_global_rect().get_center())
	await click(selector.get_global_rect().get_center())
	var popup: PopupMenu = selector.get_popup()
	check(popup.visible and popup.item_count == 2, "pointer opens the two genuine choices")
	if not popup.visible: return
	await click_window(popup, Vector2(popup.size.x * 0.5, popup.size.y * 0.75))
	check(selector.selected == 1 and game.campaign_session.campaign.difficulty == Difficulty.STORY, "click changes the difficulty through its normal save action")
	check(view.text_body.text.contains("D6、D5") and view.text_body.text.contains("驻守无轮次期限") and view.text_body.text.contains("每回合 90 秒"), "briefing displays the actual positions and both kinds of timer")
	check(view.text_body.text.contains("开局法力和法力上限各多 2") and view.status.text.contains("已保存"), "the assistance and its save are explained in the final briefing")
	var zone: Rect2 = root.get_visible_rect().grow(1)
	check(zone.encloses(selector.get_global_rect()) and zone.encloses(view.actions.get_child(0).get_global_rect()), "selector and start button fit at 1008x700 and 130 percent")
	await capture("v052-story-briefing-small.png")

func verify_story_layouts() -> void:
	var source = Campaign.new()
	var view: Control = game.story_view
	var zone: Rect2 = root.get_visible_rect().grow(1)
	for id: String in ["c06_court", "c07_saltlane_kiln", "c14_upstream_channel", "c17_screen"]:
		var setup: Dictionary = source.index.scenarios[id].duplicate(true)
		setup["difficulty"] = Difficulty.STORY
		setup["armory_slots"] = Campaign.Armory.unlocked_count(int(id.substr(1, 2)) - 1)
		var page: Dictionary = {"type": "battle", "chapter": "战前军议", "attempts": 1, "last_outcome": "defeat", "can_retreat": id == "c07_saltlane_kiln"}
		var history: Array[Dictionary] = []
		view.open(page, {}, setup, history, "已保存剧情难度。", false)
		await settle()
		check(zone.encloses(view.difficulty_choice.get_global_rect()) and zone.encloses(view.armory_button.get_global_rect()), "difficulty and armory fit together at large font size: " + id)
		check(not view.requisition_panel.visible or zone.encloses(view.requisition_choice.get_global_rect()), "requisition still fits with the new setting: " + id)
		for action_button: Control in view.actions.get_children():
			check(zone.encloses(action_button.get_global_rect()), "primary and retreat actions remain visible: " + id)

func launch_story() -> void:
	var view: Control = game.story_view
	check(view.visible and view.difficulty_choice.selected == 1, "a fresh process restores the briefing choice")
	if not view.visible: return
	await click(view.actions.get_child(0).get_global_rect().get_center())
	check(game.has_started and not view.visible and game.battle.players[0].mana == 3 and game.battle.commander(0).shield == 2, "the real battle starts with the shown assistance")
	var goals: Dictionary = game.battle.objective
	check(goals.cells == [[3, 4], [3, 5]] and goals.round_limit == 0 and game.battle.turn_time_limit == 90, "the two battle objectives have no overall deadline and the clock stays active")
	var subtitle: String = game.get_node("%MapName").get_parent().subtitle_text()
	check(subtitle.contains("剧情") and subtitle.contains("驻守 0/1") and not subtitle.contains("/0 轮"), "battle HUD indicates the chosen mode and valid progress")
	if not game.expanded_battlefield: game._toggle_battlefield()
	await settle()
	var plan: Dictionary = {}
	for candidate: Dictionary in game.battle.get_legal_actions(0):
		if candidate.type != "play": continue
		var card: Dictionary = game.battle.definition(game.battle.hand_card(0, candidate.card_uid).card_id)
		if card.type == "unit":
			plan = candidate
			break
	check(not plan.is_empty(), "the authored opener has an affordable unit")
	if plan.is_empty(): return
	for card: CardView in game.get_node("%CompactHand").get_children():
		if card.card_uid != plan.card_uid: continue
		await click(card.get_global_rect().get_center())
		break
	await click(game.board.global_position + game.board.cell_center(plan.target))
	var troops: int = game.battle.army_count(0)
	check(troops == 1 and game.battle.hand_played_this_turn, "actual hand and board clicks deploy and pay for a unit")
	await capture("v052-story-battle-small.png")
	await click(game.get_node("%Restart").get_global_rect().get_center())
	var written: Dictionary = Save.new(STORY_SLOT).load_progress()
	check(game.council.visible and written.ok and written.encounter.difficulty == Difficulty.STORY, "the normal battle menu writes the exact mode and deployed board")

func verify_live_save(prelaunch: Dictionary, legacy: bool) -> void:
	check(game.has_started and not game.story_view.visible and game.campaign_session.encounter == game.battle, "restart resumes directly in the previous battle")
	if prelaunch.is_empty() or not game.has_started: return
	var expected: Dictionary = prelaunch.battle.duplicate(true)
	var current: Dictionary = MODEL_SNAPSHOT.capture(game.battle)
	check(absf(float(current.time_remaining) - float(expected.time_remaining)) < 2.0, "restarted local clock resumes near the exact saved second")
	current.erase("time_remaining")
	expected.erase("time_remaining")
	check(current == expected, "positions, cards, mode objective, RNG and combo flag are restored")
	var text: String = game.get_node("%MapName").get_parent().subtitle_text()
	check(text.contains("剧情") == not legacy, "the active HUD reflects the saved difficulty")
	if legacy: check(game.campaign_session.campaign.difficulty == Difficulty.STANDARD and game.battle.objective.is_empty(), "old standard encounter keeps its commander-only objective")
	else: check(game.campaign_session.campaign.difficulty == Difficulty.STORY and game.battle.army_count(0) == 1, "story mode and its previously deployed unit survive restart")
