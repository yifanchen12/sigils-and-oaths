extends "res://tests/test_action_poses.gd"

func inspect_cast(actor_id: int, brace: bool) -> void:
	check(not game.board.casting_pose.is_empty(), "cast has an actor timeline")
	if game.board.casting_pose.is_empty(): return
	check(game.board.casting_pose.unit_id == actor_id, "pose belongs to actual casting source")
	game.board.set_process(false)
	var state: String = immutable_state()
	for sample: Array in [[-0.01, -1], [0.0, 0], [0.139, 0], [0.14, 0 if brace else 1], [0.449, 0 if brace else 1], [0.45, 2], [0.719, 2], [0.72, -1]]:
		game.board.casting_pose.age = sample[0]
		check(game.board.cast_pose(actor_id) == sample[1], "cast boundary " + str(sample[0]))
	check(game.board.cast_pose(-999) == -1 and state == immutable_state(), "cast sampling cannot alter rules or another actor")
	game.board.casting_pose.age = 0.20
	game.board.queue_redraw()
	await capture("cast-pose-" + str(game.battle.hero(0).id if game.battle.get_unit(actor_id).kind == "commander" else game.battle.get_unit(actor_id).kind))
	game.board.set_process(true)
	await create_timer(1.2).timeout
	check(game.board.casting_pose.is_empty() and game.board.cast_pose(actor_id) == -1 and state == immutable_state(), "cast expires without repeat damage, healing or payment")

func run() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("cast pose timeout"); quit(2))
	inspect_atlas()
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/cast_pose_deck.json")
	root.add_child(game); current_scene = game
	for kind: String in ["archer", "mage", "healer"]:
		await show_strike(kind, "mage")
	await show_strike("archer", "archer", true)
	for kind: String in ["mage", "healer", "sword", "spear"]:
		await stage()
		var actor: Dictionary = troop(kind, Vector2i(4, 5))
		var target: Dictionary = troop("sword", Vector2i(5, 5), 0 if kind == "healer" else 1)
		if kind == "healer": target.hp = 1
		await select(actor); await key(KEY_Q)
		if kind in ["mage", "healer"]: await click(game.board.global_position + game.board.cell_center(target.pos))
		check(game.battle.players[0].mana == 9, "unit cast spends one mana: " + kind)
		await inspect_cast(actor.id, kind in ["sword", "spear"])
	for hero_id: String in Art.HERO_ORDER:
		game.current_hero = hero_id
		await stage()
		var actor: Dictionary = game.battle.commander(0)
		var target: Dictionary = troop("cavalry" if hero_id == "pyromancer" else "sword", actor.pos + Vector2i(1, 0), 1 if hero_id == "pyromancer" else 0)
		if hero_id != "pyromancer": target.hp = 1
		game._refresh(); await settle()
		await click(game.get_node("%ViewSkill").get_global_rect().get_center())
		if hero_id != "grove": await click(game.board.global_position + game.board.cell_center(target.pos))
		check(game.battle.players[0].mana == 10 - int(game.battle.hero(0).cost), "hero cast pays exactly its cost")
		await inspect_cast(actor.id, hero_id == "warden")
	# A spell is presented by the nearest eligible friendly; weather by the commander.
	game.current_hero = "warden"
	for card_id: String in ["bolt", "rain"]:
		await stage()
		var caster: Dictionary = troop("mage", Vector2i(4, 5))
		var target: Dictionary = troop("sword", Vector2i(6, 5), 1)
		var uid: int = game.battle._id()
		game.battle.players[0].hand.append({"uid": uid, "card_id": card_id})
		var result: Dictionary = game._apply_with_feedback({"type": "play", "card_uid": uid, "target": target.pos if card_id == "bolt" else Vector2i(-1, -1)})
		check(result.ok, "spell fixture accepted " + card_id)
		var expected_id: int = caster.id if card_id == "bolt" else game.battle.commander(0).id
		check(game.board.casting_pose.get("unit_id", -1) == expected_id, "local spell / global weather chooses valid presentation origin")
		game._open_council(); await settle()
		check(game.board.casting_pose.is_empty(), "menu cancels spell actor")
	await stage()
	var guard: Dictionary = troop("spear", Vector2i(4, 5))
	check(game._apply_with_feedback({"type": "unit_skill", "unit_id": guard.id, "target": guard.pos}).ok, "guard fixture accepted")
	game._new_match(72)
	check(game.board.casting_pose.is_empty(), "restart clears cast actor")
	print("CAST POSE CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
