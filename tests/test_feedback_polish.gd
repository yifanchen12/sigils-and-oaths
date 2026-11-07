extends "res://tests/test_unit_skills_ui.gd"
## Reuses real-window input and scene fixtures; all actions still pass through Battle.

func hover(cell: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = game.board.global_position + game.board.cell_center(cell)
	root.push_input(event, true)
	await settle()

func give(id: String) -> Dictionary:
	for zone: String in ["hand", "deck"]:
		for card: Dictionary in game.battle.players[0][zone]:
			if card.card_id != id: continue
			if zone != "hand": game.battle.players[0][zone].erase(card); game.battle.players[0].hand.append(card)
			return card
	game.battle.add_generated_card(0, id)
	return game.battle.players[0].hand.back()

func select_card(card: Dictionary) -> void:
	game._refresh(); await settle()
	for view: Control in game.get_node("%CompactHand").get_children():
		if view.card_uid == card.uid:
			await click(view.get_global_rect().get_center())
			check(game.selected_card == card.uid, "real card click enters spell target mode")
			return
	check(false, "card fixture is visible in hand")

func effect_exists(kind: String) -> bool:
	return game.board.effects.any(func(effect: Dictionary) -> bool: return effect.kind == kind)

func run() -> void:
	create_timer(60).timeout.connect(func() -> void: push_error("feedback polish timeout"); quit(2))
	recording = OS.get_cmdline_user_args().has("--record")
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/feedback_polish_deck.json")
	root.add_child(game); current_scene = game
	await stage()
	var mage: Dictionary = troop("mage", Vector2i(4, 5))
	var guard: Dictionary = troop("spear", Vector2i(5, 3), 1)
	var target: Dictionary = troop("sword", Vector2i(4, 3), 1); target.shield = 2
	game.battle.end_turn()
	check(game.battle.apply_action({"type": "unit_skill", "unit_id": guard.id, "target": guard.pos}).ok, "real enemy guard fixture")
	game.battle.end_turn()
	await select(mage); await key(KEY_Q)
	var before: String = immutable_state()
	await hover(target.pos)
	check(before == immutable_state(), "hover preview preserves rules and RNG")
	check(game._effect_context().changes[0].hp_loss == 1, "mage preview subtracts shield")
	check(game.board.predicted_losses.has(target.id) and not game.board.predicted_losses.has(guard.id), "magic preview bypasses guard")
	check(game.battle_peek.visible and game.battle_peek.subtitle.text.begins_with("效果预估"), "effect preview appears in portrait gutter")
	check(game.battle_peek.details.text.contains("不触发援护"), "magic preview explains guard bypass")
	await capture("spell-target-preview"); await pause_for_demo()
	await click(game.board.global_position + game.board.cell_center(target.pos))
	check(target.hp == 4 and target.shield == 0 and guard.hp == guard.max_hp, "magic result matches preview")
	check(effect_exists("fire_cast"), "mage uses attack cast rather than heal effect")
	check(game.board.predicted_losses.is_empty() and game.board.predicted_gains.is_empty(), "committing spell clears stale overlays")
	await create_timer(0.40).timeout; await capture("fire-cast-impact")
	await pause_for_demo()
	await stage()
	var medic: Dictionary = troop("healer", Vector2i(4, 5))
	var ally: Dictionary = troop("sword", Vector2i(5, 5)); ally.hp = 4
	await select(medic); await key(KEY_Q); await hover(ally.pos)
	check(game.board.predicted_gains[ally.id].heal == 1, "healing preview respects cap and green segment")
	check(game.battle_peek.details.text.contains("4 → 5"), "healing preview shows exact remaining health")
	if not recording:
		var mana: int = game.battle.players[0].mana
		await key(KEY_ESCAPE)
		check(game.board.predicted_gains.is_empty() and game.board.predicted_losses.is_empty() and game.battle.players[0].mana == mana, "cancel clears recovery overlays without paying mana")
		await select(medic); await key(KEY_Q); await hover(ally.pos)
	await capture("healing-target-preview"); await pause_for_demo()
	await click(game.board.global_position + game.board.cell_center(ally.pos))
	check(ally.hp == 5 and effect_exists("heal_cast") and not effect_exists("fire_cast"), "healer gets matching healing effect")
	await create_timer(0.40).timeout; await capture("healing-cast-impact")
	if not recording:
		game._open_council(); await settle()
		check(not game.board.is_presenting() and game.board.effects.is_empty(), "opening menu clears active cast presentation")
		game._resume_battle(); await settle()
		check(not game.board.is_presenting(), "closing menu does not revive old effects")
	await pause_for_demo()
	await stage()
	ally = troop("sword", Vector2i(5, 8)); ally.shield = 1
	await select_card(give("ward")); await hover(ally.pos)
	check(game.board.predicted_gains[ally.id].shield == 2 and game.battle_peek.details.text.contains("1 → 3"), "ward preview replaces rather than stacks")
	await capture("shield-target-preview"); await pause_for_demo()
	await click(game.board.global_position + game.board.cell_center(ally.pos))
	check(ally.shield == 3 and effect_exists("ward_cast"), "ward card gets shield-shaped cast effect")
	await create_timer(0.40).timeout; await capture("ward-cast-impact")
	await pause_for_demo()
	await stage()
	var caster: Dictionary = troop("sword", Vector2i(4, 6))
	var center := Vector2i(4, 4)
	var victims: Array[Dictionary] = []
	for cell: Vector2i in [center, center + Vector2i.LEFT, center + Vector2i.RIGHT, center + Vector2i.UP, center + Vector2i.DOWN]: victims.append(troop("spear", cell, 1))
	await select_card(give("nova")); await hover(center)
	check(game.board.predicted_losses.size() == 5 and game._effect_context().changes.size() == 5, "area forecast covers all five real victims")
	check(game.battle_peek.visible and game.battle_peek.details.text.contains("命中 5"), "area preview list fits portrait gutter")
	await capture("area-spell-preview"); await pause_for_demo()
	await click(game.board.global_position + game.board.cell_center(center))
	check(effect_exists("fire_area"), "area card has cross-shaped impact effect")
	for victim: Dictionary in victims: check(victim.hp == 4, "area preview matches real health")
	for effect: Dictionary in game.board.effects:
		if effect.kind == "fire_area": check(effect.from == caster.pos and effect.cells.size() == 5, "cast starts at legal friendly source with exact cross footprint")
	await create_timer(0.40).timeout; await capture("area-spell-impact")
	await pause_for_demo()
	# Terminal state is authoritative immediately, while its panel waits for the final strike.
	await stage()
	var sword: Dictionary = troop("sword", Vector2i(4, 5))
	var leader: Dictionary = game.battle.commander(1); leader.pos = Vector2i(5, 5); leader.hp = 1
	await select(sword); await click(game.board.global_position + game.board.cell_center(leader.pos))
	check(game.battle.winner == 0 and game.board.is_presenting(), "winning action resolves before animation ends")
	check(not game.get_node("%ResultOverlay").visible, "victory panel does not cover final strike")
	before = immutable_state()
	var final_clock: float = game.battle.time_remaining
	await create_timer(0.40).timeout; await capture("final-strike-before-result")
	await create_timer(1.25).timeout
	check(game.get_node("%ResultOverlay").visible and not game.board.is_presenting(), "victory panel appears after final animation")
	check(before == immutable_state() and game.battle.time_remaining == final_clock, "waiting for victory does not mutate result or advance turn clock")
	await capture("final-strike-result"); await pause_for_demo()
	# Restart during a pending result cannot show an old winner later.
	await stage(); sword = troop("sword", Vector2i(4, 5)); leader = game.battle.commander(1); leader.pos = Vector2i(5, 5); leader.hp = 1
	await select(sword); await click(game.board.global_position + game.board.cell_center(leader.pos))
	game._new_match(78); await create_timer(1.4).timeout
	check(game.battle.winner == -1 and not game.get_node("%ResultOverlay").visible and not game.board.is_presenting(), "restart cancels old terminal presentation without stale callbacks")
	# The same presentation boundary works when a card, not a normal attack, wins.
	await stage(); troop("mage", Vector2i(4, 5)); leader = game.battle.commander(1); leader.pos = Vector2i(5, 5); leader.hp = 1
	await select_card(give("bolt")); await click(game.board.global_position + game.board.cell_center(leader.pos))
	check(game.battle.winner == 0 and effect_exists("fire_cast") and not game.get_node("%ResultOverlay").visible, "lethal spell keeps its impact visible")
	await create_timer(1.4).timeout
	check(game.get_node("%ResultOverlay").visible, "lethal spell eventually shows result")
	print("FEEDBACK POLISH CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
