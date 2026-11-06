extends "res://tests/test_campaign_playthrough_ui.gd"
## Native fixture interaction checks, not a claim of a campaign playthrough.
const Model = preload("res://scripts/battle.gd")
func fixture() -> void:
	game.generation += 1
	game.ai_running = false
	game.campaign_active = false
	game._new_match(2901, Model.new(2901, "greenwood", "warden", "warden", "ambush", "ambush"))
	game.has_started = true; game.council.hide()
	if not game.expanded_battlefield: game._toggle_battlefield()
	var b: Battle = game.battle
	for cell: Vector2i in b.terrain: b.terrain[cell] = "plain"
	for side: int in [0, 1]:
		b.players[side].discard.append_array(b.players[side].hand); b.players[side].hand.clear()
		b.players[side].mana = 10; b.players[side].max_mana = 10
	b.commander(0).pos = Vector2i(2, 3); b.commander(1).pos = Vector2i(9, 7)
	game._refresh(); await settle()
func fixture_troop(kind: String, at: Vector2i, side: int) -> Dictionary:
	var b: Battle = game.battle
	var id: int = b._spawn(b.definition(kind), at, side)
	var unit: Dictionary = b.get_unit(id)
	unit.card = {"uid": b._id(), "card_id": kind, "unit_id": id}; b.players[side].card_total += 1
	unit.moved = false; unit.attacked = false; unit.summoning = false
	return unit
func give(id: String) -> int:
	check(game.battle.add_generated_card(game.battle.active_side, id), "fixture hand contains " + id)
	return game.battle.players[game.battle.active_side].hand.back().uid
func use_hand(uid: int, at: Vector2i) -> void:
	game._refresh(); await settle()
	await player_action({"type": "play", "card_uid": uid, "target": at})
func click_editor(point: Vector2) -> void:
	# Embedded Window controls have their own origin. Route the pointer through
	# the main viewport after converting the editor's logical coordinates.
	await click(root.get_screen_transform().affine_inverse() * (game.deck_editor.get_screen_transform() * point))
