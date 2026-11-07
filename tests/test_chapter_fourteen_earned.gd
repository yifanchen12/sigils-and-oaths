extends SceneTree
## Legal-action play from real chapter-thirteen saves, against production AI.
const Session = preload("res://scripts/campaign_session.gd")
const AI = preload("res://scripts/opponent.gd")
const Pilot = preload("res://tests/fixtures/channel_push_pilot.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
var checks: int = 0
var failures: int = 0
var games: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func fight(watch: String) -> void:
	var source: String = "res://.tools/v037-test13-joint-%s.json" % watch
	var save: String = "res://.tools/v038-earned14-%s.json" % watch
	if not check(DirAccess.copy_absolute(source, save) == OK, "copy earned thirteenth save: " + watch): return
	var session: RefCounted = Session.new(save)
	if not check(session.load_campaign().ok and session.next_chapter(session.token()).ok, "enter chapter fourteen from earned history: " + watch): return
	while session.current().type == "dialogue":
		if not check(session.advance(session.token()).ok, "read briefing: " + watch): return
	if not check(session.current().type == "battle" and session.begin_battle(session.token()).ok, "start channel battle: " + watch): return
	var row: Dictionary = {"watch": watch, "actions": 0, "bridges_built": 0, "wards_armed": 0, "reloaded": false, "winner": -1}
	while session.encounter.winner == -1 and int(row.actions) < 1000:
		var battle: Battle = session.encounter
		var side: int = battle.active_side
		var action: Dictionary = Pilot.choose(battle) if side == 0 else AI.choose(battle)
		var card_id: String = battle.hand_card(side, int(action.get("card_uid", -1))).get("card_id", "") if action.type == "play" else ""
		battle.advance_clock(0.35)
		if not check(side == battle.active_side and battle.apply_action(action).ok, "legal timed channel action: " + watch): return
		row.actions += 1
		if side == 0 and card_id == "span_kit": row.bridges_built += 1
		if side == 0 and card_id == "countercurrent_ward": row.wards_armed += 1
		if not row.reloaded and battle.turn >= 8 and battle.winner == -1:
			var before: Dictionary = Snapshot.capture(battle)
			if not check(session.save().ok, "channel battle saves mid-match: " + watch): return
			var fresh: RefCounted = Session.new(save)
			if not check(fresh.load_campaign().ok and Snapshot.capture(fresh.encounter) == before, "mid-match channel save restores exactly: " + watch): return
			session = fresh; row.reloaded = true
		await process_frame
	row.winner = session.encounter.winner
	row.turn = session.encounter.turn
	row.streak = session.encounter.objective.streak
	row.blue_hp = session.encounter.commander(0).get("hp", 0)
	row.red_hp = session.encounter.commander(1).get("hp", 0)
	row.blue_units = session.encounter.units.filter(func(unit: Dictionary) -> bool: return unit.side == 0).map(func(unit: Dictionary) -> Variant: return {"kind": unit.kind, "pos": [unit.pos.x, unit.pos.y], "hp": unit.hp})
	row.red_units = session.encounter.units.filter(func(unit: Dictionary) -> bool: return unit.side == 1).map(func(unit: Dictionary) -> Variant: return {"kind": unit.kind, "pos": [unit.pos.x, unit.pos.y], "hp": unit.hp})
	games.append(row)
	if not check(row.winner == 0 and row.reloaded, "legal play wins and resumes channel: " + watch): return
	if not check(session.finish_battle(session.encounter).ok and session.campaign.story.state.flags.channel_secured, "real victory secures channel: " + watch): return
	while session.current().type == "dialogue":
		if not check(session.advance(session.token()).ok, "read earned aftermath: " + watch): return
	if not check(session.current().type == "choice" and session.choose("seal" if watch == "upstream" else "metered", session.token()).ok, "earned route chooses measured water order: " + watch): return
	while session.current().type == "dialogue":
		if not check(session.advance(session.token()).ok, "read earned water consequence: " + watch): return
	check(session.current().type == "end", "earned fourteenth ending: " + watch)

func run() -> void:
	create_timer(900).timeout.connect(func() -> void: push_error("earned channel run timed out"); quit(2))
	for watch: String in ["upstream", "tower"]:
		await fight(watch)
		if failures > 0: break
	var report: Dictionary = {"provenance": "earned chapter-thirteen saves; test-only focus pilot and production opponent; legal timed actions", "human_playtest": false, "games": games, "checks": checks, "failures": failures}
	var file: FileAccess = FileAccess.open("res://docs/chapter14-earned-results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("EARNED FOURTEENTH: %d CHECKS | FAILURES: %d | GAMES: %d" % [checks, failures, games.size()])
	quit(0 if failures == 0 and games.size() == 2 else 1)
