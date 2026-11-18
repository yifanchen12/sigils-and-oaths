extends RefCounted
## Campaign objectives. Escort delivery resolves immediately and its deadline is checked on the next blue turn.

const ESCORT_CARD: String = "shore_medic"
const ESCORT_NAME: String = "担架队"
const SENTRY_CARD: String = "archer"
const Cards = preload("res://data/cards.tres")

static func is_relay(value: Dictionary) -> bool:
	return value.get("mode", "") == "relay"

static func is_escort(value: Dictionary) -> bool:
	return value.get("mode", "") == "escort"

static func position(cell: Array) -> Vector2i:
	return Vector2i(int(cell[0]), int(cell[1]))

static func whole(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func validate_config(value: Variant, map: Dictionary) -> String:
	if not value is Dictionary: return "驻守目标必须是对象。"
	if value.is_empty(): return ""
	if value.has("mode") and not is_relay(value) and not is_escort(value): return "战役目标模式不存在。"
	if not whole(value.get("required"), 1, 20) or not whole(value.get("round_limit"), 1, 100) or value.required > value.round_limit: return "驻守次数或期限无效。"
	if not value.get("cells") is Array: return "战役目标缺少据点。"
	if is_relay(value):
		if value.cells.size() < 2 or value.cells.size() != int(value.required): return "接力点数量须与接应次数一致。"
	elif is_escort(value):
		if value.cells.size() != 1 or value.required != 1: return "护送必须有且仅有一个出口。"
	elif value.cells.size() != 2:
		return "驻守目标需要两个据点格。"
	var seen: Dictionary = {}
	for cell: Variant in value.cells:
		if not _map_cell(cell, map): return "据点坐标越界。"
		var key: Vector2i = position(cell)
		if seen.has(key) or map.rows[key.y][key.x] in ["w", "m"]: return "据点重叠或无法通行。"
		seen[key] = true
	if is_escort(value):
		if not _map_cell(value.get("escort_start"), map): return "担架队起点越界。"
		var start: Vector2i = position(value.escort_start)
		if seen.has(start) or map.spawns.has(start) or map.rows[start.y][start.x] in ["w", "m"]: return "担架队起点重叠或无法通行。"
		if value.has("sentry_start"):
			if not _map_cell(value.sentry_start, map): return "岗哨起点越界。"
			var sentry: Vector2i = position(value.sentry_start)
			if sentry == start or seen.has(sentry) or map.spawns.has(sentry) or map.rows[sentry.y][sentry.x] in ["w", "m"]: return "岗哨起点重叠或无法通行。"
			var card_id: Variant = value.get("sentry_card", SENTRY_CARD)
			if not card_id is String or Cards.find(card_id).get("type", "") != "unit": return "岗哨部队无效。"
		elif value.has("sentry_card"): return "岗哨部队缺少起点。"
	return ""

static func _map_cell(cell: Variant, map: Dictionary) -> bool:
	return cell is Array and cell.size() == 2 and whole(cell[0], 0, str(map.rows[0]).length() - 1) and whole(cell[1], 0, map.rows.size() - 1)

static func config(value: Dictionary) -> Dictionary:
	if value.is_empty(): return {}
	var cells: Array = []
	for cell: Array in value.cells: cells.append([int(cell[0]), int(cell[1])])
	var result: Dictionary = {"cells": cells, "required": int(value.required), "round_limit": int(value.round_limit)}
	if is_relay(value): result["mode"] = "relay"
	if is_escort(value):
		result["mode"] = "escort"
		result["escort_start"] = [int(value.escort_start[0]), int(value.escort_start[1])]
		if value.has("sentry_start"): result["sentry_start"] = [int(value.sentry_start[0]), int(value.sentry_start[1])]
		if value.has("sentry_card"): result["sentry_card"] = value.sentry_card
	return result

static func initial(value: Dictionary) -> Dictionary:
	var result: Dictionary = config(value)
	if not result.is_empty(): result.merge({"streak": 0, "last_check": 0})
	return result

static func check_turn(battle: RefCounted) -> void:
	var goal: Dictionary = battle.objective
	if goal.is_empty() or battle.winner != -1 or battle.active_side != 0 or battle.turn <= 1 or goal.last_check == battle.turn: return
	goal.last_check = battle.turn
	if is_escort(goal):
		if (battle.turn - 1) / 2 >= goal.round_limit:
			battle.winner = 1
			battle._record(result_text(goal, false))
		else:
			battle._record("护送时限还剩 %d 轮。" % (int(goal.round_limit) - (battle.turn - 1) / 2))
		return
	var relay: bool = is_relay(goal)
	var cells: Array = [goal.cells[int(goal.streak)]] if relay else goal.cells
	var occupied: bool = true
	for cell: Array in cells:
		var unit: Dictionary = battle.unit_at(Vector2i(int(cell[0]), int(cell[1])))
		if unit.is_empty() or unit.side != 0: occupied = false
	if occupied: goal.streak = int(goal.streak) + 1
	elif not relay: goal.streak = 0
	if goal.streak >= goal.required:
		battle.winner = 0
		battle._record(result_text(goal, true))
	elif (battle.turn - 1) / 2 >= goal.round_limit:
		battle.winner = 1
		battle._record(result_text(goal, false))
	elif relay:
		var next: Array = goal.cells[int(goal.streak)]
		battle._record("已接应 %d/%d 处 · 下一站 %s · 已过 %d/%d 轮。" % [goal.streak, goal.required, battle.cell_name(Vector2i(int(next[0]), int(next[1]))), (battle.turn - 1) / 2, goal.round_limit])
	else: battle._record("据点连续驻守 %d/%d · 已过 %d/%d 轮。" % [goal.streak, goal.required, (battle.turn - 1) / 2, goal.round_limit])

static func result_text(goal: Dictionary, won: bool, escort_lost: bool = false) -> String:
	if is_escort(goal):
		if escort_lost: return "担架队失去行动能力，本次护送失败。"
		return "担架队已抵达安全出口，本次护送完成。" if won else "护送时限已到，担架队未能抵达出口。"
	if is_relay(goal):
		return "所有接力点完成接应，撤离通道已经打通。" if won else "接应期限已到，未能打通撤离通道。"
	return "两处据点连续驻守达标，本次驻守任务完成。" if won else "驻守期限已到，未能稳住两处据点，本次驻守任务失败。"

static func validate_state(value: Variant, data: Dictionary, map: Dictionary) -> String:
	var problem: String = validate_config(value, map)
	if not problem.is_empty() or value.is_empty(): return problem
	if not whole(value.get("streak"), 0, int(value.required)) or not whole(value.get("last_check"), 0, int(data.turn)): return "驻守进度无效。"
	var last: int = int(value.last_check)
	if last != 0 and (last < 3 or last % 2 != 1): return "驻守结算回合无效。"
	if is_escort(value):
		if not whole(value.get("escort_id"), 1, int(data.next_id) - 1): return "担架队编号无效。"
	elif (last > 0 and value.streak > (last - 1) / 2) or (last == 0 and value.streak != 0): return "驻守次数早于结算回合。"
	if data.winner == -1:
		var expected: int = int(data.turn) if int(data.turn) % 2 == 1 else int(data.turn) - 1
		if last != (0 if expected == 1 else expected) or value.streak >= value.required or (data.turn - 1) / 2 >= value.round_limit: return "未结束战斗的驻守进度不一致。"
	return ""

static func objective_winner(value: Dictionary, data: Dictionary) -> int:
	if value.is_empty(): return -1
	if is_escort(value):
		var exit_cell: Vector2i = position(value.cells[0])
		for unit: Dictionary in data.units:
			if unit.id != value.escort_id: continue
			if position(unit.pos) == exit_cell: return 0
			return 1 if data.active_side == 0 and value.last_check == data.turn and (data.turn - 1) / 2 >= value.round_limit else -1
		return 1
	if data.active_side != 0 or value.last_check != data.turn: return -1
	if value.streak >= value.required:
		var cells: Array = [value.cells.back()] if is_relay(value) else value.cells
		for cell: Array in cells:
			var found: bool = false
			for unit: Dictionary in data.units:
				if unit.side == 0 and int(unit.pos[0]) == int(cell[0]) and int(unit.pos[1]) == int(cell[1]): found = true
			if not found: return -1
		return 0
	return 1 if (data.turn - 1) / 2 >= value.round_limit else -1
