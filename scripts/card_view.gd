class_name CardView
extends Button
## One reusable card control, also provides the shared vector unit emblems.

const INK := Color("e6e8dd")
const MUTED := Color("9baea9")
const GOLD := Color("d0b579")
const TEAL := Color("70d3ba")
const CORAL := Color("f08b76")
const Art = preload("res://scripts/art_library.gd")
const Catalog = preload("res://data/cards.tres")

# Face positions in the upper-body portrait atlases, reviewed across all 81 troops.
# Card controls and draw previews share these crops; the full artwork is untouched.
const FACE_HEIGHTS: Dictionary = {
	"sword": 0.2,
	"spear": 0.42,
	"cavalry": 0.48,
	"archer": 0.42,
	"mage": 0.23,
	"healer": 0.33,
	"reed_scout": 0.23,
	"gate_veteran": 0.18,
	"ridge_courier": 0.17,
	"ridge_archer": 0.23,
	"shore_medic": 0.29,
	"scribe_warden": 0.25,
	"breakwater_guard": 0.25,
	"bronze_watch": 0.34,
	"quay_lantern": 0.38,
	"lantern_bearer": 0.18,
	"mink_watcher": 0.32,
	"ferry_pikeman": 0.31,
	"willow_outlook": 0.17,
	"quartermaster": 0.22,
	"moth_cavalry": 0.37,
	"ash_notary": 0.35,
	"kiln_wardens": 0.39,
	"carriage_cloak": 0.33,
	"last_bridge_clinic": 0.24,
	"copper_gate_requiem": 0.41,
	"cinder_runner": 0.33,
	"ridge_pioneer": 0.31,
	"quay_salver": 0.2,
	"reed_harrier": 0.61,
	"byway_guard": 0.19,
	"kiln_outrider": 0.55,
	"sandbar_physician": 0.28,
	"night_surveyor": 0.23,
	"levee_marshal": 0.23,
	"storm_saddle": 0.58,
	"indigo_gate_mage": 0.16,
	"sunbreak_column": 0.61,
	"lamp_patrol": 0.38,
	"reed_watch": 0.4,
	"slate_quartermaster": 0.41,
	"bell_winch": 0.34,
	"rain_saddle": 0.42,
	"levee_brothers": 0.39,
	"rising_oath_watch": 0.47,
	"lantern_surgeon": 0.25,
	"saltfield_runner": 0.25,
	"bank_pikeman": 0.47,
	"bastion_driller": 0.22,
	"shrike_saddler": 0.26,
	"sill_physician": 0.2,
	"shoal_arbalest": 0.4,
	"oathroad_mender": 0.21,
	"undertow_knight": 0.22,
	"claywatch_sage": 0.34,
	"crownless_vanguard": 0.47,
	"chalk_courier": 0.48,
	"ridge_listener": 0.61,
	"linen_lantern": 0.24,
	"coalroad_broker": 0.16,
	"shale_lancer": 0.55,
	"bracken_hussar": 0.6,
	"cairn_colossus": 0.4,
	"bellfoundry_oracle": 0.54,
	"whitecord_marshal": 0.21,
	"kiln_sparks": 0.27,
	"marl_shield": 0.44,
	"river_wasp": 0.46,
	"granary_warden": 0.21,
	"glassroad_runner": 0.2,
	"rook_pickets": 0.28,
	"reedglass_bow": 0.41,
	"saltband_surgeon": 0.25,
	"hinge_lancer": 0.15,
	"cinder_coxswain": 0.41,
	"quarry_bugler": 0.39,
	"copper_cistern": 0.26,
	"breakline_sappers": 0.46,
	"skylens_sentinel": 0.38,
	"bellroad_captain": 0.51,
	"silver_bulwark": 0.14
}


var card: Dictionary = {}
var card_uid: int = -1
var affordable: bool = true
var chosen: bool = false
var hovered: bool = false
var font: Font
var illustration: Texture2D
var deck_copies: int = -1
var compact: bool = false
var in_hand: bool = false
var hotkey_number: int = 0
var combo_lit: bool = false
var escalation_lit: bool = false
var hover_blend: float = 0.0
var hover_tween: Tween

