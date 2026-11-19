extends SceneTree
## Capture actual game screens at the game's widescreen layout without resampling UI.

const MainScene = preload("res://scenes/main.tscn")
const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const Campaign = preload("res://scripts/campaign_session.gd")
const Preferences = preload("res://scripts/settings_store.gd")
const SIZE := Vector2i(1920, 1080)
const DIRECTORY = "res://docs/release/steam/gameplay"
const TEST_SAVE = "user://store-capture-v042.tmp.json"

var target_view: SubViewport
var game: Control
var failures: int = 0
var legal_prefix: int = 0

func _initialize() -> void:
	call_deferred("run")

func require(value: bool, description: String) -> bool:
	if value: return true
	failures += 1
	push_error(description)
	return false

func capture(stem: String) -> void:
	for frame: int in range(5):
		await process_frame
		game._position_battle_peek()
	await RenderingServer.frame_post_draw
	var frame_image: Image = target_view.get_texture().get_image()
	if not require(frame_image.get_size() == SIZE, "Actual viewport size differs from the delivery width"): return
	var file: String = ProjectSettings.globalize_path(DIRECTORY.path_join(stem + ".png"))
	if require(frame_image.save_png(file) == OK, "Could not save a gameplay image"): print("CAPTURE ", stem, " ", frame_image.get_size())

func reach_action(battle: Battle, rule: Callable) -> Dictionary:
	for action_index: int in range(600):
		if battle.winner != -1: break
		var action: Dictionary = AI.choose(battle)
		if battle.active_side == 0 and rule.call(battle, action):
			legal_prefix = action_index
			return action
		if not require(battle.apply_action(action).ok, "AI proposed an illegal move before capture"): return {}
		if action_index % 24 == 0: await process_frame
	return {}

func mount_battle(battle: Battle) -> void:
	game.story_view.hide()
	game.council.hide()
	game.has_started = true
	game._new_match(battle.match_seed, battle)
	if not game.expanded_battlefield: game._toggle_battlefield()
	game._update_clock_ui(false)

func capture_campaign() -> void:
	game._new_campaign()
	for page_index: int in range(45):
		var page: Dictionary = game.campaign_session.current()
		if page.get("speaker_id", "") == "warden" and game.story_view.illustration.visible:
			await capture("03-rivergate-story")
			print("CAPTURE STORY ", page.get("line_id", page.get("id", "warden")))
			return
		if page.get("type", "") != "dialogue": break
		game._advance_story(game.campaign_session.token())
	require(false, "Could not reach the illustrated opening dialogue")

func capture_skirmishes() -> void:
	var frost := Model.new(4107, "greenwood", "warden", "warden", "frost_engine", "balanced")
	var fire: Dictionary = await reach_action(frost, func(battle: Battle, action: Dictionary) -> bool:
		return action.type == "play" and battle.hand_card(0, action.card_uid).card_id == "last_hearth")
	if require(not fire.is_empty() and frost.players[0].mana == 10, "Expected ten-mana turn in an ordinary match"):
		mount_battle(frost)
		game._select_card(fire.card_uid)
		game.board.hover_cell = fire.target
		game._on_cell_hovered(fire.target)
		await capture("01-local-spell")
		print("CAPTURE SPELL TURN ", frost.turn)
	var river := Model.new(4186, "rivergate", "warden", "warden", "reed_legion", "balanced")
	var strike: Dictionary = await reach_action(river, func(battle: Battle, action: Dictionary) -> bool:
		return action.type == "attack" and battle.turn >= 12 and battle.units.size() >= 6)
	if require(not strike.is_empty(), "Expected a developed normal river battle"):
		mount_battle(river)
		game.selected_unit = strike.unit_id
		game._refresh()
		game.board.hover_cell = strike.target
		game._on_cell_hovered(strike.target)
		await capture("02-bridge-engagement")
		print("CAPTURE STRIKE TURN ", river.turn)

