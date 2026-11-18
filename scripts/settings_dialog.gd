extends ConfirmationDialog

signal save_requested(values: Dictionary)

const Preferences = preload("res://scripts/settings_store.gd")
var display: OptionButton
var reading: OptionButton
var motion: CheckButton
var music: HSlider
var effects: HSlider
var defaults_button: Button
var status: Label
var content: VBoxContainer

func _ready() -> void:
	title = "游戏设置"
	exclusive = true
	unresizable = true
	dialog_hide_on_ok = false
	ok_button_text = "保存设置"
	cancel_button_text = "取消"
	confirmed.connect(func() -> void:
		save_requested.emit({"fullscreen": display.selected == 1, "reading_size": reading.get_selected_id(),
			"reduce_motion": motion.button_pressed, "music": int(music.value), "effects": int(effects.value)}))
	content = VBoxContainer.new()
	content.position = Vector2(20, 18)
	content.custom_minimum_size.x = 480
	content.add_theme_constant_override("separation", 13)
	add_child(content)
	display = OptionButton.new()
	display.add_item("窗口")
	display.add_item("全屏")
	_row("显示模式", display)
	reading = OptionButton.new()
	for percent: int in Preferences.READING_SIZES: reading.add_item("%d%%" % percent, percent)
	reading.tooltip_text = "调整剧情正文、战前军议和已读回看字号。"
	_row("剧情字号", reading)
	motion = CheckButton.new()
	motion.text = "简化"
	motion.tooltip_text = "减少位移动画、飞行特效和天气动效，保留命中、护盾和行动提示。"
	_row("战斗动效", motion)
	content.add_child(HSeparator.new())
	music = _volume("背景音乐")
	effects = _volume("战斗音效")
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)
	defaults_button = Button.new()
	defaults_button.text = "恢复默认"
	defaults_button.pressed.connect(func() -> void: _set_fields(Preferences.DEFAULTS))
	footer.add_child(defaults_button)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 14)
	footer.add_child(status)

func _row(label: String, field: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var heading := Label.new()
	heading.text = label
	heading.custom_minimum_size.x = 126
	row.add_child(heading)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size.y = 36
	row.add_child(field)
	content.add_child(row)
	return row

func _volume(label: String) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	var row: HBoxContainer = _row(label, slider)
	var value := Label.new()
	value.text = "0%"
	value.custom_minimum_size.x = 52
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	slider.value_changed.connect(func(percent: float) -> void: value.text = "%d%%" % int(percent))
	return slider

func _set_fields(values: Dictionary) -> void:
	display.select(1 if values.fullscreen else 0)
	reading.select(Preferences.READING_SIZES.find(values.reading_size))
	motion.set_pressed_no_signal(values.reduce_motion)
	music.value = values.music
	effects.value = values.effects

func open_preferences(values: Dictionary, notice: String, writable: bool) -> void:
	_set_fields(values)
	get_ok_button().disabled = not writable
	defaults_button.disabled = not writable
	set_status(notice)
	popup_centered(Vector2i(565, 450))
	display.grab_focus()

func set_status(value: String, failure: bool = false) -> void:
	status.text = value
	status.add_theme_color_override("font_color", Color("f08b76") if failure else Color("b7c7ce"))
