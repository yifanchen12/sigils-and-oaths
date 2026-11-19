class_name CardData
extends Resource
## Immutable card definitions; runtime card instances contain only uid + card_id.

const SET_NAMES: Dictionary = {"warfront": "前线扩牌", "afterglow": "余烬回声", "tidegate": "潮门后备", "levee": "堤灯军令", "moorings": "回澜契令", "pilgrim": "石岭行军", "glassroad": "镜道兵书"}

@export var cards: Array[Dictionary] = []

func find(card_id: String) -> Dictionary:
	for card: Dictionary in cards:
		if card.id == card_id:
			return card
	return {}
