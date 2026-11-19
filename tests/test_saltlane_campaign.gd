extends SceneTree

const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const AI = preload("res://scripts/opponent.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const PRIOR_EASTWARD := "res://tests/fixtures/v045-c07-eastward.json"
const PRIOR_ENCOUNTER := "res://tests/fixtures/v045-c08-encounter.json"

var checks: int = 0
var failures: int = 0
var results: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition: failures += 1; push_error(label)
	return condition

func until_page(session: RefCounted, destination: String, choices: Dictionary = {}) -> bool:
	for step: int in range(400):
		var runner: RefCounted = session.campaign.story
		var page: Dictionary = runner.current()
		if page.node == destination or page.get("scenario", "") == destination: return true
		if page.type == "dialogue": runner.advance(page.revision)
		elif page.type == "choice" and choices.has(page.node): runner.choose(choices[page.node], page.revision)
		else: return false
	return false

func enter_seventh(session: RefCounted) -> bool:
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PRIOR_EASTWARD))
	var sixth: Dictionary = prior.completed.back()
	var start: Dictionary = {"chapter_id": "chapter_06", "story": sixth.story, "completed": prior.completed.slice(0, 5)}
	if not check(session.campaign.restore(start).ok and session.next_chapter(session.token()).ok, "enter C07 from actual 0.45 history"): return false
	return check(until_page(session, "saltlane_call", {"camp": "clinic"}), "normal C07 dialogue reaches optional rescue")

func enter_branch(session: RefCounted, route: String, requisition: String = "") -> bool:
	if not enter_seventh(session): return false
	if not check(session.choose("answer_call", session.token()).ok and until_page(session, "saltlane_route"), "accept rescue and reach route choice"): return false
	var scenario := "c07_saltlane_" + route
	if not check(session.choose(route, session.token()).ok and until_page(session, scenario), "reach chosen escort briefing"): return false
	if not check(not session.current().can_retreat and not session.retreat(session.token()).ok, "cannot withdraw before fighting"): return false
	if not requisition.is_empty() and not check(session.choose_requisition(requisition, session.token()).ok, "choose a real optional-escort requisition"): return false
	return check(session.begin_battle(session.token()).ok, "start authored escort with normal opening resources")

func test_rules() -> void:
	var session = Session.new("res://.tools/v046-saltlane-rules.json")
	if not enter_branch(session, "school"): return
	var battle: Battle = session.encounter
	var crew: Dictionary = battle.escort_unit()
	var exit: Vector2i = battle.ControlObjective.position(battle.objective.cells[0])
	check(battle.width == 16 and battle.height == 12 and battle.ground(Vector2i(3, 5)) == "bridge" and battle.ground(Vector2i(12, 6)) == "bridge", "original 192-cell battlefield uses both drawn bridges")
	check(crew.side == 0 and crew.hp == crew.max_hp and not battle.movement_cells(crew).is_empty(), "marked field crew can move at the start")
	check(battle.unit_at(Vector2i(8, 4)).side == 1 and battle.army_count(1) == 1, "opposing archer starts on the north quay")
	var decoy: Dictionary = Fixture.troop(battle, "sword", exit + Vector2i.UP)
	var deceptive: Dictionary = {"type": "move", "unit_id": decoy.id, "target": exit}
	check(battle.apply_action(deceptive).ok and battle.winner == -1 and battle.objective.streak == 0, "ordinary ally cannot deliver the patient")
	var recall: Dictionary = Fixture.give(battle, "recall_writ")
	check(not battle.card_targets(recall.uid, 0).has(crew.pos), "escort cannot be removed into the hand")
	var attacker: Dictionary = Fixture.troop(battle, "sword", crew.pos + Vector2i.LEFT, 1)
	check(battle.attack_targets(crew).is_empty() and battle.attack_forecast(attacker, crew).counter_damage == 0, "escort cannot initiate attacks or counterattack")
	crew.hp -= 1
	check(battle.skill_targets(crew).has(crew.pos), "crew still has its medical active skill")
	var wrong_id: Dictionary = Snapshot.capture(battle)
	wrong_id.objective.escort_id = decoy.id
	check(not Snapshot.validate(wrong_id).ok and Snapshot.validate(Snapshot.capture(battle)).ok, "snapshot refuses a replacement objective unit")
	var impossible: Dictionary = battle.ControlObjective.config(battle.objective)
	impossible.escort_start = [3, 6]
	impossible.sentry_start = impossible.escort_start
	check(not battle.ControlObjective.validate_config(impossible, battle.map_definition).is_empty(), "invalid overlapping starts fail content validation")

func finish_to_eighth(session: RefCounted, fact: String, reward: String) -> void:
	if not check(until_page(session, "end") and session.next_chapter(session.token()).ok, "authored aftermath returns to main campaign"): return
	check(session.campaign.story.state.flags.saltlane_result == fact, "chapter eight records the correct escort result")
	if not check(until_page(session, "c08_isolate", {"pressure": "isolate"}), "chapter eight remains playable through normal choices"): return
	var history: Array = session.campaign.story.state.history
	var expected_line := "c08.rope.saltlane." + fact
	check(history.has(expected_line) == (fact != "none"), "correct next chapter's callback appears in backlog")
	check(session.campaign.scenario().get("bonus_card", "") == reward, "first hand reward corresponds to actual result")
	var expected_shield: int = 3 if fact == "kiln" else 0
	check(session.campaign.scenario().get("commander_shield", 0) == expected_shield, "only the kiln route grants the opening shield")
	if not check(session.begin_battle(session.token()).ok, "enter the actual chapter-eight encounter"): return
	var output: bool = false
	for card: Dictionary in session.encounter.players[0].hand:
		if card.card_id == reward: output = true
	check(output == not reward.is_empty() and session.encounter.players[0].card_total == 30 + int(not reward.is_empty()), "normal battle adds precisely the earned supply")
	check(session.encounter.commander(0).shield == expected_shield, "starting shield is present on the live commander")
	var exact: Dictionary = Snapshot.capture(session.encounter)
	var copy = Session.new(session.store.path)
	check(copy.load_campaign().ok and Snapshot.capture(copy.encounter) == exact, "follow-up supplies survive battle save/reload")

