extends RefCounted
## All positions are board cells. Rendering samples time and never advances the battle.

const ATLAS: Texture2D = preload("res://assets/art/actions/cast-seals-v1.png")
const SIGNATURE_ATLAS: Texture2D = preload("res://assets/art/actions/river-signatures-v1.png")
const FIELD_ATLAS: Texture2D = preload("res://assets/art/actions/field-strokes-v1.png")
const SKY_ATLAS: Texture2D = preload("res://assets/art/actions/weather-cels-v1.png")
const HAMMER: Texture2D = preload("res://assets/art/actions/hollow-hammer-v1.png")
const HAMMER_CONTACT := 0.31
const HAMMER_DURATION := 0.96
const SKY_CELS := {"rain":0, "snow":1, "sun":2, "fog":3, "tailwind":4, "lanterns":5}
const SKY_LIGHT := {"rain":Color("244d73"), "snow":Color("b3d5e5"), "sun":Color("efb65c"),
	"fog":Color("b1abc7"), "tailwind":Color("71c8ad"), "lanterns":Color("283656")}
enum Signature { BULWARK, COMET, WILLOW, MOORING, COUNTER, GUARD }
enum Stroke { SHIELD, RIDE, ARROW, FIRE, LEAVES, ICE }
const TROOP_STROKES := {"sword":Stroke.SHIELD, "cavalry":Stroke.RIDE, "archer":Stroke.ARROW, "mage":Stroke.FIRE, "healer":Stroke.LEAVES}
const COMMANDER_SIGNATURES := {"blessing":Signature.BULWARK, "firestrike":Signature.COMET, "renewal":Signature.WILLOW}
const Art = preload("res://scripts/art_library.gd")
const STYLES := {
	"fire_cast": [0, Color("ff9866")], "fire_area": [0, Color("ffac70")],
	"heal_cast": [1, Color("a0e39f")], "ward_cast": [2, Color("a8ddff")],
	"snare_cast": [3, Color("c6a0ed")], "frost_cast": [4, Color("8fcfff")],
	"arrival_cast": [5, Color("ffcf7b")], "order_cast": [5, Color("f1c97d")],
	"mobility_cast": [5, Color("8de0d9")], "shot_cast": [5, Color("ffdb8c")],
	"weather_cast": [5, Color("bfdddd")], "works_cast": [5, Color("dec38f")],
	"signal_cast": [5, Color("efc373")]}
const SKILLS := {"sword":"ward_cast", "spear":"ward_cast", "cavalry":"mobility_cast",
	"archer":"shot_cast", "mage":"fire_cast", "healer":"heal_cast"}
const WEATHER := {"rain": Color("8cbfee"), "snow": Color("daefff"), "sun": Color("ffd177"),
	"fog": Color("c4d1e7"), "tailwind": Color("91e6cc"), "lanterns": Color("ffc28a")}

static func style_for(action: Dictionary) -> String:
	if not action.has("visual_origin"): return ""
	if action.type == "unit_skill": return SKILLS.get(action.get("unit_kind", ""), "")
	if action.type not in ["play","hero"]: return ""
	if action.get("card_type") == "trap": return "snare_cast"
	match str(action.get("effect_kind", "")):
		"damage", "firestrike", "shatter_bolt": return "fire_cast"
		"area": return "fire_area"
		"heal", "renewal", "rally_heal", "cleanse_root": return "heal_cast"
		"shield", "blessing": return "ward_cast"
		"root": return "frost_cast"
		"muster", "redeploy": return "arrival_cast"
		"weather", "clear_weather": return "weather_cast"
		"terrain", "roadwork": return "works_cast"
		"scheduled": return "signal_cast"
		"march", "repulse", "exchange", "onslaught": return "mobility_cast"
		"reveal_traps": return "snare_cast"
	if action.get("card_type") == "unit": return "arrival_cast"
	return "order_cast"

static func stamp(canvas: CanvasItem, index: int, center: Vector2, size: Vector2, opacity: float, atlas: Texture2D = ATLAS) -> void:
	var cell := atlas.get_size() / Vector2(3,2)
	var offset := Vector2(index % 3, floori(index / 3.0)) * cell
	canvas.draw_texture_rect_region(atlas, Rect2(center - size / 2, size), Rect2(offset, cell).grow(-1), Color(1,1,1,clampf(opacity,0,1)))

