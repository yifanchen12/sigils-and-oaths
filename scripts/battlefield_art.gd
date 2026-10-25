class_name BattlefieldArt
extends RefCounted
## Continuous ground and connected routes, with original transparent terrain props.

const Art = preload("res://scripts/art_library.gd")

static func ground_color(ground: String, terrain_theme: String, map_id: String = "") -> Color:
	var desert: bool = terrain_theme == "desert"
	if ground in ["water", "bridge"]: return Color("3c9fb0")
	if terrain_theme == "harbor": return Color("adb7a3")
	if map_id == "ridgepass":
		return Color("4e7967") if ground == "forest" else (Color("9bb39a") if ground == "hill" else Color("7c9d87"))
	if map_id == "citadel":
		return Color("96a27a") if ground == "forest" else (Color("c9c39c") if ground == "hill" else Color("beb9a0"))
	if ground == "forest": return Color("648950") if not desert else Color("9a9c61")
	if ground == "hill": return Color("9fb76b") if not desert else Color("d7be82")
	return Color("88a963") if not desert else Color("c7b27e")

static func draw_ground(canvas: CanvasItem, game: Battle, cell: Vector2i, rect: Rect2, time: float) -> void:
	var kind: String = game.ground(cell)
	var desert: bool = game.map_definition.theme == "desert"
	var harbor: bool = game.map_definition.theme == "harbor"
	var paved: bool = harbor or game.map_definition.id == "citadel"
	var tile: float = rect.size.x
	var at: Vector2 = rect.get_center()
	var tint: Color = ground_color(kind, game.map_definition.theme, game.map_definition.id)
	var variation: float = float((cell.x * 7 + cell.y * 3) % 5) * 0.007
	canvas.draw_rect(rect, tint.lightened(variation))
	var texture_id: String = "ground_water" if kind in ["water", "bridge"] else ("ground_sand" if desert else "ground_grass")
	var texture: Texture2D = Art.get_texture(texture_id)
	if texture != null and (not paved or kind in ["water", "bridge"]):
		var sample_size: Vector2 = texture.get_size() * 0.46
		var start: Vector2 = texture.get_size() * Vector2(float((cell.x * 3 + cell.y) % 5) * 0.12, float((cell.y * 2 + cell.x) % 5) * 0.12)
		canvas.draw_texture_rect_region(texture, rect, Rect2(start, sample_size), Color(1, 1, 1, 0.35 if kind not in ["water", "bridge"] else 0.30))
	if kind not in ["water", "bridge"] and not paved:
		_blend_edges(canvas, game, cell, rect, tint)
	if paved and kind not in ["water", "bridge"]:
		var mortar: Color = Color("8c9d92") if harbor else Color("9e9a83")
		for row: int in range(4):
			var y: float = rect.position.y + tile * (row + 1) / 4
			canvas.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), mortar, 1)
			for column: int in range(3):
				var x: float = rect.position.x + fposmod(tile * (column + 0.5 * (row % 2)) / 3, tile)
				canvas.draw_line(Vector2(x, y - tile / 4), Vector2(x, y), mortar, 1)
	if kind in ["water", "bridge"]:
		for wave: int in range(3):
			var shift: float = sin(time * 0.7 + cell.x * 1.2 + wave) * tile * 0.07
			var start: Vector2 = rect.position + Vector2(tile * 0.18 + shift, tile * (0.25 + wave * 0.25))
			canvas.draw_line(start, start + Vector2(tile * 0.42, -tile * 0.035), Color(0.75, 0.95, 0.91, 0.24), 1.4, true)
		for direction: Vector2i in game.DIRECTIONS:
			var next: Vector2i = cell + direction
			if game.inside(next) and game.ground(next) not in ["water", "bridge"]:
				var normal: Vector2 = Vector2(direction)
				var tangent: Vector2 = Vector2(-direction.y, direction.x)
				var edge: Vector2 = at + normal * (tile * 0.5 - 2)
				canvas.draw_line(edge - tangent * tile * 0.5, edge + tangent * tile * 0.5, Color("d6ca96"), 6, true)
				canvas.draw_line(edge - normal * 3 - tangent * tile * 0.5, edge - normal * 3 + tangent * tile * 0.5, Color(0.10, 0.43, 0.46, 0.45), 2, true)
				if harbor:
					for block: int in range(5):
						var p: Vector2 = edge + tangent * tile * (float(block) / 4.0 - 0.5)
						canvas.draw_line(p - normal * 3, p + normal * 3, Color("8c927f"), 1, true)
	elif kind == "hill":
		var rim := PackedVector2Array([rect.position + Vector2(4, tile - 16), rect.position + Vector2(4, tile - 5), rect.position + Vector2(tile - 4, tile - 5), rect.position + Vector2(tile - 4, tile - 16)])
		canvas.draw_colored_polygon(rim, Color("6d8350") if not desert else Color("a58c61"))
		canvas.draw_line(rect.position + Vector2(5, tile - 17), rect.position + Vector2(tile - 5, tile - 17), tint.lightened(0.16), 2, true)
	elif not paved:
		# Sparse grass tufts rather than a busy repeated photographic texture.
		for patch: int in range(3):
			var p: Vector2 = rect.position + Vector2(tile * (0.15 + float((cell.y + patch * 2) % 7) * 0.11), tile * (0.2 + patch * 0.27))
			canvas.draw_line(p + Vector2(-2, 0), p + Vector2(0, -3), Color(tint.darkened(0.12), 0.45), 1)
			canvas.draw_line(p, p + Vector2(3, -2), Color(tint.lightened(0.18), 0.5), 1)
	if kind == "road": _road(canvas, game, cell, rect)
	elif kind == "bridge": _bridge(canvas, game, cell, rect)
	elif kind == "ruins": _ruins(canvas, rect)

