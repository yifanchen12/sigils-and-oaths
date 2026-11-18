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
		if battle.active_side == 0 and rule.call(battle, action): return action
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

func capture_lesson() -> void:
	game._open_council()
	game._start_training()
	game._load_training_lesson(1)
	var card: Dictionary = game.battle.players[0].hand[0]
	game._select_card(card.uid)
	game._update_clock_ui()
	await capture("04-guard-drill")
	game._leave_training()

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
	AudioServer.set_bus_mute(0, true)
	await process_frame
	await capture_campaign()
	await capture_skirmishes()
	await capture_lesson()
	await capture_relay()
	cleanup()
	print("STORE GAMEPLAY CAPTURE | FAILURES ", failures)
	quit(0 if failures == 0 else 1)
