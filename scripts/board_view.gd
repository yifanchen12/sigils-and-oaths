class_name BoardView
extends Control

signal cell_clicked(cell: Vector2i, button: int)
signal cell_hovered(cell: Vector2i)
signal view_changed(zoom: float)

const CardArt = preload("res://scripts/card_view.gd")
const Art = preload("res://scripts/art_library.gd")
const Landscape = preload("res://scripts/battlefield_art.gd")
const Painted = preload("res://scripts/map_artwork.gd")
const BLUE := Color("70d3ba")
const RED := Color("ef8c79")
const GOLD := Color("c6ab72")

var battle: Battle
var selected_unit: int = -1
var predicted_losses: Dictionary = {}
var deploy: Array[Vector2i] = []
var moves: Array[Vector2i] = []
var attacks: Array[Vector2i] = []
var spell_targets: Array[Vector2i] = []
var cast_reach: Array[Vector2i] = []
var hover_cell := Vector2i(-1, -1)
var keyboard_cell := Vector2i(3, 5)
var keyboard_active: bool = false
var last_cell := Vector2i(-1, -1)
var flash_cell := Vector2i(-1, -1)
var flash_alpha: float = 0.0:
	set(value):
		flash_alpha = value
		queue_redraw()
var font: Font
var grid_visible: bool = false
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var dragging: bool = false
var visual_time: float = 0.0
var redraw_clock: float = 0.0
var effects: Array[Dictionary] = []
var motion_unit: int = -1
var motion_path: Array[Vector2i] = []
var motion_tween: Tween
var flash_tween: Tween
var motion_progress: float = 1.0:
	set(value):
		motion_progress = value
		queue_redraw()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	font = get_theme_default_font()
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(func() -> void: _clamp_pan(); queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_exited.connect(func() -> void:
		hover_cell = Vector2i(-1, -1)
		cell_hovered.emit(hover_cell)
		queue_redraw())

func _process(delta: float) -> void:
	visual_time += delta
	redraw_clock += delta
	if not effects.is_empty():
		for index: int in range(effects.size() - 1, -1, -1):
			effects[index].age += delta
			if effects[index].age >= effects[index].duration: effects.remove_at(index)
		queue_redraw()
	if battle != null and (battle.weather != "clear" or battle.map_definition.theme in ["river", "harbor"]) and redraw_clock > 0.05:
		redraw_clock = 0.0
		queue_redraw()

func grid_rect() -> Rect2:
	if battle == null: return Rect2()
	var cell_size: float = floorf(minf((size.x - 60.0) / battle.width, (size.y - 38.0) / battle.height)) * zoom
	var extent := Vector2(cell_size * battle.width, cell_size * battle.height)
	return Rect2((size - extent) / 2 + Vector2(8, 7) + pan, extent)

func fit_map() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	dragging = false
	view_changed.emit(zoom)
	queue_redraw()

func zoom_at(point: Vector2, factor: float) -> void:
	if battle == null: return
	var before: Rect2 = grid_rect()
	var coordinate: Vector2 = (point - before.position) / (before.size.x / battle.width)
	zoom = clampf(zoom * factor, 1.0, 2.8)
	var after: Rect2 = grid_rect()
	pan += point - after.position - coordinate * (after.size.x / battle.width)
	_clamp_pan()
	view_changed.emit(zoom)
	queue_redraw()

func pan_by(offset: Vector2) -> void:
	pan += offset
	_clamp_pan()
	queue_redraw()

func _clamp_pan() -> void:
	if battle == null: return
	var limit: Vector2 = ((grid_rect().size - size + Vector2(60, 44)) / 2).max(Vector2.ZERO)
	pan = pan.clamp(-limit, limit)

func reveal_cell(cell: Vector2i) -> void:
	var at: Vector2 = cell_center(cell)
	var inset := Vector2(35, 35)
	var destination: Vector2 = at.clamp(inset, size - inset)
	pan_by(destination - at)

func cell_center(cell: Vector2i) -> Vector2:
	var grid: Rect2 = grid_rect()
	return grid.position + (Vector2(cell) + Vector2(0.5, 0.5)) * (grid.size.x / battle.width)

func cell_from_point(point: Vector2) -> Vector2i:
	var grid: Rect2 = grid_rect()
	if not grid.has_point(point): return Vector2i(-1, -1)
	return Vector2i((point - grid.position) / (grid.size.x / battle.width))

func flash(cell: Vector2i) -> void:
	if flash_tween != null and flash_tween.is_valid(): flash_tween.kill()
	flash_cell = cell
	flash_alpha = 0.7
	flash_tween = create_tween()
	flash_tween.tween_property(self, "flash_alpha", 0.0, 0.4)

func reset_effects() -> void:
	if motion_tween != null and motion_tween.is_valid(): motion_tween.kill()
	if flash_tween != null and flash_tween.is_valid(): flash_tween.kill()
	effects.clear()
	predicted_losses.clear()
	motion_unit = -1
	motion_progress = 1.0
	flash_alpha = 0.0
	last_cell = Vector2i(-1, -1)

func present_action(before: Array, action: Dictionary, path: Array[Vector2i]) -> void:
	var previous_ids: Dictionary = {}
	for old: Dictionary in before:
		previous_ids[old.id] = true
		var current: Dictionary = battle.get_unit(old.id)
		if current.is_empty():
			_effect("burst", old.pos, "击破", RED, 0.8)
			continue
		var hp_delta: int = int(current.hp) - int(old.hp)
		var shield_delta: int = int(current.shield) - int(old.shield)
		if int(current.get("rooted_turns", 0)) > int(old.get("rooted_turns", 0)):
			_effect("spawn", current.pos, "定身", Color("a5cfed"), 0.9)
		if action.get("spell_effect", "") == "onslaught" and old.attacked and not current.attacked:
			_effect("spawn", current.pos, "追击", GOLD, 0.8)
		if current.pos != old.pos and action.type != "move":
			_effect("spawn", current.pos, "换位" if action.get("spell_effect", "") == "exchange" else "击退", BLUE, 0.7)
		if hp_delta < 0: _effect("hit", current.pos, str(hp_delta), RED, 0.75)
		elif hp_delta > 0: _effect("heal", current.pos, "+%d" % hp_delta, BLUE, 0.8)
		if shield_delta != 0:
			_effect("shield", current.pos, ("+%d盾" if shield_delta > 0 else "%d盾") % shield_delta, GOLD, 0.9)
	for current: Dictionary in battle.units:
		if not previous_ids.has(current.id): _effect("spawn", current.pos, "增援", BLUE if current.side == 0 else RED, 0.7)
	if action.type == "move" and path.size() >= 2:
		if motion_tween != null and motion_tween.is_valid(): motion_tween.kill()
		motion_unit = int(action.unit_id)
		motion_path = path
		motion_progress = 0.0
		motion_tween = create_tween()
		motion_tween.tween_property(self, "motion_progress", 1.0, minf(0.42, 0.14 + path.size() * 0.04)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if action.type in ["attack", "hero"] and action.has("target") and battle.inside(action.target):
		var from_cell: Vector2i = action.target
		for old: Dictionary in before:
			if (action.type == "attack" and old.id == action.unit_id) or (action.type == "hero" and old.kind == "commander" and old.side == battle.active_side):
				from_cell = old.pos
				break
		effects.append({"kind": "trace", "cell": action.target, "from": from_cell, "text": "", "color": GOLD, "age": 0.0, "duration": 0.28})
	queue_redraw()

func _effect(kind: String, cell: Vector2i, value: String, color: Color, duration: float) -> void:
	effects.append({"kind": kind, "cell": cell, "text": value, "color": color, "age": 0.0, "duration": duration})

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if dragging:
			pan_by(event.relative)
			accept_event()
			return
		keyboard_active = false
		var cell: Vector2i = cell_from_point(event.position)
		if cell != hover_cell:
			hover_cell = cell
			cell_hovered.emit(cell)
			queue_redraw()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and (event.alt_pressed or dragging)):
			dragging = event.pressed
			mouse_default_cursor_shape = Control.CURSOR_DRAG if dragging else Control.CURSOR_POINTING_HAND
			accept_event()
			return
		if not event.pressed: return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position, 1.18 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.18)
			accept_event()
			return
		var cell: Vector2i = cell_from_point(event.position)
		if cell.x >= 0:
			grab_focus()
			keyboard_cell = cell
			cell_clicked.emit(cell, event.button_index)
			accept_event()
	if event is InputEventKey and event.pressed and not event.echo:
		var direction := Vector2i.ZERO
		match event.keycode:
			KEY_LEFT: direction = Vector2i.LEFT
			KEY_RIGHT: direction = Vector2i.RIGHT
			KEY_UP: direction = Vector2i.UP
			KEY_DOWN: direction = Vector2i.DOWN
			KEY_ENTER, KEY_KP_ENTER:
				cell_clicked.emit(keyboard_cell, MOUSE_BUTTON_LEFT)
				accept_event()
		if direction != Vector2i.ZERO:
			keyboard_active = true
			keyboard_cell = (keyboard_cell + direction).clamp(Vector2i.ZERO, Vector2i(battle.width - 1, battle.height - 1))
			reveal_cell(keyboard_cell)
			hover_cell = keyboard_cell
			cell_hovered.emit(hover_cell)
			queue_redraw()
			accept_event()

