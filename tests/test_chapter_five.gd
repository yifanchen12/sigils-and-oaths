extends SceneTree
## Exhaustive narrative paths use explicit victory fixtures, not a playthrough.
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const PATH: String = "res://.tools/test_fifth_chapter.json"
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
	if depth > 650: check(false, "finite five-chapter traversal"); return
	var runner: RefCounted = campaign.story
	var page: Dictionary = runner.current()
	var fifth: bool = runner.graph.id == "chapter_05"
	match page.type:
		"dialogue":
			if fifth: seen[page.line_id] = true
			runner.advance(page.revision); walk(campaign, depth + 1)
		"choice":
			if fifth:
				seen[runner.graph.nodes[page.node].prompt] = true
				if page.node == "mandate": check(runner.state.flags.water_released and runner.state.flags.charter_copy, "mandate is decided only after a successful encounter")
			for option: Dictionary in page.options:
				var branch: RefCounted = Campaign.new()
				var restored: Dictionary = branch.restore(campaign.snapshot())
				if not restored.ok: check(false, "branch restore: " + restored.message); return
				if fifth:
					for authored: Dictionary in runner.graph.nodes[page.node].options:
						if authored.id == option.id: seen[authored.text] = true
				branch.story.choose(option.id, page.revision); walk(branch, depth + 1)
		"battle":
			if fifth:
				check(Campaign.validate_scenario(campaign.scenario()).is_empty(), "actual grove map, class, decks and objective validate")
				if not checkpoints.has(page.scenario): checkpoints[page.scenario] = campaign.snapshot()
				check(not runner.state.flags.water_released and not runner.state.flags.charter_copy and runner.state.flags.grove_mandate == "none", "no water, copy or mandate awarded before victory")
				var before: Dictionary = runner.state.flags.duplicate(true)
				for outcome: int in [1, 2]:
					var resolved: Dictionary = runner.resolve_battle(outcome, runner.current().revision)
					check(resolved.ok and runner.current().type == "battle" and runner.state.flags == before and runner.state.last_outcome == ("defeat" if outcome == 1 else "draw"), "accepted defeat and draw retain choices without granting access")
				page = runner.current()
			runner.resolve_battle(0, page.revision); walk(campaign, depth + 1)
		"end":
			if not fifth:
				if runner.graph.id == "chapter_04": incoming.append(campaign.snapshot())
				campaign.advance_chapter(); walk(campaign, depth + 1)
			else:
				seen[runner.graph.nodes[page.node].text] = true
				terminals.append(campaign.snapshot())
				check(runner.state.decisions.size() == 2 and runner.state.attempts.size() == 1, "two choices and one encounter per fifth-chapter route")
				check(runner.state.flags.water_released and runner.state.flags.charter_copy, "water and charter copy survive chapter completion")
				check(runner.state.flags.water_plan in ["nursery", "channel"] and runner.state.flags.grove_mandate in ["shared", "witness"], "independent water and mandate facts are retained")
				var previous: Dictionary = campaign.completed.back().story.flags
				for key: String in runner.graph.inherits:
					if runner.state.flags[key] != previous[key]: check(false, "inherited fact changed: " + key)
				var copy: RefCounted = Campaign.new()
				check(copy.restore(JSON.parse_string(JSON.stringify(campaign.snapshot()))).ok and copy.snapshot() == campaign.snapshot(), "five-chapter choices and read histories roundtrip")
				check(campaign.next_chapter().is_empty(), "unwritten sixth chapter is not offered")
