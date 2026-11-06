extends SceneTree
const Model = preload("res://scripts/battle.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const PATH: String = "res://tests/fixtures/campaign_v017_replays.json"
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
static func action_from(raw: Dictionary) -> Dictionary:
	var action: Dictionary = raw.duplicate(true)
	if action.get("target") is Array: action.target = Vector2i(int(action.target[0]), int(action.target[1]))
	for key: String in ["card_uid", "unit_id"]:
		if action.has(key): action[key] = int(action[key])
	return action
static func state_without_clock(battle: RefCounted) -> Dictionary:
	var state: Dictionary = Snapshot.capture(battle)
	state.erase("time_remaining")
	return JSON.parse_string(JSON.stringify(state, "", true, true))
func run() -> void:
	var source: String = PATH
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): source = arg.trim_prefix("--fixture=")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var catalog: RefCounted = Campaign.new()
	var wins: int = 0
	var moves: int = 0
	var expected_ids: Array = []
	var coverage: String = report.get("coverage", "all_scenarios")
	check(coverage in ["all_scenarios", "objective_scenarios", "selected_scenarios"], "fixture declares a recognized coverage scope")
	if coverage == "selected_scenarios":
		expected_ids = report.get("scenario_ids", [])
		check(not expected_ids.is_empty(), "selected scope names at least one scenario")
		var seen: Dictionary = {}
		for id: String in expected_ids:
			check(catalog.index.scenarios.has(id) and not seen.has(id), "selected scenario exists and is not duplicated")
			seen[id] = true
	else:
		for id: String in catalog.index.scenarios:
			if coverage != "objective_scenarios" or catalog.index.scenarios[id].has("control"): expected_ids.append(id)
	var recorded_ids: Array = report.games.map(func(row: Dictionary): return row.scenario)
	expected_ids.sort(); recorded_ids.sort()
	check(expected_ids == recorded_ids, "every scenario in the declared suite has exactly one trace including losses")
	if failures > 0: quit(1); return
	for row: Dictionary in report.games:
		var config: Dictionary = catalog.index.scenarios[row.scenario]
		var battle: Battle = Model.new(int(config.seed), config.map, config.hero, config.enemy_class, config.deck, config.enemy_deck, 90.0)
		battle.set_commander_identity(1, config.enemy_name, config.enemy_portrait)
		battle.configure_objective(config.get("control", {}))
		for step: Dictionary in row.trace:
			check(battle.active_side == int(step.side) and battle.winner == -1, "recorded action belongs to current live turn")
			battle.advance_clock(float(step.elapsed))
			var outcome: Dictionary = battle.apply_action(action_from(step.action))
			check(outcome.ok and battle.turn == int(step.turn_after), "replay action accepted by canonical rules")
			if not outcome.ok: break
			moves += 1
		var expected: Dictionary = row.final.duplicate(true)
		if int(expected.version) < Snapshot.VERSION:
			var migrated: Dictionary = Snapshot.restore(expected)
			check(migrated.ok, "historical fixture uses the explicit additive expansion migration")
			if not migrated.ok: continue
			expected = Snapshot.capture(migrated.battle)
			expected = JSON.parse_string(JSON.stringify(expected, "", true, true))
		check(absf(battle.time_remaining - float(expected.time_remaining)) < 0.00001, "recorded action cadence preserves clock")
		expected.erase("time_remaining")
		check(state_without_clock(battle) == expected, "entire final state including cards, units, RNG and objective reproduces")
		check(battle.winner == int(row.winner), "reported result is actual rules result")
		check(Snapshot.validate(Snapshot.capture(battle)).ok, "final full save is valid")
		if battle.winner == 0: wins += 1
	print("CAMPAIGN REPLAY CHECKS: %d | FAILURES: %d | ACTIONS: %d | PLAYER_POLICY_WINS: %d/%d" % [checks, failures, moves, wins, report.games.size()])
	quit(0 if failures == 0 else 1)
