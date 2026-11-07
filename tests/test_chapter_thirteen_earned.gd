extends SceneTree
## Chapter twelve finishes in native, legally won depot saves. No battle fixture is used here.
const Session = preload("res://scripts/campaign_session.gd")
const Art = preload("res://scripts/art_library.gd")
var checks: int = 0
var failures: int = 0
var seen: Dictionary = {}
var routes: int = 0

func _initialize() -> void:
	print("EARNED THIRTEENTH START")
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func _reopen(session: RefCounted, label: String) -> RefCounted:
	var expected: Dictionary = session.campaign.snapshot()
	var fresh: RefCounted = Session.new(session.store.path)
	check(fresh.load_campaign().ok and fresh.campaign.snapshot() == expected, "thirteenth saved history reloads at " + label)
	return fresh

func walk(plan: String, watch: String) -> void:
	print("EARNED THIRTEENTH ROUTE: " + plan + "/" + watch)
	var source: String = "res://.tools/v036-earned-chapter12-%s.json" % plan
	var path: String = "res://.tools/v037-test13-%s-%s.json" % [plan, watch]
	if not check(DirAccess.copy_absolute(source, path) == OK, "copy earned depot result: " + plan): return
	var session: RefCounted = Session.new(path)
	if not check(session.load_campaign().ok and session.current().type == "end" and session.campaign.story.graph.id == "chapter_12", "load actual chapter twelve victory: " + plan): return
	var prior: Dictionary = session.campaign.story.state.flags.duplicate(true)
	if not check(session.next_chapter(session.token()).ok and session.campaign.story.graph.id == "chapter_13", "earned depot result opens thirteenth: " + plan): return
	check(session.current().line_id == "c13.mill_dawn.01" and session.campaign.story.state.flags.shaft_custody == ("northbank" if plan == "hold" else "loaned"), "custody enters visible mill consequence: " + plan)
	for key: String in prior: check(session.campaign.story.state.flags[key] == prior[key], "thirteenth preserves earlier decision: " + key)
	session = _reopen(session, "mill opening")
	var choices: int = 0
	for step: int in range(160):
		var page: Dictionary = session.current()
		match page.type:
			"dialogue":
				seen[page.line_id] = true
				if not check(session.advance(session.token()).ok, "read authentic thirteenth page: " + page.line_id): return
			"choice":
				choices += 1
				check(page.node == "night_watch" and session.campaign.story.state.flags.night_watch == "none", "night watch is chosen after low-pressure trial")
				seen[session.campaign.story.graph.nodes[page.node].prompt] = true
				for option: Dictionary in session.campaign.story.graph.nodes[page.node].options: seen[option.text] = true
				if not check(session.choose(watch, session.token()).ok, "choose displayed night watch: " + watch): return
				session = _reopen(session, "night watch choice")
			"end":
				seen[session.campaign.story.graph.nodes[page.node].text] = true
				routes += 1
				check(choices == 1 and session.campaign.story.state.flags.night_watch == watch and session.campaign.next_chapter().is_empty(), "distinct watch outcome reaches authored end: " + plan + "/" + watch)
				for key: String in prior: check(session.campaign.story.state.flags[key] == prior[key], "thirteenth ending preserves earlier fact: " + key)
				_reopen(session, "chapter end")
				return
			_: check(false, "unexpected thirteenth page: " + str(page.type)); return
	check(false, "thirteenth route ends within bounded pages")

func run() -> void:
	check(Art.get_texture("scene_northbank_mill") != null, "original mill painting imports as native texture")
	for plan: String in ["joint", "split", "hold"]:
		for watch: String in ["upstream", "tower"]: walk(plan, watch)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_13.json"))
	check(routes == 6, "three actual depot victories each support both night watches")
	for id: String in source.strings: check(seen.has(id), "all thirteenth text is reachable from earned history: " + id)
	print("EARNED THIRTEENTH: %d CHECKS | FAILURES: %d | ROUTES: %d | TEXTS: %d" % [checks, failures, routes, seen.size()])
	quit(0 if failures == 0 else 1)
