extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const PATH: String = "res://.tools/test_third_chapter.json"
var checks: int = 0
var failures: int = 0
var preceding: Array[Dictionary] = []
var terminals: Array[Dictionary] = []
var seen: Dictionary = {}
var checkpoints: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func walk(campaign: RefCounted, depth: int = 0) -> void:
	if depth > 400: check(false, "finite three-chapter traversal"); return
	var runner: RefCounted = campaign.story
	var page: Dictionary = runner.current()
	var third: bool = runner.graph.id == "chapter_03"
	match page.type:
		"dialogue":
			if third: seen[page.line_id] = true
			runner.advance(page.revision); walk(campaign, depth + 1)
		"choice":
			if third: seen[runner.graph.nodes[page.node].prompt] = true
			for option: Dictionary in page.options:
				var branch: RefCounted = Campaign.new()
				var restored: Dictionary = branch.restore(campaign.snapshot())
				if not restored.ok: check(false, "branch restores: " + restored.message); return
				if third:
					for authored: Dictionary in runner.graph.nodes[page.node].options:
						if authored.id == option.id: seen[authored.text] = true
				branch.story.choose(option.id, page.revision); walk(branch, depth + 1)
		"battle":
			if third:
				check(runner.state.flags.supply_route == "none" and not runner.state.flags.mine_cargo, "no route reward before third-chapter victory")
				check(Campaign.validate_scenario(campaign.scenario()).is_empty(), "third-chapter scenario validates against real maps and decks")
				if not checkpoints.has(page.scenario): checkpoints[page.scenario] = campaign.snapshot()
				var before: Dictionary = runner.state.flags.duplicate(true)
				runner.resolve_battle(1, page.revision)
				check(runner.current().type == "battle" and runner.state.flags == before, "defeat retains route without fabricating cargo or supply access")
				page = runner.current()
			runner.resolve_battle(0, page.revision); walk(campaign, depth + 1)
		"end":
			if runner.graph.id == "chapter_01":
				campaign.advance_chapter(); walk(campaign, depth + 1)
			elif not third:
				preceding.append(campaign.snapshot())
				campaign.advance_chapter(); walk(campaign, depth + 1)
			else:
				seen[runner.graph.nodes[page.node].text] = true
				terminals.append(campaign.snapshot())
				check(runner.state.decisions.size() == 2 and runner.state.attempts.size() == 1, "each route has two choices and one battle")
				check(runner.state.flags.letter_delivered and runner.state.flags.mine_cargo, "letter and cargo facts survive completed route")
				check(runner.state.flags.supply_route == ("maintenance" if runner.state.flags.pass_route == "vent" else "long_road"), "battle awards the chosen supply route")
				var copy: RefCounted = Campaign.new()
				check(copy.restore(JSON.parse_string(JSON.stringify(campaign.snapshot()))).ok and copy.snapshot() == campaign.snapshot(), "three-chapter history roundtrips")
				check(campaign.next_chapter().get("id") == "chapter_04", "third chapter offers its authored harbor continuation")
func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
func test_session() -> void:
	clean()
	var session: RefCounted = Session.new(PATH)
	check(session.campaign.restore(preceding[0]).ok and session.save().ok, "save completed second chapter")
	var old: Dictionary = session.token()
	check(session.next_chapter(old).ok and session.current().chapter.contains("第三章"), "saved second-chapter button enters third")
	check(not session.next_chapter(old).ok and not session.advance(old).ok, "old second-chapter callbacks are invalid")
	var resumed: RefCounted = Session.new(PATH)
	check(resumed.load_campaign().ok and resumed.campaign.completed.size() == 2 and resumed.current().line_id == "c03.arrival.01", "fresh session resumes opening and two prior histories")
	check(resumed.backlog().any(func(line: Dictionary) -> bool: return line.chapter.contains("第一章")) and resumed.backlog().any(func(line: Dictionary) -> bool: return line.chapter.contains("第二章")), "both previous chapters remain readable")
	for key: String in ["c03_vent", "c03_ridge"]:
		clean(); session = Session.new(PATH)
		check(session.campaign.restore(checkpoints[key]).ok, "restore authored route checkpoint")
		var started: Dictionary = session.begin_battle(session.token())
		check(started.ok, "start " + key)
		if not started.ok: continue
		var battle: RefCounted = started.battle
		check(battle.map_definition.id == "ridgepass" and battle.hero(1).name == "掌运官杜骞" and battle.turn_time_limit == 90, "new route uses authored map, identity and clock")
		if key == "c03_vent":
			check(battle.objective.cells == [[4, 4], [7, 5]] and battle.objective.round_limit == 10 and battle.objective_status().contains("E6、H5"), "wind vents match coordinates and deadline in briefing")
			Fixture.troop(battle, "spear", Vector2i(4, 4)); Fixture.troop(battle, "sword", Vector2i(7, 5))
			battle.end_turn(); battle.end_turn(); battle.advance_clock(11.5)
			check(session.save().ok, "save mid-control battle")
			resumed = Session.new(PATH)
			check(resumed.load_campaign().ok and resumed.encounter != null, "resume wind-vent battle")
			if resumed.encounter == null: continue
			battle = resumed.encounter
			check(battle.objective.streak == 1 and battle.objective.last_check == 3 and battle.time_remaining == 78.5, "resume without extra objective credit or resetting time")
			battle.end_turn(); battle.end_turn()
			check(battle.winner == 0 and not battle.commander(1).is_empty(), "second real control check wins without commander kill")
			check(resumed.finish_battle(battle).ok and resumed.current().node == "vent_after" and resumed.campaign.story.state.flags.supply_route == "maintenance", "control result advances only the selected route")
			check(not resumed.finish_battle(battle).ok, "late duplicate result cannot award twice")
		else:
			check(battle.objective.is_empty() and battle.players[0].deck_id == "assault", "ridge assault has no control objective and the assault deck")
	clean()
func run() -> void:
	var campaign: RefCounted = Campaign.new(); campaign.start(); walk(campaign)
	check(preceding.size() == 32 and terminals.size() == 128, "32 incoming histories times four third-chapter routes")
	if not terminals.is_empty():
		campaign.restore(terminals[0])
		check(seen.size() == campaign.story.graph.strings.size(), "every third-chapter string reachable through actual inherited history")
	if not preceding.is_empty() and checkpoints.size() == 2: test_session()
	print("THIRD CHAPTER CHECKS: %d | FAILURES: %d | ROUTES: %d | TEXTS: %d | DISPLAY: %s" % [checks, failures, terminals.size(), seen.size(), DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
