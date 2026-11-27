extends SceneTree
## Actual actions and the real main scene; no duplicate draw-rule implementation.
## Self-contained so the same external script can also verify an exported PCK.

const MainScene = preload("res://scenes/main.tscn")
const Store = preload("res://scripts/deck_store.gd")
const Draw = preload("res://scripts/card_draw_presentation.gd")
const Settings = preload("res://scripts/settings_store.gd")
const Campaign = preload("res://scripts/campaign_session.gd")
const PROOF_DIR := "res://.tools/draw-ui-proof"
var proof_dir: String = PROOF_DIR
var frames_dir: String = "res://.tools/v064/draw-frames"
var game: Control
var checks: int = 0
var failures: int = 0

# Only test setup mutates zones; all exercised actions go through the real Battle.
class Fixture:
	static func give(battle: RefCounted, id: String, side: int = 0) -> Dictionary:
		for instance: Dictionary in battle.players[side].hand:
			if instance.card_id == id: return instance
		if battle.players[side].hand.size() == battle.HAND_LIMIT: battle.players[side].discard.append(battle.players[side].hand.pop_back())
		for instance: Dictionary in battle.players[side].deck:
			if instance.card_id != id: continue
			battle.players[side].deck.erase(instance)
			battle.players[side].hand.append(instance)
			return instance
		battle.add_generated_card(side, id)
		return battle.players[side].hand.back()

	static func troop(battle: RefCounted, id: String, cell: Vector2i, side: int = 0) -> Dictionary:
		var instance: Dictionary = give(battle, id, side)
		battle.players[side].hand.erase(instance)
		battle.terrain[cell] = "plain"
		var unit: Dictionary = battle.get_unit(battle._spawn(battle.definition(id), cell, side))
		instance["unit_id"] = unit.id
		unit["card"] = instance
		unit.summoning = false
		unit.attacked = false
		unit.moved = false
		return unit

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func settle() -> void:
	for frame: int in range(5): await process_frame

func immutable_state() -> String:
	return var_to_str([game.battle.units, game.battle.players, game.battle.terrain, game.battle.rng.state, game.battle.log_lines])

func stage() -> void:
	game._new_match(71)
	game.has_started = true
	game.council.hide()
	if not game.expanded_battlefield: game._toggle_battlefield()
	for player: Dictionary in game.battle.players:
		player.mana = 10
		player.max_mana = 10
	game._refresh()
	await settle()
	game.set_process(false)
	game.draw_presentation.set_process(false)
	game.draw_presentation.set_reduced_motion(false)
	game.draw_presentation.reset()
	game._sync_draw_anchors()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(proof_dir))
	check(root.get_texture().get_image().save_png(proof_dir.path_join(name + ".png")) == OK, "native screenshot " + name)

func present_at(seconds: float) -> void:
	game.draw_presentation._process(seconds)
	await settle()
	game._position_battle_peek()
	game._sync_draw_anchors()
	await settle()

func play(id: String, target: Vector2i = Vector2i(-1, -1), side: int = 0) -> Dictionary:
	var instance: Dictionary = Fixture.give(game.battle, id, side)
	return game._apply_with_feedback({"type": "play", "card_uid": instance.uid, "target": target})

func exercise_opening() -> void:
	check(not game.draw_presentation.is_presenting(), "initial war council does not deal a hidden practice match")
	game._start_from_council("greenwood", "warden", "balanced")
	await settle()
	game.set_process(false)
	game.draw_presentation.set_process(false)
	check(game.battle.players[0].hand.size() == 5 and game.battle.players[1].hand.size() == 6, "opening reflects the already resolved actual hands")
	check(game.draw_presentation.events.size() == 11, "each initial hand card is presented once")
	await present_at(0.45)
	await capture("01-opening-deal")
	var exact: String = immutable_state()
	await present_at(5.0)
	check(exact == immutable_state() and not game.draw_presentation.is_presenting(), "opening completion never deals twice or advances RNG")
	var original: Battle = game.battle
	game._new_match(original.match_seed, original)
	await settle()
	check(not game.draw_presentation.is_presenting() and exact == immutable_state(), "mounting prepared or resumed battle never replays opening")
	game._new_match(82, null, true)
	game._new_match(83)
	await settle()
	check(not game.draw_presentation.is_presenting(), "stale deferred opening is cancelled by match generation")