static func field_stroke(action: Dictionary, style: String) -> int:
	if action.type == "unit_skill": return TROOP_STROKES.get(action.get("unit_kind",""), -1)
	if action.get("card_type") != "spell": return -1
	match style:
		"fire_cast": return Stroke.FIRE if action.get("spell_effect") in ["damage", "shatter_bolt"] else -1
		"frost_cast": return Stroke.ICE
		"heal_cast": return Stroke.LEAVES if action.get("spell_effect") != "pullback" else -1
		"ward_cast": return Stroke.SHIELD if action.get("spell_effect") != "recall" else -1
	return -1

static func oriented_stroke(board: Control, stroke: int, at: Vector2, direction: Vector2, size: Vector2, alpha: float) -> void:
	board.draw_set_transform(at, direction.angle())
	stamp(board, stroke, Vector2.ZERO, size, alpha, FIELD_ATLAS)
	board.draw_set_transform(Vector2.ZERO)

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
	var signature: int = effect.get("signature", -1)
	var stroke: int = effect.get("stroke", -1)
	var t: float = clampf(effect.age / effect.duration,0,1)
	if effect.get("hammer", false):
		_draw_hammer(board, effect, tile)
		return
	if style == "weather_cast":
		_draw_weather_cast(board, effect, tile, t)
		return
	if board.reduced_motion:
		for cell: Vector2i in effect.cells:
			board.draw_rect(Rect2(board.cell_center(cell)-Vector2.ONE*tile*0.45, Vector2.ONE*tile*0.90), Color(color,0.55), false,1.5)
		var badge := at + Vector2(tile*0.24,-tile*0.25)
		if stroke >= 0: stamp(board,stroke,badge,Vector2.ONE*tile*0.82,1.0,FIELD_ATLAS)
		else: stamp(board, signature if signature >= 0 else frame, badge, Vector2.ONE*tile*0.60,0.9, SIGNATURE_ATLAS if signature >= 0 else ATLAS)
		if style == "fire_area":
			for cell: Vector2i in effect.get("struck", []):
				star(board,board.cell_center(cell)-Vector2(0,tile*0.22),tile*0.13,Color("fff0ba"))
		return
	if effect.get("sprung",false):
		_draw_signature(board,effect,signature,at,tile,t)
		return
	if stroke == Stroke.RIDE:
		_draw_ride(board, effect, tile, t)
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
			if stroke == Stroke.FIRE:
				oriented_stroke(board, stroke, head, head-tail, Vector2.ONE*tile*1.10, minf(1.0,launch*5.0))
			else: star(board,head,tile*0.13,Color.WHITE)
		return
	var hit := (t-0.39)/0.61
	if signature >= 0:
		_draw_signature(board, effect, signature, at, tile, hit)
		return
	if stroke >= 0:
		_draw_field_hit(board, effect, stroke, at, tile, hit)
		return
	if style == "fire_area":
		_draw_volley(board,effect,tile,hit)
		return
	if style in ["signal_cast","works_cast"]:
		_draw_ground_signal(board,effect,tile,hit)
		return
	var appear := smoothstep(0.0,0.14,hit)
	var fade := 1.0-smoothstep(0.55,1.0,hit)
	var strength := appear*fade
	var extent := tile*(0.91 + 0.25*sin(minf(1,hit*2.8)*PI/2))
	if style in ["mobility_cast","shot_cast"]: extent *= 0.7
	if effect.cells.size() > 1:
		for cell: Vector2i in effect.cells:
			var center: Vector2 = board.cell_center(cell)
			var rect := Rect2(center-Vector2.ONE*tile*0.46, Vector2.ONE*tile*0.92)
			board.draw_rect(rect,Color(color,strength*0.14))
			board.draw_rect(rect,Color(color,strength*0.65),false,1.6)
			if cell != effect.cell:
				var wave := clampf((hit-Vector2(cell-effect.cell).length()*0.075)*2.0,0,1)
				if wave > 0 and wave < 1 and style in ["heal_cast","frost_cast","arrival_cast"]:
					stamp(board,frame,center-Vector2(0,tile*(0.05+wave*0.10)),Vector2.ONE*tile*(0.42+wave*0.26),sin(wave*PI)*0.72)
				else: star(board,center,tile*(0.18-hit*0.08),Color(color,strength*0.81))
	var lift: float = tile*(0.08+hit*0.14) if style == "heal_cast" else tile*0.14
	stamp(board,frame,foot-Vector2(0,lift+extent*0.14),
		Vector2(extent*(0.72+appear*0.28),extent*(0.76+appear*0.24)),strength*0.94)
	var spread := (0.21 + 0.29*hit)*tile
	for i: int in range(5):
		var direction := Vector2.from_angle(i*TAU/5-0.71)
		var p := foot + direction*spread
		star(board,p, maxf(0.5,tile*(0.038+0.025*sin(i*2.1+hit*PI)))*fade, Color(color,strength*0.85))

