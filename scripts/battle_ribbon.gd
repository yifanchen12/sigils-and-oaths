extends HBoxContainer
## Public battle state, rendered as a game HUD rather than a text report.

const Art = preload("res://scripts/art_library.gd")
var battle: Battle
var hud_visible: bool = false
var replay_active: bool = false
var story_difficulty: bool = false
var last_second: int = -1

func _ready() -> void:
	custom_minimum_size.y = 72
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _process(_delta: float) -> void:
	if battle == null or not hud_visible: return
	var second: int = ceili(battle.time_remaining)
	if second != last_second:
		last_second = second
		queue_redraw()

func subtitle_text() -> String:
	if battle == null: return ""
	var value: String = "%s  /  %s" % [battle.map_definition.name, battle.WEATHER[battle.weather].name]
	if story_difficulty: value = "剧情 · " + value
	if replay_active: value = "分支 · " + value
	var goal: Dictionary = battle.objective
	if goal.is_empty(): return value
	var completed_rounds: int = (battle.turn - 1) / 2
	if battle.ControlObjective.is_escort(goal):
		var exit_cell: Vector2i = battle.ControlObjective.position(goal.cells[0])
		return "%s  ·  护送至 %s  ·  余 %d 轮" % [value, battle.cell_name(exit_cell), maxi(0, int(goal.round_limit) - completed_rounds)]
	if battle.ControlObjective.is_relay(goal):
		value += "  ·  接应 %d/%d" % [goal.streak, goal.required]
		if goal.streak < goal.required:
			var next: Array = goal.cells[int(goal.streak)]
			value += "  ·  下一站 " + battle.cell_name(Vector2i(int(next[0]), int(next[1])))
		value += "  ·  余 %d 轮" % maxi(0, int(goal.round_limit) - completed_rounds)
	else:
		value += "  ·  驻守 %d/%d  ·  %s" % [goal.streak, goal.required, battle.ControlObjective.elapsed_text(goal, battle.turn)]
	return value

func _draw() -> void:
	if battle == null or not hud_visible: return
	var font: Font = get_theme_default_font()
	var width: float = minf(340, size.x * 0.30)
	var narrow: bool = size.x < 900
	for side: int in range(2):
		var origin := Vector2(0 if side == 0 else size.x - width, 0)
		var accent := Color("82c7d5") if side == 0 else Color("df9d94")
		var commander: Dictionary = battle.commander(side)
		var player: Dictionary = battle.players[side]
		var hp: int = int(commander.get("hp", 0))
		var portrait_radius: float = 22 if narrow else 26
		var center: Vector2 = origin + Vector2(portrait_radius + 3, 32)
		draw_circle(center, portrait_radius + 3, Color("0c1a2b"))
		Art.draw_round_portrait(self, Art.get_texture(battle.hero(side).portrait), center, portrait_radius)
		draw_arc(center, portrait_radius + 2, 0, TAU, 48, Color("c5ad77"), 1.5, true)
		var start_x: float = portrait_radius * 2 + 15
		var reserve: float = 67 if side == 1 else 0
		var text_width: float = maxf(42, width - start_x - reserve - 6)
		draw_string(font, origin + Vector2(start_x, 20), _fit_text(battle.hero(side).name, text_width, 14 if narrow else 17), HORIZONTAL_ALIGNMENT_LEFT, text_width, 14 if narrow else 17, Color("f1e7cc"))
		var bar := Rect2(origin + Vector2(start_x, 30), Vector2(text_width, 7))
		draw_rect(bar, Color("081524"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp / 20.0, 0, 1), bar.size.y)), accent)
		draw_rect(bar, Color("596779"), false, 1)
		var resources: String = "%d/20  ·  %d/%d费" % [hp, player.mana, player.max_mana]
		draw_string(font, origin + Vector2(start_x, 55), resources, HORIZONTAL_ALIGNMENT_LEFT, maxf(text_width, 97), 11 if narrow else 13, Color("c5d5e4"))
		if not narrow and side == 0:
			for index: int in range(10):
				var gem: Vector2 = origin + Vector2(start_x + index * 13, 65)
				var color := Color("80c9e6") if index < player.mana else (Color("4e6579") if index < player.max_mana else Color("23344a"))
				draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -3), gem + Vector2(3, 0), gem + Vector2(0, 3), gem + Vector2(-3, 0)]), color)
		if side == 1:
			var hand_rect := Rect2(origin + Vector2(width - 63, 8), Vector2(24, 34))
			var deck_rect := Rect2(origin + Vector2(width - 28, 8), Vector2(24, 34))
			_draw_small_stack(hand_rect, "手%d" % player.hand.size(), Color("bfae8d"))
			_draw_small_stack(deck_rect, "库%d" % player.deck.size(), Color("a8b9cc"))
			_position_draw_anchor("EnemyHandAnchor", hand_rect)
			_position_draw_anchor("EnemyDeckAnchor", deck_rect)
	var center_x: float = size.x / 2
	var center_width: float = maxf(1.0, size.x - 2.0 * width - 20.0)
	var turn_text: String = "%s  ·  第 %02d 轮" % ["我方行动" if battle.active_side == 0 else "敌方行动", ceili(float(battle.turn) / 2)]
	draw_string(font, Vector2(center_x - center_width / 2, 24), turn_text, HORIZONTAL_ALIGNMENT_CENTER, center_width, 15 if narrow else 18, Color("e6cb94") if battle.active_side == 0 else Color("e5aaa1"))
	var subtitle: String = subtitle_text()
	tooltip_text = subtitle
	draw_string(font, Vector2(center_x - center_width / 2, 48), _fit_text(subtitle, center_width, 12 if narrow else 13), HORIZONTAL_ALIGNMENT_CENTER, center_width, 12 if narrow else 13, Color("b0c1d0"))
	var clock_width: float = minf(210, center_width - 8)
	var clock := Rect2(Vector2(center_x - clock_width / 2, 61), Vector2(clock_width, 3))
	draw_rect(clock, Color("314359"))
	var remaining: float = clampf(battle.time_remaining / 90.0, 0, 1)
	draw_rect(Rect2(clock.position, Vector2(clock_width * remaining, 3)), Color("ef998c") if battle.time_remaining <= 15 else Color("c3ac76"))
	draw_line(Vector2(0, 71), Vector2(size.x, 71), Color("4c5360"), 1)

func _fit_text(value: String, available: float, font_size: int) -> String:
	var font: Font = get_theme_default_font()
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= available: return value
	while value.length() > 1 and font.get_string_size(value + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		value = value.left(value.length() - 1)
	return value + "…"

func _draw_small_stack(rect: Rect2, caption: String, accent: Color) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("21344d")
	panel.border_color = accent
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(2)
	panel.draw(get_canvas_item(), Rect2(rect.position + Vector2(2, -2), rect.size))
	panel.draw(get_canvas_item(), rect)
	var c := rect.get_center()
	draw_polyline(PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 0), c + Vector2(0, 8), c + Vector2(-6, 0), c + Vector2(0, -8)]), accent, 1, true)
	draw_string(get_theme_default_font(), Vector2(rect.position.x - 6, 59), caption, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x + 12, 11, Color("c6d0dc"))

func _position_draw_anchor(node_name: String, rect: Rect2) -> void:
	var anchor: Control = owner.get_node_or_null("%" + node_name) as Control
	if anchor == null: return
	anchor.global_position = global_position + rect.position
	anchor.size = rect.size
