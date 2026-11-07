extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const PATH: String = "res://.tools/test_fourth_chapter.json"
var checks: int = 0
var failures: int = 0
var incoming: Array[Dictionary] = []
var terminals: Array[Dictionary] = []
var seen: Dictionary = {}
var checkpoints: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func walk(campaign: RefCounted, depth: int = 0) -> void:
	if depth > 550: check(false, "finite four-chapter traversal"); return
	var runner: RefCounted = campaign.story
	var page: Dictionary = runner.current()
	var fourth: bool = runner.graph.id == "chapter_04"
	match page.type:
		"dialogue":
			if fourth: seen[page.line_id] = true
			runner.advance(page.revision); walk(campaign, depth + 1)
		"choice":
			if fourth: seen[runner.graph.nodes[page.node].prompt] = true
			for option: Dictionary in page.options:
				var branch: RefCounted = Campaign.new()
				var restored: Dictionary = branch.restore(campaign.snapshot())
				if not restored.ok: check(false, "branch restores: " + restored.message); return
				if fourth:
					for authored: Dictionary in runner.graph.nodes[page.node].options:
						if authored.id == option.id: seen[authored.text] = true
				branch.story.choose(option.id, page.revision); walk(branch, depth + 1)
		"battle":
			if fourth:
				check(Campaign.validate_scenario(campaign.scenario()).is_empty(), "harbor encounter references actual map and decks")
				if not checkpoints.has(page.scenario): checkpoints[page.scenario] = campaign.snapshot()
				check(not runner.state.flags.harbor_pump and not runner.state.flags.pump_route_known, "pump victory flags cannot be awarded in advance")
				check(runner.state.flags.crew_safe == (page.scenario == "c04_pump"), "crew release follows dock victory and persists into the pump battle")
				var before: Dictionary = runner.state.flags.duplicate(true)
				runner.resolve_battle(1, page.revision)
				check(runner.current().type == "battle" and runner.state.flags == before, "defeat leaves story facts and prior choices unchanged")
				page = runner.current()
			runner.resolve_battle(0, page.revision); walk(campaign, depth + 1)
		"end":
			if not fourth:
				if runner.graph.id == "chapter_03": incoming.append(campaign.snapshot())
				campaign.advance_chapter(); walk(campaign, depth + 1)
			else:
				seen[runner.graph.nodes[page.node].text] = true
				terminals.append(campaign.snapshot())
				check(runner.state.decisions.size() == 2 and runner.state.attempts.size() == 2, "fourth chapter contains two decisions and two resolved encounters")
				check(runner.state.flags.crew_safe and runner.state.flags.harbor_pump and runner.state.flags.pump_route_known, "ending retains the actual harbor victories")
				var previous: Dictionary = campaign.completed.back().story.flags
				for key: String in runner.graph.inherits:
					if runner.state.flags[key] != previous[key]: check(false, "inherited fact changed: " + key)
				var copy: RefCounted = Campaign.new()
				check(copy.restore(JSON.parse_string(JSON.stringify(campaign.snapshot()))).ok and copy.snapshot() == campaign.snapshot(), "four-chapter history and separate shelter/debt choices roundtrip")
				check(campaign.next_chapter().get("id") == "chapter_05", "fourth chapter offers its authored upstream continuation")
func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
func test_session() -> void:
	clean()
	var session: RefCounted = Session.new(PATH)
	check(session.campaign.restore(incoming[0]).ok and session.save().ok, "old completed third chapter remains loadable")
	var old: Dictionary = session.token()
	var history: Array = session.campaign.completed.duplicate(true)
	check(session.next_chapter(old).ok and session.current().line_id == "c04.home.01", "old chapter end can enter newly installed fourth chapter")
	check(not session.next_chapter(old).ok and not session.advance(old).ok, "old chapter callbacks cannot advance the new chapter")
	for index: int in range(history.size()): check(session.campaign.completed[index] == history[index], "installing next chapter preserves prior saved histories")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.campaign.completed.size() == 3 and fresh.current().line_id == "c04.home.01", "new process state resumes fourth chapter opening")
	for id: String in ["c04_dock", "c04_pump"]:
		clean(); session = Session.new(PATH)
		check(session.campaign.restore(checkpoints[id]).ok, "restore real harbor story checkpoint")
		var started: Dictionary = session.begin_battle(session.token())
		check(started.ok, "begin authored harbor encounter")
		if not started.ok: continue
		var battle: Battle = started.battle
		check(battle.map_definition.id == "harbor" and battle.turn_time_limit == 90 and battle.units.size() == 2 and battle.objective.is_empty(), "harbor starts with normal resources, commanders only and no invented escort objective")
		battle.advance_clock(7.5)
		check(session.save().ok, "save actual harbor encounter")
		fresh = Session.new(PATH)
		check(fresh.load_campaign().ok and fresh.encounter != null and fresh.encounter.time_remaining == 82.5, "harbor encounter restores its real clock")
		if fresh.encounter == null: continue
		# A result fixture tests story wiring only; it is not victory evidence.
		fresh.encounter.commander(1).hp = 0
		fresh.encounter._cleanup(); fresh.encounter._check_winner()
		check(fresh.encounter.winner == 0, "result fixture is recognized by canonical victory rules")
		check(fresh.finish_battle(fresh.encounter).ok, "real session accepts matching encounter result")
		check(not fresh.finish_battle(fresh.encounter).ok, "already consumed result cannot award a second victory")
	clean()
func run() -> void:
	var campaign: RefCounted = Campaign.new(); check(campaign.start().ok, "campaign starts")
	walk(campaign)
	check(incoming.size() == 128 and terminals.size() == 512, "128 actual incoming histories times four harbor branches")
	if not terminals.is_empty():
		campaign.restore(terminals[0])
		check(seen.size() == campaign.story.graph.strings.size(), "all fourth-chapter text IDs reachable through actual prior choices")
	if incoming.size() > 0 and checkpoints.size() == 2: test_session()
	print("FOURTH CHAPTER CHECKS: %d | FAILURES: %d | ROUTES: %d | TEXTS: %d" % [checks, failures, terminals.size(), seen.size()])
	quit(0 if failures == 0 else 1)