static func _draw_ride(board: Control, effect: Dictionary, tile: float, t: float) -> void:
	var route: Array = effect.route
	if route.size() < 2: return
	var progress: float = board.motion_progress if board.motion_unit == effect.rider else 1.0
	var travelled := progress * (route.size()-1)
	var fade := 1.0-smoothstep(0.43, 0.96, t)
	for i: int in range(route.size()-1):
		var ratio := clampf(travelled-i, 0, 1)
		if ratio <= 0: break
		var a: Vector2 = board.cell_center(route[i]) + Vector2.DOWN*tile*0.22
		var b: Vector2 = board.cell_center(route[i+1]) + Vector2.DOWN*tile*0.22
		var tip := a.lerp(b, ratio)
		board.draw_line(a, tip, Color(Color("77daca"),0.62*fade), maxf(2,tile*0.065),true)
		oriented_stroke(board, Stroke.RIDE, a.lerp(tip,0.50), b-a, Vector2.ONE*tile*0.72, fade*minf(ratio*2,1))
	if progress >= 0.98:
		var at: Vector2 = board.cell_center(route.back()) + Vector2.DOWN*tile*0.22
		board.draw_arc(at,tile*(0.15+0.31*t),0.12,PI-0.12,18,Color(Color("c8f4dd"),fade),2,true)

static func _draw_field_hit(board: Control, effect: Dictionary, stroke: int, at: Vector2, tile: float, hit: float) -> void:
	var alpha := smoothstep(0,0.10,hit)*(1.0-smoothstep(0.63,1,hit))
	var bloom := sin(minf(hit*2.7,1.0)*PI)
	var center := at - Vector2(0, tile*0.13)
	var size := Vector2.ONE*tile
	if effect.cells.size() > 1:
		for cell: Vector2i in effect.cells:
			var rect := Rect2(Vector2(board.cell_center(cell)) - size*0.45,size*0.90)
			board.draw_rect(rect,Color(effect.color,alpha*0.12))
			board.draw_rect(rect,Color(effect.color,alpha*0.62),false,1.6)
		for cell: Vector2i in effect.get("recipients",[]):
			if cell == effect.cell: continue
			var wave := clampf((hit-0.07*Vector2(cell-effect.cell).length())*1.7,0,1)
			if wave > 0 and wave < 1:
				stamp(board,stroke,board.cell_center(cell)-Vector2(0,tile*(0.04+wave*0.26)),size*(0.76+wave*0.22),sin(PI*wave)*0.9,FIELD_ATLAS)
	match stroke:
		Stroke.SHIELD:
			center.y += tile*0.25*(1.0-smoothstep(0,0.28,hit))
			stamp(board,stroke,center,size*Vector2(1.19+0.08*bloom,0.75+0.48*smoothstep(0,0.22,hit)),alpha,FIELD_ATLAS)
			board.draw_arc(center,tile*(0.26+0.34*hit),-PI*0.91,-PI*0.09,24,Color(Color("c3ebff"),alpha*(1-hit)),2,true)
		Stroke.FIRE, Stroke.ARROW:
			var direction: Vector2 = (at-board.cell_center(effect.from)).normalized()
			if direction.is_zero_approx(): direction = Vector2.RIGHT
			if stroke == Stroke.FIRE: stamp(board,0,center,size*(1.04+bloom*0.42),alpha,ATLAS)
			for i: int in range(5):
				var dir := direction.rotated((i-2)*0.48)
				var point := at + dir*tile*(0.19+0.56*hit)
				board.draw_line(point-dir*tile*(1-hit)*0.24,point,Color(effect.color,alpha),maxf(1.5,tile*0.043),true)
				star(board,point,tile*(0.072 if i==2 else 0.044)*alpha, Color("fff4ce"))
		Stroke.LEAVES:
			center.y -= tile*hit*0.33
			stamp(board,stroke,center,size*(0.90+0.33*smoothstep(0,0.31,hit)),alpha,FIELD_ATLAS)
			for i: int in range(3):
				var mote := at+Vector2(sin(hit*4.1+i*2.3)*0.40,0.06-hit*0.66-i*0.10)*tile
				star(board,mote,tile*0.061,Color(Color("f8e492"),alpha))
		Stroke.ICE:
			var grow := smoothstep(0,0.29,hit)
			var extent := size*Vector2(1.28+0.10*bloom,0.24+grow*1.09)
			center.y = at.y+tile*0.16-extent.y*0.28
			stamp(board,stroke,center,extent,alpha,FIELD_ATLAS)
			for i: int in range(3):
				var shard := at+Vector2((i-1)*(0.26+hit*0.26),-sin(hit*PI)*(0.42+0.12*i))*tile
				star(board,shard,tile*0.068,Color(Color("d3f7ff"),alpha))

