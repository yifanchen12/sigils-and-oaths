extends SceneTree
## Diagnostic matchups at declared seeds, not a claim of human balance.
const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var games: Array[Dictionary] = []
	for map_id: String in ["greenwood", "rivergate", "sunspire"]:
		for opponent: String in ["balanced", "assault", "bastion", "ambush"]:
			for expansion_side: int in [0, 1]:
				if opponent == "ambush" and expansion_side == 1: continue # same mirror opening
				var seed_value: int = 2901
				var b := Model.new(seed_value, map_id, "warden", "warden", "ambush" if expansion_side == 0 else opponent, opponent if expansion_side == 0 else "ambush", 90)
				var trace: Array[Dictionary] = []
				var plays: Dictionary = {}; var triggers: Dictionary = {}; var invalid: String = ""
				while b.winner == -1 and trace.size() < 1000:
					var side: int = b.active_side
					var action: Dictionary = AI.choose(b)
					if action.type == "play":
						var id: String = b.hand_card(side, action.card_uid).card_id
						if id in Snapshot.EXPANSION_CARDS: plays[id] = int(plays.get(id, 0)) + 1
					b.advance_clock(0.35)
					var result: Dictionary = b.apply_action(action)
					if not result.ok: invalid = result.message; failures += 1; break
					for event: Dictionary in b.last_trap_events:
						if event.reason == "触发": triggers[event.name] = int(triggers.get(event.name, 0)) + 1
					var portable: Dictionary = action.duplicate(true)
					if portable.get("target") is Vector2i: portable.target = [portable.target.x, portable.target.y]
					trace.append({"side": side, "elapsed": 0.35, "turn_after": b.turn, "action": portable})
					if action.type == "end_turn" and not Snapshot.validate(Snapshot.capture(b)).ok: invalid = "turn-end snapshot/card conservation"; failures += 1; break
				if b.winner == -1: failures += 1
				games.append({"map": map_id, "seed": seed_value, "expansion_side": expansion_side, "opponent": opponent, "winner": b.winner, "turn": b.turn, "actions": trace.size(), "plays": plays, "triggers": triggers, "invalid": invalid, "trace": trace, "final": Snapshot.capture(b)})
				print("EXPANSION %s %s SIDE%d | WINNER%d | TURN%d | ACTIONS%d | PLAYS%s | TRIGGERS%s" % [map_id, opponent, expansion_side, b.winner, b.turn, trace.size(), str(plays), str(triggers)])
				await process_frame
	var file := FileAccess.open("res://.tools/expansion-matchups-v029.json", FileAccess.WRITE)
	if file == null: push_error("cannot write expansion diagnostic"); quit(1); return
	file.store_string(JSON.stringify({"version": 1, "rules": Snapshot.rules_signature(), "note": "21 distinct declared AI openings: seed 2901, three maps, both seats against three old decks, plus one mirror per map. Fixed 0.35-second simulated actions. Not human balance evidence.", "games": games, "failures": failures}, "\t", true, true)); file.close()
	print("EXPANSION MATCHUPS: %d | INVALID_OR_CAPPED: %d" % [games.size(), failures])
	quit(0 if failures == 0 else 1)
