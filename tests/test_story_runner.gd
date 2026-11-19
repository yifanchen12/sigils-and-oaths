extends SceneTree

const Story = preload("res://scripts/story_runner.gd")
const Campaign = preload("res://scripts/campaign.gd")
var checks: int = 0
var failures: int = 0
var routes: int = 0
var seen_lines: Dictionary = {}
var seen_nodes: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(label)

func fixture() -> Dictionary:
	return {"version": 1, "id": "fixture", "title": "Test", "start": "a", "defaults": {"trusted": false, "amount": 0}, "speakers": {"n": "Narrator"},
		"strings": {"one": "Opening", "prompt": "Decision", "yes": "Trust", "no": "Wait", "true_line": "Trusted", "false_line": "Untrusted", "common": "Common", "done": "Complete"},
		"nodes": {
			"a": {"type": "dialogue", "lines": [{"id": "one", "speaker": "n"}], "next": "c"},
			"c": {"type": "choice", "prompt": "prompt", "options": [{"id": "yes", "text": "yes", "set": {"trusted": true, "amount": 2}, "next": "b"}, {"id": "no", "text": "no", "next": "b"}]},
			"b": {"type": "battle", "scenario": "test", "win": "after"},
			"after": {"type": "dialogue", "lines": [{"id": "true_line", "speaker": "n", "when": {"trusted": true}}, {"id": "false_line", "speaker": "n", "when": {"trusted": false}}, {"id": "common", "speaker": "n"}], "next": "end"},
			"end": {"type": "end", "ending": "finished", "text": "done"}}}

func test_validation() -> bool:
	check(Story.validate(fixture()).is_empty(), "valid finite graph")
	for source: Variant in [null, [], {}, {"version": true}]: check(not Story.validate(source).is_empty(), "reject malformed graph root")
	var source: Dictionary = fixture(); source.nodes.a.next = "missing"
	check(not Story.validate(source).is_empty(), "reject dangling jump")
	source = fixture(); source.nodes.after.next = "a"
	check(not Story.validate(source).is_empty(), "reject story cycle")
	source = fixture(); source.nodes["orphan"] = {"type": "end", "text": "done", "ending": "unused"}
	check(not Story.validate(source).is_empty(), "reject disconnected node")
	source = fixture(); source.nodes.c.options[0].set = {"unknown": true}
	check(not Story.validate(source).is_empty(), "reject undeclared variable")
	source = fixture(); source.nodes.c.options[0].set.trusted = "true"
	check(not Story.validate(source).is_empty(), "reject flag type changes")
	source = fixture(); source.nodes.c.options[1].id = "yes"
	check(not Story.validate(source).is_empty(), "reject duplicate option identity")
	source = fixture(); source.strings["unused"] = "Not connected"
	check(not Story.validate(source).is_empty(), "reject unattached prose")
	source = fixture(); source.nodes.c.options[0]["when"] = {"trusted": true}; source.nodes.c.options[1]["when"] = {"trusted": false}
	check(not Story.validate(source).is_empty(), "require unconditional escape from choice")
	source = fixture(); source.nodes.a.lines[0].speaker = "missing"
	check(not Story.validate(source).is_empty(), "reject unknown speaker")
	source = fixture(); source.nodes.b["win_set"] = {"trusted": "true"}
	check(not Story.validate(source).is_empty(), "reject invalid victory fact type")
	source = fixture(); source.nodes.b["win_set"] = {"missing": true}
	check(not Story.validate(source).is_empty(), "reject undeclared victory fact")
	return true

func test_transitions() -> bool:
	for trusted: bool in [true, false]:
		var runner: RefCounted = Story.new(fixture())
		var initial: Dictionary = runner.snapshot()
		check(runner.current().text == "Opening" and runner.snapshot() == initial, "read is pure")
		check(not runner.choose("yes", 0).ok and runner.snapshot() == initial, "wrong action cannot change state")
		check(runner.advance(0).ok and runner.current().type == "choice", "advance enters choice")
		var before: Dictionary = runner.snapshot()
		check(not runner.advance(0).ok and runner.snapshot() == before, "stale advance rejected")
		check(not runner.choose("unknown", 1).ok and runner.snapshot() == before, "unknown choice rejected atomically")
		check(runner.choose("yes" if trusted else "no", 1).ok, "choose accepted once")
		before = runner.snapshot()
		check(not runner.choose("yes", 1).ok and runner.snapshot() == before, "double click does not apply twice")
		check(runner.state.flags.trusted == trusted, "choice writes expected flag")
		check(not runner.resolve_battle(-1, 2).ok and runner.snapshot() == before, "unfinished battle cannot advance")
		check(runner.resolve_battle(1, 2).ok and runner.current().type == "battle" and runner.current().attempts == 1, "defeat retains checkpoint")
		before = runner.snapshot()
		check(not runner.resolve_battle(0, 2).ok and runner.snapshot() == before, "late result from failed attempt rejected")
		check(runner.resolve_battle(2, 3).ok and runner.current().attempts == 2, "draw permits another attempt")
		check(runner.resolve_battle(0, 4).ok and runner.current().text == ("Trusted" if trusted else "Untrusted"), "win selects correct conditional line")
		check(runner.advance(5).ok and runner.current().text == "Common", "hidden dialogue is skipped")
		check(runner.advance(6).ok and runner.current().type == "end", "route reaches finite ending")
		before = runner.snapshot()
		check(not runner.resolve_battle(0, 7).ok and runner.snapshot() == before, "ending rejects repeat reward callback")
		var restored: RefCounted = Story.new(fixture())
		check(restored.restore(JSON.parse_string(JSON.stringify(before))).ok and restored.current().type == "end", "JSON roundtrip preserves completed chapter")
		before.flags.trusted = not trusted
		check(runner.state.flags.trusted == trusted, "exported snapshot does not alias live state")
	return true

