extends SceneTree
## A diagnostic, not a claim that heuristic-AI win rates equal human balance.

const BattleModel = preload("res://scripts/battle.gd")
const EnemyAI = preload("res://scripts/opponent.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var reports: Array[Dictionary] = []
	var totals: Dictionary = {}
	var blue_wins: int = 0
	for hero: Dictionary in BattleModel.HEROES.heroes:
		totals[hero.id] = {"games": 0, "wins": 0, "hero_skills": 0, "weather_cards": 0}
	var pairs: Array = [["warden", "pyromancer"], ["pyromancer", "grove"], ["grove", "warden"]]
	for map: Dictionary in BattleModel.MAPS.available():
		for pair: Array in pairs:
			for match_seed: int in [307, 619]:
				for reverse_order: bool in [false, true]:
					var blue: String = pair[1] if reverse_order else pair[0]
					var red: String = pair[0] if reverse_order else pair[1]
					var game: Battle = BattleModel.new(match_seed, map.id, blue, red)
					var actions: int = 0
					var skills: Array[int] = [0, 0]
					var weather: Array[int] = [0, 0]
					var final_action: String = ""
					while game.winner == -1 and actions < 1200:
						var side: int = game.active_side
						var action: Dictionary = EnemyAI.choose(game)
						if action.type == "hero": skills[side] += 1
						if action.type == "play":
							var instance: Dictionary = game.hand_card(side, action.card_uid)
							if game.definition(instance.card_id).type == "environment": weather[side] += 1
						var result: Dictionary = game.apply_action(action)
						if not result.ok:
							push_error("Illegal benchmark action: " + result.message)
							quit(1)
							return
						final_action = action.type
						actions += 1
					if game.winner == -1:
						push_error("Benchmark game did not terminate")
						quit(1)
						return
					if game.winner == 0: blue_wins += 1
					for side: int in range(2):
						var key: String = blue if side == 0 else red
						totals[key].games += 1
						if game.winner == side: totals[key].wins += 1
						totals[key].hero_skills += skills[side]
						totals[key].weather_cards += weather[side]
					reports.append({"map": map.id, "seed": match_seed, "blue": blue, "red": red, "winner": game.winner,
						"turn": game.turn, "actions": actions, "skills": skills, "weather": weather, "final_action": final_action})
	var report: Dictionary = {"note": "Heuristic AI diagnostic; 6 large maps, local casting, positioning and fatigue-aware AI, all hero pairings, two fixed seeds and mirrored sides.",
		"matches": reports.size(), "first_player_wins": blue_wins, "heroes": totals, "games": reports}
	var file: FileAccess = FileAccess.open("res://docs/balance-v08-positioning.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot save balance report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	print("BALANCE MATCHES: ", reports.size(), " | FIRST PLAYER WINS: ", blue_wins)
	for hero_id: String in totals:
		print(hero_id, ": ", totals[hero_id])
	quit(0)
