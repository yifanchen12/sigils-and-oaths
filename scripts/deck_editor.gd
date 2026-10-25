class_name DeckEditor
extends ConfirmationDialog

signal deck_saved(definition: Dictionary)

const CATALOG = preload("res://data/cards.tres")
const DECKS = preload("res://data/decks.tres")
const CardControl = preload("res://scripts/card_view.gd")
var store: DeckStore
var draft: Dictionary = {}
var rows: Dictionary = {}
var source_choice: OptionButton
var copy_button: Button
var summary: Label
var status: Label
var details: Label
var selected_list: RichTextLabel
var grid: GridContainer
var filter_buttons: Dictionary = {}
var cost_curve: CostCurve

class CostCurve extends Control:
	var counts: Array[int] = [0, 0, 0, 0, 0, 0]
	func _draw() -> void:
		var font: Font = get_theme_default_font()
		var width: float = size.x / counts.size()
		var peak: int = maxi(1, counts.max())
		for index: int in range(counts.size()):
			var height: float = 44.0 * counts[index] / peak
			var x: float = width * index + 5
			draw_rect(Rect2(Vector2(x, 51 - height), Vector2(width - 10, height)), Color("70b8c9"))
			draw_line(Vector2(x, 52), Vector2(x + width - 10, 52), Color("c3ad7e"), 1)
			draw_string(font, Vector2(x + 5, 70), str(index) + ("+" if index == 5 else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b8ccd6"))
			if counts[index] > 0: draw_string(font, Vector2(x + 3, 46 - height), str(counts[index]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e6d7b4"))


func _ready() -> void:
	title = "纹章与誓约 · 自定义组牌"
	size = Vector2i(1100, 820)
	min_size = Vector2i(900, 620)
	exclusive = true
	dialog_hide_on_ok = false
	get_ok_button().text = "保存套牌"
	get_cancel_button().text = "取消"
	confirmed.connect(_save)
	size_changed.connect(_adjust_columns)
	_build()
	_adjust_columns()

func _label(text: String, font_size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _build() -> void:
	var content := VBoxContainer.new()
	add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 20
	content.offset_top = 18
	content.offset_right = -20
	content.offset_bottom = -65
	content.add_theme_constant_override("separation", 12)
	content.add_child(_label("编 成 军 势    /    DECK WORKSHOP", 25))
	content.add_child(_label("30张 · 每种最多4张 · 至少1张部队 · 点击卡面加入军势", 13))
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 12)
	content.add_child(tools)
	source_choice = OptionButton.new()
	source_choice.custom_minimum_size.x = 180
	for deck: Dictionary in DECKS.decks:
		source_choice.add_item(deck.name)
		source_choice.set_item_metadata(source_choice.item_count - 1, deck.id)
	tools.add_child(source_choice)
	copy_button = Button.new()
	copy_button.text = "复制预组牌"
	copy_button.pressed.connect(func() -> void:
		draft = DECKS.find(source_choice.get_selected_metadata()).cards.duplicate(true)
		_refresh("已复制预组牌，尚未保存。"))
	tools.add_child(copy_button)
	summary = _label("", 16)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tools.add_child(summary)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	content.add_child(filters)
	var group := ButtonGroup.new()
	for kind: String in ["all", "unit", "spell", "environment"]:
		var filter := Button.new()
		filter.text = {"all": "全部卡牌", "unit": "部队", "spell": "法术", "environment": "环境"}[kind]
		filter.toggle_mode = true
		filter.button_group = group
		filter.button_pressed = kind == "all"
		filter.pressed.connect(_filter.bind(kind))
		filters.add_child(filter)
		filter_buttons[kind] = filter
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	content.add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for card: Dictionary in CATALOG.cards:
		if card.get("generated_only", false): continue
		var cell := VBoxContainer.new()
		grid.add_child(cell)
		var view: CardView = CardControl.new()
		view.configure(card, -1, 10, false, false)
		view.pressed.connect(_change.bind(String(card.id), 1))
		view.mouse_entered.connect(_inspect.bind(card))
		cell.add_child(view)
		var controls := HBoxContainer.new()
		controls.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(controls)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size.x = 42
		minus.pressed.connect(_change.bind(String(card.id), -1))
		controls.add_child(minus)
		var count := _label("0", 16)
		count.custom_minimum_size.x = 46
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		controls.add_child(count)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size.x = 42
		plus.pressed.connect(_change.bind(String(card.id), 1))
		controls.add_child(plus)
		rows[card.id] = {"cell": cell, "type": card.type, "minus": minus, "plus": plus, "count": count, "view": view}
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 280
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("102136")
	skin.border_color = Color("b5a176")
	skin.set_border_width_all(1)
	for edge: String in ["left", "right", "top", "bottom"]: skin.set("content_margin_" + edge, 12)
	sidebar.add_theme_stylebox_override("panel", skin)
	columns.add_child(sidebar)
	var side := VBoxContainer.new()
	sidebar.add_child(side)
	side.custom_minimum_size.x = 250
	side.add_theme_constant_override("separation", 10)
	side.add_child(_label("自定义军势", 22))
	side.add_child(_label("MANA CURVE  /  法力分布", 11))
	cost_curve = CostCurve.new()
	cost_curve.custom_minimum_size.y = 74
	side.add_child(cost_curve)
	side.add_child(HSeparator.new())
	details = _label("悬停查看卡牌，点击卡面或 + 加入，− 移除。", 14)
	details.custom_minimum_size = Vector2(250, 92)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(details)
	selected_list = RichTextLabel.new()
	selected_list.bbcode_enabled = true
	selected_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selected_list.custom_minimum_size.y = 180
	side.add_child(selected_list)
	var note := _label("保存后在战前菜单选用。\n当前战斗保持原套牌；自定义对阵均衡AI。", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(note)
	status = _label("", 14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status)

func _filter(kind: String) -> void:
	for row: Dictionary in rows.values(): row.cell.visible = kind == "all" or row.type == kind

func _adjust_columns() -> void:
	if grid != null: grid.columns = 4 if size.x >= 1060 else 3

func open_deck(starting: Dictionary, notice: String = "") -> void:
	draft = starting.cards.duplicate(true)
	_filter("all")
	filter_buttons.all.button_pressed = true
	for index: int in range(source_choice.item_count):
		if source_choice.get_item_metadata(index) == starting.id: source_choice.select(index)
	_refresh(notice if not notice.is_empty() else "修改仅在保存后生效。")
	var requested := Vector2i(mini(1100, int(get_parent().get_viewport_rect().size.x) - 40), mini(820, int(get_parent().get_viewport_rect().size.y) - 40))
	popup_centered(requested)
	_adjust_columns()
	# Wrapped labels need their final widths before Window can shrink its minimum.
	await get_tree().process_frame
	await get_tree().process_frame
	if visible: popup_centered(requested)

func _total() -> int:
	var result: int = 0
	for count: int in draft.values(): result += count
	return result

func _change(card_id: String, amount: int) -> void:
	var next: int = int(draft.get(card_id, 0)) + amount
	if next < 0 or next > DECKS.COPY_LIMIT or (amount > 0 and _total() >= DECKS.DECK_SIZE): return
	draft[card_id] = next
	_refresh("尚未保存。")

func _inspect(card: Dictionary) -> void:
	details.text = "%s · %d费\n%s\n%s" % [card.name, card.cost, card.tag, card.text]

func _refresh(notice: String) -> void:
	cost_curve.counts = [0, 0, 0, 0, 0, 0]
	var total: int = _total()
	var troops: int = 0
	var selected: String = ""
	for card: Dictionary in CATALOG.cards:
		if card.get("generated_only", false): continue
		var count: int = int(draft.get(card.id, 0))
		if card.type == "unit": troops += count
		cost_curve.counts[mini(5, int(card.cost))] += count
		rows[card.id].count.text = "%d / 4" % count
		rows[card.id].minus.disabled = count == 0
		rows[card.id].plus.disabled = count >= DECKS.COPY_LIMIT or total >= DECKS.DECK_SIZE
		rows[card.id].view.chosen = count > 0
		rows[card.id].view.deck_copies = count
		rows[card.id].view.queue_redraw()
		if count > 0: selected += "[color=#d0b579]%d费[/color]  %s  ×%d\n" % [card.cost, card.name, count]
	cost_curve.queue_redraw()
	summary.text = "%d / 30张  ·  部队%d  ·  其他%d" % [total, troops, total - troops]
	selected_list.text = selected
	var invalid: String = DECKS.validate_counts(draft, CATALOG.cards)
	get_ok_button().disabled = not invalid.is_empty()
	status.text = invalid if not invalid.is_empty() else notice
	status.add_theme_color_override("font_color", Color("ef8c79") if not invalid.is_empty() else Color("a7c3b4"))

func _save() -> void:
	var result: Dictionary = store.save_deck(draft)
	if not result.ok:
		status.text = result.message
		status.add_theme_color_override("font_color", Color("ef8c79"))
		return
	deck_saved.emit(result.definition)
	hide()
