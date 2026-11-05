extends SceneTree

const Session = preload("res://scripts/campaign_session.gd")
const BattleModel = preload("res://scripts/battle.gd")
const PATH: String = "res://.tools/test_campaign_session.json"
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(label)

func cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix): DirAccess.remove_absolute(PATH + suffix)

func arrive_at_battle(session: RefCounted, route: String = "river") -> void:
	while session.current().type == "dialogue": session.advance(session.token())
	session.choose(route, session.token())
	while session.current().type == "dialogue": session.advance(session.token())

func defeat_commander(battle: RefCounted, side: int) -> void:
	battle.commander(side).hp = 0
	battle._cleanup()
	battle._check_winner()

func win_with_rules(battle: RefCounted) -> void:
	# Fixture positions shorten the battle; the actual attack resolver decides victory.
	var own: Dictionary = battle.commander(0)
	var enemy: Dictionary = battle.commander(1)
	for direction: Vector2i in BattleModel.DIRECTIONS:
		var cell: Vector2i = own.pos + direction
		if battle.passable(cell) and battle.unit_at(cell).is_empty():
			enemy.pos = cell
			break
	battle.terrain[enemy.pos] = "plain"
	enemy.hp = 1
	enemy.defense = 0
	var result: Dictionary = battle.apply_action({"type": "attack", "unit_id": own.id, "target": enemy.pos})
	check(result.ok and battle.winner == 0, "real attack resolver returns the campaign victory")

func test_session() -> bool:
	cleanup()
	var session: RefCounted = Session.new(PATH)
	check(not session.current().ok and not session.load_campaign().ok, "empty session has no fabricated progress")
	check(session.new_campaign().ok, "new campaign starts and saves")
	var stale: Dictionary = session.token()
	check(session.advance(stale).ok, "dialogue advances through coordinator")
	var before: Dictionary = session.campaign.snapshot()
	check(not session.advance(stale).ok and session.campaign.snapshot() == before, "stale page is rejected")
	check(session.new_campaign().ok, "restart succeeds")
	check(not session.advance(stale).ok, "old session callback rejected despite matching revision zero")
	arrive_at_battle(session)
	var started: Dictionary = session.begin_battle(session.token())
	check(started.ok and started.battle == session.encounter, "session gives UI the authoritative battle instance")
	var original: RefCounted = started.battle
	var setup: Dictionary = started.scenario
	check(original.match_seed == setup.seed and original.map_definition.id == setup.map, "scenario map and seed applied")
	check(original.deck(0).id == setup.deck and original.deck(1).id == setup.enemy_deck, "both authored armies applied")
	check(original.turn_time_limit == 90 and original.players[0].hero_id == setup.hero, "campaign keeps selected rules and ninety second turns")
	check(original.hero(1).name == setup.enemy_name and original.commander(1).name == setup.enemy_name and original.hero(1).portrait == "terrain_fort", "NPC displayed consistently without companion portrait")
	check(original.hero(1).id == setup.enemy_class and original.hero(1).effect == BattleModel.HEROES.find(setup.enemy_class).effect, "NPC retains existing rules class")
	check(BattleModel.HEROES.find(setup.enemy_class).name != setup.enemy_name, "NPC does not mutate shared hero resource")
	check(original.side_name(1).contains(setup.enemy_name), "battle logs name the actual NPC force")
	before = session.campaign.snapshot()
	check(not session.finish_battle(original).ok and session.campaign.snapshot() == before, "unfinished battle cannot award story facts")
	check(not session.begin_battle(session.token()).ok and not session.advance(session.token()).ok, "no second battle or dialogue while fighting")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.current().scenario == "c01_river", "during-battle save recovers pre-battle checkpoint")
	defeat_commander(original, 0)
	check(session.finish_battle(original).ok and session.current().last_outcome == "defeat", "loss returns to the actual encounter")
	check(not session.campaign.story.state.flags.witness_present and session.current().attempts == 1, "failure grants no rescued witness")
	check(not session.finish_battle(original).ok, "completed encounter cannot be submitted twice")
	started = session.begin_battle(session.token())
	check(started.ok and started.battle != original and started.battle.match_seed == original.match_seed, "retry creates fresh battle with stable seed")
	var retry: RefCounted = started.battle
	before = session.campaign.snapshot()
	check(not session.finish_battle(original).ok and session.encounter == retry and session.campaign.snapshot() == before, "late result cannot replace retry")
	win_with_rules(retry)
	check(session.finish_battle(retry).ok and session.current().node == "river_after", "rules victory advances to post-battle dialogue")
	check(session.campaign.story.state.flags.witness_present, "successful rescue now unlocks witness")
	check(fresh.load_campaign().ok and fresh.current().node == "river_after" and fresh.campaign.story.state.attempts.river_battle == 2, "victory checkpoint persists with both attempts")
	check(session.backlog().size() > 0, "backlog contains actual visited text")
	var exported: Array = session.backlog(); exported[0].text = "changed"
	check(session.backlog()[0].text != "changed", "backlog is a nonexecuting copy")
	check(session.new_campaign().ok, "start stale-load fixture")
	arrive_at_battle(session, "road")
	started = session.begin_battle(session.token())
	defeat_commander(started.battle, 1)
	check(session.load_campaign().ok, "loading clears active encounter")
	before = session.campaign.snapshot()
	check(not session.finish_battle(started.battle).ok and session.campaign.snapshot() == before, "late result after load cannot award copied order")
	check(not session.campaign.story.state.flags.seal_copy, "road evidence awarded only after accepted win")
	started = session.begin_battle(session.token())
	session.leave_battle()
	check(session.encounter == null and session.current().type == "battle", "leaving for skirmish retains checkpoint")
	check(not session.finish_battle(started.battle).ok, "skirmish switch invalidates campaign callback")
	# Failed autosave is visible and retryable; it never silently pretends durability.
	session.store.path = "res://.tools/__campaign_missing_dir__/save.json"
	check(not session.begin_battle(session.token()).ok and session.encounter == null, "unsavable checkpoint blocks entering battle")
	check(session.unsaved and not session.notice.is_empty(), "write failure is visible to UI")
	before = session.campaign.snapshot()
	check(not session.new_campaign().ok and session.campaign.snapshot() == before, "failed restart preserves running progress")
	session.store.path = PATH
	check(session.save().ok and not session.unsaved, "manual retry clears save error only after real write")
	cleanup()
	return true

