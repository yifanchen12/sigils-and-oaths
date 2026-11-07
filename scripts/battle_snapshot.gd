extends RefCounted
## Plain-data snapshots. No object deserialization, rendering or turn-start effects.

const Model = preload("res://scripts/battle.gd")
const VERSION: int = 3
const EXPANSION_CARDS: Array[String] = ["shatter_bolt", "rally_heal", "cleanse_root", "reveal_traps", "seedwood", "anchor_snare", "ember_mine", "oath_ward"]
const SCALARS: Array[String] = ["active_side", "turn", "winner", "next_id", "match_seed", "deck_size", "weather", "weather_remaining", "turn_time_limit", "time_remaining"]
const PLAYER_FIELDS: Array[String] = ["hero_id", "deck_id", "mana", "max_mana", "fatigue", "skill_cooldown", "spell_boost_used", "card_total"]
const UNIT_INTS: Array[String] = ["id", "side", "hp", "max_hp", "atk", "defense", "move", "range", "shield", "last_move_distance", "rooted_turns"]
const UNIT_FLAGS: Array[String] = ["moved", "attacked", "summoning", "skill_used", "guarding"]
const UNIT_TEXT: Array[String] = ["name", "kind", "short"]

static func rules_signature() -> String:
	return JSON.stringify([Model.CATALOG.cards, Model.HEROES.heroes, Model.DECKS.decks, Model.MAPS.maps, Model.TERRAIN, Model.WEATHER, Model.ADVANTAGE]).sha256_text()

static func maps_before_towergate() -> Array[Dictionary]:
	var maps: Array[Dictionary] = []
	for map: Dictionary in Model.MAPS.maps:
		if not map.get("campaign_only", false): maps.append(map)
	return maps

static func pre_towergate_signature() -> String:
	# A chapter-only map must not invalidate a running battle on an unchanged
	# original map. This is the exact 0.33 catalog, not a wildcard signature.
	return JSON.stringify([Model.CATALOG.cards, Model.HEROES.heroes, Model.DECKS.decks, maps_before_towergate(), Model.TERRAIN, Model.WEATHER, Model.ADVANTAGE]).sha256_text()

static func pre_expansion_signature() -> String:
	# Additive card pool only: retain exact old cards/decks/maps in the hash.
	# A future change to those definitions still invalidates old battle saves.
	var cards: Array[Dictionary] = []
	var decks: Array[Dictionary] = []
	for card: Dictionary in Model.CATALOG.cards:
		if card.id not in EXPANSION_CARDS: cards.append(card)
	for deck: Dictionary in Model.DECKS.decks:
		if deck.id != "ambush": decks.append(deck)
	return JSON.stringify([cards, Model.HEROES.heroes, decks, maps_before_towergate(), Model.TERRAIN, Model.WEATHER, Model.ADVANTAGE]).sha256_text()