func _draw() -> void:
	if battle == null or font == null: return
	var grid: Rect2 = grid_rect()
	var tile: float = grid.size.x / battle.width
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("101e23")
	frame.border_color = Color("465553")
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(10)
	frame.shadow_color = Color(0, 0, 0, 0.3)
	frame.shadow_size = 12
	frame.draw(get_canvas_item(), grid.grow(10))
	for x: int in range(battle.width):
		_text(String.chr(65 + x), Vector2(grid.position.x + tile * (x + 0.5), grid.position.y - 17), 12, Color("81958e"))
	for y: int in range(battle.height):
		_text(str(battle.height - y), Vector2(grid.position.x - 25, grid.position.y + tile * (y + 0.5) + 5), 12, Color("81958e"))
	var painted: bool = Painted.draw_map(self, battle, grid)
	if not painted:
		for y: int in range(battle.height):
			for x: int in range(battle.width):
				var ground_cell := Vector2i(x, y)
				var ground_rect := Rect2(grid.position + Vector2(x, y) * tile, Vector2.ONE * tile)
				Landscape.draw_ground(self, battle, ground_cell, ground_rect, visual_time)
	else:
		Painted.draw_water_motion(self, battle, grid, visual_time)
	for y: int in range(battle.height):
		for x: int in range(battle.width):
			var cell := Vector2i(x, y)
			var rect := Rect2(grid.position + Vector2(x, y) * tile, Vector2.ONE * tile)
			_draw_terrain(cell, rect, painted)
			if cast_reach.has(cell):
				draw_rect(rect.grow(-1), Color(0.34, 0.61, 0.90, 0.12))
			if deploy.has(cell):
				draw_rect(rect.grow(-3), Color(BLUE, 0.24))
				draw_rect(rect.grow(-4), Color(BLUE, 0.95), false, 2)
				var center: Vector2 = rect.get_center()
				draw_line(center - Vector2(6, 0), center + Vector2(6, 0), BLUE, 1.6)
				draw_line(center - Vector2(0, 6), center + Vector2(0, 6), BLUE, 1.6)
			if moves.has(cell):
				draw_rect(rect.grow(-3), Color("#283f5888"))
				draw_circle(rect.get_center(), 4, Color("81b6db"))
			if attacks.has(cell) or spell_targets.has(cell):
				draw_rect(rect.grow(-3), Color(RED, 0.14))
				draw_rect(rect.grow(-4), RED, false, 1.6)
			if cell == last_cell:
				draw_line(rect.position + Vector2(6, tile - 5), rect.position + Vector2(tile - 6, tile - 5), Color(GOLD, 0.65), 2)
			if cell == flash_cell and flash_alpha > 0:
				draw_rect(rect.grow(-2), Color(GOLD, flash_alpha))
	if selected_unit != -1 and moves.has(hover_cell):
		var selected: Dictionary = battle.get_unit(selected_unit)
		if not selected.is_empty():
			var path: Array[Vector2i] = battle.movement_path(selected, hover_cell)
			var points := PackedVector2Array()
			for step: Vector2i in path: points.append(cell_center(step))
			if points.size() >= 2: draw_polyline(points, Color("abcce5"), 2.5, true)
	for unit: Dictionary in battle.units:
		var at: Vector2 = cell_center(unit.pos)
		if unit.id == motion_unit and motion_progress < 1.0 and motion_path.size() > 1:
			var progress: float = motion_progress * (motion_path.size() - 1)
			var segment: int = mini(motion_path.size() - 2, int(progress))
			at = cell_center(motion_path[segment]).lerp(cell_center(motion_path[segment + 1]), progress - segment)
		_draw_unit(unit, at, tile)
	_draw_weather(grid)
	_draw_effects(tile)
	if battle.inside(hover_cell):
		var rect := Rect2(grid.position + Vector2(hover_cell) * tile, Vector2.ONE * tile)
		draw_rect(rect.grow(-2), Color("e4dfc8"), false, 2)
	if keyboard_active and has_focus():
		var rect := Rect2(grid.position + Vector2(keyboard_cell) * tile, Vector2.ONE * tile)
		draw_rect(rect.grow(-6), GOLD, false, 2)

