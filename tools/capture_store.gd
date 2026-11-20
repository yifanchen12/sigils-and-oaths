extends SceneTree
## Capture actual game screens at the game's widescreen layout without resampling UI.

const MainScene = preload("res://scenes/main.tscn")
const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const Campaign = preload("res://scripts/campaign_session.gd")
const CastArt = preload("res://scripts/cast_art.gd")
const Preferences = preload("res://scripts/settings_store.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Course = preload("res://scripts/training.gd")
const SIZE := Vector2i(1920, 1080)
const DIRECTORY = "res://docs/release/steam/gameplay"
const TEST_SAVE = "user://store-capture-v042.tmp.json"

var target_view: SubViewport
var game: Control
var failures: int = 0
var legal_prefix: int = 0
var filming_frame := 0

func _initialize() -> void:
	call_deferred("run")

func require(value: bool, description: String) -> bool:
	if value: return true
	failures += 1
	push_error(description)
	return false

func capture(stem: String, output_file: String = "") -> void:
	for frame: int in range(5):
		await process_frame
		game._position_battle_peek()
	await RenderingServer.frame_post_draw
	var frame_image: Image = target_view.get_texture().get_image()
	if not require(frame_image.get_size() == SIZE, "Actual viewport size differs from the delivery width"): return
	var file: String = ProjectSettings.globalize_path(DIRECTORY.path_join(stem + ".png")) if output_file.is_empty() else output_file
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
	for path: String in [TEST_SAVE,Campaign.replay_path(TEST_SAVE)]:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)

func film_position(map_id: String, deck: String, id: String) -> Dictionary:
	if id in ["trigger_step", "trigger_counter"]: return await trap_film_position(map_id, deck, id == "trigger_step")
	if id == "hammer_due":
		var placement := await film_position(map_id,deck,"hollow_hammer")
		return placement.get("followup",{})
	for seed_value: int in [56037, 56377, 56102]:
		var hero: String = {"firestrike":"pyromancer", "renewal":"grove"}.get(id, "warden")
		var battle := Model.new(seed_value,map_id,hero,"warden",deck,"balanced")
		for step: int in range(520):
			if battle.winner != -1: break
			if battle.active_side == 0 and battle.turn >= 5 and battle.units.size() >= 5:
				for action: Dictionary in battle.get_legal_actions(0):
					var matched: bool = action.type == "play" and not CastArt.SKILLS.has(id) and battle.hand_card(0,action.card_uid).card_id == id
					if matched and id == "glass_treaty": matched = battle.unit_at(action.target).get("side",-1) == 1
					if matched and id == "nova":
						matched = battle.units.filter(func(enemy: Dictionary) -> bool: return enemy.side == 1 and battle.distance(enemy.pos,action.target) <= 1).size() >= 2
					if matched and id == "hollow_hammer":
						if battle.unit_at(action.target).get("side",-1) != 1: continue
						var next := hammer_reply(battle,action,step)
						if not next.is_empty(): return {"battle":battle,"action":action,"prefix":step,"followup":next}
						continue
					if id in ["blessing", "firestrike", "renewal"]:
						matched = action.type == "hero"
						if matched and id == "blessing": matched = action.target != battle.commander(0).pos
						if matched and id == "renewal":
							matched = battle.units.any(func(ally: Dictionary) -> bool:
								return ally.side == 0 and ally.kind != "commander" and ally.hp < ally.max_hp and battle.distance(battle.commander(0).pos, ally.pos) <= battle.hero_cast_range(0))
					if matched and id == "gate_veteran":
						matched = battle.units.any(func(ally: Dictionary) -> bool: return ally.side == 0 and ally.kind != "commander" and battle.distance(ally.pos, action.target) == 1)
					if action.type == "unit_skill" and battle.get_unit(action.unit_id).kind == id:
						matched = id != "spear" or battle.units.any(func(unit: Dictionary) -> bool:
							return unit.side == 0 and battle.distance(unit.pos,action.target) == 1)
						if id == "cavalry":
							var path := battle.movement_path(battle.get_unit(action.unit_id),action.target)
							matched = path.size() == 3 and path[1]-path[0] != path[2]-path[1]
					if matched: return {"battle":battle,"action":action,"prefix":step}
			if not require(battle.apply_action(AI.choose(battle)).ok, "legal film prefix"): return {}
			if step % 24 == 0: await process_frame
	return {}

