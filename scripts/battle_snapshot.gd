extends RefCounted
## Plain-data snapshots. No object deserialization, rendering or turn-start effects.

const Model = preload("res://scripts/battle.gd")
const VERSION: int = 13
const PILGRIM_SET: String = "pilgrim"
const NEW_SET: String = "glassroad"
const EXPANSION_CARDS: Array[String] = ["shatter_bolt", "rally_heal", "cleanse_root", "reveal_traps", "seedwood", "anchor_snare", "ember_mine", "oath_ward"]
const CHANNEL_CARDS: Array[String] = ["span_kit", "countercurrent_ward"]
const LATER_SETS: Array[String] = ["warfront", "afterglow", "tidegate", "levee", "moorings", PILGRIM_SET, NEW_SET]
const SCALARS: Array[String] = ["active_side", "turn", "winner", "next_id", "match_seed", "deck_size", "weather", "weather_remaining", "turn_time_limit", "time_remaining"]
const PLAYER_FIELDS: Array[String] = ["hero_id", "deck_id", "mana", "max_mana", "fatigue", "skill_cooldown", "spell_boost_used", "card_total"]
const UNIT_INTS: Array[String] = ["id", "side", "hp", "max_hp", "atk", "defense", "move", "range", "shield", "last_move_distance", "rooted_turns"]
const UNIT_FLAGS: Array[String] = ["moved", "attacked", "summoning", "skill_used", "guarding"]
const UNIT_TEXT: Array[String] = ["name", "kind", "short"]
const WARFRONT_PRESETS_V043: Dictionary = {
	"frost_engine": {
		"description": "中场用雾棘锁阵和崩纹破盾，保持法师阵线，用八费澜潮或十费坠火处理敌人集群。",
		"cards": {"sword": 3, "spear": 2, "archer": 2, "mage": 2, "reed_scout": 2, "scribe_warden": 1, "ridge_archer": 1, "shore_medic": 1, "cavalry": 1, "breakwater_guard": 1,
			"mist_spike": 2, "kiln_lance": 1, "dispatch_bundle": 1, "warder_hymn": 1, "hammer_sweep": 1, "signal_torrent": 1, "last_hearth": 1, "frostbind": 1, "clear_skies": 1, "tidal_oath": 1, "fog": 1, "ward": 1, "second_watch": 1}},
	"lantern_convoy": {
		"description": "围绕重装枪兵布置援护和受击补给。群疗、灯夜和重印维持阵线，铺路时考虑双方都能使用。",
		"cards": {"sword": 2, "gate_veteran": 3, "healer": 2, "shore_medic": 3, "breakwater_guard": 2, "bronze_watch": 1, "mage": 2, "archer": 2,
			"field_signals": 2, "warder_hymn": 2, "fallback_horn": 2, "tidal_oath": 1, "night_muster": 2, "reed_roads": 1, "detach_line": 1, "silt_snare": 1, "hammer_sweep": 1}},
}

const EDICT_V055: Dictionary = {
	"description": "从低费灵活军令过渡到高费攻守两用牌。等敌军成列再破阵，或用天气、援护和续攻为下一轮抢先。",
	"cards": {"sword": 3, "glassroad_runner": 2, "rook_pickets": 1, "reedglass_bow": 2, "hinge_lancer": 2, "cinder_coxswain": 1, "copper_cistern": 1, "skylens_sentinel": 1, "mage": 1, "breakline_sappers": 1,
		"crossroads_whistle": 1, "hinge_order": 1, "rain_notch": 1, "highroad_edict": 1, "twin_standard": 1, "ebb_and_surge": 1, "glass_treaty": 1,
		"scour_fulcrum": 1, "winter_march": 1, "miller_alarm": 1, "hollow_hammer": 1, "storm_of_seals": 1, "bolt": 2, "quay_signal": 1}}

static func _historical_preset(id: String) -> Dictionary:
	return EDICT_V055 if id == "glassroad_edict" else WARFRONT_PRESETS_V043.get(id, {})

static func rules_signature() -> String:
	return _relay_signature(Model.CATALOG.cards, Model.DECKS.decks, Model.MAPS.maps, "glassroad_v1")

static func v055_rules_signature() -> String:
	var prior: Array[Dictionary] = []
	for deck: Dictionary in Model.DECKS.decks:
		prior.append(deck.merged(EDICT_V055, true) if deck.id == "glassroad_edict" else deck)
	return _relay_signature(Model.CATALOG.cards, prior, Model.MAPS.maps, "glassroad_v1")

