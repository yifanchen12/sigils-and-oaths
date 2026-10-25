class_name BattlePeek
extends PanelContainer
## Read-only inspection in the unused gutter of an expanded battlefield.

var portrait: TextureRect
var heading: Label
var subtitle: Label
var details: Label
var layout_width: float = -1.0
var width_changed_frame: int = -10

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("eee8d8")
	skin.border_color = Color("b7a174")
	skin.set_border_width_all(2)
	skin.set_corner_radius_all(3)
	skin.content_margin_left = 12
	skin.content_margin_right = 12
	skin.content_margin_top = 12
	skin.content_margin_bottom = 14
	add_theme_stylebox_override("panel", skin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 9)
	add_child(stack)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(0, 175)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(portrait)
	heading = _label(19, Color("233a50"))
	subtitle = _label(13, Color("7c6944"))
	details = _label(14, Color("4a5f69"))
	for label: Label in [heading, subtitle, details]: stack.add_child(label)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func present(texture: Texture2D, title: String, tag: String, body: String, accent: Color) -> void:
	portrait.texture = texture
	heading.text = title
	heading.add_theme_color_override("font_color", Color("214459") if accent.g > accent.r else Color("8d3c38"))
	subtitle.text = tag
	details.text = body

func fit_width(value: float) -> void:
	if not is_equal_approx(value, layout_width):
		layout_width = value
		width_changed_frame = Engine.get_process_frames()
	size = Vector2(value, 0)

func layout_settled() -> bool:
	return Engine.get_process_frames() > width_changed_frame + 2
