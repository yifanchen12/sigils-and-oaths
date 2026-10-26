class_name Battle
extends RefCounted
## The only authority for rules. UI and AI both submit actions here.

signal changed

const CATALOG = preload("res://data/cards.tres")
const MAPS = preload("res://data/maps.tres")
const HEROES = preload("res://data/heroes.tres")
const DECKS = preload("res://data/decks.tres")
var width: int = 8
var height: int = 6
const HAND_LIMIT: int = 8
const UNIT_LIMIT: int = 6
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const ADVANTAGE: Dictionary = {"sword": "spear", "spear": "cavalry", "cavalry": "sword"}
const TERRAIN: Dictionary = {
	"plain": {"name": "平地", "defense": 0, "description": "基础移动费用 1。"},
	"forest": {"name": "森林", "defense": 1, "description": "防御 +1；步/枪费用 1，其他步行单位 2，骑兵 3。"},
	"mountain": {"name": "山地", "defense": 0, "description": "无法通行或部署。"},
	"road": {"name": "军道", "defense": 0, "description": "移动费用 1；从军道出发的骑兵移动力 +1。"},
	"bridge": {"name": "桥梁", "defense": 0, "description": "过河通路；费用 1，骑兵从桥上出发移动力 +1。"},
	"water": {"name": "河流", "defense": 0, "description": "无法通行或部署，需从桥梁渡河。"},
	"hill": {"name": "高地", "defense": 1, "description": "防御 +1，攻击非高地目标伤害 +1，远程射程 +1；进入费用 2。"},
	"ruins": {"name": "遗迹", "defense": 0, "description": "移动费用 1；己方回合开始恢复驻守部队 1 生命。"},
	"fort": {"name": "工事", "defense": 2, "description": "防御 +2，移动费用 1。"}
}
const WEATHER: Dictionary = {
	"clear": {"name": "晴朗", "description": "无额外影响。"},
	"rain": {"name": "暴雨", "description": "骑兵在军道/桥梁外移动费用 +1；火焰法术伤害 -1。"},
	"fog": {"name": "浓雾", "description": "双方单位的最终射程上限为 2。"},
	"sun": {"name": "烈日", "description": "火焰法术伤害 +1，医师回合治疗 +1。"},
	"snow": {"name": "寒潮", "description": "普通部队移动力 -1（至少 1）；森林再提供 1 防御。"}
}

var players: Array[Dictionary] = []
var units: Array[Dictionary] = []
var terrain: Dictionary = {}
var active_side: int = 0
var turn: int = 1
var winner: int = -1 # -1 ongoing; 0/1 winner; 2 draw
var log_lines: Array[String] = []
var rng := RandomNumberGenerator.new()
var next_id: int = 1
var match_seed: int = 0
var deck_size: int = 0
var map_definition: Dictionary = {}
var weather: String = "clear"
var weather_remaining: int = 0
var turn_time_limit: float = 90.0
var time_remaining: float = 90.0

