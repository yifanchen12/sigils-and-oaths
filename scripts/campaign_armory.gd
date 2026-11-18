extends RefCounted
## Campaign loadouts replace stock deck instances after the authored opener.

const Model = preload("res://scripts/battle.gd")
const Requisition = preload("res://scripts/campaign_requisition.gd")
const SLOTS: Array[Dictionary] = [
	{"id": "vanguard", "name": "先遣补给", "min_cost": 1, "max_cost": 3, "unlock_after": 2, "draw": 2},
	{"id": "company", "name": "中坚军备", "min_cost": 4, "max_cost": 6, "unlock_after": 4, "draw": 5},
	{"id": "reserve", "name": "压阵重装", "min_cost": 7, "max_cost": 10, "unlock_after": 7, "draw": 8},
]

static func unlocked_count(completed: int) -> int:
	var count: int = 0
	for slot: Dictionary in SLOTS:
		if completed >= int(slot.unlock_after): count += 1
	return count

static func _fits(slot: Dictionary, card: Dictionary) -> bool:
	return (card.get("set_id", "") == "moorings" and not card.get("generated_only", false)
		and int(card.cost) >= int(slot.min_cost) and int(card.cost) <= int(slot.max_cost))

static func options(slot: Dictionary) -> Array[Dictionary]:
	var cards: Array[Dictionary] = Model.CATALOG.cards.filter(func(card: Dictionary) -> bool: return _fits(slot, card))
	cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.cost) < int(b.cost) if a.cost != b.cost else str(a.id) < str(b.id))
	return cards

static func validate(picks: Variant, completed: int) -> String:
	if not picks is Dictionary: return "军备编成格式无效。"
	var recognized: int = 0
	for slot: Dictionary in SLOTS:
		if not picks.has(slot.id): continue
		recognized += 1
		var card_id: Variant = picks[slot.id]
		if completed < int(slot.unlock_after): return "「%s」尚未解锁。" % slot.name
		if not card_id is String or not _fits(slot, Model.CATALOG.find(card_id)):
			return "所选卡牌不属于「%s」。" % slot.name
	return "" if recognized == picks.size() else "军备包含未知的补给位。"

static func prepare(setup: Dictionary, requisition: String, picks: Dictionary) -> Dictionary:
	var battle := Model.new(int(setup.seed), setup.map, setup.hero, setup.enemy_class, setup.deck, setup.enemy_deck, 90)
	var requisitioned: Dictionary = Requisition.apply(battle, setup, requisition)
	if not requisitioned.ok: return requisitioned
	if picks.is_empty(): return {"ok": true, "battle": battle, "swaps": {}}
	var problem: String = validate(picks, int(SLOTS.back().unlock_after))
	if not problem.is_empty(): return {"ok": false, "message": problem}
	var player: Dictionary = battle.players[0]
	var remaining: Array = player.deck.duplicate(true)
	var counts: Dictionary = battle.deck(0).cards.duplicate()
	var reserved: Array[Dictionary] = []
	var swaps: Dictionary = {}
	for slot: Dictionary in SLOTS:
		var card_id: String = picks.get(slot.id, "")
		if card_id.is_empty(): continue
		var incoming: Dictionary = battle.definition(card_id)
		var index: int = _candidate(remaining, incoming)
		if index < 0: return {"ok": false, "message": "原定牌库没有可换给「%s」的同类牌。" % incoming.name}
		var instance: Dictionary = remaining.pop_at(index)
		var outgoing: String = instance.card_id
		counts[outgoing] = int(counts[outgoing]) - 1
		if counts[outgoing] == 0: counts.erase(outgoing)
		counts[card_id] = int(counts.get(card_id, 0)) + 1
		instance.card_id = card_id
		reserved.append({"instance": instance, "draw": slot.draw})
		swaps[slot.id] = {"incoming": card_id, "outgoing": outgoing, "draw": slot.draw}
	problem = Model.DECKS.validate_counts(counts, Model.CATALOG.cards)
	if not problem.is_empty(): return {"ok": false, "message": problem}
	# Blue draws from the back. Reinsert from nearest to farthest draw so
	# each later insertion preserves every earlier slot's final position.
	for reserve: Dictionary in reserved:
		remaining.insert(remaining.size() + 1 - int(reserve.draw), reserve.instance)
	player.deck = remaining
	player.deck_id = "custom"
	player.deck_definition = {"id": "custom", "name": "自定义军势", "description": "本关战役军备。", "cards": Model.DECKS.canonical_counts(counts, Model.CATALOG.cards)}
	return {"ok": true, "battle": battle, "swaps": swaps}

static func _candidate(deck: Array, incoming: Dictionary) -> int:
	var best_index: int = -1
	var best_weight: int = 999
	for index: int in range(deck.size()):
		var current: Dictionary = Model.CATALOG.find(deck[index].card_id)
		if current.id == incoming.id or (current.type == "unit") != (incoming.type == "unit"): continue
		var weight: int = absi(int(current.cost) - int(incoming.cost)) * 2 + int(current.type != incoming.type)
		if weight >= best_weight: continue
		best_index = index
		best_weight = weight
	return best_index