func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
func test_session() -> void:
	clean()
	var session: RefCounted = Session.new(PATH)
	check(session.campaign.restore(incoming[0]).ok and session.save().ok, "previous completed fourth chapter remains loadable")
	var stale: Dictionary = session.token()
	var history: Array = session.campaign.completed.duplicate(true)
	check(session.next_chapter(stale).ok and session.current().line_id == "c05.arrival.01", "old chapter end enters newly installed fifth chapter")
	check(not session.next_chapter(stale).ok and not session.advance(stale).ok, "prior chapter callbacks cannot advance new chapter")
	for index: int in range(history.size()): check(session.campaign.completed[index] == history[index], "adding a chapter preserves saved past histories")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.campaign.completed.size() == 4 and fresh.current().line_id == "c05.arrival.01", "fresh session resumes fifth chapter opening")
	for id: String in ["c05_nursery", "c05_channel"]:
		clean(); session = Session.new(PATH)
		check(session.campaign.restore(checkpoints[id]).ok, "restore authored upstream checkpoint")
		var started: Dictionary = session.begin_battle(session.token())
		check(started.ok, "begin authored grove encounter")
		if not started.ok: continue
		var battle: Battle = started.battle
		check(battle.map_definition.id == "greenwood" and battle.turn_time_limit == 90 and battle.units.size() == 2 and battle.players[0].hero_id == "grove", "both routes use grove commander, normal opening and 90 seconds")
		battle.advance_clock(7.5)
		check(session.save().ok, "save actual upstream encounter")
		fresh = Session.new(PATH)
		check(fresh.load_campaign().ok and fresh.encounter != null and fresh.encounter.time_remaining == 82.5, "upstream encounter restores exact remaining clock")
		if fresh.encounter == null: continue
		if id == "c05_nursery":
			check(fresh.encounter.objective.cells == [[5, 4], [6, 5]] and fresh.encounter.objective.round_limit == 12 and fresh.encounter.objective_status().contains("F6、G5"), "real control cells and deadline match briefing")
			Fixture.troop(fresh.encounter, "spear", Vector2i(5, 4)); Fixture.troop(fresh.encounter, "sword", Vector2i(6, 5))
			fresh.encounter.end_turn(); fresh.encounter.end_turn()
			check(fresh.encounter.winner == -1 and fresh.encounter.objective.streak == 1, "one control checkpoint does not award victory")
			fresh.encounter.advance_clock(3)
			check(fresh.save().ok, "partial upstream objective saves")
			var resumed: RefCounted = Session.new(PATH)
			check(resumed.load_campaign().ok and resumed.encounter.objective.streak == 1 and resumed.encounter.time_remaining == 87, "fresh session restores objective credit and clock")
			fresh = resumed
			fresh.encounter.end_turn(); fresh.encounter.end_turn()
			check(fresh.encounter.winner == 0 and fresh.encounter.commander(1).hp > 0, "second real checkpoint produces control victory with enemy commander alive")
		else:
			check(fresh.encounter.objective.is_empty(), "channel route uses ordinary commander victory")
			fresh.encounter.commander(1).hp = 0
			fresh.encounter._cleanup(); fresh.encounter._check_winner()
		check(fresh.finish_battle(fresh.encounter).ok and fresh.current().line_id == "c05.after_water.01", "matching encounter advances to actual water consequences")
		check(fresh.campaign.story.state.flags.water_released and fresh.campaign.story.state.flags.grove_mandate == "none", "battle cannot silently grant representative authority")
		check(not fresh.finish_battle(fresh.encounter).ok, "consumed result cannot grant victory twice")
		resumed_after_result(fresh)
	clean()
func resumed_after_result(session: RefCounted) -> void:
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.current().line_id == session.current().line_id and fresh.encounter == null, "resolved water event resumes as story without a stale battle")
func run() -> void:
	var campaign: RefCounted = Campaign.new(); check(campaign.start().ok, "campaign starts")
	walk(campaign)
	check(incoming.size() == 512 and terminals.size() == 2048, "512 actual incoming histories times four water/mandate branches")
	if not terminals.is_empty():
		campaign.restore(terminals[0])
		check(seen.size() == campaign.story.graph.strings.size(), "all fifth-chapter IDs reachable through actual prior decisions")
	if incoming.size() > 0 and checkpoints.size() == 2: test_session()
	print("FIFTH CHAPTER CHECKS: %d | FAILURES: %d | ROUTES: %d | TEXTS: %d" % [checks, failures, terminals.size(), seen.size()])
	quit(0 if failures == 0 else 1)
