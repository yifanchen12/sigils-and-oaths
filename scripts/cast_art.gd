extends RefCounted
## All positions are board cells. Rendering samples time and never advances the battle.

const ATLAS: Texture2D = preload("res://assets/art/actions/cast-seals-v1.png")
const Art = preload("res://scripts/art_library.gd")
const STYLES := {
	"fire_cast": [0, Color("ff9866")], "fire_area": [0, Color("ffac70")],
	"heal_cast": [1, Color("a0e39f")], "ward_cast": [2, Color("a8ddff")],
	"snare_cast": [3, Color("c6a0ed")], "frost_cast": [4, Color("8fcfff")],
	"arrival_cast": [5, Color("ffcf7b")], "order_cast": [5, Color("f1c97d")],
	"mobility_cast": [5, Color("8de0d9")], "shot_cast": [5, Color("ffdb8c")],
	"weather_cast": [5, Color("bfdddd")]}
const SKILLS := {"sword":"ward_cast", "spear":"ward_cast", "cavalry":"mobility_cast",
	"archer":"shot_cast", "mage":"fire_cast", "healer":"heal_cast"}
const WEATHER := {"rain": Color("8cbfee"), "snow": Color("daefff"), "sun": Color("ffd177"),
	"fog": Color("c4d1e7"), "tailwind": Color("91e6cc"), "lanterns": Color("ffc28a")}

static func style_for(action: Dictionary) -> String:
	if not action.has("visual_origin"): return ""
	if action.type == "unit_skill": return SKILLS.get(action.get("unit_kind", ""), "")
	if action.type not in ["play","hero"]: return ""
	if action.get("card_type") == "trap": return "snare_cast"
	if action.get("card_type") == "environment": return "weather_cast"
	match str(action.get("effect_kind", "")):
		"damage", "firestrike", "shatter_bolt": return "fire_cast"
		"area": return "fire_area"
		"heal", "renewal", "rally_heal", "cleanse_root": return "heal_cast"
		"shield", "blessing": return "ward_cast"
		"root": return "frost_cast"
		"muster", "redeploy": return "arrival_cast"
		"weather", "clear_weather": return "weather_cast"
		"march", "repulse", "exchange", "onslaught": return "mobility_cast"
		"reveal_traps": return "snare_cast"
	if action.get("card_type") == "unit": return "arrival_cast"
	return "order_cast"

static func stamp(canvas: CanvasItem, index: int, center: Vector2, size: Vector2, opacity: float) -> void:
	var cell := ATLAS.get_size() / Vector2(3,2)
	var offset := Vector2(index % 3, floori(index / 3.0)) * cell
	canvas.draw_texture_rect_region(ATLAS, Rect2(center - size / 2, size), Rect2(offset, cell).grow(-1), Color(1,1,1,clampf(opacity,0,1)))

