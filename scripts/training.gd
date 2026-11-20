extends RefCounted
## Guided exercises use the regular rules after their starting positions are laid out.

const Model = preload("res://scripts/battle.gd")
const DEPLOY := Vector2i(5, 8)
const SPEAR_PATH := Vector2i(5, 7)
const CAVALRY := Vector2i(5, 6)
const GUARD := Vector2i(6, 7)
const PROTECTED := Vector2i(6, 6)
const ENEMY_ARCHER := Vector2i(7, 6)
const MAGE_START := Vector2i(6, 8)
const MAGE_FINISH := Vector2i(6, 7)
const FIRE_CENTER := Vector2i(6, 3)
const FIRE_EDGE := Vector2i(7, 4)
const FIRE_SAFE := Vector2i(8, 4)
const COUNTER_CENTER := Vector2i(6, 6)
const COUNTER_ARCHER := Vector2i(7, 5)
const COUNTER_MAGE := Vector2i(6, 2)
const COUNTER_SPELL: String = "last_hearth"
const ORDER_CENTER := Vector2i(6, 5)
const RIDER_START := Vector2i(4, 4)
const RIDER_DEST := Vector2i(7, 4)
const SNARE_SITES := [Vector2i(5, 4), Vector2i(6, 4)]
const BRIDGE_GUARD := Vector2i(3, 6)
const BRIDGE_ARCHER := Vector2i(5, 3)
const BRIDGE_POST := Vector2i(3, 3)
const MEDIC_SITES := [Vector2i(2, 6), Vector2i(3, 5)]
const LESSONS: Array[Dictionary] = [
	{"name": "部署、移动与克制", "steps": [
		{"type": "play", "card": "spear", "target": DEPLOY, "text": "选中手牌「铁壁枪卫」，部署到指挥官前方标出的空格。新部队必须贴着友军部署。"},
		{"type": "end_turn", "text": "新部署的枪卫要到下次己方回合才能行动。点击「结束回合」，让守军按演练顺序交还回合。"},
		{"type": "move", "from": DEPLOY, "target": SPEAR_PATH, "text": "先点选枪卫，再走到标出的空格。移动会消耗地形费用，攻击后就不能移动了。"},
		{"type": "attack", "from": SPEAR_PATH, "target": CAVALRY, "text": "把鼠标移到林中的骑士上查看攻防，再点击攻击。枪兵克骑兵，加 2 伤害；敌人脚下的森林提供 1 防御。"},
	], "done": "枪卫已攻击骑士，骑士存活且射程够近，立即反击。下一课练习如何替友军接下攻击。"},
	{"name": "援护与手牌伏设", "steps": [
		{"type": "play", "card": "oath_ward", "target": GUARD, "text": "选中手牌「回誓屏障」，伏设在标出的枪卫身上。陷阱随保护对象移动，等到受击才触发。"},
		{"type": "unit_skill", "from": GUARD, "target": GUARD, "text": "选中枪卫，点「铁壁援护」或按 Q，再点枪卫所在格。援护只替正交相邻友军承受普通攻击。"},
		{"type": "end_turn", "target_hint": PROTECTED, "text": "结束回合。对面的弓手将瞄准标出的步兵，观察真正接下这箭的人和伏牌触发。"},
	], "done": "枪卫替相邻步兵承伤，并在受击前获得陷阱的护盾。敌方只能看到伏设数量，无法预知具体牌。"},
	{"name": "施法范围与溅射", "steps": [
		{"type": "move", "from": MAGE_START, "target": MAGE_FINISH, "text": "选中己方法师，前进一步。普通友军提供 3 格施法范围，法师提供 4 格。下方手牌已为练习备好 10 点法力。"},
		{"type": "play", "card": "last_hearth", "target": FIRE_CENTER, "text": "选中「天炉坠火」，悬停标出的中心检查扩散范围，再点击施法。超出中心两格的枪卫不会受伤。"},
	], "done": "火焰同时打中中心和边缘的敌军，最外侧枪卫安全。正式对局每个己方回合增加 1 点法力上限，最多 10 点。"},
	{"name": "散阵与术击反制", "steps": [
		{"type": "play", "card": "quiet_veil", "target": COUNTER_CENTER, "show_blast": true, "text": "守军法师要向红框中心施放「天炉坠火」。把「湿帷潜护」从手牌伏设到中心的受伤枪卫身上。"},
		{"type": "move", "from": COUNTER_ARCHER, "outside_blast": true, "text": "选中高地旁的暮林游侠，走到红框外任意一个青色可移动格。距离中心超过两格就能躲开这次溅射。"},
		{"type": "end_turn", "target_hint": COUNTER_CENTER, "show_blast": true, "text": "结束回合。观察伏设如何在术击前救护枪卫，以及游侠离开范围后的生命。"},
		{"type": "play", "card": "recall_writ", "target": COUNTER_CENTER, "text": "枪卫撑过了这次攻击。用「折回哨令」把他收回手牌，给下一次部署腾出位置。"},
		{"type": "play", "card": "spear", "outside_blast": true, "text": "用手中刚收回的铁壁枪卫，选红框外任意合法增援格重新部署。"},
	], "done": "游侠避开了溅射，枪卫重新部署时恢复满生命，到下次己方回合才能行动。对手有重术时，可以提前分散与保护关键部队。"},
	{"name": "绊索与落锤", "map": "citadel", "rider_route": true, "steps": [
		{"type": "play", "card": "hollow_hammer", "target": ORDER_CENTER, "text": "把八费「空锤待落」标在 G5。看清蓝色十字，锤要到下个己方回合才落。"},
		{"type": "play", "card": "anchor_snare", "sites": SNARE_SITES, "text": "铁骑将沿箭头从 E6 直奔 H6。在 F6 或 G6 伏下最后两费的「锚索伏阵」。你想让它停在哪一格？"},
		{"type": "end_turn", "text": "结束回合，让铁骑走进绊索。留意它停下的位置，以及落锤时还剩多少护盾和生命。"},
	], "done": "可点「重练本节」，把同一根绊索往前或往后移一格。"},
	{"name": "桥头的医师", "map": "rivergate", "archer_watch": true, "steps": [
		{"type": "play", "card": "healer", "sites": MEDIC_SITES, "text": "枪卫守在 D4，身边有两处可增援。选中「晨光医师」，比较岸边 C4 和桥上 D5 的敌军射程，再选落点。按 V 可开关射程图。"},
		{"type": "end_turn", "text": "结束回合。北岸游侠会从 F7 赶到 D7。他优先瞄准医师，够不到才会转向枪卫。"},
	], "done": "两处落点都能照应枪卫。桥上的医师还能把下一次增援接到 D6。"},
]