func exercise_draws() -> void:
	await stage()
	var draw_card: Dictionary = Fixture.give(game.battle, "insight")
	var first: Dictionary = game.battle.players[0].deck.back().duplicate()
	var second: Dictionary = game.battle.players[0].deck[-2].duplicate()
	var mana: int = game.battle.players[0].mana
	check(game._apply_with_feedback({"type": "play", "card_uid": draw_card.uid, "target": Vector2i(-1, -1)}).ok, "real two-card spell resolves")
	check(game.draw_presentation.events.size() == 2 and game.draw_presentation.events[0].uid == first.uid and game.draw_presentation.events[1].uid == second.uid, "animation uses actual top-deck UID order")
	check(game.battle.players[0].mana == mana - 2, "draw spell paid exactly once")
	await present_at(0.56)
	await capture("02-two-card-reveal")
	var exact: String = immutable_state()
	await present_at(0.42)
	await capture("03-cards-landing")
	await present_at(5.0)
	check(exact == immutable_state(), "travel and arrival preserve cards, units, terrain, log and RNG")
	await stage()
	check(play("chalk_route").ok and game.draw_presentation.events.size() == 1, "targeted supply presents the actual reserve card")
	await stage()
	Fixture.give(game.battle, "dispatch_bundle")
	while game.battle.players[0].hand.size() < 8: game.battle.add_generated_card(0, "sword")
	check(play("dispatch_bundle").ok, "full hand plays a real three-card draw")
	check(game.battle.players[0].hand.size() == 8 and game.draw_presentation.events.size() == 3, "one free hand slot and two actual overflow cards")
	check(game.draw_presentation.events.filter(func(e: Dictionary) -> bool: return e.burned).size() == 2, "overflow cards go to discard instead of imaginary hand slots")
	await present_at(0.8)
	await capture("04-full-hand-discard")
	await stage()
	Fixture.give(game.battle, "insight")
	game.battle.players[0].deck.clear()
	var hp: int = game.battle.commander(0).hp
	check(play("insight").ok and not game.draw_presentation.is_presenting(), "empty deck produces no fake card")
	check(game.battle.commander(0).hp == hp - 3, "fatigue remains the real one plus two damage")
	await stage()
	Fixture.give(game.battle, "insight")
	game.battle.players[0].mana = 0
	check(not play("insight").ok and not game.draw_presentation.is_presenting(), "rejected draw spell creates no presentation")

func exercise_other_transfers() -> void:
	await stage()
	var ally: Dictionary = Fixture.troop(game.battle, "sword", Vector2i(4, 5))
	check(play("recall_writ", ally.pos).ok and not game.draw_presentation.is_presenting(), "returning a unit is not a deck draw")
	var before: Array[Dictionary] = Draw.capture(game.battle.players)
	game.battle.add_generated_card(0, "initiative")
	game._present_draws(before)
	check(not game.draw_presentation.is_presenting(), "generated hand cards are not deck draws")
	await stage()
	var reserve: Dictionary = Fixture.give(game.battle, "insight")
	game.battle.players[0].hand.erase(reserve)
	game.battle.players[0].discard.append(reserve)
	check(play("lamp_ledger").ok and not game.draw_presentation.is_presenting(), "recovering a discarded spell is not a deck draw")
	await stage()
	var card: Dictionary = Fixture.give(game.battle, "roadside_muster")
	var targets: Array[Vector2i] = game.battle.card_targets(card.uid, 0)
	check(not targets.is_empty(), "muster fixture has a legal landing")
	if not targets.is_empty():
		check(game._apply_with_feedback({"type": "play", "card_uid": card.uid, "target": targets[0]}).ok and not game.draw_presentation.is_presenting(), "deck-to-battlefield muster does not draw into hand")
	await stage()
	var attacker: Dictionary = Fixture.troop(game.battle, "sword", Vector2i(4, 5))
	var victim: Dictionary = Fixture.troop(game.battle, "lantern_bearer", Vector2i(4, 4), 1)
	victim.hp = 1
	check(game._apply_with_feedback({"type": "attack", "unit_id": attacker.id, "target": victim.pos}).ok, "actual attack kills a draw-on-fall enemy")
	check(game.draw_presentation.events.size() == 1 and game.draw_presentation.events[0].side == 1, "enemy death draw is captured during the player's action")