func hammer_reply(battle: Battle, cast: Dictionary, prefix: int) -> Dictionary:
	var replay: Battle = Snapshot.restore(Snapshot.capture(battle)).battle
	if not require(replay.apply_action(cast).ok and replay.end_turn().ok,"end the turn after marking the actual hammer"): return {}
	for steps: int in range(65):
		if replay.winner != -1: return {}
		var next := AI.choose(replay)
		var before: Dictionary = Snapshot.capture(replay) if next.type == "end_turn" else {}
		if not require(replay.apply_action(next).ok,"the opponent plays its normal reply to the field order"): return {}
		if not before.is_empty():
			if replay.last_order_event.get("impacts",[]).is_empty() or replay.winner != -1: return {}
			return {"battle":Snapshot.restore(before).battle,"action":next,"prefix":prefix+2+steps,"order_cell":cast.target}
	return {}

func trap_film_position(map_id: String, deck: String, step_trap: bool) -> Dictionary:
	for seed_value: int in [57023, 56037, 56377, 57107, 57139]:
		var battle := Model.new(seed_value,map_id,"warden","warden",deck,"ambush")
		for step: int in range(650):
			if battle.winner != -1: break
			var side := battle.active_side
			var action: Dictionary = AI.choose(battle)
			if not require(battle.apply_action(action).ok,"legal trap replay prefix"): return {}
			if side != 0 or action.type != ("move" if step_trap else "attack"): continue
			for event: Dictionary in battle.last_trap_events:
				if not event.triggered or event.side != 1 or (event.trigger == "step") != step_trap: continue
				var before := Model.new(seed_value,map_id,"warden","warden",deck,"ambush")
				for i: int in range(step):
					if not require(before.apply_action(AI.choose(before)).ok,"rebuild the actual pre-trigger board"): return {}
				return {"battle":before, "action":action, "prefix":step, "revealed_cell":event.cell}
		await process_frame
	return {}

