extends SceneTree
const Session = preload("res://scripts/campaign_session.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const PATH: String = "res://.tools/chapter_cross_process.json"
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func write_save() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
	var session: RefCounted = Session.new(PATH)
	check(session.new_campaign().ok, "start independent chapter writer")
	var runner: RefCounted = session.campaign.story
	while runner.current().type != "end":
		var page: Dictionary = runner.current()
		match page.type:
			"dialogue": runner.advance(page.revision)
			"choice": runner.choose(page.options[0].id, page.revision)
			"battle": runner.resolve_battle(0, page.revision)
	check(session.next_chapter(session.token()).ok, "transition persists inherited first chapter")
	runner = session.campaign.story
	while runner.current().type == "dialogue": runner.advance(runner.current().revision)
	runner.choose("seed", runner.current().revision)
	while runner.current().type == "dialogue": runner.advance(runner.current().revision)
	var result: Dictionary = session.begin_battle(session.token())
	check(result.ok, "start actual second chapter control battle")
	var battle: RefCounted = result.battle
	Fixture.troop(battle, "spear", Vector2i(3, 5), 0)
	Fixture.troop(battle, "sword", Vector2i(8, 5), 0)
	battle.end_turn(); battle.end_turn(); battle.advance_clock(17.25)
	check(battle.objective.streak == 1 and session.save().ok, "write one-credit bridge state to disk before process exits")
func read_save() -> void:
	var session: RefCounted = Session.new(PATH)
	check(session.load_campaign().ok, "new process resumes chapter two battle")
	if session.encounter == null: check(false, "saved battle exists"); return
	var battle: RefCounted = session.encounter
	check(session.campaign.completed.size() == 1 and session.campaign.story.state.flags.route == "road", "previous chapter and chosen route survive process exit")
	check(session.campaign.story.state.flags.priority == "seed" and session.current().scenario == "c02_seed_bridge", "current choice and scenario survive")
	check(battle.time_remaining == 72.75 and battle.objective.streak == 1 and battle.objective.last_check == 3, "timer and control credit restore without replaying start-turn")
	check(session.backlog()[0].chapter.contains("第一章"), "completed chapter is still readable")
	battle.end_turn(); battle.end_turn()
	check(battle.winner == 0 and not battle.commander(1).is_empty(), "next real turn wins by objective, not fixture commander death")
	check(session.finish_battle(battle).ok and session.current().node == "bridge_after", "objective victory enters authored postbattle dialogue")
	check(not session.finish_battle(battle).ok, "objective result applies only once")
	var repeated: RefCounted = Session.new(PATH)
	check(repeated.load_campaign().ok and repeated.current().line_id == "c02.bridge_after.01" and repeated.encounter == null, "post-objective autosave resumes stable dialogue cursor")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--write"): write_save()
	elif args.has("--read"): read_save()
	else: check(false, "run writer then reader as separate processes")
	print("CHAPTER PROCESS CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
