extends SceneTree
## Native source/PCK verification over shipped resources; no test fixtures.
## Supply one existing absolute output directory after --.

const Scene = preload("res://scenes/main.tscn")
const Model = preload("res://scripts/battle.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Settings = preload("res://scripts/settings_store.gd")
const Campaign = preload("res://scripts/campaign_session.gd")
const DeckStore = preload("res://scripts/deck_store.gd")
const VISIBLE_ANCHORS := {
	"PlayerDeckAnchor": "own_deck", "PlayerDiscardAnchor": "own_discard",
	"EnemyDeckAnchor": "enemy_deck", "EnemyHandAnchor": "enemy_hand",
}
const FRAME_TIMES: Array[float] = [0.00, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00, 1.05, 1.10, 1.15, 1.20, 1.25, 1.30, 1.35, 1.40, 1.45, 1.50, 1.55, 1.60, 1.65, 1.70, 1.75, 1.80, 1.85, 1.90, 1.95, 2.00, 2.05]

var game: Control
var viewport: SubViewport
var output: String
var checks: int = 0
var failures: Array[String] = []
var screenshots: Array[Dictionary] = []
var opening_frames: Array[Dictionary] = []
var layout_records: Array[Dictionary] = []
var opening_events: Array[Dictionary] = []
var opening_state: String

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
	return condition

func state() -> String:
	return JSON.stringify(Snapshot.capture(game.battle), "", true, true)

func logical_canvas(physical: Vector2i) -> Vector2i:
	# Mirror the project's 1440x1000 canvas_items/expand window stretch.
	var aspect: float = float(physical.x) / float(physical.y)
	return Vector2i(roundi(1000.0 * aspect), 1000) if aspect >= 1.44 else Vector2i(1440, roundi(1440.0 / aspect))

func settle(frames: int = 6) -> void:
	for frame: int in frames:
		await process_frame
		game._sync_draw_anchors()
	game._position_battle_peek()

func freeze_visual_clock() -> void:
	game.set_process(false)
	game.draw_presentation.set_process(false)
	game.board.set_process(false)
	game.board.visual_time = 0.0
	game.board.reset_effects()
	game.board.hover_cell = Vector2i(-1, -1)
	game.board.last_cell = Vector2i(-1, -1)
	game.board.queue_redraw()
	game.audio.stop_playback()

func photograph(name: String) -> void:
	await settle(3)
	await RenderingServer.frame_post_draw
	var picture: Image = viewport.get_texture().get_image()
	var destination: String = output.path_join(name + ".png")
	var saved: bool = picture.save_png(destination) == OK
	check(picture.get_size() == viewport.size and saved, "native capture " + name)
	if saved:
		screenshots.append({"file": name + ".png", "width": picture.get_width(), "height": picture.get_height(), "sha256": FileAccess.get_sha256(destination)})

func enemy_private(label: String) -> void:
	var safe: bool = true
	var backs_only: bool = true
	for event: Dictionary in game.draw_presentation.events:
		if int(event.side) != 1: continue
		for key: String in event:
			if key not in ["side", "burned", "opening", "age", "duration"]: safe = false
		if game.draw_presentation.geometry(event).face: backs_only = false
	check(safe, label + ": enemy presentation holds no hidden identity")
	check(backs_only, label + ": enemy presentation renders only card backs")

func cards_inside(label: String) -> void:
	var visible: Rect2 = game.get_global_rect().grow(2.0)
	var enclosed: bool = true
	for event: Dictionary in game.draw_presentation.events:
		if float(event.age) < 0.0: continue
		var geometry: Dictionary = game.draw_presentation.geometry(event)
		var center: Vector2 = geometry.center + game.draw_presentation.global_position
		if not visible.encloses(Rect2(center - geometry.size * 0.5, geometry.size)): enclosed = false
	check(enclosed, label + ": drawing card rectangles stay inside the viewport")

func inspect_anchors(label: String) -> void:
	var visible: Rect2 = game.get_global_rect().grow(2.0)
	for node_name: String in VISIBLE_ANCHORS:
		var anchor: Control = game.get_node_or_null("%" + node_name) as Control
		if not check(anchor != null, label + ": anchor exists " + node_name): continue
		var rectangle: Rect2 = anchor.get_global_rect()
		check(anchor.is_visible_in_tree() and rectangle.size.x >= 8 and rectangle.size.y >= 8 and visible.encloses(rectangle), label + ": visible in-window pile " + node_name)
		var actual: Rect2 = game.draw_presentation.anchors[VISIBLE_ANCHORS[node_name]]
		check(actual.is_equal_approx(rectangle), label + ": animation uses actual pile " + node_name)
	# Enemy discard is intentionally a hidden fallback rather than a fifth HUD pile.
	var discard: Rect2 = game.draw_presentation.anchors.enemy_discard
	check(discard.size.x >= 8 and discard.size.y >= 8 and visible.encloses(discard), label + ": enemy discard fallback stays inside the viewport")
	var slots: Dictionary = game.draw_presentation.hand_slots
	check(slots.size() == game.battle.players[0].hand.size(), label + ": every real hand card has one destination")
	var valid_slots: bool = true
	for instance: Dictionary in game.battle.players[0].hand:
		var rectangle: Rect2 = slots.get(int(instance.uid), Rect2())
		if rectangle.size.x <= 0 or rectangle.size.y <= 0 or not visible.encloses(rectangle): valid_slots = false
	check(valid_slots, label + ": actual card UID destinations are visible and nonzero")

func exercise_opening() -> void:
	check(not game.draw_presentation.is_presenting(), "war council has no phantom opening draw")
	game.council.open("rivergate", "warden", false, "balanced", "balanced")
	game.council.start_button.pressed.emit()
	freeze_visual_clock()
	await settle()
	check(game.has_started and not game.council.visible, "normal start button enters the battlefield")
	check(game.battle.match_seed == 1 and game.battle.map_definition.id == "rivergate", "normal first skirmish uses deterministic rivergate seed")
	check(game.battle.deck(0).id == "balanced" and game.battle.deck(1).id == "balanced", "normal council applies both selected balanced decks")
	check(game.battle.players[0].hand.size() == 5 and game.battle.players[1].hand.size() == 6, "real resolved opening contains five own and six enemy cards")
	opening_events = game.draw_presentation.events.duplicate(true)
	check(opening_events.size() == 11, "eleven real opening cards create eleven presentation events")
	var own_uids: Dictionary = {}
	var enemy_count: int = 0
	var actual_own_cards: bool = true
	for event: Dictionary in opening_events:
		if int(event.side) == 1:
			enemy_count += 1
		else:
			if own_uids.has(int(event.uid)): actual_own_cards = false
			own_uids[int(event.uid)] = true
			var card: Dictionary = game.battle.hand_card(0, int(event.uid))
			if card.is_empty() or str(card.card_id) != str(event.card_id): actual_own_cards = false
	check(own_uids.size() == 5 and actual_own_cards, "own reveal events match distinct actual hand card identities")
	check(enemy_count == 6, "six enemy opening events remain hidden")
	enemy_private("opening")
	inspect_anchors("opening")
	opening_state = state()
	var previous: float = 0.0
	for index: int in FRAME_TIMES.size():
		var seconds: float = FRAME_TIMES[index]
		game.draw_presentation._process(seconds - previous)
		previous = seconds
		await settle(2)
		cards_inside("opening frame %02d" % index)
		check(state() == opening_state, "opening frame %02d preserves battle data, clock and RNG" % index)
		if index == 3:
			check(not game.draw_presentation.geometry(game.draw_presentation.events[0]).face, "own card first travels as a card back")
		if index == 7:
			var turning: Dictionary = game.draw_presentation.geometry(game.draw_presentation.events[0])
			check(float(turning.flip) < 0.75, "actual flip frame narrows the own card")
		if index == 10:
			check(game.draw_presentation.geometry(game.draw_presentation.events[0]).face, "own card reveals its actual face")
		var filename: String = "opening-%02d" % index
		await photograph(filename)
		opening_frames.append({"file": filename + ".png", "seconds": seconds, "pending_events": game.draw_presentation.events.size()})
	check(not game.draw_presentation.is_presenting(), "all opening cards settle without dealing again")
	check(game.battle.players[0].hand.size() == 5 and game.battle.players[1].hand.size() == 6, "settled hand counts remain five and six")
	await photograph("opening-settled")

func exercise_layouts() -> void:
	for dimensions: Vector2i in [Vector2i(1008, 700), Vector2i(1440, 1000), Vector2i(1920, 1080)]:
		viewport.size = dimensions
		viewport.size_2d_override = logical_canvas(dimensions)
		for expanded: bool in [true, false]:
			if bool(game.expanded_battlefield) != expanded: game._toggle_battlefield()
			await settle()
			var label: String = "%dx%d-%s" % [dimensions.x, dimensions.y, "expanded" if expanded else "standard"]
			inspect_anchors(label)
			# Rewind only the captured presentation, never the model or deck.
			game.draw_presentation.events = opening_events.duplicate(true)
			game.draw_presentation._process(0.56)
			await settle(2)
			cards_inside(label)
			enemy_private(label)
			check(state() == opening_state, label + ": resizing and replaying captured visuals preserve battle and RNG")
			await photograph("layout-" + label)
			layout_records.append({"pixels": [dimensions.x, dimensions.y], "logical_canvas": [viewport.size_2d_override.x, viewport.size_2d_override.y], "expanded": expanded, "hand_destinations": game.draw_presentation.hand_slots.size(), "visible_pile_anchors": VISIBLE_ANCHORS.size()})
			game.draw_presentation.reset()
	viewport.size = Vector2i(1920, 1080)
	viewport.size_2d_override = Vector2i(1778, 1000)
	if not game.expanded_battlefield: game._toggle_battlefield()
	await settle()

func exercise_real_turn_draws() -> void:
	game.draw_presentation.reset()
	check(game._apply_with_feedback({"type": "end_turn"}).ok, "legal player end turn resolves")
	freeze_visual_clock()
	await settle()
	check(game.draw_presentation.events.size() == 1 and game.draw_presentation.events[0].side == 1, "normal enemy turn draws one real hidden card")
	enemy_private("enemy turn")
	var enemy_state: String = state()
	game.draw_presentation._process(0.22)
	await photograph("enemy-hidden-draw")
	game.draw_presentation._process(2.0)
	check(state() == enemy_state, "enemy animation changes no battle data or RNG")
	check(game._apply_with_feedback({"type": "end_turn"}).ok, "legal enemy end turn resolves")
	freeze_visual_clock()
	await settle()
	check(game.draw_presentation.events.size() == 1 and game.draw_presentation.events[0].side == 0, "normal player turn draws one actual own card")
	var own_state: String = state()
	game.draw_presentation._process(0.56)
	await photograph("turn-draw-reveal")
	if not game.draw_presentation.events.is_empty():
		var uid: int = int(game.draw_presentation.events[0].uid)
		var instance: Dictionary = game.battle.hand_card(0, uid)
		var definition: Dictionary = game.battle.definition(instance.card_id)
		var immediate: bool = Model.is_global_card(definition) and int(definition.cost) <= int(game.battle.players[0].mana)
		var expected_state: String = own_state
		if immediate:
			# A payable global card is intentionally played on selection. Compare
			# with one legal model action, rather than demanding no state change.
			var restored: Dictionary = Snapshot.restore(JSON.parse_string(own_state))
			if check(restored.ok, "early global-card play has a valid independent baseline"):
				check(restored.battle.apply_action({"type": "play", "card_uid": uid, "target": Vector2i(-1, -1)}).ok, "early global-card baseline applies exactly one legal play")
				expected_state = JSON.stringify(Snapshot.capture(restored.battle), "", true, true)
		game._select_card(uid)
		check(not game.draw_presentation.pending(uid), "early interaction removes the consumed card presentation")
		if immediate:
			check(game.battle.hand_card(0, uid).is_empty(), "payable global card is actually played before animation ends")
		else:
			check(game.selected_card == uid, "targeted or unaffordable card can be selected before animation ends")
		check(state() == expected_state, "early interaction matches exactly the normal selection or single-play rule and RNG")
	game.draw_presentation.set_reduced_motion(true)
	check(game._apply_with_feedback({"type": "end_turn"}).ok, "reduced-motion enemy turn resolves normally")
	game.draw_presentation.reset()
	check(game._apply_with_feedback({"type": "end_turn"}).ok, "reduced-motion player turn resolves normally")
	freeze_visual_clock()
	await settle()
	var reduced_state: String = state()
	check(game.draw_presentation.events.size() == 1, "reduced motion preserves the actual draw event")
	game.draw_presentation._process(0.10)
	if not game.draw_presentation.events.is_empty():
		var event: Dictionary = game.draw_presentation.events[0]
		var target: Rect2 = game.draw_presentation.hand_slots[event.uid]
		check(float(event.duration) <= 0.22 and game.draw_presentation.geometry(event).center.is_equal_approx(target.get_center() - game.draw_presentation.global_position), "reduced motion is a short stationary arrival marker")
	await photograph("reduced-motion-arrival")
	game.draw_presentation._process(1.0)
	check(state() == reduced_state, "reduced-motion completion preserves battle and RNG")
	game.draw_presentation.set_reduced_motion(false)
	game._new_match(game.battle.match_seed, game.battle)
	await settle()
	check(not game.draw_presentation.is_presenting() and state() == reduced_state, "remounting a prepared battle does not replay or duplicate opening cards")

func finish() -> void:
	var report_file := FileAccess.open(output.path_join("draw-verification.json"), FileAccess.WRITE)
	check(report_file != null, "native verification report can be written")
	if report_file != null:
		report_file.store_string(JSON.stringify({
			"version": ProjectSettings.get_setting("application/config/version", ""),
			"scope": "Native draw presentation and HUD layout using normal council entry and legal turn actions. Layout samples replay only captured opening visuals.",
			"renderer": DisplayServer.get_name(), "checks": checks, "failures": failures.size(), "failure_labels": failures,
			"scenario": {"map": "rivergate", "opening_seed": 1, "own_deck": "balanced", "enemy_deck": "balanced", "own_opening_cards": 5, "enemy_opening_cards": 6},
			"opening_state_sha256": opening_state.sha256_text(), "opening_frames": opening_frames,
			"layouts": layout_records, "screenshots": screenshots,
		}, "\t") + "\n")
		report_file.close()
	print("DRAW PRESENTATION | ", checks, " checks | ", failures.size(), " failures")
	game.draw_presentation.reset()
	game.audio.stop_playback()
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or not DirAccess.dir_exists_absolute(args[0]) or DisplayServer.get_name() == "headless":
		push_error("Supply an existing absolute output directory and use a native renderer.")
		quit(2)
		return
	output = args[0]
	create_timer(90.0).timeout.connect(func() -> void: push_error("Native draw verification timed out"); quit(2))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.size_2d_override = Vector2i(1778, 1000)
	viewport.size_2d_override_stretch = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	game = Scene.instantiate()
	game.settings_store = Settings.new(output.path_join("preferences.cfg"))
	game.campaign_session = Campaign.new(output.path_join("campaign.json"))
	game.deck_store = DeckStore.new(output.path_join("deck.json"))
	check(game.settings_store.save_preferences({"music": 0, "effects": 0, "reduce_motion": false}).ok, "isolated deterministic presentation preferences")
	viewport.add_child(game)
	freeze_visual_clock()
	AudioServer.set_bus_mute(0, true)
	await settle()
	await exercise_opening()
	await exercise_layouts()
	await exercise_real_turn_draws()
	await finish()