func capture_cast_frames(directory: String, series: String) -> void:
	if not require(DirAccess.dir_exists_absolute(directory), "an existing capture directory is required"): return
	var shots := [["ridgepass","balanced","bolt"], ["sunspire","balanced","healer"],
		["citadel","reed_legion","spear"], ["citadel","glassroad_edict","anchor_snare"],
		["sunspire","balanced","firestrike"], ["harbor","balanced","rain"], ["rivergate","glassroad_edict","glass_treaty"]]
	if series == "--signature-frames":
		shots = [["rivergate","frost_engine","gate_veteran"], ["sunspire","balanced","firestrike"],
			["ridgepass","balanced","blessing"], ["greenwood","balanced","renewal"],
			["citadel","ambush","anchor_snare"], ["harbor","ambush","oath_ward"],
			["rivergate","reed_legion","trigger_step"], ["citadel","balanced","trigger_counter"]]
	elif series == "--field-frames":
		shots = [["ridgepass","balanced","sword"], ["rivergate","assault","cavalry"], ["sunspire","balanced","archer"],
			["citadel","balanced","mage"], ["greenwood","balanced","healer"], ["harbor","glassroad_edict","frostbind"],
			["ridgepass","balanced","bolt"]]
	elif series == "--sky-frames":
		shots = [["sunspire","balanced","nova"], ["harbor","balanced","rain"], ["ridgepass","balanced","snow"],
			["sunspire","balanced","sun"], ["rivergate","balanced","fog"], ["greenwood","reed_legion","open_wind"],
			["citadel","lantern_convoy","night_muster"], ["rivergate","frost_engine","clear_skies"],
			["harbor","levee_relief","dike_flagstones"], ["citadel","glassroad_edict","hollow_hammer"],
			["citadel","glassroad_edict","hammer_due"], ["rivergate","reed_legion","trigger_step"], ["sunspire","balanced","firestrike"]]
	var record_sound := series in ["--field-frames","--sky-frames"]
	var soundtrack: Array[Dictionary] = []
	if record_sound:
		game.audio.cue_started.connect(func(cue: String) -> void:
			soundtrack.append({"sound":game.audio.CUES[cue].resource_path.get_file(), "frame":filming_frame}))
	var frame_index := 0
	var recorded: Array[Dictionary] = []
	for shot: Array in shots:
		var position: Dictionary = await film_position(shot[0],shot[1],shot[2])
		if not require(not position.is_empty(), "legal cast available for " + str(shot[2])): return
		var battle: Battle = position.battle
		var action: Dictionary = position.action
		mount_battle(battle)
		game.set_process(false)
		game.board.set_process(false)
		if record_sound:
			game.audio.stopping = false
			game.audio.set_levels(0,100)
		var global_card: bool = action.type == "play" and not battle.inside(action.target)
		var untargeted_hero: bool = action.type == "hero" and not battle.inside(action.target)
		var self_skill: bool = action.type == "unit_skill" and battle.get_unit(action.unit_id).kind in ["sword","spear"]
		var due: bool = position.has("order_cell")
		var focus: Vector2i = position.order_cell if due else (battle.commander(0).pos if global_card or untargeted_hero else action.target)
		if due: pass
		elif global_card: game._inspect_card(action.card_uid)
		elif action.type == "play": game._select_card(action.card_uid)
		elif action.type == "hero":
			if not untargeted_hero: game._select_hero_skill()
		else:
			game._on_cell_clicked(battle.get_unit(action.unit_id).pos,MOUSE_BUTTON_LEFT)
			if action.type == "unit_skill" and not self_skill: game._select_unit_skill()
		await process_frame
		game.board.fit_map()
		if not global_card:
			game.board.zoom_at(game.board.cell_center(focus), 1.45)
			game.board.reveal_cell(focus)
			game.board.hover_cell = focus
			game._on_cell_hovered(focus)
		for f: int in range(36):
			filming_frame = frame_index
			if f == 8:
				if due:
					if not require(game._apply_with_feedback(action).ok and battle.last_order_event.get("card_id") == "hollow_hammer","turn change resolves the same player's marked order"): return
					game._refresh()
				elif global_card: game._select_card(action.card_uid)
				elif untargeted_hero: game._select_hero_skill()
				elif self_skill: game._select_unit_skill()
				else: game._on_cell_clicked(action.target,MOUSE_BUTTON_LEFT)
				if not require(not game.error_message and game.board.is_presenting(),"cast accepted through the battle UI"): return
				if series == "--field-frames":
					if not require(game.board.effects.any(func(effect: Dictionary) -> bool:
						return effect.get("stroke",-1) >= 0 and (effect.get("rider",-1) == action.unit_id if action.type == "unit_skill" else effect.get("cost",-1) >= 0)), "the filmed action actually displays its declared stroke"): return
				if record_sound:
					var sounds: Array = game.audio.sfx.get_children().filter(func(node: Node) -> bool: return node.playing)
					if not require(not sounds.is_empty(),"native audio starts at the filmed input"): return
					var event: Dictionary = {}
					for cue: Dictionary in game.board.effects:
						if CastArt.STYLES.has(cue.kind): event = cue
					if not require(not event.is_empty(),"the recorded input generates a board effect"): return
					recorded.append({"id":shot[2], "type":action.type, "map":shot[0], "seed":battle.match_seed,
						"preceding_actions":position.prefix, "turn":battle.turn, "target":battle.cell_name(event.cell),
						"effect":event.kind,"weather":battle.weather,"footprint":event.cells.size(),"impacts":event.get("struck",[]).size(),
						"sound":sounds.back().stream.resource_path.get_file(), "sound_frame":frame_index})
				if position.has("revealed_cell") and not require(battle.last_trap_events.any(func(event: Dictionary) -> bool:
					return event.triggered and event.cell == position.revealed_cell), "live UI reveals the replayed trap"): return
				game.board.hover_cell = Vector2i(-1,-1)
				if game.board.motion_tween != null: game.board.motion_tween.pause()
			if f > 8:
				game.board._process(1.0/24.0)
				if game.board.motion_tween != null and game.board.motion_tween.is_valid():
					game.board.motion_tween.custom_step(1.0/24.0)
			game.board.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var frame: Image = target_view.get_texture().get_image()
			if not require(frame.save_png(directory.path_join("cast-%04d.png" % frame_index)) == OK,"write actual game frame"): return
			if series == "--cast-frames" and shot[2] == "bolt" and f == 20:
				if not require(frame.save_png(ProjectSettings.globalize_path(DIRECTORY.path_join("12-cast-impact.png"))) == OK,"write spell impact screenshot"): return
			frame_index += 1
		game.board.set_process(true)
		print("CAST FILM ", shot[2], " action ",action.type, " map ", shot[0], " seed ", battle.match_seed, " preceding legal actions ",
			position.prefix, " turn ", battle.turn, " target ", focus)
	if record_sound:
		var manifest := FileAccess.open(directory.path_join("shots.json"), FileAccess.WRITE)
		if not require(manifest != null, "open reel metadata"): return
		manifest.store_string(JSON.stringify({"fps":24,"frames":frame_index,"shots":recorded,"cues":soundtrack,"full_board":series == "--sky-frames"},"\t"))
		manifest.close()