static func _draw_signature(board: Control, effect: Dictionary, signature: int, at: Vector2, tile: float, hit: float) -> void:
	var appear := smoothstep(0, 0.19, hit)
	var fade := 1.0 - smoothstep(0.59, 1, hit)
	var alpha := appear * fade
	var color: Color = effect.color
	var size := Vector2.ONE * tile
	var center := at - Vector2(0, tile * 0.16)
	match signature:
		Signature.BULWARK, Signature.GUARD:
			for cell: Vector2i in effect.cells:
				if cell == effect.cell: continue
				var ally: Vector2 = board.cell_center(cell)
				var tip := at.lerp(ally, smoothstep(0.07, 0.45, hit))
				board.draw_line(at, tip, Color(color, alpha * 0.86), maxf(1.8, tile*0.045), true)
				stamp(board, 2, ally - Vector2(0, tile*0.17), size*0.62, alpha*smoothstep(0.15,0.46,hit))
			center.y += (1.0-appear)*tile*0.38
			size *= Vector2(1.16, 0.45+0.70*appear)
		Signature.COMET:
			var fall := smoothstep(0, 0.34, hit)
			var impact := at + Vector2(0, tile*0.13)
			size *= 1.53
			# The bright tip is at the lower left of the source cel.
			center = impact + size*Vector2(0.28,-0.30) + Vector2(0.60,-0.72)*tile*(1.0-fall)
			if hit >= 0.28:
				var spread := smoothstep(0.28, 0.83, hit)
				for i: int in range(5):
					var direction := Vector2.from_angle(-PI*(i+0.5)/5.0)
					board.draw_line(impact+direction*tile*(0.05+0.30*spread), impact+direction*tile*(0.18+0.50*spread), Color(Color("ffe2a5"),(1.0-spread)*fade), maxf(1.4,tile*0.035),true)
		Signature.WILLOW:
			for cell: Vector2i in effect.cells:
				if cell == effect.cell: continue
				var ally: Vector2 = board.cell_center(cell)
				var distance := Vector2(cell-effect.cell).length()
				var wave := clampf((hit-minf(0.32,distance*0.07))/0.52, 0, 1)
				if wave <= 0 or wave >= 1: continue
				var tip := at.lerp(ally, wave) - Vector2(0, sin(wave*PI)*tile*0.21)
				star(board, tip, tile*0.10, Color(color, sin(wave*PI)))
				stamp(board, signature, ally-Vector2(0,tile*(0.10+0.25*wave)), size*(0.47+0.24*wave), sin(wave*PI)*0.87, SIGNATURE_ATLAS)
			center.y -= hit*tile*0.22
			size *= 1.13
		Signature.MOORING:
			var snap := sin(minf(hit*2.7, 1.0)*PI) if effect.get("sprung", false) else 0.0
			center.y += tile*0.12
			if not effect.get("sprung", false): center.y -= (1.0-appear)*tile*0.26
			size *= Vector2(1.18-snap*0.35, 0.68+snap*0.42)
		Signature.COUNTER:
			var flare := sin(minf(hit*2.6, 1.0)*PI)
			size *= 0.87 + 0.36*flare
			for i: int in range(3):
				var direction := Vector2.from_angle((i-1)*0.66-0.6)
				var ray := hit if effect.get("sprung", false) else 1.0-hit
				star(board, at+direction*tile*(0.43+ray*0.35), tile*0.11*flare, Color(color,alpha))
	stamp(board, signature, center, size, alpha, SIGNATURE_ATLAS)

