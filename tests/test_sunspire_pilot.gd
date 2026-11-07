extends SceneTree
## Audit the diagnostic player's public-information boundary at real positions.
const Campaign = preload("res://scripts/campaign.gd")
const Replay = preload("res://tests/test_campaign_replays.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Pilot = preload("res://tests/fixtures/sunspire_focus_pilot.gd")
const HarborPilot = preload("res://tests/fixtures/harbor_court_pilot.gd")
var pilot: Script = Pilot
var checks: int = 0
var failures: int = 0
var samples: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func sample(battle: Battle, expected: Dictionary) -> void:
	var before: Dictionary = Snapshot.capture(battle)
	var chosen: Dictionary = pilot.choose(battle)
	check(Snapshot.capture(battle) == before, "diagnostic choice does not mutate rules, clock, resources or RNG")
	check(battle.get_legal_actions(0).has(chosen), "diagnostic choice is an ordinary legal action")
	check(chosen == expected, "sampled position reproduces the saved strategy decision")
	var old_players: Array[Dictionary] = battle.players.duplicate(true)
	var old_seed: int = battle.rng.seed
	var old_state: int = battle.rng.state
	var old_match_seed: int = battle.match_seed
	for card: Dictionary in battle.players[1].hand: card.card_id = "bolt"
	for side: int in [0, 1]: battle.players[side].deck.reverse()
	battle.rng.seed = 99991; battle.match_seed = 99883
	check(pilot.choose(battle) == chosen, "enemy cards, both future deck orders and seed cannot affect public-board policy")
	battle.players = old_players; battle.rng.seed = old_seed; battle.rng.state = old_state; battle.match_seed = old_match_seed
	check(Snapshot.capture(battle) == before, "hidden-information probe restores original position exactly")
	samples += 1
func run() -> void:
	var catalog: RefCounted = Campaign.new()
	var harbor: bool = OS.get_cmdline_user_args().has("--harbor-player")
	pilot = HarborPilot if harbor else Pilot
	var path: String = "res://tests/fixtures/campaign_v028_harbor.json" if harbor else "res://tests/fixtures/campaign_v028_sunspire.json"
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var scope: Array = ["c04_dock", "c04_pump", "c06_court"] if harbor else ["c08_isolate", "c08_buffer"]
	check(report.scenario_ids == scope, "diagnostic scope names every encounter in the selected group, including losses")
	for row: Dictionary in report.games:
		var c: Dictionary = catalog.index.scenarios[row.scenario]
		var battle := Battle.new(int(c.seed), c.map, c.hero, c.enemy_class, c.deck, c.enemy_deck, 90)
		battle.set_commander_identity(1, c.enemy_name, c.enemy_portrait); battle.configure_objective(c.get("control", {}))
		var last_sample_turn: int = -1
		for step: Dictionary in row.trace:
			var action: Dictionary = Replay.action_from(step.action)
			if battle.active_side == 0 and battle.turn != last_sample_turn:
				sample(battle, action); last_sample_turn = battle.turn
			battle.advance_clock(float(step.elapsed))
			var outcome: Dictionary = battle.apply_action(action)
			if not outcome.ok: check(false, "audit replay remains legal"); quit(1); return
		check(battle.winner == int(row.winner) and battle.turn == int(row.turn), "sampled replay reaches its recorded outcome")
	print("CAMPAIGN PILOT CHECKS: %d | FAILURES: %d | PUBLIC POSITIONS: %d | GROUP: %s" % [checks, failures, samples, "harbor" if harbor else "sunspire"])
	quit(0 if failures == 0 else 1)