static func _blend_edges(canvas: CanvasItem, game: Battle, cell: Vector2i, rect: Rect2, tint: Color) -> void:
	# Soft biome transitions stay inside each legal cell, preserving click geometry.
	var tile: float = rect.size.x
	for direction: Vector2i in game.DIRECTIONS:
		var neighbor: String = game.ground(cell + direction)
		if not game.inside(cell + direction) or neighbor in ["water", "bridge"]: continue
		var adjacent: Color = ground_color(neighbor, game.map_definition.theme, game.map_definition.id)
		if adjacent.is_equal_approx(tint): continue
		for band: int in range(5):
			var depth: float = tile * 0.05
			var strip: Rect2 = rect
			if direction.x != 0:
				strip.size.x = depth + 1
				strip.position.x += depth * band if direction.x < 0 else tile - depth * (band + 1)
			else:
				strip.size.y = depth + 1
				strip.position.y += depth * band if direction.y < 0 else tile - depth * (band + 1)
			canvas.draw_rect(strip, Color(adjacent, (1.0 - float(band) / 5.0) * 0.22))

static func _road(canvas: CanvasItem, game: Battle, cell: Vector2i, rect: Rect2) -> void:
	var at: Vector2 = rect.get_center()
	var width: float = rect.size.x * 0.43
	var neighbors: Array[Vector2i] = []
	for direction: Vector2i in game.DIRECTIONS:
		if game.inside(cell + direction) and game.ground(cell + direction) in ["road", "bridge", "fort", "ruins"]: neighbors.append(direction)
	var edge_color: Color = Color(Color("8f956b"), 0.30) if game.map_definition.theme != "harbor" else Color(Color("849c9a"), 0.45)
	var road_color: Color = Color("cdb88b") if game.map_definition.theme != "harbor" else Color("cbcbb5")
	canvas.draw_circle(at, width * 0.58, edge_color)
	canvas.draw_circle(at, width * 0.45, road_color)
	for direction: Vector2i in neighbors:
		var end: Vector2 = at + Vector2(direction) * rect.size.x * 0.51
		canvas.draw_line(at, end, Color(edge_color, 0.12), width + rect.size.x * 0.15, true)
		canvas.draw_line(at, end, edge_color, width + rect.size.x * 0.07, true)
		canvas.draw_line(at, end, road_color, width, true)
	if neighbors.is_empty():
		canvas.draw_line(at - Vector2(width * 0.6, width * 0.6), at + Vector2(width * 0.6, width * 0.6), road_color, width, true)
	for stone: int in range(3):
		var offset: Vector2 = Vector2(sin(float(cell.x * 17 + cell.y * 11 + stone * 7)) * width * 0.2, (stone - 1) * rect.size.x * 0.12)
		canvas.draw_line(at + offset - Vector2(width * 0.12, 0), at + offset + Vector2(width * 0.16, -1), Color(Color("efe1bb"), 0.75), maxf(1, rect.size.x * 0.025), true)

