extends Control
## Read-only card travel. Enemy events deliberately contain no card identity.

const Art = preload("res://scripts/art_library.gd")
const CardStyle = preload("res://scripts/card_view.gd")
const Catalog = preload("res://data/cards.tres")
const GOLD := Color("d0b579")
const TEAL := Color("70d3ba")
const PAPER := Color("f3eddc")

var events: Array[Dictionary] = []
var reduced_motion: bool = false
var anchors: Dictionary = {}
var hand_slots: Dictionary = {}
var viewport_rect := Rect2()

static func capture(players: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for player: Dictionary in players:
		var deck: Dictionary = {}
		for instance: Dictionary in player.deck: deck[int(instance.uid)] = true
		result.append(deck)
	return result

static func transitions(before: Array[Dictionary], players: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for side: int in range(mini(before.size(), players.size())):
		for zone: String in ["hand", "discard"]:
			for instance: Dictionary in players[side][zone]:
				if not before[side].has(int(instance.uid)): continue
				var event: Dictionary = {"side": side, "burned": zone == "discard", "opening": false}
				if side == 0:
					event["uid"] = int(instance.uid)
					event["card_id"] = str(instance.card_id)
				result.append(event)
	return result

static func opening_hand(players: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for side: int in range(players.size()):
		for instance: Dictionary in players[side].hand:
			var event: Dictionary = {"side": side, "burned": false, "opening": true}
			if side == 0:
				event["uid"] = int(instance.uid)
				event["card_id"] = str(instance.card_id)
			result.append(event)
	return result

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 80
	resized.connect(queue_redraw)

func enqueue(batch: Array[Dictionary]) -> void:
	var delays: Array[float] = [0.0, 0.0]
	for current: Dictionary in events:
		delays[int(current.side)] = maxf(delays[int(current.side)], -float(current.age) + 0.16)
	for source: Dictionary in batch:
		# Copy only public fields: even a malformed caller cannot expose an enemy face.
		var side: int = int(source.side)
		var event: Dictionary = {"side": side, "burned": bool(source.get("burned", false)), "opening": bool(source.get("opening", false))}
		if side == 0:
			event["uid"] = int(source.uid)
			event["card_id"] = str(source.card_id)
		event["age"] = -delays[side]
		event["duration"] = 0.22 if reduced_motion else (1.12 if side == 0 else 0.50)
		delays[side] += 0.08 if reduced_motion else (0.18 if side == 0 else 0.10)
		events.append(event)
	queue_redraw()

func set_anchors(rects: Dictionary, slots: Dictionary, visible_rect: Rect2) -> void:
	anchors = rects
	hand_slots = slots
	viewport_rect = visible_rect
	queue_redraw()

func set_reduced_motion(value: bool) -> void:
	if reduced_motion == value: return
	reduced_motion = value
	reset()

func reset() -> void:
	events.clear()
	queue_redraw()

func dismiss_uid(uid: int) -> void:
	events = events.filter(func(event: Dictionary) -> bool: return int(event.get("uid", -1)) != uid)
	queue_redraw()

func pending(uid: int) -> bool:
	return events.any(func(event: Dictionary) -> bool: return not event.burned and int(event.get("uid", -1)) == uid)

func is_presenting() -> bool:
	return not events.is_empty()

func _process(delta: float) -> void:
	if events.is_empty(): return
	for event: Dictionary in events: event.age += delta
	events = events.filter(func(event: Dictionary) -> bool: return float(event.age) < float(event.duration))
	queue_redraw()

func geometry(event: Dictionary) -> Dictionary:
	var own: bool = int(event.side) == 0
	var source: Rect2 = anchors.get("own_deck" if own else "enemy_deck", Rect2())
	var destination: String = "own_discard" if own else ("enemy_discard" if event.burned else "enemy_hand")
	var target: Rect2 = anchors.get(destination, source)
	if own and not event.burned: target = hand_slots.get(int(event.uid), anchors.get("own_hand", source))
	var time: float = clampf(float(event.age) / float(event.duration), 0.0, 1.0)
	var small: Vector2 = Vector2(34, 48) if not own else Vector2(62, 88)
	var large: Vector2 = Vector2(176, 244) * clampf(viewport_rect.size.y / 900.0, 0.76, 1.1)
	var start: Vector2 = source.get_center()
	var finish: Vector2 = target.get_center()
	var center: Vector2 = finish
	var dimensions: Vector2 = target.size if own and not event.burned else small
	var face: bool = own
	var flip: float = 1.0
	var angle: float = 0.0
	if reduced_motion:
		dimensions = Vector2(minf(target.size.x, 176), minf(target.size.y, 140)) if own and not event.burned else small
	elif not own:
		center = start.lerp(finish, smoothstep(0.0, 1.0, time)) + Vector2(0, -sin(time * PI) * 26)
		dimensions = small
		face = false
		angle = sin(time * PI) * -0.08
	else:
		var peek: Vector2 = Vector2(clampf(finish.x, viewport_rect.position.x + large.x * 0.6, viewport_rect.end.x - large.x * 0.6), maxf(viewport_rect.position.y + large.y * 0.6, finish.y - large.y * 0.78))
		if time < 0.23:
			var lift: float = smoothstep(0.0, 0.23, time)
			center = start.lerp(peek, lift) + Vector2(0, -sin(lift * PI) * 34)
			dimensions = small.lerp(large, lift)
			face = false
			angle = (1.0 - lift) * 0.13
		elif time < 0.38:
			center = peek
			dimensions = large
			var turn: float = inverse_lerp(0.23, 0.38, time)
			flip = maxf(0.025, absf(cos(turn * PI)))
			face = turn >= 0.5
		elif time < 0.64:
			center = peek
			dimensions = large
		else:
			var settle: float = smoothstep(0.64, 1.0, time)
			center = peek.lerp(finish, settle)
			dimensions = large.lerp(dimensions, settle)
	center.x = clampf(center.x, viewport_rect.position.x + dimensions.x * 0.5 + 2, viewport_rect.end.x - dimensions.x * 0.5 - 2)
	center.y = clampf(center.y, viewport_rect.position.y + dimensions.y * 0.5 + 2, viewport_rect.end.y - dimensions.y * 0.5 - 2)
	return {"center": center - global_position, "size": dimensions, "face": face, "flip": flip, "angle": angle, "time": time}

func _draw() -> void:
	if anchors.is_empty(): return
	for event: Dictionary in events:
		if float(event.age) < 0: continue
		var frame: Dictionary = geometry(event)
		var fade: float = 1.0 if frame.time < 0.9 else (1.0 - frame.time) / 0.1
		var accent: Color = Color("ed9a83") if event.burned else TEAL
		if reduced_motion:
			var ring := Rect2(frame.center - frame.size * 0.5 - Vector2(5, 5), frame.size + Vector2(10, 10))
			draw_rect(ring, Color(accent, 0.65 * fade), false, 3)
			if not event.burned: continue
		elif int(event.side) == 0:
			for step: int in range(3):
				var glow := Rect2(frame.center - frame.size * 0.5 - Vector2.ONE * (4 + step * 4), frame.size + Vector2.ONE * (8 + step * 8))
				draw_rect(glow, Color(GOLD, (0.13 - step * 0.035) * fade), false, 2)
		draw_set_transform(frame.center, frame.angle, Vector2(frame.flip, 1.0))
		_draw_card(Rect2(-frame.size * 0.5, frame.size), event, frame.face)
		draw_set_transform(Vector2.ZERO)
		if int(event.side) == 0 and frame.time >= 0.38 and frame.time < 0.77:
			var caption: String = "手牌已满 · 弃置" if event.burned else ("起始手牌" if event.opening else "抽取卡牌")
			var at: Vector2 = frame.center + Vector2(0, -frame.size.y * 0.5 - 14)
			_text(caption, at, 14, accent)

func _draw_card(rect: Rect2, event: Dictionary, face: bool) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = PAPER if face else Color("142c45")
	panel.border_color = Color("e1bd71")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(5)
	panel.shadow_color = Color(0.02, 0.03, 0.06, 0.65)
	panel.shadow_size = 9
	panel.draw(get_canvas_item(), rect)
	var inset := rect.grow(-6)
	if not face:
		draw_rect(inset, Color("7d876d"), false, 1)
		var center: Vector2 = rect.get_center()
		var radius: float = minf(rect.size.x, rect.size.y) * 0.27
		draw_circle(center, radius, Color("263e56"))
		draw_arc(center, radius, 0, TAU, 40, GOLD, 1.5, true)
		var points := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius * 0.56, 0), center + Vector2(0, radius), center + Vector2(-radius * 0.56, 0)])
		draw_colored_polygon(points, Color("d0b579"))
		draw_line(center + Vector2(0, -radius * 1.65), center + Vector2(0, radius * 1.65), GOLD, 1)
		return
	var card: Dictionary = Catalog.find(str(event.card_id))
	var artwork: Texture2D = Art.get_texture(str(event.card_id))
	var footer: float = minf(54, rect.size.y * 0.27)
	var picture := Rect2(inset.position, Vector2(inset.size.x, maxf(1, inset.size.y - footer)))
	if artwork != null: Art.draw_cover(self, artwork, picture, CardStyle.art_focus(card))
	draw_line(Vector2(inset.position.x, picture.end.y + 3), Vector2(inset.end.x, picture.end.y + 3), GOLD, 1)
	var title_size: int = 16
	var font: Font = get_theme_default_font()
	while title_size > 9 and font.get_string_size(str(card.name), HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > inset.size.x - 6: title_size -= 1
	_text(str(card.name), Vector2(rect.get_center().x, picture.end.y + footer * 0.48), title_size, Color("20374a"))
	if footer > 35: _text(str(card.tag), Vector2(rect.get_center().x, picture.end.y + footer * 0.84), 11, Color("69736e"))
	var gem: Vector2 = rect.position + Vector2(18, 19)
	draw_circle(gem, 15, Color("182f47"))
	draw_arc(gem, 15, 0, TAU, 24, GOLD, 1, true)
	_text(str(card.cost), gem + Vector2(0, 6), 18, PAPER)

func _text(value: String, at: Vector2, font_size: int, color: Color) -> void:
	var font: Font = get_theme_default_font()
	var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
