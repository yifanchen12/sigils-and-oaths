extends SceneTree
## Actual preset-vs-preset matches using the production opponent on both seats.

const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const PAIRS: Array[Array] = [["breakwater_line", "ember_quarter"], ["breakwater_line", "frost_engine"],
	["ember_quarter", "frost_engine"], ["ember_quarter", "lantern_convoy"]]
const ACTION_LIMIT: int = 1000

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	run_suite("moorings", 4901, PAIRS)

func run_suite(card_set: String, seed_value: int, pairs: Array[Array]) -> void:
	var title: String = card_set.to_upper()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
	var games: Array[Dictionary] = []
	var failures: int = 0
	var actions: int = 0
	for map_id: String in ["greenwood", "rivergate", "harbor"]:
		for pair: Array in pairs:
			for swapped: int in [0, 1]:
				var game: Dictionary = play_match(seed_value, map_id, pair[swapped], pair[1 - swapped], card_set)
				games.append(game)
				actions += int(game.actions)
				if not String(game.error).is_empty(): failures += 1
				print("%s %s %s-%s | WINNER %d | TURN %d | ACTIONS %d" % [title, map_id, game.blue, game.red, game.winner, game.turn, game.actions])
	var path: String = "res://.tools/%s-%d.json" % [card_set, seed_value]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write match report")
		quit(1)
		return
	file.store_string(JSON.stringify({"seed": seed_value, "actions": actions, "failures": failures, "rules": Snapshot.rules_signature(), "games": games}, "\t"))
	file.close()
	print("%s MATCHUPS: %d | ACTIONS: %d | FAILURES: %d" % [title, games.size(), actions, failures])
	quit(0 if failures == 0 else 1)

func play_match(seed_value: int, map_id: String, blue: String, red: String, card_set: String = "moorings") -> Dictionary:
	var battle := Model.new(seed_value, map_id, "warden", "warden", blue, red)
	var turn_actions: int = 0
	var count: int = 0
	var plays: Dictionary = {}
	var paid_by_cost: Dictionary = {}
	var triggers: Dictionary = {}
	var combos: Dictionary = {}
	var problem: String = ""
	while battle.winner == -1 and count < ACTION_LIMIT:
		var side: int = battle.active_side
		var action: Dictionary = AI.choose(battle)
		var card: Dictionary = battle.definition(battle.hand_card(side, action.card_uid).card_id) if action.type == "play" else {}
		var had_combo: bool = battle.combo_ready(card, side)
		var result: Dictionary = battle.apply_action(action)
		if not result.ok:
			problem = str(result.message)
			break
		count += 1
		if card.get("set_id", "") == card_set:
			plays[card.id] = int(plays.get(card.id, 0)) + 1
			paid_by_cost[card.cost] = int(paid_by_cost.get(card.cost, 0)) + 1
			if had_combo: combos[card.id] = int(combos.get(card.id, 0)) + 1
		for event: Dictionary in battle.last_trap_events:
			if event.reason == "触发": triggers[event.name] = int(triggers.get(event.name, 0)) + 1
		if action.type == "end_turn":
			turn_actions += 1
			if turn_actions % 5 == 0 and not Snapshot.validate(Snapshot.capture(battle)).ok:
				problem = "invalid turn-end snapshot"
				break
	if problem.is_empty() and battle.winner == -1: problem = "action limit"
	if problem.is_empty() and not Snapshot.validate(Snapshot.capture(battle)).ok: problem = "invalid final snapshot"
	var summary: Dictionary = {"map": map_id, "blue": blue, "red": red, "winner": battle.winner, "turn": battle.turn, "actions": count,
		"plays": plays, "played_costs": paid_by_cost, "trap_triggers": triggers, "error": problem}
	if card_set == "pilgrim": summary["combos"] = combos
	return summary
