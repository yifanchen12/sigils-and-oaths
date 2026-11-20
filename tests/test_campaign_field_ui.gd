extends "res://tests/test_campaign_requisition_ui.gd"

const Snapshot = preload("res://scripts/battle_snapshot.gd")
const CHANNEL := "res://tests/fixtures/v057-channel-result.json"
const SLOT := "user://field-window-acceptance.json"

func press_key(code: Key) -> void:
	for state: bool in [true,false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.pressed = state
		root.push_input(ev,true)
	await settle()

func run() -> void:
	DisplayServer.window_set_size(Vector2i(1008,700))
	var setup = Settings.new("user://field-window-settings.cfg")
	check(setup.save_preferences({"reading_size":130,"music":0,"effects":0}).ok,"large-text QA profile")
	check(DirAccess.copy_absolute(CHANNEL,SLOT) == OK,"copy previous published terminal save into an isolated slot")
	game = MainScene.instantiate()
	game.settings_store = setup
	game.campaign_session = Session.new(SLOT)
	root.add_child(game)
	current_scene = game
	await settle()
	var resume := find_button(game.council,"继续战役")
	await click(resume.get_global_rect().get_center())
	var view: Control = game.story_view
	if not view.field_button.is_visible_in_tree() or not view.text_body.text.contains("期限"):
		check(false,"the normal continue button opens the authentic failed briefing")
		quit(1); return
	await click(view.field_button.get_global_rect().get_center())
	var panel: Control = view.field_view
	var zone: Rect2 = root.get_visible_rect().grow(1)
	check(panel.visible and not view.content_margin.visible and panel.previous, "review takes focus from the briefing")
	check(panel.reason.text.contains("期限") and panel.record.text.contains("驻守") and panel.subtitle.text.contains("22 个完整轮次"),"saved outcome, turn and public log are readable")
	check(zone.encloses(panel.board.get_global_rect()) and zone.encloses(panel.opening_button.get_global_rect()) and zone.encloses(panel.sidebar.get_global_rect()),"board, controls and scrollable large text fit the 1008×700 window")
	var seal: String = FileAccess.get_sha256(SLOT)
	var badge: Button = panel.points.get_child(-1)
	await click(badge.get_global_rect().get_center())
	check(panel.detail.text.contains("K9") and panel.board.has_focus(),"clicking the second objective inspects the correct cell")
	var from: Vector2i = panel.selected_cell
	await press_key(KEY_LEFT)
	check(panel.selected_cell == from+Vector2i.LEFT, "the keyboard can inspect an adjacent tile")
	await click(panel.board.global_position+panel.board.cell_center(panel.selected_cell),MOUSE_BUTTON_WHEEL_UP)
	check(panel.board.zoom > 1.0 and game.campaign_session.encounter == null, "zoom does not start the encounter")
	await click(panel.opening_button.get_global_rect().get_center())
	check(not panel.previous and panel.deploy_button.is_visible_in_tree() and panel.record_heading.text.contains("起手"),"switching shows the actual opening hand and deployment")
	await press_key(KEY_V)
	check(panel.reach_button.button_pressed and panel.board.enemy_reach_visible and not panel.board.enemy_reach.is_empty(), "the independent briefing's V key draws the active army before deployment")
	var attacker: Dictionary = panel.board.battle.commander(1)
	await click(panel.board.global_position + panel.board.cell_center(attacker.pos))
	check(panel.detail.text.contains("只看" + str(attacker.name)) and panel.detail.text.contains("双齿"), "map inspection identifies the focused enemy and uses shape as well as colour")
	check(zone.encloses(panel.reach_button.get_global_rect()) and zone.encloses(panel.deploy_button.get_global_rect()),"range controls and deploy still fit the minimum-size briefing")
	check(FileAccess.get_sha256(SLOT) == seal and panel.board.battle.time_remaining == 90.0, "reading both maps does not write the save or start the clock")
	await press_key(KEY_ESCAPE)
	check(not panel.visible and view.visible and view.field_button.has_focus(),"Escape returns to the briefing and restores focus")
	await click(view.field_button.get_global_rect().get_center())
	await click(panel.opening_button.get_global_rect().get_center())
	var first: Dictionary = Snapshot.capture(panel.board.battle)
	game.set_process(false)
	await click(panel.deploy_button.get_global_rect().get_center())
	check(game.has_started and not view.visible and Snapshot.capture(game.battle) == first, "deploy starts the previewed battle through the standard button")
	check(game.reach_button.button_pressed and game.board.enemy_reach_visible and game.map_legend.is_visible_in_tree(), "battle inherits the briefing overlay and its visible key")
	await press_key(KEY_TAB)
	check(game.map_legend.is_visible_in_tree() and zone.encloses(game.reach_button.get_global_rect()), "both battlefield layouts expose the toggle and legend")
	await press_key(KEY_V)
	check(not game.board.enemy_reach_visible and game.board.enemy_reach.is_empty(), "live shortcut releases the projection")
	game.audio.stop_playback()
	await create_timer(0.15,true,false,true).timeout
	game.queue_free()
	await process_frame
	print("CAMPAIGN FIELD NATIVE ",checks," CHECKS | ",failures," FAILURES")
	quit(0 if failures == 0 else 1)
