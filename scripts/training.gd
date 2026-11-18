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
]

var lesson: int = 0
var step_index: int = 0

func prepare(index: int) -> Battle:
	lesson = clampi(index, 0, LESSONS.size() - 1)
	step_index = 0
	var battle := Model.new(4211 + lesson, "greenwood")
	battle.set_commander_identity(1, "演练守军", "pyromancer")
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
	return battle

func current() -> Dictionary:
	return {} if complete() else LESSONS[lesson].steps[step_index]

func complete() -> bool:
	return step_index >= LESSONS[lesson].steps.size()

func allows(battle: Battle, action: Dictionary) -> bool:
	var step: Dictionary = current()
	if step.is_empty() or action.type != step.type: return false
	if step.has("target") and action.get("target") != step.target: return false
	if step.has("card"):
		var card: Dictionary = battle.hand_card(0, int(action.get("card_uid", -1)))
		return card.get("card_id", "") == step.card
	if step.has("from"):
		var unit: Dictionary = battle.get_unit(int(action.get("unit_id", -1)))
		return unit.get("pos") == step.from
	return true

func enemy_response(battle: Battle) -> Dictionary:
	if lesson != 1: return {}
	return {"type": "attack", "unit_id": battle.unit_at(ENEMY_ARCHER).id, "target": PROTECTED}

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