func _ready() -> void:
	custom_minimum_size = Vector2(108 if in_hand else 158, 104) if compact else Vector2(118 if in_hand else 158, 168)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_EXPAND_FILL
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
	illustration = Art.get_texture(str(card.id))
	card_uid = uid
	affordable = int(card.cost) <= mana
	chosen = selected
	disabled = locked
	tooltip_text = "%s · %d 费\n%s\n%s" % [card.name, card.cost, card.tag, card.text]
	if combo_lit: tooltip_text += "\n连携已就绪。"
	if escalation_lit: tooltip_text += "\n法力上限强化已就绪。"
	if card.type == "unit":
		tooltip_text += "\n攻击 %d · 生命 %d · 防御 %d · 移动 %d · 射程 %d" % [card.atk, card.hp, card.defense, card.move, card.range]
		var skill: Dictionary = Catalog.find(card.kind).get("skill", {})
		if not skill.is_empty(): tooltip_text += "\n主动 · %s（1费，每回合一次）：%s" % [skill.name, skill.text]
	elif card.effect in ["redeploy", "muster"]:
		tooltip_text += "\n需要一处相邻空地和空余部队位。"
	elif not Battle.is_global_card(card):
		tooltip_text += "\n施法范围：友军3格、法师4格。"
		if card.effect == "exchange": tooltip_text += "换位另限指挥官3格。"
	if card.type == "trap":
		tooltip_text += "\n每方最多2张伏设；对手只见数量。"
		if card.trigger == "step": tooltip_text += "主动移动含骑兵再机动，不含部署、击退或换位。"
		elif card.trigger == "spell": tooltip_text += "只在敌方伤害法术或技能命中保护对象前触发。"
	queue_redraw()

