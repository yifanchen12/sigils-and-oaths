extends Control
## Player-readable world and character archive. Text stays separate from presentation.

signal closed

const Art = preload("res://scripts/art_library.gd")
const SOURCE: String = "res://data/narrative/codex.json"
const GOLD := Color("d0b579")
const INK := Color("eee8db")
var entries: Array = []
var selected_id: String = ""
var entry_buttons: Dictionary = {}
var heading: Label
var subtitle: Label
var summary: Label
var paragraphs: VBoxContainer
var scroll: ScrollContainer
var portrait: Control
var close_button: Button
var origin_focus: Control

class Illustration extends Control:
	var texture: Texture2D
	var face: Texture2D
	var is_person: bool = false
	func _draw() -> void:
		if size.x < 32 or size.y < 128: return
		draw_rect(Rect2(Vector2.ZERO, size), Color("152e3b"))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.82, 0.71, 0.47, 0.6), false, 1)
		if texture == null: return
		if is_person:
			var portrait_height: float = minf(size.x, size.y * 0.42)
			if face != null: Art.draw_cover(self, face, Rect2(Vector2(8, 8), Vector2(size.x - 16, portrait_height - 16)))
			draw_line(Vector2(8, portrait_height + 8), Vector2(size.x - 8, portrait_height + 8), Color(0.82, 0.71, 0.47, 0.5), 1)
			var remaining := Vector2(size.x, size.y - portrait_height - 24)
			var center := Vector2(size.x * 0.5, portrait_height + 24 + remaining.y * 0.5)
			draw_arc(center, minf(size.x * 0.43, remaining.y * 0.43), 0, TAU, 72, Color(0.82, 0.71, 0.47, 0.22), 1, true)
			var ratio: float = minf((remaining.x - 12) / texture.get_width(), (remaining.y - 24) / texture.get_height())
			var extent: Vector2 = texture.get_size() * ratio
			draw_texture_rect(texture, Rect2(center - extent / 2, extent), false)
		else:
			Art.draw_cover(self, texture, Rect2(Vector2(8, 8), size - Vector2(16, 16)))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if parsed is Dictionary and parsed.get("version", 0) == 1 and parsed.get("entries") is Array:
		entries = parsed.entries
	_build()
	resized.connect(queue_redraw)
	if not entries.is_empty(): select_entry(str(entries[0].id))
	else: heading.text = "档案暂时无法读取"

func _draw() -> void:
	var background: Texture2D = Art.get_texture("menu")
	if background != null: Art.draw_cover(self, background, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.06, 0.10, 0.94))
	draw_line(Vector2(36, 112), Vector2(size.x - 36, 112), Color(GOLD, 0.6), 1)

func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 36)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 28)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	layout.add_child(header)
	var title := _label("共誓档案", 32, INK)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var strapline := _label("人物 · 土地 · 未完成的承诺", 16, GOLD)
	strapline.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.add_child(strapline)
	close_button = Button.new()
	close_button.text = "返回战前页  Esc"
	close_button.custom_minimum_size = Vector2(190, 48)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	var directory := ScrollContainer.new()
	directory.custom_minimum_size.x = 246
	directory.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(directory)
	var index := VBoxContainer.new()
	index.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	index.add_theme_constant_override("separation", 8)
	directory.add_child(index)
	var category: String = ""
	for entry: Dictionary in entries:
		if str(entry.category) != category:
			category = entry.category
			var label := _label(category, 16, GOLD)
			label.custom_minimum_size.y = 34
			index.add_child(label)
		var button := Button.new()
		button.text = entry.title
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(225, 46)
		button.toggle_mode = true
		button.pressed.connect(select_entry.bind(str(entry.id)))
		index.add_child(button)
		entry_buttons[entry.id] = button
	portrait = Illustration.new()
	portrait.custom_minimum_size.x = 310
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(portrait)
	var reading := VBoxContainer.new()
	reading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading.add_theme_constant_override("separation", 14)
	columns.add_child(reading)
	heading = _label("", 30, INK)
	subtitle = _label("", 16, GOLD)
	summary = _label("", 20, Color("a9d6cb"))
	reading.add_child(heading)
	reading.add_child(subtitle)
	reading.add_child(summary)
	reading.add_child(HSeparator.new())
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	reading.add_child(scroll)
	paragraphs = VBoxContainer.new()
	paragraphs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paragraphs.add_theme_constant_override("separation", 20)
	scroll.add_child(paragraphs)
	layout.add_child(_label("共誓历三一七年    /    以卡为令，落子成军。", 13, Color("8da7b2")))

func _label(value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func open(entry_id: String = "") -> void:
	origin_focus = get_viewport().gui_get_focus_owner()
	if not entry_id.is_empty(): select_entry(entry_id)
	show()
	move_to_front()
	close_button.grab_focus()

func select_entry(entry_id: String) -> void:
	for entry: Dictionary in entries:
		if entry.id != entry_id: continue
		selected_id = entry_id
		heading.text = entry.title
		subtitle.text = entry.subtitle
		summary.text = entry.summary
		portrait.is_person = entry.category == "人物"
		portrait.face = Art.get_texture(str(entry.portrait)) if portrait.is_person else null
		portrait.texture = Art.get_texture(("sprite_" if portrait.is_person else "") + str(entry.portrait))
		portrait.queue_redraw()
		for child: Node in paragraphs.get_children():
			paragraphs.remove_child(child)
			child.queue_free()
		for paragraph: Dictionary in entry.body:
			var label := _label(paragraph.text, 20, INK)
			label.add_theme_constant_override("line_spacing", 7)
			paragraphs.add_child(label)
		scroll.scroll_vertical = 0
		for id: String in entry_buttons: entry_buttons[id].set_pressed_no_signal(id == entry_id)
		return

func close() -> void:
	hide()
	if is_instance_valid(origin_focus) and origin_focus.is_visible_in_tree(): origin_focus.grab_focus()
	closed.emit()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