func _draw_terrain(cell: Vector2i, rect: Rect2, painted: bool = false) -> void:
	var ground_type: String = battle.ground(cell)
	if not painted: Landscape.draw_prop(self, ground_type, rect, battle.map_definition.theme, battle.map_definition.id)
	if grid_visible or not painted:
		draw_rect(rect, Color(0.08, 0.17, 0.17, 0.19 if grid_visible else 0.08), false, 1)
	var markers: Dictionary = {"forest": "森", "hill": "丘", "road": "路", "bridge": "桥", "mountain": "山", "ruins": "+", "fort": "堡"}
	if markers.has(ground_type) and (grid_visible or cell == hover_cell or (not painted and ground_type in ["hill", "ruins", "fort"])):
		var badge: Vector2 = rect.position + Vector2(10, 10)
		draw_circle(badge, 8, Color(0.06, 0.15, 0.17, 0.8))
		_text(markers[ground_type], badge + Vector2(0, 4), 11, Color("eee6bc"))

func _draw_weather(grid: Rect2) -> void:
	match battle.weather:
		"rain":
			for drop: int in range(48):
				var x: float = fposmod(drop * 73.7 - visual_time * 28, grid.size.x)
				var y: float = fposmod(drop * 47.1 + visual_time * 185, grid.size.y)
				var start: Vector2 = grid.position + Vector2(x, y)
				draw_line(start, start + Vector2(-4, 12), Color(0.6, 0.8, 0.92, 0.28), 1, true)
		"snow":
			for flake: int in range(42):
				var x: float = fposmod(flake * 91.7 + sin(visual_time + flake) * 10, grid.size.x)
				var y: float = fposmod(flake * 57.9 + visual_time * 22, grid.size.y)
				draw_circle(grid.position + Vector2(x, y), 1 + flake % 2, Color(0.86, 0.94, 0.98, 0.62))
		"fog":
			for band: int in range(6):
				var y: float = grid.position.y + grid.size.y * (band + 0.5) / 6
				draw_rect(Rect2(Vector2(grid.position.x, y), Vector2(grid.size.x, 19)), Color(0.73, 0.82, 0.80, 0.055 + sin(visual_time * 0.4 + band) * 0.012))
		"sun":
			for ray: int in range(4):
				var start: Vector2 = grid.position + Vector2(grid.size.x * (0.45 + ray * 0.13), 0)
				draw_colored_polygon(PackedVector2Array([start, start + Vector2(20, 0), start + Vector2(-120, grid.size.y), start + Vector2(-155, grid.size.y)]), Color(1, 0.83, 0.45, 0.035))