func check_enemy_privacy() -> void:
	for event: Dictionary in game.draw_presentation.events:
		if event.side != 1: continue
		check(not event.has("uid") and not event.has("card_id") and not event.has("name") and not event.has("card"), "enemy event contains no hidden card identity")
		check(not game.draw_presentation.geometry(event).face, "enemy geometry can only draw a card back")

func exercise_turns_and_privacy() -> void:
	await stage()
	check(game._apply_with_feedback({"type": "end_turn"}).ok and game.draw_presentation.events.size() == 1, "end turn queues one actual enemy draw")
	check_enemy_privacy()
	await present_at(0.22)
	await capture("05-enemy-hidden-draw")
	game.draw_presentation.reset()
	check(game._apply_with_feedback({"type": "end_turn"}).ok and game.draw_presentation.events[0].side == 0, "opponent end turn queues player's actual draw")
	game.draw_presentation.reset()
	game.battle.end_turn()
	game.battle.time_remaining = 0.01
	game._process(0.02)
	check(game.battle.active_side == 0 and game.draw_presentation.events.size() == 1 and game.draw_presentation.events[0].side == 0, "timeout bypass path still captures the new turn draw")
	var hostile: Array[Dictionary] = [{"side": 1, "uid": 12345, "card_id": "insight", "name": "secret", "burned": true}]
	game.draw_presentation.enqueue(hostile)
	check_enemy_privacy()
	var burned: Dictionary = game.draw_presentation.events.back().duplicate()
	burned.age = burned.duration
	check(game.draw_presentation.geometry(burned).center.is_equal_approx(game.draw_presentation.anchors.enemy_discard.get_center() - game.draw_presentation.global_position), "enemy overflow travels to discard rather than hidden hand")
	await stage()
	while game.battle.players[1].hand.size() < 8: game.battle.add_generated_card(1, "sword")
	check(game._apply_with_feedback({"type": "end_turn"}).ok and game.draw_presentation.events.size() == 1 and game.draw_presentation.events[0].burned, "actual enemy full hand overflows into discard")
	check_enemy_privacy()

func exercise_lifecycle() -> void:
	await stage()
	check(play("insight").ok, "lifecycle draw fixture")
	game._open_council(false)
	check(not game.draw_presentation.is_presenting(), "opening modal clears drawing cards immediately")
	game._resume_battle()
	check(not game.draw_presentation.is_presenting(), "closing modal does not revive old cards")
	await stage()
	check(play("insight").ok, "early interaction fixture")
	var uid: int = game.draw_presentation.events[0].uid
	game._select_card(uid)
	check(game.selected_card == uid and not game.draw_presentation.pending(uid), "new card may be selected immediately without waiting for animation")
	game._new_match(84)
	check(not game.draw_presentation.is_presenting(), "new match clears all queued card effects")
	await stage()
	game.draw_presentation.set_reduced_motion(true)
	check(play("insight").ok, "draw still resolves in reduced motion")
	await present_at(0.1)
	for event: Dictionary in game.draw_presentation.events:
		check(event.duration <= 0.22, "reduced motion uses only a short static arrival marker")
		var target: Rect2 = game.draw_presentation.hand_slots[event.uid]
		check(game.draw_presentation.geometry(event).center.is_equal_approx(target.get_center() - game.draw_presentation.global_position), "reduced motion stays at the final slot")
	await capture("06-reduced-motion-arrival")
	var exact: String = immutable_state()
	game.draw_presentation.set_reduced_motion(false)
	check(not game.draw_presentation.is_presenting() and exact == immutable_state(), "changing motion preference clears visuals without state changes")
	for dialog_name: String in ["quit_confirmation", "campaign_confirmation", "replay_confirmation"]:
		await stage()
		check(play("insight").ok, "confirmation fixture " + dialog_name)
		var dialog: Window = game.get(dialog_name)
		dialog.popup_centered()
		game._process(0.0)
		check(not game.draw_presentation.is_presenting(), "confirmation cannot be covered by cards " + dialog_name)
		dialog.hide()
	await stage()
	check(play("insight").ok, "victory interruption fixture")
	var enemy: Dictionary = game.battle.commander(1)
	enemy.hp = 1
	var attacker: Dictionary = Fixture.troop(game.battle, "sword", enemy.pos + Vector2i(0, 1))
	check(game._apply_with_feedback({"type": "attack", "unit_id": attacker.id, "target": enemy.pos}).ok and game.battle.winner == 0, "real lethal attack ends battle")
	check(not game.draw_presentation.is_presenting(), "victory cancels outstanding draw presentation before result display")

