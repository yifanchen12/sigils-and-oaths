extends RefCounted
## Shared quiet palette; panels and the primary action inherit the same treatment.

const INK := Color("f2ead7")
const GOLD := Color("ccb17b")
const MUTED := Color("a9bacb")

static func box(fill: Color, border: Color, padding: Vector2 = Vector2(12, 8), radius: int = 6) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = fill
	value.border_color = border
	value.set_border_width_all(1)
	value.set_corner_radius_all(radius)
	value.content_margin_left = padding.x
	value.content_margin_right = padding.x
	value.content_margin_top = padding.y
	value.content_margin_bottom = padding.y
	return value

static func apply(value: Theme) -> void:
	value.default_font_size = 15
	value.set_color("font_color", "Label", INK)
	value.set_color("default_color", "RichTextLabel", Color("c7d2dd"))
	value.set_stylebox("panel", "PanelContainer", box(Color("142338"), Color("47576a"), Vector2(14, 12)))
	for button_type: String in ["Button", "OptionButton"]:
		value.set_stylebox("normal", button_type, box(Color("21354c"), Color("53687c"), Vector2(10, 7)))
		value.set_stylebox("hover", button_type, box(Color("304961"), GOLD, Vector2(10, 7)))
		value.set_stylebox("pressed", button_type, box(Color("182a40"), GOLD, Vector2(10, 7)))
		value.set_stylebox("disabled", button_type, box(Color("142134"), Color("304153"), Vector2(10, 7)))
		value.set_color("font_color", button_type, INK)
		value.set_color("font_hover_color", button_type, Color("fff5df"))
		value.set_color("font_pressed_color", button_type, GOLD)
		value.set_color("font_disabled_color", button_type, Color("7f91a3"))
		var focus := box(Color(0, 0, 0, 0), Color("e7c98c"), Vector2.ZERO)
		focus.set_border_width_all(2)
		value.set_stylebox("focus", button_type, focus)
	value.set_type_variation("PrimaryButton", "Button")
	value.set_stylebox("normal", "PrimaryButton", box(Color("c6aa75"), Color("ebd4a5"), Vector2(16, 8)))
	value.set_stylebox("hover", "PrimaryButton", box(Color("e3c58c"), Color("fff0c7"), Vector2(16, 8)))
	value.set_stylebox("pressed", "PrimaryButton", box(Color("ac8e59"), Color("f4d59b"), Vector2(16, 8)))
	value.set_color("font_color", "PrimaryButton", Color("17263a"))
	value.set_color("font_hover_color", "PrimaryButton", Color("142237"))
	value.set_color("font_pressed_color", "PrimaryButton", Color("142237"))
	value.set_stylebox("panel", "AcceptDialog", box(Color("142338"), GOLD, Vector2(16, 16), 8))
	var window_panel := box(Color("142338"), GOLD, Vector2(14, 14), 8)
	window_panel.expand_margin_top = 36
	value.set_stylebox("embedded_border", "Window", window_panel)
	value.set_stylebox("embedded_unfocused_border", "Window", window_panel)
	value.set_color("title_color", "Window", INK)
	value.set_color("title_outline_modulate", "Window", Color("142338"))
	value.set_font_size("title_font_size", "Window", 17)
	value.set_constant("title_height", "Window", 36)
	value.set_stylebox("panel", "TooltipPanel", box(Color("0e1b2d"), GOLD, Vector2(14, 12)))
	value.set_color("font_color", "TooltipLabel", INK)
	value.set_font_size("font_size", "TooltipLabel", 16)
	var separator := StyleBoxLine.new()
	separator.color = Color("44536a")
	separator.thickness = 1
	value.set_stylebox("separator", "HSeparator", separator)
