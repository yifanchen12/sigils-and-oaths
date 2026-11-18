extends RefCounted
## One source for encounter rules, briefing copy and saved objective checks.

const Model = preload("res://scripts/battle.gd")
const Objective = preload("res://scripts/control_objective.gd")
const STANDARD: String = "standard"
const STORY: String = "story"
const STARTING_MANA: int = 2
const COMMANDER_SHIELD: int = 2
const EXTRA_ROUNDS: int = 3

static func is_valid(value: Variant) -> bool:
	return value is String and value in [STANDARD, STORY]

static func control_for(setup: Dictionary, difficulty: String) -> Dictionary:
	var original: Dictionary = setup.get("control", {})
	if difficulty == STANDARD: return original
	if setup.has("story_control"): return setup.story_control
	var goal: Dictionary = original.duplicate(true)
	if Objective.has_deadline(goal): goal.round_limit = mini(100, int(goal.round_limit) + EXTRA_ROUNDS)
	return goal

static func support(battle: Battle) -> void:
	var player: Dictionary = battle.players[0]
	player.mana = mini(10, int(player.mana) + STARTING_MANA)
	player.max_mana = mini(10, int(player.max_mana) + STARTING_MANA)
	var commander: Dictionary = battle.commander(0)
	commander.shield = mini(5, int(commander.shield) + COMMANDER_SHIELD)

static func support_text() -> String:
	return "剧情难度 · 开局法力和法力上限各多 %d，指挥官多 %d 护盾（上限 5）。限时关卡多 %d 轮。" % [STARTING_MANA, COMMANDER_SHIELD, EXTRA_ROUNDS]

static func brief_for(setup: Dictionary, difficulty: String) -> String:
	if difficulty == STORY and setup.has("story_brief"): return setup.story_brief
	return setup.get("brief", "")

static func objective_for(setup: Dictionary, difficulty: String) -> String:
	var goal: Dictionary = control_for(setup, difficulty)
	if difficulty == STANDARD or goal.is_empty(): return setup.get("objective", "")
	var map: Dictionary = Model.MAPS.find(setup.map)
	var cells := PackedStringArray()
	for point: Array in goal.cells:
		var cell: Vector2i = Objective.position(point)
		cells.append(String.chr(65 + cell.x) + str(map.rows.size() - cell.y))
	var objective: String
	if Objective.is_escort(goal):
		objective = "将担架队送到 %s。抵达立即获胜，担架队倒下则败。" % cells[0]
	elif Objective.is_relay(goal):
		objective = "依次接应 %s。己方行动回合开始时，每次确认当前一处，已经接应的部队可以离开。" % " → ".join(cells)
	else:
		var checks: String = "确认一次即胜" if int(goal.required) == 1 else "连续确认 %d 次即胜" % int(goal.required)
		objective = "守住 %s。己方行动回合开始时两格均有友军，%s。" % ["、".join(cells), checks]
	if Objective.has_deadline(goal): objective += "在 %d 个完整轮次内完成。" % int(goal.round_limit)
	else: objective += "驻守无轮次期限。"
	return objective + "击退敌指挥官也胜，己方指挥官倒下则败。"
