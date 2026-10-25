class_name DeckData
extends Resource

@export var decks: Array[Dictionary] = []
const DECK_SIZE: int = 30
const COPY_LIMIT: int = 4

func find(deck_id: String) -> Dictionary:
	for deck: Dictionary in decks:
		if deck.id == deck_id: return deck
	return decks[0]

func validate_counts(counts: Variant, catalog: Array[Dictionary]) -> String:
	if not counts is Dictionary: return "套牌数量格式无效。"
	var known: Dictionary = {}
	for card: Dictionary in catalog:
		if not card.get("generated_only", false): known[card.id] = card
	var total: int = 0
	var troops: int = 0
	for card_id: Variant in counts:
		if not card_id is String or not known.has(card_id): return "包含不可组入的卡牌。"
		var count: Variant = counts[card_id]
		if typeof(count) not in [TYPE_INT, TYPE_FLOAT]: return "卡牌数量必须是整数。"
		if not is_finite(float(count)) or float(count) != floorf(float(count)): return "卡牌数量必须是有限整数。"
		if count < 0 or count > COPY_LIMIT: return "每种卡牌最多4张，数量不能为负。"
		total += int(count)
		if known[card_id].type == "unit": troops += int(count)
	if total != DECK_SIZE: return "需要30张牌，当前%d张。" % total
	if troops < 1: return "至少需要1张部队牌。"
	return ""

func canonical_counts(counts: Dictionary, catalog: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for card: Dictionary in catalog:
		if not card.get("generated_only", false) and int(counts.get(card.id, 0)) > 0: result[card.id] = int(counts[card.id])
	return result