func exercise_layout() -> void:
	for dimensions: Vector2i in [Vector2i(1008, 700), Vector2i(1440, 1000), Vector2i(1920, 1080)]:
		root.size = dimensions
		await stage()
		while game.battle.players[0].hand.size() < 8: game.battle.add_generated_card(0, "sword")
		game._refresh()
		await settle()
		game.draw_presentation.enqueue(Draw.opening_hand(game.battle.players))
		await present_at(0.55)
		for event: Dictionary in game.draw_presentation.events:
			if event.age < 0: continue
			var frame: Dictionary = game.draw_presentation.geometry(event)
			check(game.get_global_rect().grow(2).encloses(Rect2(frame.center - frame.size * 0.5, frame.size)), "drawing card remains within viewport " + str(dimensions))
		game._toggle_battlefield()
		await settle()
		game._sync_draw_anchors()
		var view_rect: Rect2 = game.get_viewport_rect()
		if OS.get_cmdline_user_args().has("--draw-layout-diagnostics"):
			print("DRAW_LAYOUT physical=", dimensions, " logical=", view_rect, " owner=", game.get_global_rect(), " margin=", game.get_node("Margin").get_global_rect(), " hand=", game.hand.get_global_rect(), " child_min=", game.hand.get_child(0).custom_minimum_size, " tools_min=", game.get_node("%ViewEnd").get_parent().get_combined_minimum_size())
		for node_name: String in ["InfoPanel", "RightPanel", "Board", "HandPanel"]:
			var element: Control = game.get_node("%" + node_name)
			check(view_rect.grow(2).encloses(element.get_global_rect()), "standard layout remains inside real stretched viewport: " + node_name + " / " + str(dimensions))
		check(game.draw_presentation.hand_slots.size() == 8, "layout switch rebinds all card UID targets " + str(dimensions))
		for slot: Rect2 in game.draw_presentation.hand_slots.values():
			check(slot.size.x > 0 and slot.size.y > 0, "new layout targets have real dimensions")
		await capture("07-layout-%dx%d" % [dimensions.x, dimensions.y])
		for count: int in [1, 0]:
			game.draw_presentation.reset()
			while game.battle.players[0].hand.size() > count: game.battle.players[0].discard.append(game.battle.players[0].hand.pop_back())
			game._refresh()
			await settle()
			game._sync_draw_anchors()
			check(game.draw_presentation.hand_slots.size() == count, "layout supports %d remaining hand cards at %s" % [count, dimensions])

func capture_filmstrip() -> void:
	if DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1920, 1080)
	await stage()
	game.battle.end_turn()
	game._apply_with_feedback({"type": "end_turn"})
	game.board.reset_effects()
	var directory: String = frames_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for index: int in range(12):
		await present_at(0.0 if index == 0 else 0.11)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("frame-%02d.png" % index)) == OK, "native draw filmstrip frame %d" % index)
	await capture("08-settled-interface")

func check_dialog_inside(dialog: Window, viewport_size: Vector2i, label: String) -> void:
	var decorated := Rect2(Vector2(dialog.position) - Vector2(0, 36), Vector2(dialog.size) + Vector2(0, 36))
	check(Rect2(Vector2.ZERO, Vector2(viewport_size)).grow(1).encloses(decorated), label + " includes title bar and remains inside viewport: " + str(decorated))

func capture_dialog(viewport: SubViewport, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(proof_dir.path_join(label + ".png")) == OK, "native resized dialog " + label)