func select_drill_card(id: String) -> bool:
	for card: Dictionary in game.battle.players[0].hand:
		if card.card_id == id:
			game._select_card(card.uid)
			return require(game.selected_card == card.uid, "selected the real hand card " + id)
	return require(false, "missing hand card " + id)

func record_drill_frame(directory: String, screenshot: String = "") -> void:
	var board: Control = game.board
	game._position_battle_peek()
	board._process(1.0/24.0)
	if board.motion_tween != null and board.motion_tween.is_valid():
		board.motion_tween.pause()
		board.motion_tween.custom_step(1.0/24.0)
	board.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = target_view.get_texture().get_image()
	require(frame.save_png(directory.path_join("cast-%04d.png" % filming_frame)) == OK, "write the drill frame")
	if not screenshot.is_empty():
		require(frame.save_png(directory.path_join(screenshot+".png")) == OK, "write the native drill screenshot")
	filming_frame += 1

func capture_order_drill(directory: String) -> void:
	if not require(DirAccess.dir_exists_absolute(directory), "supply an existing output directory"): return
	var cues: Array[Dictionary] = []
	game.audio.stopping = false
	game.audio.set_levels(55,70)
	game.audio.cue_started.connect(func(cue: String) -> void:
		cues.append({"sound":game.audio.CUES[cue].resource_path.get_file(), "frame":filming_frame}))
	game.board.set_process(false)
	for i: int in range(72): await record_drill_frame(directory)
	game.council.training_button.pressed.emit()
	game.training_panel.lesson_choice.select(4)
	game.training_panel.lesson_choice.item_selected.emit(4)
	var outcomes: Array[Dictionary] = []
	for choice: int in range(Course.SNARE_SITES.size()):
		if choice > 0: game.training_panel.reset_button.pressed.emit()
		if not require(game.training.lesson == 4 and game.battle.turn == 1, "fifth lesson opens from the public training menu"): return
		var site: Vector2i = Course.SNARE_SITES[choice]
		var hammer_captured := false
		var prefix := filming_frame
		for f: int in range(210):
			var still := ""
			match f:
				6: if not select_drill_card("hollow_hammer"): return
				24: game._on_cell_clicked(Course.ORDER_CENTER,MOUSE_BUTTON_LEFT)
				55: if not select_drill_card("anchor_snare"): return
				62:
					game.board.hover_cell = site
					game._on_cell_hovered(site)
				75:
					if choice == 1: still = "20-snare-training"
				85:
					game._on_cell_clicked(site,MOUSE_BUTTON_LEFT)
					game.board.hover_cell = Vector2i(-1,-1)
				113: game._end_turn()
			if choice == 1 and not hammer_captured:
				for fx: Dictionary in game.board.effects:
					if fx.get("hammer",false) and fx.age >= 0.24:
						still = "21-hollow-hammer"
						hammer_captured = true
			await record_drill_frame(directory,still)
		var rider: Dictionary = game.battle.unit_at(site)
		var event: Dictionary = game.battle.last_order_event
		if not require(game.training.complete() and event.get("impacts",[]).size() == choice and rider.get("hp") == [8,3][choice]
				and rider.get("shield") == [1,0][choice] and (choice == 0 or hammer_captured), "the recorded hand actions finish with the authentic branch outcome"): return
		outcomes.append({"trap":game.battle.cell_name(site), "hits":event.impacts.size(), "hp":rider.hp, "shield":rider.shield, "first_frame":prefix})
		print("DRILL ", outcomes.back(), " ",game.training_panel.instruction.text)
	var manifest := FileAccess.open(directory.path_join("shots.json"),FileAccess.WRITE)
	if not require(manifest != null, "write drill film metadata"): return
	manifest.store_string(JSON.stringify({"fps":24,"frames":filming_frame,"shots":[],"cues":cues,"full_board":true,"outcomes":outcomes,
		"music":[{"file":"evening.ogg","frame":0},{"file":"angevin.ogg","frame":72}],"music_percent":55,"effects_percent":70},"\t"))
	manifest.close()

