class_name MapData
extends Resource

@export var maps: Array[Dictionary] = []

func available() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for map: Dictionary in maps:
		if map.get("selectable", true): result.append(map)
	return result

func find(map_id: String) -> Dictionary:
	for map: Dictionary in maps:
		if map.id == map_id: return map
	return maps[0]
