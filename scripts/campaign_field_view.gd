extends PanelContainer
## The board receives a detached battle. Its inspection signals never execute moves.

signal close_requested
signal switch_requested(previous: bool)
signal deploy_requested

const Board = preload("res://scripts/board_view.gd")
const Difficulty = preload("res://scripts/campaign_difficulty.gd")
const GOLD := Color("e2c58e")
const PAPER := Color("edf0e5")
const MUTED := Color("b1c5c5")

var board: BoardView
var mission: Label
var subtitle: Label
var reason: Label
var objective: Label
var points: HFlowContainer
var detail: Label
var record_heading: Label
var record: Label
var opening_button: Button
var previous_button: Button
var deploy_button: Button
var sidebar: PanelContainer
var scroll: ScrollContainer
var selected_cell := Vector2i(-1, -1)
var previous: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _surface(Color("101c29"), Color("526566"), 24))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var headings := VBoxContainer.new()
	headings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(headings)
	mission = _label(headings, 32, GOLD)
	subtitle = _label(headings, 18, MUTED)
	_button(header, "返回简报  Esc", close_requested.emit)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	var table := PanelContainer.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_stylebox_override("panel", _surface(Color("15252b"), Color("4c6667"), 6))
	body.add_child(table)
	board = Board.new()
	table.add_child(board)
	board.grid_visible = true
	board.set_reduced_motion(true)
	board.set_process(false)
	board.cell_clicked.connect(func(cell: Vector2i, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT: inspect(cell))
	board.cell_hovered.connect(func(cell: Vector2i) -> void:
		if board.keyboard_active and board.battle != null and board.battle.inside(cell): inspect(cell))
	sidebar = PanelContainer.new()
	sidebar.add_theme_stylebox_override("panel", _surface(Color("1a2b35"), Color("516264"), 16))
	body.add_child(sidebar)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	sidebar.add_child(scroll)
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_theme_constant_override("separation", 10)
	scroll.add_child(notes)
	reason = _label(notes, 22, GOLD)
	objective = _label(notes, 18, PAPER)
	points = HFlowContainer.new()
	notes.add_child(points)
	notes.add_child(HSeparator.new())
	detail = _label(notes, 18, PAPER)
	notes.add_child(HSeparator.new())
	record_heading = _label(notes, 21, GOLD)
	record = _label(notes, 17, MUTED)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	opening_button = _button(footer, "本次开局", switch_requested.emit.bind(false))
	previous_button = _button(footer, "上次终局", switch_requested.emit.bind(true))
	var controls := _label(footer, 16, MUTED)
	controls.text = "点选地格或用方向键查看 · 滚轮缩放 · 中键拖动"
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(footer, "全图", func() -> void: board.fit_map(); board.grab_focus())
	deploy_button = _button(footer, "率军出征", deploy_requested.emit)
	resized.connect(_resize_sidebar)
	_resize_sidebar()
	hide()

func _surface(fill: Color, edge: Color, inset: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side,inset)
	return style

func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Control, caption: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 44
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button

func _resize_sidebar() -> void:
	sidebar.custom_minimum_size.x = clampf(size.x*0.29, 320, 480)

func set_reading_size(percent: int) -> void:
	for label: Label in [objective, detail, record]:
		label.add_theme_font_size_override("font_size", roundi(18.0 * percent / 100.0))

func open(field: Battle, setup: Dictionary, mode: String, review: bool, attempts: int, has_history: bool) -> void:
	previous = review
	board.battle = field
	board.reset_effects()
	board.fit_map()
	mission.text = setup.title
	var stage := "第 %d 次出征的终局 · 第 %d 轮" % [attempts, ceili(field.turn/2.0)] if previous else "出征前 · 尚未计时"
	if previous and not field.objective.is_empty() and not field.commander(0).is_empty() and not field.commander(1).is_empty():
		stage = "第 %d 次出征的终局 · 已过 %d 个完整轮次" % [attempts,(field.turn-1)/2]
	subtitle.text = "%s   /   %s难度   /   %s" % [field.map_definition.name, "剧情" if mode == Difficulty.STORY else "标准", stage]
	reason.text = field.result_reason() if previous else "作战目标"
	objective.text = field.objective_status() if not field.objective.is_empty() else "击败%s，保护%s。" % [field.hero(1).name, field.hero(0).name]
	for child: Node in points.get_children(): points.remove_child(child); child.queue_free()
	var focus := Vector2i(field.width / 2, field.height / 2)
	for side: int in [0, 1]:
		var leader: Dictionary = field.commander(side)
		if leader.is_empty(): continue
		var loc: Vector2i = leader.pos
		_marker("我方指挥" if side == 0 else "敌方指挥", loc)
		if side == 0: focus = loc
	var escort: Dictionary = field.escort_unit()
	if not escort.is_empty(): _marker("担架队", escort.pos)
	var cells: Array = field.objective.get("cells", [])
	for i: int in range(cells.size()):
		var cell: Vector2i = field.ControlObjective.position(cells[i])
		var label := "出口" if field.ControlObjective.is_escort(field.objective) else ("第%d站" % (i+1) if field.ControlObjective.is_relay(field.objective) else "据点")
		_marker(label, cell, previous)
	if not cells.is_empty():
		var index: int = clampi(int(field.objective.streak),0,cells.size()-1) if field.ControlObjective.is_relay(field.objective) else 0
		focus = field.ControlObjective.position(cells[index])
	var lines := PackedStringArray()
	if previous:
		record_heading.text = "末段战报"
		for entry: String in field.log_lines:
			if not entry.contains("回合 · 法力"): lines.append(entry)
		lines = lines.slice(maxi(0,lines.size()-5))
	else:
		record_heading.text = "我方起手 · %d 法力" % int(field.players[0].mana)
		for instance: Dictionary in field.players[0].hand:
			var card: Dictionary = field.definition(instance.card_id)
			lines.append("%d 费  %s" % [card.cost, card.name])
	record.text = "\n".join(lines)
	opening_button.visible = has_history
	previous_button.visible = has_history
	opening_button.disabled = not previous
	previous_button.disabled = previous
	deploy_button.visible = not previous
	scroll.scroll_vertical = 0
	show()
	inspect(focus)
	board.grab_focus()

func _marker(label: String, cell: Vector2i, show_occupant: bool = false) -> void:
	var caption := label + " " + board.battle.cell_name(cell)
	if show_occupant:
		var unit := board.battle.unit_at(cell)
		caption += " · " + ("空" if unit.is_empty() else ("我方" if unit.side == 0 else "敌方"))
	_button(points, caption, func() -> void: board.reveal_cell(cell); inspect(cell); board.grab_focus())

func inspect(cell: Vector2i) -> void:
	var field: Battle = board.battle
	if field == null or not field.inside(cell): return
	selected_cell = cell
	board.keyboard_cell = cell
	board.keyboard_active = true
	board.hover_cell = cell
	var ground: Dictionary = field.TERRAIN[field.ground(cell)]
	var unit := field.unit_at(cell)
	board.selected_unit = unit.get("id",-1)
	detail.text = "%s  ·  %s\n%s" % [field.cell_name(cell), ground.name, ground.description]
	if not unit.is_empty():
		detail.text += "\n%s · %s   生命 %d/%d   护盾 %d" % ["我方" if unit.side == 0 else "敌方", unit.name, unit.hp, unit.max_hp, unit.shield]
		if unit.get("guarding", false) and int(unit.rooted_turns) == 0: detail.text += "\n正在援护相邻友军"
	board.queue_redraw()
