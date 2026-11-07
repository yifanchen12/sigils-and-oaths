extends SceneTree
## Real earlier choices and explicit victory fixtures. Not a normal playthrough.
const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const PATH: String = "res://.tools/test_eighth_chapter.json"
var checks: int = 0
var failures: int = 0
var terminals: int = 0
var seen: Dictionary = {}
var checkpoints: Dictionary = {}
var incoming: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func clean() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)
func previous(camp: String, sale: bool, shared: bool) -> RefCounted:
	var campaign: RefCounted = Campaign.new(); check(campaign.start().ok, "start real history")
	var choices: Dictionary = {"chapter_04.terms": "sale" if sale else "lease", "chapter_05.mandate": "shared" if shared else "witness", "chapter_07.camp": camp}
	for step: int in range(1000):
		var r: RefCounted = campaign.story; var p: Dictionary = r.current()
		match p.type:
			"dialogue": r.advance(p.revision)
			"choice": r.choose(choices.get(r.graph.id + "." + p.node, p.options[0].id), p.revision)
			"battle": r.resolve_battle(0, p.revision)
			"end":
				if r.graph.id == "chapter_07": return campaign
				campaign.advance_chapter()
	check(false, "reach real seventh ending"); return campaign
func walk(campaign: RefCounted) -> void:
	for step: int in range(250):
		var r: RefCounted = campaign.story; var p: Dictionary = r.current()
		match p.type:
			"dialogue": seen[p.line_id] = true; r.advance(p.revision)
			"choice":
				seen[r.graph.nodes[p.node].prompt] = true
				check(p.options.size() == 2 and r.state.flags.pressure_plan == "none" and not r.state.flags.sunspire_stable, "pressure choice precedes battle consequences")
				for option: Dictionary in p.options:
					for source: Dictionary in r.graph.nodes[p.node].options:
						if source.id == option.id: seen[source.text] = true
					var branch: RefCounted = Campaign.new(); check(branch.restore(campaign.snapshot()).ok, "branch restores genuine history")
					check(branch.story.choose(option.id, p.revision).ok, "choose plan"); walk(branch)
				return
			"battle":
				var plan: String = r.state.flags.pressure_plan
				check(Campaign.validate_scenario(campaign.scenario()).is_empty() and p.scenario == "c08_" + plan, "selected plan starts its authored encounter")
				if not checkpoints.has(plan): checkpoints[plan] = campaign.snapshot()
				var before: Dictionary = r.state.flags.duplicate(true)
				for outcome: int in [1, 2]:
					check(r.resolve_battle(outcome, r.current().revision).ok and r.current().type == "battle" and r.state.flags == before, "loss/draw cannot stabilize water or change choice")
				check(r.resolve_battle(0, r.current().revision).ok and r.state.flags.sunspire_stable, "victory unlocks authored repair aftermath")
			"end":
				seen[r.graph.nodes[p.node].text] = true; terminals += 1
				check(r.state.decisions.size() == 1 and r.state.attempts.size() == 1 and r.state.attempts.get(r.state.flags.pressure_plan + "_battle") == 3 and r.state.flags.sunspire_stable, "one decision and explicit loss/draw/win attempt history")
				for key: String in r.graph.inherits: check(r.state.flags[key] == campaign.completed.back().story.flags[key], "old fact retained " + key)
				var copy: RefCounted = Campaign.new()
				check(copy.restore(JSON.parse_string(JSON.stringify(campaign.snapshot()))).ok and copy.snapshot() == campaign.snapshot(), "all eight histories roundtrip")
				check(campaign.next_chapter().get("id") == "chapter_09", "completed eighth chapter offers installed ninth")
				return
	check(false, "chapter eight terminates")
func sessions() -> void:
	clean(); var s: RefCounted = Session.new(PATH)
	check(s.campaign.restore(incoming).ok and s.save().ok, "save actual old seventh ending")
	var stale: Dictionary = s.token()
	check(s.next_chapter(stale).ok and s.current().line_id == "c08.rope.01", "old ending enters eighth")
	check(not s.advance(stale).ok and not s.next_chapter(stale).ok, "old callbacks rejected")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.current().line_id == "c08.rope.01" and fresh.campaign.completed.size() == 7, "fresh disk session reads eighth opening")
	for plan: String in ["isolate", "buffer"]:
		clean(); s = Session.new(PATH)
		check(s.campaign.restore(checkpoints[plan]).ok, "restore each real briefing")
		var result: Dictionary = s.begin_battle(s.token()); check(result.ok, "begin " + plan)
		if not result.ok: continue
		var b: Battle = result.battle
		check(b.map_definition.id == "sunspire" and b.players[0].hero_id == "pyromancer" and b.units.size() == 2 and b.turn_time_limit == 90, "normal Sunspire initial resources and timer")
		check((b.objective.get("cells") == [[4, 4], [7, 5]] and b.objective.required == 2 and b.objective.round_limit == 12) if plan == "isolate" else b.objective.is_empty(), "precise route objective")
		b.advance_clock(11.25); check(s.save().ok, "save live encounter")
		fresh = Session.new(PATH)
		check(fresh.load_campaign().ok and fresh.encounter != null and fresh.encounter.time_remaining == 78.75 and fresh.campaign.story.state.flags.pressure_plan == plan and not fresh.campaign.story.state.flags.sunspire_stable, "fresh battle restore preserves remaining clock and unawarded facts")
		if fresh.encounter == null: continue
		if plan == "isolate":
			Fixture.troop(fresh.encounter, "spear", Vector2i(4, 4)); Fixture.troop(fresh.encounter, "sword", Vector2i(7, 5))
			fresh.encounter.end_turn(); fresh.encounter.end_turn()
			check(fresh.encounter.objective.streak == 1 and fresh.encounter.winner == -1 and fresh.save().ok, "first control checkpoint alone does not win")
			var resumed: RefCounted = Session.new(PATH)
			check(resumed.load_campaign().ok and resumed.encounter.objective.streak == 1, "control progress persists across disk")
			fresh = resumed; fresh.encounter.end_turn(); fresh.encounter.end_turn()
		else:
			fresh.encounter.commander(1).hp = 0; fresh.encounter._cleanup(); fresh.encounter._check_winner()
		var ended: Battle = fresh.encounter
		check(ended.winner == 0 and fresh.finish_battle(ended).ok and fresh.current().line_id == "c08.after.01", "canonical objective victory hands off once")
		check(not fresh.finish_battle(ended).ok, "consumed battle rejected")
		var next: RefCounted = Session.new(PATH)
		check(next.load_campaign().ok and next.encounter == null and next.current().line_id == "c08.after.01" and next.campaign.story.state.flags.sunspire_stable, "disk resumes actual aftermath")
	clean()
func run() -> void:
	for camp: String in ["bridge", "clinic", "watch"]:
		for sale: bool in [false, true]:
			for shared: bool in [false, true]:
				var c: RefCounted = previous(camp, sale, shared)
				if incoming.is_empty(): incoming = c.snapshot()
				check(c.advance_chapter().ok, "inherit actual seventh route"); walk(c)
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_08.json"))
	check(terminals == 24, "12 inherited condition combinations times two pressure plans")
	for id: String in g.strings: check(seen.has(id), "reachable string " + id)
	if checkpoints.size() == 2: sessions()
	else: check(false, "both briefings reached")
	print("EIGHTH CHAPTER CHECKS: %d | FAILURES: %d | REPRESENTATIVE ROUTES: %d | TEXTS: %d" % [checks, failures, terminals, seen.size()])
	quit(0 if failures == 0 else 1)
