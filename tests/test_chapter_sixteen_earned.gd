extends SceneTree
## Legal-action East Bridge wins from two actual chapter-fifteen endings.
const Session = preload("res://scripts/campaign_session.gd")
const AI = preload("res://scripts/opponent.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
var checks := 0
var failures := 0
var games: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func fight(watch: String) -> void:
	var source := "res://.tools/v039-earned15-%s.json" % watch
	var save := "res://.tools/v040-earned16-%s.json" % watch
	if not check(DirAccess.copy_absolute(source, save) == OK, "copy prior earned save"): return
	var session: RefCounted = Session.new(save)
	if not check(session.load_campaign().ok and session.next_chapter(session.token()).ok, "enter chapter sixteen from earned history"): return
	while session.current().type == "dialogue":
		if not check(session.advance(session.token()).ok, "read bridge confrontation"): return
	if not check(session.current().type == "battle" and session.begin_battle(session.token()).ok, "start East Bridge battle"): return
	var row: Dictionary = {"watch": watch, "repair_plan": session.campaign.story.state.flags.repair_plan, "actions": 0, "winner": -1, "reloaded": false}
	while session.encounter.winner == -1 and row.actions < 1000:
		var battle: Battle = session.encounter
		var side: int = battle.active_side
		var action: Dictionary = AI.choose(battle)
		battle.advance_clock(0.35)
		if not check(side == battle.active_side and battle.apply_action(action).ok, "legal timed bridge action"): return
		row.actions += 1
		if not row.reloaded and battle.turn >= 8 and battle.winner == -1:
			var before: Dictionary = Snapshot.capture(battle)
			if not check(session.save().ok, "save midbridge battle"): return
			var fresh: RefCounted = Session.new(save)
			if not check(fresh.load_campaign().ok and Snapshot.capture(fresh.encounter) == before, "midbridge battle restores exactly"): return
			session = fresh; row.reloaded = true
		await process_frame
	row.winner = session.encounter.winner
	row.turn = session.encounter.turn
	games.append(row)
	if not check(row.winner == 0 and row.reloaded, "earned route wins with legal actions"): return
	if not check(session.finish_battle(session.encounter).ok and session.campaign.story.state.flags.bridge_open, "real win opens bridge"): return
	while session.current().type == "dialogue":
		if not check(session.advance(session.token()).ok, "read earned aftermath"): return
	var decision := "hearing" if watch == "upstream" else "service"
	if not check(session.current().type == "choice" and session.choose(decision, session.token()).ok, "select earned escort decision"): return
	while session.current().type == "dialogue":
		if not check(session.advance(session.token()).ok, "read earned resolution"): return
	if not check(session.current().type == "end" and session.save().ok, "real win reaches saved chapter end"): return
	var reopened: RefCounted = Session.new(save)
	check(reopened.load_campaign().ok and reopened.current().type == "end" and reopened.campaign.story.state.flags.escort_terms == decision, "earned ending reloads")

func run() -> void:
	create_timer(900).timeout.connect(func() -> void: push_error("earned East Bridge test timed out"); quit(2))
	for watch: String in ["upstream", "tower"]:
		await fight(watch)
		if failures > 0: break
	var report: Dictionary = {"provenance": "two earned chapter-fifteen endings; production AI on both sides; legal timed actions", "human_playtest": false, "games": games, "checks": checks, "failures": failures}
	var file := FileAccess.open("res://docs/chapter16-earned-results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("EARNED SIXTEENTH: %d CHECKS | FAILURES: %d | GAMES: %d" % [checks, failures, games.size()])
	quit(0 if failures == 0 and games.size() == 2 else 1)
