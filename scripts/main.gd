extends Control

const BattleModel = preload("res://scripts/battle.gd")
const EnemyAI = preload("res://scripts/opponent.gd")
const CardControl = preload("res://scripts/card_view.gd")
const Art = preload("res://scripts/art_library.gd")
const PeekControl = preload("res://scripts/battle_peek.gd")
const Store = preload("res://scripts/deck_store.gd")
const DeckEditorControl = preload("res://scripts/deck_editor.gd")
const Effects = preload("res://scripts/effect_forecast.gd")
const TEAL := Color("70d3ba")
const GOLD := Color("d0b579")
const RED := Color("f08b76")

@onready var board: BoardView = %Board
@onready var hand: HBoxContainer = %Hand
@onready var end_button: Button = %EndTurn
@onready var info_title: Label = %InfoTitle
@onready var info_body: RichTextLabel = %InfoBody
@onready var hint: Label = %Hint
@onready var council: WarCouncil = %WarCouncil

var battle: Battle
var selected_card: int = -1
var selected_unit: int = -1
var inspected_card: int = -1
var hovered_cell := Vector2i(-1, -1)
var ai_running: bool = false
var generation: int = 0
var using_hero: bool = false
var current_map: String = "greenwood"
var current_hero: String = "warden"
var current_deck: String = "balanced"
var has_started: bool = false
var expanded_battlefield: bool = false
var message: String = "选择部队牌，再点击己方部队身旁的青色格部署。"
var error_message: bool = false
var session_rng := RandomNumberGenerator.new()
var battle_peek: BattlePeek
var battle_brief: BattlePeek
var deck_store: DeckStore = Store.new()
var deck_editor: DeckEditor
var custom_deck: Dictionary = {}
var custom_load_notice: String = ""
var grid_button: Button
var unit_skill_button: Button
var unit_action_label: Label
var using_unit_skill: bool = false

func _process(delta: float) -> void:
	if battle == null: return
	_position_battle_peek()
	var paused: bool = not has_started or council.visible or %CardsDialog.visible or %RulesDialog.visible or deck_editor.visible
	if paused or battle.winner != -1:
		if paused and board.is_presenting(): board.reset_effects()
		if battle.winner != -1 and not paused and not board.is_presenting() and not %ResultOverlay.visible: _refresh()
		_update_clock_ui(paused)
		return
	var before: Array = []
	var old_side: int = battle.active_side
	if battle.time_remaining <= delta:
		before = battle.units.duplicate(true)
		generation += 1
		ai_running = false
		selected_card = -1
		selected_unit = -1
		using_hero = false
		using_unit_skill = false
	if battle.advance_clock(delta):
		board.present_action(before, {"type": "end_turn"}, [])
		ai_running = battle.active_side == 1 and battle.winner == -1
		message = "你的回合时间已用尽，赤曜军团开始行动。" if old_side == 0 else "敌方回合超时，轮到你行动。"
		error_message = false
		_refresh()
		if ai_running: _run_ai(generation)
	_update_clock_ui(false)

func _update_clock_ui(paused: bool = false) -> void:
	var seconds: int = maxi(0, ceili(battle.time_remaining))
	%TurnClock.text = ("暂停 " if paused else "回合 ") + "%02d:%02d" % [seconds / 60, seconds % 60]
	%TurnClock.add_theme_color_override("font_color", RED if seconds <= 15 else (GOLD if seconds <= 30 else TEAL))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101d30"))
	for strip: int in range(20):
		var alpha: float = 0.025 * (1.0 - float(strip) / 20.0)
		draw_rect(Rect2(Vector2(0, strip * size.y / 20), Vector2(size.x, size.y / 20 + 1)), Color(0.4, 0.65, 0.85, alpha))
	for x: float in [12.0, size.x - 12.0]:
		draw_line(Vector2(x, 14), Vector2(x, size.y - 14), Color(0.72, 0.62, 0.4, 0.35), 1)
	draw_line(Vector2(18, 12), Vector2(size.x - 18, 12), Color("a88f60"), 1)