var lesson: int = 0
var step_index: int = 0
var scripted_spell_uid: int = -1
var bridge_target: String = ""
var resolving: bool = false

func prepare(index: int) -> Battle:
	lesson = clampi(index, 0, LESSONS.size() - 1)
	step_index = 0
	resolving = false
	scripted_spell_uid = -1
	bridge_target = ""
	var defender: String = "warden" if lesson == 3 else "pyromancer"
	var battle := Model.new(4211 + lesson, LESSONS[lesson].get("map", "greenwood"), "warden", defender)
	battle.set_commander_identity(1, "演练守军", defender)
	battle.players[0].discard.append_array(battle.players[0].hand)
	battle.players[0].hand.clear()
	match lesson:
		0:
			_supply(battle, "spear", 0)
			_place(battle, "cavalry", CAVALRY, 1)
			_set_mana(battle, 2)
		1:
			_supply(battle, "oath_ward", 0)
			_place(battle, "spear", GUARD, 0)
			_place(battle, "sword", PROTECTED, 0)
			_place(battle, "archer", ENEMY_ARCHER, 1)
			_set_mana(battle, 4)
		2:
			_supply(battle, "last_hearth", 0)
			_place(battle, "scribe_warden", MAGE_START, 0)
			_place(battle, "bronze_watch", FIRE_CENTER, 1).shield = 2
			_place(battle, "breakwater_guard", FIRE_EDGE, 1)
			_place(battle, "spear", FIRE_SAFE, 1)
			_set_mana(battle, 10)
		3:
			_supply(battle, "quiet_veil", 0)
			_supply(battle, "recall_writ", 0)
			_place(battle, "spear", COUNTER_CENTER, 0).hp = 4
			_place(battle, "archer", COUNTER_ARCHER, 0)
			_place(battle, "mage", COUNTER_MAGE, 1)
			scripted_spell_uid = _supply(battle, COUNTER_SPELL, 1).uid
			battle.players[1].max_mana = 9
			_set_mana(battle, 4)
		4:
			_supply(battle, "hollow_hammer", 0)
			_supply(battle, "anchor_snare", 0)
			_place(battle, "mage", Vector2i(5, 6), 0)
			var rider := _place(battle, "carriage_cloak", RIDER_START, 1)
			rider.shield = battle.definition("carriage_cloak").entry.shield
			_set_mana(battle, 10)
		5:
			_supply(battle, "healer", 0)
			_place(battle, "spear", BRIDGE_GUARD, 0)
			_place(battle, "archer", BRIDGE_ARCHER, 1)
			_set_mana(battle, 3)
	return battle

