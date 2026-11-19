extends "res://tests/benchmark_moorings.gd"
## Matched-seat comparison of Twin-Tide Orders. Each process changes only its in-memory preset.

const EDICT := "glassroad_edict"
const OLD_SAVE := "res://tests/fixtures/v055-active-edict.json"
const CALIBRATION: Array[String] = ["balanced", "assault", "frost_engine", "bellfoundry_column", "glassroad_reserve", "glassroad_ambush"]
const HOLDOUT: Array[String] = ["balanced", "frost_engine", "glassroad_reserve", "glassroad_ambush", "chalkline_vanguard", "ember_quarter"]
const ORIGINAL_MAPS: Array[String] = ["greenwood", "rivergate", "harbor"]
const EXTRA_MAPS: Array[String] = ["ridgepass", "sunspire", "citadel"]

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4 or args[0] not in ["calibration", "holdout"] or not args[1].is_valid_int():
		push_error("Pass calibration|holdout, a seed, current|v055|a recipe JSON path, and an output path.")
		quit(1)
		return
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	Model.DECKS.find("frost_engine").merge(Snapshot.FROST_V056, true)
	var preset := Model.DECKS.find(EDICT)
	if args[2] == "v055":
		preset.cards = Model.DECKS.canonical_counts(old.snapshot.players[0].deck_counts, Model.CATALOG.cards)
		preset.description = Snapshot.EDICT_V055.description
	elif args[2] != "current":
		var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
		if not recipe is Dictionary or not Model.DECKS.validate_counts(recipe, Model.CATALOG.cards).is_empty():
			push_error("Invalid experimental deck.")
			quit(1)
			return
		preset.cards = Model.DECKS.canonical_counts(recipe, Model.CATALOG.cards)
	var signature := Snapshot.rules_signature()
	if args[2] == "v055" and signature != old.snapshot.rules:
		push_error("The reconstructed balance controls differ from the released 0.55 rules.")
		quit(1)
		return
	var opponents := CALIBRATION if args[0] == "calibration" else HOLDOUT
	var maps: Array[String] = ORIGINAL_MAPS.duplicate()
	if args[0] == "holdout": maps.append_array(EXTRA_MAPS)
	var matches: Array[Dictionary] = []
	var wins := 0
	for map_id: String in maps:
		for other: String in opponents:
			for seat: int in [0, 1]:
				var blue := EDICT if seat == 0 else other
				var red := other if seat == 0 else EDICT
				var leader_hp: int = Model.HEROES.find("warden").hp
				var trace := {"enemy_hp": leader_hp, "enemy_troops": 0,
					"plays": {}, "leader_damage": {}, "troop_losses": {}, "finisher": ""}
				var watch := func(game: Battle, actor: int, action: Dictionary, card: Dictionary) -> void:
					observe_edict(trace, game, seat, actor, action, card)
				var result := play_match(int(args[1]), map_id, blue, red, "glassroad", watch, 1)
				if not str(result.error).is_empty() or int(result.winner) not in [0,1,2]:
					push_error("Incomplete game on %s against %s: %s" % [map_id, other, result.error])
					quit(2)
					return
				if int(result.winner) == seat: wins += 1
				matches.append({"map": map_id, "opponent": other, "seat": seat, "winner": result.winner, "turn": result.turn,
					"actions": result.actions, "edict_plays": trace.plays, "edict_leader_damage": trace.leader_damage,
					"edict_troop_losses_inflicted": trace.troop_losses, "finisher": trace.finisher})
	var file := FileAccess.open(args[3], FileAccess.WRITE)
	if file == null:
		push_error("Could not create balance report")
		quit(2)
		return
	file.store_string(JSON.stringify({"cohort": args[0], "seed": int(args[1]), "recipe": preset.cards,
		"rules": signature, "wins": wins, "games": matches}, "\t", true) + "\n")
	file.close()
	print("EDICT ", args[0], " seed ", args[1], " | wins ", wins, "/", matches.size())
	quit(0)

func observe_edict(trace: Dictionary, game: Battle, seat: int, actor: int, action: Dictionary, card: Dictionary) -> void:
	var foe: Dictionary = game.commander(1 - seat)
	var hp: int = int(foe.get("hp", 0))
	var count := game.army_count(1 - seat)
	var source: String = card.id if action.type == "play" else action.type
	if actor == seat:
		if action.type == "play": trace.plays[source] = int(trace.plays.get(source, 0)) + 1
		if hp < int(trace.enemy_hp):
			trace.leader_damage[source] = int(trace.leader_damage.get(source, 0)) + int(trace.enemy_hp) - hp
		if count < int(trace.enemy_troops):
			trace.troop_losses[source] = int(trace.troop_losses.get(source, 0)) + int(trace.enemy_troops) - count
	if game.winner != -1: trace.finisher = ("edict/" if actor == seat else "opponent/") + source
	trace.enemy_hp = hp
	trace.enemy_troops = count
