extends "res://tests/test_campaign_playthrough_ui.gd"
## Native pointer continuation from each saved 0.34 gate victory. The earlier
## battles were replayed from legal winning traces, not human difficulty tests.
var plan: String = "joint"
var lines_seen: int = 0

func writer() -> void:
	var resume: Button = button(game.council, "继续战役")
	check(resume != null, "earned tenth ending offers continue")
	if failures > 0: return
	await click(resume.get_global_rect().get_center())
	check(game.campaign_session.campaign.story.graph.id == "chapter_10" and game.campaign_session.current().type == "end", "real gate victory restores chapter-ten end")
	check(game.campaign_session.campaign.story.state.flags.governance_plan == plan and game.campaign_session.campaign.story.state.flags.tower_gate_secured, "gate win and chosen plan survive")
	if failures > 0: return
	await click(button(game.story_view.actions, "进入").get_global_rect().get_center())
	check(game.campaign_session.campaign.story.graph.id == "chapter_11" and game.campaign_session.campaign.completed.size() == 10, "actual ten-battle history enters eleventh")
	var witnessed: Dictionary = {}
	for step: int in range(150):
		var page: Dictionary = game.campaign_session.current()
		if page.type == "end": break
		check(page.type == "dialogue" and game.story_view.text_body.text == page.text, "earned chapter eleven page renders source text")
		check(game.story_view.Art.get_texture(page.background) != null, "earned chapter eleven page has native scene art")
		if failures > 0: return
		witnessed[page.line_id] = true
		lines_seen += 1
		if page.line_id in ["c11.letter.01", "c11.riverbank.01", "c11.gate_alarm.01"]:
			await capture("v035-" + plan + "-" + page.line_id.replace(".", "-"))
		await click(game.story_view.actions.get_child(0).get_global_rect().get_center())
	check(game.campaign_session.current().type == "end" and game.campaign_session.campaign.story.graph.id == "chapter_11", "witness chapter reaches authored end")
	check(lines_seen >= 105 and witnessed.has("c11.mark.01") and witnessed.has("c11.supply.01"), "witness and immediate supply conflict played before ending")
	check(game.campaign_session.campaign.next_chapter().is_empty(), "no unwritten twelfth chapter offered")
	check(game.campaign_session.save().ok, "earned chapter eleven end saved to disk")
	await capture("v035-" + plan + "-chapter11-ending")
	print("ELEVENTH NATIVE WRITER: %d CHECKS | FAILURES: %d | PLAN: %s | PARAGRAPHS: %d" % [checks, failures, plan, lines_seen])

func reader() -> void:
	var resume: Button = button(game.council, "继续战役")
	check(resume != null, "independent process offers chapter eleven continue")
	if failures > 0: return
	await click(resume.get_global_rect().get_center())
	var campaign: RefCounted = game.campaign_session.campaign
	check(game.story_view.visible and game.campaign_session.encounter == null and campaign.story.graph.id == "chapter_11" and game.campaign_session.current().type == "end", "independent process restores earned witness ending")
	check(campaign.completed.size() == 10 and campaign.story.state.flags.governance_plan == plan and campaign.story.state.flags.tower_gate_secured, "ten prior chapters and real gate victory persist")
	await capture("v035-" + plan + "-chapter11-resumed")
	print("ELEVENTH NATIVE READER: %d CHECKS | FAILURES: %d | PLAN: %s" % [checks, failures, plan])

func run() -> void:
	create_timer(420).timeout.connect(func() -> void: push_error("eleventh native UI timeout"); quit(2))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--plan="): plan = arg.trim_prefix("--plan=")
	writing = OS.get_cmdline_user_args().has("--write")
	check(plan in ["joint", "split", "hold"] and (writing or OS.get_cmdline_user_args().has("--read")), "supported plan and process mode")
	if failures > 0: quit(1); return
	var source_save: String = "res://.tools/v034-native-chapter-ten-" + plan + ".json"
	var save_path: String = "res://.tools/v035-native-chapter-eleven-" + plan + ".json"
	check(FileAccess.file_exists(source_save), "actual gate victory save exists")
	if failures > 0: quit(1); return
	if writing:
		check(DirAccess.copy_absolute(ProjectSettings.globalize_path(source_save), ProjectSettings.globalize_path(save_path)) == OK, "copy earned end to isolated continuation save")
		if failures > 0: quit(1); return
	game = MainScene.instantiate()
	game.deck_store = Store.new("res://.tools/v035-native-deck.json")
	game.campaign_session = Session.new(save_path)
	root.add_child(game); current_scene = game; await settle()
	if writing: await writer()
	else: await reader()
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
