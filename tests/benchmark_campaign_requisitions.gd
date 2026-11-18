extends SceneTree
## Paired ordinary scenario starts with the default hand and each actual swap.

const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const AI = preload("res://scripts/opponent.gd")
const HarborPilot = preload("res://tests/fixtures/harbor_court_pilot.gd")
const FocusPilot = preload("res://tests/fixtures/bridge_focus_pilot.gd")
const ChannelPilot = preload("res://tests/fixtures/channel_push_pilot.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const ACTION_CAP: int = 1000

func _initialize() -> void: call_deferred("run")

func pilot_for(scenario_id: String) -> Script:
	match scenario_id:
		"c04_pump", "c06_court": return HarborPilot
		"c05_nursery", "c12_joint_depot", "c12_split_depot", "c12_hold_depot": return FocusPilot
		"c14_upstream_channel", "c14_tower_channel": return ChannelPilot
	return AI

func run_match(scenario_id: String, setup: Dictionary, choice: String, armory: Dictionary = {}) -> Dictionary:
	var result: Dictionary = Session.create_encounter(setup, choice, armory)
	var row: Dictionary = {"scenario": scenario_id, "card": choice, "seed": setup.seed, "winner": -1, "actions": 0, "turn": 1,
		"play_turn": 0, "play_mana": 0, "error": ""}
	if not result.ok:
		row.error = result.message
		return row
	var battle: Battle = result.battle
	var gear_uids: Dictionary = {}
	var gear_seen: Dictionary = {}
	var gear_played: Dictionary = {}
	if not armory.is_empty():
		var pile: Array = battle.players[0].deck
		for slot: Dictionary in Campaign.Armory.SLOTS:
			if armory.has(slot.id):
				var instance: Dictionary = pile[-int(slot.draw)]
				gear_uids[instance.uid] = instance.card_id
	var pilot: Script = pilot_for(scenario_id)
	while battle.winner == -1 and row.actions < ACTION_CAP:
		if not gear_uids.is_empty():
			for instance: Dictionary in battle.players[0].hand:
				if gear_uids.has(instance.uid): gear_seen[instance.card_id] = true
		var side: int = battle.active_side
		var action: Dictionary = (AI if side == 1 else pilot).choose(battle)
		var played: String = battle.hand_card(side, action.card_uid).get("card_id", "") if action.type == "play" else ""
		var before_mana: int = int(battle.players[side].mana)
		result = battle.apply_action(action)
		if not result.ok:
			row.error = result.message
			break
		if side == 0 and not choice.is_empty() and played == choice and row.play_turn == 0:
			row.play_turn = battle.turn
			row.play_mana = before_mana
		if side == 0 and action.type == "play" and gear_uids.has(action.card_uid):
			gear_played[played] = int(gear_played.get(played, 0)) + 1
		row.actions += 1
	row.winner = battle.winner
	row.turn = battle.turn
	row.finish = battle.log_lines.back()
	if not armory.is_empty():
		row["armory"] = armory
		row["armory_seen"] = gear_seen.keys()
		row["armory_plays"] = gear_played
	if row.error.is_empty() and battle.winner == -1: row.error = "action limit"
	var validity: Dictionary = Snapshot.validate(Snapshot.capture(battle))
	if not validity.ok: row.error = validity.message
	return row

func run() -> void:
	var shard: int = 0
	var shards: int = 1
	var destination: String = "res://.tools/v048-requisition-diagnostic.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shard="): shard = int(arg.trim_prefix("--shard="))
		if arg.begins_with("--shards="): shards = int(arg.trim_prefix("--shards="))
		if arg.begins_with("--report="): destination = arg.trim_prefix("--report=")
	if shards <= 0 or shard < 0 or shard >= shards:
		push_error("Invalid diagnostic shard")
		quit(1)
		return
	var catalog = Campaign.new()
	var configured: Array = catalog.index.scenarios.keys()
	configured.sort()
	var select_index: int = 0
	var errors: int = 0
	var rows: Array[Dictionary] = []
	for id: String in configured:
		var setup: Dictionary = catalog.index.scenarios[id]
		if not setup.has("requisition"): continue
		var in_shard: bool = select_index % shards == shard
		select_index += 1
		if not in_shard: continue
		for choice: String in [""] + setup.requisition.offers:
			var result: Dictionary = run_match(id, setup, choice)
			rows.append(result)
			if not result.error.is_empty(): errors += 1
			print("%s | %s | winner %d | %d actions | play turn %d | %s" % [id, choice if not choice.is_empty() else "original", result.winner, result.actions, result.play_turn, result.error])
			await process_frame
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		push_error("Could not write diagnostic")
		quit(2)
		return
	file.store_string(JSON.stringify({"matches": rows, "failures": errors}, "  ", true, true))
	file.close()
	print("REQUISITION MATCHES %d | FAILURES %d" % [rows.size(), errors])
	quit(0 if errors == 0 else 1)
