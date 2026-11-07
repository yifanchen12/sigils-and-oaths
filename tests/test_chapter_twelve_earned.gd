extends SceneTree
## Replays chapter-eleven endings earned by native battles; plays depot battles
## with legal actions and production enemy, without fixture victories.
const Session = preload("res://scripts/campaign_session.gd")
const AI = preload("res://scripts/opponent.gd")
const Pilot = preload("res://tests/fixtures/bridge_focus_pilot.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const REPORT: String = "res://docs/chapter12-earned-results.json"
var checks: int = 0
var failures: int = 0
var games: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func fight(session: RefCounted, plan: String) -> bool:
	if not check(session.begin_battle(session.token()).ok, "earned route starts authentic depot battle: " + plan): return false
	var before: Dictionary = session.campaign.snapshot()
	var row: Dictionary = {"governance_plan": plan, "scenario": session.current().scenario, "actions": 0, "reloaded_in_battle": false}
	while session.encounter.winner == -1 and int(row.actions) < 1000:
		var battle: Battle = session.encounter
		var side: int = battle.active_side
		var action: Dictionary = Pilot.choose(battle) if side == 0 else AI.choose(battle)
		battle.advance_clock(0.35)
		if not check(side == battle.active_side and battle.apply_action(action).ok, "legal timed depot action: " + plan): return false
		row.actions += 1
		if not row.reloaded_in_battle and battle.turn >= 8 and battle.winner == -1:
			var expected: Dictionary = Snapshot.capture(battle)
			if not check(session.save().ok, "battle autosave writes authentic state: " + plan): return false
			var fresh: RefCounted = Session.new(session.store.path)
			if not check(fresh.load_campaign().ok and Snapshot.capture(fresh.encounter) == expected, "depot reload preserves complete battle: " + plan): return false
			session = fresh
			row.reloaded_in_battle = true
		await process_frame
	row.winner = session.encounter.winner
	row.turn = session.encounter.turn
	row.objective_streak = session.encounter.objective.streak
	row.reason = "control" if row.winner == 0 and session.encounter.objective.streak >= session.encounter.objective.required else "commander" if row.winner == 0 else "defeat"
	games.append(row)
	if not check(row.winner == 0 and row.reloaded_in_battle, "all earned depot routes can win through legal timed actions: " + plan): return false
	if not check(session.finish_battle(session.encounter).ok and session.campaign.story.state.flags.northbank_access, "actual result alone grants depot access: " + plan): return false
	if not check(session.campaign.story.state.flags.governance_plan == before.story.flags.governance_plan, "depot combat preserves elected governance: " + plan): return false
	while session.current().type == "dialogue":
		if not check(session.advance(session.token()).ok, "read postbattle depot page: " + plan): return false
	if not check(session.current().type == "choice" and session.campaign.story.state.flags.shaft_custody == "none", "custody requires informed postbattle choice: " + plan): return false
	var custody: String = "northbank" if plan == "hold" else "loaned"
	if not check(session.choose(custody, session.token()).ok, "select an actual displayed custody option: " + plan): return false
	while session.current().type == "dialogue":
		if not check(session.advance(session.token()).ok, "read depot ending: " + plan): return false
	if not check(session.current().type == "end" and session.campaign.story.state.flags.shaft_custody == custody, "earned route reaches custody-specific ending: " + plan): return false
	var result: Dictionary = session.campaign.snapshot()
	var reopened: RefCounted = Session.new(session.store.path)
	return check(reopened.load_campaign().ok and reopened.campaign.snapshot() == result, "earned depot ending restores exactly: " + plan)

func run() -> void:
	create_timer(900).timeout.connect(func() -> void: push_error("earned depot run timed out"); quit(2))
	for plan: String in ["joint", "split", "hold"]:
		var source: String = "res://tests/fixtures/v035-earned-chapter11-%s.json" % plan
		var save: String = "res://.tools/v036-earned-chapter12-%s.json" % plan
		if not check(DirAccess.copy_absolute(source, save) == OK, "copy earned prior native save: " + plan): break
		var session: RefCounted = Session.new(save)
		if not check(session.load_campaign().ok and session.current().type == "end" and session.campaign.story.graph.id == "chapter_11", "load earned chapter-eleven ending: " + plan): break
		if not check(session.next_chapter(session.token()).ok and session.campaign.story.graph.id == "chapter_12", "earned route advances into chapter twelve: " + plan): break
		while session.current().type == "dialogue":
			if not check(session.advance(session.token()).ok, "read prebattle depot page: " + plan): break
		if failures > 0 or not check(session.current().type == "battle", "depot battle is required: " + plan): break
		if not await fight(session, plan): break
	var report: Dictionary = {"provenance": "chapter-eleven native earned save fixtures; focus policy uses visible state and legal actions against production opponent", "human_playtest": false, "games": games, "checks": checks, "failures": failures}
	var file: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("EARNED TWELFTH: %d CHECKS | FAILURES: %d | WINS: %d" % [checks, failures, games.filter(func(g: Dictionary) -> bool: return g.winner == 0).size()])
	quit(0 if failures == 0 and games.size() == 3 else 1)
