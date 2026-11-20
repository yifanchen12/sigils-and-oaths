extends RefCounted
## Ordinary attacks by troops already on the board, before any other action changes the formation.

const CAPTION := "敌军射程 V"
const KEY := "双齿 原地可攻　单齿 移动后可攻"
const HELP := "双齿实线表示原地可攻，单齿虚线表示移动后可攻。指向敌军可单看该队。按现有阵形和敌军行动时的天气推演；出牌、技能、援护、伏设和军令另行结算。"

static func legend(field: Battle) -> String:
	if field != null and field.active_side == 0 and field.weather_remaining == 1 and field.weather != "clear":
		return KEY + "　敌方行动时转晴"
	return KEY

static func project(field: Battle, side: int) -> Dictionary:
	var cells := {}
	if field == null or field.winner != -1: return cells
	var next_turn := field.active_side != side
	var sky := "clear" if next_turn and field.weather_remaining == 1 else field.weather
	var allied_cells := {}
	for unit: Dictionary in field.units:
		if unit.side == side: allied_cells[unit.pos] = true
	for unit: Dictionary in field.units:
		if unit.side != side or field.is_escort_unit(unit.id): continue
		var actor := unit.duplicate()
		if next_turn: Battle.ready_unit_for_turn(actor)
		if actor.attacked or actor.summoning: continue
		var origins: Array[Vector2i] = [unit.pos]
		origins.append_array(field.movement_cells(actor, {}, sky))
		for origin: Vector2i in origins:
			actor.pos = origin
			var reach := field.attack_range(actor, sky)
			for dx: int in range(-reach, reach + 1):
				var dy_limit := reach - absi(dx)
				for dy: int in range(-dy_limit, dy_limit + 1):
					var cell := origin + Vector2i(dx, dy)
					if cell == origin or allied_cells.has(cell) or not field.passable(cell): continue
					if not cells.has(cell): cells[cell] = {"direct": {}, "advance": {}}
					var entry: Dictionary = cells[cell]
					if origin == unit.pos:
						entry.direct[unit.id] = origin
					elif not entry.direct.has(unit.id) and not entry.advance.has(unit.id):
						entry.advance[unit.id] = origin
	return cells

static func level(cells: Dictionary, cell: Vector2i, focus_id: int) -> int:
	if not cells.has(cell): return 0
	var entry: Dictionary = cells[cell]
	if focus_id == -1:
		return 1 if entry.direct.is_empty() else 2
	if entry.direct.has(focus_id): return 2
	return 1 if entry.advance.has(focus_id) else 0

static func describe(field: Battle, cells: Dictionary, cell: Vector2i) -> String:
	if field == null or not field.inside(cell): return ""
	var unit := field.unit_at(cell)
	if not unit.is_empty() and unit.side == 1:
		return "只看%s · %s　移开查看全军" % [unit.name, field.cell_name(cell)]
	if not field.passable(cell): return field.cell_name(cell) + " · 无法驻军"
	if not cells.has(cell): return field.cell_name(cell) + " · 现有敌军普攻够不到这里"
	var groups := PackedStringArray()
	for key: String in ["direct", "advance"]:
		var origins: Dictionary = cells[cell][key]
		if origins.is_empty(): continue
		var labels := PackedStringArray()
		for id: int in origins:
			var attacker := field.get_unit(id)
			labels.append("%s（%s）" % [attacker.name, field.cell_name(origins[id])])
		groups.append(("原地 " if key == "direct" else "移至攻击格 ") + "、".join(labels))
	return field.cell_name(cell) + "　" + " ／ ".join(groups)