func _init(seed_value: int = 42, map_id: String = "greenwood", blue_hero: String = "warden", red_hero: String = "pyromancer", blue_deck: String = "balanced", red_deck: String = "balanced", seconds_per_turn: float = 90.0, blue_custom: Dictionary = {}) -> void:
	match_seed = seed_value
	turn_time_limit = maxf(1.0, seconds_per_turn)
	rng.seed = seed_value
	map_definition = MAPS.find(map_id)
	width = str(map_definition.rows[0]).length()
	height = map_definition.rows.size()
	var symbols: Dictionary = {".": "plain", "f": "forest", "m": "mountain", "r": "road", "w": "water", "b": "bridge", "h": "hill", "t": "fort"}
	for y: int in range(height):
		for x: int in range(width):
			terrain[Vector2i(x, y)] = symbols[map_definition.rows[y][x]]
	for cell: Vector2i in map_definition.ruins: terrain[cell] = "ruins"
	for side: int in range(2):
		var deck: Array = []
		var deck_definition: Dictionary = DECKS.find(blue_deck if side == 0 else red_deck)
		if side == 0 and blue_deck == "custom":
			var custom_error: String = DECKS.validate_counts(blue_custom.get("cards", {}), CATALOG.cards)
			if custom_error.is_empty():
				deck_definition = {"id": "custom", "name": "自定义军势", "description": "本地自定义套牌。", "cards": DECKS.canonical_counts(blue_custom.cards, CATALOG.cards)}
			else: _record("自定义套牌无效，改用均衡军势：" + custom_error)
		for definition: Dictionary in CATALOG.cards:
			if definition.get("generated_only", false): continue
			for copy_index: int in range(int(deck_definition.cards.get(definition.id, 0))):
				deck.append({"uid": _id(), "card_id": definition.id})
		# Fisher-Yates uses this match's RNG, never the process-global shuffle.
		for index: int in range(deck.size() - 1, 0, -1):
			var other: int = rng.randi_range(0, index)
			var saved: Dictionary = deck[index]
			deck[index] = deck[other]
			deck[other] = saved
		deck_size = deck.size()
		var hero: Dictionary = HEROES.find(blue_hero if side == 0 else red_hero)
		players.append({"deck": deck, "hand": [], "discard": [], "mana": 0, "max_mana": 0, "fatigue": 0,
			"hero_id": hero.id, "deck_id": deck_definition.id, "deck_definition": deck_definition.duplicate(true), "skill_cooldown": 0, "spell_boost_used": false, "card_total": deck.size()})
		units.append({"id": _id(), "side": side, "name": hero.name,
			"kind": "commander", "short": hero.short, "hp": hero.hp, "max_hp": hero.hp, "atk": hero.atk,
			"defense": hero.defense, "move": 0, "range": hero.range, "shield": 0,
			"pos": map_definition.spawns[side], "last_move_distance": 0, "rooted_turns": 0,
			"moved": false, "attacked": false, "summoning": false})
		_draw(side, 4 if side == 0 else 5)
		if side == 1: add_generated_card(side, "initiative")
	_start_turn()
	_record("战斗开始：推进部队，即可向前延伸部署范围。")

func _id() -> int:
	var value: int = next_id
	next_id += 1
	return value

func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func ground(cell: Vector2i) -> String:
	return terrain.get(cell, "plain")

func hero(side: int) -> Dictionary:
	return HEROES.find(players[side].hero_id)

func deck(side: int) -> Dictionary:
	return players[side].deck_definition

func passable(cell: Vector2i) -> bool:
	return inside(cell) and ground(cell) not in ["mountain", "water"]

func terrain_defense(unit: Dictionary) -> int:
	return int(TERRAIN[ground(unit.pos)].defense) + (1 if weather == "snow" and ground(unit.pos) == "forest" else 0)

func aura_defense(unit: Dictionary) -> int:
	if unit.kind == "commander" or hero(unit.side).id != "warden": return 0
	var leader: Dictionary = commander(unit.side)
	return 1 if not leader.is_empty() and distance(unit.pos, leader.pos) == 1 else 0

func movement_allowance(unit: Dictionary) -> int:
	if unit.move == 0: return 0
	var allowance: int = int(unit.move)
	if unit.kind == "cavalry" and ground(unit.pos) in ["road", "bridge"]: allowance += 1
	if weather == "snow": allowance -= 1
	return maxi(1, allowance)

func movement_cost(unit: Dictionary, cell: Vector2i) -> int:
	if not passable(cell): return 999
	var cost: int = 1
	if ground(cell) == "hill": cost = 2
	if ground(cell) == "forest":
		cost = 3 if unit.get("kind", "") == "cavalry" else (1 if unit.get("kind", "") in ["sword", "spear"] else 2)
	if weather == "rain" and unit.get("kind", "") == "cavalry" and ground(cell) not in ["road", "bridge"]: cost += 1
	return cost

func attack_range(unit: Dictionary) -> int:
	var result: int = unit.range
	if ground(unit.pos) == "hill" and result > 1: result += 1
	if weather == "fog": result = mini(2, result)
	return result

func get_unit(unit_id: int) -> Dictionary:
	for unit: Dictionary in units:
		if unit.id == unit_id:
			return unit
	return {}

func unit_at(cell: Vector2i) -> Dictionary:
	for unit: Dictionary in units:
		if unit.pos == cell:
			return unit
	return {}

func commander(side: int) -> Dictionary:
	for unit: Dictionary in units:
		if unit.side == side and unit.kind == "commander":
			return unit
	return {}