func capture_harbor() -> void:
	for seed_value: int in [5501,5502,5503,5504,5505]:
		var harbor := Model.new(seed_value, "harbor", "warden", "warden", "reed_legion", "balanced")
		var strike: Dictionary = await reach_action(harbor, func(model: Battle, action: Dictionary) -> bool:
			if action.type != "attack" or model.turn < 8 or model.units.size() < 6: return false
			return model.ground(model.get_unit(action.unit_id).pos) == "bridge" or model.ground(action.target) == "bridge")
		if strike.is_empty(): continue
		mount_battle(harbor)
		game.selected_unit = strike.unit_id
		game._refresh()
		game.board.hover_cell = strike.target
		game._on_cell_hovered(strike.target)
		if not require(not game._attack_context().is_empty(), "Harbor basic attack preview opens on the actual bridge"): return
		await capture("08-harbor-crossing")
		print("HARBOR CAPTURE seed ", seed_value, " turn ", harbor.turn, " legal prefix ", legal_prefix,
			" attacker ", harbor.get_unit(strike.unit_id).kind, " ", harbor.get_unit(strike.unit_id).pos,
			" target ", harbor.unit_at(strike.target).kind, " ", strike.target)
		return
	require(false, "Could not reach an ordinary Harbor bridge engagement")

func capture_lesson() -> void:
	game._open_council()
	game._start_training()
	game._load_training_lesson(1)
	var card: Dictionary = game.battle.players[0].hand[0]
	game._select_card(card.uid)
	game._update_clock_ui()
	await capture("04-guard-drill")
	game._leave_training()

func capture_highlands() -> void:
	var shots := {"ridgepass": "09-ridgepass", "sunspire": "10-sunspire", "citadel": "11-citadel"}
	for map_id: String in shots:
		var found := false
		for seed_value: int in [56037, 56377, 56102, 56103]:
			var deck := "glassroad_edict" if map_id == "citadel" else "reed_legion"
			var battle := Model.new(seed_value, map_id, "warden", "warden", deck, "balanced")
			var action: Dictionary = await reach_action(battle, func(model: Battle, candidate: Dictionary) -> bool:
				if model.turn < 7 or model.units.size() < 6: return false
				if map_id == "citadel":
					return candidate.type == "play" and model.hand_card(0,candidate.card_uid).card_id == "anchor_snare"
				if candidate.type != "attack": return false
				var attacker: Vector2i = model.get_unit(candidate.unit_id).pos
				if map_id == "sunspire":
					return model.ground(attacker) in ["hill","fort","ruins"] or model.ground(candidate.target) in ["hill","fort","ruins"]
				for direction: Vector2i in model.DIRECTIONS:
					for cell: Vector2i in [attacker + direction, Vector2i(candidate.target) + direction]:
						if model.inside(cell) and model.ground(cell) == "mountain": return true
				return false)
			if action.is_empty(): continue
			mount_battle(battle)
			if action.type == "play": game._select_card(action.card_uid)
			else:
				game.selected_unit = action.unit_id
				game._refresh()
			game.board.hover_cell = action.target
			game._on_cell_hovered(action.target)
			var aimed: bool = game.selected_card == action.card_uid and game.board.spell_targets.has(action.target) if action.type == "play" else not game._attack_context().is_empty()
			if not require(aimed, "capture shows the legal target on " + map_id): return
			await capture(shots[map_id])
			print("HIGHLANDS CAPTURE ", map_id, " seed ", seed_value, " turn ", battle.turn, " legal prefix ", legal_prefix,
				" action ", action.type, " target ", action.target)
			found = true
			break
		require(found, "found a real tactical position on " + map_id)

func capture_relay() -> void:
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign.json"))
	var stage: Dictionary = index.scenarios.c17_runner
	var battle := Model.new(stage.seed, stage.map, stage.hero, stage.enemy_class, stage.deck, stage.enemy_deck)
	battle.set_commander_identity(1, stage.enemy_name, stage.enemy_portrait)
	if not require(battle.configure_objective(stage.control).ok and battle.add_generated_card(0, stage.bonus_card), "Could not construct the authored campaign mission"): return
	mount_battle(battle)
	await capture("05-three-lamps-mission")

func cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEST_SAVE + suffix): DirAccess.remove_absolute(TEST_SAVE + suffix)