static func normalize_legacy(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	if int(result.version) == 1: result["objective"] = {}
	if int(result.version) < 3: result["traps"] = []
	return result

static func _whole(value: Variant, minimum: int = 0, maximum: int = 1000000) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= minimum and value <= maximum

static func _text(value: Variant, maximum: int = 128) -> bool:
	return value is String and not value.is_empty() and value.length() <= maximum

static func _int64(value: Variant) -> bool:
	# Round-trip spelling catches overflow, exponent notation, whitespace and truncation.
	return value is String and value.is_valid_int() and str(value.to_int()) == value

static func capture(battle: RefCounted) -> Dictionary:
	var data: Dictionary = {"version": VERSION, "rules": rules_signature(), "map_id": battle.map_definition.id,
		"rng_seed": str(battle.rng.seed), "rng_state": str(battle.rng.state), "players": [], "units": [], "terrain": [], "log": Array(battle.log_lines)}
	for key: String in SCALARS: data[key] = battle.get(key)
	data["objective"] = battle.objective.duplicate(true)
	data["traps"] = []
	for trap: Dictionary in battle.traps:
		data.traps.append({"side": trap.side, "unit_id": trap.unit_id, "pos": [trap.pos.x, trap.pos.y], "card": trap.card.duplicate(true)})
	for side: int in range(2):
		var source: Dictionary = battle.players[side]
		var player: Dictionary = {}
		for key: String in PLAYER_FIELDS: player[key] = source[key]
		player["deck_counts"] = source.deck_definition.cards.duplicate(true)
		for zone: String in ["deck", "hand", "discard"]: player[zone] = source[zone].duplicate(true)
		player["identity"] = {"name": source.hero_display.name, "portrait": source.hero_display.portrait} if source.has("hero_display") else {}
		data.players.append(player)
	for source: Dictionary in battle.units:
		var unit: Dictionary = {}
		for key: String in UNIT_INTS + UNIT_TEXT: unit[key] = source[key]
		for key: String in UNIT_FLAGS: unit[key] = source.get(key, false)
		unit["pos"] = [source.pos.x, source.pos.y]
		if source.has("card"): unit["card"] = source.card.duplicate(true)
		data.units.append(unit)
	for y: int in range(battle.height):
		for x: int in range(battle.width): data.terrain.append(battle.ground(Vector2i(x, y)))
	return data

static func _find(items: Array[Dictionary], id: Variant) -> Dictionary:
	for item: Dictionary in items:
		if item.id == id: return item
	return {}

static func _card(card: Variant, ids: Dictionary, next_id: int, deployed_id: int = -1) -> String:
	if not card is Dictionary or not _whole(card.get("uid"), 1, next_id - 1): return "卡牌实例编号无效。"
	if ids.has(int(card.uid)): return "卡牌或单位实例编号重复。"
	var definition: Dictionary = Model.CATALOG.find(str(card.get("card_id", "")))
	if definition.is_empty(): return "卡牌定义不存在。"
	if card.has("unit_id") and not _whole(card.unit_id, 1, next_id - 1): return "部署牌关联编号无效。"
	if deployed_id != -1 and (definition.type != "unit" or card.get("unit_id") != deployed_id): return "部署牌与部队关联不一致。"
	ids[int(card.uid)] = true
	return ""

static func validate(data: Variant) -> Dictionary:
	if not data is Dictionary: return {"ok": false, "message": "战斗快照无效。"}
	var version: Variant = data.get("version")
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(version)) or float(version) != floorf(float(version)) or version < 1:
		return {"ok": false, "message": "战斗快照版本无效。"}
	if data.version > VERSION:
		return {"ok": false, "protected": true, "message": "战斗存档版本不兼容，原档保留。"}
	if not data.get("rules") is String or data.rules.length() != 64: return {"ok": false, "message": "战斗规则签名缺失。"}
	var old_map_ok: bool = data.get("map_id") != "towergate" and data.get("rules") == pre_towergate_signature()
	var old_cards_ok: bool = int(data.version) < 3 and data.get("map_id") != "towergate" and data.get("rules") == pre_expansion_signature()
	if data.get("rules") != rules_signature() and not old_map_ok and not old_cards_ok: return {"ok": false, "protected": true, "message": "战斗存档与当前规则版本不同，原档保留。"}
	if int(data.version) < 3 and data.get("traps", []) != []: return {"ok": false, "message": "旧版战斗不能包含伏设区。"}
	data = normalize_legacy(data)
	var problem: String = _validate(data)
	return {"ok": true} if problem.is_empty() else {"ok": false, "message": problem}