static func _relay_signature(cards: Array[Dictionary], decks: Array[Dictionary], maps: Array[Dictionary], revision: String = "relay_v1") -> String:
	return JSON.stringify([cards, Model.HEROES.heroes, decks, maps, Model.TERRAIN, Model.WEATHER, Model.ADVANTAGE, revision]).sha256_text()

static func v052_rules_signature() -> String:
	var cards: Array[Dictionary] = Model.CATALOG.cards.filter(func(card: Dictionary) -> bool: return card.get("set_id", "") != NEW_SET)
	var decks: Array[Dictionary] = Model.DECKS.decks.filter(func(deck: Dictionary) -> bool: return deck.get("set_id", "") != NEW_SET)
	return _relay_signature(cards, decks, Model.MAPS.maps, "hand_combo_v1")

static func v050_rules_signature() -> String:
	var cards: Array[Dictionary] = Model.CATALOG.cards.filter(func(card: Dictionary) -> bool: return card.get("set_id", "") not in [PILGRIM_SET, NEW_SET])
	var decks: Array[Dictionary] = Model.DECKS.decks.filter(func(deck: Dictionary) -> bool: return deck.get("set_id", "") not in [PILGRIM_SET, NEW_SET])
	return _relay_signature(cards, decks, Model.MAPS.maps)

static func v048_rules_signature() -> String:
	var cards: Array[Dictionary] = Model.CATALOG.cards.filter(func(card: Dictionary) -> bool: return card.get("set_id", "") not in ["moorings", PILGRIM_SET, NEW_SET])
	var decks: Array[Dictionary] = Model.DECKS.decks.filter(func(deck: Dictionary) -> bool: return deck.get("set_id", "") not in ["moorings", PILGRIM_SET, NEW_SET])
	return _relay_signature(cards, decks, Model.MAPS.maps)

static func _cards_through_v046() -> Array[Dictionary]:
	return Model.CATALOG.cards.filter(func(card: Dictionary) -> bool: return card.get("set_id", "") not in ["levee", "moorings", PILGRIM_SET, NEW_SET])

static func _presets_through_v046() -> Array[Dictionary]:
	return Model.DECKS.decks.filter(func(deck: Dictionary) -> bool: return deck.get("set_id", "") not in ["levee", "moorings", PILGRIM_SET, NEW_SET])

static func v046_rules_signature() -> String:
	return _relay_signature(_cards_through_v046(), _presets_through_v046(), Model.MAPS.maps)

static func v045_rules_signature() -> String:
	return _relay_signature(_cards_through_v046(), _presets_through_v046(), maps_without([]))

static func _cards_through_v044() -> Array[Dictionary]:
	return _cards_through_v046().filter(func(card: Dictionary) -> bool: return card.get("set_id", "") != "tidegate")

static func _presets_through_v044() -> Array[Dictionary]:
	return _presets_through_v046().filter(func(deck: Dictionary) -> bool: return deck.get("set_id", "") != "tidegate")

static func v044_rules_signature() -> String:
	return _relay_signature(_cards_through_v044(), _presets_through_v044(), maps_without([]))

static func _presets_through_v043() -> Array[Dictionary]:
	var decks: Array[Dictionary] = []
	for preset: Dictionary in _presets_through_v044():
		var previous: Dictionary = WARFRONT_PRESETS_V043.get(preset.id, {})
		decks.append(preset if previous.is_empty() else preset.merged(previous, true))
	return decks

static func v043_rules_signature() -> String:
	return _relay_signature(_cards_through_v044(), _presets_through_v043(), maps_without([]))

static func pre_afterglow_signature() -> String:
	var cards: Array[Dictionary] = _cards_through_v044().filter(func(card: Dictionary) -> bool: return card.get("set_id", "") != "afterglow")
	var decks: Array[Dictionary] = _presets_through_v043().filter(func(deck: Dictionary) -> bool: return deck.get("set_id", "") != "afterglow")
	return _relay_signature(cards, decks, maps_without([]))

static func cards_before_channel() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for card: Dictionary in Model.CATALOG.cards:
		if card.id not in CHANNEL_CARDS and card.get("set_id", "") not in LATER_SETS: cards.append(card)
	return cards

static func decks_before_channel() -> Array[Dictionary]:
	var decks: Array[Dictionary] = []
	for deck: Dictionary in Model.DECKS.decks:
		if deck.id != "channel" and deck.get("set_id", "") not in LATER_SETS: decks.append(deck)
	return decks