func test_restore_validation() -> bool:
	var runner: RefCounted = Story.new(fixture())
	var valid: Dictionary = runner.snapshot()
	for field: String in ["node", "line", "revision", "flags", "decisions", "history", "attempts", "last_outcome"]:
		var broken: Dictionary = valid.duplicate(true); broken.erase(field)
		check(not runner.restore(broken).ok and runner.snapshot() == valid, "missing field rejected atomically " + field)
	for value: Variant in [-1, 99, 0.5, "0", true, INF, NAN]:
		var broken: Dictionary = valid.duplicate(true); broken.line = value
		broken.erase("line_id") # Exercise the legacy index-only format.
		check(not runner.restore(broken).ok and runner.snapshot() == valid, "invalid line rejected")
	var broken: Dictionary = valid.duplicate(true); broken.node = "missing"
	check(not runner.restore(broken).ok, "missing save node rejected")
	broken = valid.duplicate(true); broken.flags.trusted = "false"
	check(not runner.restore(broken).ok, "wrong flag type rejected")
	broken = valid.duplicate(true); broken.history = ["not_written"]
	check(not runner.restore(broken).ok, "missing backlog text rejected")
	broken = valid.duplicate(true); broken.decisions = {"c": "unknown"}
	check(not runner.restore(broken).ok, "unknown saved option rejected")
	broken = valid.duplicate(true); broken.attempts = {"a": 1}
	check(not runner.restore(broken).ok, "nonbattle attempt rejected")
	broken = valid.duplicate(true); broken.flags.erase("amount")
	check(runner.restore(broken).ok and runner.state.flags.amount == 0, "new default flag can fill an older save")
	broken = valid.duplicate(true); broken["extra"] = {"ignored": "field"}
	check(runner.restore(broken).ok and not runner.snapshot().has("extra"), "restore retains only supported plain state")
	return true

func walk_chapter(campaign: RefCounted, depth: int = 0) -> void:
	if depth > 300: check(false, "chapter path terminates within authored graph"); return
	var runner: RefCounted = campaign.story
	var current: Dictionary = runner.current()
	seen_nodes[current.node] = true
	match current.type:
		"dialogue":
			seen_lines[current.line_id] = true
			check(runner.advance(current.revision).ok, "authored line advances " + str(current.line_id))
			walk_chapter(campaign, depth + 1)
		"choice":
			seen_lines[runner.graph.nodes[current.node].prompt] = true
			check(not current.options.is_empty(), "authored choice has visible options")
			var available: Array = []
			for option: Dictionary in current.options: available.append(option.id)
			if current.node == "publication":
				check(available.has("witness") == bool(runner.state.flags.witness_present), "witness option respects actual route")
				check(available.has("copy") == bool(runner.state.flags.seal_copy), "document option respects actual route")
			for option: Dictionary in current.options:
				var branch: RefCounted = Campaign.new()
				check(branch.restore(campaign.snapshot()).ok, "branch snapshot restores")
				check(branch.story.choose(option.id, current.revision).ok, "authored option commits")
				for definition: Dictionary in runner.graph.nodes[current.node].options:
					if definition.id == option.id: seen_lines[definition.text] = true
				walk_chapter(branch, depth + 1)
		"battle":
			var scenario: Dictionary = campaign.scenario()
			check(not scenario.is_empty() and Campaign.validate_scenario(scenario).is_empty(), "authored battle has valid engine configuration")
			check(runner.resolve_battle(0, current.revision).ok, "chapter accepts fixture win once")
			walk_chapter(campaign, depth + 1)
		"end":
			routes += 1
			seen_lines[runner.graph.nodes[current.node].text] = true
			check(runner.state.decisions.size() == 3 and runner.state.attempts.size() == 2, "route has three decisions and two resolved battle nodes")

func test_real_chapter() -> bool:
	var campaign: RefCounted = Campaign.new()
	check(campaign.start().ok, "first chapter loads from actual index")
	if campaign.story == null: return false
	var initial: Dictionary = campaign.snapshot()
	check(not campaign.start("missing").ok and campaign.snapshot() == initial, "unknown chapter cannot destroy progress")
	walk_chapter(campaign)
	check(routes == 8, "eight authored route combinations reach the chapter ending")
	check(seen_nodes.size() == campaign.story.graph.nodes.size(), "every chapter node is reachable")
	check(seen_lines.size() == campaign.story.graph.strings.size(), "every authored text has a reachable condition path")
	for scenario: Dictionary in campaign.index.scenarios.values():
		var broken: Dictionary = scenario.duplicate(true); broken.map = "missing"
		check(not Campaign.validate_scenario(broken).is_empty(), "scenario refuses unknown map instead of fallback")
	return true

func run() -> void:
	for test: String in ["test_validation", "test_transitions", "test_restore_validation", "test_real_chapter"]:
		check(call(test) == true, test + " completed without runtime interruption")
	print("STORY CHECKS: %d | FAILURES: %d | ROUTES: %d | TEXTS: %d | DISPLAY: %s" % [checks, failures, routes, seen_lines.size(), DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