func _ready() -> void:
	resized.connect(queue_redraw)
	DisplayServer.window_set_title("纹章与誓约 · v%s" % ProjectSettings.get_setting("application/config/version", "dev"))
	_make_theme()
	# Reuse the canonical controls so shortcuts, focus and pointer routes agree.
	%Restart.reparent(%ViewEnd.get_parent())
	%ViewEnd.get_parent().move_child(%Restart, 0)
	%Restart.tooltip_text = "选择地图、指挥官与军势；菜单中暂停计时。"
	%Help.reparent(%ViewEnd.get_parent())
	%ViewEnd.get_parent().move_child(%Help, 1)
	grid_button = Button.new()
	grid_button.text = "地形网格 G"
	grid_button.toggle_mode = true
	grid_button.tooltip_text = "查看精确地格与地形标识；不改变移动或施法范围。"
	grid_button.toggled.connect(func(value: bool) -> void: board.grid_visible = value; board.queue_redraw())
	%ViewEnd.get_parent().add_child(grid_button)
	%ViewEnd.get_parent().move_child(grid_button, 7)
	var unit_actions := HBoxContainer.new()
	unit_actions.add_theme_constant_override("separation", 12)
	board.get_parent().add_child(unit_actions)
	board.get_parent().move_child(unit_actions, board.get_index())
	unit_action_label = Label.new()
	unit_action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_action_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	unit_action_label.add_theme_font_size_override("font_size", 13)
	unit_action_label.add_theme_color_override("font_color", GOLD)
	unit_actions.add_child(unit_action_label)
	unit_skill_button = Button.new()
	unit_skill_button.add_theme_font_size_override("font_size", 14)
	unit_skill_button.custom_minimum_size = Vector2(178, 34)
	unit_skill_button.pressed.connect(_select_unit_skill)
	unit_actions.add_child(unit_skill_button)
	%CompactHandPanel.add_theme_stylebox_override("panel", _box(Color("182a40"), Color("a28a5a"), 3, 8))
	%ViewEnd.add_theme_stylebox_override("normal", _box(Color("446377"), GOLD, 3, 12))
	%Header.hide()
	%Status.hide()
	%MapName.get_parent().hud_visible = true
	%MapName.get_parent().custom_minimum_size.y = 72
	%MapName.hide()
	%MapType.hide()
	%BattleSummary.hide()
	deck_editor = DeckEditorControl.new()
	deck_editor.theme = theme
	deck_editor.store = deck_store
	add_child(deck_editor)
	deck_editor.deck_saved.connect(_on_deck_saved)
	deck_editor.visibility_changed.connect(_refresh)
	var loaded: Dictionary = deck_store.load_deck()
	if loaded.ok: custom_deck = loaded.definition
	custom_load_notice = loaded.get("message", "")
	battle_peek = PeekControl.new()
	board.add_child(battle_peek)
	battle_brief = PeekControl.new()
	board.add_child(battle_brief)
	session_rng.randomize()
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_on_cell_hovered)
	board.view_changed.connect(func(value: float) -> void: %ZoomValue.text = "%d%%" % roundi(value * 100))
	%ZoomOut.pressed.connect(func() -> void: board.zoom_at(board.size / 2, 1.0 / 1.18))
	%ZoomIn.pressed.connect(func() -> void: board.zoom_at(board.size / 2, 1.18))
	%FitMap.pressed.connect(board.fit_map)
	%ExpandBoard.pressed.connect(_toggle_battlefield)
	%ViewSkill.pressed.connect(_select_hero_skill)
	%ViewEnd.pressed.connect(_end_turn)
	end_button.pressed.connect(_end_turn)
	%Restart.text = "战前菜单"
	%Restart.pressed.connect(_open_council)
	%PlayAgain.pressed.connect(_restart)
	%Cancel.pressed.connect(_cancel)
	%Help.pressed.connect(func() -> void: %RulesDialog.popup_centered())
	%RulesText.text = preload("res://scripts/rules_text.gd").CONTENT
	%HeroSkill.pressed.connect(_select_hero_skill)
	for map: Dictionary in BattleModel.MAPS.available():
		%MapChoice.add_item(map.name)
		%MapChoice.set_item_metadata(%MapChoice.item_count - 1, map.id)
	for hero_data: Dictionary in BattleModel.HEROES.heroes:
		%HeroChoice.add_item(hero_data.name)
		%HeroChoice.set_item_metadata(%HeroChoice.item_count - 1, hero_data.id)
	%MapChoice.item_selected.connect(func(index: int) -> void:
		current_map = %MapChoice.get_item_metadata(index)
		_restart())
	%HeroChoice.item_selected.connect(func(index: int) -> void:
		current_hero = %HeroChoice.get_item_metadata(index)
		_restart())
	for deck_data: Dictionary in BattleModel.DECKS.decks:
		%DeckChoice.add_item(deck_data.name)
		%DeckChoice.set_item_metadata(%DeckChoice.item_count - 1, deck_data.id)
	%DeckChoice.item_selected.connect(func(index: int) -> void:
		current_deck = %DeckChoice.get_item_metadata(index)
		_restart())
	_sync_custom_options()
	%CardLibrary.pressed.connect(_open_library)
	%CardsDialog.visibility_changed.connect(_refresh)
	%RulesDialog.visibility_changed.connect(_refresh)
	council.start_requested.connect(_start_from_council)
	council.resume_requested.connect(_resume_battle)
	council.library_requested.connect(_open_library)
	council.deck_editor_requested.connect(_open_deck_editor)
	_new_match(1)
	council.open(current_map, current_hero, false, current_deck)

func _open_council() -> void:
	council.open(current_map, current_hero, has_started and battle.winner == -1, current_deck)
	_refresh()

func _resume_battle() -> void:
	council.hide()
	_refresh()
	board.grab_focus()

func _start_from_council(map_id: String, hero_id: String, deck_id: String) -> void:
	if deck_id == "custom" and (custom_deck.is_empty() or not BattleModel.DECKS.validate_counts(custom_deck.get("cards"), BattleModel.CATALOG.cards).is_empty()):
		_open_deck_editor()
		deck_editor.status.text = "请先保存30张合法的自定义套牌。"
		return
	current_map = map_id
	current_hero = hero_id
	current_deck = deck_id
	for index: int in range(%MapChoice.item_count):
		if %MapChoice.get_item_metadata(index) == map_id: %MapChoice.select(index)
	for index: int in range(%HeroChoice.item_count):
		if %HeroChoice.get_item_metadata(index) == hero_id: %HeroChoice.select(index)
	for index: int in range(%DeckChoice.item_count):
		if %DeckChoice.get_item_metadata(index) == deck_id: %DeckChoice.select(index)
	council.hide()
	_new_match(1 if not has_started else session_rng.randi_range(1, 999999))
	has_started = true
	if not expanded_battlefield: _toggle_battlefield()
	board.grab_focus()

func _open_library() -> void:
	var deck_id: String = council.selected_deck if council.visible else current_deck
	var selected: Dictionary = _deck_definition(deck_id)
	%LibraryIntro.text = "24 种可组牌 + 1 张后手专属牌   /   %s · 30 张   /   右下角为套牌张数" % selected.name
	for child: Node in %CardGrid.get_children():
		%CardGrid.remove_child(child)
		child.queue_free()
	for card: Dictionary in BattleModel.CATALOG.cards:
		var copies: int = int(selected.cards.get(card.id, 0))
		var view: CardView = CardControl.new()
		view.configure(card, -1, 10, false, false)
		view.deck_copies = copies
		view.tooltip_text += "\n%s" % ("后手专属，不占套牌位置。" if card.get("generated_only", false) else "当前套牌中有 %d 张。" % copies)
		view.pressed.connect(_library_details.bind(card, copies))
		view.mouse_entered.connect(_library_details.bind(card, copies))
		%CardGrid.add_child(view)
	_library_details(BattleModel.CATALOG.cards[0], int(selected.cards.get("sword", 0)))
	%CardsDialog.popup_centered()

func _deck_definition(deck_id: String) -> Dictionary:
	return custom_deck if deck_id == "custom" and not custom_deck.is_empty() else BattleModel.DECKS.find(deck_id)

func _open_deck_editor() -> void:
	var starting: Dictionary = custom_deck if not custom_deck.is_empty() else _deck_definition(council.selected_deck)
	deck_editor.open_deck(starting, custom_load_notice)
	_refresh()

func _sync_custom_options() -> void:
	if custom_deck.is_empty(): return
	var found: bool = false
	for index: int in range(%DeckChoice.item_count):
		if %DeckChoice.get_item_metadata(index) == "custom": found = true
	if not found:
		%DeckChoice.add_item("自定义军势")
		%DeckChoice.set_item_metadata(%DeckChoice.item_count - 1, "custom")
	council.set_custom_deck(custom_deck)

func _on_deck_saved(definition: Dictionary) -> void:
	custom_deck = definition.duplicate(true)
	custom_load_notice = ""
	_sync_custom_options()
	council.set_custom_deck(custom_deck, true)

