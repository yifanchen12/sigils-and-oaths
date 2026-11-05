extends SceneTree
## Real initial states and legal actions only. These are policy diagnostics,
## not claims about human balance or a manual playthrough.
const Model = preload("res://scripts/battle.gd")
const Campaign = preload("res://scripts/campaign.gd")
const AI = preload("res://scripts/opponent.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
func _initialize() -> void: call_deferred("run")
func portable(action: Dictionary) -> Dictionary:
	var result: Dictionary = action.duplicate(true)
	if result.get("target") is Vector2i: result.target = [result.target.x, result.target.y]
	return result
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var baseline: bool = args.has("--baseline")
	var policy: Script = load("res://.tools/opponent_before_v017.gd") if baseline else AI
	var catalog: RefCounted = Campaign.new()
	var results: Array[Dictionary] = []
	var failed: bool = false
	for id: String in catalog.index.scenarios:
		var config: Dictionary = catalog.index.scenarios[id]
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
			var action: Dictionary = policy.choose(battle)
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
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if file == null: push_error("cannot write campaign diagnostic"); quit(1); return
	file.store_string(JSON.stringify({"policy": "0.16.0 baseline" if baseline else "objective-aware candidate", "note": "All eight authored scenarios at fixed seeds, symmetric policy, real initial resources and legal actions; fixed 0.35 s cadence. Not human balance or manual playthrough evidence.", "games": results}, "\t"))
	file.close()
	print("CAMPAIGN BENCHMARK: %d SCENARIOS | INVALID_OR_CAPPED: %s" % [results.size(), failed])
	quit(1 if failed else 0)