static func _bridge(canvas: CanvasItem, game: Battle, cell: Vector2i, rect: Rect2) -> void:
	var vertical: bool = game.ground(cell + Vector2i.LEFT) == "water" or game.ground(cell + Vector2i.RIGHT) == "water"
	var forward: Vector2 = Vector2.DOWN if vertical else Vector2.RIGHT
	var side: Vector2 = Vector2.RIGHT if vertical else Vector2.DOWN
	var at: Vector2 = rect.get_center()
	var tile: float = rect.size.x
	canvas.draw_line(at - forward * tile * 0.51, at + forward * tile * 0.51, Color("5b6659"), tile * 0.5)
	canvas.draw_line(at - forward * tile * 0.51, at + forward * tile * 0.51, Color("c5af7b"), tile * 0.41)
	for plank: int in range(8):
		var p: Vector2 = at + forward * tile * (float(plank) / 7 - 0.5)
		canvas.draw_line(p - side * tile * 0.2, p + side * tile * 0.2, Color("8c7b59"), 1.2)
	for sign_value: int in [-1, 1]:
		var center: Vector2 = at + side * sign_value * tile * 0.27
		canvas.draw_line(center - forward * tile * 0.51, center + forward * tile * 0.51, Color("ece0b6"), 3)

static func _ruins(canvas: CanvasItem, rect: Rect2) -> void:
	var at: Vector2 = rect.get_center()
	var tile: float = rect.size.x
	canvas.draw_circle(at + Vector2(0, 4), tile * 0.33, Color("6b8260"))
	canvas.draw_arc(at, tile * 0.29, 0, TAU, 32, Color("d7d4af"), 4, true)
	for index: int in range(4):
		var p: Vector2 = at + Vector2.from_angle(index * PI / 2 + PI / 4) * tile * 0.28
		canvas.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 13)), Color("7f8c77"))
		canvas.draw_rect(Rect2(p - Vector2(4, 8), Vector2(8, 11)), Color("ddd8ba"))
	canvas.draw_circle(at, 5, Color("c6e8b6"))

static func draw_prop(canvas: CanvasItem, kind: String, rect: Rect2, terrain_theme: String = "forest", map_id: String = "") -> void:
	if kind not in ["forest", "mountain", "fort", "hill", "ruins"]: return
	var asset_id: String = "map_harbor_fort" if kind == "fort" and terrain_theme == "harbor" else "map_" + kind
	if kind == "forest" and map_id == "ridgepass": asset_id = "map_pines"
	elif kind == "forest" and terrain_theme == "desert": asset_id = "map_acacia"
	elif kind == "fort" and map_id == "citadel": asset_id = "map_gate"
	elif kind == "mountain": asset_id = "map_sand_mountain" if terrain_theme == "desert" else "map_rock_mountain"
	elif kind == "hill": asset_id = "map_plateau"
	var texture: Texture2D = Art.get_texture(asset_id)
	if texture != null:
		var extent: Vector2 = rect.size * Vector2(0.94, 0.94)
		if kind in ["forest", "mountain", "fort"]:
			canvas.draw_set_transform(rect.get_center() + Vector2(2, rect.size.y * 0.24), 0, Vector2(1, 0.36))
			canvas.draw_circle(Vector2.ZERO, rect.size.x * 0.34, Color(0.08, 0.17, 0.12, 0.19))
			canvas.draw_set_transform(Vector2.ZERO)
		canvas.draw_texture_rect(texture, Rect2(rect.get_center() - extent / 2, extent), false)
