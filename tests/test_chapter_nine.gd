extends SceneTree
## Chapter-nine narrative checks from real preceding choices with explicit
## victory fixtures for earlier battles. This is not a continuous playthrough.
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const PATH: String = "res://.tools/test_ninth_chapter.json"
var checks: int = 0
var failures: int = 0
var routes: int = 0
var seen: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)

func eighth_end(variant: int) -> RefCounted:
	var campaign: RefCounted = Campaign.new()
	check(campaign.start().ok, "start genuine campaign graph")
	var choices: Dictionary = {
		"chapter_01.route": "road", "chapter_02.priority": "relief",
		"chapter_03.route": "vent", "chapter_04.terms": "sale" if variant % 2 == 0 else "lease",
		"chapter_05.water": "nursery", "chapter_05.mandate": "shared" if variant % 4 < 2 else "witness",
		"chapter_06.disclosure": "open" if variant % 2 == 0 else "witnessed",
		"chapter_07.camp": ["bridge", "clinic", "watch"][variant % 3],
		"chapter_08.pressure": "isolate" if variant < 4 else "buffer"
	}
	for step: int in range(1600):
		var page: Dictionary = campaign.story.current()
		match page.type:
			"dialogue": campaign.story.advance(page.revision)
			"choice":
				var key: String = campaign.story.graph.id + "." + page.node
				campaign.story.choose(choices.get(key, page.options[0].id), page.revision)
			"battle": campaign.story.resolve_battle(0, page.revision) # Explicit fixture-only prior victory.
			"end":
				if campaign.story.graph.id == "chapter_08": return campaign
				check(campaign.advance_chapter().ok, "advance earned prior chapter")
	check(false, "fixture history reaches eighth ending")
	return campaign

func walk_nine(campaign: RefCounted, plan: String) -> void:
	var inherited: Dictionary = campaign.story.state.flags.duplicate(true)
	check(campaign.next_chapter().get("id") == "chapter_09", "eighth ending offers ninth chapter")
	check(campaign.advance_chapter().ok, "advance to ninth from earned eighth ending")
	check(campaign.story.graph.id == "chapter_09" and campaign.story.current().line_id == "c09.dawn.01", "ninth starts with visible local inspection")
	for key: String in inherited:
		check(campaign.story.state.flags[key] == inherited[key], "old fact carries into ninth: " + key)
	var choices: int = 0
	for step: int in range(260):
		var page: Dictionary = campaign.story.current()
		match page.type:
			"dialogue":
				seen[page.line_id] = true
				check(campaign.story.advance(page.revision).ok, "advance authored ninth dialogue")
			"choice":
				choices += 1
				check(page.node == "governance" and page.options.size() == 3, "three executable governance choices are visible")
				seen[campaign.story.graph.nodes[page.node].prompt] = true
				for option: Dictionary in campaign.story.graph.nodes[page.node].options: seen[option.text] = true
				check(campaign.story.choose(plan, page.revision).ok, "selected governance plan is legal")
				check(campaign.story.state.flags.governance_plan == plan, "chosen plan is saved as a durable fact")
			"battle":
				check(false, "ninth chapter does not invent a battle before the tower gate")
				return
			"end":
				seen[campaign.story.graph.nodes[page.node].text] = true
				routes += 1
				check(choices == 1 and campaign.story.state.decisions.size() == 1 and campaign.next_chapter().get("id") == "chapter_10", "one decision reaches ninth ending and offers installed tenth")
				for key: String in inherited:
					check(campaign.story.state.flags[key] == inherited[key], "ninth leaves earlier fact untouched: " + key)
				var portable: Variant = JSON.parse_string(JSON.stringify(campaign.snapshot()))
				var copy: RefCounted = Campaign.new()
				check(copy.restore(portable).ok and copy.snapshot() == campaign.snapshot(), "nine-chapter history restores exactly")
				return
	check(false, "ninth chapter terminates without a graph loop")

func disk_resume(progress: Dictionary) -> void:
	clean()
	var session: RefCounted = Session.new(PATH)
	check(session.campaign.restore(progress).ok and session.save().ok, "save genuine eighth ending")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.current().type == "end" and fresh.campaign.story.graph.id == "chapter_08", "new session reads old ending")
	var token: Dictionary = fresh.token()
	check(fresh.next_chapter(token).ok and fresh.current().line_id == "c09.dawn.01", "new session enters ninth without fabricated battle")
	check(not fresh.next_chapter(token).ok, "stale cross-chapter callback is rejected")
	check(fresh.save().ok, "ninth opening is saved")
	var reopened: RefCounted = Session.new(PATH)
	check(reopened.load_campaign().ok and reopened.current().line_id == "c09.dawn.01" and reopened.campaign.completed.size() == 8, "ninth opening roundtrips on disk")
	clean()

func run() -> void:
	var opening: Dictionary = {}
	for variant: int in range(8):
		var prior: RefCounted = eighth_end(variant)
		if opening.is_empty(): opening = prior.snapshot()
		for plan: String in ["joint", "split", "hold"]:
			var campaign: RefCounted = Campaign.new()
			check(campaign.restore(prior.snapshot()).ok, "clone genuine eighth ending")
			walk_nine(campaign, plan)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_09.json"))
	check(routes == 24, "eight representative histories times three governance plans")
	for id: String in source.strings: check(seen.has(id), "every ninth-chapter string is reached: " + id)
	if not opening.is_empty(): disk_resume(opening)
	print("NINTH CHAPTER CHECKS: %d | FAILURES: %d | REPRESENTATIVE ROUTES: %d | TEXTS: %d" % [checks, failures, routes, seen.size()])
	quit(0 if failures == 0 else 1)
