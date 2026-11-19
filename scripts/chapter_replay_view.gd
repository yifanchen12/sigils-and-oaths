extends Control
## Chapter selection and the status of the independently saved branch.

signal start_requested(chapter_id: String)
signal continue_requested
signal close_requested

const Art = preload("res://scripts/art_library.gd")
const GOLD := Color("d0b579")
const INK := Color("e6e8dd")
const MUTED := Color("a3b3bd")

var shell: PanelContainer
var chapters: ItemList
var unlocked_count: Label
var selected_title: Label
var detail: Label
var branch_status: Label
var status: Label
var start_button: Button
var continue_button: Button
var close_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_build()
	hide()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _panel_fill(fill: Color, frame: Color, margin: float) -> StyleBoxFlat:
	var shape := StyleBoxFlat.new()
	shape.bg_color = fill
	shape.border_color = frame
	shape.set_border_width_all(1)
	shape.set_corner_radius_all(6)
	for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		shape.set_content_margin(side, margin)
	return shape

func _build() -> void:
	var curtain := ColorRect.new()
	curtain.color = Color(0.02, 0.04, 0.08, 0.78)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(curtain)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell = PanelContainer.new()
	add_child(shell)
	shell.anchor_left = 0.10
	shell.anchor_right = 0.90
	shell.anchor_top = 0.09
	shell.anchor_bottom = 0.91
	shell.add_theme_stylebox_override("panel", _panel_fill(Color("101d2d"), Color("9e885d"), 24))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	shell.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(header)
	header.add_child(_label("章节重走", 34, INK))
	unlocked_count = _label("", 19, GOLD)
	unlocked_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unlocked_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(unlocked_count)
	close_button = Button.new()
	close_button.text = "返回  Esc"
	close_button.custom_minimum_size = Vector2(136, 44)
	close_button.pressed.connect(close_requested.emit)
	header.add_child(close_button)
	layout.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	chapters = ItemList.new()
	chapters.custom_minimum_size = Vector2(390, 225)
	chapters.add_theme_font_size_override("font_size", 22)
	chapters.add_theme_constant_override("v_separation", 13)
	chapters.add_theme_stylebox_override("panel", _panel_fill(Color("0b1624"), Color("506278"), 12))
	chapters.add_theme_stylebox_override("selected", _panel_fill(Color("284058"), Color("8a805c"), 4))
	chapters.add_theme_stylebox_override("selected_focus", _panel_fill(Color("304a63"), GOLD, 4))
	chapters.item_selected.connect(_select)
	body.add_child(chapters)
	var preview := VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_theme_constant_override("separation", 12)
	body.add_child(preview)
	var art := TextureRect.new()
	art.texture = Art.get_texture("chapter_replay_archive")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.custom_minimum_size.y = 180
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(art)
	selected_title = _label("", 25, GOLD)
	selected_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(selected_title)
	detail = _label("", 18, INK)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(detail)
	branch_status = _label("", 18, MUTED)
	branch_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(branch_status)

	status = _label("", 17, MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 26
	layout.add_child(status)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(footer)
	continue_button = Button.new()
	continue_button.text = "继续分支"
	continue_button.custom_minimum_size = Vector2(152, 49)
	continue_button.pressed.connect(continue_requested.emit)
	footer.add_child(continue_button)
	start_button = Button.new()
	start_button.text = "从本章重走"
	start_button.custom_minimum_size = Vector2(180, 49)
	start_button.pressed.connect(func() -> void:
		var chapter_id: String = selected_chapter()
		if not chapter_id.is_empty(): start_requested.emit(chapter_id))
	footer.add_child(start_button)

func open(entries: Array[Dictionary], branch_label: String, can_continue: bool, source_notice: String) -> void:
	chapters.clear()
	var latest: int = -1
	var unlocked: int = 0
	for entry: Dictionary in entries:
		var index: int = chapters.add_item(entry.title if entry.unlocked else "第 %02d 章 · 尚未完成" % entry.number)
		chapters.set_item_metadata(index, entry.id)
		chapters.set_item_disabled(index, not entry.unlocked)
		if entry.unlocked:
			unlocked += 1
			latest = index
	unlocked_count.text = "主线已完成 %d / %d 章" % [unlocked, entries.size()]
	branch_status.text = branch_label
	continue_button.disabled = not can_continue
	set_status(source_notice)
	show()
	if latest >= 0:
		chapters.select(latest)
		_select(latest)
		chapters.ensure_current_is_visible()
		chapters.grab_focus()
	else:
		start_button.disabled = true
		selected_title.text = "从已完成的章节重走"
		detail.text = "完成主线第一章后，这里会开放章节选择。"
		(continue_button if can_continue else close_button).grab_focus()

func _select(index: int) -> void:
	selected_title.text = chapters.get_item_text(index)
	detail.text = "从本章第一句开始，承接主线此前的选择。随后获得的进度会保存到分支存档。"
	start_button.disabled = chapters.is_item_disabled(index)

func selected_chapter() -> String:
	var selected: PackedInt32Array = chapters.get_selected_items()
	if selected.is_empty() or chapters.is_item_disabled(selected[0]): return ""
	return str(chapters.get_item_metadata(selected[0]))

func set_status(text: String, failed: bool = false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", Color("f08b76") if failed else MUTED)

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_requested.emit()