func exercise_dialog_resize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sample: Control = MainScene.instantiate()
	sample.deck_store = Store.new(proof_dir.path_join("dialog-deck.json"))
	sample.settings_store = Settings.new(proof_dir.path_join("dialog-settings.cfg"))
	sample.campaign_session = Campaign.new(proof_dir.path_join("dialog-campaign.json"))
	viewport.add_child(sample)
	sample.set_process(false)
	sample.audio.set_levels(0, 0)
	await settle()
	sample._open_library()
	await settle()
	viewport.size = Vector2i(1008, 700)
	await settle()
	await settle()
	check_dialog_inside(sample.get_node("%CardsDialog"), viewport.size, "open card library shrinks")
	check(sample.get_node("%CardGrid").columns <= 5, "library reduces columns before shrinking the window")
	await capture_dialog(viewport, "09-library-shrink-1008")
	sample._library_details(sample.battle.definition("ash_notary"), 0)
	sample._open_character_art()
	await settle()
	viewport.size = Vector2i(1920, 1080)
	await settle()
	viewport.size = Vector2i(1008, 700)
	await settle()
	await settle()
	check_dialog_inside(sample.get_node("%CardsDialog"), viewport.size, "library behind full art also shrinks")
	check_dialog_inside(sample.get_node("%CharacterArtDialog"), viewport.size, "nested full-art dialog shrinks")
	await capture_dialog(viewport, "10-full-art-shrink-1008")
	sample.get_node("%CharacterArtDialog").hide()
	sample.get_node("%CardsDialog").hide()
	sample._open_deck_editor()
	await settle()
	viewport.size = Vector2i(1920, 1080)
	await settle()
	viewport.size = Vector2i(1008, 700)
	await settle()
	await settle()
	check_dialog_inside(sample.deck_editor, viewport.size, "deck editor shrinks after opening")
	check(sample.deck_editor.grid.columns == 3, "deck editor reduces card columns")
	await capture_dialog(viewport, "11-editor-shrink-1008")
	sample.audio.stop_playback()
	viewport.queue_free()
	await process_frame
	# Also exercise the shipped root window's canvas_items/expand contract.
	root.size = Vector2i(1920, 1080)
	await stage()
	game._open_library()
	await settle()
	root.size = Vector2i(1008, 700)
	await settle()
	await settle()
	var logical: Vector2i = Vector2i(game.get_viewport_rect().size)
	check(logical.x >= 1440 and logical.y >= 1000, "retail window resize retains the configured logical canvas")
	check_dialog_inside(game.get_node("%CardsDialog"), logical, "retail root window card library resize")
	await capture("12-retail-library-1008")
	game._library_details(game.battle.definition("ash_notary"), 0)
	game._open_character_art()
	await settle()
	check_dialog_inside(game.get_node("%CharacterArtDialog"), logical, "retail root window full art resize")
	await capture("13-retail-full-art-1008")
	game.get_node("%CharacterArtDialog").hide()
	game.get_node("%CardsDialog").hide()
	root.size = Vector2i(1920, 1080)
	await settle()
	game._open_deck_editor()
	await settle()
	root.size = Vector2i(1008, 700)
	await settle()
	await settle()
	check_dialog_inside(game.deck_editor, Vector2i(game.get_viewport_rect().size), "retail root window deck editor resize")
	await capture("14-retail-editor-1008")
	game.deck_editor.hide()

func run() -> void:
	create_timer(80).timeout.connect(func() -> void: push_error("card draw UI timeout"); quit(2))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--draw-proof-dir="): proof_dir = argument.trim_prefix("--draw-proof-dir=")
		if argument.begins_with("--draw-frames-dir="): frames_dir = argument.trim_prefix("--draw-frames-dir=")
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(proof_dir))
	game = MainScene.instantiate()
	game.deck_store = Store.new(proof_dir.path_join("fixture-deck.json"))
	game.settings_store = Settings.new(proof_dir.path_join("fixture-settings.cfg"))
	game.campaign_session = Campaign.new(proof_dir.path_join("fixture-campaign.json"))
	root.add_child(game)
	current_scene = game
	game.audio.set_levels(0, 0)
	game.set_process(false)
	game.draw_presentation.set_process(false)
	await settle()
	await exercise_opening()
	await exercise_draws()
	await exercise_other_transfers()
	await exercise_turns_and_privacy()
	await exercise_lifecycle()
	await exercise_layout()
	await capture_filmstrip()
	await exercise_dialog_resize()
	game.draw_presentation.reset()
	game.audio.stop_playback()
	print("CARD DRAW UI: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
