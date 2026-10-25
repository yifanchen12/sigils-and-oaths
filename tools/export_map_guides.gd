extends SceneTree
## Reproducible, terrain-only image-generation guides from the real rule data.

const Model = preload("res://scripts/battle.gd")
const Landscape = preload("res://scripts/battlefield_art.gd")

class Guide extends Control:
	var battle: Battle
	var schematic: bool = false
	func _draw() -> void:
		var tile: float = 100.0
		if schematic:
			var colors: Dictionary = {"plain": Color("e8ddbb"), "forest": Color("3f754e"), "mountain": Color("776b70"), "road": Color("bea26e"), "water": Color("2a92ba"), "bridge": Color("997a4b"), "hill": Color("9bb05f"), "fort": Color("8a9ea8"), "ruins": Color("79d6c7")}
			var marks: Dictionary = {"plain": "", "forest": "F", "mountain": "M", "road": "R", "water": "W", "bridge": "B", "hill": "H", "fort": "T", "ruins": "+"}
			for y: int in range(battle.height):
				for x: int in range(battle.width):
					var kind: String = battle.ground(Vector2i(x, y))
					var rect := Rect2(Vector2(x, y) * tile, Vector2.ONE * tile)
					draw_rect(rect, colors[kind])
					draw_rect(rect, Color(0, 0, 0, 0.18), false, 1)
					draw_string(get_theme_default_font(), rect.position + Vector2(38, 64), marks[kind], HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color.WHITE)
			return
		for y: int in range(battle.height):
			for x: int in range(battle.width):
				Landscape.draw_ground(self, battle, Vector2i(x, y), Rect2(Vector2(x, y) * tile, Vector2.ONE * tile), 0)
		for y: int in range(battle.height):
			for x: int in range(battle.width):
				var cell := Vector2i(x, y)
				var rect := Rect2(Vector2(cell) * tile, Vector2.ONE * tile)
				Landscape.draw_prop(self, battle.ground(cell), rect, battle.map_definition.theme, battle.map_definition.id)
				draw_rect(rect, Color(0.03, 0.08, 0.12, 0.20), false, 1)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(1200, 1000)
	root.content_scale_size = Vector2i(1200, 1000)
	var directory: String = "res://assets/art/map-guides/schematic" if OS.get_cmdline_user_args().has("--schematic") else "res://assets/art/map-guides"
	DirAccess.make_dir_recursive_absolute(directory)
	var guide := Guide.new()
	guide.schematic = OS.get_cmdline_user_args().has("--schematic")
	root.add_child(guide)
	for map: Dictionary in Model.MAPS.available():
		guide.battle = Model.new(1, map.id)
		guide.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var error: Error = root.get_texture().get_image().save_png(directory + "/%s.png" % map.id)
		if error != OK: push_error("Map guide save failed: " + str(map.id)); quit(1); return
		print("EXPORTED MAP GUIDE: ", map.id, " 1200x1000")
	quit()