static func star(canvas: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	if radius < 0.35 or color.a < 0.005: return
	var shape := PackedVector2Array()
	for i: int in range(8):
		shape.append(at + Vector2.from_angle(i * PI / 4.0) * radius * (0.22 if i % 2 else 1.0))
	canvas.draw_colored_polygon(shape, color)

static func draw_cast(board: Control, effect: Dictionary, tile: float) -> void:
	var at: Vector2 = board.cell_center(effect.cell)
	var start: Vector2 = board.cell_center(effect.from)
	var style: String = effect.kind
	var color: Color = effect.color
	var frame: int = int(STYLES[style][0])
	var t: float = clampf(effect.age / effect.duration,0,1)
	if board.reduced_motion:
		for cell: Vector2i in effect.cells:
			board.draw_rect(Rect2(board.cell_center(cell)-Vector2.ONE*tile*0.45, Vector2.ONE*tile*0.90), Color(color,0.55), false,1.5)
		stamp(board, frame, at+Vector2(tile*0.24,-tile*0.25), Vector2.ONE*tile*0.52,0.82)
		return
	var foot := at + Vector2.DOWN*tile*0.17
	if t < 0.39:
		var charge := clampf(t/0.19,0,1)
		var launch := clampf((t-0.17)/0.22,0,1)
		var radius := tile*lerpf(0.09,0.26,charge)
		for i: int in range(3):
			var theta: float = i*TAU/3 + charge*0.72
			board.draw_arc(start, radius, theta, theta+1.22, 10, Color(color,(1-launch)*0.92),2.0,true)
		star(board,start-Vector2(0,tile*0.08),tile*0.095*sin(charge*PI*0.72),Color(color,1-launch*0.8))
		if launch > 0 and start.distance_to(at) > tile*0.18 and style != "shot_cast":
			var head := start.lerp(at,launch)
			head.y -= sin(launch*PI)*tile*0.17
			var tail := start.lerp(at,maxf(0,launch-0.29))
			tail.y -= sin(maxf(0,launch-0.29)*PI)*tile*0.17
			board.draw_line(tail,head,Color(color,0.38),maxf(2,tile*0.085),true)
			board.draw_line(tail,head,Color(color.lightened(0.5),0.93),maxf(1,tile*0.027),true)
			star(board,head,tile*0.13,Color.WHITE)
		return
	var hit := (t-0.39)/0.61
	var appear := smoothstep(0.0,0.14,hit)
	var fade := 1.0-smoothstep(0.55,1.0,hit)
	var strength := appear*fade
	var extent := tile*(0.91 + 0.25*sin(minf(1,hit*2.8)*PI/2))
	if style == "fire_area": extent *= 1.15
	if style in ["mobility_cast","shot_cast"]: extent *= 0.7
	if style == "weather_cast":
		_weather(board, at, tile, hit, color, str(effect.get("weather", "")), strength)
	else:
		if style == "ward_cast" and effect.get("guard",false):
			for cell: Vector2i in effect.cells:
				if cell == effect.cell: continue
				var ally: Vector2 = board.cell_center(cell)
				board.draw_line(at, ally, Color(color,strength*0.72),maxf(1.7,tile*0.043),true)
				stamp(board,frame,ally+Vector2(0,-tile*0.16),Vector2.ONE*tile*0.60,strength*0.76)
		elif effect.cells.size() > 1:
			for cell: Vector2i in effect.cells:
				var center: Vector2 = board.cell_center(cell)
				var rect := Rect2(center-Vector2.ONE*tile*0.46, Vector2.ONE*tile*0.92)
				board.draw_rect(rect,Color(color,strength*0.14))
				board.draw_rect(rect,Color(color,strength*0.65),false,1.6)
				if cell != effect.cell:
					var distance: float = Vector2(cell-effect.cell).length()
					var wave := clampf((hit-distance*0.075)*2.0,0,1)
					if wave > 0 and wave < 1 and style in ["fire_area","heal_cast","frost_cast","arrival_cast"]:
						var icon := 5 if style == "fire_area" and effect.get("martial",false) else frame
						stamp(board,icon,center-Vector2(0,tile*(0.05+wave*0.10)),Vector2.ONE*tile*(0.42+wave*0.26),sin(wave*PI)*0.72)
					else: star(board,center,tile*(0.18-hit*0.08),Color(color,strength*0.81))
		var lift: float = tile*(0.08+hit*0.14) if style == "heal_cast" else tile*0.14
		var tint_frame := 5 if style == "fire_area" and effect.get("martial",false) else frame
		stamp(board,tint_frame,foot-Vector2(0,lift+extent*0.14),
			Vector2(extent*(0.72+appear*0.28),extent*(0.76+appear*0.24)),strength*0.94)
	var spread := (0.21 + 0.29*hit)*tile
	for i: int in range(5):
		var direction := Vector2.from_angle(i*TAU/5-0.71)
		var p := foot + direction*spread
		star(board,p, maxf(0.5,tile*(0.038+0.025*sin(i*2.1+hit*PI)))*fade, Color(color,strength*0.85))

static func _weather(board: Control, at: Vector2, tile: float, hit: float, color: Color, name: String, alpha: float) -> void:
	var grid: Rect2 = board.grid_rect()
	var front := grid.position.x + (grid.size.x + tile)*hit
	for i: int in range(14):
		var y := grid.position.y + grid.size.y * (i+0.5)/14.0
		var p := Vector2(front-tile*(0.4+0.38*sin(i*2.6)),y)
		if not grid.grow(-tile*0.13).has_point(p): continue
		match name:
			"rain": board.draw_line(p,p+Vector2(-0.06,0.16)*tile,Color(color,0.83*alpha),2,true)
			"snow", "sun", "lanterns": star(board,p,tile*0.068,Color(color,0.85*alpha))
			_: board.draw_line(p,p+Vector2(0.21,-0.045)*tile,Color(color,0.58*alpha),2,true)
	board.draw_arc(at,tile*(0.26+hit*0.34),0,TAU,40,Color(color,alpha*0.83),2,true)
	star(board,at-Vector2(0,tile*0.25),tile*0.16,Color(color,alpha))

static func draw_title(board: Control, effect: Dictionary) -> void:
	var area: Rect2 = board.grid_rect().intersection(Rect2(Vector2.ZERO,board.size)).grow(-5)
	if area.size.x < 180 or area.size.y < 120: return
	var portrait: Texture2D = Art.get_texture(effect.portrait)
	if portrait == null: return
	var t: float = effect.age/effect.duration
	var opacity := smoothstep(0.0,0.13,t)*(1.0-smoothstep(0.68,0.97,t))
	if opacity < 0.02: return
	var width := minf(222.0,area.size.x*0.47)
	var height := clampf(area.size.y*0.10,36.0,55.0)
	var right: bool = board.cell_center(effect.cell).x < area.get_center().x
	var x: float = area.end.x-width if right else area.position.x
	x += (1.0-opacity)*14.0*(1.0 if right else -1.0)
	var where := Vector2(x,area.position.y+3)
	var points := PackedVector2Array([where,where+Vector2(width,0),where+Vector2(width-15,height),where+Vector2(0,height)])
	var color: Color = effect.color
	board.draw_colored_polygon(points,Color(0.065,0.105,0.16,opacity*0.93))
	board.draw_line(where,where+Vector2(width,0),Color(color,opacity),2.4,true)
	board.draw_line(where+Vector2(0,height),where+Vector2(width-15,height),Color(color,opacity*0.72),1.3,true)
	var side := height-4.0
	var image_size := portrait.get_size()
	var crop := minf(image_size.x,image_size.y)*0.84
	var source := Rect2((image_size.x-crop)/2.0,maxf(0,(image_size.y-crop)*0.22),crop,crop)
	board.draw_texture_rect_region(portrait,Rect2(where+Vector2(2,2),Vector2.ONE*side),source,Color(1,1,1,opacity))
	var font_size := clampi(roundi(height*0.40),14,22)
	var pos := where+Vector2(side+10,height*0.50+font_size*0.33)
	board.draw_string(board.get_theme_default_font(), pos, effect.title, HORIZONTAL_ALIGNMENT_LEFT,
		width-side-29,font_size,Color(1.0,0.965,0.88,opacity))
