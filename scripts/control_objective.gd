extends RefCounted
## Two control cells, checked once per new player turn. Plain data only.

static func whole(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func validate_config(value: Variant, map: Dictionary) -> String:
	if not value is Dictionary: return "驻守目标必须是对象。"
	if value.is_empty(): return ""
	if not whole(value.get("required"), 1, 20) or not whole(value.get("round_limit"), 1, 100) or value.required > value.round_limit: return "驻守次数或期限无效。"
	if not value.get("cells") is Array or value.cells.size() != 2: return "驻守目标需要两个据点格。"
	var seen: Dictionary = {}
	for cell: Variant in value.cells:
		if not cell is Array or cell.size() != 2 or not whole(cell[0], 0, str(map.rows[0]).length() - 1) or not whole(cell[1], 0, map.rows.size() - 1): return "据点坐标越界。"
		var key := Vector2i(int(cell[0]), int(cell[1]))
		if seen.has(key) or map.rows[key.y][key.x] in ["w", "m"]: return "据点重叠或无法通行。"
		seen[key] = true
	return ""

static func config(value: Dictionary) -> Dictionary:
	if value.is_empty(): return {}
	var cells: Array = []
	for cell: Array in value.cells: cells.append([int(cell[0]), int(cell[1])])
	return {"cells": cells, "required": int(value.required), "round_limit": int(value.round_limit)}

static func initial(value: Dictionary) -> Dictionary:
	var result: Dictionary = config(value)
	if not result.is_empty(): result.merge({"streak": 0, "last_check": 0})
	return result

static func check_turn(battle: RefCounted) -> void:
	var goal: Dictionary = battle.objective
	if goal.is_empty() or battle.winner != -1 or battle.active_side != 0 or battle.turn <= 1 or goal.last_check == battle.turn: return
	goal.last_check = battle.turn
	var occupied: bool = true
	for cell: Array in goal.cells:
		var unit: Dictionary = battle.unit_at(Vector2i(int(cell[0]), int(cell[1])))
		if unit.is_empty() or unit.side != 0: occupied = false
	goal.streak = int(goal.streak) + 1 if occupied else 0
	if goal.streak >= goal.required:
		battle.winner = 0
		battle._record("两处据点连续驻守达标，本次驻守任务完成。")
	elif (battle.turn - 1) / 2 >= goal.round_limit:
		battle.winner = 1
		battle._record("驻守期限已到，未能稳住两处据点，本次驻守任务失败。")
	else: battle._record("据点连续驻守 %d/%d · 已过 %d/%d 轮。" % [goal.streak, goal.required, (battle.turn - 1) / 2, goal.round_limit])

static func validate_state(value: Variant, data: Dictionary, map: Dictionary) -> String:
	var problem: String = validate_config(value, map)
	if not problem.is_empty() or value.is_empty(): return problem
	if not whole(value.get("streak"), 0, int(value.required)) or not whole(value.get("last_check"), 0, int(data.turn)): return "驻守进度无效。"
	var last: int = int(value.last_check)
	if last != 0 and (last < 3 or last % 2 != 1): return "驻守结算回合无效。"
	if (last > 0 and value.streak > (last - 1) / 2) or (last == 0 and value.streak != 0): return "驻守次数早于结算回合。"
	if data.winner == -1:
		var expected: int = int(data.turn) if int(data.turn) % 2 == 1 else int(data.turn) - 1
		if last != (0 if expected == 1 else expected) or value.streak >= value.required or (data.turn - 1) / 2 >= value.round_limit: return "未结束战斗的驻守进度不一致。"
	return ""

static func objective_winner(value: Dictionary, data: Dictionary) -> int:
	if value.is_empty() or data.active_side != 0 or value.last_check != data.turn: return -1
	if value.streak >= value.required:
		for cell: Array in value.cells:
			var found: bool = false
			for unit: Dictionary in data.units:
				if unit.side == 0 and int(unit.pos[0]) == int(cell[0]) and int(unit.pos[1]) == int(cell[1]): found = true
			if not found: return -1
		return 0
	return 1 if (data.turn - 1) / 2 >= value.round_limit else -1
