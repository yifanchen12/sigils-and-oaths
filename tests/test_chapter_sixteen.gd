extends SceneTree
## Earned chapter-fifteen endings enter a real East Bridge encounter.
const Session = preload("res://scripts/campaign_session.gd")
const Model = preload("res://scripts/battle.gd")
const Painted = preload("res://scripts/map_artwork.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
var checks := 0
var failures := 0
var seen: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func route(watch: String, choice: String) -> void:
	var source := "res://.tools/v039-earned15-%s.json" % watch
	var save := "res://.tools/v040-test16-%s-%s.json" % [watch, choice]
	if not check(DirAccess.copy_absolute(source, save) == OK, "copy earned chapter-fifteen end"): return
	var session: RefCounted = Session.new(save)
	if not check(session.load_campaign().ok and session.current().type == "end", "earned end loads"): return
	var before: Dictionary = session.campaign.story.state.flags.duplicate(true)
	if not check(session.next_chapter(session.token()).ok and session.campaign.story.graph.id == "chapter_16", "fifteenth end opens sixteenth"): return
	for step: int in range(80):
		var page: Dictionary = session.current()
		if page.type == "battle": break
		if not check(page.type == "dialogue", "prebattle page is dialogue"): return
		seen[page.line_id] = true
		if not check(session.advance(session.token()).ok, "read bridge setup"): return
	if not check(session.current().type == "battle" and session.campaign.scenario().map == "eastbridge", "authored bridge battle reached"): return
	if not check(session.begin_battle(session.token()).ok, "begin actual battle model"): return
	var battle: Battle = session.encounter
	check(battle.width == 16 and battle.height == 12 and battle.map_definition.id == "eastbridge", "sixteen by twelve new board")
	var snapshot: Dictionary = Snapshot.capture(battle)
	check(session.save().ok, "battle save writes")
	var resumed: RefCounted = Session.new(save)
	if not check(resumed.load_campaign().ok and Snapshot.capture(resumed.encounter) == snapshot, "battle reload preserves state"): return
	# Narrative reachability only; a legal-action win is a separate benchmark.
	resumed.encounter.winner = 0
	if not check(resumed.finish_battle(resumed.encounter).ok and resumed.campaign.story.state.flags.bridge_open, "win opens bridge in story"): return
	for step: int in range(80):
		var page: Dictionary = resumed.current()
		if page.type == "choice": break
		if not check(page.type == "dialogue", "postbattle page is dialogue"): return
		seen[page.line_id] = true
		if not check(resumed.advance(resumed.token()).ok, "read aftermath"): return
	if not check(resumed.current().type == "choice" and resumed.current().options.size() == 2, "two distinct escort choices"): return
	if not check(resumed.choose(choice, resumed.token()).ok, "choose escort handling"): return
	while resumed.current().type == "dialogue":
		seen[resumed.current().line_id] = true
		if not check(resumed.advance(resumed.token()).ok, "read selected ending"): return
	check(resumed.current().type == "end" and resumed.campaign.story.state.flags.escort_terms == choice, "selected ending persists")
	for key: String in before: check(resumed.campaign.story.state.flags[key] == before[key], "earlier fact preserved: " + key)
	check(resumed.save().ok, "ending saves")
	var last: RefCounted = Session.new(save)
	check(last.load_campaign().ok and last.current().type == "end" and last.campaign.story.state.flags.escort_terms == choice, "ending reloads")

func run() -> void:
	var board: Battle = Model.new(16031, "eastbridge")
	check(Painted.texture(board) != null, "new native painting imported")
	for row: String in board.map_definition.rows: check(row.length() == 16, "map row matches sixteen columns")
	for y: int in [4, 5]:
		for x: int in range(16): check((board.ground(Vector2i(x, y)) == "bridge") == (x in [3, 4, 10, 11]), "only two authored crossings")
	for watch: String in ["upstream", "tower"]:
		for choice: String in ["hearing", "service"]: route(watch, choice)
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_16.json"))
	for id: String in graph.strings:
		if id.contains("escort_choice"): continue
		if id in ["c16.hearing_end", "c16.service_end"]: continue
		# The two earned prior saves share a foundry contract; the narrative
		# graph audit checks the other lawful contract state separately.
		if id in ["c16.claim.05", "c16.after.05"]: continue
		check(seen.has(id), "authored body reached: " + id)
	print("SIXTEENTH: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
