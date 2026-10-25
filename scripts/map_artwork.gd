class_name MapArtwork
extends RefCounted
## Authored battlefield paintings. Rule data remains authoritative at every cell.

const Art = preload("res://scripts/art_library.gd")
const Landscape = preload("res://scripts/battlefield_art.gd")
const SYMBOLS: Dictionary = {".": "plain", "f": "forest", "m": "mountain", "r": "road", "w": "water", "b": "bridge", "h": "hill", "t": "fort"}

static func texture(game: Battle) -> Texture2D:
	return Art.get_texture("battlefield_" + str(game.map_definition.id))

static func original_ground(game: Battle, cell: Vector2i) -> String:
	if game.map_definition.ruins.has(cell): return "ruins"
	return SYMBOLS[str(game.map_definition.rows[cell.y])[cell.x]]

static func changed_cells(game: Battle) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(game.height):
		for x: int in range(game.width):
			var cell := Vector2i(x, y)
			if game.ground(cell) != original_ground(game, cell): result.append(cell)
	return result

static func floor_sample(game: Battle) -> Vector2i:
	for y: int in range(1, game.height - 1):
		for x: int in range(1, game.width - 1):
			var cell := Vector2i(x, y)
			if original_ground(game, cell) != "plain": continue
			var open: bool = true
			for direction: Vector2i in game.DIRECTIONS:
				if original_ground(game, cell + direction) != "plain": open = false
			if open: return cell
	# Dense harbor maps can have no meadow interior; edge cells are paved floor.
	return Vector2i.ZERO

static func draw_map(canvas: CanvasItem, game: Battle, grid: Rect2) -> bool:
	var painting: Texture2D = texture(game)
	if painting == null: return false
	canvas.draw_texture_rect(painting, grid, false)
	var tile: float = grid.size.x / game.width
	var source_cell: Vector2 = painting.get_size() / Vector2(game.width, game.height)
	var sample := Rect2(Vector2(floor_sample(game)) * source_cell, source_cell)
	for cell: Vector2i in changed_cells(game):
		var rect := Rect2(grid.position + Vector2(cell) * tile, Vector2.ONE * tile)
		# Clear old objects, then feather the patch into the surrounding painting.
		for edge: int in range(5):
			var extent: float = 0.17 - edge * 0.03
			var alpha: float = 0.16 + edge * 0.21
			canvas.draw_texture_rect_region(painting, rect.grow(tile * extent).intersection(grid), sample, Color(1, 1, 1, alpha))
		var kind: String = game.ground(cell)
		if kind == "road": Landscape._road(canvas, game, cell, rect)
		elif kind == "bridge": Landscape._bridge(canvas, game, cell, rect)
		else: Landscape.draw_prop(canvas, kind, rect, game.map_definition.theme, game.map_definition.id)
	return true

static func draw_water_motion(canvas: CanvasItem, game: Battle, grid: Rect2, time: float) -> void:
	var tile: float = grid.size.x / game.width
	for cell: Vector2i in game.terrain:
		if game.ground(cell) != "water": continue
		var origin: Vector2 = grid.position + Vector2(cell) * tile
		for ripple: int in range(2):
			var phase: float = time * 0.55 + cell.x * 0.7 + cell.y * 0.4 + ripple * 2.1
			var at: Vector2 = origin + Vector2(tile * (0.28 + 0.10 * sin(phase)), tile * (0.30 + ripple * 0.35))
			canvas.draw_line(at, at + Vector2(tile * 0.33, -tile * 0.02), Color(0.83, 0.97, 1.0, 0.10 + 0.05 * sin(phase)), 1.2, true)
