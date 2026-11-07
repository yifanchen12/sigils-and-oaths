extends "res://tests/test_chapter_nine.gd"
## All tenth-chapter facts and plan-specific battle setups. Prior battle wins
## in these narrative walks are explicit fixtures, not live playthroughs.
const TEN_PATH: String = "res://.tools/test_tenth_chapter.json"
var tenth_seen: Dictionary = {}
var tenth_routes: int = 0

func clean_ten() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEN_PATH + suffix): DirAccess.remove_absolute(TEN_PATH + suffix)

func disk_battle(campaign: RefCounted, plan: String) -> void:
	clean_ten()
	var session: RefCounted = Session.new(TEN_PATH)
	check(session.campaign.restore(campaign.snapshot()).ok and session.save().ok, "save tenth battle briefing before deployment")
	var started: Dictionary = session.begin_battle(session.token())
	check(started.ok and started.battle.map_definition.id == "towergate", "begin real plan-specific gate battle: " + plan)
	check(started.battle.players[0].hero_id == {"joint": "warden", "split": "pyromancer", "hold": "grove"}[plan], "governance changes actual commander: " + plan)
	check(started.battle.objective.round_limit == {"joint": 18, "split": 16, "hold": 20}[plan], "governance changes actual deadline: " + plan)
	var fresh: RefCounted = Session.new(TEN_PATH)
	check(fresh.load_campaign().ok and fresh.encounter != null and fresh.current().scenario == "c10_gate", "independent session restores variant battle with stable story alias: " + plan)
	check(fresh.campaign.scenario().hero == started.scenario.hero and fresh.encounter.map_definition.id == "towergate", "variant setup survives disk and save validation: " + plan)
	var forged: Dictionary = campaign.snapshot().duplicate(true)
	forged.story.flags.governance_plan = "split" if plan != "split" else "hold"
	var rejected: RefCounted = Campaign.new()
	check(not rejected.restore(forged).ok, "chapter-ten plan cannot be changed independently of the earned ninth ending: " + plan)
	clean_ten()

func walk_ten(campaign: RefCounted, plan: String, disk: bool) -> void:
	var inherited: Dictionary = campaign.story.state.flags.duplicate(true)
	check(campaign.next_chapter().get("id") == "chapter_10" and campaign.advance_chapter().ok, "ninth ending enters installed tenth")
	check(campaign.story.current().line_id == "c10.before.01" and campaign.story.state.flags.governance_plan == plan, "tenth begins after the chosen governance plan")
	for key: String in inherited: check(campaign.story.state.flags[key] == inherited[key], "prior fact remains intact in tenth: " + key)
	var battles: int = 0
	for step: int in range(250):
		var page: Dictionary = campaign.story.current()
		match page.type:
			"dialogue":
				tenth_seen[page.line_id] = true
				check(campaign.story.advance(page.revision).ok, "advance authored tenth page")
			"choice":
				check(false, "ninth governance is carried automatically without an unadvertised new choice")
				return
			"battle":
				battles += 1
				var setup: Dictionary = campaign.scenario()
				check(page.scenario == "c10_gate" and setup.map == "towergate" and setup.hero == {"joint": "warden", "split": "pyromancer", "hold": "grove"}[plan], "battle setup resolves inherited governance: " + plan)
				check(setup.deck == ("balanced" if plan == "hold" else "assault") and int(setup.control.cells[0][0]) == 3 and int(setup.control.cells[1][0]) == 10, "deck and dual bridgeheads agree with governance: " + plan)
				if disk: disk_battle(campaign, plan)
				check(campaign.story.resolve_battle(1, page.revision).ok and not campaign.story.state.flags.tower_gate_secured, "defeat stays at gate without awarding victory")
				check(campaign.story.current().type == "battle" and campaign.story.current().last_outcome == "defeat", "gate can be retried after loss")
				check(campaign.story.resolve_battle(0, campaign.story.current().revision).ok and campaign.story.state.flags.tower_gate_secured, "fixture-only win reaches aftermath and records secured gate")
			"end":
				tenth_seen[campaign.story.graph.nodes[page.node].text] = true
				tenth_routes += 1
				check(battles == 1 and campaign.next_chapter().get("id") == "chapter_11", "one gate battle reaches tenth ending and unlocks eleventh")
				for key: String in inherited: check(campaign.story.state.flags[key] == inherited[key], "tenth does not erase earlier fact: " + key)
				var portable: Variant = JSON.parse_string(JSON.stringify(campaign.snapshot()))
				var copy: RefCounted = Campaign.new()
				check(copy.restore(portable).ok and copy.snapshot() == campaign.snapshot(), "ten-chapter history restores exactly")
				return
	check(false, "tenth chapter terminates before bounded page limit")

func run() -> void:
	for variant: int in range(8):
		var prior: RefCounted = eighth_end(variant)
		for plan: String in ["joint", "split", "hold"]:
			var campaign: RefCounted = Campaign.new()
			check(campaign.restore(prior.snapshot()).ok, "clone valid eighth ending")
			walk_nine(campaign, plan)
			walk_ten(campaign, plan, variant == 0)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_10.json"))
	check(tenth_routes == 24, "eight prior histories times three governance plans reach tenth")
	for id: String in source.strings: check(tenth_seen.has(id), "every tenth source string is reached: " + id)
	print("TENTH CHAPTER CHECKS: %d | FAILURES: %d | ROUTES: %d | TEXTS: %d" % [checks, failures, tenth_routes, tenth_seen.size()])
	quit(0 if failures == 0 else 1)