static func maps_without(excluded: Array) -> Array[Dictionary]:
	# Earlier releases all predate the chapter-seven escort battlefield.
	var maps: Array[Dictionary] = []
	for map: Dictionary in Model.MAPS.maps:
		if map.id != "saltlane" and map.id not in excluded: maps.append(map)
	return maps

static func pre_v038_signature() -> String:
	return JSON.stringify([cards_before_channel(), Model.HEROES.heroes, decks_before_channel(), maps_without(["spillway", "eastbridge", "lamplanding"]), Model.TERRAIN, weather_before_warfront(), Model.ADVANTAGE]).sha256_text()

static func pre_eastbridge_signature() -> String:
	return _signature_before_warfront(["eastbridge", "lamplanding"])

static func pre_relay_signature() -> String:
	return _signature_before_warfront(["lamplanding"])

static func _signature_before_warfront(excluded_maps: Array) -> String:
	var cards: Array[Dictionary] = Model.CATALOG.cards.filter(func(card: Dictionary) -> bool: return card.get("set_id", "") not in LATER_SETS)
	var decks: Array[Dictionary] = Model.DECKS.decks.filter(func(deck: Dictionary) -> bool: return deck.get("set_id", "") not in LATER_SETS)
	return JSON.stringify([cards, Model.HEROES.heroes, decks, maps_without(excluded_maps), Model.TERRAIN, weather_before_warfront(), Model.ADVANTAGE]).sha256_text()

static func weather_before_warfront() -> Dictionary:
	var conditions: Dictionary = Model.WEATHER.duplicate()
	conditions.erase("tailwind")
	conditions.erase("lanterns")
	return conditions

static func maps_before_towergate() -> Array[Dictionary]:
	var maps: Array[Dictionary] = []
	for map: Dictionary in Model.MAPS.maps:
		if not map.get("campaign_only", false): maps.append(map)
	return maps

static func pre_northbank_signature() -> String:
	# A new chapter-only map leaves already-started 0.35 battles intact.
	return JSON.stringify([cards_before_channel(), Model.HEROES.heroes, decks_before_channel(), maps_without(["northbank", "spillway", "eastbridge", "lamplanding"]), Model.TERRAIN, weather_before_warfront(), Model.ADVANTAGE]).sha256_text()

static func pre_towergate_signature() -> String:
	# A chapter-only map must not invalidate a running battle on an unchanged
	# original map. This is the exact 0.33 catalog, not a wildcard signature.
	return JSON.stringify([cards_before_channel(), Model.HEROES.heroes, decks_before_channel(), maps_before_towergate(), Model.TERRAIN, weather_before_warfront(), Model.ADVANTAGE]).sha256_text()

static func pre_expansion_signature() -> String:
	# Additive card pool only: retain exact old cards/decks/maps in the hash.
	# A future change to those definitions still invalidates old battle saves.
	var cards: Array[Dictionary] = []
	var decks: Array[Dictionary] = []
	for card: Dictionary in cards_before_channel():
		if card.id not in EXPANSION_CARDS: cards.append(card)
	for deck: Dictionary in decks_before_channel():
		if deck.id != "ambush": decks.append(deck)
	return JSON.stringify([cards, Model.HEROES.heroes, decks, maps_before_towergate(), Model.TERRAIN, weather_before_warfront(), Model.ADVANTAGE]).sha256_text()

