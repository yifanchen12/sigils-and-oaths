extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const Store = preload("res://scripts/campaign_store.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Story = preload("res://scripts/story_runner.gd")
const PATH: String = "res://.tools/test_chapters.json"
var checks: int = 0
var failures: int = 0
var first_endings: Array[Dictionary] = []
var second_endings: Array[Dictionary] = []
var seen: Dictionary = {}
var seen_nodes: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
func walk(campaign: RefCounted, depth: int = 0) -> void:
	if depth > 300: check(false, "finite route terminates"); return
	var runner: RefCounted = campaign.story
	var page: Dictionary = runner.current()
	var second: bool = runner.graph.id == "chapter_02"
	if second: seen_nodes[page.node] = true
	match page.type:
		"dialogue":
			if second: seen[page.line_id] = true
			runner.advance(page.revision)
			walk(campaign, depth + 1)
		"choice":
			if second: seen[runner.graph.nodes[page.node].prompt] = true
			for option: Dictionary in page.options:
				var branch: RefCounted = Campaign.new()
				check(branch.restore(campaign.snapshot()).ok, "branch restores complete chapter history")
				check(branch.story.choose(option.id, page.revision).ok, "visible choice accepted")
				if second:
					for definition: Dictionary in runner.graph.nodes[page.node].options:
						if definition.id == option.id: seen[definition.text] = true
				walk(branch, depth + 1)
		"battle":
			check(Campaign.validate_scenario(campaign.scenario()).is_empty(), "authored encounter configuration is valid")
			runner.resolve_battle(0, page.revision)
			walk(campaign, depth + 1)
		"end":
			if not second:
				first_endings.append(campaign.snapshot())
				return
			seen[runner.graph.nodes[page.node].text] = true
			second_endings.append(campaign.snapshot())
			check(runner.state.decisions.size() == 2 and runner.state.attempts.size() == 2, "second chapter contains two decisions and two battles")
			check(runner.state.flags.dispatch_receipts and runner.state.flags.clerk_safe, "chapter victories supply receipts and clerk safety")
			check(campaign.next_chapter().get("id") == "chapter_03", "second chapter exposes the authored third chapter")
func test_paths() -> bool:
	var campaign: RefCounted = Campaign.new()
	check(campaign.start().ok, "first chapter starts")
	var initial: Dictionary = campaign.snapshot()
	check(not campaign.advance_chapter().ok and campaign.snapshot() == initial, "unfinished chapter cannot skip ahead")
	check(not campaign.start("chapter_02").ok and campaign.snapshot() == initial, "direct chapter start cannot erase inherited facts")
	walk(campaign)
	check(first_endings.size() == 8, "all eight first chapter endings reached")
	for ending: Dictionary in first_endings:
		check(campaign.restore(ending).ok, "first ending restores")
		check(campaign.next_chapter().id == "chapter_02" and campaign.advance_chapter().ok, "completed chapter advances to registered successor")
		check(campaign.completed.size() == 1 and campaign.completed[0].story == ending.story, "prior chapter is retained unchanged")
		for key: String in ending.story.flags:
			check(campaign.story.state.flags[key] == ending.story.flags[key], "prior choice inherited: " + key)
		check(campaign.story.current().revision == 0, "new chapter has a fresh revision")
		walk(campaign)
	check(second_endings.size() == 32, "eight inherited states times four second chapter choices terminate")
	check(seen.size() == campaign.story.graph.strings.size() and seen_nodes.size() == campaign.story.graph.nodes.size(), "every second chapter string and node reachable")
	for ending: Dictionary in second_endings:
		var copy: RefCounted = Campaign.new()
		check(copy.restore(JSON.parse_string(JSON.stringify(ending))).ok and copy.snapshot() == ending, "two chapter terminal save restores without drift")
	return true
func test_transition_save() -> bool:
	cleanup()
	var session: RefCounted = Session.new(PATH)
	check(session.campaign.restore(first_endings[0]).ok and session.save().ok, "prepare real chapter end save")
	var old_token: Dictionary = session.token()
	var old_state: Dictionary = session.campaign.snapshot()
	var old_file: String = FileAccess.get_file_as_string(PATH)
	session.store.path = "res://.tools/missing_chapter_directory/save.json"
	check(not session.next_chapter(old_token).ok and session.campaign.snapshot() == old_state and session.token() == old_token, "failed transition save leaves current chapter and token unchanged")
	check(FileAccess.get_file_as_string(PATH) == old_file, "failed write cannot change last good on-disk ending")
	session.store.path = PATH
	check(session.next_chapter(old_token).ok, "retry saves and enters next chapter")
	check(session.current().chapter.contains("第二章") and session.epoch == old_token.epoch + 1, "chapter transition invalidates previous session callbacks")
	var new_state: Dictionary = session.campaign.snapshot()
	check(not session.next_chapter(old_token).ok and not session.advance(old_token).ok and session.campaign.snapshot() == new_state, "stale chapter callbacks cannot advance twice")
	var loaded: RefCounted = Session.new(PATH)
	check(loaded.load_campaign().ok and loaded.campaign.snapshot() == new_state, "cross-chapter save resumes at exact new opening")
	check(loaded.backlog().size() > 40 and loaded.backlog()[0].chapter.contains("第一章"), "prior chapter read history remains available")
	var history: Array = loaded.backlog(); history[0].text = "changed"
	check(loaded.backlog()[0].text != "changed", "cross-chapter backlog is a copy")
	while loaded.current().type == "dialogue": loaded.campaign.story.advance(loaded.current().revision)
	check(loaded.choose("relief", loaded.token()).ok, "choose second chapter bridge loadout")
	while loaded.current().type == "dialogue": loaded.campaign.story.advance(loaded.current().revision)
	var result: Dictionary = loaded.begin_battle(loaded.token())
	check(result.ok and result.battle.objective.required == 2 and result.battle.hero(0).id == "grove", "authored objective and choice-dependent army applied")
	var disk: Dictionary = loaded.store.load_progress()
	check(disk.ok and disk.encounter.battle.objective.streak == 0, "campaign saves full objective state")
	var forged: Dictionary = disk.encounter.duplicate(true)
	forged.battle.objective.round_limit = 11
	check(not loaded.store.save_progress(disk.progress, forged).ok, "valid but mismatched objective configuration rejected")
	check(loaded.store.load_progress().encounter == disk.encounter, "failed mismatched save preserves valid battle")
	cleanup()
	return true
func test_invalid_history() -> bool:
	var campaign: RefCounted = Campaign.new()
	check(campaign.restore(second_endings[0]).ok, "set complete two-chapter state")
	var good: Dictionary = campaign.snapshot()
	for change: String in ["missing", "incomplete", "wrong_order", "duplicate", "changed_fact", "missing_fact"]:
		var bad: Dictionary = good.duplicate(true)
		match change:
			"missing": bad.erase("completed")
			"incomplete":
				var fresh: RefCounted = Campaign.new(); fresh.start()
				bad.completed[0].story = fresh.story.snapshot()
			"wrong_order": bad.completed[0].chapter_id = "chapter_02"
			"duplicate": bad.completed.append(bad.completed[0].duplicate(true))
			"changed_fact": bad.story.flags.public_ledger = not bad.story.flags.public_ledger
			"missing_fact": bad.story.flags.erase("public_ledger")
		check(not campaign.restore(bad).ok and campaign.snapshot() == good, "invalid chapter history rejected atomically: " + change)
	var source: Dictionary = campaign.story.graph.duplicate(true)
	source.nodes.priority.options[0].set["relief"] = "ration"
	check(not Story.validate(source).is_empty(), "new choice cannot rewrite a prior chapter fact")
	source = campaign.story.graph.duplicate(true); source.nodes.dispatch_battle.win_set["public_ledger"] = true
	check(not Story.validate(source).is_empty(), "battle reward cannot rewrite a prior chapter fact")
	return true
func run() -> void:
	for method: String in ["test_paths", "test_transition_save", "test_invalid_history"]:
		check(call(method) == true, method + " completed")
	print("CAMPAIGN CHAPTER CHECKS: %d | FAILURES: %d | ROUTES: %d | TEXTS: %d | DISPLAY: %s" % [checks, failures, second_endings.size(), seen.size(), DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
