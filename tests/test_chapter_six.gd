extends SceneTree
## Full authored choice histories, with explicit battle-result fixtures.
## No manual or normal-difficulty playthrough is implied by this traversal.
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const PATH: String = "res://.tools/test_sixth_chapter.json"
var checks: int = 0
var failures: int = 0
var incoming: int = 0
var terminals: int = 0
var first_incoming: Dictionary = {}
var first_terminal: Dictionary = {}
var checkpoints: Dictionary = {}
var seen: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func walk(campaign: RefCounted, depth: int = 0) -> void:
	if depth > 850: check(false, "finite six-chapter traversal"); return
	var runner: RefCounted = campaign.story
	var page: Dictionary = runner.current()
	var sixth: bool = runner.graph.id == "chapter_06"
	match page.type:
		"dialogue":
			if sixth: seen[page.line_id] = true
			runner.advance(page.revision); walk(campaign, depth + 1)
		"choice":
			if sixth:
				seen[runner.graph.nodes[page.node].prompt] = true
				if page.node == "letter_choice": check(runner.state.flags.court_access and runner.state.flags.father_trail, "private reading happens after court settlement")
			for option: Dictionary in page.options:
				var branch: RefCounted = Campaign.new()
				var restored: Dictionary = branch.restore(campaign.snapshot())
				if not restored.ok: check(false, "branch restore: " + restored.message); return
				if sixth:
					for authored: Dictionary in runner.graph.nodes[page.node].options:
						if authored.id == option.id: seen[authored.text] = true
				branch.story.choose(option.id, page.revision); walk(branch, depth + 1)
		"battle":
			if sixth:
				check(Campaign.validate_scenario(campaign.scenario()).is_empty(), "court encounter configuration validates")
				var policy: String = runner.state.flags.evidence_council
				if not checkpoints.has(policy): checkpoints[policy] = campaign.snapshot()
				check(not runner.state.flags.court_access and not runner.state.flags.father_trail and runner.state.flags.letter_company == "none", "victory consequences are not awarded at the briefing")
				var before: Dictionary = runner.state.flags.duplicate(true)
				for outcome: int in [1, 2]:
					var resolved: Dictionary = runner.resolve_battle(outcome, runner.current().revision)
					check(resolved.ok and runner.current().type == "battle" and runner.state.flags == before and runner.state.last_outcome == ("defeat" if outcome == 1 else "draw"), "accepted defeat or draw preserves evidence choice without court access")
				page = runner.current()
			runner.resolve_battle(0, page.revision); walk(campaign, depth + 1)
		"end":
			if not sixth:
				if runner.graph.id == "chapter_05":
					incoming += 1
					if first_incoming.is_empty(): first_incoming = campaign.snapshot()
				campaign.advance_chapter(); walk(campaign, depth + 1)
			else:
				seen[runner.graph.nodes[page.node].text] = true
				terminals += 1
				if first_terminal.is_empty(): first_terminal = campaign.snapshot()
				check(runner.state.decisions.size() == 2 and runner.state.attempts.size() == 1, "two decisions and one court encounter per route")
				check(runner.state.flags.court_access and runner.state.flags.father_trail, "court settlement facts retained at end")
				check(runner.state.flags.evidence_council in ["open", "witnessed"] and runner.state.flags.letter_company in ["alone", "companions"], "public evidence and private company remain independent choices")
				var previous: Dictionary = campaign.completed.back().story.flags
				for key: String in runner.graph.inherits:
					if runner.state.flags[key] != previous[key]: check(false, "inherited fact changed: " + key)
				var copy: RefCounted = Campaign.new()
				check(copy.restore(JSON.parse_string(JSON.stringify(campaign.snapshot()))).ok and copy.snapshot() == campaign.snapshot(), "six-chapter decisions and read histories roundtrip")
				check(campaign.next_chapter().get("id") == "chapter_07", "completed court chapter offers installed seventh chapter")
func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
func test_session() -> void:
	clean()
	var session: RefCounted = Session.new(PATH)
	check(session.campaign.restore(first_incoming).ok and session.save().ok, "old fifth-chapter ending saves")
	var history: Array = session.campaign.completed.duplicate(true)
	var stale: Dictionary = session.token()
	check(session.next_chapter(stale).ok and session.current().line_id == "c06.arrival.01", "old ending enters installed sixth chapter")
	check(not session.next_chapter(stale).ok and not session.advance(stale).ok, "old callbacks cannot advance new chapter")
	for index: int in range(history.size()): check(session.campaign.completed[index] == history[index], "earlier complete histories are unchanged")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.campaign.completed.size() == 5 and fresh.current().line_id == "c06.arrival.01", "new session resumes sixth opening from disk")
	for policy: String in ["open", "witnessed"]:
		clean(); session = Session.new(PATH)
		check(session.campaign.restore(checkpoints[policy]).ok, "restore each genuine prebattle evidence branch")
		var started: Dictionary = session.begin_battle(session.token())
		check(started.ok, "court battle begins")
		if not started.ok: continue
		var battle: Battle = started.battle
		check(battle.map_definition.id == "citadel" and battle.players[0].hero_id == "warden" and battle.units.size() == 2 and battle.objective.is_empty() and battle.turn_time_limit == 90, "normal court setup with exact authored hero and no invented escort objective")
		battle.advance_clock(12.5)
		check(session.save().ok, "live court battle saves")
		fresh = Session.new(PATH)
		check(fresh.load_campaign().ok and fresh.encounter != null and fresh.encounter.time_remaining == 77.5 and fresh.campaign.story.state.flags.evidence_council == policy, "fresh session restores battle clock and correct political choice")
		if fresh.encounter == null: continue
		fresh.encounter.commander(1).hp = 0
		fresh.encounter._cleanup(); fresh.encounter._check_winner()
		var ended: Battle = fresh.encounter
		check(fresh.finish_battle(ended).ok and fresh.current().line_id == "c06.after_court.01", "canonical victory hands off to chapter consequences")
		check(not fresh.finish_battle(ended).ok, "consumed encounter cannot be applied twice")
		var resumed: RefCounted = Session.new(PATH)
		check(resumed.load_campaign().ok and resumed.encounter == null and resumed.current().line_id == "c06.after_court.01" and resumed.campaign.story.state.flags.letter_company == "none", "disk resumes story and leaves private reading undecided")
	clean()
func run() -> void:
	var campaign: RefCounted = Campaign.new(); check(campaign.start().ok, "campaign starts")
	walk(campaign)
	check(incoming == 2048 and terminals == 8192, "2048 real incoming histories times four evidence/company choices")
	if not first_terminal.is_empty():
		campaign.restore(first_terminal)
		check(seen.size() == campaign.story.graph.strings.size(), "all sixth-chapter strings reached through actual histories")
	if not first_incoming.is_empty() and checkpoints.size() == 2: test_session()
	print("SIXTH CHAPTER CHECKS: %d | FAILURES: %d | ROUTES: %d | TEXTS: %d" % [checks, failures, terminals, seen.size()])
	quit(0 if failures == 0 else 1)