static func _draw_weather_cast(board: Control, effect: Dictionary, tile: float, t: float) -> void:
	var visible_field: Rect2 = board.grid_rect().intersection(Rect2(Vector2.ZERO,board.size))
	var area := visible_field.grow(-tile*0.46)
	if area.size.x < tile or area.size.y < tile: return
	var clearing: bool = effect.weather == "clear"
	var sky: String = effect.get("previous_weather","clear") if clearing else effect.weather
	if not SKY_CELS.has(sky): return
	var index: int = SKY_CELS[sky]
	var ink: Color = WEATHER[sky]
	var source: Vector2 = board.cell_center(effect.from)
	var badge := (source-Vector2(0,tile*0.55)).clamp(area.position,area.end)
	# The old weather dissolves on dispel. A clear sky never plays the blazing-sun buff.
	if board.reduced_motion:
		board.draw_rect(visible_field.grow(-3),Color(ink,0.80), false,2)
		stamp(board,index,badge,Vector2.ONE*tile*0.84,0.96,SKY_ATLAS)
		if clearing: board.draw_line(badge+Vector2(-0.31,0.31)*tile,badge+Vector2(0.31,-0.31)*tile,Color.WHITE,3,true)
	else:
		var alpha := smoothstep(0,0.13,t)*(1.0-smoothstep(0.76,1,t))
		_weather_light(board,visible_field,sky,t,tile,alpha*(1.0-t if clearing else 1.0))
		stamp(board,index,badge,Vector2.ONE*tile*(0.66+0.29*sin(t*PI)),alpha,SKY_ATLAS)
		var count := 2 if sky == "sun" else (4 if sky in ["rain","fog"] else 7)
		for i: int in range(count):
			var lane := Vector2(fposmod(0.19+i*0.618,1), fposmod(0.13+i*0.382+i%3*0.17,1))
			var wave := clampf((t-0.07-lane.x*0.27)/0.62,0,1)
			if wave <= 0 or wave >= 1: continue
			var pos: Vector2 = area.position + lane*area.size
			var strength := sin(wave*PI)*alpha
			var size := Vector2.ONE*tile*(0.53+0.12*(i%3))
			var drift := Vector2.ZERO
			match sky:
				"rain": drift = Vector2(-0.43,0.85)*tile*wave
				"snow": drift = Vector2(sin(i+wave*3)*0.24,wave*0.58)*tile
				"fog":
					size *= Vector2(2.45,1.25)
					drift.x = tile*(wave-0.5)*1.65
				"tailwind": drift = Vector2(wave*1.45,-0.19*sin(wave*PI))*tile
				"lanterns": drift = Vector2(sin(i+wave*4)*0.13,-0.94*wave)*tile
				"sun":
					var end := pos+Vector2(-0.74,1.18)*tile
					board.draw_colored_polygon(PackedVector2Array([pos,pos+Vector2.RIGHT*tile*0.09,end+Vector2.RIGHT*tile*0.32,end]),Color(ink,strength*0.24))
					size *= 0.80
			if clearing:
				drift += (pos-area.get_center()).normalized()*tile*wave
				strength *= 1.0-smoothstep(0.3,1.0,wave)
			pos += drift
			if visible_field.encloses(Rect2(pos-size/2,size)):
				stamp(board,index,pos,size,strength*(0.60 if sky == "fog" else 0.86),SKY_ATLAS)
	for cell: Vector2i in effect.get("recipients",[]):
		var foot: Vector2 = board.cell_center(cell)+Vector2(0,tile*0.19)
		var glow := 0.88 if board.reduced_motion else sin(t*PI)
		board.draw_arc(foot,tile*0.32,-PI*0.1,PI*1.10,24,Color(Color("a9e9bd"),glow),2,true)