func definition(card_id: String) -> Dictionary:
	return CATALOG.find(card_id)

func hand_card(side: int, uid: int) -> Dictionary:
	for card: Dictionary in players[side].hand:
		if card.uid == uid:
			return card
	return {}

func add_generated_card(side: int, card_id: String) -> bool:
	if side < 0 or side >= players.size() or definition(card_id).is_empty(): return false
	var instance: Dictionary = {"uid": _id(), "card_id": card_id}
	players[side].card_total += 1
	if players[side].hand.size() < HAND_LIMIT: players[side].hand.append(instance)
	else: players[side].discard.append(instance)
	return true

func army_count(side: int) -> int:
	var count: int = 0
	for unit: Dictionary in units:
		if unit.side == side and unit.kind != "commander":
			count += 1
	return count

func deployment_cells(side: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if army_count(side) >= UNIT_LIMIT:
		return result
	for unit: Dictionary in units:
		if unit.side != side:
			continue
		for direction: Vector2i in DIRECTIONS:
			var cell: Vector2i = unit.pos + direction
			if passable(cell) and unit_at(cell).is_empty() and not result.has(cell):
				result.append(cell)
	return result

func walk_distances(origin: Vector2i, unit: Dictionary = {}) -> Dictionary:
	# ponytail: a small Dijkstra frontier is sufficient for the 48-cell weighted board.
	var distances: Dictionary = {origin: 0}
	var queue: Array[Vector2i] = [origin]
	while not queue.is_empty():
		var cheapest: int = 0
		for index: int in range(1, queue.size()):
			if int(distances[queue[index]]) < int(distances[queue[cheapest]]): cheapest = index
		var current: Vector2i = queue.pop_at(cheapest)
		for direction: Vector2i in DIRECTIONS:
			var cell: Vector2i = current + direction
			if not passable(cell) or not unit_at(cell).is_empty():
				continue
			var cost: int = int(distances[current]) + movement_cost(unit, cell)
			if not distances.has(cell) or cost < int(distances[cell]):
				distances[cell] = cost
				if not queue.has(cell): queue.append(cell)
	return distances

func movement_cells(unit: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit.is_empty() or unit.moved or unit.attacked or unit.summoning or unit.move == 0 or int(unit.get("rooted_turns", 0)) > 0:
		return result
	var distances: Dictionary = walk_distances(unit.pos, unit)
	for cell: Vector2i in distances:
		if cell != unit.pos and int(distances[cell]) <= movement_allowance(unit):
			result.append(cell)
	return result

func movement_path(unit: Dictionary, destination: Vector2i) -> Array[Vector2i]:
	var distances: Dictionary = walk_distances(unit.pos, unit)
	var path: Array[Vector2i] = []
	if not distances.has(destination): return path
	var cell: Vector2i = destination
	while cell != unit.pos:
		path.append(cell)
		var found: bool = false
		for direction: Vector2i in DIRECTIONS:
			var previous: Vector2i = cell + direction
			if distances.has(previous) and int(distances[previous]) + movement_cost(unit, cell) == int(distances[cell]):
				cell = previous
				found = true
				break
		if not found: return []
	path.append(unit.pos)
	path.reverse()
	return path

func attack_targets(unit: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit.is_empty() or unit.attacked or unit.summoning:
		return result
	for target: Dictionary in units:
		if target.side != unit.side and distance(unit.pos, target.pos) <= attack_range(unit):
			result.append(target.pos)
	return result

func unit_skill(unit: Dictionary) -> Dictionary:
	if unit.is_empty() or unit.kind == "commander": return {}
	return definition(unit.kind).get("skill", {})

func skill_targets(unit: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var skill: Dictionary = unit_skill(unit)
	if winner != -1 or skill.is_empty() or unit.side != active_side or unit.hp <= 0: return result
	if unit.summoning or unit.attacked or unit.get("skill_used", false) or players[active_side].mana < skill.cost: return result
	match String(unit.kind):
		"sword":
			if unit.shield < 3: result.append(unit.pos)
		"spear":
			if int(unit.get("rooted_turns", 0)) == 0 and not unit.get("guarding", false): result.append(unit.pos)
		"cavalry":
			if not unit.moved or int(unit.get("rooted_turns", 0)) > 0: return result
			var costs: Dictionary = walk_distances(unit.pos, unit)
			for cell: Vector2i in costs:
				if cell != unit.pos and int(costs[cell]) <= 2: result.append(cell)
		"archer": return attack_targets(unit)
		"mage", "healer":
			for target: Dictionary in units:
				if distance(unit.pos, target.pos) > 2: continue
				if unit.kind == "mage" and target.side != unit.side: result.append(target.pos)
				elif unit.kind == "healer" and target.side == unit.side and target.hp < target.max_hp: result.append(target.pos)
	return result

func attack_defender(attacker: Dictionary, target: Dictionary) -> Dictionary:
	# Only an initiating normal attack is intercepted; never recurse through guards.
	if target.is_empty() or attacker.is_empty() or attacker.side == target.side: return target
	var defender: Dictionary = target
	for guard: Dictionary in units:
		if guard.id == target.id or guard.side != target.side or guard.kind != "spear" or guard.hp <= 0: continue
		if not guard.get("guarding", false) or int(guard.get("rooted_turns", 0)) > 0: continue
		if distance(guard.pos, target.pos) != 1: continue
		if defender.id == target.id or guard.id < defender.id: defender = guard
	return defender

func attack_forecast(attacker: Dictionary, target: Dictionary, bonus: int = 0) -> Dictionary:
	var defender: Dictionary = attack_defender(attacker, target)
	if defender.is_empty() or attacker.is_empty(): return {}
	var damage: int = damage_preview(attacker, defender) + bonus
	var loss: int = mini(int(defender.hp), maxi(0, damage - int(defender.shield)))
	var counter: int = 0
	if defender.hp > loss and distance(attacker.pos, defender.pos) <= attack_range(defender): counter = damage_preview(defender, attacker)
	return {"defender_id": defender.id, "protected_id": target.id, "intercepted": defender.id != target.id,
		"damage": damage, "counter_damage": counter, "target_loss": loss,
		"attacker_loss": mini(int(attacker.hp), maxi(0, counter - int(attacker.shield)))}

func _resolve_attack(unit: Dictionary, selected_target: Dictionary, bonus: int = 0) -> void:
	var target: Dictionary = attack_defender(unit, selected_target)
	unit.attacked = true
	unit.moved = true
	if target.id != selected_target.id: _record("%s援护%s，代为承受攻击。" % [target.name, selected_target.name])
	var damage: int = damage_preview(unit, target) + bonus
	_hurt(target, damage)
	var advantage_text: String = "（兵种克制 +2）" if ADVANTAGE.get(unit.kind, "") == target.kind else ""
	_record("%s攻击%s，造成 %d 点伤害%s。" % [unit.name, target.name, damage, advantage_text])
	if target.hp > 0 and distance(unit.pos, target.pos) <= attack_range(target):
		var counter: int = damage_preview(target, unit)
		_hurt(unit, counter)
		_record("%s反击，造成 %d 点伤害。" % [target.name, counter])

func _resolve_unit_skill(unit: Dictionary, cell: Vector2i) -> void:
	unit["skill_used"] = true
	match String(unit.kind):
		"sword": unit.shield = maxi(3, int(unit.shield))
		"spear": unit["guarding"] = true
		"cavalry":
			unit.last_move_distance = int(unit.get("last_move_distance", 0)) + movement_path(unit, cell).size() - 1
			unit.pos = cell
		"archer": _resolve_attack(unit, unit_at(cell), 1)
		"mage": _hurt(unit_at(cell), fire_damage(3))
		"healer":
			var target: Dictionary = unit_at(cell)
			target.hp = mini(int(target.max_hp), int(target.hp) + 3)
	unit.moved = true
	if unit.kind != "cavalry": unit.attacked = true
	_record("%s发动「%s」。" % [unit.name, unit_skill(unit).name])

func unit_cast_range(unit: Dictionary) -> int:
	return 4 if unit.kind == "mage" else 3

func hero_cast_range(side: int) -> int:
	return int(hero(side).get("skill_range", 3))

func can_cast_at(cell: Vector2i, side: int) -> bool:
	if not inside(cell): return false
	for caster: Dictionary in units:
		if caster.side == side and distance(caster.pos, cell) <= unit_cast_range(caster): return true
	return false

func casting_cells(side: int, leader_only: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var leader: Dictionary = commander(side)
	for y: int in range(height):
		for x: int in range(width):
			var cell := Vector2i(x, y)
			var covered: bool = (not leader.is_empty() and distance(leader.pos, cell) <= hero_cast_range(side)) if leader_only else can_cast_at(cell, side)
			if covered: result.append(cell)
	return result

func spell_cells(card: Dictionary, side: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if card.effect == "mana": return [Vector2i(-1, -1)] if players[side].mana < 10 else []
	if card.effect == "clear_weather": return [Vector2i(-1, -1)] if weather != "clear" else []
	if card.effect in ["draw", "weather"]:
		return [Vector2i(-1, -1)]
	if card.effect == "terrain":
		for y: int in range(height):
			for x: int in range(width):
				var cell := Vector2i(x, y)
				var occupant: Dictionary = unit_at(cell)
				if not passable(cell) or ground(cell) in ["bridge", String(card.terrain)]: continue
				if not can_cast_at(cell, side): continue
				if card.terrain == "fort" and (occupant.is_empty() or occupant.side != side): continue
				result.append(cell)
		return result
	for target: Dictionary in units:
		var friendly: bool = target.side == side
		var valid: bool = false
		match String(card.effect):
			"damage", "area": valid = not friendly
			"heal": valid = friendly and target.hp < target.max_hp
			"shield": valid = friendly and target.shield < card.amount
			"march": valid = friendly and target.kind != "commander" and target.moved and not target.attacked and not target.summoning and int(target.get("rooted_turns", 0)) == 0
			"repulse": valid = not friendly and target.kind != "commander"
			"root": valid = not friendly and target.kind != "commander" and int(target.get("rooted_turns", 0)) < 2
			"dispel": valid = not friendly and target.shield > 0
			"exchange": valid = friendly and target.kind != "commander" and distance(commander(side).pos, target.pos) <= 3
			"onslaught": valid = friendly and target.kind != "commander" and target.attacked and not target.summoning
		if valid and can_cast_at(target.pos, side):
			result.append(target.pos)
	return result

func repulse_destination(target: Dictionary, side: int) -> Vector2i:
	var origin: Vector2i = commander(side).pos
	var difference: Vector2i = target.pos - origin
	var direction: Vector2i = Vector2i(signi(difference.x), 0) if absi(difference.x) > absi(difference.y) else Vector2i(0, signi(difference.y))
	var destination: Vector2i = target.pos + direction
	if direction == Vector2i.ZERO or not passable(destination) or not unit_at(destination).is_empty(): return target.pos
	return destination

func card_targets(uid: int, side: int) -> Array[Vector2i]:
	var instance: Dictionary = hand_card(side, uid)
	if instance.is_empty():
		return []
	var card: Dictionary = definition(instance.card_id)
	return deployment_cells(side) if card.type == "unit" else spell_cells(card, side)

func damage_preview(attacker: Dictionary, target: Dictionary) -> int:
	return int(damage_breakdown(attacker, target).damage)

func damage_breakdown(attacker: Dictionary, target: Dictionary) -> Dictionary:
	var advantage: int = 2 if ADVANTAGE.get(attacker.kind, "") == target.kind else 0
	var elevation: int = 1 if ground(attacker.pos) == "hill" and ground(target.pos) != "hill" else 0
	var charge: int = 1 if attacker.kind == "cavalry" and attacker.side == active_side and int(attacker.get("last_move_distance", 0)) >= 3 else 0
	var close_penalty: int = 1 if attacker.kind == "archer" and distance(attacker.pos, target.pos) == 1 else 0
	var terrain_bonus: int = terrain_defense(target)
	var aura: int = aura_defense(target)
	var stance: int = 1 if target.kind == "spear" and int(target.get("last_move_distance", 0)) == 0 else 0
	var total_armor: int = int(target.defense) + terrain_bonus + aura + stance
	var pierce: int = mini(1, total_armor) if attacker.kind == "mage" else 0
	return {"damage": maxi(1, int(attacker.atk) + advantage + elevation + charge - close_penalty - total_armor + pierce),
		"base": int(attacker.atk), "advantage": advantage, "elevation": elevation, "charge": charge,
		"close_penalty": close_penalty, "armor": int(target.defense), "terrain": terrain_bonus,
		"aura": aura, "stance": stance, "pierce": pierce}

func fire_damage(amount: int) -> int:
	return maxi(1, amount + (1 if weather == "sun" else (-1 if weather == "rain" else 0)))

func spell_damage(card: Dictionary, side: int) -> int:
	var bonus: int = 1 if hero(side).id == "pyromancer" and not players[side].spell_boost_used else 0
	return fire_damage(int(card.amount) + bonus)

func hero_targets(side: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if commander(side).is_empty(): return result
	var effect: String = hero(side).effect
	if effect == "renewal": return [Vector2i(-1, -1)]
	for unit: Dictionary in units:
		if distance(commander(side).pos, unit.pos) > hero_cast_range(side): continue
		if effect == "firestrike" and unit.side != side: result.append(unit.pos)
		if effect == "blessing" and unit.side == side and (unit.shield < 5 or unit.hp < unit.max_hp): result.append(unit.pos)
	return result

func get_legal_actions(side: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if winner != -1 or side != active_side:
		return result
	for instance: Dictionary in players[side].hand:
		var card: Dictionary = definition(instance.card_id)
		if card.cost <= players[side].mana:
			for cell: Vector2i in card_targets(instance.uid, side):
				result.append({"type": "play", "card_uid": instance.uid, "target": cell})
	for unit: Dictionary in units:
		if unit.side != side:
			continue
		for cell: Vector2i in movement_cells(unit):
			result.append({"type": "move", "unit_id": unit.id, "target": cell})
		for cell: Vector2i in attack_targets(unit):
			result.append({"type": "attack", "unit_id": unit.id, "target": cell})
		for cell: Vector2i in skill_targets(unit):
			result.append({"type": "unit_skill", "unit_id": unit.id, "target": cell})
	if players[side].skill_cooldown == 0 and players[side].mana >= hero(side).cost:
		for cell: Vector2i in hero_targets(side): result.append({"type": "hero", "target": cell})
	result.append({"type": "end_turn"})
	return result

func apply_action(action: Dictionary) -> Dictionary:
	if winner != -1:
		return _error("对局已经结束，请重新开始。")
	var action_type: String = str(action.get("type", ""))
	if action_type == "end_turn":
		return end_turn()
	if not action.get("target") is Vector2i:
		return _error("请先选择一个有效目标。")
	var cell: Vector2i = action.target
	match action_type:
		"unit_skill":
			var caster: Dictionary = get_unit(int(action.get("unit_id", -1)))
			if caster.is_empty() or not skill_targets(caster).has(cell): return _error("技能不可用：检查己方单位、新兵/行动状态、1点法力、次数与目标范围。")
			players[active_side].mana -= int(unit_skill(caster).cost)
			_resolve_unit_skill(caster, cell)
		"hero":
			var leader_hero: Dictionary = hero(active_side)
			if players[active_side].skill_cooldown > 0: return _error("指挥官技能仍在冷却。")
			if players[active_side].mana < leader_hero.cost: return _error("法力不足，无法发动指挥官技能。")
			if not hero_targets(active_side).has(cell): return _error("目标超出指挥官技能范围，或不符合技能条件。")
			players[active_side].mana -= int(leader_hero.cost)
			players[active_side].skill_cooldown = int(leader_hero.cooldown)
			_resolve_hero(leader_hero, cell)
			_record("%s发动「%s」。" % [leader_hero.name, leader_hero.skill])
		"play":
			var instance: Dictionary = hand_card(active_side, int(action.get("card_uid", -1)))
			if instance.is_empty(): return _error("这张牌不在当前玩家手中。")
			var card: Dictionary = definition(instance.card_id)
			if card.cost > players[active_side].mana: return _error("法力不足，无法使用这张牌。")
			if not card_targets(instance.uid, active_side).has(cell):
				return _error("部署需紧邻己方部队的空地（上下左右），最多 6 支部队。" if card.type == "unit" else "目标需在友军3格内（法师4格），且满足卡牌条件；换位限指挥官3格。")
			# All validation happens before resource payment or zone mutation.
			players[active_side].mana -= int(card.cost)
			players[active_side].hand.erase(instance)
			if card.type == "unit":
				var unit_id: int = _spawn(card, cell, active_side)
				instance["unit_id"] = unit_id
				units.back()["card"] = instance
			else:
				players[active_side].discard.append(instance)
				_resolve_spell(card, cell)
			_record("%s使用了「%s」。" % [side_name(active_side), card.name])
		"move", "attack":
			var unit: Dictionary = get_unit(int(action.get("unit_id", -1)))
			if unit.is_empty() or unit.side != active_side: return _error("请选择己方部队。")
			if action_type == "move":
				if not movement_cells(unit).has(cell): return _error("无法移动至此处：检查行动次数、阻挡和移动范围。")
				unit.last_move_distance = int(unit.get("last_move_distance", 0)) + movement_path(unit, cell).size() - 1
				unit.pos = cell
				unit.moved = true
				_record("%s推进至 %s。" % [unit.name, cell_name(cell)])
			else:
				if not attack_targets(unit).has(cell): return _error("无法攻击此目标：检查射程或本回合行动状态。")
				_resolve_attack(unit, unit_at(cell))
		_:
			return _error("未知的操作。")
	_cleanup()
	_check_winner()
	changed.emit()
	return {"ok": true, "message": log_lines.back()}

func end_turn() -> Dictionary:
	if winner != -1:
		return _error("对局已经结束。")
	active_side = 1 - active_side
	turn += 1
	_start_turn()
	changed.emit()
	return {"ok": true, "message": "%s的回合" % side_name(active_side)}

func advance_clock(seconds: float) -> bool:
	if winner != -1 or seconds <= 0 or not is_finite(seconds): return false
	time_remaining = maxf(0, time_remaining - seconds)
	if time_remaining > 0: return false
	_record("%s行动时间用尽，自动结束回合。" % side_name(active_side))
	end_turn()
	return true

func _start_turn() -> void:
	time_remaining = turn_time_limit
	if weather_remaining > 0:
		weather_remaining -= 1
		if weather_remaining == 0:
			_record("%s散去，战场恢复晴朗。" % WEATHER[weather].name)
			weather = "clear"
	var player: Dictionary = players[active_side]
	player.skill_cooldown = maxi(0, int(player.skill_cooldown) - 1)
	player.spell_boost_used = false
	player.max_mana = mini(10, int(player.max_mana) + 1)
	player.mana = player.max_mana
	for unit: Dictionary in units:
		if unit.side == active_side:
			unit["skill_used"] = false
			unit["guarding"] = false
			unit.moved = false
			unit.attacked = false
			unit.summoning = false
			unit.last_move_distance = 0
			unit.rooted_turns = maxi(0, int(unit.get("rooted_turns", 0)) - 1)
			if ground(unit.pos) == "ruins" or (hero(active_side).id == "grove" and ground(unit.pos) == "forest"):
				unit.hp = mini(int(unit.max_hp), int(unit.hp) + 1)
	for healer: Dictionary in units:
		if healer.side == active_side and healer.kind == "healer":
			for target: Dictionary in units:
				if target.side == active_side and distance(healer.pos, target.pos) <= 1:
					target.hp = mini(int(target.max_hp), int(target.hp) + (2 if weather == "sun" else 1))
	_draw(active_side, 1)
	_cleanup()
	_check_winner()
	_record("%s回合 · 法力 %d/%d" % [side_name(active_side), player.mana, player.max_mana])

func _draw(side: int, amount: int) -> void:
	var player: Dictionary = players[side]
	for draw_index: int in range(amount):
		if player.deck.is_empty():
			player.fatigue += 1
			var leader: Dictionary = commander(side)
			if not leader.is_empty(): _hurt(leader, player.fatigue)
			_record("%s牌库耗尽，受到 %d 点疲劳伤害。" % [side_name(side), player.fatigue])
			continue
		var card: Dictionary = player.deck.pop_back()
		if player.hand.size() >= HAND_LIMIT:
			player.discard.append(card)
			_record("%s手牌已满，弃置「%s」。" % [side_name(side), definition(card.card_id).name])
		else:
			player.hand.append(card)

func _spawn(card: Dictionary, cell: Vector2i, side: int) -> int:
	var unit_id: int = _id()
	units.append({"id": unit_id, "side": side, "name": card.name, "kind": card.kind,
		"short": card.short, "hp": card.hp, "max_hp": card.hp, "atk": card.atk,
		"defense": card.defense, "move": card.move, "range": card.range,
		"shield": 0, "pos": cell, "moved": true, "attacked": true, "summoning": true, "last_move_distance": 0, "rooted_turns": 0, "skill_used": false, "guarding": false})
	return unit_id

func _resolve_spell(card: Dictionary, cell: Vector2i) -> void:
	var target: Dictionary = unit_at(cell)
	match String(card.effect):
		"damage": _hurt(target, spell_damage(card, active_side))
		"area":
			for unit: Dictionary in units:
				if unit.side != active_side and distance(unit.pos, cell) <= 1:
					_hurt(unit, spell_damage(card, active_side))
		"heal": target.hp = mini(int(target.max_hp), int(target.hp) + int(card.amount))
		"shield": target.shield = card.amount
		"march": target.moved = false
		"draw": _draw(active_side, card.amount)
		"mana": players[active_side].mana = mini(10, int(players[active_side].mana) + int(card.amount))
		"weather":
			weather = card.weather
			weather_remaining = int(card.duration)
			_record("环境变为%s，持续 %d 个行动回合（双方回合都计时）。" % [WEATHER[weather].name, weather_remaining])
		"terrain":
			terrain[cell] = card.terrain
			_record("%s变为%s。" % [cell_name(cell), TERRAIN[String(card.terrain)].name])
		"repulse":
			var destination: Vector2i = repulse_destination(target, active_side)
			_hurt(target, int(card.amount) + (1 if destination == target.pos else 0))
			if target.hp > 0 and destination != target.pos:
				target.pos = destination
				_record("%s被击退到%s。" % [target.name, cell_name(destination)])
		"root": target.rooted_turns = 2
		"dispel": target.shield = 0
		"exchange":
			var leader: Dictionary = commander(active_side)
			var previous: Vector2i = leader.pos
			leader.pos = target.pos
			target.pos = previous
		"onslaught": target.attacked = false
		"clear_weather":
			weather = "clear"
			weather_remaining = 0
			_record("天气被驱散，战场恢复晴朗。")
	if card.effect in ["damage", "area"]: players[active_side].spell_boost_used = true

func _resolve_hero(leader_hero: Dictionary, cell: Vector2i) -> void:
	var target: Dictionary = unit_at(cell)
	match String(leader_hero.effect):
		"blessing":
			target.hp = mini(int(target.max_hp), int(target.hp) + 2)
			target.shield = mini(5, int(target.shield) + 3)
		"firestrike": _hurt(target, fire_damage(int(leader_hero.amount)))
		"renewal":
			for unit: Dictionary in units:
				if unit.side == active_side and distance(commander(active_side).pos, unit.pos) <= hero_cast_range(active_side): unit.hp = mini(int(unit.max_hp), int(unit.hp) + 2)
			_draw(active_side, 1)

func _hurt(target: Dictionary, amount: int) -> void:
	var absorbed: int = mini(int(target.shield), amount)
	target.shield -= absorbed
	target.hp -= amount - absorbed

func _cleanup() -> void:
	for index: int in range(units.size() - 1, -1, -1):
		var unit: Dictionary = units[index]
		if unit.hp <= 0:
			if unit.has("card"): players[unit.side].discard.append(unit.card)
			_record("%s倒下了。" % unit.name)
			units.remove_at(index)

func _check_winner() -> void:
	var blue_alive: bool = not commander(0).is_empty()
	var red_alive: bool = not commander(1).is_empty()
	if blue_alive and red_alive: return
	winner = 2 if not blue_alive and not red_alive else (0 if blue_alive else 1)
	_record("双方指挥官同时倒下，平局。" if winner == 2 else "%s取得胜利！" % side_name(winner))

func _record(message: String) -> void:
	log_lines.append(message)
	if log_lines.size() > 80: log_lines.pop_front()

func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

func side_name(side: int) -> String:
	return "苍蓝军团" if side == 0 else "赤曜军团"

func cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), height - cell.y]
