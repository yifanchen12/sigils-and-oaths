class_name EffectForecast
extends RefCounted
## Read-only, numeric target previews. Legality and damage values come from Battle.

static func predict(battle: Battle, action: Dictionary) -> Dictionary:
	if battle.winner != -1 or not action.get("target") is Vector2i: return {}
	var cell: Vector2i = action.target
	var target: Dictionary = battle.unit_at(cell)
	var title: String = ""
	var effect: String = ""
	var amount: int = 0
	var side: int = battle.active_side
	match str(action.get("type", "")):
		"unit_skill":
			var caster: Dictionary = battle.get_unit(int(action.get("unit_id", -1)))
			if caster.is_empty() or not battle.skill_targets(caster).has(cell): return {}
			title = battle.unit_skill(caster).name
			match String(caster.kind):
				"mage": effect = "damage"; amount = battle.fire_damage(3)
				"healer": effect = "heal"; amount = 3
				"sword": effect = "shield"; amount = 3
				_: return {}
		"play":
			var instance: Dictionary = battle.hand_card(side, int(action.get("card_uid", -1)))
			if instance.is_empty(): return {}
			var card: Dictionary = battle.definition(instance.card_id)
			if card.cost > battle.players[side].mana or not battle.card_targets(instance.uid, side).has(cell): return {}
			title = card.name
			effect = str(card.get("effect", ""))
			if effect not in ["damage", "area", "heal", "shield", "dispel", "repulse"]: return {}
			if effect in ["damage", "area"]: amount = battle.spell_damage(card, side)
			elif effect == "repulse": amount = int(card.amount) + (1 if battle.repulse_destination(target, side) == cell else 0)
			else: amount = int(card.get("amount", 0))
		"hero":
			var hero: Dictionary = battle.hero(side)
			if battle.players[side].skill_cooldown > 0 or battle.players[side].mana < hero.cost or not battle.hero_targets(side).has(cell): return {}
			title = hero.skill
			effect = "damage" if hero.effect == "firestrike" else str(hero.effect)
			if effect == "damage": amount = battle.fire_damage(int(hero.amount))
			elif effect != "blessing": return {}
		_: return {}
	if target.is_empty(): return {}
	var changes: Array[Dictionary] = []
	if effect == "area":
		for victim: Dictionary in battle.units:
			if victim.side != side and battle.distance(victim.pos, cell) <= 1: changes.append(_change(victim, "damage", amount))
	else:
		var change: Dictionary = _change(target, effect, amount)
		if effect == "repulse":
			change["position_after"] = battle.repulse_destination(target, side) if change.hp_after > 0 else target.pos
		changes.append(change)
	var note: String = ""
	match effect:
		"damage", "area": note = "法术无视防御，护盾先抵挡；不触发援护或反击。"
		"heal": note = "恢复不超过生命上限；不会恢复目标的行动次数。"
		"shield": note = "护盾变为%d，不叠加。" % amount
		"blessing": note = "恢复2生命、增加3护盾；护盾上限5。"
		"dispel": note = "仅移除护盾，不造成生命伤害。"
		"repulse": note = "退路受阻时增加1伤害；击破后不再位移。"
	if str(action.get("type", "")) == "unit_skill": note += "\n消耗1法力，结束施术部队的行动。"
	return {"title": title, "effect": effect, "amount": amount, "target_id": target.id, "changes": changes, "note": note}

static func _change(unit: Dictionary, effect: String, amount: int) -> Dictionary:
	var hp: int = unit.hp
	var shield: int = unit.shield
	if effect in ["damage", "area", "repulse"]:
		hp = maxi(0, hp - maxi(0, amount - shield))
		shield = maxi(0, shield - amount)
	elif effect == "heal": hp = mini(int(unit.max_hp), hp + amount)
	elif effect == "shield": shield = amount
	elif effect == "dispel": shield = 0
	elif effect == "blessing":
		hp = mini(int(unit.max_hp), hp + 2)
		shield = mini(5, shield + 3)
	return {"unit_id": unit.id, "name": unit.name, "position_before": unit.pos, "hp_before": unit.hp, "hp_after": hp,
		"shield_before": unit.shield, "shield_after": shield, "hp_loss": maxi(0, int(unit.hp) - hp),
		"healing": maxi(0, hp - int(unit.hp)), "shield_delta": shield - int(unit.shield)}

static func describe(forecast: Dictionary, battle: Battle, compact: bool = false) -> String:
	var lines := PackedStringArray()
	if forecast.effect in ["damage", "area"]: lines.append("本次火焰伤害 %d\n" % forecast.amount)
	if forecast.effect == "area": lines.append("范围命中 %d 名敌军\n" % forecast.changes.size())
	for change: Dictionary in forecast.changes:
		var label: String = "%s · %s" % [battle.cell_name(change.position_before), change.name]
		lines.append(("%s  %d → %d" if compact else "%s\n生命 %d → %d") % [label, change.hp_before, change.hp_after])
		if change.shield_before != change.shield_after: lines.append("护盾 %d → %d" % [change.shield_before, change.shield_after])
		if change.has("position_after"): lines.append("结算位置 · %s" % battle.cell_name(change.position_after))
		if change.hp_after == 0: lines.append("预计击破")
		if not compact: lines.append("")
	lines.append(forecast.note)
	lines.append("\n点击高亮目标确认。")
	return "\n".join(lines)

static func hint(forecast: Dictionary) -> String:
	var loss: int = 0
	var healing: int = 0
	var shield: int = 0
	for change: Dictionary in forecast.changes:
		loss += int(change.hp_loss)
		healing += int(change.healing)
		shield += int(change.shield_delta)
	var values := PackedStringArray()
	if loss > 0: values.append("生命损失%d" % loss)
	if healing > 0: values.append("恢复%d生命" % healing)
	if shield > 0: values.append("增加%d护盾" % shield)
	elif shield < 0: values.append("减少%d护盾" % -shield)
	if values.is_empty(): values.append("不改变生命与护盾")
	return "%s预估 · %d个目标 · %s · 点击确认，右键取消。" % [forecast.title, forecast.changes.size(), " / ".join(values)]
