extends SceneTree
## Start at the first line and let real, unmodified battle outcomes gate the
## story. Stop at the first defeat; never insert victory or jump to a chapter.
const Session = preload("res://scripts/campaign_session.gd")
const AI = preload("res://scripts/opponent.gd")
const HarborPilot = preload("res://tests/fixtures/harbor_court_pilot.gd")
const FocusPilot = preload("res://tests/fixtures/bridge_focus_pilot.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Replay = preload("res://tests/test_campaign_replays.gd")
const SAVE: String = "res://.tools/continuous_diagnostic_save.json"
var checks: int = 0
var failures: int = 0
var session: RefCounted
var pump_focus: bool = false
var nursery_focus: bool = false
var court_focus: bool = false
var report: Dictionary = {"policy": "production opponent on both sides", "coverage": "continuous_campaign", "note": "New campaign, first visible choices (except the declared opening route and priority), real battle results and save/reload. Stops at first defeat. Automated diagnostic, not a human playthrough or balance verdict.", "route": "road", "priority": "relief", "choices": [], "chapters_entered": [], "dialogue_ids": [], "games": [], "reached_authored_end": false, "stop": ""}

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures += 1; push_error(label)
	return value

func reload_exact() -> bool:
	var progress: Dictionary = session.campaign.snapshot()
	var encounter: Dictionary = Snapshot.capture(session.encounter) if session.encounter != null else {}
	if not check(session.save().ok, "continuous route saves through the real coordinator"): return false
	var fresh: RefCounted = Session.new(SAVE)
	if not check(fresh.load_campaign().ok, "fresh session reads the same disk save"): return false
	if not check(fresh.campaign.snapshot() == progress, "all story flags, choices, history, attempts and cursors survive reload"): return false
	if not check((Snapshot.capture(fresh.encounter) if fresh.encounter != null else {}) == encounter, "battle including cards, RNG and precise clock survives reload"): return false
	session = fresh
	return true

func fight() -> bool:
	var scenario: String = session.current().scenario
	var before: Dictionary = session.campaign.snapshot()
	if not check(session.begin_battle(session.token()).ok, "begin actual encountered battle " + scenario): return false
	var row: Dictionary = {"scenario": scenario, "story_before": before, "trace": [], "reload_at_action": -1}
	var restored: bool = false
	while session.encounter.winner == -1 and row.trace.size() < 1000:
		var b: Battle = session.encounter
		var side: int = b.active_side
		var actor: Script = AI
		if side == 0 and pump_focus and scenario == "c04_pump": actor = HarborPilot
		if side == 0 and nursery_focus and scenario == "c05_nursery": actor = FocusPilot
		if side == 0 and court_focus and scenario == "c06_court": actor = HarborPilot
		var action: Dictionary = actor.choose(b)
		b.advance_clock(0.35)
		if not check(side == b.active_side and b.apply_action(action).ok, "continuous battle action is legal and within the actual clock"): return false
		var portable: Dictionary = action.duplicate(true)
		if portable.get("target") is Vector2i: portable.target = [portable.target.x, portable.target.y]
		row.trace.append({"side": side, "turn_after": b.turn, "elapsed": 0.35, "action": portable})
		if not restored and b.turn >= 8 and b.winner == -1:
			row.reload_at_action = row.trace.size()
			if not reload_exact(): return false
			restored = true
		await process_frame
	var battle: Battle = session.encounter
	row.final = Snapshot.capture(battle)
	row.winner = battle.winner; row.turn = battle.turn; row.actions = row.trace.size()
	if not check(battle.winner in [0, 1, 2], "continuous battle reaches a real terminal result before the action cap"): return false
	if not check(session.finish_battle(battle).ok, "only the authoritative battle result advances the story"): return false
	row.story_after = session.campaign.snapshot()
	report.games.append(row)
	if not reload_exact(): return false
	print("CONTINUOUS %s | WINNER %d | TURN %d | ACTIONS %d" % [scenario, row.winner, row.turn, row.actions])
	if row.winner != 0:
		check(session.current().type == "battle" and session.current().scenario == scenario, "defeat stays at its own encounter without granting a later chapter")
		check(session.campaign.story.state.flags == before.story.flags, "defeat grants no victory flags")
		check(session.campaign.story.state.history == before.story.history, "defeat invents no unread story history")
		check(session.campaign.story.state.attempts.get(before.story.node, 0) == int(before.story.attempts.get(before.story.node, 0)) + 1, "defeat is persisted exactly once")
		report.stop = "defeat" if row.winner == 1 else "draw"
		return false
	return true

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--route="): report.route = arg.trim_prefix("--route=")
		if arg.begins_with("--priority="): report.priority = arg.trim_prefix("--priority=")
		if arg == "--pump-focus": pump_focus = true
		if arg == "--nursery-focus": nursery_focus = true
		if arg == "--court-focus": court_focus = true
	if pump_focus or nursery_focus or court_focus:
		var selected_policies: Array[String] = []
		if pump_focus: selected_policies.append("c04_pump harbor focus player")
		if nursery_focus: selected_policies.append("c05_nursery wounded/support focus player")
		if court_focus: selected_policies.append("c06_court central-formation focus player")
		report.policy = "production on both sides except " + ", ".join(selected_policies)
		report.note = "Actual new campaign with real battle results. Focus policies use visible positions, health and terrain; no hidden cards, RNG peek, fixture victory or chapter jump. Stops at first defeat. Not human balance evidence."
	if not check(report.route in ["road", "river"], "opening route is explicit and recognized"): quit(1); return
	if not check(report.priority in ["relief", "seed"], "chapter-two priority is explicit and recognized"): quit(1); return
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SAVE + suffix): DirAccess.remove_absolute(SAVE + suffix)
	session = Session.new(SAVE)
	if not check(session.new_campaign().ok, "start a genuine new campaign"): quit(1); return
	var pages: int = 0
	while failures == 0 and pages < 5000:
		pages += 1
		var chapter: String = session.campaign.story.graph.id
		if not report.chapters_entered.has(chapter): report.chapters_entered.append(chapter)
		var page: Dictionary = session.current()
		match String(page.type):
			"dialogue":
				if not report.dialogue_ids.has(page.line_id): report.dialogue_ids.append(page.line_id)
				check(session.advance(session.token()).ok, "advance one actual dialogue page")
			"choice":
				var option: String = report.route if chapter == "chapter_01" and page.node == "route" else (report.priority if chapter == "chapter_02" and page.node == "priority" else page.options[0].id)
				report.choices.append({"chapter": chapter, "node": page.node, "option": option})
				check(session.choose(option, session.token()).ok, "choose a currently displayed option")
			"battle":
				if not await fight(): break
			"end":
				if session.campaign.next_chapter().is_empty(): report.reached_authored_end = true; report.stop = "authored_end"; break
				check(session.next_chapter(session.token()).ok, "next chapter inherits the earned story outcome")
				if not reload_exact(): break
	check(pages < 5000, "continuous narrative finishes or stops without a graph loop")
	if failures > 0: report.stop = "invalid"
	report.progress = session.campaign.snapshot()
	var destination: String = "res://.tools/continuous-campaign-" + report.route + ("-seed" if report.priority == "seed" else "") + ("-pump-focus" if pump_focus else "") + ("-nursery-focus" if nursery_focus else "") + ("-court-focus" if court_focus else "") + ".json"
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if not check(file != null, "write complete continuous diagnostic including defeat"): quit(1); return
	report.checks = checks; report.failures = failures
	file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("CONTINUOUS CAMPAIGN CHECKS: %d | FAILURES: %d | GAMES: %d | DIALOGUES: %d | STOP: %s | AUTHORED_END: %s" % [checks, failures, report.games.size(), report.dialogue_ids.size(), report.stop, report.reached_authored_end])
	quit(0 if failures == 0 else 1)