func _draw_effects(tile: float) -> void:
	for effect: Dictionary in effects:
		var progress: float = float(effect.age) / float(effect.duration)
		var at: Vector2 = cell_center(effect.cell)
		var color: Color = effect.color
		color.a = 1.0 - progress
		if effect.kind == "trace":
			var start: Vector2 = cell_center(effect.from)
			var end: Vector2 = start.lerp(at, minf(1, progress * 3))
			draw_line(start, end, Color(color, color.a * 0.75), 2.5, true)
			draw_circle(end, 3 + progress * 3, color)
			continue
		if effect.kind in ["hit", "burst", "spawn", "heal"]:
			draw_arc(at, tile * (0.14 + progress * 0.37), 0, TAU, 32, Color(color, color.a * 0.7), 2, true)
			for spark: int in range(6):
				var direction: Vector2 = Vector2.from_angle(spark * TAU / 6 + 0.4)
				var point: Vector2 = at + direction * tile * progress * 0.55
				draw_circle(point, 1.3 + (1 - progress), Color(color, color.a * 0.8))
		var offset: float = 12.0 if effect.kind == "shield" else 0.0
		var text_at: Vector2 = at - Vector2(0, 23 + offset + progress * 32)
		_text(str(effect.text), text_at + Vector2(1, 1), 17, Color(0.01, 0.03, 0.04, color.a))
		_text(str(effect.text), text_at, 17, color)