func capture_bridge_watch(directory: String) -> void:
	if not require(DirAccess.dir_exists_absolute(directory), "supply an existing bridge film directory"): return
	var cues: Array[Dictionary] = []
	game.audio.stopping = false
	game.audio.set_levels(55,70)
	game.audio.cue_started.connect(func(cue: String) -> void:
		cues.append({"sound":game.audio.CUES[cue].resource_path.get_file(), "frame":filming_frame}))
	game.board.set_process(false)
	for frame: int in range(48): await record_drill_frame(directory)
	game.council.training_button.pressed.emit()
	game.training_panel.lesson_choice.item_selected.emit(5)
	var outcomes: Array[Dictionary] = []
	for choice: int in range(2):
		if choice == 1: game.training_panel.reset_button.pressed.emit()
		var site: Vector2i = Course.MEDIC_SITES[choice]
		if not require(game.training.lesson == 5 and game.reach_button.button_pressed, "the public sixth lesson opens with its range map"): return
		for frame: int in range(188):
			match frame:
				4: if not select_drill_card("healer"): return
				12:
					game.board.hover_cell = site
					game._on_cell_hovered(site)
				62: game._on_cell_clicked(site,MOUSE_BUTTON_LEFT)
				82: game._end_turn()
			var still := "22-bridge-reinforcement" if frame == 52 and choice == 1 else ""
			await record_drill_frame(directory,still)
		var medic: Dictionary = game.battle.unit_at(site)
		if not require(game.training.complete() and game.battle.turn == 3 and medic.get("hp") == [5,3][choice]
				and game.training.bridge_target == ["铁壁枪卫","晨光医师"][choice], "record actual move, attack recipient and recovered health"): return
		outcomes.append({"site":game.battle.cell_name(site),"defender":game.training.bridge_target,"medic_hp":medic.hp,
			"d6_available":game.battle.deployment_cells(0).has(Vector2i(3,4))})
	game.training_panel.exit_button.pressed.emit()
	var campaign := Campaign.Campaign.new()
	var b: Battle = Campaign.create_encounter(campaign.index.scenarios.c01_bridge).battle
	var finish := await reach_action(b,func(model: Battle, action: Dictionary) -> bool: return model.turn == 9 and action.type == "end_turn")
	if not require(not finish.is_empty() and b.active_side == 0, "reach the bridge player's actual ninth side turn"): return
	mount_battle(b)
	game.reach_button.button_pressed = true
	var target := Vector2i(7,7)
	var rider := b.unit_at(Vector2i(8,4))
	if not require(rider.get("kind") == "cavalry" and b.unit_at(target).get("kind") == "archer" and BoardView.EnemyReach.level(game.board.enemy_reach,target,rider.id) == 1,
			"H3 is a genuine move-only threat before the enemy turn"): return
	game.board.zoom_at(game.board.cell_center(Vector2i(7,6)),1.35)
	game.board.hover_cell = target
	game._on_cell_hovered(target)
	for frame: int in range(80):
		b.advance_clock(1.0/24.0)
		game._update_clock_ui(false)
		await record_drill_frame(directory,"23-rivergate-threat" if frame == 55 else "")
		if frame == 55 and not require(game.battle_brief.visible and not game.board.grid_rect().intersects(game.battle_brief.get_rect()),
				"the source portrait stays in the right gutter and leaves the cavalry visible"): return
	if not require(game._apply_with_feedback(finish).ok, "play the pending handoff"): return
	var end_frame := filming_frame + 144
	for frame: int in range(12): await record_drill_frame(directory)
	var reached := false
	var survivor_hp := -1
	for i: int in range(28):
		var reply := AI.choose(b)
		var is_strike: bool = reply.type == "attack" and reply.unit_id == rider.id and reply.target == target
		var origin: Vector2i = rider.pos
		if not require(b.active_side == 1 and game._apply_with_feedback(reply).ok, "play the actual red turn through normal battle feedback"): return
		var frames := maxi(18, ceili(game.board.action_duration * 24.0) + 8)
		for frame: int in range(frames): await record_drill_frame(directory)
		if is_strike:
			reached = origin == Vector2i(6,7)
			survivor_hp = b.unit_at(target).get("hp",0)
			break
	if not require(reached, "the same cavalry actually attacks H3 from G3 on turn ten"): return
	if not require(filming_frame <= end_frame, "the full charge and hit fit the edit"): return
	while filming_frame < end_frame: await record_drill_frame(directory)
	var out := FileAccess.open(directory.path_join("shots.json"),FileAccess.WRITE)
	if not require(out != null, "write native bridge capture metadata"): return
	out.store_string(JSON.stringify({"fps":24,"frames":filming_frame,"shots":[],"cues":cues,"full_board":true,"outcomes":outcomes,
		"campaign":{"id":"c01_bridge","seed":b.match_seed,"player_prefix":legal_prefix,"target":"H3","origin":"G3","rider_start":"I6","archer_hp_after":survivor_hp},
		"music":[{"file":"evening.ogg","frame":0},{"file":"angevin.ogg","frame":48}],"music_percent":55,"effects_percent":70},"\t"))
	out.close()
	print("BRIDGE WATCH ",outcomes, " | campaign ",legal_prefix," actions before the view, I6 to G3 attacks H3")