func test_delivery(route: String, reward: String) -> void:
	var path := "res://.tools/v046-saltlane-win-" + route + ".json"
	var session = Session.new(path)
	if not enter_branch(session, route): return
	var battle: Battle = session.encounter
	var reload_at: int = -1
	var min_hp: int = int(battle.escort_unit().hp)
	var actions: int = 0
	while battle.winner == -1 and actions < 150:
		var decision: Dictionary = AI.choose(battle)
		if not check(battle.apply_action(decision).ok, "legal escort action " + route): return
		actions += 1
		min_hp = mini(min_hp, int(battle.escort_unit().get("hp", 0)))
		if battle.turn >= 3 and reload_at == -1 and battle.winner == -1:
			battle.advance_clock(11.5)
			var before: Dictionary = Snapshot.capture(battle)
			if not check(session.save().ok, "save during " + route + " evacuation"): return
			var fresh = Session.new(path)
			if not check(fresh.load_campaign().ok and Snapshot.capture(fresh.encounter) == before, "exact mid-escort restoration"): return
			session = fresh
			battle = session.encounter
			reload_at = actions
	if not check(battle.winner == 0 and battle.objective.streak == 1 and not battle.commander(1).is_empty(), "deliver marked team while opposing commander is still alive"): return
	check(battle.escort_unit().pos == battle.ControlObjective.position(battle.objective.cells[0]) and min_hp < 6, "team reaches the intended exit and survived damage")
	check(Snapshot.validate(Snapshot.capture(battle)).ok, "immediate win is a valid final state")
	results[route] = {"actions": actions, "turn": battle.turn, "escort_min_hp": min_hp, "reload_at_action": reload_at,
		"exit": battle.cell_name(battle.escort_unit().pos)}
	if not check(session.finish_battle(battle).ok and session.current().node == "saltlane_" + route + "_after", "actual victory unlocks chosen aftermath"): return
	finish_to_eighth(session, route, reward)

func test_withdrawal() -> void:
	var path := "res://.tools/v046-saltlane-defeat.json"
	var session = Session.new(path)
	if not enter_branch(session, "kiln", "chalk_spike"): return
	var battle: Battle = session.encounter
	var original: Dictionary = Snapshot.capture(battle)
	while battle.winner == -1 and battle.turn <= 20:
		battle.end_turn()
	check(battle.winner == 1 and not battle.escort_unit().is_empty() and battle.log_lines.any(func(line: String) -> bool: return line.contains("护送时限已到")), "deadline causes defeat even when crew stays alive")
	if not check(session.save().ok, "save terminal timeout before returning to story"): return
	session = Session.new(path)
	if not check(session.load_campaign().ok and session.encounter == null and session.current().can_retreat and session.current().attempts == 1, "loading terminal battle restores retry exactly once"): return
	check(session.campaign.requisition == "chalk_spike", "losing preserves the selected escort requisition")
	var stale: Dictionary = session.token()
	if not check(session.begin_battle(stale).ok and Snapshot.capture(session.encounter) == original, "retry rebuilds same authored force and seed"): return
	battle = session.encounter
	for step: int in range(120):
		if battle.winner != -1: break
		var action: Dictionary = {"type": "end_turn"} if battle.active_side == 0 else AI.choose(battle)
		if not check(battle.apply_action(action).ok, "defeat test uses normal actions"): return
	if not check(battle.winner == 1 and battle.escort_unit().is_empty() and Snapshot.validate(Snapshot.capture(battle)).ok, "enemy can cause escort loss and casualty survives validation"): return
	if not check(session.finish_battle(battle).ok and not session.retreat(stale).ok, "stale retreat token fails after retry and second loss"): return
	if not check(session.current().attempts == 2 and session.retreat(session.token()).ok and session.current().node == "saltlane_retreat", "withdrawal after defeat takes its authored path"): return
	check(session.campaign.requisition.is_empty(), "withdrawing clears the selected escort requisition")
	finish_to_eighth(session, "withdrawn", "")

func test_old_release() -> void:
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PRIOR_EASTWARD))
	var campaign = Campaign.new()
	check(campaign.restore(old).ok and campaign.story.current().line_id == old.story.line_id and campaign.story.state.flags.saltlane_result == "none", "0.45 save past the insertion keeps exact dialogue cursor")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PRIOR_ENCOUNTER))
	check(legacy.encounter.battle.version == 7 and legacy.encounter.battle.rules == Snapshot.v045_rules_signature(), "old snapshot signature matches actual prior PCK")
	var session = Session.new(PRIOR_ENCOUNTER)
	if not check(session.load_campaign().ok and session.encounter != null, "actual 0.45 C08 encounter restores"): return
	check(session.encounter.turn == 2 and is_equal_approx(session.encounter.time_remaining, 75.5) and session.campaign.scenario().get("bonus_card", "") == "", "old clock and lack of escort reward survive")
	check(session.encounter.end_turn().ok and session.encounter.turn == 3, "old encounter resumes legitimate turns")

func run() -> void:
	test_old_release()
	test_rules()
	test_delivery("school", "lantern_stretcher")
	test_delivery("kiln", "")
	test_withdrawal()
	print("SALTLANE %d CHECKS | %d FAILURES | %s" % [checks, failures, JSON.stringify(results)])
	quit(0 if failures == 0 else 1)
