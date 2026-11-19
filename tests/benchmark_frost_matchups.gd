extends SceneTree
## Runs against source or an exported PCK. Swap seats with the same shuffle and commander.

const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const FROST := "frost_engine"
const EDICT := "glassroad_edict"
const MAPS := ["greenwood", "rivergate", "harbor", "ridgepass", "sunspire", "citadel"]
const RIVALS := [EDICT, "balanced", "reed_legion", "bellfoundry_column"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5 or args[0] not in ["prior", "calibration", "validation"] or not args[1].is_valid_int():
		push_error("Pass cohort, base seed, commander, stock or Frost recipe JSON path, and output JSON path.")
		quit(1)
		return
	if Model.HEROES.find(args[2]).get("id") != args[2]:
		push_error("Unknown commander.")
		quit(1)
		return
	var preset := Model.DECKS.find(FROST)
	if args[3] != "stock":
		var recipe: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[3]))
		if not recipe is Dictionary or not Model.DECKS.validate_counts(recipe, Model.CATALOG.cards).is_empty():
			push_error("Invalid Frost deck recipe.")
			quit(1)
			return
		preset.cards = Model.DECKS.canonical_counts(recipe, Model.CATALOG.cards)
	var games: Array[Dictionary] = []
	var cohort := args[0]
	var map_count := 3 if cohort == "calibration" else MAPS.size()
	var rival_count := 1 if cohort == "prior" else (3 if cohort == "calibration" else RIVALS.size())
	for index: int in range(map_count):
		for rival_index: int in range(rival_count):
			var seed_value := int(args[1]) if cohort == "prior" else int(args[1]) + index * 103 + rival_index * 37
			for seat: int in [0, 1]:
				var game := play_game(seed_value, MAPS[index], RIVALS[rival_index], seat, args[2])
				if not game.get("error", "").is_empty():
					push_error(str(game))
					quit(2)
					return
				games.append(game)
	var file := FileAccess.open(args[4], FileAccess.WRITE)
	if file == null:
		push_error("Could not open output path.")
		quit(2)
		return
	file.store_string(JSON.stringify({"cohort":cohort, "base_seed":int(args[1]), "hero":args[2],
		"version":ProjectSettings.get_setting("application/config/version"), "recipe":preset.cards,
		"rules":Snapshot.rules_signature(), "games":games}, "\t", true) + "\n")
	file.close()
	var wins := games.filter(func(g: Dictionary) -> bool: return g.winner == g.frost_seat).size()
	print("FROST ", cohort, " ", args[1], " ", args[2], " | games ", games.size(), " | Frost wins ", wins)
	quit()

func play_game(seed_value: int, map_id: String, rival: String, seat: int, hero: String) -> Dictionary:
	var game := Model.new(seed_value, map_id, hero, hero, FROST if seat == 0 else rival, rival if seat == 0 else FROST)
	var casts: Array[Dictionary] = []
	var played: Dictionary = {}
	var finish := ""
	var count := 0
	while game.winner == -1 and count < 1000:
		var side := game.active_side
		var action := AI.choose(game)
		var label: String = action.type
		var hit: Dictionary = {}
		var victims: Array[int] = []
		if action.type == "play":
			var card := game.card_for_play(game.definition(game.hand_card(side, action.card_uid).card_id), side)
			label = card.id
			if side == seat: played[label] = int(played.get(label, 0)) + 1
			var effect_type: String = card.get("effect", "")
			var effect: Dictionary = game.choice_mode(card, action.target, side) if effect_type == "choice" else card
			if effect_type in ["formation", "choice"] and effect.get("target_side") == "enemy" and int(effect.get("damage", 0)) > 0:
				for change: Dictionary in game.Formation.changes(game, effect, action.target, side):
					if not change.friendly: victims.append(change.unit_id)
				hit = {"turn":game.turn, "frost_cast":side == seat, "card":label, "victims":victims.size(), "removed":0}
		if not game.apply_action(action).ok: return {"error":"invalid action", "action":action}
		if not hit.is_empty():
			for id: int in victims:
				if game.get_unit(id).is_empty(): hit.removed += 1
			casts.append(hit)
		count += 1
		if action.type == "end_turn" and game.turn % 5 == 0 and not Snapshot.validate(Snapshot.capture(game)).ok:
			return {"error":"invalid midgame snapshot", "turn":game.turn}
		if game.winner != -1: finish = ("frost/" if side == seat else "rival/") + label
	if game.winner == -1 or not Snapshot.validate(Snapshot.capture(game)).ok: return {"error":"incomplete or invalid final state"}
	return {"seed":seed_value, "map":map_id, "rival":rival, "frost_seat":seat, "winner":game.winner,
		"turn":game.turn, "actions":count, "finisher":finish, "frost_plays":played, "casts":casts}