static func _validate(data: Dictionary) -> String:
	var map: Dictionary = _find(Model.MAPS.maps, data.get("map_id"))
	if map.is_empty(): return "战斗地图不存在。"
	var width: int = str(map.rows[0]).length()
	var height: int = map.rows.size()
	for key: String in ["turn", "next_id", "match_seed", "deck_size"]:
		if not _whole(data.get(key), 1): return "战斗编号无效：" + key
	if data.deck_size != Model.DECKS.DECK_SIZE: return "起始牌库数量与规则不一致。"
	if not _whole(data.get("active_side"), 0, 1) or not _whole(data.get("winner"), -1, 2): return "行动方或胜负无效。"
	if int(data.active_side) != (int(data.turn) - 1) % 2: return "回合与行动方不一致。"
	var goal_problem: String = Model.ControlObjective.validate_state(data.get("objective"), data, map)
	if not goal_problem.is_empty(): return goal_problem
	if not Model.WEATHER.has(data.get("weather")) or not _whole(data.get("weather_remaining"), 0, 10000): return "天气状态无效。"
	if (data.weather == "clear") != (data.weather_remaining == 0): return "天气期限不一致。"
	if not _number(data.get("turn_time_limit"), 1, 3600) or not _number(data.get("time_remaining"), 0, data.turn_time_limit): return "回合计时无效。"
	if not _int64(data.get("rng_seed")) or not _int64(data.get("rng_state")): return "随机数状态无法精确恢复。"
	if not data.get("terrain") is Array or data.terrain.size() != width * height: return "地形格数与地图不一致。"
	for ground: Variant in data.terrain:
		if not ground is String or not Model.TERRAIN.has(ground): return "地形类型不存在。"
	if not data.get("log") is Array or data.log.size() > 80: return "战报无效。"
	for line: Variant in data.log:
		if not _text(line, 4096): return "战报文本无效。"
	if not data.get("players") is Array or data.players.size() != 2: return "双方资料不完整。"
	if not data.get("units") is Array or data.units.size() > (Model.UNIT_LIMIT + 1) * 2: return "部队数量无效。"
	var ids: Dictionary = {}
	var cells: Dictionary = {}
	var commanders: Array[int] = [0, 0]
	var troops: Array[int] = [0, 0]
	var cards: Array[int] = [0, 0]
	for unit: Variant in data.units:
		if not unit is Dictionary: return "部队资料无效。"
		for key: String in UNIT_INTS:
			if not _whole(unit.get(key)): return "部队数值无效：" + key
		if unit.id < 1 or unit.id >= data.next_id or unit.side > 1 or unit.hp < 1 or unit.hp > unit.max_hp: return "部队生命或编号越界。"
		if ids.has(int(unit.id)): return "卡牌或单位实例编号重复。"
		ids[int(unit.id)] = true
		for key: String in UNIT_FLAGS:
			if not unit.get(key) is bool: return "部队状态标志无效：" + key
		for key: String in UNIT_TEXT:
			if not _text(unit.get(key)): return "部队名称或类型无效。"
		var pos: Variant = unit.get("pos")
		if not pos is Array or pos.size() != 2 or not _whole(pos[0], 0, width - 1) or not _whole(pos[1], 0, height - 1): return "部队位置越界。"
		var cell: int = int(pos[1]) * width + int(pos[0])
		if cells.has(cell) or data.terrain[cell] in ["water", "mountain"]: return "部队重叠或位于不可通行地形。"
		cells[cell] = true
		if unit.kind == "commander":
			commanders[int(unit.side)] += 1
			if unit.has("card"): return "指挥官不能关联部署牌。"
		else:
			var definition: Dictionary = Model.CATALOG.find(unit.kind)
			if definition.is_empty() or definition.type != "unit": return "部队兵种不存在。"
			var issue: String = _card(unit.get("card"), ids, int(data.next_id), int(unit.id))
			if not issue.is_empty(): return issue
			if unit.card.card_id != unit.kind: return "部署牌与兵种不一致。"
			troops[int(unit.side)] += 1
			cards[int(unit.side)] += 1
	if not data.get("traps") is Array or data.traps.size() > Model.Traps.LIMIT * 2: return "伏设区无效。"
	var trap_counts: Array[int] = [0, 0]
	var trap_slots: Dictionary = {}
	for trap: Variant in data.traps:
		if not trap is Dictionary or not _whole(trap.get("side"), 0, 1) or not _whole(trap.get("unit_id"), -1): return "伏设归属无效。"
		var issue: String = _card(trap.get("card"), ids, int(data.next_id))
		if not issue.is_empty(): return issue
		var card: Dictionary = Model.CATALOG.find(trap.card.card_id)
		if card.type != "trap" or trap.card.has("unit_id"): return "伏设区只能存放陷阱牌。"
		var pos: Variant = trap.get("pos")
		if not pos is Array or pos.size() != 2 or not _whole(pos[0], -1, width - 1) or not _whole(pos[1], -1, height - 1): return "伏设位置无效。"
		var slot: String = "%d:%s:%d" % [trap.side, str(pos), trap.unit_id]
		if trap_slots.has(slot): return "同一位置不能重复伏设。"
		trap_slots[slot] = true
		if card.trigger == "step":
			if trap.unit_id != -1 or pos[0] < 0 or pos[1] < 0 or data.terrain[int(pos[1]) * width + int(pos[0])] in ["mountain", "water"]: return "地格陷阱位置无效。"
		else:
			var protected: bool = false
			for unit: Dictionary in data.units:
				if unit.id == trap.unit_id and unit.side == trap.side: protected = true
			if not protected or pos[0] != -1 or pos[1] != -1: return "护军陷阱必须关联存活的友军。"
		trap_counts[int(trap.side)] += 1
		cards[int(trap.side)] += 1
		if trap_counts[int(trap.side)] > Model.Traps.LIMIT: return "伏设数量超过上限。"
	for side: int in range(2):
		if commanders[side] > 1 or troops[side] > Model.UNIT_LIMIT: return "指挥官或普通部队数量超限。"
		var player: Variant = data.players[side]
		if not player is Dictionary or _find(Model.HEROES.heroes, player.get("hero_id")).is_empty(): return "指挥官职业不存在。"
		var preset: Dictionary = _find(Model.DECKS.decks, player.get("deck_id"))
		if preset.is_empty() and player.get("deck_id") != "custom": return "套牌编号不存在。"
		var issue: String = Model.DECKS.validate_counts(player.get("deck_counts"), Model.CATALOG.cards)
		if not issue.is_empty(): return issue
		if not preset.is_empty() and Model.DECKS.canonical_counts(player.deck_counts, Model.CATALOG.cards) != Model.DECKS.canonical_counts(preset.cards, Model.CATALOG.cards): return "预组套牌与当前定义不一致。"
		for key: String in ["mana", "max_mana", "fatigue", "skill_cooldown", "card_total"]:
			if not _whole(player.get(key)): return "玩家数值无效：" + key
		if player.mana > 10 or player.max_mana > 10 or player.card_total > 1024 or not player.get("spell_boost_used") is bool: return "玩家资源状态无效。"
		if not player.get("identity") is Dictionary: return "指挥官显示身份无效。"
		if not player.identity.is_empty() and (not _text(player.identity.get("name")) or not _text(player.identity.get("portrait"))): return "指挥官显示身份缺少信息。"
		for zone: String in ["deck", "hand", "discard"]:
			if not player.get(zone) is Array or player[zone].size() > 1024: return "卡牌区域无效。"
			if zone == "hand" and player[zone].size() > Model.HAND_LIMIT: return "手牌数量超限。"
			for card: Variant in player[zone]:
				issue = _card(card, ids, int(data.next_id))
				if not issue.is_empty(): return issue
				cards[side] += 1
		if cards[side] != int(player.card_total): return "卡牌总数与牌区、场上部队不一致。"
	var actual_winner: int = -1 if commanders == [1, 1] else (2 if commanders == [0, 0] else (0 if commanders[0] == 1 else 1))
	if not data.objective.is_empty():
		if commanders[0] == 0: actual_winner = 1
		elif commanders[1] == 1: actual_winner = Model.ControlObjective.objective_winner(data.objective, data)
	if data.winner != actual_winner: return "指挥官状态与战果不一致。"
	return ""