func _library_details(card: Dictionary, copies: int) -> void:
	%LibraryPortrait.texture = Art.get_texture(str(card.get("kind", card.id)))
	%LibraryPortrait.visible = %LibraryPortrait.texture != null
	%LibraryDetails.text = "[font_size=21][color=#d0b579]%s[/color][/font_size]  ·  %d 费  ·  %s  ·  当前 %d 张\n%s" % [card.name, card.cost, card.tag, copies, card.text]
	if card.type == "unit":
		%LibraryDetails.text += "\n攻击 %d / 生命 %d / 防御 %d / 移动 %d / 射程 %d" % [card.atk, card.hp, card.defense, card.move, card.range]
		if card.has("skill"): %LibraryDetails.text += "\n主动 · %s（1费，每回合一次）：%s" % [card.skill.name, card.skill.text]
	elif card.effect not in ["draw", "mana", "weather", "clear_weather"]:
		%LibraryDetails.text += "\n施法范围：友军3格、法师4格；换位目标另须在指挥官3格内。"

func _make_theme() -> void:
	var ui_theme := Theme.new()
	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 16
	ui_theme.set_color("font_color", "Label", Color("d9e1d9"))
	ui_theme.set_color("default_color", "RichTextLabel", Color("bdcbc4"))
	ui_theme.set_constant("line_separation", "RichTextLabel", 6)
	ui_theme.set_stylebox("panel", "PanelContainer", _box(Color("182a40"), Color("7d775e"), 3, 16))
	ui_theme.set_stylebox("panel", "AcceptDialog", _box(Color("17283d"), Color("b7a174"), 4, 16))
	ui_theme.set_constant("buttons_min_width", "AcceptDialog", 100)
	ui_theme.set_constant("buttons_min_height", "AcceptDialog", 42)
	ui_theme.set_stylebox("normal", "Button", _box(Color("243d55"), Color("788c98"), 3, 12))
	ui_theme.set_stylebox("hover", "Button", _box(Color("3a5870"), GOLD, 3, 12))
	ui_theme.set_stylebox("pressed", "Button", _box(Color("466879"), GOLD, 3, 12))
	ui_theme.set_stylebox("disabled", "Button", _box(Color("13212a"), Color("263b40"), 6, 12))
	var focus_box: StyleBoxFlat = _box(Color(0, 0, 0, 0), GOLD, 6, 0)
	focus_box.set_border_width_all(2)
	ui_theme.set_stylebox("focus", "Button", focus_box)
	ui_theme.set_color("font_color", "Button", Color("e2e8da"))
	ui_theme.set_color("font_disabled_color", "Button", Color("647b7b"))
	ui_theme.set_stylebox("panel", "TooltipPanel", _box(Color("142832"), GOLD, 6, 14))
	ui_theme.set_color("font_color", "TooltipLabel", Color("e6e8dd"))
	ui_theme.set_font_size("font_size", "TooltipLabel", 16)
	theme = ui_theme
	%CardsDialog.theme = ui_theme
	%RulesDialog.theme = ui_theme
	end_button.add_theme_stylebox_override("normal", _box(Color("31544a"), Color("74977b"), 7, 12))
	end_button.add_theme_color_override("font_color", Color("f1e9cb"))

