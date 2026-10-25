class_name WarCouncil
extends Control

signal start_requested(map_id: String, hero_id: String, deck_id: String)
signal resume_requested
signal library_requested
signal deck_editor_requested

const BattleModel = preload("res://scripts/battle.gd")
const Art = preload("res://scripts/art_library.gd")
const CardArt = preload("res://scripts/card_view.gd")
const GOLD := Color("d0b579")
const INK := Color("e6e8dd")
const MUTED := Color("a5b8af")
var selected_map: String = "greenwood"
var selected_hero: String = "warden"
var selected_deck: String = "balanced"
var map_buttons: Array[Button] = []
var hero_buttons: Array[Button] = []
var start_button: Button
var resume_button: Button
var library_button: Button
var editor_button: Button
var deck_choice: OptionButton
var background: Texture2D
var map_options: Array[Dictionary] = []
var custom_definition: Dictionary = {}
var hero_showcase: Control
var hero_name: Label
var hero_title: Label
var hero_lore: Label
var shown_hero: String = ""
var hero_fade: Tween

class HeroPortrait extends Control:
	var texture: Texture2D
	func _draw() -> void:
		if texture != null: Art.draw_cover(self, texture, Rect2(Vector2.ZERO, size), Vector2(0.5, 0.24))

class HeroShowcase extends Control:
	var texture: Texture2D
	func _draw() -> void:
		var center := Vector2(size.x * 0.5, size.y * 0.57)
		var radius: float = minf(size.x * 0.43, size.y * 0.39)
		for ring: float in [1.0, 0.91, 0.7]:
			draw_arc(center, radius * ring, 0, TAU, 96, Color(0.84, 0.76, 0.54, 0.35), 1, true)
		for ray: int in range(12):
			var direction := Vector2.from_angle(ray * TAU / 12)
			draw_line(center + direction * radius * 0.94, center + direction * radius * 1.05, Color("bdac7a"), 2)
		if texture != null:
			var target := Rect2(Vector2(0, 5), size - Vector2(0, 10))
			var ratio: float = minf(target.size.x / texture.get_width(), target.size.y / texture.get_height())
			var extent: Vector2 = texture.get_size() * ratio
			draw_texture_rect(texture, Rect2(target.position + (target.size - extent) / 2, extent), false)


class MapSwatch extends Control:
	const Field = preload("res://scripts/battlefield_art.gd")
	const Painted = preload("res://scripts/map_artwork.gd")
	var data: Dictionary
	var preview_battle: Battle
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		preview_battle = BattleModel.new(1, str(data.id))
	func _draw() -> void:
		if data.is_empty() or preview_battle == null: return
		var extent: float = minf(size.x / preview_battle.width, size.y / preview_battle.height)
		var origin: Vector2 = (size - Vector2(preview_battle.width, preview_battle.height) * extent) / 2
		if not Painted.draw_map(self, preview_battle, Rect2(origin, Vector2(preview_battle.width, preview_battle.height) * extent)):
			for y: int in range(preview_battle.height):
				for x: int in range(preview_battle.width):
					var cell := Vector2i(x, y)
					var rect := Rect2(origin + Vector2(cell) * extent, Vector2.ONE * extent)
					Field.draw_ground(self, preview_battle, cell, rect, 0)
			for y: int in range(preview_battle.height):
				for x: int in range(preview_battle.width):
					var cell := Vector2i(x, y)
					var rect := Rect2(origin + Vector2(cell) * extent, Vector2.ONE * extent)
					Field.draw_prop(self, preview_battle.ground(cell), rect, str(data.theme), str(data.id))
		draw_rect(Rect2(origin, Vector2(preview_battle.width, preview_battle.height) * extent), Color("b5a174"), false, 1)
		for index: int in range(2):
			var cell: Vector2i = data.spawns[index]
			draw_circle(origin + (Vector2(cell) + Vector2.ONE * 0.5) * extent, extent * 0.23, Color("b9f2ef") if index == 0 else Color("ffb19c"))

func _ready() -> void:
	map_options = BattleModel.MAPS.available()
	background = Art.get_texture("menu")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	_build()
	_refresh_selection()

func _draw() -> void:
	if background != null: Art.draw_cover(self, background, Rect2(Vector2.ZERO, size), Vector2(0.5, 0.5))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.09, 0.15, 0.28))
	# The left stage is reserved for the selected character; the right is an in-world briefing sheet.
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * 0.37, size.y)), Color(0.035, 0.10, 0.17, 0.81))
	draw_line(Vector2(size.x * 0.37, 0), Vector2(size.x * 0.37, size.y), Color("bca777"), 2)
	draw_line(Vector2(30, 24), Vector2(size.x - 30, 24), Color(GOLD, 0.6), 1)
	draw_line(Vector2(30, size.y - 24), Vector2(size.x - 30, size.y - 24), Color(GOLD, 0.6), 1)

