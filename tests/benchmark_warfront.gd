extends SceneTree
## Mirrored skirmishes with ordinary decks, mana, and production AI for both seats.
const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const DECKS = ["reed_legion", "frost_engine", "lantern_convoy"]
const MAPS = ["greenwood", "rivergate", "ridgepass"]
const ACTION_CAP = 1000
var tracked_set: String = "warfront"
var profile_turns: bool = false
var commander_id: String = "warden"

func _initialize() -> void:
	call_deferred("run")

func play_match(deck: String, opponent_deck: String, map: String, seed_value: int, expansion_side: int, seen: Dictionary) -> Dictionary:
	var seats: Array[String] = [opponent_deck, opponent_deck]
	seats[expansion_side] = deck
	var battle := Model.new(seed_value, map, commander_id, commander_id, seats[0], seats[1])
	var result: Dictionary = {"deck": deck, "map": map, "seed": seed_value, "expansion_side": expansion_side,
		"actions": 0, "winner": -1, "turn": 1, "new_cards_played": {}, "high_cost_plays": [], "area_casts": [], "resolved_orders": [], "error": ""}
	var decision_time_total: int = 0
	var longest_decision: int = 0
	if profile_turns: result["turn_profile"] = []
	while battle.winner == -1 and result.actions < ACTION_CAP:
		var side: int = battle.active_side
		var start: int = Time.get_ticks_usec()
		var action: Dictionary = AI.choose(battle)
		var usec: int = Time.get_ticks_usec() - start
		decision_time_total += usec
		longest_decision = maxi(longest_decision, usec)
		var card: Dictionary = {}
		var mana_before: int = battle.players[side].mana
		if action.type == "play": card = battle.definition(battle.hand_card(side, action.card_uid).get("card_id", ""))
		var row_profile: Dictionary = {}
		if profile_turns:
			row_profile = {"turn": battle.turn, "side": side, "action": action.type, "card": card.get("id", ""),
				"counts_before": [battle.army_count(0), battle.army_count(1)], "mana_before": mana_before}
		if card.get("effect", "") == "formation" and card.get("target_side", "") == "enemy" and int(card.get("damage", 0)) > 0:
			var victims: Array = battle.Formation.recipients(battle, card, action.target, side).filter(func(unit: Dictionary) -> bool: return unit.side != side)
			result.area_casts.append({"id": card.id, "side": side, "turn": battle.turn,
				"units": victims.size()})
		var applied: Dictionary = battle.apply_action(action)
		if not applied.ok:
			result.error = applied.message
			break
		result.actions += 1
		if not battle.last_order_event.is_empty():
			result.resolved_orders.append({"id": battle.last_order_event.card_id, "side": battle.active_side, "turn": battle.turn})
		if profile_turns:
			row_profile["counts_after"] = [battle.army_count(0), battle.army_count(1)]
			row_profile["mana_after"] = battle.players[side].mana
			row_profile["leader_hp"] = [battle.commander(0).get("hp", 0), battle.commander(1).get("hp", 0)]
			result.turn_profile.append(row_profile)
		if card.get("set_id", "") != tracked_set: continue
		var id: String = card.id
		result.new_cards_played[id] = int(result.new_cards_played.get(id, 0)) + 1
		seen[id] = int(seen.get(id, 0)) + 1
		if card.cost >= 7:
			result.high_cost_plays.append({"id": id, "cost": card.cost, "turn": battle.turn, "mana_before": mana_before})
	result.winner = battle.winner
	result.turn = battle.turn
	result.mean_decision_ms = float(decision_time_total) / (maxi(1, result.actions) * 1000)
	result.max_decision_ms = longest_decision / 1000.0
	result.finish_reason = str(battle.log_lines.back())
	if result.error.is_empty() and battle.winner == -1: result.error = "action limit"
	var final_check: Dictionary = Snapshot.validate(Snapshot.capture(battle))
	if not final_check.ok: result.error = str(final_check)
	return result

func run() -> void:
	var report_path: String = "user://warfront-benchmark.json"
	var opponent_deck: String = "balanced"
	var tested_decks: Array = DECKS
	var base_seed: int = 4107
	var repetitions: int = 1
	var maps: PackedStringArray = PackedStringArray(MAPS)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg.begins_with("--opponent="): opponent_deck = arg.trim_prefix("--opponent=")
		if arg.begins_with("--deck="): tested_decks = [arg.trim_prefix("--deck=")]
		if arg.begins_with("--seed="): base_seed = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--repetitions="): repetitions = maxi(1, int(arg.trim_prefix("--repetitions=")))
		if arg.begins_with("--set="): tracked_set = arg.trim_prefix("--set=")
		if arg == "--profile": profile_turns = true
		if arg.begins_with("--maps="): maps = arg.trim_prefix("--maps=").split(",", false)
		if arg.begins_with("--hero="): commander_id = arg.trim_prefix("--hero=")
	if maps.is_empty() or Model.HEROES.find(commander_id).id != commander_id:
		push_error("At least one map and a known commander are required.")
		quit(1)
		return
	for map: String in maps:
		if Model.MAPS.find(map).id != map:
			push_error("Unknown benchmark map: " + map)
			quit(1)
			return
	for selected: String in tested_decks + [opponent_deck]:
		if Model.DECKS.find(selected).id != selected:
			push_error("Unknown benchmark deck: " + selected)
			quit(1)
			return
	var report: Dictionary = {"version": ProjectSettings.get_setting("application/config/version"), "basis": "Production AI on both sides, standard mana and draw, same commander, mirrored seats, fixed seeds.",
		"baseline": opponent_deck, "commander": commander_id, "matches": [], "by_deck": {}, "cards_played": {}, "total_actions": 0, "failures": 0}
	for deck: String in tested_decks:
		var totals: Dictionary = {"wins": 0, "losses": 0, "draws": 0}
		for layout_index: int in range(repetitions * maps.size()):
			var map: String = maps[layout_index % maps.size()]
			for side: int in [0, 1]:
				var row: Dictionary = play_match(deck, opponent_deck, map, base_seed + layout_index * 79, side, report.cards_played)
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
