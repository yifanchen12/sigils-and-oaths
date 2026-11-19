extends SceneTree
## Play both relay openings and validate the terminal choices from a battle win.
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const AI = preload("res://scripts/opponent.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const REPORT: String = "res://.tools/v041-finale-check.json"
const ENDINGS: Dictionary = {"joint": "shared_lanterns", "split": "streams_apart", "hold": "quiet_reservoir"}
var checks: int = 0
var failures: int = 0
var games: Array[Dictionary] = []
var endings: Array[Dictionary] = []
var earned_sources: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value

func prior_progress(watch: String) -> Dictionary:
	if earned_sources:
		var prior: RefCounted = Session.new("res://.tools/v040-earned16-%s.json" % watch)
		if not check(prior.load_campaign().ok and prior.current().type == "end" and prior.campaign.story.graph.id == "chapter_16", "load prior earned end: " + watch): return {}
		return prior.campaign.snapshot()
	var campaign: RefCounted = Campaign.new()
	if not campaign.start().ok: return {}
	for step: int in range(2000):
		var page: Dictionary = campaign.story.current()
		match page.type:
			"dialogue": campaign.story.advance(page.revision)
			"battle": campaign.story.resolve_battle(0, page.revision)
			"choice":
				var choices: Dictionary = {"night_watch": watch, "repair_choice": "recast" if watch == "upstream" else "sleeve", "escort_choice": "hearing" if watch == "upstream" else "service"}
				var option: String = choices.get(page.node, page.options[0].id)
				if not campaign.story.choose(option, page.revision).ok: return {}
			"end":
				if campaign.story.graph.id == "chapter_16": return campaign.snapshot()
				if not campaign.advance_chapter().ok: return {}
	return {}

func read_to_action(session: RefCounted) -> bool:
	while session.current().type == "dialogue":
		if not check(session.advance(session.token()).ok, "advance authored page"): return false
	return true

func test_deadline(session: RefCounted) -> bool:
	var battle: Battle = session.encounter
	var opening: Dictionary = Snapshot.capture(battle)
	while battle.winner == -1 and battle.turn <= 32:
		if not check(battle.apply_action({"type": "end_turn"}).ok, "waiting is a legal turn"): return false
	if not check(battle.winner == 1 and battle.turn == 33 and battle.objective.streak == 0, "16 complete rounds without a relay expire the mission"): return false
	if not check(Snapshot.restore(Snapshot.capture(battle)).ok, "relay deadline result has a valid snapshot"): return false
	if not check(session.finish_battle(battle).ok and session.current().last_outcome == "defeat" and not session.campaign.story.state.flags.evacuation_complete, "loss persists and grants no route access"): return false
	var restarted: Dictionary = session.begin_battle(session.token())
	if not check(restarted.ok, "begin relay retry: " + str(restarted.get("message", ""))): return false
	var retry: Dictionary = Snapshot.capture(session.encounter)
	var differences: Array = opening.keys().filter(func(key: String) -> bool: return opening[key] != retry.get(key))
	if not check(differences.is_empty(), "retry rebuilds starting state; mismatched fields: " + str(differences)): return false
	return true

func fight(watch: String, kit: String) -> Dictionary:
	var path := "res://.tools/v041-finale-%s.json" % kit
	var session: RefCounted = Session.new(path)
	var prior: Dictionary = prior_progress(watch)
	if not check(not prior.is_empty() and session.campaign.restore(prior).ok, "restore chapter sixteen: " + kit): return {}
	if not check(session.next_chapter(session.token()).ok and session.campaign.story.graph.id == "chapter_17", "old ending enters chapter seventeen"): return {}
	if not read_to_action(session): return {}
	if not check(session.choose(kit, session.token()).ok and session.begin_battle(session.token()).ok, "select and begin new relief battle"): return {}
	var card: String = "march" if kit == "runner" else "oath_ward"
	if not check(session.encounter.players[0].hand.any(func(item: Dictionary) -> bool: return item.card_id == card), "opening hand contains choice card: " + card): return {}
	if kit == "screen" and not test_deadline(session): return {}
	var row: Dictionary = {"kit": kit, "opening_card": card, "actions": 0, "reloaded": false, "defeat_then_retry": kit == "screen"}
	while session.encounter.winner == -1 and row.actions < 500:
		var battle: Battle = session.encounter
		var action: Dictionary = AI.choose(battle)
		var side: int = battle.active_side
		battle.advance_clock(0.35)
		if not check(side == battle.active_side and battle.apply_action(action).ok, "time and action comply with the battle rules"): return {}
		row.actions += 1
		if battle.objective.streak == 1 and not row.reloaded:
			var saved: Dictionary = Snapshot.capture(battle)
			if not check(session.save().ok, "mid-relay save written"): return {}
			var fresh: RefCounted = Session.new(path)
			if not check(fresh.load_campaign().ok and Snapshot.capture(fresh.encounter) == saved, "reload preserves relay progress and all battle data"): return {}
			session = fresh
			row.reloaded = true
		await process_frame
	var completed: Battle = session.encounter
	row.winner = completed.winner
	row.turn = completed.turn
	row.stations = completed.objective.streak
	if not check(row.winner == 0 and row.stations == 3 and row.reloaded and not completed.commander(1).is_empty(), "win by all three relay points, with enemy commander standing"): return {}
	if not check(session.finish_battle(completed).ok and session.campaign.story.state.flags.evacuation_complete, "actual relay win moves the story forward"): return {}
	if not read_to_action(session): return {}
	if not check(session.current().type == "end" and session.next_chapter(session.token()).ok, "earned win opens final chapter"): return {}
	if not read_to_action(session): return {}
	if not check(session.current().type == "choice" and session.current().options.size() == 3, "three final choices are present on an earned route"): return {}
	games.append(row)
	return session.campaign.snapshot()

func finish(branch: Dictionary, plan: String, kit: String) -> void:
	var path := "res://.tools/v041-finale-%s-%s-ending.json" % [kit, plan]
	var session: RefCounted = Session.new(path)
	if not check(session.campaign.restore(branch).ok and session.choose(plan, session.token()).ok, "choose and save " + plan): return
	if not read_to_action(session): return
	var page: Dictionary = session.current()
	if not check(page.type == "end" and page.ending == ENDINGS[plan] and page.has("ending_title") and page.next_chapter.is_empty(), "reach distinct final page for " + plan): return
	var fresh: RefCounted = Session.new(path)
	if not check(fresh.load_campaign().ok and fresh.campaign.snapshot() == session.campaign.snapshot() and fresh.current() == page, "ending round trips for " + plan): return
	var history: Array[Dictionary] = fresh.backlog()
	if not check(not history.is_empty() and history.back().text == page.text and fresh.campaign.story.state.flags.covenant == plan, "ending remains in backlog " + plan): return
	endings.append({"kit": kit, "plan": plan, "ending": page.ending})

func run() -> void:
	create_timer(600).timeout.connect(func() -> void: push_error("finale test timed out"); quit(2))
	earned_sources = OS.get_cmdline_user_args().has("--earned")
	for kit: String in ["runner", "screen"]:
		var branch: Dictionary = await fight("upstream" if kit == "runner" else "tower", kit)
		if branch.is_empty(): break
		for plan: String in ENDINGS: finish(branch, plan, kit)
	if check(games.size() == 2 and endings.size() == 6, "both battles and all six final continuations ran"):
		var out := FileAccess.open(REPORT, FileAccess.WRITE)
		if out != null:
			out.store_string(JSON.stringify({"earned_0_40_sources": earned_sources, "games": games, "endings": endings, "checks": checks, "failures": failures}, "\t", true, true) + "\n")
			out.close()
	print("FINALE: %d CHECKS | FAILURES: %d | WINS: %d | ENDINGS: %d" % [checks, failures, games.size(), endings.size()])
	quit(0 if failures == 0 else 1)