func capture_frost_front(output: String) -> void:
	game._start_from_council("rivergate", "warden", "frost_engine", "glassroad_edict")
	if not require(game.battle.deck(0).cards.has("gate_veteran") and game.battle.deck(0).cards.has("breakwater_guard"), "skirmish menu loads the Frost reinforcements"): return
	var battle := Model.new(57023, "rivergate", "warden", "warden", "frost_engine", "glassroad_edict")
	for step: int in range(78):
		if not require(battle.winner == -1 and battle.apply_action(AI.choose(battle)).ok, "replay through the normal skirmish"): return
	var cell := Vector2i(8, battle.height - 6)
	var ally := battle.unit_at(cell + Vector2i.DOWN)
	if not require(battle.active_side == 0 and not ally.is_empty() and ally.card.card_id == "mink_watcher"
		and battle.attack_defender(battle.commander(1), ally).id == ally.id, "the exposed archer is on I5"): return
	var veterans: Array = battle.players[0].hand.filter(func(c: Dictionary) -> bool: return c.card_id == "gate_veteran")
	if not require(not veterans.is_empty() and battle.card_targets(veterans[0].uid, 0).has(cell), "I6 is a legal deployment from this hand"): return
	mount_battle(battle)
	await process_frame
	game._select_card(veterans[0].uid)
	game._on_cell_clicked(cell, MOUSE_BUTTON_LEFT)
	var guard := battle.unit_at(cell)
	if not require(not guard.is_empty() and guard.guarding and battle.attack_defender(battle.commander(1), ally).id == guard.id, "hand deployment immediately intercepts for the archer"): return
	game.board._process(2.0)
	game._on_cell_clicked(cell, MOUSE_BUTTON_LEFT)
	game.board.fit_map()
	game.board.zoom_at(game.board.cell_center(cell), 1.35)
	game.board.reveal_cell(cell)
	game.board.hover_cell = ally.pos
	game._on_cell_hovered(ally.pos)
	if not require(game.selected_unit == guard.id, "select the deployed guarding unit"): return
	await capture("13-frost-front", output)
	print("FROST FRONT ", battle.match_seed, " | preceding actions 78 | turn ", battle.turn,
		" | guard ", battle.cell_name(cell), " | ally ", ally.name, " ", battle.cell_name(ally.pos))