func _draw() -> void:
	if card.is_empty() or font == null or size.x < 32 or size.y < 32: return
	var accent: Color = Color("8fc8cf") if card.type == "unit" else (Color("baa6e1") if card.type == "trap" else (Color("a8bce9") if card.type == "environment" else Color("dfbf80")))
	var lit: bool = chosen or hovered or has_focus()
	var top: float = 0 if chosen else lerpf(3, 0, hover_blend)
	var frame := Rect2(Vector2(1, top + 1), size - Vector2(2, top + 3))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("14243a")
	panel.border_color = accent if lit else Color("8a795b")
	panel.set_border_width_all(2 if lit else 1)
	panel.set_corner_radius_all(5)
	panel.shadow_color = Color(0.01, 0.02, 0.04, 0.65)
	panel.shadow_size = 5 if lit else 3
	panel.draw(get_canvas_item(), frame)
	var name_height: float = 29 if compact else 34
	var footer_height: float = 0 if compact else 26
	var art_rect := Rect2(Vector2(5, top + 5), Vector2(size.x - 10, frame.size.y - name_height - footer_height - 8))
	if illustration != null:
		Art.draw_cover(self, illustration, art_rect, art_focus(card))
	else:
		draw_rect(art_rect, Color("233b54"))
	if not affordable or disabled:
		draw_rect(art_rect, Color(0.025, 0.04, 0.07, 0.32 if disabled else 0.20))
	# Keep names on an opaque plate; rarity/type never carries meaning by color alone.
	var plate := Rect2(Vector2(5, art_rect.end.y), Vector2(size.x - 10, name_height))
	draw_rect(plate, Color("eee7d4"))
	draw_line(plate.position, plate.position + Vector2(plate.size.x, 0), Color("c1a66d"), 1)
	var title_font: int = 14 if compact else 16
	_center(_fit(str(card.name), size.x - 18, title_font), Vector2(size.x / 2, plate.position.y + (20 if compact else 23)), title_font, Color("203249"))
	if not compact:
		var value: String = "%d 攻   %d 血   %d 移" % [card.atk, card.hp, card.move] if card.type == "unit" else str(card.tag)
		_center(_fit(value, size.x - 20, 12), Vector2(size.x / 2, frame.end.y - 8), 12, Color("d5dfeb"))
	var gem := Vector2(21, top + 23)
	draw_circle(gem + Vector2(0, 1), 18, Color(0.02, 0.04, 0.07, 0.5))
	draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -19), gem + Vector2(17, 0), gem + Vector2(0, 19), gem + Vector2(-17, 0)]), Color("16364f") if affordable else Color("3f2e3b"))
	draw_polyline(PackedVector2Array([gem + Vector2(0, -19), gem + Vector2(17, 0), gem + Vector2(0, 19), gem + Vector2(-17, 0), gem + Vector2(0, -19)]), Color("dfc18b"), 1.5, true)
	_center(str(card.cost), gem + Vector2(0, 8), 23, Color("fff3d1") if affordable else Color("ffbbab"))
	var badge := Vector2(size.x - 18, top + 19)
	draw_circle(badge, 11, Color("172c40"))
	draw_arc(badge, 11, 0, TAU, 28, Color("b7a076"), 1, true)
	draw_symbol(self, str(card.get("kind", card.get("weather", card.get("terrain", card.get("effect", "draw"))))), badge, 7, accent)
	var type_name: String = {"unit":"部队", "spell":"法术", "trap":"陷阱", "environment":"环境"}.get(str(card.type), "战术")
	if card.type == "unit": type_name = {"sword":"步兵", "spear":"枪兵", "cavalry":"骑兵", "archer":"弓手", "mage":"法师", "healer":"医师"}.get(str(card.get("kind", "")), "部队")
	var strip_height: float = 15 if compact else 20
	var strip := Rect2(Vector2(art_rect.position.x, art_rect.end.y - strip_height), Vector2(art_rect.size.x, strip_height))
	draw_rect(strip, Color(0.05, 0.10, 0.17, 0.86))
	draw_string(font, strip.position + Vector2(6, 11 if compact else 14), type_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent)
	var detail: String = ""
	if combo_lit or escalation_lit: detail = "连携" if combo_lit else "强化"
	elif compact and card.type == "unit": detail = "%d/%d" % [card.atk, card.hp]
	elif not affordable: detail = "费不足"
	var right_padding: float = 24 if hotkey_number > 0 or deck_copies >= 0 else 6
	if not detail.is_empty():
		draw_string(font, strip.position + Vector2(35, 11 if compact else 14), detail, HORIZONTAL_ALIGNMENT_RIGHT, maxf(0, strip.size.x - 35 - right_padding), 11, TEAL if combo_lit or escalation_lit else Color("e0e6e9"))
	if hotkey_number > 0:
		var key_rect := Rect2(Vector2(size.x - 22, art_rect.end.y - 15), Vector2(16, 14))
		draw_rect(key_rect, Color("32475c"))
		_center(str(hotkey_number), key_rect.get_center() + Vector2(0, 4), 11, INK)
	if chosen:
		draw_line(Vector2(12, frame.end.y - 1), Vector2(size.x - 12, frame.end.y - 1), accent, 3)
	if has_focus():
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color(0, 0, 0, 0)
		focus.border_color = Color("f5d899")
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(6)
		focus.draw(get_canvas_item(), frame.grow(1))
	if deck_copies >= 0:
		_center("×%d" % deck_copies, Vector2(size.x - 17, art_rect.end.y - 5), 11, GOLD if deck_copies > 0 else MUTED)

static func art_focus(definition: Dictionary) -> Vector2:
	if definition.get("type", "") == "unit":
		return Vector2(0.5, float(FACE_HEIGHTS.get(str(definition.id), 0.35)))
	return Art.card_focus(definition)

func _fit(value: String, available: float, font_size: int) -> String:
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= available: return value
	var shortened: String = value
	while shortened.length() > 1 and font.get_string_size(shortened + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		shortened = shortened.left(shortened.length() - 1)
	return shortened + "…"

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
