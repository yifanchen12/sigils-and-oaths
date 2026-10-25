class_name HeroData
extends Resource

@export var heroes: Array[Dictionary] = []

func find(hero_id: String) -> Dictionary:
	for hero: Dictionary in heroes:
		if hero.id == hero_id: return hero
	return heroes[0]
