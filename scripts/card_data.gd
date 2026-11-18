class_name CardData
extends Resource
## Immutable card definitions; runtime card instances contain only uid + card_id.

const SET_NAMES: Dictionary = {"warfront": "前线扩牌", "afterglow": "余烬回声"}

@export var cards: Array[Dictionary] = []

func find(card_id: String) -> Dictionary:
	for card: Dictionary in cards:
		if card.id == card_id:
			return card
	return {}
