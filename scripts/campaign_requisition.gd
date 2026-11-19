extends RefCounted
## Curated scenario choices exchange one real opening-hand instance.

const Model = preload("res://scripts/battle.gd")

static func allows(setup: Dictionary, card_id: String) -> bool:
	return card_id.is_empty() or setup.get("requisition", {}).get("offers", []).has(card_id)

static func counts_for(setup: Dictionary, card_id: String) -> Dictionary:
	var base: Dictionary = Model.DECKS.find(setup.deck).cards
	if card_id.is_empty(): return base.duplicate()
	var counts: Dictionary = base.duplicate()
	var outgoing: String = setup.requisition.replace
	counts[outgoing] = int(counts[outgoing]) - 1
	if counts[outgoing] == 0: counts.erase(outgoing)
	counts[card_id] = int(counts.get(card_id, 0)) + 1
	return counts

static func validate_setup(setup: Dictionary) -> String:
	if not setup.has("requisition"): return ""
	var spec: Variant = setup.requisition
	if not spec is Dictionary or not spec.get("replace") is String or not spec.get("offers") is Array:
		return "关卡的战前军需格式无效。"
	if not Model.DECKS.find(setup.deck).cards.has(spec.replace): return "原始军势没有待替换的军需牌。"
	if spec.offers.is_empty() or spec.offers.size() > 3: return "战前军需需要一至三种换牌选项。"
	var offered: Array[String] = []
	for card_id: Variant in spec.offers:
		if not card_id is String or card_id.is_empty() or card_id == spec.replace or offered.has(card_id):
			return "战前军需选项无效或重复。"
		var issue: String = Model.DECKS.validate_counts(counts_for(setup, card_id), Model.CATALOG.cards)
		if not issue.is_empty(): return "战前军需军势无效：" + issue
		offered.append(card_id)
	return ""

static func apply(battle: RefCounted, setup: Dictionary, card_id: String) -> Dictionary:
	if card_id.is_empty(): return {"ok": true}
	if not allows(setup, card_id) or battle.turn != 1 or battle.active_side != 0 or battle.deck(0).id != setup.deck:
		return {"ok": false, "message": "当前部队无法应用这项战前军需。"}
	var outgoing: String = setup.requisition.replace
	var replacements: Dictionary = counts_for(setup, card_id)
	var issue: String = Model.DECKS.validate_counts(replacements, Model.CATALOG.cards)
	if not issue.is_empty(): return {"ok": false, "message": issue}
	for instance: Dictionary in battle.players[0].hand:
		if instance.card_id != outgoing: continue
		instance.card_id = card_id
		battle.players[0].deck_id = "custom"
		battle.players[0].deck_definition = {"id": "custom", "name": "自定义军势", "description": "本关战前军需。", "cards": Model.DECKS.canonical_counts(replacements, Model.CATALOG.cards)}
		battle._record("战前军需 · 「%s」替下「%s」。" % [battle.definition(card_id).name, battle.definition(outgoing).name])
		return {"ok": true}
	return {"ok": false, "message": "这次开局的手牌中没有指定的待换卡牌。"}
