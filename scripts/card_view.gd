class_name CardView
extends Button
## One reusable card control, also provides the shared vector unit emblems.

const INK := Color("e6e8dd")
const MUTED := Color("9baea9")
const GOLD := Color("d0b579")
const TEAL := Color("70d3ba")
const CORAL := Color("f08b76")
const Art = preload("res://scripts/art_library.gd")

var card: Dictionary = {}
var card_uid: int = -1
var affordable: bool = true
var chosen: bool = false
var hovered: bool = false
var font: Font
var illustration: Texture2D
var deck_copies: int = -1
var compact: bool = false
var hotkey_number: int = 0
var hover_blend: float = 0.0
var hover_tween: Tween

func _ready() -> void:
	custom_minimum_size = Vector2(118, 104) if compact else Vector2(158, 168)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	font = get_theme_default_font()
	flat = true
	text = ""
	mouse_entered.connect(func() -> void: hovered = true; _animate_hover())
	mouse_exited.connect(func() -> void: hovered = false; _animate_hover())
	focus_entered.connect(_animate_hover)
	focus_exited.connect(_animate_hover)

func _animate_hover() -> void:
	if hover_tween != null: hover_tween.kill()
	hover_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hover_tween.tween_method(_set_hover_blend, hover_blend, 1.0 if hovered or has_focus() else 0.0, 0.14)
	queue_redraw()

func _set_hover_blend(value: float) -> void:
	hover_blend = value
	queue_redraw()

func configure(definition: Dictionary, uid: int, mana: int, selected: bool, locked: bool) -> void:
	card = definition
	illustration = Art.get_texture(str(card.get("kind", card.id)))
	card_uid = uid
	affordable = int(card.cost) <= mana
	chosen = selected
	disabled = locked
	tooltip_text = "%s · %d 费\n%s\n%s" % [card.name, card.cost, card.tag, card.text]
	if card.type == "unit":
		tooltip_text += "\n攻击 %d · 生命 %d · 防御 %d · 移动 %d · 射程 %d" % [card.atk, card.hp, card.defense, card.move, card.range]
		if card.has("skill"): tooltip_text += "\n主动 · %s（1费，每回合一次）：%s" % [card.skill.name, card.skill.text]
	elif card.effect not in ["draw", "mana", "weather", "clear_weather"]:
		tooltip_text += "\n施法范围：友军3格、法师4格；换位另限指挥官3格。"
	queue_redraw()

func _draw() -> void:
	if card.is_empty() or font == null: return
	var accent: Color = Color("63c5ca") if card.type == "unit" else (Color("a6b9ee") if card.type == "environment" else GOLD)
	var lit: bool = chosen or hovered or has_focus()
	var top: float = 0 if chosen else lerpf(4, 0, hover_blend)
	var frame := Rect2(Vector2(0, top), size - Vector2(0, top + 2))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("eee8d8")
	panel.border_color = accent if lit else Color("ad9566")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(4)
	panel.shadow_color = Color(0.01, 0.02, 0.04, 0.6)
	panel.shadow_size = 5 if lit else 3
	panel.draw(get_canvas_item(), frame)
	var art_height: float = frame.size.y - (33 if compact else 57)
	var art_rect := Rect2(Vector2(4, top + 4), Vector2(size.x - 8, art_height))
	if illustration != null:
		Art.draw_cover(self, illustration, art_rect, Vector2(0.5, 0.24) if compact and card.type == "unit" else Art.card_focus(card))
	else:
		draw_rect(art_rect, Color("233b54"))
	draw_rect(art_rect, Color("806f50"), false, 1)
	# A native engraved nameplate stays legible over every illustration.
	var title_y: float = art_rect.end.y + 22
	draw_line(Vector2(7, art_rect.end.y + 2), Vector2(size.x - 7, art_rect.end.y + 2), Color("b89b61"), 1)
	_center(str(card.name), Vector2(size.x / 2, title_y), 14 if compact else 17, Color("20374a"))
	if not compact:
		var value: String = "%d 攻    %d 血    %d 移" % [card.atk, card.hp, card.move] if card.type == "unit" else str(card.tag)
		_center(value, Vector2(size.x / 2, title_y + 23), 12, Color("626c6a"))
	var gem := Vector2(20, top + 22)
	draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -18), gem + Vector2(16, 0), gem + Vector2(0, 19), gem + Vector2(-16, 0)]), Color("142d4a"))
	draw_polyline(PackedVector2Array([gem + Vector2(0, -18), gem + Vector2(16, 0), gem + Vector2(0, 19), gem + Vector2(-16, 0), gem + Vector2(0, -18)]), GOLD, 1.4, true)
	_center(str(card.cost), gem + Vector2(0, 7), 21, Color("fff3cc") if affordable else CORAL)
	var badge := Vector2(size.x - 19, top + 20)
	draw_circle(badge, 12, Color("172c40"))
	draw_arc(badge, 12, 0, TAU, 32, GOLD, 1, true)
	draw_symbol(self, str(card.get("kind", card.get("weather", card.get("terrain", card.get("effect", "draw"))))), badge, 8, accent)
	if hotkey_number > 0:
		draw_rect(Rect2(Vector2(size.x - 23, art_rect.end.y - 21), Vector2(19, 20)), Color("172c40"))
		_center(str(hotkey_number), Vector2(size.x - 14, art_rect.end.y - 5), 12, INK)
	if not affordable or disabled:
		draw_rect(frame, Color(0.025, 0.04, 0.05, 0.30))
	if chosen:
		draw_line(Vector2(16, frame.end.y - 2), Vector2(size.x - 16, frame.end.y - 2), accent, 4)
	if deck_copies >= 0:
		draw_circle(Vector2(size.x - 19, art_rect.end.y - 15), 12, Color("172c40"))
		_center("×%d" % deck_copies, Vector2(size.x - 19, art_rect.end.y - 10), 11, GOLD if deck_copies > 0 else MUTED)

