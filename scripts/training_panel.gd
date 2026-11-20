extends PanelContainer

signal lesson_requested(index: int)
signal reset_requested
signal next_requested
signal exit_requested

const Training = preload("res://scripts/training.gd")
var lesson_choice: OptionButton
var instruction: Label
var continue_button: Button
var reset_button: Button
var exit_button: Button
var progress: Label

func _ready() -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	add_child(content)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	content.add_child(row)
	lesson_choice = OptionButton.new()
	lesson_choice.tooltip_text = "可跳到任一节练习。"
	for lesson: Dictionary in Training.LESSONS: lesson_choice.add_item(lesson.name)
	lesson_choice.item_selected.connect(lesson_requested.emit)
	row.add_child(lesson_choice)
	progress = Label.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.add_theme_font_size_override("font_size", 15)
	progress.add_theme_color_override("font_color", Color("d0b579"))
	row.add_child(progress)
	reset_button = _button(row, "重练本节", reset_requested.emit)
	exit_button = _button(row, "退出练习", exit_requested.emit)
	continue_button = _button(row, "下一课", next_requested.emit)
	instruction = Label.new()
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.add_theme_font_size_override("font_size", 16)
	instruction.add_theme_color_override("font_color", Color("eee8db"))
	content.add_child(instruction)
	hide()

func _button(row: HBoxContainer, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	row.add_child(button)
	return button

func update_step(training: RefCounted, battle: Battle) -> void:
	visible = training != null
	if training == null: return
	var lesson: Dictionary = Training.LESSONS[training.lesson]
	lesson_choice.select(training.lesson)
	continue_button.visible = training.complete()
	continue_button.text = "完成练习" if training.lesson == Training.LESSONS.size() - 1 else "下一课"
	if training.resolving:
		progress.text = "结算中"
		instruction.text = "铁骑正沿路线移动，留意绊索收紧的位置。" if battle.active_side == 1 else "空锤正在落下，留意铁骑和金色十字的位置。"
		return
	progress.text = "本节完成" if training.complete() else "第 %d / %d 步" % [training.step_index + 1, lesson.steps.size()]
	var step: Dictionary = training.current()
	instruction.text = training.conclusion(battle) if step.is_empty() else step.text
	var target: Variant = step.get("target_hint", step.get("target"))
	if target is Vector2i: instruction.text += "  ·  目标 %s" % battle.cell_name(target)