func test_complete_routes() -> bool:
	for route: String in ["road", "river"]:
		cleanup()
		var session: RefCounted = Session.new(PATH)
		check(session.new_campaign().ok, route + " route starts")
		var battles: int = 0
		var steps: int = 0
		while session.current().type != "end" and steps < 160:
			var page: Dictionary = session.current()
			match page.type:
				"dialogue": check(session.advance(session.token()).ok, "coordinated authored line " + page.line_id)
				"choice":
					var option: String = route if page.node == "route" else str(page.options[0].id)
					check(session.choose(option, session.token()).ok, "coordinated authored choice " + page.node)
				"battle":
					var result: Dictionary = session.begin_battle(session.token())
					check(result.ok, "authored encounter starts")
					if not result.ok: return false
					win_with_rules(result.battle)
					check(session.finish_battle(result.battle).ok, "authored encounter returns to story")
					battles += 1
			steps += 1
		check(session.current().type == "end" and battles == 2, route + " route ends after two resolved battles")
		var reloaded: RefCounted = Session.new(PATH)
		check(reloaded.load_campaign().ok and reloaded.current().type == "end", "chapter completion survives fresh session")
		check(reloaded.campaign.story.state.decisions.size() == 3, "all three decisions persist")
		check(reloaded.campaign.story.state.flags.route == route, "finished the requested route, not a fallback")
	cleanup()
	return true

func run() -> void:
	check(test_session(), "session tests completed")
	check(test_complete_routes(), "both complete route tests completed")
	print("CAMPAIGN SESSION CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
