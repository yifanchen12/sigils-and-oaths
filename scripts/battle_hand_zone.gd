extends HBoxContainer
## A visible physical draw/discard area around the canonical card container.
## Children are not game state; main retains ownership of cards and all input.

const ThemeStyle = preload("res://scripts/game_theme.gd")
@export var compact: bool = false
var hand: HBoxContainer
var pending_layout: bool = false
var bound_battle: Battle

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand = get_node("CompactHand" if compact else "Hand") as HBoxContainer
	hand.child_entered_tree.connect(_children_changed)
	hand.child_exiting_tree.connect(_children_changed)
	hand.resized.connect(_schedule_layout)
	resized.connect(_schedule_layout)
	get_viewport().size_changed.connect(_schedule_layout)
	visibility_changed.connect(_schedule_layout)
	sort_children.connect(_schedule_layout)
	_schedule_layout()

func _children_changed(_child: Node) -> void:
	_schedule_layout()

func _schedule_layout() -> void:
	if pending_layout: return
	pending_layout = true
	call_deferred("_sync_layout")

func _sync_layout() -> void:
	pending_layout = false
	if not is_inside_tree(): return
	var battle: Battle = owner.get("battle") as Battle
	if bound_battle != battle:
		if bound_battle != null and bound_battle.changed.is_connected(_schedule_layout): bound_battle.changed.disconnect(_schedule_layout)
		bound_battle = battle
		if bound_battle != null: bound_battle.changed.connect(_schedule_layout)
	var count: int = hand.get_child_count()
	var gap: float = hand.get_theme_constant("separation")
	# A former wide-window card minimum can keep the HBox wider than its new
	# viewport. Derive the budget from the visible viewport too, so it can shrink.
	var viewport_width: float = get_viewport_rect().size.x
	var side_inset: float = maxf(0, global_position.x)
	var row_width: float = minf(size.x, viewport_width - side_inset * 2)
	var available: float = row_width - $DiscardPile.size.x - $DeckPile.size.x - get_theme_constant("separation") * 2
	var width: float = clampf(floorf((available - maxf(0, count - 1) * gap) / maxi(1, count)), 92, 178 if compact else 196)
	for child: Control in hand.get_children():
		if not child is CardView: continue
		if not is_equal_approx(child.custom_minimum_size.x, width): child.custom_minimum_size.x = width
		child.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if is_visible_in_tree():
		_update_anchor("PlayerDiscardAnchor", _pile_rect($DiscardPile))
		_update_anchor("PlayerDeckAnchor", _pile_rect($DeckPile))
	$DiscardPile.tooltip_text = "弃牌堆 · %d 张\n已使用、被弃置或溢出的卡牌。" % battle.players[0].discard.size() if battle != null else "弃牌堆"
	$DeckPile.tooltip_text = "牌库 · %d 张\n回合开始时从这里抽牌。空牌库将承受疲劳。" % battle.players[0].deck.size() if battle != null else "牌库"
	queue_redraw()

func _update_anchor(node_name: String, local_rect: Rect2) -> void:
	var anchor: Control = owner.get_node_or_null("%" + node_name) as Control
	if anchor == null: return
	anchor.global_position = global_position + local_rect.position
	anchor.size = local_rect.size

func _pile_rect(pile: Control) -> Rect2:
	var height: float = 64 if compact else 96
	var width: float = 44 if compact else 60
	return Rect2(pile.position + Vector2((pile.size.x - width) / 2, maxf(4, (pile.size.y - height - 30) / 2)), Vector2(width, height))

func _draw() -> void:
	if hand == null or not is_visible_in_tree(): return
	var battle: Battle = owner.get("battle") as Battle
	if battle == null: return
	var player: Dictionary = battle.players[0]
	_draw_pile(_pile_rect($DiscardPile), int(player.discard.size()), false)
	_draw_pile(_pile_rect($DeckPile), int(player.deck.size()), true)
	if hand.get_child_count() == 0:
		var font: Font = get_theme_default_font()
		draw_string(font, hand.position + Vector2(0, hand.size.y / 2 + 5), "手牌已空  ·  等待下一次抽牌", HORIZONTAL_ALIGNMENT_CENTER, hand.size.x, 14, ThemeStyle.MUTED)

func _draw_pile(rect: Rect2, count: int, deck: bool) -> void:
	var gold := Color("bca16e")
	var font: Font = get_theme_default_font()
	var base := ThemeStyle.box(Color("192d46") if deck else Color("111e30"), gold if count > 0 else Color("435268"), Vector2.ZERO, 4)
	for layer: int in range(2, -1, -1):
		base.draw(get_canvas_item(), Rect2(rect.position + Vector2(layer * 2, -layer * 2), rect.size))
	var inner: Rect2 = rect.grow(-6)
	draw_rect(inner, Color("52647a"), false, 1)
	var c := rect.get_center()
	var r: float = 13 if compact else 19
	var points := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.7, 0), c + Vector2(0, r), c + Vector2(-r * 0.7, 0), c + Vector2(0, -r)])
	draw_polyline(points, gold if deck else Color("65788e"), 1.3, true)
	if deck:
		draw_line(c - Vector2(0, r * 0.55), c + Vector2(0, r * 0.55), gold, 1)
	else:
		draw_line(c - Vector2(r * 0.45, 0), c + Vector2(r * 0.45, 0), Color("65788e"), 1)
	var label: String = ("牌库 " if deck else "弃牌 ") + str(count)
	var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(c.x - text_width / 2, rect.end.y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ThemeStyle.INK if deck else ThemeStyle.MUTED)