static func _weather_light(board: Control, field: Rect2, sky: String, t: float, tile: float, alpha: float) -> void:
	var ink: Color = WEATHER[sky]
	board.draw_rect(field, Color(SKY_LIGHT[sky],alpha*(0.28 if sky == "lanterns" else 0.16)))
	match sky:
		"rain", "snow":
			for i: int in range(38):
				var near := 0.45+float(i%5)*0.12
				var x := fposmod(i*0.618-t*(0.14 if sky == "rain" else 0.025),1)
				var y := fposmod(i*0.293+t*(1.25 if sky == "rain" else 0.36)*near,1)
				var pt := field.position+Vector2(x,y)*field.size
				if sky == "rain":
					var tail := pt+Vector2(0.24,-0.60)*tile*near
					if field.has_point(tail): board.draw_line(tail,pt,Color(ink.lightened(0.42),alpha*near*0.82),maxf(1.1,tile*0.028*near),true)
				else: star(board,pt,tile*near*0.061,Color(Color("effcff"),alpha*near))
		"sun":
			for i: int in range(3):
				var top := field.position+Vector2(field.size.x*(0.36+i*0.24+t*0.018),0)
				var bottom := Vector2(maxf(field.position.x,top.x-field.size.y*0.34),field.end.y)
				var quad := PackedVector2Array([top,top+Vector2.RIGHT*tile*0.29,bottom+Vector2.RIGHT*tile*0.94,bottom])
				board.draw_polygon(quad,PackedColorArray([Color(ink,alpha*0.29),Color(ink,alpha*0.26),Color(ink,0.01),Color(ink,0.06)]))
		"fog", "tailwind":
			for band: int in range(3):
				var top := PackedVector2Array()
				var bottom := PackedVector2Array()
				for i: int in range(23):
					var u := float(i)/22
					var y := field.size.y*(0.20+0.28*band)+sin(u*5.6+band*1.8-t*4.8)*tile*0.27
					var point := field.position+Vector2(field.size.x*u,y)
					top.append(point)
					bottom.append(point+Vector2.DOWN*tile*(0.18+0.53*sin(u*PI)))
				if sky == "fog":
					bottom.reverse()
					top.append_array(bottom)
					board.draw_colored_polygon(top,Color(ink,alpha*0.14))
				else: board.draw_polyline(top,Color(ink,alpha*0.37),maxf(1.4,tile*0.028),true)
		"lanterns":
			for i: int in range(21):
				var lane := Vector2(fposmod(i*0.618+sin(t*3+i)*0.009,1),fposmod(i*0.392-t*0.23,1))
				var spark := field.position+field.size*lane
				star(board,spark,tile*(0.028+i%3*0.021),Color(Color("ffdfa3"),alpha*0.88))

static func hammer_contact(cell: Vector2i, center: Vector2i) -> float:
	return HAMMER_CONTACT + Vector2(cell-center).length()*0.065