func film_position(map_id: String, deck: String, id: String) -> Dictionary:
	for seed_value: int in [56037, 56377, 56102]:
		var hero := "pyromancer" if id == "firestrike" else "warden"
		var battle := Model.new(seed_value,map_id,hero,"warden",deck,"balanced")
		for step: int in range(520):
			if battle.winner != -1: break
			if battle.active_side == 0 and battle.turn >= 5 and battle.units.size() >= 5:
				for action: Dictionary in battle.get_legal_actions(0):
					var matched: bool = action.type == "play" and battle.hand_card(0,action.card_uid).card_id == id
					if matched and id == "glass_treaty": matched = battle.unit_at(action.target).get("side",-1) == 1
					if id == "firestrike": matched = action.type == "hero"
					if action.type == "unit_skill" and battle.get_unit(action.unit_id).kind == id:
						matched = id != "spear" or battle.units.any(func(unit: Dictionary) -> bool:
							return unit.side == 0 and battle.distance(unit.pos,action.target) == 1)
					if matched: return {"battle":battle,"action":action,"prefix":step}
			if not require(battle.apply_action(AI.choose(battle)).ok, "legal film prefix"): return {}
			if step % 24 == 0: await process_frame
	return {}

func capture_cast_frames(directory: String) -> void:
	if not require(DirAccess.dir_exists_absolute(directory), "an existing capture directory is required"): return
	var shots := [["ridgepass","balanced","bolt"], ["sunspire","balanced","healer"],
		["citadel","reed_legion","spear"], ["citadel","glassroad_edict","anchor_snare"],
		["sunspire","balanced","firestrike"], ["harbor","balanced","rain"], ["rivergate","glassroad_edict","glass_treaty"]]
	var frame_index := 0
	for shot: Array in shots:
		var position: Dictionary = await film_position(shot[0],shot[1],shot[2])
		if not require(not position.is_empty(), "legal cast available for " + str(shot[2])): return
		var battle: Battle = position.battle
		var action: Dictionary = position.action
		mount_battle(battle)
		game.set_process(false)
		game.board.set_process(false)
		var global_card: bool = action.type == "play" and not battle.inside(action.target)
		var focus: Vector2i = battle.commander(0).pos if global_card else action.target
		if global_card: game._inspect_card(action.card_uid)
		elif action.type == "play": game._select_card(action.card_uid)
		elif action.type == "hero":
			game.using_hero = true
			game._refresh()
		else:
			game.selected_unit = action.unit_id
			game.using_unit_skill = true
			game._refresh()
		await process_frame
		game.board.fit_map()
		if not global_card:
			game.board.zoom_at(game.board.cell_center(focus), 1.45)
			game.board.reveal_cell(focus)
			game.board.hover_cell = focus
			game._on_cell_hovered(focus)
		for f: int in range(36):
			if f == 8:
				if global_card: game._select_card(action.card_uid)
				else: game._commit(action)
				if not require(not game.error_message and game.board.is_presenting(),"cast accepted through the battle UI"): return
				game.board.hover_cell = Vector2i(-1,-1)
			if f > 8: game.board._process(1.0/24.0)
			game.board.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var frame: Image = target_view.get_texture().get_image()
			if not require(frame.save_png(directory.path_join("cast-%04d.png" % frame_index)) == OK,"write actual game frame"): return
			if shot[2] == "bolt" and f == 20:
				if not require(frame.save_png(ProjectSettings.globalize_path(DIRECTORY.path_join("12-cast-impact.png"))) == OK,"write spell impact screenshot"): return
			frame_index += 1
		game.board.set_process(true)
		print("CAST FILM ", shot[2], " map ", shot[0], " seed ", battle.match_seed, " preceding legal actions ",
			position.prefix, " turn ", battle.turn, " target ", action.target)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A native renderer is required for gameplay screenshots")
		quit(2)
		return
	cleanup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	target_view = SubViewport.new()
	target_view.size = SIZE
	target_view.size_2d_override = Vector2i(1778, 1000)
	target_view.size_2d_override_stretch = true
	target_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target_view)
	game = MainScene.instantiate()
	game.campaign_session = Campaign.new(TEST_SAVE)
	game.settings_store = Preferences.new("user://store-capture-defaults.cfg")
	target_view.add_child(game)
	game.set_process(false)
	game.audio.stop_playback()
	AudioServer.set_bus_mute(0, true)
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--cast-frames":
		await capture_cast_frames(args[1])
	elif args.has("--highlands"):
		await capture_highlands()
	else:
		var skirmishes_only := OS.get_cmdline_user_args().has("--skirmishes")
		if not skirmishes_only: await capture_campaign()
		await capture_skirmishes()
		await capture_harbor()
		await capture_highlands()
		if not skirmishes_only:
			await capture_lesson()
			await capture_relay()
	cleanup()
	print("STORE GAMEPLAY CAPTURE | FAILURES ", failures)
	game.audio.stop_playback()
	await create_timer(0.15, true, false, true).timeout
	target_view.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
