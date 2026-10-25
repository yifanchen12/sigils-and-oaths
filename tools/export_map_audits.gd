extends SceneTree
## Exact cell overlay for reviewing painted terrain against the rule data.

const Model = preload("res://scripts/battle.gd")
const Painted = preload("res://scripts/map_artwork.gd")

class Audit extends Control:
	var battle: Battle
	func _draw() -> void:
		var grid := Rect2(0, 0, 1200, 1000)
		Painted.draw_map(self, battle, grid)
		var font: Font = get_theme_default_font()
		var labels: Dictionary = {"forest": "FOREST", "mountain": "BLOCK", "hill": "HILL", "ruins": "SHRINE", "fort": "FORT", "bridge": "BRIDGE", "water": "WATER", "road": "ROAD"}
		for y: int in range(battle.height):
			for x: int in range(battle.width):
				var cell := Vector2i(x, y)
				var rect := Rect2(Vector2(x, y) * 100, Vector2(100, 100))
				draw_rect(rect, Color(1, 1, 1, 0.46), false, 1)
				var label: String = "%s%d %s" % [String.chr(65 + x), battle.height - y, labels.get(battle.ground(cell), "")]
				draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(95, 19)), Color(0.02, 0.06, 0.09, 0.7))
				draw_string(font, rect.position + Vector2(5, 16), label, HORIZONTAL_ALIGNMENT_LEFT, 94, 11, Color.WHITE)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(1200, 1000)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots/map-audits")
	var view := Audit.new()
	root.add_child(view)
	for map: Dictionary in Model.MAPS.available():
		view.battle = Model.new(1, map.id)
		if Painted.texture(view.battle) == null: continue
		view.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var error: Error = root.get_texture().get_image().save_png("res://docs/screenshots/map-audits/%s.png" % map.id)
		if error != OK: push_error("Map audit save failed"); quit(1); return
		print("EXPORTED MAP AUDIT: ", map.id)
	quit()