func _box(fill: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box

func _restart() -> void:
	_new_match(session_rng.randi_range(1, 999999))
	board.grab_focus()

func _new_match(seed_value: int) -> void:
	using_unit_skill = false
	generation += 1
	ai_running = false
	using_hero = false
	selected_card = -1
	selected_unit = -1
	inspected_card = -1
	hovered_cell = Vector2i(-1, -1)
	if battle != null and battle.changed.is_connected(_refresh): battle.changed.disconnect(_refresh)
	var hero_index: int = 0
	for index: int in range(BattleModel.HEROES.heroes.size()):
		if BattleModel.HEROES.heroes[index].id == current_hero: hero_index = index
	var enemy_id: String = BattleModel.HEROES.heroes[(hero_index + 1) % BattleModel.HEROES.heroes.size()].id
	var enemy_deck: String = "balanced" if current_deck == "custom" else current_deck
	battle = BattleModel.new(seed_value, current_map, current_hero, enemy_id, current_deck, enemy_deck, 90, custom_deck)
	battle.changed.connect(_refresh)
	board.battle = battle
	board.fit_map()
	board.reset_effects()
	board.last_cell = Vector2i(-1, -1)
	board.hover_cell = Vector2i(-1, -1)
	%ResultOverlay.hide()
	message = "选择部队牌，再点击己方部队身旁的青色格部署。"
	error_message = false
	_refresh()

func _refresh() -> void:
	if battle == null: return
	var player: Dictionary = battle.players[0]
	var enemy: Dictionary = battle.players[1]
	%MapName.get_parent().battle = battle
	%MapName.get_parent().queue_redraw()
	var blue: Dictionary = battle.commander(0)
	var red: Dictionary = battle.commander(1)
	var blue_hp: int = int(blue.get("hp", 0))
	var red_hp: int = int(red.get("hp", 0))
	%BlueStatus.text = "[color=#70d3ba]%s · 你[/color]   [b]%d[/b]/20\n[color=#d0b579]法力 %s[/color] %d/%d  部队 %d/6" % [battle.hero(0).name, blue_hp, _mana_dots(player), player.mana, player.max_mana, battle.army_count(0)]
	%RedStatus.text = "[color=#f08b76]%s · AI[/color]   [b]%d[/b]/20\n[color=#d0b579]法力 %s[/color] %d/%d  部队 %d/6" % [battle.hero(1).name, red_hp, _mana_dots(enemy), enemy.mana, enemy.max_mana, battle.army_count(1)]
	%TurnStatus.text = "第 %d 轮 · %s" % [ceili(float(battle.turn) / 2), "你的回合" if battle.active_side == 0 else "敌方回合"]
	%TurnStatus.add_theme_color_override("font_color", TEAL if battle.active_side == 0 else RED)
	%Seed.text = "v%s / %d" % [ProjectSettings.get_setting("application/config/version", "dev"), battle.match_seed]
	%MapName.text = battle.map_definition.name + " / " + battle.map_definition.subtitle
	%MapType.text = "%d × %d" % [battle.width, battle.height]
	%BattleSummary.text = "你 %d/20  ·  法力 %d/%d    |    敌 %d/20    |    第%d轮 · %s · %s" % [blue_hp, player.mana, player.max_mana, red_hp, ceili(float(battle.turn) / 2), "你的回合" if battle.active_side == 0 else "敌方行动", battle.WEATHER[battle.weather].name]
	%MapName.tooltip_text = battle.map_definition.description
	%WeatherStatus.text = battle.WEATHER[battle.weather].name + (" · 剩余 %d 行动回合" % battle.weather_remaining if battle.weather_remaining > 0 else " · 无环境修正")
	%WeatherStatus.tooltip_text = battle.WEATHER[battle.weather].description
	var own_hero: Dictionary = battle.hero(0)
	%HeroSkill.text = "%s · %d费" % [own_hero.skill, own_hero.cost] if player.skill_cooldown == 0 else "%s · 冷却 %d" % [own_hero.skill, player.skill_cooldown]
	%HeroSkill.disabled = not _player_can_act() or player.skill_cooldown > 0 or player.mana < own_hero.cost
	%HeroSkill.tooltip_text = "%s\n%s\n\n被动「%s」：%s" % [own_hero.skill, own_hero.skill_text, own_hero.passive, own_hero.passive_text]
	%ViewSkill.text = %HeroSkill.text
	%ViewSkill.disabled = %HeroSkill.disabled
	%ViewSkill.tooltip_text = %HeroSkill.tooltip_text
	for side: int in range(2):
		var portrait: TextureRect = %BluePortrait if side == 0 else %RedPortrait
		portrait.texture = Art.get_texture(battle.hero(side).portrait)
		portrait.visible = portrait.texture != null
	%EnemyHand.text = "敌方手牌 %d 张    牌库 %d 张" % [enemy.hand.size(), enemy.deck.size()]
	%HandTitle.text = "你的手牌  %d/8     /     选择卡牌查看详情" % player.hand.size()
	%DeckInfo.text = "牌库 %d   ·   弃牌 %d   ·   疲劳 %d" % [player.deck.size(), player.discard.size(), player.fatigue]
	var log_text: String = ""
	var first: int = maxi(0, battle.log_lines.size() - 16)
	for index: int in range(first, battle.log_lines.size()):
		log_text += "[color=#d0b579]›[/color] " + battle.log_lines[index] + "\n\n"
	%BattleLog.text = log_text
	if selected_card != -1 and battle.hand_card(0, selected_card).is_empty(): selected_card = -1
	if selected_unit != -1 and battle.get_unit(selected_unit).is_empty():
		selected_unit = -1
		using_unit_skill = false
	_update_unit_skill_ui()
	for child: Node in hand.get_children():
		hand.remove_child(child)
		child.queue_free()
	for instance: Dictionary in player.hand:
		var view: CardView = CardControl.new()
		view.configure(battle.definition(instance.card_id), instance.uid, player.mana, instance.uid == selected_card, not _player_can_act())
		view.pressed.connect(_select_card.bind(int(instance.uid)))
		view.mouse_entered.connect(_inspect_card.bind(int(instance.uid)))
		view.mouse_exited.connect(_inspect_card.bind(-1))
		hand.add_child(view)
	end_button.disabled = not _player_can_act()
	end_button.text = "结束回合  →" if battle.active_side == 0 else "敌方行动中…"
	%ViewEnd.disabled = end_button.disabled
	%ViewEnd.text = end_button.text
	_refresh_compact_hand()
	%Cancel.disabled = selected_card == -1 and selected_unit == -1 and not using_hero
	_update_board()
	_update_info()
	var context_hint: Dictionary = _attack_context()
	var effect_hint: Dictionary = _effect_context()
	_show_hint(Effects.hint(effect_hint) if not effect_hint.is_empty() else (_attack_hint(context_hint) if not context_hint.is_empty() else message), error_message if context_hint.is_empty() and effect_hint.is_empty() else false)
	if battle.winner != -1:
		if board.is_presenting():
			%ResultOverlay.hide()
			return
		var already_visible: bool = %ResultOverlay.visible
		%ResultOverlay.show()
		%ResultTitle.text = "苍蓝旗帜，仍在飘扬" if battle.winner == 0 else ("战场归于寂静" if battle.winner == 2 else "此役失利，再整旗鼓")
		%ResultDetail.text = "%s\n共 %d 轮 · 种子 %d" % ["你取得了胜利！" if battle.winner == 0 else ("双方指挥官同时倒下，平局。" if battle.winner == 2 else "赤曜军团赢得本次战斗。"), ceili(float(battle.turn) / 2), battle.match_seed]
		if not already_visible: %PlayAgain.grab_focus()

func _mana_dots(player: Dictionary) -> String:
	var extra: int = maxi(0, int(player.mana) - int(player.max_mana))
	return "◆".repeat(mini(int(player.mana), int(player.max_mana))) + "◇".repeat(maxi(0, int(player.max_mana) - int(player.mana))) + ("[color=#9bc6e7]+%d临时[/color]" % extra if extra > 0 else "")

func _toggle_battlefield() -> void:
	expanded_battlefield = not expanded_battlefield
	%MapName.get_parent().hud_visible = true
	%MapName.get_parent().custom_minimum_size.y = 72
	$Margin/Layout/Shortcuts.visible = not expanded_battlefield
	$Margin/Layout/BattleArea/Center/Legend.visible = not expanded_battlefield
	%Header.hide()
	%Status.hide()
	%BattleSummary.hide()
	%InfoPanel.visible = not expanded_battlefield
	%RightPanel.visible = not expanded_battlefield
	%HandPanel.visible = not expanded_battlefield
	%CompactHandPanel.visible = expanded_battlefield
	%ViewEnd.visible = expanded_battlefield
	%ViewSkill.visible = expanded_battlefield
	%ExpandBoard.text = "详细面板 Tab" if expanded_battlefield else "大地图 Tab"
	_refresh()

func _refresh_compact_hand() -> void:
	for child: Node in %CompactHand.get_children():
		%CompactHand.remove_child(child)
		child.queue_free()
	if not expanded_battlefield: return
	var index: int = 0
	for instance: Dictionary in battle.players[0].hand:
		index += 1
		var card: Dictionary = battle.definition(instance.card_id)
		var button: CardView = CardControl.new()
		button.compact = true
		button.hotkey_number = index
		button.configure(card, instance.uid, battle.players[0].mana, selected_card == instance.uid, not _player_can_act())
		button.pressed.connect(_select_card.bind(int(instance.uid)))
		button.mouse_entered.connect(_inspect_card.bind(int(instance.uid)))
		button.mouse_exited.connect(_inspect_card.bind(-1))
		%CompactHand.add_child(button)

func _player_can_act() -> bool:
	return battle != null and battle.active_side == 0 and battle.winner == -1 and not ai_running and not council.visible and not %CardsDialog.visible and not %RulesDialog.visible and not deck_editor.visible

func _update_board() -> void:
	board.predicted_losses.clear()
	board.selected_unit = selected_unit
	board.moves.clear()
	board.attacks.clear()
	board.deploy.clear()
	board.spell_targets.clear()
	board.cast_reach.clear()
	if _player_can_act():
		if using_hero:
			board.spell_targets = battle.hero_targets(0)
			board.cast_reach = battle.casting_cells(0, true)
		elif using_unit_skill:
			var caster: Dictionary = battle.get_unit(selected_unit)
			board.spell_targets = battle.skill_targets(caster)
			if not caster.is_empty() and caster.kind == "archer": board.attacks = board.spell_targets.duplicate()
		elif selected_card != -1:
			var instance: Dictionary = battle.hand_card(0, selected_card)
			if not instance.is_empty():
				var card: Dictionary = battle.definition(instance.card_id)
				if card.cost <= battle.players[0].mana:
					if card.type == "unit": board.deploy = battle.card_targets(selected_card, 0)
					else:
						board.spell_targets = battle.card_targets(selected_card, 0)
						if card.effect not in ["draw", "mana", "weather", "clear_weather"]: board.cast_reach = battle.casting_cells(0)
		elif selected_unit != -1:
			var unit: Dictionary = battle.get_unit(selected_unit)
			if not unit.is_empty() and unit.side == 0:
				board.moves = battle.movement_cells(unit)
				board.attacks = battle.attack_targets(unit)
	_update_attack_overlay()

func _select_card(uid: int) -> void:
	if not _player_can_act(): return
	using_unit_skill = false
	var instance: Dictionary = battle.hand_card(0, uid)
	if instance.is_empty(): return
	if selected_card == uid:
		_cancel()
		return
	selected_card = uid
	selected_unit = -1
	using_hero = false
	var card: Dictionary = battle.definition(instance.card_id)
	if card.cost > battle.players[0].mana:
		message = "「%s」需要 %d 点法力，当前只有 %d 点。" % [card.name, card.cost, battle.players[0].mana]
		error_message = true
	elif card.get("effect", "") in ["draw", "weather", "mana", "clear_weather"]:
		_commit({"type": "play", "card_uid": uid, "target": Vector2i(-1, -1)})
		return
	else:
		message = "选择青色空格部署「%s」；可紧邻任意己方部队。" % card.name if card.type == "unit" else "「%s」：选择赤色框内的合法目标。" % card.name
		if battle.card_targets(uid, 0).is_empty(): message = "「%s」当前没有合法目标。" % card.name
		error_message = false
	_refresh()
	board.grab_focus()

func _select_hero_skill() -> void:
	if not _player_can_act() or %HeroSkill.disabled: return
	using_unit_skill = false
	if using_hero:
		_cancel()
		return
	using_hero = true
	selected_card = -1
	selected_unit = -1
	if battle.hero(0).effect == "renewal":
		_commit({"type": "hero", "target": Vector2i(-1, -1)})
		return
	message = "指挥官技能「%s」：请选择高亮目标。" % battle.hero(0).skill
	error_message = false
	_refresh()
	board.grab_focus()

func _update_unit_skill_ui() -> void:
	var unit: Dictionary = battle.get_unit(selected_unit)
	var skill: Dictionary = battle.unit_skill(unit)
	unit_skill_button.text = "部队技能 Q" if skill.is_empty() else "%s Q · 1费" % skill.name
	unit_skill_button.disabled = not _player_can_act() or battle.skill_targets(unit).is_empty()
	unit_skill_button.tooltip_text = "选择己方普通部队；新兵不能使用技能。" if skill.is_empty() else "%s\n%s\n1法力，每回合一次；新兵不能使用。" % [skill.name, skill.text]
	unit_action_label.text = "兵种克制：步兵 → 枪兵 → 骑兵 → 步兵 · 伤害 +2" if skill.is_empty() else "%s · %s%s" % [unit.name, "本回合技能已用 · " if unit.get("skill_used", false) else "", skill.text]
	unit_action_label.tooltip_text = unit_skill_button.tooltip_text

func _select_unit_skill() -> void:
	if not _player_can_act() or unit_skill_button.disabled: return
	if using_unit_skill:
		using_unit_skill = false
		_refresh()
		return
	var unit: Dictionary = battle.get_unit(selected_unit)
	selected_card = -1
	inspected_card = -1
	using_hero = false
	using_unit_skill = true
	if unit.kind in ["sword", "spear"]:
		_commit({"type": "unit_skill", "unit_id": unit.id, "target": unit.pos})
		return
	message = "%s：选择高亮目标。%s" % [battle.unit_skill(unit).name, battle.unit_skill(unit).text]
	error_message = false
	_refresh()
	board.grab_focus()

func _on_cell_clicked(cell: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_cancel()
		return
	if button != MOUSE_BUTTON_LEFT or not _player_can_act(): return
	if using_unit_skill:
		_commit({"type": "unit_skill", "unit_id": selected_unit, "target": cell})
		return
	if using_hero:
		_commit({"type": "hero", "target": cell})
		return
	if selected_card != -1:
		_commit({"type": "play", "card_uid": selected_card, "target": cell})
		return
	var target: Dictionary = battle.unit_at(cell)
	if not target.is_empty() and target.side == 0:
		selected_unit = target.id
		message = "已选择「%s」。%s" % [target.name, _unit_status(target)]
		error_message = false
		_refresh()
		return
	if selected_unit != -1:
		_commit({"type": "move" if target.is_empty() else "attack", "unit_id": selected_unit, "target": cell})
	elif not target.is_empty():
		hovered_cell = cell
		_update_info()

func _commit(action: Dictionary) -> void:
	var result: Dictionary = _apply_with_feedback(action)
	error_message = not result.ok
	message = str(result.message)
	if result.ok:
		if action.type == "play": selected_card = -1
		if action.type == "hero": using_hero = false
		if action.type == "unit_skill": using_unit_skill = false
		if action.has("target") and battle.inside(action.target):
			board.last_cell = action.target
			board.flash(action.target)
	_refresh()

func _apply_with_feedback(action: Dictionary) -> Dictionary:
	var before: Array = battle.units.duplicate(true)
	var visual_action: Dictionary = action.duplicate()
	var side: int = battle.active_side
	if action.type == "hero":
		visual_action["effect_kind"] = battle.hero(side).effect
		visual_action["visual_origin"] = battle.commander(side).pos
	if action.type in ["attack", "unit_skill"]:
		var caster: Dictionary = battle.get_unit(int(action.get("unit_id", -1)))
		if not caster.is_empty():
			visual_action["unit_kind"] = caster.kind
			visual_action["visual_origin"] = caster.pos
			if action.type == "unit_skill": visual_action["effect_kind"] = {"mage": "damage", "healer": "heal", "sword": "shield"}.get(caster.kind, "")
			if action.type == "attack" or caster.kind == "archer":
				var target: Dictionary = battle.unit_at(action.target)
				if not target.is_empty(): visual_action["combat"] = battle.attack_forecast(caster, target, 1 if action.type == "unit_skill" else 0)
	if action.type == "play":
		var instance: Dictionary = battle.hand_card(battle.active_side, int(action.get("card_uid", -1)))
		if not instance.is_empty():
			visual_action["spell_effect"] = battle.definition(instance.card_id).get("effect", "")
			visual_action["effect_kind"] = visual_action.spell_effect
			var origin: Dictionary = {}
			for caster: Dictionary in battle.units:
				if caster.side != side or battle.distance(caster.pos, action.target) > battle.unit_cast_range(caster): continue
				if origin.is_empty() or battle.distance(caster.pos, action.target) < battle.distance(origin.pos, action.target): origin = caster
			if origin.is_empty(): origin = battle.commander(side)
			visual_action["visual_origin"] = origin.pos
	var path: Array[Vector2i] = []
	if action.type == "move" or (action.type == "unit_skill" and visual_action.get("unit_kind", "") == "cavalry"):
		var unit: Dictionary = battle.get_unit(int(action.get("unit_id", -1)))
		if not unit.is_empty(): path = battle.movement_path(unit, action.target)
	var result: Dictionary = battle.apply_action(action)
	if result.ok:
		board.present_action(before, visual_action, path)
		if battle.winner != -1: _refresh()
	return result

func _cancel() -> void:
	using_unit_skill = false
	selected_card = -1
	selected_unit = -1
	inspected_card = -1
	using_hero = false
	message = "选择手牌部署或施法；选择己方部队移动、攻击。"
	error_message = false
	_refresh()
	board.grab_focus()

func _inspect_card(uid: int) -> void:
	inspected_card = uid
	_update_info()

func attack_prediction(attacker: Dictionary, target: Dictionary) -> Dictionary:
	return battle.attack_forecast(attacker, target, 1 if using_unit_skill and attacker.kind == "archer" else 0)

func _effect_context() -> Dictionary:
	if not _player_can_act() or not battle.inside(hovered_cell): return {}
	var action: Dictionary = {"target": hovered_cell}
	if using_unit_skill:
		action.merge({"type": "unit_skill", "unit_id": selected_unit})
	elif using_hero: action["type"] = "hero"
	elif selected_card != -1: action.merge({"type": "play", "card_uid": selected_card})
	else: return {}
	return Effects.predict(battle, action)

func _attack_context() -> Dictionary:
	if selected_card != -1 or using_hero or not _player_can_act() or not board.attacks.has(hovered_cell): return {}
	var attacker: Dictionary = battle.get_unit(selected_unit)
	var target: Dictionary = battle.unit_at(hovered_cell)
	if attacker.is_empty() or target.is_empty(): return {}
	var prediction: Dictionary = attack_prediction(attacker, target)
	return {"attacker": attacker, "target": battle.get_unit(prediction.defender_id), "selected_target": target, "prediction": prediction}

func _update_attack_overlay() -> void:
	board.predicted_losses.clear()
	board.predicted_gains.clear()
	var effect: Dictionary = _effect_context()
	if not effect.is_empty():
		for change: Dictionary in effect.changes:
			if change.hp_loss > 0: board.predicted_losses[change.unit_id] = change.hp_loss
			if change.healing > 0 or change.shield_delta != 0: board.predicted_gains[change.unit_id] = {"heal": change.healing, "shield": change.shield_delta}
	var context: Dictionary = _attack_context()
	if not context.is_empty():
		board.predicted_losses = {context.attacker.id: context.prediction.attacker_loss, context.target.id: context.prediction.target_loss}
	board.queue_redraw()

func _attack_forecast_text(context: Dictionary) -> String:
	var attacker: Dictionary = context.attacker
	var target: Dictionary = context.target
	var prediction: Dictionary = context.prediction
	var breakdown: Dictionary = battle.damage_breakdown(attacker, target)
	var modifiers: Array[String] = []
	for key: String in ["advantage", "elevation", "charge", "armor", "terrain", "aura", "stance", "pierce", "close_penalty"]:
		if int(breakdown[key]) == 0: continue
		var labels: Dictionary = {"advantage": "克制 +", "elevation": "高地 +", "charge": "冲锋 +", "armor": "基础防御 ", "terrain": "地形防御 ", "aura": "光环防御 ", "stance": "枪阵防御 ", "pierce": "穿透 +", "close_penalty": "近战惩罚 −"}
		modifiers.append(str(labels[key]) + str(breakdown[key]))
	var lines: String = ""
	for index: int in range(modifiers.size()):
		lines += modifiers[index] + (" · " if index % 2 == 0 and index < modifiers.size() - 1 else "\n")
	if lines.is_empty(): lines = "无额外克制或地形修正。\n"
	if using_unit_skill and attacker.kind == "archer": lines += "精准射击 +1\n"
	if prediction.counter_damage > 0 and battle.ADVANTAGE.get(target.kind, "") == attacker.kind: lines += "反击克制 +2\n"
	if prediction.intercepted: lines = "%s援护%s，原目标不受伤。\n\n" % [target.name, context.selected_target.name] + lines
	var outcome: String = "目标存活并反击。"
	if prediction.target_loss >= target.hp: outcome = "目标被击破，不会反击。"
	elif battle.distance(attacker.pos, target.pos) > battle.attack_range(target): outcome = "目标射程不足，不会反击。"
	elif prediction.attacker_loss == 0: outcome = "反击未造成生命损失。"
	return "生命损失 %d  /  反击 %d\n\n目标生命  %d → %d\n我方生命  %d → %d\n\n%s\n已计入护盾：我方%d / 敌方%d\n%s\n点击目标确认攻击。" % [prediction.target_loss, prediction.attacker_loss, target.hp, target.hp - prediction.target_loss, attacker.hp, attacker.hp - prediction.attacker_loss, lines, attacker.shield, target.shield, outcome]

func _attack_hint(context: Dictionary) -> String:
	return ("援护拦截 · %s承伤。" % context.target.name if context.prediction.intercepted else "") + "攻击预览：敌方生命 %d → %d  /  我方生命 %d → %d  ·  浅金段为预计损失，点击目标确认。" % [context.target.hp, context.target.hp - context.prediction.target_loss, context.attacker.hp, context.attacker.hp - context.prediction.attacker_loss]

func _on_cell_hovered(cell: Vector2i) -> void:
	if is_queued_for_deletion() or not is_inside_tree(): return
	hovered_cell = cell
	_update_attack_overlay()
	_update_info()
	var unit: Dictionary = battle.get_unit(selected_unit)
	var target: Dictionary = battle.unit_at(cell)
	var context: Dictionary = _attack_context()
	var effect: Dictionary = _effect_context()
	if not effect.is_empty():
		_show_hint(Effects.hint(effect), false)
	elif not context.is_empty():
		_show_hint(_attack_hint(context), false)
	elif battle.inside(cell) and target.is_empty():
		var terrain_name: String = battle.TERRAIN[battle.ground(cell)].name
		var terrain_text: String = battle.TERRAIN[battle.ground(cell)].description
		if not unit.is_empty():
			terrain_text += " 当前部队进入费用 %s。" % (str(battle.movement_cost(unit, cell)) if battle.passable(cell) else "不可通行")
		_show_hint("%s · %s：%s" % [battle.cell_name(cell), terrain_name, terrain_text], false)
	else:
		_show_hint(message, error_message)

func _update_info() -> void:
	_update_battle_peek()
	var effect: Dictionary = _effect_context()
	if not effect.is_empty():
		info_title.text = "效果预估 · " + str(effect.title)
		info_body.text = Effects.describe(effect, battle)
		return
	if using_hero:
		var chosen: Dictionary = battle.hero(0)
		info_title.text = chosen.skill
		info_body.text = "[color=#d0b579]英雄主动 · %d 费 · 冷却 %d[/color]\n\n%s\n\n[color=#70d3ba]点击高亮目标施放，右键取消。[/color]" % [chosen.cost, chosen.cooldown, chosen.skill_text]
		return
	var uid: int = selected_card if selected_card != -1 else inspected_card
	var instance: Dictionary = battle.hand_card(0, uid)
	if not instance.is_empty():
		var card: Dictionary = battle.definition(instance.card_id)
		info_title.text = card.name
		info_body.text = "[color=#d0b579]%s  /  %d 法力[/color]\n\n%s\n\n" % [card.tag, card.cost, card.text]
		if card.type == "unit":
			info_body.text += "攻击 [b]%d[/b]     生命 [b]%d[/b]\n防御 %d       移动 %d\n射程 %d\n\n[color=#70d3ba]部署在友军上下左右的空地。新兵本回合无法行动。[/color]" % [card.atk, card.hp, card.defense, card.move, card.range]
			if card.has("skill"): info_body.text += "\n\n主动 · %s（1费）\n%s" % [card.skill.name, card.skill.text]
		else:
			info_body.text += "[color=#8eaaa4]%s\n右键或 Esc 可取消。[/color]" % ("全局牌：不需要选择棋盘目标。" if card.effect in ["draw", "mana", "weather", "clear_weather"] else "施法目标须在友军3格内，法师可延伸至4格。淡蓝为覆盖，赤框为合法目标。")
		return
	var context: Dictionary = _attack_context()
	if not context.is_empty():
		info_title.text = "攻击预估 · " + str(context.target.name)
		info_body.text = _attack_forecast_text(context)
		return
	var unit: Dictionary = battle.get_unit(selected_unit)
	if unit.is_empty(): unit = battle.unit_at(hovered_cell)
	if not unit.is_empty():
		info_title.text = unit.name
		var faction: String = "#70d3ba" if unit.side == 0 else "#f08b76"
		info_body.text = "[color=%s]%s / %s[/color]\n\n生命 [b]%d / %d[/b]   护盾 %d\n攻击 %d   基础防御 %d\n移动 %d   最终射程 %d\n\n%s\n\n[color=#d0b579]%s：地形防御 +%d[/color]\n光环防御 +%d\n[color=#8eaaa4]%s[/color]" % [faction, battle.side_name(unit.side), battle.cell_name(unit.pos), unit.hp, unit.max_hp, unit.shield, unit.atk, unit.defense, battle.movement_allowance(unit), battle.attack_range(unit), _unit_status(unit), battle.TERRAIN[battle.ground(unit.pos)].name, battle.terrain_defense(unit), battle.aura_defense(unit), battle.TERRAIN[battle.ground(unit.pos)].description]
		if not battle.unit_skill(unit).is_empty(): info_body.text += "\n\n主动 · %s（1费）\n%s" % [battle.unit_skill(unit).name, battle.unit_skill(unit).text]
		return
	var own_hero: Dictionary = battle.hero(0)
	info_title.text = own_hero.name
	info_body.text = "[color=#70d3ba]%s[/color]\n\n[color=#d0b579]被动 · %s[/color]\n%s\n\n[color=#d0b579]主动 · %s[/color]\n%s\n\n[color=#8eaaa4]步兵 → 枪兵 → 骑兵 → 步兵\n相邻友军就是部署支点。[/color]" % [own_hero.title, own_hero.passive, own_hero.passive_text, own_hero.skill, own_hero.skill_text]

func _position_battle_peek() -> void:
	if battle_peek == null: return
	var grid: Rect2 = board.grid_rect()
	var allowed: bool = expanded_battlefield and has_started and battle.winner == -1 and not council.visible and not %CardsDialog.visible and not %RulesDialog.visible and not deck_editor.visible and board.size.y >= 460.0
	for panel: BattlePeek in [battle_peek, battle_brief]:
		var left: bool = panel == battle_peek
		var available: float = grid.position.x - 42.0 if left else board.size.x - grid.end.x - 28.0
		panel.visible = allowed and available >= 200.0
		if not panel.visible: continue
		panel.portrait.custom_minimum_size.y = clampf(board.size.y * 0.22, 105, 175)
		panel.fit_width(minf(232.0, available))
		if panel.layout_settled() and panel.size.y > board.size.y - 32.0:
			panel.hide()
			continue
		panel.position = Vector2(12 if left else board.size.x - panel.size.x - 12, maxf(16, (board.size.y - panel.size.y) / 2))

func _update_battle_peek() -> void:
	if battle_peek == null: return
	var uid: int = selected_card if selected_card != -1 else inspected_card
	var instance: Dictionary = battle.hand_card(0, uid)
	if not instance.is_empty():
		var card: Dictionary = battle.definition(instance.card_id)
		var body: String = card.text
		if card.has("skill"): body += "\n\n主动 · %s（1费）\n%s" % [card.skill.name, card.skill.text]
		if card.type == "unit": body = "攻击%d  生命%d  防御%d\n移动%d  射程%d\n\n%s" % [card.atk, card.hp, card.defense, card.move, card.range, body]
		battle_peek.present(Art.get_texture(str(card.get("kind", card.id))), card.name, "%d 法力 · %s" % [card.cost, card.tag], body, TEAL if card.type == "unit" else GOLD, Art.card_focus(card))
	elif using_hero:
		var leader: Dictionary = battle.hero(0)
		battle_peek.present(Art.get_texture(leader.portrait), leader.skill, "%d 法力 · 冷却%d" % [leader.cost, leader.cooldown], leader.skill_text, GOLD)
	else:
		var unit: Dictionary = battle.unit_at(hovered_cell)
		if unit.is_empty(): unit = battle.get_unit(selected_unit)
		if unit.is_empty(): unit = battle.commander(0)
		if not unit.is_empty():
			var asset_id: String = battle.hero(unit.side).portrait if unit.kind == "commander" else str(unit.kind)
			var body: String = "生命%d/%d  护盾%d\n攻击%d  防御%d+地形%d\n移动%d  射程%d  施法%d\n\n%s" % [unit.hp, unit.max_hp, unit.shield, unit.atk, unit.defense, battle.terrain_defense(unit), battle.movement_allowance(unit), battle.attack_range(unit), battle.unit_cast_range(unit), _unit_status(unit)]
			if unit.kind == "commander": body += "\n\n" + str(battle.hero(unit.side).passive_text)
			elif not battle.unit_skill(unit).is_empty(): body += "\n\n主动 · %s（1费）\n%s" % [battle.unit_skill(unit).name, battle.unit_skill(unit).text]
			battle_peek.present(Art.get_texture(asset_id), unit.name, "%s · %s" % [battle.side_name(unit.side), battle.cell_name(unit.pos)], body, TEAL if unit.side == 0 else RED)
	var context: Dictionary = _attack_context()
	if not context.is_empty():
		var defender: Dictionary = context.target
		var prediction: Dictionary = context.prediction
		var asset: String = battle.hero(defender.side).portrait if defender.kind == "commander" else str(defender.kind)
		battle_peek.present(Art.get_texture(asset), defender.name, "攻击预估 · " + ("可击杀" if prediction.target_loss >= defender.hp else "目标将存活"), _attack_forecast_text(context), RED)
	var effect: Dictionary = _effect_context()
	if not effect.is_empty():
		var target: Dictionary = battle.get_unit(effect.target_id)
		var asset: String = battle.hero(target.side).portrait if target.kind == "commander" else str(target.kind)
		battle_peek.present(Art.get_texture(asset), effect.title, "效果预估 · " + str(target.name), Effects.describe(effect, battle, true), TEAL if target.side == 0 else RED)
	var enemy: Dictionary = battle.commander(1)
	if not enemy.is_empty():
		var enemy_hero: Dictionary = battle.hero(1)
		var enemy_player: Dictionary = battle.players[1]
		var weather_text: String = battle.WEATHER[battle.weather].name + (" · 剩余%d回合" % battle.weather_remaining if battle.weather_remaining > 0 else "")
		var body: String = "生命%d/%d  护盾%d\n法力%d/%d  部队%d/6\n手牌%d张  牌库%d张\n\n%s\n%s\n\n%s：%d费 · %s\n%s\n\n%s\n%s" % [enemy.hp, enemy.max_hp, enemy.shield, enemy_player.mana, enemy_player.max_mana, battle.army_count(1), enemy_player.hand.size(), enemy_player.deck.size(), weather_text, battle.WEATHER[battle.weather].description, enemy_hero.skill, enemy_hero.cost, "就绪" if enemy_player.skill_cooldown == 0 else "冷却%d" % enemy_player.skill_cooldown, enemy_hero.skill_text, enemy_hero.passive, enemy_hero.passive_text]
		battle_brief.present(Art.get_texture(enemy_hero.portrait), enemy.name, "敌方指挥官 · 公开战况", body, RED)
	_position_battle_peek()

func _unit_status(unit: Dictionary) -> String:
	if unit.get("guarding", false): return "援护中：保护上下左右相邻友军的普通攻击；定身时无法接应。" if int(unit.get("rooted_turns", 0)) == 0 else "援护受阻：定身中，无法接应。"
	if unit.summoning: return "新兵待命：下个己方回合恢复行动。"
	if int(unit.get("rooted_turns", 0)) > 0: return "已被定身：无法主动移动，仍可攻击或被换位。"
	if unit.side != battle.active_side: return "等待所属阵营的回合。"
	if unit.attacked: return "本回合已攻击，行动结束。"
	if unit.moved: return "已移动，仍可攻击射程内目标。"
	if unit.kind == "commander": return "固守阵地：不能主动移动，可攻击射程内目标。"
	return "可移动一次，并攻击一次。"

func _show_hint(value: String, is_error: bool) -> void:
	hint.text = value
	hint.add_theme_color_override("font_color", RED if is_error else Color("a1c4b6"))

func _end_turn() -> void:
	using_unit_skill = false
	if not _player_can_act(): return
	selected_card = -1
	selected_unit = -1
	inspected_card = -1
	ai_running = true
	using_hero = false
	_apply_with_feedback({"type": "end_turn"})
	message = "赤曜军团正在行动…"
	error_message = false
	_refresh()
	_run_ai(generation)

func _run_ai(token: int) -> void:
	await get_tree().create_timer(0.35).timeout
	var actions: int = 0
	while token == generation and battle.winner == -1 and battle.active_side == 1 and actions < 64:
		if council.visible or %CardsDialog.visible or %RulesDialog.visible or deck_editor.visible:
			await get_tree().create_timer(0.1).timeout
			continue
		var action: Dictionary = EnemyAI.choose(battle)
		var result: Dictionary = _apply_with_feedback(action)
		if not result.ok:
			push_error("AI action rejected: " + str(result.message))
			battle.end_turn()
			break
		if action.has("target") and battle.inside(action.target):
			board.last_cell = action.target
			board.flash(action.target)
		actions += 1
		if battle.winner != -1 or battle.active_side != 1: break
		await get_tree().create_timer(maxf(board.action_duration, 0.45 if action.type == "move" else 0.32)).timeout
	if token != generation: return
	if battle.winner == -1 and battle.active_side == 1: battle.end_turn()
	ai_running = false
	message = "你的回合：法力已恢复，选择卡牌或部队开始行动。"
	_refresh()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if council == null or council.visible or %RulesDialog.visible or %CardsDialog.visible or deck_editor.visible: return
	if event.keycode == KEY_TAB:
		_toggle_battlefield()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_G:
		grid_button.button_pressed = not grid_button.button_pressed
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Q:
		_select_unit_skill()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_HOME:
		board.fit_map()
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
		board.zoom_at(board.size / 2, 1.0 / 1.18 if event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] else 1.18)
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if council.visible: return
	if %RulesDialog.visible or %CardsDialog.visible or deck_editor.visible: return
	if event.keycode == KEY_ESCAPE:
		if battle.winner == -1: _cancel()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE:
		_end_turn()
		get_viewport().set_input_as_handled()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_8 and _player_can_act():
		var index: int = event.keycode - KEY_1
		if index < battle.players[0].hand.size(): _select_card(battle.players[0].hand[index].uid)
		get_viewport().set_input_as_handled()
