extends SceneTree
## Captures the actual battlefield reached by replaying released skirmishes.

const MainScene = preload("res://scenes/main.tscn")
const Opponent = preload("res://scripts/opponent.gd")
const Settings = preload("res://scripts/settings_store.gd")
const SIZE := Vector2i(1920, 1080)
const REPORT := "res://docs/glassroad-playtest-v053.json"
const SHOTS: Array[Dictionary] = [
	{"card": "all_banner_call", "deck": "glassroad_reserve", "minimum": 2, "name": "06-glassroad-muster.png"},
	{"card": "glass_treaty", "deck": "glassroad_edict", "minimum": 2, "name": "07-glassroad-dual-order.png"},
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.size() != 1 or not DirAccess.dir_exists_absolute(args[0]):
		push_error("Use the Windows display backend and pass a writable output folder.")
		quit(1)
		return
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	if not report is Dictionary or not report.has("final_matches"):
		push_error("Skirmish replay data is missing.")
		quit(1)
		return
	var matches: Array = report.final_matches.duplicate()
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.actions < b.actions)
	var game: Control = MainScene.instantiate()
	game.settings_store = Settings.new(args[0].path_join("capture-preferences.cfg"))
	game.deck_store = DeckStore.new(args[0].path_join("capture-deck.json"))
	root.size = SIZE
	root.content_scale_size = SIZE
	root.add_child(game)
	current_scene = game
	for shot: Dictionary in SHOTS:
		var position: Dictionary = find_position(matches, shot)
		if position.is_empty():
			push_error("No legal replay position for " + shot.name)
			quit(1)
			return
		if not await capture(game, position, shot, args[0]):
			quit(1)
			return
	game.queue_free()
	await process_frame
	quit(0)

func find_position(matches: Array, shot: Dictionary) -> Dictionary:
	for record: Dictionary in matches:
		if record.blue != shot.deck or not record.plays.has(shot.card): continue
		var battle := Battle.new(int(record.seed), record.map, "warden", "warden", record.blue, record.red)
		for step: int in range(int(record.actions)):
			if battle.winner != -1: break
			if battle.active_side == 0 and int(battle.players[0].mana) >= 10:
				for instance: Dictionary in battle.players[0].hand:
					if instance.card_id != shot.card: continue
					var targets: Array[Vector2i] = battle.card_targets(int(instance.uid), 0)
					if shot.card == "all_banner_call":
						var front: Vector2i = battle.commander(1).pos
						targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return battle.distance(a, front) < battle.distance(b, front))
					for cell: Vector2i in targets:
						var action: Dictionary = {"type": "play", "card_uid": instance.uid, "target": cell}
						if visible_effects(battle, action, shot) >= int(shot.minimum):
							return {"battle": battle, "action": action, "prefix": step, "seed": int(record.seed)}
			if not battle.apply_action(Opponent.choose(battle)).ok: break
	return {}

func visible_effects(battle: Battle, action: Dictionary, shot: Dictionary) -> int:
	var card: Dictionary = battle.definition(shot.card)
	if card.effect == "muster": return battle.muster_plan(card, action.target, 0).size()
	var mode: Dictionary = battle.choice_mode(card, action.target, 0)
	if mode.target_side != "enemy": return 0
	return battle.Formation.changes(battle, mode, action.target, 0).size()

func capture(game: Control, position: Dictionary, shot: Dictionary, destination: String) -> bool:
	var battle: Battle = position.battle
	var action: Dictionary = position.action
	game._start_from_council(battle.map_definition.id, battle.hero(0).id, battle.deck(0).id, battle.deck(1).id)
	game._new_match(position.seed, battle)
	for frame: int in range(4): await process_frame
	game._select_card(action.card_uid)
	game._on_cell_hovered(action.target)
	for frame: int in range(4): await process_frame
	var preview: Dictionary = game._effect_context()
	if preview.is_empty() or preview.title != battle.definition(shot.card).name:
		push_error("The game did not show the preview for " + shot.card)
		return false
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.get_size() != SIZE or image.save_png(destination.path_join(shot.name)) != OK:
		push_error("Screenshot could not be stored at the required size. Rendered %s." % str(image.get_size()))
		return false
	print("STORE SCREEN ", shot.name, " | seed ", position.seed, " | map ", battle.map_definition.id,
		" | ", battle.deck(0).id, " vs ", battle.deck(1).id, " | turn ", battle.turn, " | legal prefix ", position.prefix,
		" | affected ", visible_effects(battle, action, shot))
	return true
