extends SceneTree
## Saved thirteenth outcomes must enter a distinct, playable channel setup.
const Session = preload("res://scripts/campaign_session.gd")
const Model = preload("res://scripts/battle.gd")
const Painted = preload("res://scripts/map_artwork.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
var checks: int = 0
var failures: int = 0
var seen: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok

func walk(plan: String, watch: String, order: String) -> void:
	var source: String = "res://.tools/v037-test13-%s-%s.json" % [plan, watch]
	var save: String = "res://.tools/v038-test14-%s-%s-%s.json" % [plan, watch, order]
	if not check(DirAccess.copy_absolute(source, save) == OK, "copy earned chapter-thirteen result"): return
	var session: RefCounted = Session.new(save)
	if not check(session.load_campaign().ok and session.current().type == "end" and session.campaign.story.graph.id == "chapter_13", "load earned chapter-thirteen ending"): return
	var before: Dictionary = session.campaign.story.state.flags.duplicate(true)
	if not check(session.next_chapter(session.token()).ok and session.campaign.story.graph.id == "chapter_14", "earned ending opens fourteenth chapter"): return
	for step: int in range(100):
		var page: Dictionary = session.current()
		if page.type == "battle": break
		if not check(page.type == "dialogue", "fourteenth prebattle page is dialogue"): return
		seen[page.line_id] = true
		if not check(session.advance(session.token()).ok, "advance channel briefing"): return
	if not check(session.current().type == "battle", "battle follows authored investigation"): return
	var setup: Dictionary = session.campaign.scenario()
	check(setup.map == "spillway" and setup.deck == "channel" and setup.bonus_card == ("span_kit" if watch == "upstream" else "countercurrent_ward"), "night watch changes a real battle card")
	if not check(session.begin_battle(session.token()).ok, "start authentic channel battle"): return
	var battle: Battle = session.encounter
	check(battle.map_definition.id == "spillway" and battle.width == 16 and battle.height == 12, "channel battlefield has expanded grid")
	check(battle.players[0].hand.any(func(card: Dictionary) -> bool: return card.card_id == setup.bonus_card), "earned clue appears in opening hand")
	check(battle.players[0].card_total == 31 and battle.objective.cells == [[5, 6], [10, 3]], "bonus card and two work positions survive setup")
	var snapshot: Dictionary = Snapshot.capture(battle)
	check(session.save().ok, "new battle saves")
	var reopened: RefCounted = Session.new(save)
	check(reopened.load_campaign().ok and Snapshot.capture(reopened.encounter) == snapshot, "new battle reopens without losing watch bonus")
	# Story-only gate check. Legal-action victory is covered by the earned match pilot.
	reopened.encounter.winner = 0
	if not check(reopened.finish_battle(reopened.encounter).ok and reopened.campaign.story.state.flags.channel_secured, "victory advances story and records secured channel"): return
	for step: int in range(100):
		var page: Dictionary = reopened.current()
		if page.type == "choice": break
		if not check(page.type == "dialogue", "postbattle page is dialogue"): return
		seen[page.line_id] = true
		if not check(reopened.advance(reopened.token()).ok, "read postbattle passage"): return
	if not check(reopened.current().type == "choice" and reopened.current().node == "water_order", "water order is chosen after combat"): return
	for option: Dictionary in reopened.campaign.story.graph.nodes.water_order.options: seen[option.text] = true
	seen[reopened.campaign.story.graph.nodes.water_order.prompt] = true
	if not check(reopened.choose(order, reopened.token()).ok, "choose measured water order"): return
	while reopened.current().type == "dialogue":
		seen[reopened.current().line_id] = true
		if not check(reopened.advance(reopened.token()).ok, "read selected water consequence"): return
	var ending: Dictionary = reopened.current()
	check(ending.type == "end" and reopened.campaign.story.state.flags.channel_order == order and ending.ending == ("channel_sealed" if order == "seal" else "channel_metered"), "water order has distinct saved ending")
	seen[reopened.campaign.story.graph.nodes[ending.node].text] = true
	for key: String in before: check(reopened.campaign.story.state.flags[key] == before[key], "older campaign fact remains intact: " + key)

func run() -> void:
	var map: Battle = Model.new(14031, "spillway")
	var art: Texture2D = Painted.texture(map)
	check(art != null and absf(art.get_size().aspect() - 16.0 / 12.0) < 0.002, "original spillway art fits rule grid")
	check(map.MAPS.find("spillway").campaign_only and not map.MAPS.available().any(func(item: Dictionary) -> bool: return item.id == "spillway"), "spillway is campaign-only")
	for row: String in map.map_definition.rows: check(row.length() == 16, "spillway row exactly sixteen cells")
	for y: int in [4, 5]:
		for x: int in range(16): check((map.ground(Vector2i(x, y)) == "bridge") == (x in [3, 12]), "only the two authored bridges traverse the river")
	for plan: String in ["joint", "split", "hold"]:
		for watch: String in ["upstream", "tower"]:
			for order: String in ["seal", "metered"]: walk(plan, watch, order)
	var graph: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/chapters/chapter_14.json"))
	for id: String in graph.strings: check(seen.has(id), "fourteenth text is reachable from earned history: " + id)
	print("FOURTEENTH: %d CHECKS | FAILURES: %d | TEXTS: %d" % [checks, failures, seen.size()])
	quit(0 if failures == 0 else 1)