func _center(value: String, at: Vector2, font_size: int, color: Color) -> void:
	var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at - Vector2(width / 2, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

static func draw_symbol(canvas: CanvasItem, kind: String, at: Vector2, radius: float, color: Color) -> void:
	var r: float = radius
	var dark := Color("0c1920")
	match kind:
		"sword":
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, 10) * r / 20, at + Vector2(-4, -12) * r / 20, at + Vector2(0, -21) * r / 20, at + Vector2(4, -12) * r / 20, at + Vector2(3, 10) * r / 20]), color)
			canvas.draw_line(at + Vector2(-10, 9) * r / 20, at + Vector2(10, 9) * r / 20, color, 3)
			canvas.draw_line(at + Vector2(0, 10) * r / 20, at + Vector2(0, 20) * r / 20, color, 4)
		"spear":
			canvas.draw_line(at + Vector2(0, 20) * r / 20, at + Vector2(0, -16) * r / 20, color, 2.5)
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -23) * r / 20, at + Vector2(-6, -10) * r / 20, at + Vector2(6, -10) * r / 20]), color)
			canvas.draw_arc(at + Vector2(0, 3) * r / 20, r * 0.6, 0, PI, 18, color, 3, true)
		"cavalry":
			var points := PackedVector2Array([Vector2(-13, 18), Vector2(-10, -1), Vector2(-3, -15), Vector2(-5, -22), Vector2(4, -17), Vector2(11, -10), Vector2(15, 0), Vector2(9, 4), Vector2(3, -1), Vector2(7, 18)])
			for index: int in range(points.size()): points[index] = at + points[index] * r / 22
			canvas.draw_colored_polygon(points, color)
			canvas.draw_circle(at + Vector2(6, -10) * r / 22, 1.7, dark)
			canvas.draw_line(at + Vector2(-15, 20) * r / 22, at + Vector2(10, 20) * r / 22, color, 3)
		"archer":
			canvas.draw_arc(at - Vector2(r * 0.35, 0), r * 0.85, -PI / 2, PI / 2, 24, color, 2.5, true)
			canvas.draw_line(at + Vector2(-r * 0.35, -r * 0.85), at + Vector2(-r * 0.35, r * 0.85), color, 1)
			canvas.draw_line(at - Vector2(r * 0.7, 0), at + Vector2(r, 0), color, 2)
			canvas.draw_line(at + Vector2(r, 0), at + Vector2(r * 0.65, -r * 0.3), color, 2)
			canvas.draw_line(at + Vector2(r, 0), at + Vector2(r * 0.65, r * 0.3), color, 2)
		"commander":
			var points := PackedVector2Array([Vector2(-18, -10), Vector2(-9, -3), Vector2(0, -19), Vector2(9, -3), Vector2(18, -10), Vector2(13, 13), Vector2(-13, 13)])
			for index: int in range(points.size()): points[index] = at + points[index] * r / 22
			canvas.draw_colored_polygon(points, color)
			canvas.draw_line(at + Vector2(-13, 18) * r / 22, at + Vector2(13, 18) * r / 22, color, 2)
		"healer", "heal":
			canvas.draw_rect(Rect2(at - Vector2(r * 0.22, r * 0.8), Vector2(r * 0.44, r * 1.6)), color)
			canvas.draw_rect(Rect2(at - Vector2(r * 0.8, r * 0.22), Vector2(r * 1.6, r * 0.44)), color)
			canvas.draw_arc(at, r, 0, TAU, 32, Color(color, 0.4), 1, true)
		"shield":
			var points := PackedVector2Array([Vector2(-16, -15), Vector2(0, -20), Vector2(16, -15), Vector2(13, 6), Vector2(0, 20), Vector2(-13, 6)])
			for index: int in range(points.size()): points[index] = at + points[index] * r / 22
			canvas.draw_colored_polygon(points, color)
			canvas.draw_line(at - Vector2(0, r * 0.6), at + Vector2(0, r * 0.6), dark, 2)
		"march":
			for offset: int in [-8, 7]:
				canvas.draw_polyline(PackedVector2Array([at + Vector2(offset - 6, -13) * r / 22, at + Vector2(offset + 6, 0) * r / 22, at + Vector2(offset - 6, 13) * r / 22]), color, 3, true)
		"draw":
			canvas.draw_rect(Rect2(at - Vector2(r * 0.7, r * 0.8), Vector2(r, r * 1.35)), Color(color, 0.4), false, 2)
			canvas.draw_rect(Rect2(at - Vector2(r * 0.25, r * 0.5), Vector2(r, r * 1.35)), color, false, 2)
			canvas.draw_line(at + Vector2(0, r * 0.05), at + Vector2(r * 0.5, r * 0.05), color, 1.5)
		"mana":
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.7, 0), at + Vector2(0, r), at + Vector2(-r * 0.7, 0)]), Color("9bc6e7"))
			canvas.draw_line(at - Vector2(0, r), at + Vector2(0, r), Color("dceafa"), 1.5)
		"rain", "fog", "snow":
			canvas.draw_circle(at + Vector2(-r * 0.4, -r * 0.2), r * 0.4, color)
			canvas.draw_circle(at + Vector2(r * 0.1, -r * 0.4), r * 0.52, color)
			canvas.draw_circle(at + Vector2(r * 0.55, -r * 0.14), r * 0.34, color)
			if kind == "fog":
				for line: int in range(3): canvas.draw_line(at + Vector2(-r * 0.75, r * (0.25 + line * 0.25)), at + Vector2(r * 0.75, r * (0.25 + line * 0.25)), color, 2)
			else:
				for offset: float in [-0.5, 0.1, 0.65]:
					var start: Vector2 = at + Vector2(r * offset, r * 0.45)
					canvas.draw_line(start, start + Vector2(-r * 0.1, r * 0.35), color, 2)
					if kind == "snow": canvas.draw_line(start + Vector2(-3, 3), start + Vector2(3, 3), color, 1.5)
		"sun":
			canvas.draw_circle(at, r * 0.45, color)
			for ray: int in range(8):
				var direction: Vector2 = Vector2.from_angle(ray * PI / 4)
				canvas.draw_line(at + direction * r * 0.65, at + direction * r, color, 2)
		"fort":
			canvas.draw_rect(Rect2(at - Vector2(r * 0.8, r * 0.4), Vector2(r * 1.6, r * 1.2)), color)
			for tooth: int in range(3): canvas.draw_rect(Rect2(at + Vector2(-r * 0.8 + tooth * r * 0.6, -r * 0.8), Vector2(r * 0.4, r * 0.5)), color)
			canvas.draw_rect(Rect2(at - Vector2(r * 0.2, 0), Vector2(r * 0.4, r * 0.8)), dark)
		"road":
			canvas.draw_line(at + Vector2(-r, r * 0.8), at + Vector2(r * 0.2, -r), color, 2)
			canvas.draw_line(at + Vector2(-r * 0.2, r), at + Vector2(r, -r * 0.8), color, 2)
			for part: int in range(3): canvas.draw_line(at + Vector2(-r * 0.15 + part * r * 0.2, r * 0.55 - part * r * 0.5), at + Vector2(r * 0.05 + part * r * 0.2, r * 0.25 - part * r * 0.5), color, 2)
		_:
			var points := PackedVector2Array([Vector2(0, -22), Vector2(13, -2), Vector2(8, 15), Vector2(-3, 21), Vector2(-14, 9), Vector2(-9, -5), Vector2(-3, 1)])
			for index: int in range(points.size()): points[index] = at + points[index] * r / 24
			canvas.draw_colored_polygon(points, color)
			if kind == "area": canvas.draw_arc(at, r * 1.1, 0, TAU, 32, Color(color, 0.5), 1.5, true)