func run() -> void:
	create_timer(120).timeout.connect(func() -> void: push_error("expansion native fixture timeout"); quit(2))
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/expansion_native_deck.json")
	game.campaign_session = Session.new("res://.tools/expansion_native_campaign.json")
	root.add_child(game); current_scene = game; await settle()
	await fixture()
	for id: String in Snapshot.EXPANSION_CARDS:
		give(id)
		check(game.Art.get_texture(id) != null, "new card has native generated illustration " + id)
	game._refresh(); await settle()
	check(game.get_node("%CompactHand").get_child_count() == 8, "all eight expansion cards use real hand controls")
	await capture("v029-expansion-hand")
	await fixture()
	game.battle.commander(0).hp -= 3
	var heal_uid: int = give("rally_heal")
	game._refresh(); await settle()
	await click(game.get_node("%CompactHand").get_child(0).get_global_rect().get_center())
	var motion := InputEventMouseMotion.new()
	motion.position = game.board.global_position + game.board.cell_center(Vector2i(3, 3))
	root.push_input(motion, true); await settle()
	check(game._effect_context().get("target_id", 0) == -1, "area heal can preview an empty center")
	check(game.battle_peek.heading.text == "同行祷雨" and game.battle_peek.subtitle.text.begins_with("范围预估"), "empty-center hover shows the spell and affected allies")
	await click_cell(Vector2i(3, 3))
	check(game.battle.hand_card(0, heal_uid).is_empty() and game.battle.commander(0).hp == game.battle.commander(0).max_hp - 1, "empty-center native click heals adjacent ally and spends the card")
	await fixture()
	var enemy: Dictionary = fixture_troop("cavalry", Vector2i(6, 3), 1)
	var uid: int = give("anchor_snare")
	await use_hand(uid, Vector2i(4, 3))
	check(game.battle.traps.size() == 1 and game.battle.players[0].mana == 8 and game.battle.hand_card(0, uid).is_empty(), "real hand and board clicks pay for a concealed ground trap")
	await create_timer(0.9).timeout
	await capture("v029-trap-armed")
	game.battle.end_turn()
	check(game._apply_with_feedback({"type": "move", "unit_id": enemy.id, "target": Vector2i(3, 3)}).ok, "native move resolves through canonical trap rules")
	check(game.board.motion_path.back() == Vector2i(4, 3) and enemy.pos == Vector2i(4, 3), "movement animation stops at the real triggered tile")
	check(game.battle.traps.is_empty() and game.board.effects.any(func(e: Dictionary): return e.text.contains("锚索伏阵")), "trigger is named only when revealed")
	await create_timer(0.12).timeout
	await capture("v029-trap-trigger")
	await fixture()
	enemy = fixture_troop("archer", Vector2i(5, 3), 1); enemy.hp = 2
	uid = give("ember_mine"); await use_hand(uid, Vector2i(4, 3))
	game.battle.end_turn()
	check(game._apply_with_feedback({"type": "move", "unit_id": enemy.id, "target": Vector2i(3, 3)}).ok, "native lethal mine resolves a legal movement")
	check(game.battle.get_unit(enemy.id).is_empty() and game.board.motion_ghost.get("id", -1) == enemy.id, "removed mover retains a temporary presentation image")
	check(game.board.effects.any(func(e: Dictionary): return e.text == "击破" and e.cell == Vector2i(4, 3) and e.age < 0), "death burst waits for arrival at the triggering tile")
	await create_timer(0.12).timeout; await capture("v029-mine-motion")
	await create_timer(0.25).timeout; await capture("v029-mine-death")
	await fixture()
	var ally: Dictionary = fixture_troop("mage", Vector2i(4, 3), 0)
	enemy = fixture_troop("sword", Vector2i(5, 3), 1)
	uid = give("oath_ward"); await use_hand(uid, ally.pos)
	game.battle.end_turn()
	check(game._apply_with_feedback({"type": "attack", "unit_id": enemy.id, "target": ally.pos}).ok and ally.hp == ally.max_hp and game.battle.traps.is_empty(), "native armed ward absorbs a real normal attack")
	await create_timer(0.16).timeout
	await capture("v029-ward-trigger")
	await fixture()
	game.battle.end_turn()
	game.battle.players[1].discard.append_array(game.battle.players[1].hand); game.battle.players[1].hand.clear()
	game.battle.players[1].mana = 2
	# Isolate placement secrecy from the higher-scoring commander blessing.
	game.battle.players[1].skill_cooldown = 1
	give("oath_ward")
	game.board.last_cell = Vector2i(-1, -1); game.board.flash_cell = Vector2i(-1, -1)
	game.ai_running = true
	await game._run_ai(game.generation)
	check(game.battle.Traps.count(game.battle, 1) == 1 and game.battle.visible_traps(0).is_empty(), "actual enemy AI can set a hidden ward")
	check(game.board.last_cell == Vector2i(-1, -1) and game.board.flash_cell == Vector2i(-1, -1), "enemy AI does not flash or underline its secret target")
	check(game.board.casting_pose.is_empty() and game.board.effects.is_empty(), "enemy placement exposes no caster pose or target effect")
	check(not game.get_node("%BattleLog").text.contains("回誓屏障") and game.get_node("%WeatherStatus").text.contains("敌1"), "public HUD reveals only enemy trap count")
	await capture("v029-enemy-trap-hidden")
	await game.deck_editor.open_deck(Model.DECKS.find("ambush")); await settle()
	await click_editor(game.deck_editor.filter_buttons.trap.get_global_rect().get_center())
	var visible_rows: int = 0
	for entry: Dictionary in game.deck_editor.rows.values():
		if entry.cell.visible: visible_rows += 1; check(entry.type == "trap", "trap filter excludes other card types")
	check(visible_rows == 3, "deck editor exposes all three new traps")
	await RenderingServer.frame_post_draw
	check(game.deck_editor.get_texture().get_image().save_png("res://docs/screenshots/v029-trap-deck-editor.png") == OK, "capture the native deck-editor window")
	game.deck_editor.hide()
	print("EXPANSION NATIVE UI: %d CHECKS | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	game.queue_free(); await process_frame; quit(0 if failures == 0 else 1)
