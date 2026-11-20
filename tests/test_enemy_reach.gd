extends SceneTree

const Reach = preload("res://scripts/enemy_reach.gd")
const Course = preload("res://scripts/training.gd")
const Snap = preload("res://scripts/battle_snapshot.gd")
const Session = preload("res://scripts/campaign_session.gd")
const AI = preload("res://scripts/opponent.gd")

var checks := 0
var failures := 0
var comparisons := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		check(compare_weather(), "all weather and status fixtures finished")
		check(special_cases(), "public-state and drill cases finished")
	else:
		for scenario: String in args: check(trace_encounter(scenario), "completed " + scenario)
	print("ENEMY REACH | ", comparisons, " attacker-cell comparisons | ", checks, " checks | ", failures, " failures")
	quit(0 if failures == 0 else 1)

func compare_weather() -> bool:
	for sky: String in ["clear", "rain", "fog", "snow", "tailwind"]:
		for ticks: int in [1, 3]:
			var b := Battle.new(4216, "rivergate")
			var setup := Course.new()
			var bow := setup._place(b, "archer", Vector2i(6,3), 1)
			var rider := setup._place(b, "cavalry", Vector2i(3,4), 1)
			var spear := setup._place(b, "spear", Vector2i(8,5), 1)
			setup._place(b, "healer", Vector2i(3,6), 0)
			bow.summoning = true
			bow.attacked = true
			rider.rooted_turns = 1
			spear.rooted_turns = 2
			b.weather = sky
			b.weather_remaining = ticks
			var before := Snap.capture(b)
			var preview := Reach.project(b, 1)
			check(Snap.capture(b) == before, "forecast preserves the complete live state including RNG, weather, flags and clock")
			if not check(b.end_turn().ok and b.active_side == 1, "actual enemy turn begins"): return false
			if not check(preview == Reach.project(b,1), "the predicted refill matches the actual refreshed turn, " + sky): return false
			if not compare_cells(b, preview): return false
			bow.moved = true
			rider.attacked = true
			spear.summoning = true
			if not compare_cells(b, Reach.project(b,1)): return false
	return true

func compare_cells(b: Battle, forecast: Dictionary) -> bool:
	var actors: Array = b.units.filter(func(u: Dictionary) -> bool: return u.side == 1)
	for y: int in range(b.height):
		for x: int in range(b.width):
			var cell := Vector2i(x,y)
			var occupant := b.unit_at(cell)
			if not b.passable(cell) or occupant.get("side",-1) == 1:
				if not check(not forecast.has(cell), "unavailable landing " + str(cell)): return false
				continue
			# A prospective defender actually occupies the tile when testing legal paths.
			if occupant.is_empty(): b.units.append({"id":-10,"side":0,"pos":cell})
			for actor: Dictionary in actors:
				var direct := b.attack_targets(actor).has(cell)
				var origins: Array[Vector2i] = []
				if not direct:
					for landing: Vector2i in b.movement_cells(actor):
						var moved := actor.duplicate()
						moved.pos = landing
						moved.moved = true
						if b.attack_targets(moved).has(cell): origins.append(landing)
				var expected := 2 if direct else (0 if origins.is_empty() else 1)
				var actual := Reach.level(forecast,cell,actor.id)
				comparisons += 1
				if not check(actual == expected, "classification %s %s at %s, expected %d" % [b.weather,actor.kind,b.cell_name(cell),expected]): return false
				if actual == 1 and not check(origins.has(forecast[cell].advance[actor.id]), "reported firing tile is reachable with the defender present"): return false
			if occupant.is_empty(): b.units.pop_back()
	return true

func special_cases() -> bool:
	var course := Course.new()
	var b := course.prepare(5)
	var born := Reach.project(b,1)
	var bow := b.unit_at(Course.BRIDGE_ARCHER)
	check(Reach.level(born,Course.MEDIC_SITES[0],bow.id) == 0 and Reach.level(born,Course.MEDIC_SITES[1],bow.id) == 1, "choice between safe bank and exposed bridge")
	b.players[1].hand.reverse()
	b.players[1].deck.reverse()
	b.traps.append({"side":1,"pos":Course.MEDIC_SITES[0]})
	check(Reach.project(b,1) == born, "private trap position and unseen cards cannot affect the public projection")
	b.traps.clear()
	var second := course._place(b, "spear", Vector2i(3,4), 1)
	var overlap := Reach.project(b,1)
	var bridge: Vector2i = Course.MEDIC_SITES[1]
	check(Reach.level(overlap,bridge,-1) == 2 and Reach.level(overlap,bridge,second.id) == 2 and Reach.level(overlap,bridge,bow.id) == 1,
		"the strongest combined mark preserves the other attacker's move-only firing point when focused")
	b.objective = {"escort_id":bow.id}
	var escort_map := Reach.project(b,1)
	for cell: Vector2i in escort_map:
		if not check(Reach.level(escort_map,cell,bow.id) == 0, "noncombatant has no attacks"): return false
	b.winner = 1
	check(Reach.project(b,1).is_empty(), "a finished battle has no remaining attacks")
	return true

func trace_encounter(id: String) -> bool:
	var campaign := Session.Campaign.new()
	if not campaign.index.scenarios.has(id): return false
	var opening := Session.create_encounter(campaign.index.scenarios[id])
	if not check(opening.ok, "standard authored encounter opens"): return false
	var b: Battle = opening.battle
	var recent_move := {}
	var strikes := 0
	var move_only := 0
	var actions := 0
	var example := ""
	while b.winner == -1 and actions < 1800:
		var action := AI.choose(b)
		var before_move := {}
		if b.active_side == 1 and action.type == "move":
			before_move = {"id":action.unit_id,"cell":b.get_unit(action.unit_id).pos,"map":Reach.project(b,1)}
		if b.active_side == 1 and action.type == "attack":
			strikes += 1
			var actor := b.get_unit(action.unit_id)
			if not check(Reach.level(Reach.project(b,1),action.target,actor.id) == 2, "actual ordinary attack was marked on the exact board"): return false
			if recent_move.get("id",-1) == actor.id:
				var prior := Reach.level(recent_move.map,action.target,actor.id)
				if not check(prior > 0, "actual move-then-attack was covered before the move"): return false
				if prior == 1:
					move_only += 1
					if example.is_empty():
						example = "turn %d %s %s -> %s attacks %s at %s" % [b.turn,actor.name,b.cell_name(recent_move.cell),b.cell_name(actor.pos),b.unit_at(action.target).name,b.cell_name(action.target)]
		if not check(b.apply_action(action).ok, "ordinary campaign action accepted"): return false
		recent_move = before_move
		actions += 1
	print("CAMPAIGN ",id," | seed ",b.match_seed," | winner ",b.winner," | side turns ",b.turn," | actions ",actions," | red attacks ",strikes," | move-only strikes ",move_only," | ",example)
	return check(b.winner != -1 and strikes > 0 and move_only > 0,"completed a battle with a genuinely move-only strike")
