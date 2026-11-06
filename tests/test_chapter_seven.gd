extends SceneTree
## All five inherited display-condition combinations, reached by real choices.
## Prior battle wins are explicit fixtures, not a normal campaign playthrough.
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const PATH: String = "res://.tools/test_seventh_chapter.json"
var checks: int = 0
var failures: int = 0
var terminals: int = 0
var seen: Dictionary = {}
var incoming: Dictionary = {}
var camps: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
func reach_sixth_end(mask: int) -> RefCounted:
	var campaign: RefCounted = Campaign.new()
	check(campaign.start().ok, "start real history")
	var choices: Dictionary = {
		"chapter_03.letter": "return" if mask & 1 else "unscheduled",
		"chapter_04.shelter": "warehouse" if mask & 2 else "households",
		"chapter_04.terms": "sale" if mask & 4 else "lease",
		"chapter_05.mandate": "shared" if mask & 8 else "witness",
		"chapter_06.letter_choice": "alone" if mask & 16 else "companions"}
	for step: int in range(900):
		var runner: RefCounted = campaign.story
		var page: Dictionary = runner.current()
		match page.type:
			"dialogue": runner.advance(page.revision)
			"choice": runner.choose(choices.get(runner.graph.id + "." + page.node, page.options[0].id), page.revision)
			"battle": runner.resolve_battle(0, page.revision)
			"end":
				if runner.graph.id == "chapter_06": return campaign
				campaign.advance_chapter()
	check(false, "fixture reaches sixth ending within finite graph")
	return campaign
func walk_seven(campaign: RefCounted) -> void:
	var original: Dictionary = campaign.completed.back().story.flags
	var old_history: Array = campaign.completed.duplicate(true)
	for step: int in range(300):
		var runner: RefCounted = campaign.story
		var page: Dictionary = runner.current()
		match page.type:
			"dialogue":
				seen[page.line_id] = true
				if page.node in ["bridge", "clinic", "watch"] and not camps.has(page.node):
					runner.advance(page.revision)
					camps[page.node] = campaign.snapshot()
				else: runner.advance(page.revision)
			"choice":
				seen[runner.graph.nodes[page.node].prompt] = true
				check(page.node == "camp" and page.options.size() == 3 and runner.state.flags.camp_company == "none", "one three-way camp choice, still undecided")
				for option: Dictionary in page.options:
					for authored: Dictionary in runner.graph.nodes[page.node].options:
						if authored.id == option.id: seen[authored.text] = true
					var branch: RefCounted = Campaign.new()
					check(branch.restore(campaign.snapshot()).ok, "restore genuine seventh-chapter choice")
					check(branch.story.choose(option.id, page.revision).ok, "choose camp " + option.id)
					walk_seven(branch)
				return
			"end":
				seen[runner.graph.nodes[page.node].text] = true
				terminals += 1
				check(runner.state.decisions.size() == 1 and runner.state.attempts.is_empty(), "one camp decision and no fabricated seventh battle")
				check(runner.state.flags.camp_company in ["bridge", "clinic", "watch"], "chosen camp retained at end")
				for key: String in runner.graph.inherits: check(runner.state.flags[key] == original[key], "inherited fact preserved: " + key)
				check(campaign.completed == old_history, "earlier histories remain byte-equivalent objects")
				var copy: RefCounted = Campaign.new()
				check(copy.restore(JSON.parse_string(JSON.stringify(campaign.snapshot()))).ok and copy.snapshot() == campaign.snapshot(), "all decisions and read histories roundtrip")
				check(campaign.next_chapter().is_empty(), "unwritten eighth chapter is not offered")
				return
			_: check(false, "no encounter or unknown page in seventh chapter"); return
	check(false, "seventh route terminates")
func test_session() -> void:
	clean()
	var session: RefCounted = Session.new(PATH)
	check(session.campaign.restore(incoming).ok and session.save().ok, "save real old sixth ending")
	var history: Array = session.campaign.completed.duplicate(true)
	var stale: Dictionary = session.token()
	check(session.next_chapter(stale).ok and session.current().line_id == "c07.arrival.01", "old sixth ending advances to installed seventh")
	check(not session.next_chapter(stale).ok and not session.advance(stale).ok, "old chapter callbacks rejected")
	for index: int in range(history.size()): check(session.campaign.completed[index] == history[index], "previous history preserved")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.current().line_id == "c07.arrival.01" and fresh.campaign.completed.size() == 6, "new session resumes opening from disk")
	for camp: String in ["bridge", "clinic", "watch"]:
		clean(); session = Session.new(PATH)
		check(session.campaign.restore(camps[camp]).ok and session.save().ok, "save mid-camp " + camp)
		var saved: Dictionary = session.campaign.snapshot()
		fresh = Session.new(PATH)
		check(fresh.load_campaign().ok and fresh.campaign.snapshot() == saved and fresh.encounter == null, "disk restores exact line and full histories " + camp)
		check(fresh.campaign.story.state.flags.camp_company == camp and fresh.current().node == camp, "restored branch stays selected " + camp)
		var backlog: Array[Dictionary] = fresh.backlog()
		check(backlog.size() > 300 and backlog.back().text == fresh.campaign.story.graph.strings["c07." + camp + ".01"], "backlog keeps prior chapters and last read camp line")
		var before: Dictionary = fresh.campaign.snapshot()
		check(not fresh.begin_battle(fresh.token()).ok and fresh.encounter == null and fresh.campaign.snapshot() == before, "camp cannot create a fake battle")
		stale = fresh.token()
		check(fresh.advance(stale).ok and not fresh.advance(stale).ok, "resumed line advances once")
	clean()
func run() -> void:
	for mask: int in range(32):
		var campaign: RefCounted = reach_sixth_end(mask)
		if incoming.is_empty(): incoming = campaign.snapshot()
		var battles: int = campaign.story.state.attempts.size()
		for chapter: Dictionary in campaign.completed: battles += chapter.story.attempts.size()
		check(battles == 9, "history contains nine explicit battle-result fixtures")
		check(campaign.advance_chapter().ok and campaign.story.graph.id == "chapter_07", "start seventh with inherited history")
		walk_seven(campaign)
	check(terminals == 96, "32 actual incoming condition combinations times three camp choices")
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_07.json"))
	check(seen.size() == graph.strings.size(), "every seventh-chapter string reached")
	for id: String in graph.strings: check(seen.has(id), "reached authored string " + id)
	if camps.size() == 3 and not incoming.is_empty(): test_session()
	else: check(false, "all camp checkpoints collected")
	print("SEVENTH CHAPTER CHECKS: %d | FAILURES: %d | REPRESENTATIVE ROUTES: %d | TEXTS: %d" % [checks, failures, terminals, seen.size()])
	quit(0 if failures == 0 else 1)