static func _draw_hammer(board: Control, effect: Dictionary, tile: float) -> void:
	var age: float = effect.age
	var center: Vector2 = board.cell_center(effect.cell)
	var size := Vector2.ONE * tile * (0.74 if board.reduced_motion else 1.52)
	var gold := Color("edc788")
	var jade := Color("8be5d2")
	for cell: Vector2i in effect.cells:
		var ground: Vector2 = board.cell_center(cell)
		var elapsed := age - hammer_contact(cell, effect.cell)
		var pulse := 0.6 if board.reduced_motion else (1.0-smoothstep(0.03,0.40,elapsed) if elapsed >= 0 else 0.09)
		var square := Rect2(ground - Vector2.ONE*tile*0.46, Vector2.ONE*tile*0.92)
		board.draw_rect(square, Color(gold, pulse*0.16))
		board.draw_rect(square, Color(gold, pulse*0.85),false,maxf(1.3,tile*0.035))
		if effect.struck.has(cell) and (board.reduced_motion or elapsed >= 0.0):
			star(board,ground-Vector2(0,tile*0.1),tile*(0.12+0.16*pulse),Color(jade,pulse))
	if board.reduced_motion:
		board.draw_texture_rect(HAMMER,Rect2(center+Vector2(tile*0.28,-tile*0.23)-size/2,size),false)
		return
	var drop := clampf(age/HAMMER_CONTACT,0.0,1.0)
	var foot := center + Vector2(0,tile*(0.18 - 1.60*(1.0-drop*drop*drop)))
	if drop < 1.0:
		board.draw_set_transform(center, 0, Vector2(1,0.30))
		board.draw_circle(Vector2.ZERO,tile*(0.14+0.18*drop),Color(Color("192f34"),0.18+0.30*drop))
		board.draw_set_transform(Vector2.ZERO)
		for side: int in [-1,1]:
			var edge := foot+Vector2(side*tile*0.27,-tile*0.72)
			board.draw_line(edge-Vector2(0,tile*(0.12+0.60*drop)),edge,Color(jade,drop*0.74),maxf(1.5,tile*0.036),true)
	var opacity := smoothstep(0,0.09,age)*(1.0-smoothstep(0.39,0.73,age))
	board.draw_texture_rect(HAMMER,Rect2(foot-Vector2(size.x*0.5,size.y*0.92),size),false,Color(1,1,1,opacity))
	if age >= HAMMER_CONTACT:
		var wave := clampf((age-HAMMER_CONTACT)/0.53,0,1)
		board.draw_set_transform(center+Vector2(0,tile*0.15),0,Vector2(1,0.40))
		board.draw_arc(Vector2.ZERO,tile*(0.15+0.85*sqrt(wave)),0,TAU,36,Color(jade,(1-wave)*0.84),maxf(1.2,tile*0.045),true)
		board.draw_set_transform(Vector2.ZERO)

static func volley_contact(cell: Vector2i, center: Vector2i) -> float:
	return 0.39+0.61*(minf(0.31,Vector2(cell-center).length()*0.078)+0.23*0.68)

static func _draw_volley(board: Control, effect: Dictionary, tile: float, t: float) -> void:
	var martial: bool = effect.get("martial",false)
	var color: Color = effect.color
	var hits: Array = effect.get("struck",[])
	for cell: Vector2i in effect.cells:
		var at: Vector2 = board.cell_center(cell)
		var distance: float = Vector2(cell-effect.cell).length()
		var phase := clampf((t-minf(0.31,distance*0.078))/0.68,0,1)
		var alpha := sin(phase*PI)
		var rect := Rect2(at-Vector2.ONE*tile*0.46,Vector2.ONE*tile*0.92)
		board.draw_rect(rect,Color(color,alpha*0.12))
		board.draw_rect(rect,Color(color,alpha*0.62),false,maxf(1.3,tile*0.028))
		if phase <= 0 or phase >= 1 or not hits.has(cell): continue
		var direction := Vector2(-0.40,0.92) if martial else Vector2(0.48,0.88)
		var drop := smoothstep(0.01,0.38,phase)
		var tip := at-direction*tile*(1.0-drop)*0.65
		if drop < 1:
			oriented_stroke(board,Stroke.ARROW if martial else Stroke.FIRE,tip-direction*tile*0.24,direction,Vector2.ONE*tile*0.82,alpha*1.35)
		if phase >= 0.23:
			var burst := smoothstep(0.23,0.55,phase)
			if martial:
				for sign_x: int in [-1,1]:
					var blade := Vector2(sign_x*0.48,-0.64)*tile
					board.draw_line(at+blade*(1-burst),at+blade*(1-burst-0.73),Color(Color("d5f3ff"),alpha),maxf(2.3,tile*0.08),true)
				star(board,at,tile*(0.30-0.14*phase),Color(Color("fff1b5"),alpha))
			else:
				var size := Vector2.ONE*tile*(0.81+0.43*burst)
				stamp(board,0,at-Vector2(0,tile*0.14),size,alpha,ATLAS)

