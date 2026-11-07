extends "res://tests/test_chapter_eleven.gd"
## Branch walks use explicit victory fixtures. Separate tactical tests play real turns.
const TWELVE_PATH: String = "res://.tools/test_twelfth_chapter.json"
const Model = preload("res://scripts/battle.gd")
var twelfth_seen: Dictionary = {}
var twelfth_routes: int = 0

func _clean_twelve() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TWELVE_PATH + suffix): DirAccess.remove_absolute(TWELVE_PATH + suffix)

func _roundtrip_twelve(campaign: RefCounted, label: String) -> void:
	_clean_twelve()
	var session: RefCounted = Session.new(TWELVE_PATH)
	check(session.campaign.restore(campaign.snapshot()).ok and session.save().ok, "twelfth campaign saves: " + label)
	var fresh: RefCounted = Session.new(TWELVE_PATH)
	check(fresh.load_campaign().ok and fresh.campaign.snapshot() == campaign.snapshot(), "twelfth campaign reloads: " + label)
	_clean_twelve()

func walk_twelve(campaign: RefCounted, plan: String, custody: String, disk: bool) -> void:
	var inherited: Dictionary = campaign.story.state.flags.duplicate(true)
	check(campaign.next_chapter().get("id") == "chapter_12" and campaign.advance_chapter().ok, "earned eleventh ending enters twelfth")
	check(campaign.story.current().line_id == "c12.arrival.01" and campaign.story.state.flags.governance_plan == plan, "twelfth opens at actual depot with governance inherited")
	if disk: _roundtrip_twelve(campaign, plan + " opening")
	var battles: int = 0
	var decisions: int = 0
	for step: int in range(180):
		var page: Dictionary = campaign.story.current()
		match page.type:
			"dialogue":
				twelfth_seen[page.line_id] = true
				check(campaign.story.advance(page.revision).ok, "advance twelfth page: " + page.line_id)
			"battle":
				battles += 1
				var setup: Dictionary = campaign.scenario()
				check(page.scenario == "c12_depot" and setup.map == "northbank" and setup.hero == {"joint": "warden", "split": "pyromancer", "hold": "grove"}[plan], "twelfth scenario resolves to plan-specific northbank encounter")
				check(setup.enemy_deck == "ambush" and int(setup.control.cells[0][0]) == 5 and int(setup.control.cells[0][1]) == 3 and int(setup.control.cells[1][0]) == 10 and int(setup.control.cells[1][1]) == 3, "depot uses two worksites and hand-played traps")
				var live: Battle = Model.new(int(setup.seed), setup.map, setup.hero, setup.enemy_class, setup.deck, setup.enemy_deck)
				check(live.configure_objective(setup.control).ok and live.objective.round_limit == {"joint": 20, "split": 18, "hold": 22}[plan], "real battle config has plan-specific deadline")
				if disk: _roundtrip_twelve(campaign, plan + " before battle")
				check(campaign.story.resolve_battle(1, page.revision).ok and not campaign.story.state.flags.northbank_access, "loss does not award depot access")
				check(campaign.story.current().type == "battle" and campaign.story.current().last_outcome == "defeat", "loss remains retryable at depot")
				check(campaign.story.resolve_battle(0, campaign.story.current().revision).ok and campaign.story.state.flags.northbank_access, "fixture-only win opens measured aftermath")
			"choice":
				decisions += 1
				check(campaign.story.state.flags.northbank_access and campaign.story.state.flags.shaft_custody == "none", "custody is unset until the postbattle choice")
				twelfth_seen[campaign.story.graph.nodes[page.node].prompt] = true
				for option: Dictionary in campaign.story.graph.nodes[page.node].options: twelfth_seen[option.text] = true
				check(campaign.story.choose(custody, page.revision).ok and campaign.story.state.flags.shaft_custody == custody, "choice records chosen custody")
				if disk: _roundtrip_twelve(campaign, plan + " custody")
			"end":
				twelfth_seen[campaign.story.graph.nodes[page.node].text] = true
				twelfth_routes += 1
				check(battles == 1 and decisions == 1 and campaign.next_chapter().is_empty(), "twelfth route ends after one battle and one custody decision")
				for key: String in inherited: check(campaign.story.state.flags[key] == inherited[key], "prior fact preserved: " + key)
				var copy: RefCounted = Campaign.new()
				check(copy.restore(JSON.parse_string(JSON.stringify(campaign.snapshot()))).ok and copy.snapshot() == campaign.snapshot(), "full twelve-chapter history roundtrips")
				return
	check(false, "twelfth route ends in bounded pages")

func run() -> void:
	check(Art.get_texture("battlefield_northbank") != null, "northbank painting imports as native texture")
	for variant: int in range(8):
		var prior: RefCounted = eighth_end(variant)
		for plan: String in ["joint", "split", "hold"]:
			for custody: String in ["loaned", "northbank"]:
				var campaign: RefCounted = Campaign.new()
				check(campaign.restore(prior.snapshot()).ok, "clone valid eighth ending")
				walk_nine(campaign, plan)
				walk_ten(campaign, plan, false)
				walk_eleven(campaign, plan, false)
				walk_twelve(campaign, plan, custody, variant == 0)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_12.json"))
	check(twelfth_routes == 48, "eight prior histories, three governance plans and two custody choices reach twelfth")
	for id: String in source.strings: check(twelfth_seen.has(id), "every twelfth source text is reachable: " + id)
	print("TWELFTH CHAPTER CHECKS: %d | FAILURES: %d | ROUTES: %d | TEXTS: %d" % [checks, failures, twelfth_routes, twelfth_seen.size()])
	quit(0 if failures == 0 else 1)
