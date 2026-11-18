extends SceneTree
## Mirrored skirmishes with ordinary decks, mana, and production AI for both seats.
const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const DECKS = ["reed_legion", "frost_engine", "lantern_convoy"]
const MAPS = ["greenwood", "rivergate", "ridgepass"]
const ACTION_CAP = 1000

func _initialize() -> void:
	call_deferred("run")

func play_match(deck: String, opponent_deck: String, map: String, seed_value: int, expansion_side: int, seen: Dictionary) -> Dictionary:
	var seats: Array[String] = [opponent_deck, opponent_deck]
	seats[expansion_side] = deck
	var battle := Model.new(seed_value, map, "warden", "warden", seats[0], seats[1])
	var result: Dictionary = {"deck": deck, "map": map, "seed": seed_value, "expansion_side": expansion_side,
		"actions": 0, "winner": -1, "turn": 1, "new_cards_played": {}, "high_cost_plays": [], "error": ""}
	while battle.winner == -1 and result.actions < ACTION_CAP:
		var side: int = battle.active_side
		var action: Dictionary = AI.choose(battle)
		var card: Dictionary = {}
		var mana_before: int = battle.players[side].mana
		if action.type == "play": card = battle.definition(battle.hand_card(side, action.card_uid).get("card_id", ""))
		var applied: Dictionary = battle.apply_action(action)
		if not applied.ok:
			result.error = applied.message
			break
		result.actions += 1
		if card.get("set_id", "") != "warfront": continue
		var id: String = card.id
		result.new_cards_played[id] = int(result.new_cards_played.get(id, 0)) + 1
		seen[id] = int(seen.get(id, 0)) + 1
		if card.cost >= 7:
			result.high_cost_plays.append({"id": id, "cost": card.cost, "turn": battle.turn, "mana_before": mana_before})
	result.winner = battle.winner
	result.turn = battle.turn
	result.finish_reason = str(battle.log_lines.back())
	if result.error.is_empty() and battle.winner == -1: result.error = "action limit"
	var final_check: Dictionary = Snapshot.validate(Snapshot.capture(battle))
	if not final_check.ok: result.error = str(final_check)
	return result

func run() -> void:
	var report_path: String = "user://warfront-benchmark.json"
	var opponent_deck: String = "balanced"
	var tested_decks: Array = DECKS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg.begins_with("--opponent="): opponent_deck = arg.trim_prefix("--opponent=")
		if arg.begins_with("--deck="): tested_decks = [arg.trim_prefix("--deck=")]
	for selected: String in tested_decks + [opponent_deck]:
		if Model.DECKS.find(selected).id != selected:
			push_error("Unknown benchmark deck: " + selected)
			quit(1)
			return
	var report: Dictionary = {"version": "0.41.0-dev", "basis": "Production AI on both sides, standard mana and draw, equal wardens, mirrored decks, fixed seeds.",
		"baseline": opponent_deck, "matches": [], "by_deck": {}, "cards_played": {}, "total_actions": 0, "failures": 0}
	for deck: String in tested_decks:
		var totals: Dictionary = {"wins": 0, "losses": 0, "draws": 0}
		for map_index: int in range(MAPS.size()):
			for side: int in [0, 1]:
				var row: Dictionary = play_match(deck, opponent_deck, MAPS[map_index], 4107 + map_index * 79, side, report.cards_played)
				report.matches.append(row)
				report.total_actions += row.actions
				if not row.error.is_empty(): report.failures += 1
				elif row.winner == side: totals.wins += 1
				elif row.winner == 2: totals.draws += 1
				else: totals.losses += 1
				print("WARFRONT %s %s S%d | WINNER %d | %d ACTIONS | HIGH %d | %s" % [deck, row.map, side, row.winner, row.actions, row.high_cost_plays.size(), row.error])
				await process_frame
		report.by_deck[deck] = totals
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write benchmark to " + report_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("WARFRONT MATCHES %d | ACTIONS %d | NEW CARDS PLAYED %d | FAILURES %d" % [report.matches.size(), report.total_actions, report.cards_played.size(), report.failures])
	quit(0 if report.failures == 0 else 1)
