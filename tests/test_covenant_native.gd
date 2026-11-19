extends "res://tests/test_campaign_replay_native_ui.gd"

func run() -> void:
	primary_path = "user://chronicle-acceptance-main.json"
	DisplayServer.window_set_size(Vector2i(1008,700))
	for path: String in [primary_path,primary_path+".bak"]:
		check(DirAccess.copy_absolute(ProjectSettings.globalize_path(SOURCE),ProjectSettings.globalize_path(path)) == OK,"open a previously earned ending in an isolated slot")
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(branch_path()+suffix): DirAccess.remove_absolute(branch_path()+suffix)
	var original: String = FileAccess.get_sha256(primary_path)
	game = MainScene.instantiate()
	game.settings_store = Settings.new("user://chronicle-acceptance-settings.cfg")
	check(game.settings_store.save_preferences({"reading_size":130,"music":0,"effects":0}).ok,"use the largest reading size")
	game.campaign_session = Session.new(primary_path)
	root.add_child(game)
	current_scene = game
	await settle()
	await click_control(button(game.council,"继续战役"))
	var original_end: Dictionary = game.campaign_session.current()
	check(original_end.node == "joint_end","continue reopens the earned joint ending")
	await click_control(game.story_view.actions.get_child(0))
	var view: Control = game.replay_view
	check(view.selected_chapter() == "chapter_18" and view.covenant_button.is_visible_in_tree(),"the ending offers its recorded chapter and covenant")
	var graph: Dictionary = game.campaign_session.campaign.story.graph
	var journal: String = view.detail.get_parsed_text()
	check(journal.contains(original_end.text) and journal.contains(original_end.ending_title),"the chapter reader gives the exact reached ending")
	for opt: Dictionary in graph.nodes.covenant.options:
		check(journal.contains(graph.strings[opt.text]) == (opt.id == "joint"), "the journal discloses only the player's chosen terms")
	check(view.detail.get_theme_font_size("normal_font_size") == 23,"chapter records honor 130 percent reading size")
	var visible_bounds: Rect2 = root.get_visible_rect().grow(1)
	for control: Control in [view.shell,view.chapters,view.detail,view.covenant_button,view.start_button,view.close_button]:
		check(visible_bounds.encloses(control.get_global_rect()),"chapter controls remain visible at the smallest native window")
	await key(KEY_UP)
	check(view.selected_chapter() == "chapter_17" and not view.covenant_button.visible and view.detail.get_parsed_text() != journal,"arrow keys reveal the preceding chapter's own choices")
	await key(KEY_DOWN)
	await click_control(view.covenant_button)
	var session: RefCounted = game.campaign_session
	var page: Dictionary = session.current()
	check(page.node == "covenant" and page.options.size() == 3 and not session.campaign.story.state.decisions.has("covenant"),"the branch stops before the sworn choice")
	check(session.store.path == branch_path() and session.campaign.story.state.history.size() > 0,"read pages and inherited decisions enter the separate slot")
	var autosave := Session.new(branch_path())
	check(autosave.load_campaign().ok and autosave.current().node == "covenant" and autosave.campaign.snapshot() == session.campaign.snapshot(),"an independent load reopens the precise unanswered choice")
	if failures == 0:
		check(await choose_story_option("split") and await read_to("split_end"),"choose split governance through the real buttons and read its epilogue")
	if failures == 0:
		check(autosave.load_campaign().ok and autosave.current().node == "split_end","the newly earned ending persists")
		await click_control(game.story_view.actions.get_child(0))
		var prior := FileAccess.get_sha256(branch_path())
		await click_control(view.covenant_button)
		check(game.replay_confirmation.visible and game.replay_confirmation.dialog_text.contains("誓约抉择"),"an existing branch identifies the exact replacement point")
		await click_dialog_button(game.replay_confirmation,game.replay_confirmation.get_cancel_button())
		check(prior == FileAccess.get_sha256(branch_path()) and view.visible,"cancelling retains the completed branch")
		await click_control(view.covenant_button)
		await click_dialog_button(game.replay_confirmation,game.replay_confirmation.get_ok_button())
		check(game.campaign_session.current().node == "covenant","confirmed restart reaches the covenant through the ordinary slot guard")
	check(FileAccess.get_sha256(primary_path) == original and FileAccess.get_sha256(primary_path+".bak") == original,"main save and backup match their original bytes")
	print("CHRONICLE NATIVE ",checks," CHECKS | FAILURES ",failures)
	game.audio.stop_playback()
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