func capture_field(source: String, output: String) -> void:
	if not require(DirAccess.copy_absolute(source, TEST_SAVE) == OK, "copy an earned campaign save to the isolated capture slot"): return
	game._continue_campaign()
	var view: Control = game.story_view
	if not require(view.field_button.is_visible_in_tree() and view.setup.has("last_summary"), "continue reaches a genuine post-defeat briefing"): return
	view.field_button.pressed.emit()
	if not require(view.field_view.previous and view.field_view.board.battle.winner == 1, "review opens on the saved defeat"): return
	await capture("after-action",output.path_join("after-action.png"))
	view.field_view.opening_button.pressed.emit()
	if not require(not view.field_view.previous and view.field_view.board.battle.turn == 1, "switching shows the fresh starting position"): return
	await capture("briefing-field",output.path_join("briefing-field.png"))

func capture_chronicle(source: String, output: String) -> void:
	if not require(DirAccess.copy_absolute(source,TEST_SAVE) == OK,"copy a reached ending to the isolated main slot"): return
	var original: String = FileAccess.get_sha256(TEST_SAVE)
	game._continue_campaign()
	var last: Dictionary = game.campaign_session.current()
	if not require(last.type == "end" and last.has("ending_title"),"the archived save opens at a genuine ending"): return
	game.story_view.actions.get_child(0).pressed.emit()
	var view: Control = game.replay_view
	if not require(view.is_visible_in_tree() and view.selected_chapter() == "chapter_18" and view.covenant_button.visible
			and view.detail.get_parsed_text().contains(last.text), "last chapter shows this run's own ending"): return
	await capture("chronicle",output.path_join("chronicle.png"))
	var list: ItemList = view.chapters
	var selected: int = list.get_selected_items()[0]
	var scroll := list.get_v_scroll_bar()
	var row := list.get_item_rect(selected)
	if not require(row.position.y >= scroll.value-16 and row.end.y <= scroll.value+scroll.page+16,
			"selected chapter must be visible in the list; current=%s row=%s scroll=%s page=%s" % [selected,row,scroll.value,scroll.page]): return
	view.covenant_button.pressed.emit()
	if game.replay_confirmation.visible: game.replay_confirmation.confirmed.emit(); game.replay_confirmation.hide()
	var session: RefCounted = game.campaign_session
	var page: Dictionary = session.current()
	if not require(page.node == "covenant" and page.options.size() == 3 and session.store.path != TEST_SAVE, "the shortcut opens an unanswered covenant in the separate branch"): return
	await capture("covenant",output.path_join("covenant.png"))
	var picked: int = 1 if last.node != "split_end" else 2
	var choice: String = page.options[picked].id
	game.story_view.actions.get_child(picked).pressed.emit()
	var read := 0
	while session.current().type == "dialogue" and read < 160:
		game.story_view.actions.get_child(0).pressed.emit()
		read += 1
	var earned: Dictionary = session.current()
	if not require(earned.node == choice+"_end" and earned.node != last.node,"follow the changed covenant to a different actual ending"): return
	var reopened := Campaign.new(session.store.path)
	if not require(reopened.load_campaign().ok and reopened.current().node == earned.node and FileAccess.get_sha256(TEST_SAVE) == original,"reopen the separate ending with the primary file intact"): return
	print("CHRONICLE ", last.node, " -> ", earned.node, " | read ", read," | native route reloaded")