static func restore(data: Variant) -> Dictionary:
	var checked: Dictionary = validate(data)
	if not checked.ok: return checked
	data = normalize_legacy(data)
	var battle: RefCounted = Model.new(int(data.match_seed), data.map_id, data.players[0].hero_id, data.players[1].hero_id)
	if int(data.version) >= 2 and not data.objective.is_empty():
		battle.objective = Model.ControlObjective.config(data.objective)
		battle.objective["streak"] = int(data.objective.streak)
		battle.objective["last_check"] = int(data.objective.last_check)
	for key: String in SCALARS:
		battle.set(key, data[key] if key in ["weather", "turn_time_limit", "time_remaining"] else int(data[key]))
	battle.players.clear()
	for raw: Dictionary in data.players:
		var player: Dictionary = {}
		for key: String in PLAYER_FIELDS: player[key] = raw[key] if key in ["hero_id", "deck_id", "spell_boost_used"] else int(raw[key])
		var counts: Dictionary = Model.DECKS.canonical_counts(raw.deck_counts, Model.CATALOG.cards)
		player["deck_definition"] = {"id": "custom", "name": "自定义军势", "description": "本地自定义套牌。", "cards": counts} if raw.deck_id == "custom" else Model.DECKS.find(raw.deck_id).duplicate(true)
		for zone: String in ["deck", "hand", "discard"]:
			player[zone] = []
			for card: Dictionary in raw[zone]: player[zone].append(_decode_card(card))
		battle.players.append(player)
	battle.units.clear()
	battle.traps.clear()
	for raw: Dictionary in data.traps:
		battle.traps.append({"side": int(raw.side), "unit_id": int(raw.unit_id), "pos": Vector2i(int(raw.pos[0]), int(raw.pos[1])), "card": _decode_card(raw.card)})
	for raw: Dictionary in data.units:
		var unit: Dictionary = {}
		for key: String in UNIT_INTS: unit[key] = int(raw[key])
		for key: String in UNIT_FLAGS + UNIT_TEXT: unit[key] = raw[key]
		unit["pos"] = Vector2i(int(raw.pos[0]), int(raw.pos[1]))
		if raw.has("card"): unit["card"] = _decode_card(raw.card)
		battle.units.append(unit)
	for side: int in range(2):
		var identity: Dictionary = data.players[side].identity
		if not identity.is_empty(): battle.set_commander_identity(side, identity.name, identity.portrait)
	# Identity reconstruction must not overwrite serialized survivor names/short labels.
	for index: int in range(data.units.size()):
		battle.units[index].name = data.units[index].name
		battle.units[index].short = data.units[index].short
	for y: int in range(battle.height):
		for x: int in range(battle.width): battle.terrain[Vector2i(x, y)] = data.terrain[y * battle.width + x]
	battle.log_lines.assign(data.log)
	battle.rng.seed = data.rng_seed.to_int()
	battle.rng.state = data.rng_state.to_int()
	return {"ok": true, "battle": battle}

static func _decode_card(raw: Dictionary) -> Dictionary:
	var card: Dictionary = {"uid": int(raw.uid), "card_id": raw.card_id}
	if raw.has("unit_id"): card["unit_id"] = int(raw.unit_id)
	return card