static func _draw_ground_signal(board: Control, effect: Dictionary, tile: float, t: float) -> void:
	var alpha := smoothstep(0,0.12,t)*(1.0-smoothstep(0.62,1,t))
	for cell: Vector2i in effect.cells:
		var at: Vector2 = board.cell_center(cell)
		var wave := smoothstep(0,0.42,t-minf(0.23,Vector2(cell-effect.cell).length()*0.06))
		var size := Vector2.ONE*tile*0.87
		board.draw_rect(Rect2(at-size/2,size),Color(effect.color,alpha*wave*0.12))
		for corner: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var tip := at+corner*tile*(0.35+0.08*wave)
			board.draw_polyline(PackedVector2Array([tip-Vector2(corner.x,0)*tile*0.16,tip,tip-Vector2(0,corner.y)*tile*0.16]),Color(effect.color,alpha*wave),maxf(1.6,tile*0.045),true)
		if effect.kind == "works_cast":
			for j: int in range(3):
				var p := at+Vector2((j-1)*0.20,0.19-wave*0.14)*tile
				board.draw_line(p,p+Vector2(0.12,-0.10)*tile,Color(Color("ffedb8"),alpha*wave),maxf(2,tile*0.06),true)
	var center: Vector2 = board.cell_center(effect.cell)
	if effect.kind == "signal_cast": stamp(board,5,center-Vector2(0,tile*(0.10+0.12*t)),Vector2.ONE*tile*0.84,alpha,ATLAS)

static func draw_title(board: Control, effect: Dictionary) -> void:
	var area: Rect2 = board.grid_rect().intersection(Rect2(Vector2.ZERO,board.size)).grow(-5)
	if area.size.x < 180 or area.size.y < 120: return
	var portrait: Texture2D = Art.get_texture(effect.portrait)
	var t: float = effect.age/effect.duration
	var opacity := 1.0 if board.reduced_motion else smoothstep(0.0,0.13,t)*(1.0-smoothstep(0.68,0.97,t))
	if opacity < 0.02: return
	var caption: String = effect.get("caption","")
	var width := minf(297.0 if not caption.is_empty() else 260.0,area.size.x*0.53)
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
	if portrait != null:
		var image_size := portrait.get_size()
		var crop := minf(image_size.x,image_size.y)*0.84
		var source := Rect2((image_size.x-crop)/2.0,maxf(0,(image_size.y-crop)*0.22),crop,crop)
		board.draw_texture_rect_region(portrait,Rect2(where+Vector2(2,2),Vector2.ONE*side),source,Color(1,1,1,opacity))
	else:
		stamp(board,STYLES[effect.kind][0],where+Vector2.ONE*(side*0.5+2),Vector2.ONE*side,opacity)
	var font_size := clampi(roundi(height*(0.34 if not caption.is_empty() else 0.40)),14,22)
	var pos := where+Vector2(side+10,height*(0.34 if not caption.is_empty() else 0.50)+font_size*0.33)
	var cost: int = effect.get("cost",-1)
	var badge_width := 35.0 if cost >= 0 else 0.0
	if not caption.is_empty():
		board.draw_string(board.get_theme_default_font(),Vector2(pos.x,where.y+height*0.83),caption,HORIZONTAL_ALIGNMENT_LEFT,
			width-side-23,clampi(roundi(height*0.24),11,14),Color(color.lightened(0.34),opacity))
	board.draw_string(board.get_theme_default_font(), pos, effect.title, HORIZONTAL_ALIGNMENT_LEFT,
		width-side-29-badge_width,font_size,Color(1.0,0.965,0.88,opacity))
	if cost >= 0:
		board.draw_string(board.get_theme_default_font(), Vector2(where.x+width-49,pos.y), "%d费" % cost,
			HORIZONTAL_ALIGNMENT_CENTER,34,font_size-2,Color(color.lightened(0.28),opacity))
