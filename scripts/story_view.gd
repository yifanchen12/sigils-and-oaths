extends Control
## Presentation only: every button carries the session and revision it displayed.

signal advance_requested(expected: Dictionary)
signal choice_requested(option_id: String, expected: Dictionary)
signal battle_requested(expected: Dictionary)
signal requisition_requested(card_id: String, expected: Dictionary)
signal armory_requested(expected: Dictionary)
signal retreat_requested(expected: Dictionary)
signal next_chapter_requested(expected: Dictionary)
signal replay_requested
signal menu_requested
signal save_requested
signal settings_requested

const Art = preload("res://scripts/art_library.gd")
const Cards = preload("res://data/cards.tres")
const GOLD := Color("d0b579")
const INK := Color("eee8db")
var heading: Label
var speaker: Label
var text_body: RichTextLabel
var actions: VBoxContainer
var status: Label
var illustration: TextureRect
var stage: Control
var dialogue_panel: PanelContainer
var backlog_button: Button
var settings_button: Button
var requisition_panel: PanelContainer
var requisition_choice: OptionButton
var requisition_art: TextureRect
var requisition_text: RichTextLabel
var armory_button: Button
var background_id: String = "menu"
var page: Dictionary = {}
var setup: Dictionary = {}
var view_token: Dictionary = {}
var history: Array[Dictionary] = []
var showing_history: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hide()
	_build()
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x < 32 or size.y < 32: return
	var background: Texture2D = Art.get_texture(background_id)
	if background != null: Art.draw_cover(self, background, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.06, 0.10, 0.18))
	draw_rect(Rect2(0, 0, size.x, 112), Color(0.025, 0.06, 0.10, 0.76))
	draw_rect(Rect2(0, size.y - 92, size.x, 92), Color(0.025, 0.06, 0.10, 0.76))
	draw_line(Vector2(36, 112), Vector2(size.x - 36, 112), Color(GOLD, 0.65), 1)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable, wrap: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	# Toolbar buttons must keep their text width inside an HBox. Wrapping there
	# lets the expanding title/status squeeze them into unreadable vertical bars.
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	button.add_theme_font_size_override("font_size", 18)
	if not wrap: button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(callback)
	return button

func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 36)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	layout.add_child(header)
	heading = _label("河门来信", 28, INK)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	backlog_button = _button("已读回看", _toggle_history, false)
	header.add_child(backlog_button)
	settings_button = _button("设置", settings_requested.emit, false)
	header.add_child(settings_button)
	header.add_child(_button("返回战前页  Esc", func() -> void: menu_requested.emit(), false))
	stage = Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 120
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(stage)
	illustration = TextureRect.new()
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Let the lower body continue behind the dialogue panel, instead of leaving
	# a miniature full-body sprite floating above it. Source art stays intact.
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(illustration)
	illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	illustration.anchor_right = 0.48
	illustration.anchor_bottom = 1.6
	dialogue_panel = PanelContainer.new()
	dialogue_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.075, 0.12, 0.95)
	panel_style.border_color = Color(GOLD, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 24; panel_style.content_margin_right = 24
	panel_style.content_margin_top = 16; panel_style.content_margin_bottom = 16
	dialogue_panel.add_theme_stylebox_override("panel", panel_style)
	layout.add_child(dialogue_panel)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 10)
	dialogue_panel.add_child(copy)
	speaker = _label("", 25, GOLD)
	copy.add_child(speaker)
	copy.add_child(HSeparator.new())
	text_body = RichTextLabel.new()
	text_body.custom_minimum_size.y = 160
	text_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_body.bbcode_enabled = false
	text_body.selection_enabled = true
	text_body.add_theme_font_size_override("normal_font_size", 22)
	text_body.add_theme_constant_override("line_separation", 14)
	text_body.add_theme_color_override("default_color", INK)
	copy.add_child(text_body)
	_build_requisition(copy)
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
	armory_button = _button("战役军备", func() -> void: armory_requested.emit(view_token.duplicate()), false)
	armory_button.hide()
	footer.add_child(armory_button)
	footer.add_child(_button("保存进度", func() -> void: save_requested.emit(), false))