static func normalize_legacy(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	if int(result.version) == 1: result["objective"] = {}
	if int(result.version) < 3: result["traps"] = []
	if int(result.version) < 9: result["pending_orders"] = []
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
		"rng_seed": str(battle.rng.seed), "rng_state": str(battle.rng.state), "players": [], "units": [], "terrain": [], "log": battle.log_lines.duplicate()}
	for key: String in SCALARS: data[key] = battle.get(key)
	if battle.hand_played_this_turn: data["hand_played_this_turn"] = true
	data["objective"] = battle.objective.duplicate(true)
	data["traps"] = []
	for trap: Dictionary in battle.traps:
		data.traps.append({"side": trap.side, "unit_id": trap.unit_id, "pos": [trap.pos.x, trap.pos.y], "card": trap.card.duplicate(true)})
	data["pending_orders"] = []
	for order: Dictionary in battle.pending_orders:
		data.pending_orders.append({"side": order.side, "pos": [order.pos.x, order.pos.y], "due_turn": order.due_turn, "card": order.card.duplicate(true)})
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
	if card.has("unit_id") and (definition.type != "unit" or not _whole(card.unit_id, 1, next_id - 1)): return "部署牌关联编号无效。"
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
	var compatible: bool
	if int(version) == 12:
		compatible = data.rules == v055_rules_signature()
	else:
		compatible = data.rules == rules_signature() or (int(version) < VERSION and _legacy_rules_match(data))
	if not compatible:
		return {"ok": false, "protected": true, "message": "战斗存档与当前规则版本不同，原档保留。"}
	if data.has("hand_played_this_turn") and (int(version) < 11 or not data.hand_played_this_turn is bool):
		return {"ok": false, "message": "回合连携记录无效。"}
	var goal: Variant = data.get("objective")
	if int(version) < 8 and (data.get("map_id") == "saltlane" or (goal is Dictionary and Model.ControlObjective.is_escort(goal))):
		return {"ok": false, "message": "旧版战斗不支持护送任务。"}
	if int(version) < 4 and (data.get("map_id") == "lamplanding" or (goal is Dictionary and Model.ControlObjective.is_relay(goal))):
		return {"ok": false, "message": "旧版战斗不支持接力任务。"}
	if int(data.version) < 3 and data.get("traps", []) != []: return {"ok": false, "message": "旧版战斗不能包含伏设区。"}
	if int(data.version) < 9 and data.get("pending_orders", []) != []: return {"ok": false, "message": "旧版战斗不能包含待结算军令。"}
	data = normalize_legacy(data)
	var problem: String = _validate(data)
	return {"ok": true} if problem.is_empty() else {"ok": false, "message": problem}

