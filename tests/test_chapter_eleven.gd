extends "res://tests/test_chapter_ten.gd"
## Eleventh-chapter text/flag coverage. Prior victories in these walks are
## explicit fixtures; the separate continuous benchmark tests native wins.
const ELEVEN_PATH: String = "res://.tools/test_eleventh_chapter.json"
const Art = preload("res://scripts/art_library.gd")
var eleventh_seen: Dictionary = {}
var eleventh_routes: int = 0

func _clean_eleven() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(ELEVEN_PATH + suffix): DirAccess.remove_absolute(ELEVEN_PATH + suffix)

func _disk_roundtrip(campaign: RefCounted, label: String) -> void:
	_clean_eleven()
	var session: RefCounted = Session.new(ELEVEN_PATH)
	check(session.campaign.restore(campaign.snapshot()).ok and session.save().ok, "chapter eleven saves at " + label)
	var fresh: RefCounted = Session.new(ELEVEN_PATH)
	check(fresh.load_campaign().ok and fresh.campaign.snapshot() == campaign.snapshot(), "chapter eleven restores exact history at " + label)
	_clean_eleven()

func walk_eleven(campaign: RefCounted, plan: String, disk: bool) -> void:
	var inherited: Dictionary = campaign.story.state.flags.duplicate(true)
	check(campaign.next_chapter().get("id") == "chapter_11" and campaign.advance_chapter().ok, "earned tenth ending enters eleventh: " + plan)
	check(campaign.story.current().line_id == "c11.letter.01" and campaign.story.state.flags.governance_plan == plan, "chapter eleven begins with carried governance: " + plan)
	for key: String in inherited: check(campaign.story.state.flags[key] == inherited[key], "eleventh inherits prior fact: " + key)
	if disk: _disk_roundtrip(campaign, plan + " opening")
	var pages: int = 0
	for step: int in range(180):
		var page: Dictionary = campaign.story.current()
		match page.type:
			"dialogue":
				eleventh_seen[page.line_id] = true
				pages += 1
				check(campaign.story.advance(page.revision).ok, "advance eleventh page: " + page.line_id)
			"choice", "battle":
				check(false, "witness chapter has no invented choice or instant battle")
				return
			"end":
				eleventh_seen[campaign.story.graph.nodes[page.node].text] = true
				eleventh_routes += 1
				check(pages >= 105 and campaign.next_chapter().get("id") == "chapter_12", "eleventh witness route reaches authored end and opens twelfth: " + plan)
				for key: String in inherited: check(campaign.story.state.flags[key] == inherited[key], "eleventh preserves inherited fact: " + key)
				if disk: _disk_roundtrip(campaign, plan + " ending")
				return
	check(false, "eleventh chapter reaches end within bounded pages")

func run() -> void:
	check(Art.get_texture("scene_redroof") != null and Art.get_texture("scene_northbank_memorial") != null, "both new narrative backgrounds import as native textures")
	for variant: int in range(8):
		var prior: RefCounted = eighth_end(variant)
		for plan: String in ["joint", "split", "hold"]:
			var campaign: RefCounted = Campaign.new()
			check(campaign.restore(prior.snapshot()).ok, "clone valid eighth ending")
			walk_nine(campaign, plan)
			walk_ten(campaign, plan, false)
			walk_eleven(campaign, plan, variant == 0)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_11.json"))
	check(eleventh_routes == 24, "eight prior histories and three governance plans reach eleventh")
	for id: String in source.strings: check(eleventh_seen.has(id), "every eleventh source string is reached: " + id)
	print("ELEVENTH CHAPTER CHECKS: %d | FAILURES: %d | ROUTES: %d | TEXTS: %d" % [checks, failures, eleventh_routes, eleventh_seen.size()])
	quit(0 if failures == 0 else 1)
