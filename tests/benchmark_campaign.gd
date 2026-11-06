extends SceneTree
## Real initial states and legal actions only. These are policy diagnostics,
## not claims about human balance or a manual playthrough.
const Model = preload("res://scripts/battle.gd")
const Campaign = preload("res://scripts/campaign.gd")
const AI = preload("res://scripts/opponent.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Pilot = preload("res://tests/fixtures/campaign_pilot.gd")
const FocusPilot = preload("res://tests/fixtures/bridge_focus_pilot.gd")
const SunspirePilot = preload("res://tests/fixtures/sunspire_focus_pilot.gd")
const HarborPilot = preload("res://tests/fixtures/harbor_court_pilot.gd")
func _initialize() -> void: call_deferred("run")
func portable(action: Dictionary) -> Dictionary:
	var result: Dictionary = action.duplicate(true)
	if result.get("target") is Vector2i: result.target = [result.target.x, result.target.y]
	return result
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var baseline: bool = args.has("--baseline")
	var cautious: bool = args.has("--cautious-player")
	var focus: bool = args.has("--focus-player")
	var sunspire: bool = args.has("--sunspire-player")
	var harbor: bool = args.has("--harbor-player")
	var objectives_only: bool = args.has("--objectives-only")
	var selected: String = ""
	for arg: String in args:
		if arg.begins_with("--scenario="): selected = arg.trim_prefix("--scenario=")
	if int(baseline) + int(cautious) + int(focus) + int(sunspire) + int(harbor) > 1:
		push_error("baseline, cautious-player, focus-player, sunspire-player and harbor-player are separate diagnostic groups"); quit(1); return
	if baseline and not FileAccess.file_exists("res://.tools/opponent_before_v017.gd"):
		push_error("baseline source is missing; prepare the historical policy as described in docs/campaign-ai.md"); quit(1); return
	var policy: Script = load("res://.tools/opponent_before_v017.gd") if baseline else AI
	var catalog: RefCounted = Campaign.new()
	if (not selected.is_empty() and not catalog.index.scenarios.has(selected)) or (focus and selected != "c01_bridge"):
		push_error("select a valid scenario; focus-player is authored only for c01_bridge"); quit(1); return
	if sunspire and (objectives_only or (not selected.is_empty() and selected not in ["c08_isolate", "c08_buffer"])):
		push_error("sunspire-player covers both Sunspire encounters or one explicitly selected encounter"); quit(1); return
	if harbor and (objectives_only or (not selected.is_empty() and selected not in ["c04_dock", "c04_pump", "c06_court"])):
		push_error("harbor-player covers the two harbor encounters and court, or one explicitly selected encounter"); quit(1); return
	var results: Array[Dictionary] = []
	var failed: bool = false
	for id: String in catalog.index.scenarios:
		if not selected.is_empty() and id != selected: continue
		if sunspire and id not in ["c08_isolate", "c08_buffer"]: continue
		if harbor and id not in ["c04_dock", "c04_pump", "c06_court"]: continue
		var config: Dictionary = catalog.index.scenarios[id]
		if objectives_only and not config.has("control"): continue
		var battle: Battle = Model.new(int(config.seed), config.map, config.hero, config.enemy_class, config.deck, config.enemy_deck, 90.0)
		battle.set_commander_identity(1, config.enemy_name, config.enemy_portrait)
		battle.configure_objective(config.get("control", {}))
		var trace: Array[Dictionary] = []
		var elapsed_us: int = 0
		var peak_us: int = 0
		var peak_control: int = 0
		var denial_count: int = 0
		var illegal: String = ""
		while battle.winner == -1 and trace.size() < 1000:
			var side: int = battle.active_side
			var started: int = Time.get_ticks_usec()
			var player_policy: Script = HarborPilot if harbor else (SunspirePilot if sunspire else (FocusPilot if focus else (Pilot if cautious else policy)))
			var action: Dictionary = player_policy.choose(battle) if side == 0 else policy.choose(battle)
			var decision_us: int = Time.get_ticks_usec() - started
			elapsed_us += decision_us; peak_us = maxi(peak_us, decision_us)
			# Fixed 0.35 second action cadence makes traces deterministic. Actual
			# decision cost is reported separately; no resources or board edits.
			battle.advance_clock(0.35)
			if side != battle.active_side: continue
			var credit: int = battle.objective.get("streak", 0)
			var outcome: Dictionary = battle.apply_action(action)
			if not outcome.ok: illegal = outcome.message; failed = true; break
			trace.append({"side": side, "turn_after": battle.turn, "elapsed": 0.35, "action": portable(action)})
			peak_control = maxi(peak_control, battle.objective.get("streak", 0))
			if credit > 0 and battle.objective.get("streak", 0) == 0: denial_count += 1
		var reason: String = "commander"
		if battle.winner == -1: reason = "action_cap"; failed = true
		elif not battle.objective.is_empty() and not battle.commander(0).is_empty() and not battle.commander(1).is_empty():
			reason = "control" if battle.winner == 0 else "deadline"
		var row: Dictionary = {"scenario": id, "seed": config.seed, "winner": battle.winner, "reason": reason, "turn": battle.turn,
			"actions": trace.size(), "max_control_streak": peak_control, "streak_resets": denial_count,
			"decision_mean_ms": elapsed_us / maxf(1, trace.size()) / 1000.0, "decision_peak_ms": peak_us / 1000.0,
			"illegal_action": illegal, "trace": trace, "final": Snapshot.capture(battle)}
		results.append(row)
		print("CAMPAIGN %s | WINNER %d | %s | TURN %d | ACTIONS %d | PEAK_MS %.2f" % [id, battle.winner, reason, battle.turn, trace.size(), peak_us / 1000.0])
		await process_frame
	var destination: String = "res://.tools/campaign-baseline.json" if baseline else "res://.tools/campaign-objective-ai.json"
	if cautious: destination = "res://.tools/campaign-cautious-player.json"
	if focus: destination = "res://.tools/campaign-bridge-focus.json"
	if sunspire: destination = "res://.tools/campaign-sunspire-player.json"
	if harbor: destination = "res://.tools/campaign-harbor-player.json"
	if results.is_empty(): push_error("the requested scope contains no scenarios"); quit(1); return
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if file == null: push_error("cannot write campaign diagnostic"); quit(1); return
	var report: Dictionary = {"policy": "focused left-bridge diagnostic player against production opponent" if focus else ("cautious diagnostic player against production opponent" if cautious else ("0.16.0 baseline" if baseline else "production opponent on both sides")), "coverage": "selected_scenarios" if not selected.is_empty() else ("objective_scenarios" if objectives_only else "all_scenarios"), "note": "Authored scenarios at fixed seeds, real initial resources and legal actions; fixed 0.35 s cadence. Not human balance or manual playthrough evidence.", "games": results}
	if not selected.is_empty(): report.scenario_ids = [selected]
	if sunspire:
		report.policy = "central-formation diagnostic player against production opponent"
		report.coverage = "selected_scenarios"
		report.scenario_ids = [selected] if not selected.is_empty() else ["c08_isolate", "c08_buffer"]
	if harbor:
		report.policy = "harbor focus and central court diagnostic player against production opponent"
		report.coverage = "selected_scenarios"
		report.scenario_ids = [selected] if not selected.is_empty() else ["c04_dock", "c04_pump", "c06_court"]
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("CAMPAIGN BENCHMARK: %d SCENARIOS | INVALID_OR_CAPPED: %s" % [results.size(), failed])
	quit(1 if failed else 0)
