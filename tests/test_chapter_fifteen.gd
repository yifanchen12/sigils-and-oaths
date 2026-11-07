extends SceneTree
## Chapter fifteen must resume from earned channel wins and preserve older decisions.
const Session = preload("res://scripts/campaign_session.gd")
var checks: int = 0
var failures: int = 0
var seen: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func walk(source: String, dest: String, repair: String, earned: bool) -> void:
	if not check(DirAccess.copy_absolute(source, dest) == OK, "copy chapter-fourteen ending"): return
	var session: RefCounted = Session.new(dest)
	if not check(session.load_campaign().ok and session.current().type == "end" and session.campaign.story.graph.id == "chapter_14", "load completed channel battle"): return
	var before: Dictionary = session.campaign.story.state.flags.duplicate(true)
	if not check(session.next_chapter(session.token()).ok and session.campaign.story.graph.id == "chapter_15", "open fifteenth chapter from prior result"): return
	for step: int in range(160):
		var page: Dictionary = session.current()
		if page.type == "choice":
			if not check(page.node == "repair_choice", "repair choice follows tower failure"): return
			check(page.options.size() == 2, "both repair choices available")
			if not check(session.choose(repair, session.token()).ok, "apply repair choice"): return
			continue
		if page.type == "end":
			check(session.campaign.story.state.flags.repair_plan == repair and page.ending == ("valve_recast_ordered" if repair == "recast" else "valve_sleeve_ordered"), "distinct repair ending persists")
			seen[session.campaign.story.graph.nodes[page.node].text] = true
			for key: String in before: check(session.campaign.story.state.flags[key] == before[key], "old fact preserved: " + key)
			check(session.save().ok, "ending saves")
			var loaded: RefCounted = Session.new(dest)
			check(loaded.load_campaign().ok and loaded.current().type == "end" and loaded.campaign.story.state.flags.repair_plan == repair, "ending reloads")
			if earned: check(loaded.campaign.completed.size() == 14, "earned route retains fourteen prior endings")
			return
		if not check(page.type == "dialogue", "all other fifteenth pages are dialogue"): return
		seen[page.line_id] = true
		if not check(session.advance(session.token()).ok, "advance fifteenth page"): return
	check(false, "fifteenth chapter terminates")

func run() -> void:
	for plan: String in ["joint", "split", "hold"]:
		for order: String in ["seal", "metered"]:
			for repair: String in ["recast", "sleeve"]:
				var source: String = "res://.tools/v038-test14-%s-%s-%s.json" % [plan, "upstream" if order == "seal" else "tower", order]
				walk(source, "res://.tools/v039-test15-%s-%s-%s.json" % [plan, order, repair], repair, false)
	for watch: String in ["upstream", "tower"]:
		walk("res://.tools/v038-earned14-%s.json" % watch, "res://.tools/v039-earned15-%s.json" % watch, "recast" if watch == "upstream" else "sleeve", true)
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_15.json"))
	for id: String in graph.strings:
		if id.contains("repair_choice"): continue
		check(seen.has(id), "authored fifteenth body reachable: " + id)
	print("FIFTEENTH: %d CHECKS | FAILURES: %d | TEXTS: %d" % [checks, failures, seen.size()])
	quit(0 if failures == 0 else 1)