func _build_requisition(parent: Control) -> void:
	requisition_panel = PanelContainer.new()
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color("142438")
	surface.border_color = Color("57656a")
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(4)
	for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		surface.set_content_margin(side, 10)
	requisition_panel.add_theme_stylebox_override("panel", surface)
	parent.add_child(requisition_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	requisition_panel.add_child(row)
	requisition_art = TextureRect.new()
	requisition_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	requisition_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	requisition_art.custom_minimum_size = Vector2(128, 82)
	requisition_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(requisition_art)
	var picker := VBoxContainer.new()
	picker.custom_minimum_size.x = 240
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.add_theme_constant_override("separation", 6)
	row.add_child(picker)
	picker.add_child(_label("战前军需", 18, GOLD))
	requisition_choice = OptionButton.new()
	requisition_choice.custom_minimum_size.y = 38
	requisition_choice.add_theme_font_size_override("font_size", 17)
	requisition_choice.item_selected.connect(func(index: int) -> void:
		requisition_requested.emit(str(requisition_choice.get_item_metadata(index)), view_token.duplicate()))
	picker.add_child(requisition_choice)
	requisition_text = RichTextLabel.new()
	requisition_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	requisition_text.custom_minimum_size.y = 104
	requisition_text.add_theme_font_size_override("normal_font_size", 17)
	requisition_text.add_theme_constant_override("line_separation", 4)
	requisition_text.add_theme_color_override("default_color", INK)
	row.add_child(requisition_text)
	requisition_panel.hide()

func render_requisition() -> void:
	var config: Dictionary = setup.get("requisition", {})
	requisition_panel.visible = page.get("type", "") == "battle" and not showing_history and not config.is_empty()
	if not requisition_panel.visible: return
	requisition_choice.clear()
	requisition_choice.add_item("沿用原定军势")
	requisition_choice.set_item_metadata(0, "")
	var selected_id: String = setup.get("selected_requisition", "")
	var selected_index: int = 0
	for id: String in config.offers:
		var definition: Dictionary = Cards.find(id)
		var index: int = requisition_choice.item_count
		requisition_choice.add_item("%s · %d 费" % [definition.name, definition.cost])
		requisition_choice.set_item_metadata(index, id)
		if id == selected_id: selected_index = index
	requisition_choice.select(selected_index)
	var outgoing: Dictionary = Cards.find(config.replace)
	var picked: Dictionary = Cards.find(selected_id)
	if picked.is_empty():
		requisition_art.texture = Art.get_texture("requisition_desk")
		requisition_text.text = "可换下起手的「%s」（%d 费），将一张军需牌直接换入手牌。\n点击出征确认本次阵容。" % [outgoing.name, outgoing.cost]
	else:
		requisition_art.texture = Art.get_texture(selected_id)
		requisition_text.text = "换下「%s」 · %d 费\n%s" % [outgoing.name, outgoing.cost, picked.text.replace("\n", " ")]
	requisition_text.tooltip_text = requisition_text.text
	requisition_text.scroll_to_line(0)

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

func set_reading_size(percent: int) -> void:
	text_body.add_theme_font_size_override("normal_font_size", roundi(22.0 * percent / 100.0))
	text_body.add_theme_constant_override("line_separation", roundi(14.0 * percent / 100.0))
	requisition_text.add_theme_font_size_override("normal_font_size", roundi(17.0 * percent / 100.0))
	requisition_text.custom_minimum_size.y = 128 if percent == 130 else 104

func _clear_actions() -> void:
	for child: Node in actions.get_children():
		actions.remove_child(child)
		child.queue_free()

func _render_page() -> void:
	_clear_actions()
	backlog_button.text = "返回当前对白" if showing_history else "已读回看"
	backlog_button.disabled = history.is_empty()
	# Battle objectives and retry details must not be pushed below a decorative
	# stage in a small window. Dialogue still keeps its portrait/background space.
	var briefing: bool = page.get("type", "") == "battle"
	armory_button.visible = briefing and not showing_history and int(setup.get("armory_slots", 0)) > 0
	if armory_button.visible: armory_button.text = "战役军备  %d/%d" % [setup.get("armory_equipped", 0), setup.armory_slots]
	render_requisition()
	text_body.custom_minimum_size.y = 118 if requisition_panel.visible else 160
	stage.visible = not showing_history and not briefing
	dialogue_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL if showing_history or briefing else Control.SIZE_FILL
	if showing_history:
		illustration.hide()
		speaker.text = "已经走过的路"
		var paragraphs: PackedStringArray = []
		for entry: Dictionary in history: paragraphs.append(entry.text)
		text_body.text = "\n\n".join(paragraphs)
		text_body.scroll_to_line(0)
		backlog_button.grab_focus()
		return
	var speaker_id: String = page.get("speaker_id", "")
	var has_portrait: bool = Art.HERO_ORDER.has(speaker_id) or Art.UNIT_ORDER.has(speaker_id)
	illustration.texture = Art.get_narrative_portrait(speaker_id) if has_portrait else null
	illustration.visible = has_portrait
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
			text_body.text = "作战目标\n%s\n\n%s\n\n敌方指挥：%s\n每回合 90 秒。战斗自动保存，退出后可继续当前局面。%s" % [setup.get("objective", ""), setup.get("brief", ""), setup.get("enemy_name", ""), retry]
			actions.add_child(_button("重新出征" if page.attempts > 0 else "率军出征", _battle.bind(view_token.duplicate())))
			if page.get("can_retreat", false):
				actions.add_child(_button("撤出任务 · 回到主线", retreat_requested.emit.bind(view_token.duplicate())))
		"end":
			speaker.text = page.get("ending_title", page.get("chapter", "本章") + " · 章末")
			if not page.get("next_chapter", {}).is_empty():
				actions.add_child(_button("进入" + page.next_chapter.title, _next_chapter.bind(view_token.duplicate())))
			else:
				actions.add_child(_button("章节重走", replay_requested.emit))
			actions.add_child(_button("返回战前页", func() -> void: menu_requested.emit()))
	if actions.get_child_count() > 0: actions.get_child(0).grab_focus()

func _advance(expected: Dictionary) -> void: advance_requested.emit(expected)
func _choose(option: String, expected: Dictionary) -> void: choice_requested.emit(option, expected)
func _battle(expected: Dictionary) -> void: battle_requested.emit(expected)
func _next_chapter(expected: Dictionary) -> void: next_chapter_requested.emit(expected)

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