func _build() -> void:
	var left := VBoxContainer.new()
	add_child(left)
	left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.anchor_right = 0.37
	left.offset_left = 40
	left.offset_right = -30
	left.offset_top = 45
	left.offset_bottom = -42
	left.add_theme_constant_override("separation", 8)
	left.add_child(_label("S I G I L S   &   O A T H S", 13, GOLD))
	left.add_child(_label("纹章与誓约", 40, INK))
	left.add_child(_label("以卡为令，落子成军。", 16, Color("c0d3db")))
	hero_showcase = HeroShowcase.new()
	hero_showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_showcase.custom_minimum_size.y = 170
	left.add_child(hero_showcase)
	hero_title = _label("", 14, GOLD)
	hero_name = _label("", 28, INK)
	hero_lore = _label("", 14, Color("c2d3d8"), true)
	left.add_child(hero_title)
	left.add_child(hero_name)
	left.add_child(hero_lore)
	var heroes_row := HBoxContainer.new()
	heroes_row.add_theme_constant_override("separation", 10)
	left.add_child(heroes_row)
	for hero: Dictionary in BattleModel.HEROES.heroes:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 68)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_choose_hero.bind(String(hero.id)))
		button.tooltip_text = "%s · %s\n%s\n%s" % [hero.name, hero.title, hero.passive_text, hero.skill_text]
		heroes_row.add_child(button)
		hero_buttons.append(button)
		var inset: MarginContainer = _inset(button, 3)
		var portrait := HeroPortrait.new()
		portrait.texture = Art.get_texture(hero.portrait)
		portrait.clip_contents = true
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(portrait)
	var sheet := PanelContainer.new()
	add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.anchor_left = 0.40
	sheet.offset_left = 0
	sheet.offset_right = -40
	sheet.offset_top = 60
	sheet.offset_bottom = -60
	var paper: StyleBoxFlat = _style(Color(0.055, 0.11, 0.18, 0.94), Color("bca777"))
	paper.content_margin_left = 24
	paper.content_margin_right = 24
	paper.content_margin_top = 24
	paper.content_margin_bottom = 24
	sheet.add_theme_stylebox_override("panel", paper)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	sheet.add_child(layout)
	layout.add_child(_label("作 战 准 备", 28, INK))
	layout.add_child(_label("WAR COUNCIL     /     选择你的下一场战役", 12, GOLD))
	layout.add_child(HSeparator.new())
	layout.add_child(_label("01   战场 · 12 × 10", 17, GOLD))
	var maps_row := GridContainer.new()
	maps_row.columns = 2
	maps_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	maps_row.add_theme_constant_override("h_separation", 12)
	maps_row.add_theme_constant_override("v_separation", 10)
	layout.add_child(maps_row)
	for map: Dictionary in map_options:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 91)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = map.description
		button.pressed.connect(_choose_map.bind(String(map.id)))
		maps_row.add_child(button)
		map_buttons.append(button)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		_inset(button, 10).add_child(row)
		var preview := MapSwatch.new()
		preview.data = map
		preview.custom_minimum_size = Vector2(128, 106)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(preview)
		var copy := VBoxContainer.new()
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(copy)
		copy.add_child(_label(map.name, 18, INK))
		copy.add_child(_label(map.subtitle, 12, Color("b0c4cf"), true))
	layout.add_child(_label("02   军势 · 30张套牌", 17, GOLD))
	var deck_row := HBoxContainer.new()
	deck_row.add_theme_constant_override("separation", 10)
	layout.add_child(deck_row)
	deck_choice = OptionButton.new()
	deck_choice.custom_minimum_size = Vector2(160, 42)
	deck_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for deck: Dictionary in BattleModel.DECKS.decks:
		deck_choice.add_item(deck.name)
		deck_choice.set_item_metadata(deck_choice.item_count - 1, deck.id)
	deck_choice.item_selected.connect(func(index: int) -> void:
		selected_deck = deck_choice.get_item_metadata(index)
		deck_choice.tooltip_text = _deck_description())
	deck_row.add_child(deck_choice)
	library_button = Button.new()
	library_button.text = "牌库图鉴"
	library_button.pressed.connect(func() -> void: library_requested.emit())
	deck_row.add_child(library_button)
	editor_button = Button.new()
	editor_button.text = "编辑军势"
	editor_button.pressed.connect(func() -> void: deck_editor_requested.emit())
	deck_row.add_child(editor_button)
	layout.add_child(_label("邻接友军即可增援  ·  地形制胜  ·  每回合90秒", 13, Color("a9bdc9")))
	start_button = Button.new()
	start_button.custom_minimum_size = Vector2(0, 64)
	start_button.text = "率 军 出 征     →"
	start_button.add_theme_font_size_override("font_size", 24)
	start_button.add_theme_stylebox_override("normal", _style(Color("365a71"), GOLD))
	start_button.pressed.connect(func() -> void: start_requested.emit(selected_map, selected_hero, selected_deck))
	layout.add_child(start_button)
	resume_button = Button.new()
	resume_button.custom_minimum_size.y = 38
	resume_button.text = "返回当前战斗"
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	layout.add_child(resume_button)