static func _legacy_rules_match(data: Dictionary) -> bool:
	if int(data.version) == 11: return data.rules == v052_rules_signature()
	if int(data.version) == 10: return data.rules == v050_rules_signature()
	if int(data.version) == 9: return data.rules == v048_rules_signature()
	if int(data.version) == 8: return data.rules == v046_rules_signature()
	if int(data.version) == 7: return data.rules == v045_rules_signature()
	if int(data.version) == 6: return data.rules == v044_rules_signature()
	if int(data.version) == 5: return data.rules == v043_rules_signature()
	if int(data.version) == 4: return data.rules == pre_afterglow_signature()
	var map: Variant = data.get("map_id")
	if map == "lamplanding": return false
	if data.rules == pre_relay_signature(): return true
	if map == "eastbridge": return false
	if data.rules == pre_eastbridge_signature(): return true
	if map == "spillway": return false
	if data.rules == pre_v038_signature(): return true
	if map == "northbank": return false
	if data.rules == pre_northbank_signature(): return true
	if map == "towergate": return false
	return data.rules == pre_towergate_signature() or (int(data.version) < 3 and data.rules == pre_expansion_signature())

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
			var issue: String = _card(unit.get("card"), ids, int(data.next_id), int(unit.id))
			if not issue.is_empty(): return issue
			var definition: Dictionary = Model.CATALOG.find(unit.card.card_id)
			if definition.type != "unit" or definition.kind != unit.kind: return "部署牌与兵种不一致。"
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
	if not data.get("pending_orders") is Array or data.pending_orders.size() > 2: return "待结算军令数量无效。"
	var issuing_sides: Array[int] = []
	for order: Variant in data.pending_orders:
		if not order is Dictionary or not _whole(order.get("side"), 0, 1): return "待结算军令归属无效。"
		var issuer: int = int(order.side)
		if issuing_sides.has(issuer): return "每方只能保留一条待结算军令。"
		issuing_sides.append(issuer)
		var due: int = int(data.turn) + (2 if issuer == int(data.active_side) else 1)
		if not _whole(order.get("due_turn"), due, due): return "待结算军令期限无效。"
		var pos: Variant = order.get("pos")
		if not pos is Array or pos.size() != 2 or not _whole(pos[0], 0, width - 1) or not _whole(pos[1], 0, height - 1): return "军令位置无效。"
		if data.terrain[int(pos[1]) * width + int(pos[0])] in ["water", "mountain"]: return "军令中心必须位于可通行地格。"
		var order_issue: String = _card(order.get("card"), ids, int(data.next_id))
		if not order_issue.is_empty(): return order_issue
		if order.card.has("unit_id") or Model.CATALOG.find(order.card.card_id).get("effect", "") != "scheduled": return "军令区卡牌种类无效。"
		cards[issuer] += 1
	for side: int in range(2):
		if commanders[side] > 1 or troops[side] > Model.UNIT_LIMIT: return "指挥官或普通部队数量超限。"
		var player: Variant = data.players[side]
		if not player is Dictionary or _find(Model.HEROES.heroes, player.get("hero_id")).is_empty(): return "指挥官职业不存在。"
		var preset: Dictionary = _find(Model.DECKS.decks, player.get("deck_id"))
		if preset.is_empty() and player.get("deck_id") != "custom": return "套牌编号不存在。"
		var issue: String = Model.DECKS.validate_counts(player.get("deck_counts"), Model.CATALOG.cards)
		if not issue.is_empty(): return issue
		if not preset.is_empty():
			var counts: Dictionary = Model.DECKS.canonical_counts(player.deck_counts, Model.CATALOG.cards)
			var old_counts: Dictionary = _historical_preset(preset.id).get("cards", {})
			if int(data.version) == 12 and preset.id == "glassroad_edict" and counts != old_counts:
				return "旧版双潮军令与已发行牌表不一致。"
			if counts != preset.cards and counts != old_counts: return "预组套牌与已发行牌表不一致。"
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
				if zone != "discard" and card.has("unit_id"): return "牌库与手牌不能保留部署编号。"
				cards[side] += 1
		if cards[side] != int(player.card_total): return "卡牌总数与牌区、场上部队不一致。"
	var actual_winner: int = -1 if commanders == [1, 1] else (2 if commanders == [0, 0] else (0 if commanders[0] == 1 else 1))
	if not data.objective.is_empty():
		if commanders[0] == 0: actual_winner = 1
		elif commanders[1] == 1: actual_winner = Model.ControlObjective.objective_winner(data.objective, data)
	if Model.ControlObjective.is_escort(data.objective):
		var escort: Dictionary = {}
		for unit: Dictionary in data.units:
			if unit.id == data.objective.escort_id: escort = unit; break
		if escort.is_empty():
			var casualties: int = 0
			for card: Dictionary in data.players[0].discard:
				if card.get("unit_id", -1) == data.objective.escort_id and card.card_id == Model.ControlObjective.ESCORT_CARD:
					casualties += 1
			if casualties != 1: return "护送记录缺少阵亡的担架队。"
			actual_winner = 1
		elif escort.side != 0 or escort.get("card", {}).get("card_id", "") != Model.ControlObjective.ESCORT_CARD or escort.name != Model.ControlObjective.ESCORT_NAME:
			return "护送对象与担架队资料不一致。"
		var delivered: bool = not escort.is_empty() and commanders == [1, 1] and Model.ControlObjective.position(escort.pos) == Model.ControlObjective.position(data.objective.cells[0])
		if int(data.objective.streak) != int(delivered): return "担架队送达状态无效。"
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
		if Model.ControlObjective.is_escort(data.objective):
			battle.objective["escort_id"] = int(data.objective.escort_id)
	for key: String in SCALARS:
		battle.set(key, data[key] if key in ["weather", "turn_time_limit", "time_remaining"] else int(data[key]))
	battle.hand_played_this_turn = data.get("hand_played_this_turn", false)
	battle.players.clear()
	for raw: Dictionary in data.players:
		var player: Dictionary = {}
		for key: String in PLAYER_FIELDS: player[key] = raw[key] if key in ["hero_id", "deck_id", "spell_boost_used"] else int(raw[key])
		var counts: Dictionary = Model.DECKS.canonical_counts(raw.deck_counts, Model.CATALOG.cards)
		if raw.deck_id == "custom":
			player["deck_definition"] = {"id": "custom", "name": "自定义军势", "description": "本地自定义套牌。", "cards": counts}
		else:
			var preset: Dictionary = Model.DECKS.find(raw.deck_id).duplicate(true)
			if counts != preset.cards: preset.merge(_historical_preset(raw.deck_id), true)
			preset["cards"] = counts
			player["deck_definition"] = preset
		for zone: String in ["deck", "hand", "discard"]:
			player[zone] = []
			for card: Dictionary in raw[zone]: player[zone].append(_decode_card(card))
		battle.players.append(player)
	battle.units.clear()
	battle.traps.clear()
	for raw: Dictionary in data.traps:
		battle.traps.append({"side": int(raw.side), "unit_id": int(raw.unit_id), "pos": Vector2i(int(raw.pos[0]), int(raw.pos[1])), "card": _decode_card(raw.card)})
	for raw: Dictionary in data.pending_orders:
		battle.pending_orders.append({"side": int(raw.side), "pos": Vector2i(int(raw.pos[0]), int(raw.pos[1])),
			"due_turn": int(raw.due_turn), "card": _decode_card(raw.card)})
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