func _draw_unit(unit: Dictionary, at: Vector2, tile: float) -> void:
	var color: Color = BLUE if unit.side == 0 else RED
	var radius: float = minf(tile * 0.31, 25)
	var exhausted: bool = unit.summoning or (unit.attacked and unit.side == battle.active_side)
	var selected: bool = unit.id == selected_unit
	var center: Vector2 = at - Vector2(0, 3)
	var marker := Rect2(at - Vector2(tile * 0.41, tile * 0.40), Vector2(tile * 0.82, tile * 0.78))
	draw_rect(marker, Color(color, 0.09))
	for side: int in [-1, 1]:
		var corner: Vector2 = at + Vector2(side * tile * 0.39, tile * 0.36)
		draw_line(corner, corner + Vector2(-side * 9, 0), color, 2, true)
		draw_line(corner, corner - Vector2(0, 8), color, 2, true)
	var sprite_id: String = battle.hero(unit.side).portrait if unit.kind == "commander" else str(unit.kind)
	var sprite: Texture2D = Art.get_texture("sprite_" + sprite_id)
	if sprite != null:
		var height_offset := Vector2(0, -tile * 0.1) if battle.ground(unit.pos) == "hill" else Vector2.ZERO
		var feet: Vector2 = at + height_offset + Vector2(0, tile * 0.24)
		draw_set_transform(feet, 0, Vector2(1, 0.4))
		draw_circle(Vector2(0, 3), tile * 0.31, Color(0.02, 0.06, 0.06, 0.3))
		draw_circle(Vector2.ZERO, tile * 0.29, Color(color, 0.55 if not selected else 0.85))
		draw_arc(Vector2.ZERO, tile * 0.3, 0, TAU, 32, GOLD if unit.kind == "commander" else color, 2.3 if selected else 1.4, true)
		draw_set_transform(Vector2.ZERO)
		var extent: Vector2 = Vector2.ONE * tile * 0.97
		draw_texture_rect(sprite, Rect2(at + height_offset - Vector2(extent.x / 2, extent.y * 0.60), extent), false, Color(0.72, 0.76, 0.78, 1) if exhausted else Color.WHITE)
		draw_circle(center + Vector2(-radius + 2, -radius + 2), 7.5, Color("0b1720"))
		_text(str(unit.short), center + Vector2(-radius + 2, -radius + 6), 10, GOLD)
	else:
		draw_circle(center + Vector2(0, 4), radius + 3, Color(0, 0, 0, 0.35))
		if selected: draw_circle(center, radius + 7, Color(color, 0.16))
		draw_circle(center, radius + 2, Color("0b1c25"))
		draw_circle(center, radius - 1, Color("173b40") if unit.side == 0 else Color("482b2c"))
		draw_arc(center, radius + 1, 0, TAU, 48, GOLD if unit.kind == "commander" else Color(color, 0.9), 2.3 if selected else 1.4, true)
		var asset_id: String = battle.hero(unit.side).portrait if unit.kind == "commander" else str(unit.kind)
		var portrait: Texture2D = Art.get_texture(asset_id)
		if portrait != null:
			Art.draw_round_portrait(self, portrait, center, radius - 2, Color(0.66, 0.69, 0.7, 1) if exhausted else Color.WHITE)
			draw_circle(center + Vector2(-radius + 2, -radius + 2), 7.5, Color("0b1720"))
			_text(str(unit.short), center + Vector2(-radius + 2, -radius + 6), 10, GOLD)
		else:
			CardArt.draw_symbol(self, unit.kind, center, radius * 0.65, Color(color, 0.55) if exhausted else color)
	if unit.shield > 0:
		draw_arc(center, radius + 4, PI * 1.08, PI * 1.92, 24, GOLD, 2.3, true)
		_text(str(unit.shield), center + Vector2(0, -radius - 5), 11, GOLD)
	if int(unit.get("rooted_turns", 0)) > 0:
		draw_circle(center - Vector2(0, radius), 8, Color("173140"))
		_text("锁", center - Vector2(0, radius - 4), 10, Color("b7d8ee"))
	var bar_width: float = tile * 0.67
	var bar := Rect2(at + Vector2(-bar_width / 2, tile * 0.31), Vector2(bar_width, 4))
	draw_rect(bar, Color("0b1720"))
	draw_rect(Rect2(bar.position, Vector2(bar_width * clampf(float(unit.hp) / float(unit.max_hp), 0, 1), 4)), color)
	var loss: int = int(predicted_losses.get(unit.id, 0))
	if loss > 0:
		var after: float = maxf(0, float(unit.hp - loss) / unit.max_hp)
		var width: float = bar_width * mini(loss, int(unit.hp)) / unit.max_hp
		draw_rect(Rect2(bar.position + Vector2(bar_width * after, 0), Vector2(width, 4)), Color("ffe0a0"))
	draw_circle(center + Vector2(-radius + 1, radius - 3), 7.5, Color("0b1720"))
	draw_circle(center + Vector2(radius - 1, radius - 3), 7.5, Color("0b1720"))
	_text(str(unit.atk), center + Vector2(-radius + 1, radius + 1), 12, Color("ebd5a6"))
	_text(str(unit.hp), center + Vector2(radius - 1, radius + 1), 12, Color("f2eee2"))
	if unit.summoning:
		_text("Z", center + Vector2(radius + 3, -radius + 7), 12, Color("97a9a9"))
	elif unit.side == battle.active_side and not unit.attacked:
		draw_circle(center + Vector2(radius + 1, -radius + 4), 3.5, color)

func _text(value: String, at: Vector2, font_size: int, color: Color) -> void:
	var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at - Vector2(width / 2, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
