extends SceneTree
## Engine-native atlas inspection at enlarged and normal board scale.

class Gallery extends Control:
	const Art = preload("res://scripts/art_library.gd")
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("10252d"))
		var font: Font = get_theme_default_font()
		draw_string(font, Vector2(38, 45), "近战动作图集 · 大图与棋盘尺寸对照", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("f2e9d5"))
		for column: int in range(3):
			draw_string(font, Vector2(140 + column * 420, 88), ["蓄力 / 援护", "出手", "收招"][column], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c6ab72"))
		for row: int in range(3):
			for column: int in range(3):
				var at := Vector2(100 + column * 420, 105 + row * 270)
				draw_rect(Rect2(at, Vector2(198, 228)), Color("193a3e"))
				var kind: String = ["sword", "spear", "cavalry"][row]
				var texture: Texture2D = Art.get_action_texture(kind, column)
				if texture != null:
					for display: Array in [[Vector2(98, 205), 145.0], [Vector2(255, 205), 72.0]]:
						var ratio: float = float(display[1]) * Art.action_scale(kind) / texture.get_height()
						draw_texture_rect(texture, Rect2(at + display[0] - Art.action_feet(kind, column) * ratio, texture.get_size() * ratio), false)
				if column == 0: draw_string(font, at + Vector2(-62, 125), ["步兵", "枪兵", "骑兵"][row], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("70d3ba"))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var gallery := Gallery.new()
	gallery.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.add_child(gallery)
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://docs/screenshots/melee-pose-gallery.png")
	print("ACTION GALLERY: ", error_string(error))
	quit(0 if error == OK else 1)