func capture_ferryman(directory: String) -> void:
	if not require(DirAccess.dir_exists_absolute(directory), "supply an existing capture directory"): return
	var battle := Model.new(6205, "rivergate", "warden", "warden", "relay_watch", "relay_watch")
	var board: Control = game.board
	var followed := -1
	var events := 0
	for step: int in range(42):
		var act := AI.choose(battle)
		var moving: bool = act.type == "move" and act.get("unit_id", -1) == followed
		var striking: bool = events == 2 and act.type == "attack" and act.get("unit_id", -1) == followed and act.target.x != battle.get_unit(followed).pos.x
		var arriving: bool = followed == -1 and battle.active_side == 0 and act.type == "play" and battle.hand_card(0, act.card_uid).card_id == "ferry_pikeman"
		if not (arriving or (moving and events == 1) or striking):
			if not require(battle.apply_action(act).ok, "legal skirmish prefix"): return
			continue
		mount_battle(battle)
		board.set_process(false)
		await process_frame
		var site: Vector2i = act.target if arriving else battle.get_unit(followed).pos
		board.fit_map()
		if arriving:
			var room: float = (board.size.x - 570.0) / board.grid_rect().size.x
			board.zoom_at(board.size * 0.5, clampf(room, 1.0, 1.65))
			board.pan_by(Vector2(0, board.size.y * 0.55 - board.cell_center(site).y))
		else:
			board.zoom_at(board.cell_center(site), 2.5)
			board.pan_by(board.size * Vector2(0.53, 0.51) - board.cell_center(site))
		if not require(game._apply_with_feedback(act).ok, "ferryman action passes normal game rules"): return
		var actor: Dictionary = battle.unit_at(site) if arriving else battle.get_unit(followed)
		if arriving: followed = actor.id
		if not require(actor.id == followed and battle.unit_art_id(actor) == "ferry_pikeman", "same deployed card and unit"): return
		game.selected_unit = followed
		game.board.hover_cell = actor.pos
		game._on_cell_hovered(actor.pos)
		game._refresh()
		game._update_battle_peek()
		var stage := "24-ferry-pikeman" if arriving else ("26-ferryman-moving" if moving else "25-ferryman-strike")
		if moving:
			if not require(board.motion_unit == followed and board.motion_tween != null, "actual movement tween"): return
			board.motion_tween.pause()
			board.motion_tween.custom_step(0.11)
			if not require(board.motion_progress > 0 and board.motion_progress < 1, "sample mid-step"): return
		elif striking:
			board._process(0.23)
			if not require(board.combat_pose(followed) == 1, "draw the contact cel of the actual attacker"): return
		else:
			board._process(1.10)
			if not require(actor.guarding, "the new deployment is covering adjacent allies"): return
			var resumed: Dictionary = Snapshot.restore(JSON.parse_string(JSON.stringify(Snapshot.capture(battle), "", true, true)))
			if not require(resumed.ok and resumed.battle.unit_art_id(resumed.battle.get_unit(followed)) == "ferry_pikeman", "save restores this specific piece"): return
		board.queue_redraw()
		await capture(stage, directory.path_join(stage + ".png"))
		if arriving and not require(game.battle_peek.is_visible_in_tree() and game.battle_peek.heading.text == actor.name
				and game.battle_peek.portrait.texture == CastArt.Art.get_texture("ferry_pikeman"), "card portrait and deployed figure visible together"): return
		if not require(Rect2(Vector2.ZERO, board.size).grow(-20).has_point(board.cell_center(site)), "the piece is inside the visible battlefield"): return
		print("FERRYMAN | ", stage, " | legal prefix ", step, " | instance ", followed, " | ", battle.cell_name(site), " -> ", battle.cell_name(act.target))
		events += 1
	require(events == 3, "captured deployment, actual movement and contact for the same ferryman")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A native renderer is required for gameplay screenshots")
		quit(2)
		return
	cleanup()
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args[0] not in ["--frost-front","--signature-frames","--field-frames","--sky-frames","--campaign-field","--chronicle","--order-drill","--bridge-watch","--ferryman"]:
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
	if args.size() == 2 and args[0] == "--ferryman":
		await capture_ferryman(args[1])
	elif args.size() == 2 and args[0] == "--bridge-watch":
		await capture_bridge_watch(args[1])
	elif args.size() == 2 and args[0] == "--order-drill":
		await capture_order_drill(args[1])
	elif args.size() == 2 and args[0] in ["--cast-frames","--signature-frames","--field-frames","--sky-frames"]:
		await capture_cast_frames(args[1], args[0])
	elif args.size() == 3 and args[0] == "--campaign-field":
		await capture_field(args[1],args[2])
	elif args.size() == 3 and args[0] == "--chronicle":
		await capture_chronicle(args[1],args[2])
	elif args.has("--frost-front"):
		await capture_frost_front(args[1] if args.size() == 2 else "")
	elif args.has("--highlands"):
		await capture_highlands()
	else:
		var skirmishes_only := OS.get_cmdline_user_args().has("--skirmishes")
		if not skirmishes_only: await capture_campaign()
		await capture_skirmishes()
		await capture_harbor()
		await capture_highlands()
		await capture_frost_front("")
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
