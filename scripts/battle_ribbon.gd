extends HBoxContainer
## Public battle state, rendered as a game HUD rather than a text report.

const Art = preload("res://scripts/art_library.gd")
var battle: Battle
var hud_visible: bool = false
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

func _draw() -> void:
	if battle == null or not hud_visible: return
	var font: Font = get_theme_default_font()
	var width: float = minf(340, size.x * 0.32)
	for side: int in range(2):
		var origin := Vector2(0 if side == 0 else size.x - width, 0)
		var accent := Color("80d5dc") if side == 0 else Color("f4a294")
		var commander: Dictionary = battle.commander(side)
		var player: Dictionary = battle.players[side]
		var hp: int = int(commander.get("hp", 0))
		var center: Vector2 = origin + Vector2(31, 34)
		draw_circle(center, 29, Color("15283f"))
		Art.draw_round_portrait(self, Art.get_texture(battle.hero(side).portrait), center, 26)
		draw_arc(center, 28, 0, TAU, 48, Color("c5ad77"), 2, true)
		draw_string(font, origin + Vector2(70, 22), battle.hero(side).name, HORIZONTAL_ALIGNMENT_LEFT, width - 75, 17, Color("f1e7cc"))
		var bar := Rect2(origin + Vector2(70, 32), Vector2(width - 83, 8))
		draw_rect(bar, Color("091525"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp / 20.0, bar.size.y)), accent)
		draw_rect(bar, Color("9c916f"), false, 1)
		draw_string(font, origin + Vector2(70, 60), "%d/20" % hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("d6e1e4"))
		for index: int in range(10):
			var gem: Vector2 = origin + Vector2(124 + index * minf(14, (width - 190) / 10.0), 55)
			if gem.x > origin.x + width - 12: break
			var color := Color("79c7e4") if index < player.mana else (Color("536d80") if index < player.max_mana else Color("263b50"))
			draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -5), gem + Vector2(4, 0), gem + Vector2(0, 5), gem + Vector2(-4, 0)]), color)
		draw_string(font, origin + Vector2(width - 57, 60), "%d/%d" % [player.mana, player.max_mana], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c1dce9"))
	var center_x: float = size.x / 2
	var turn_text: String = "第 %02d 轮  ·  %s" % [ceili(float(battle.turn) / 2), "我方行动" if battle.active_side == 0 else "敌方行动"]
	var text_width: float = font.get_string_size(turn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(font, Vector2(center_x - text_width / 2, 27), turn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("eddbac"))
	var weather: String = battle.WEATHER[battle.weather].name
	var subtitle: String = "%s  /  %s" % [battle.map_definition.name, weather]
	text_width = font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(center_x - text_width / 2, 51), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a8bdcd"))
	var clock_width: float = minf(220, size.x * 0.26)
	var clock := Rect2(Vector2(center_x - clock_width / 2, 61), Vector2(clock_width, 3))
	draw_rect(clock, Color("314359"))
	var remaining: float = clampf(battle.time_remaining / 90.0, 0, 1)
	draw_rect(Rect2(clock.position, Vector2(clock_width * remaining, 3)), Color("ef998c") if battle.time_remaining <= 15 else Color("c3ac76"))
	draw_line(Vector2(0, 71), Vector2(size.x, 71), Color(0.7, 0.6, 0.4, 0.5), 1)
