extends Control
## Presentation only: every button carries the session and revision it displayed.

signal advance_requested(expected: Dictionary)
signal choice_requested(option_id: String, expected: Dictionary)
signal battle_requested(expected: Dictionary)
signal menu_requested
signal save_requested

const Art = preload("res://scripts/art_library.gd")
const GOLD := Color("d0b579")
const INK := Color("eee8db")
var heading: Label
var speaker: Label
var text_body: RichTextLabel
var actions: VBoxContainer
var status: Label
var illustration: TextureRect
var backlog_button: Button
var background_id: String = "menu"
var page: Dictionary = {}
var setup: Dictionary = {}
var view_token: Dictionary = {}
var history: Array[Dictionary] = []
var showing_history: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()
	_build()
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x < 32 or size.y < 32: return
	var background: Texture2D = Art.get_texture(background_id)
	if background != null: Art.draw_cover(self, background, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.06, 0.10, 0.83))
	draw_line(Vector2(36, 112), Vector2(size.x - 36, 112), Color(GOLD, 0.65), 1)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(callback)
	return button

func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 36)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 26)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	layout.add_child(header)
	heading = _label("河门来信", 28, INK)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	backlog_button = _button("已读回看", _toggle_history)
	header.add_child(backlog_button)
	header.add_child(_button("返回战前页  Esc", func() -> void: menu_requested.emit()))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 32)
	layout.add_child(columns)
	illustration = TextureRect.new()
	illustration.custom_minimum_size.x = 260
	illustration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	illustration.size_flags_stretch_ratio = 0.7
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(illustration)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.8
	columns.add_child(panel)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 20)
	panel.add_child(copy)
	speaker = _label("", 25, GOLD)
	copy.add_child(speaker)
	copy.add_child(HSeparator.new())
	text_body = RichTextLabel.new()
	text_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_body.bbcode_enabled = false
	text_body.selection_enabled = true
	text_body.add_theme_font_size_override("normal_font_size", 22)
	text_body.add_theme_constant_override("line_separation", 14)
	text_body.add_theme_color_override("default_color", INK)
	copy.add_child(text_body)
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	copy.add_child(actions)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	layout.add_child(footer)
	status = _label("", 14, Color("b7c7ce"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status)
	footer.add_child(_button("保存进度", func() -> void: save_requested.emit()))

func open(current_page: Dictionary, expected: Dictionary, scenario: Dictionary, backlog: Array[Dictionary], save_notice: String, save_failed: bool) -> void:
	page = current_page.duplicate(true)
	view_token = expected.duplicate(true)
	setup = scenario.duplicate(true)
	history = backlog.duplicate(true)
	showing_history = false
	background_id = str(page.get("background", "menu"))
	if background_id.is_empty(): background_id = "menu"
	heading.text = page.get("chapter", "战役")
	set_status(save_notice, save_failed)
	show()
	_render_page()
	queue_redraw()

func set_status(message: String, failed: bool = false) -> void:
	status.text = message
	status.add_theme_color_override("font_color", Color("f08b76") if failed else Color("b7c7ce"))

func _clear_actions() -> void:
	for child: Node in actions.get_children():
		actions.remove_child(child)
		child.queue_free()

func _render_page() -> void:
	_clear_actions()
	backlog_button.text = "返回当前对白" if showing_history else "已读回看"
	backlog_button.disabled = history.is_empty()
	if showing_history:
		speaker.text = "已经走过的路"
		var paragraphs: PackedStringArray = []
		for entry: Dictionary in history: paragraphs.append(entry.text)
		text_body.text = "\n\n".join(paragraphs)
		text_body.scroll_to_line(0)
		backlog_button.grab_focus()
		return
	var speaker_id: String = page.get("speaker_id", "")
	illustration.texture = Art.get_texture("sprite_" + speaker_id) if Art.HERO_ORDER.has(speaker_id) or Art.UNIT_ORDER.has(speaker_id) else Art.get_texture("terrain_fort")
	speaker.text = page.get("speaker", "军议")
	text_body.text = page.get("text", "")
	text_body.scroll_to_line(0)
	match page.get("type", ""):
		"dialogue":
			actions.add_child(_button("继续  ·  Space / Enter", _advance.bind(view_token.duplicate())))
		"choice":
			speaker.text = "由你下令"
			for option: Dictionary in page.options:
				actions.add_child(_button(option.text, _choose.bind(str(option.id), view_token.duplicate())))
		"battle":
			speaker.text = setup.get("title", "战前军议")
			var retry: String = ""
			if page.last_outcome != "": retry = "\n\n上一战" + ("失利" if page.last_outcome == "defeat" else "平局") + "，剧情停在此处。重新出征将重建同一战场。"
			text_body.text = "%s\n\n作战目标\n%s\n\n敌方指挥：%s\n每回合 90 秒。战斗中退出，下次从战前重新开始。%s" % [setup.get("brief", ""), setup.get("objective", ""), setup.get("enemy_name", ""), retry]
			actions.add_child(_button("重新出征" if page.attempts > 0 else "率军出征", _battle.bind(view_token.duplicate())))
		"end":
			speaker.text = "第一章 · 章末"
			actions.add_child(_button("返回战前页", func() -> void: menu_requested.emit()))
	if actions.get_child_count() > 0: actions.get_child(0).grab_focus()

func _advance(expected: Dictionary) -> void: advance_requested.emit(expected)
func _choose(option: String, expected: Dictionary) -> void: choice_requested.emit(option, expected)
func _battle(expected: Dictionary) -> void: battle_requested.emit(expected)

func _toggle_history() -> void:
	showing_history = not showing_history
	_render_page()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		if showing_history: _toggle_history()
		else: menu_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE and not showing_history and page.get("type") == "dialogue":
		advance_requested.emit(view_token.duplicate())
		get_viewport().set_input_as_handled()
