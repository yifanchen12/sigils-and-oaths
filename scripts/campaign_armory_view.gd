extends Control
## Draft equipment for the next encounter; save only through CampaignSession.

signal submitted(picks: Dictionary, expected: Dictionary)
signal cancelled

const Armory = preload("res://scripts/campaign_armory.gd")
const Art = preload("res://scripts/art_library.gd")
const INK := Color("e8e7df")
const MUTED := Color("b0c5cc")
const GOLD := Color("dfc68e")
const RED := Color("ffa494")

var backdrop: Texture2D
var mission: Label
var status: Label
var save_button: Button
var cancel_button: Button
var slots: Dictionary = {}
var briefing: Dictionary = {}
var selected_requisition: String = ""
var starting: Dictionary = {}
var draft: Dictionary = {}
var view_token: Dictionary = {}
var unlocked: int = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop = Art.get_texture("campaign_armory")
	_build()
	resized.connect(queue_redraw)
	hide()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color("0b1625"))
	if backdrop != null: Art.draw_cover(self, backdrop, rect, Vector2(0.5, 0.38))
	draw_rect(rect, Color(0.03, 0.06, 0.09, 0.28))

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _panel(fill: Color, border: Color, inset: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var surface := StyleBoxFlat.new()
	surface.bg_color = fill
	surface.border_color = border
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(6)
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		surface.set_content_margin(side, inset)
	panel.add_theme_stylebox_override("panel", surface)
	return panel

func _build() -> void:
	var frame: PanelContainer = _panel(Color(0.045, 0.083, 0.13, 0.92), Color("8b7857"), 26)
	add_child(frame)
	frame.anchor_left = 0.075
	frame.anchor_right = 0.925
	frame.anchor_top = 0.075
	frame.anchor_bottom = 0.925
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	frame.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(header)
	header.add_child(_label("战役军备", 35, GOLD))
	mission = _label("", 20, INK)
	mission.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(mission)
	cancel_button = Button.new()
	cancel_button.text = "返回简报  Esc"
	cancel_button.custom_minimum_size = Vector2(144, 45)
	cancel_button.pressed.connect(cancelled.emit)
	header.add_child(cancel_button)
	layout.add_child(_label("从牌库换出一张同类牌。下方顺位从起手之后计数，定向检索会改变抽牌顺序。", 18, MUTED))
	var rack := HBoxContainer.new()
	rack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rack.add_theme_constant_override("separation", 14)
	layout.add_child(rack)
	for slot: Dictionary in Armory.SLOTS:
		_build_slot(rack, slot)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 15)
	layout.add_child(footer)
	status = _label("", 18, MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(status)
	save_button = Button.new()
	save_button.text = "保存编成"
	save_button.custom_minimum_size = Vector2(160, 48)
	save_button.pressed.connect(func() -> void: submitted.emit(draft.duplicate(), view_token.duplicate()))
	footer.add_child(save_button)

func _build_slot(rack: HBoxContainer, slot: Dictionary) -> void:
	var panel: PanelContainer = _panel(Color("15283b"), Color("455b70"), 15)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	panel.add_child(content)
	content.add_child(_label(slot.name, 23, GOLD))
	var band: String = "%d–%d 费  /  牌库第 %d 张" % [slot.min_cost, slot.max_cost, slot.draw]
	content.add_child(_label(band, 16, MUTED))
	var choice := OptionButton.new()
	choice.fit_to_longest_item = false
	choice.custom_minimum_size.y = 42
	choice.item_selected.connect(_change.bind(str(slot.id)))
	content.add_child(choice)
	var picture := TextureRect.new()
	picture.custom_minimum_size.y = 138
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(picture)
	var swap: Label = _label("", 17, GOLD)
	swap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	swap.custom_minimum_size.y = 26
	content.add_child(swap)
	var rules := RichTextLabel.new()
	rules.custom_minimum_size.y = 108
	rules.add_theme_constant_override("line_separation", 4)
	rules.add_theme_color_override("default_color", INK)
	content.add_child(rules)
	slots[slot.id] = {"choice": choice, "picture": picture, "swap": swap, "rules": rules}

func open(setup: Dictionary, requisition: String, selected: Dictionary, completed: int, expected: Dictionary, reading_size: int) -> void:
	briefing = setup.duplicate(true)
	selected_requisition = requisition
	starting = selected.duplicate()
	draft = selected.duplicate()
	view_token = expected.duplicate()
	unlocked = Armory.unlocked_count(completed)
	mission.text = briefing.title
	for index: int in range(Armory.SLOTS.size()):
		var slot: Dictionary = Armory.SLOTS[index]
		var row: Dictionary = slots[slot.id]
		var choice: OptionButton = row.choice
		choice.clear()
		choice.add_theme_font_size_override("font_size", roundi(17.0 * reading_size / 100.0))
		row.rules.add_theme_font_size_override("normal_font_size", roundi(18.0 * reading_size / 100.0))
		choice.disabled = index >= unlocked
		choice.add_item("第 %d 章完成后开放" % slot.unlock_after if choice.disabled else "留空 · 使用原定牌库")
		choice.set_item_metadata(0, "")
		var selected_index: int = 0
		if not choice.disabled:
			for card: Dictionary in Armory.options(slot):
				var position: int = choice.item_count
				choice.add_item("%s · %d 费" % [card.name, card.cost])
				choice.set_item_metadata(position, card.id)
				if draft.get(slot.id, "") == card.id: selected_index = position
		choice.select(selected_index)
	show()
	queue_redraw()
	_update_draft()
	if unlocked > 0: slots[Armory.SLOTS[0].id].choice.grab_focus()

func _change(index: int, slot_id: String) -> void:
	var pick: String = slots[slot_id].choice.get_item_metadata(index)
	if pick.is_empty(): draft.erase(slot_id)
	else: draft[slot_id] = pick
	_update_draft()

func _update_draft() -> void:
	var result: Dictionary = Armory.prepare(briefing, selected_requisition, draft)
	save_button.disabled = not result.ok or draft == starting
	var changes: Dictionary = result.get("swaps", {})
	for slot: Dictionary in Armory.SLOTS:
		var row: Dictionary = slots[slot.id]
		var change: Dictionary = changes.get(slot.id, {})
		var pick: String = draft.get(slot.id, "")
		var card: Dictionary = Armory.Model.CATALOG.find(pick)
		row.picture.texture = null if card.is_empty() else Art.get_texture(pick)
		row.picture.modulate = Color.WHITE
		if card.is_empty():
			row.picture.texture = backdrop
			row.picture.modulate = Color(0.53, 0.61, 0.66) if row.choice.disabled else Color(0.72, 0.78, 0.81)
		row.swap.text = ""
		if not change.is_empty():
			var outgoing: Dictionary = Armory.Model.CATALOG.find(change.outgoing)
			row.swap.text = "换下「%s」 · %d 费" % [outgoing.name, outgoing.cost]
		row.rules.text = card.get("text", "")
		if row.choice.disabled:
			row.rules.text = "这项补给会随战役推进开放。"
		elif card.is_empty():
			row.rules.text = "选择出征时要加入牌库的一张牌。"
		row.rules.scroll_to_line(0)
	if result.ok:
		set_status("将携带 %d / %d 张军备 · 牌组共 30 张%s" % [draft.size(), unlocked, " · 有待保存的修改" if draft != starting else ""])
	else: set_status(result.message, true)

func set_status(message: String, failed: bool = false) -> void:
	status.text = message
	status.add_theme_color_override("font_color", RED if failed else MUTED)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		cancelled.emit()
		get_viewport().set_input_as_handled()