func current() -> Dictionary:
	return {} if complete() else LESSONS[lesson].steps[step_index]

func complete() -> bool:
	return step_index >= LESSONS[lesson].steps.size()

func allows(battle: Battle, action: Dictionary) -> bool:
	var step: Dictionary = current()
	if step.is_empty() or action.type != step.type: return false
	if step.has("target") and action.get("target") != step.target: return false
	if step.has("sites") and not step.sites.has(action.get("target")): return false
	if step.get("outside_blast", false):
		var cell: Variant = action.get("target")
		if not cell is Vector2i or not outside_blast(battle, cell): return false
	if step.has("card"):
		var card: Dictionary = battle.hand_card(0, int(action.get("card_uid", -1)))
		return card.get("card_id", "") == step.card
	if step.has("from"):
		var unit: Dictionary = battle.get_unit(int(action.get("unit_id", -1)))
		return unit.get("pos") == step.from
	return true

func outside_blast(battle: Battle, cell: Vector2i) -> bool:
	return battle.inside(cell) and battle.distance(cell, COUNTER_CENTER) > int(battle.definition(COUNTER_SPELL).radius)

func warning_cells(battle: Battle) -> Array[Vector2i]:
	var step: Dictionary = current()
	if not (step.get("show_blast", false) or step.get("outside_blast", false)): return []
	return battle.Formation.footprint(battle, COUNTER_CENTER, int(battle.definition(COUNTER_SPELL).radius))

func announced_route(battle: Battle) -> Array[Vector2i]:
	if not LESSONS[lesson].get("rider_route", false) or complete() or battle.active_side != 0: return []
	var rider: Dictionary = battle.unit_at(RIDER_START)
	if rider.is_empty(): return []
	return battle.movement_path(rider, RIDER_DEST)

func conclusion(battle: Battle) -> String:
	var text: String = LESSONS[lesson].done
	if LESSONS[lesson].get("archer_watch", false):
		for site: Vector2i in MEDIC_SITES:
			var medic := battle.unit_at(site)
			if medic.is_empty(): continue
			return "游侠在 D7 射中了%s。%s 的医师经过回合治疗，现有 %d/%d 生命。%s" % [bridge_target, battle.cell_name(site), medic.hp, medic.max_hp, text]
	if not LESSONS[lesson].get("rider_route", false) or battle.last_order_event.is_empty(): return text
	for pos: Vector2i in SNARE_SITES:
		var rider: Dictionary = battle.unit_at(pos)
		if not rider.is_empty() and rider.side == 1:
			return "铁骑在 %s 被绊停。落锤%s。铁骑现有 %d 生命、%d 护盾。%s" % [battle.cell_name(pos), battle.last_order_event.result, rider.hp, rider.shield, text]
	return text

func enemy_response(battle: Battle) -> Dictionary:
	match lesson:
		1: return {"type": "attack", "unit_id": battle.unit_at(ENEMY_ARCHER).id, "target": PROTECTED}
		3: return {"type": "play", "card_uid": scripted_spell_uid, "target": COUNTER_CENTER}
		4: return {"type": "move", "unit_id": battle.unit_at(RIDER_START).id, "target": RIDER_DEST}
		5: return {"type": "move", "unit_id": battle.unit_at(BRIDGE_ARCHER).id, "target": BRIDGE_POST}
	return {}

func bridge_shot(battle: Battle) -> Dictionary:
	var archer := battle.unit_at(BRIDGE_POST)
	var targets := battle.attack_targets(archer)
	for site: Vector2i in MEDIC_SITES:
		if targets.has(site): return {"type": "attack", "unit_id": archer.id, "target": site}
	return {"type": "attack", "unit_id": archer.id, "target": BRIDGE_GUARD}

func _set_mana(battle: Battle, amount: int) -> void:
	battle.players[0].mana = amount
	battle.players[0].max_mana = amount

func _supply(battle: Battle, card_id: String, side: int) -> Dictionary:
	var player: Dictionary = battle.players[side]
	for instance: Dictionary in player.deck:
		if instance.card_id != card_id: continue
		player.deck.erase(instance)
		player.hand.append(instance)
		return instance
	battle.add_generated_card(side, card_id)
	return player.hand.back()

func _place(battle: Battle, card_id: String, cell: Vector2i, side: int) -> Dictionary:
	var instance: Dictionary = _supply(battle, card_id, side)
	battle.players[side].hand.erase(instance)
	var unit_id: int = battle._spawn(battle.definition(card_id), cell, side)
	instance["unit_id"] = unit_id
	var unit: Dictionary = battle.get_unit(unit_id)
	unit.merge({"card": instance, "moved": false, "attacked": false, "summoning": false}, true)
	return unit