func open(map_id: String, hero_id: String, can_resume: bool, deck_id: String = "balanced") -> void:
	selected_map = map_id
	selected_hero = hero_id
	selected_deck = deck_id
	for index: int in range(deck_choice.item_count):
		if deck_choice.get_item_metadata(index) == deck_id: deck_choice.select(index)
	deck_choice.tooltip_text = _deck_description()
	resume_button.visible = can_resume
	_refresh_selection()
	show()
	start_button.grab_focus()

func _deck_description() -> String:
	return custom_definition.description if selected_deck == "custom" and not custom_definition.is_empty() else BattleModel.DECKS.find(selected_deck).description

func set_custom_deck(definition: Dictionary, choose: bool = false) -> void:
	custom_definition = definition.duplicate(true)
	var custom_index: int = -1
	for index: int in range(deck_choice.item_count):
		if deck_choice.get_item_metadata(index) == "custom": custom_index = index
	if custom_index == -1:
		deck_choice.add_item("自定义军势")
		custom_index = deck_choice.item_count - 1
		deck_choice.set_item_metadata(custom_index, "custom")
	if choose:
		selected_deck = "custom"
		deck_choice.select(custom_index)
		deck_choice.tooltip_text = _deck_description()

func _choose_map(map_id: String) -> void:
	selected_map = map_id
	_refresh_selection()

func _choose_hero(hero_id: String) -> void:
	selected_hero = hero_id
	_refresh_selection()

func _refresh_selection() -> void:
	if hero_showcase != null:
		for hero: Dictionary in BattleModel.HEROES.heroes:
			if hero.id != selected_hero: continue
			if not shown_hero.is_empty() and shown_hero != selected_hero:
				if hero_fade != null: hero_fade.kill()
				hero_showcase.modulate.a = 0.0
				hero_fade = create_tween()
				hero_fade.tween_property(hero_showcase, "modulate:a", 1.0, 0.18)
			shown_hero = selected_hero
			hero_showcase.texture = Art.get_texture("sprite_" + str(hero.id))
			hero_showcase.queue_redraw()
			hero_name.text = hero.name
			hero_title.text = hero.title + "  /  COMMANDER"
			hero_lore.text = "%s · %d法力\n%s" % [hero.skill, hero.cost, hero.passive_text]
	for index: int in range(map_buttons.size()):
		var selected: bool = map_options[index].id == selected_map
		map_buttons[index].add_theme_stylebox_override("normal", _style(Color("263e39") if selected else Color("13242d"), GOLD if selected else Color("425454")))
	for index: int in range(hero_buttons.size()):
		var selected: bool = BattleModel.HEROES.heroes[index].id == selected_hero
		hero_buttons[index].add_theme_stylebox_override("normal", _style(Color("263e39") if selected else Color("13242d"), GOLD if selected else Color("425454")))

func _label(value: String, font_size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap: label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _inset(parent: Control, padding: int) -> MarginContainer:
	var margin := MarginContainer.new()
	parent.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, padding)
	return margin

func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style

func _map_summary(map_id: String) -> String:
	match map_id:
		"greenwood": return "林地掩护，侧翼军道，争夺高地射界。"
		"rivergate": return "双桥控制河谷，桥头就是前线部署支点。"
		"ridgepass": return "山带分割阵线，封锁隘口或从侧翼增援。"
		"citadel": return "工事保护推进，开阔侧翼适合骑兵突击。"
		"harbor": return "港区运河分隔两岸，横桥与近岸堡垒相互掩护。"
		_: return "军道穿过遗迹，在废墟高台争夺主动。"

func _emblem_texture(color: Color) -> Texture2D:
	var image := Image.create(96, 140, false, Image.FORMAT_RGBA8)
	image.fill(Color("142a30"))
	for y: int in range(20, 120):
		for x: int in range(15, 81):
			var dx: float = (x - 48) / 33.0
			var dy: float = (y - 70) / 50.0
			if dx * dx + dy * dy < 1: image.set_pixel(x, y, Color(color, 0.22))
	return ImageTexture.create_from_image(image)

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and resume_button.visible:
		resume_requested.emit()
		get_viewport().set_input_as_handled()
