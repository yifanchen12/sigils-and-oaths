class_name CardData
extends Resource
## Immutable card definitions; runtime card instances contain only uid + card_id.

@export var cards: Array[Dictionary] = []

func find(card_id: String) -> Dictionary:
	for card: Dictionary in cards:
		if card.id == card_id:
			return card
	return {}
