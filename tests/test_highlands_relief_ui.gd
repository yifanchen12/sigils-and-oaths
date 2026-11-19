extends "res://tests/test_frontier_relief_ui.gd"

func run() -> void:
	DisplayServer.window_set_size(Vector2i(1296, 900))
	game = MainScene.instantiate()
	game.deck_store = Store.new("user://highlands-test-deck.json")
	game.settings_store = Settings.new("user://highlands-test-settings.cfg")
	check(game.settings_store.save_preferences({"reduce_motion": true}).ok, "isolated preferences")
	root.add_child(game)
	game.audio.stop_playback()
	current_scene = game
	await settle()
	for id: String in ["ridgepass", "sunspire", "citadel"]:
		if await enter_map(id):
			check(game.board.find_children("*", "Node3D", true, false).is_empty(), "flat tactical board " + id)
			match id:
				"ridgepass": await test_pass()
				"sunspire": await test_solar_gate()
				"citadel": await test_court()
		if id != "citadel":
			game._open_council()
			await settle()
	print("HIGHLANDS RELIEF UI: %d CHECKS | FAILURES: %d" % [checks, failures])
	await finish_relief_test()

func test_pass() -> void:
	var battle: Battle = game.battle
	var archer := place(battle, "archer", Vector2i(5, 3))
	var hill := Vector2i(5, 4)
	var peak := Vector2i(4, 3)
	var target := place(battle, "spear", Vector2i(9, 4), 1)
	game._refresh()
	await settle()
	await click(board_point(archer.pos))
	check(not game.board.moves.has(peak) and game.board.moves.has(hill), "the crag blocks movement and the grassy slope permits it")
	await click(board_point(hill))
	check(archer.pos == hill and battle.attack_range(archer) == 4, "climbing the photographed hill extends actual bow range")
	var hp: int = target.hp
	await click(board_point(target.pos))
	check(target.hp < hp and archer.attacked, "normal shot reaches the fourth tile beyond the pass")

func test_solar_gate() -> void:
	var battle: Battle = game.battle
	var swords := place(battle, "sword", Vector2i(3, 2))
	var gate := Vector2i(3, 3)
	game._refresh()
	await settle()
	await click(board_point(swords.pos))
	check(game.board.moves.has(gate), "the stone gate admits troops")
	await click(board_point(gate))
	check(swords.pos == gate and battle.terrain_defense(swords) == 2, "the actual pylon square provides two defense")
	var trail := Fixture.give(battle, "trail")
	game._refresh()
	await settle()
	await select_hand(trail.uid)
	check(game.board.spell_targets.has(gate) and not game.board.spell_targets.has(Vector2i(0,0)), "a nearby gate can be cleared and the mesa cannot")
	await click(board_point(gate))
	check(battle.ground(gate) == "road" and battle.terrain_defense(swords) == 0 and Artwork.changed_cells(battle) == [gate], "a hand card converts only the pictured fort")

func test_court() -> void:
	var battle: Battle = game.battle
	var anchor := place(battle, "spear", Vector2i(5, 4))
	var deployment := Vector2i(6, 4)
	var trap_site := Vector2i(6, 5)
	var recruit := Fixture.give(battle, "sword")
	game._refresh()
	await settle()
	await select_hand(recruit.uid)
	await click(board_point(deployment))
	var unit: Dictionary = battle.unit_at(deployment)
	check(not unit.is_empty() and unit.get("summoning", false) and battle.distance(deployment, anchor.pos) == 1, "deploy beside the spearman on the compass inlay")
	var trap := Fixture.give(battle, "anchor_snare")
	game._refresh()
	await settle()
	await select_hand(trap.uid)
	await click(board_point(trap_site))
	check(battle.traps.size() == 1 and battle.traps[0].pos == trap_site and battle.hand_card(0,trap.uid).is_empty(), "trap placed from hand on the adjacent mosaic square")
