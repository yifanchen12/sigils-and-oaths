extends "res://tests/test_unit_skills_ui.gd"

const CastArt = preload("res://scripts/cast_art.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const Settings = preload("res://scripts/settings_store.gd")

func effect_of(kind: String) -> Dictionary:
	for effect: Dictionary in game.board.effects:
		if effect.kind == kind: return effect
	return {}

func play(card_id: String, target: Vector2i, side: int = 0) -> Dictionary:
	var card := Fixture.give(game.battle,card_id,side)
	return game._apply_with_feedback({"type":"play","card_uid":card.uid,"target":target})

func exercise_skills() -> void:
	for kind: String in CastArt.SKILLS:
		await stage()
		var home := Vector2i(5,5)
		var actor := troop(kind,home)
		var friend := troop("sword",Vector2i(4,5))
		friend.hp -= 2
		var foe := troop("spear",Vector2i(6,5),1)
		var target := home
		if kind in ["mage","archer"]: target = foe.pos
		elif kind == "healer": target = friend.pos
		elif kind == "cavalry":
			actor.moved = true
			actor.last_move_distance = 1
			target = game.battle.skill_targets(actor)[0]
		check(game._apply_with_feedback({"type":"unit_skill","unit_id":actor.id,"target":target}).ok,"legal skill " + kind)
		var effect := effect_of(CastArt.SKILLS[kind])
		check(effect.get("from") == home and effect.get("cell") == target, "correct launch and landing for " + kind)
		check(effect.get("title") == game.battle.unit_skill(actor).name and CastArt.Art.get_texture(effect.portrait) != null,
			"the skill cut-in uses the actor's portrait and actual skill name")
		if kind == "spear":
			check(effect.guard and effect.cells.has(friend.pos) and not effect.cells.has(foe.pos), "the guard links only to adjacent friendly pieces")
		if kind == "cavalry": check(actor.pos == target and actor.skill_used,"the charge arrives on the actual second move")
		check(game.battle.players[0].mana == 9, "one skill payment " + kind)

func exercise_cards() -> void:
	for ally_branch: bool in [true,false]:
		await stage()
		var source := troop("mage",Vector2i(5,5))
		var target := troop("archer",Vector2i(5,3),0 if ally_branch else 1)
		target.hp -= 2
		check(play("hinge_order",target.pos).ok,"play either branch of the same original card")
		var effect := effect_of("heal_cast" if ally_branch else "frost_cast")
		check(not effect.is_empty() and effect.cell == target.pos, "branch determines the visible element")
		if not ally_branch: check(effect.from == source.pos and target.rooted_turns > 0,"binding originates at the nearby allied mage")
	await stage()
	troop("mage",Vector2i(5,5))
	var other := troop("sword",Vector2i(6,4),1)
	check(play("quay_signal",other.pos).ok,"offensive order accepted")
	var row := effect_of("fire_area")
	check(row.cells == game.battle.Formation.footprint(game.battle,other.pos,2,"row"),"enemy choice draws the actual horizontal footprint")
	await stage()
	troop("mage",Vector2i(5,5))
	other = troop("spear",Vector2i(6,4),1)
	check(play("glass_treaty",other.pos).ok,"a ten-mana order resolves")
	var treaty := effect_of("fire_area")
	check(treaty.get("title") == game.battle.definition("glass_treaty").name and treaty.portrait == "glass_treaty","high-cost cut-in uses the played card")
	await stage()
	game.board.reset_effects()
	check(play("rain",Vector2i(-1,-1)).ok,"weather played from hand")
	var weather := effect_of("weather_cast")
	check(weather.weather == "rain" and weather.cell == game.battle.commander(0).pos,"weather enters at the commander and uses the full-board cue")
	await stage()
	var anchor := troop("mage",Vector2i(5,5))
	var empty := Vector2i(5,4)
	check(play("sword",empty).ok and effect_of("arrival_cast").cell == empty, "a playable recruit arrives on its own tile")
	game.board.reset_effects()
	check(play("anchor_snare",Vector2i(4,5)).ok and effect_of("snare_cast").from == anchor.pos, "the player's hand trap can show its placement")
	game.board.reset_effects()
	game.battle.end_turn()
	troop("spear",Vector2i(4,2),1)
	check(play("anchor_snare",Vector2i(4,3),1).ok and game.board.effects.is_empty() and game.board.casting_pose.is_empty(), "enemy placement reveals neither its position nor its caster")

func exercise_accessibility() -> void:
	await stage()
	game.board.set_reduced_motion(true)
	var source := troop("mage",Vector2i(5,5))
	var target := troop("spear",Vector2i(5,3),1)
	check(play("frostbind",target.pos).ok,"accessible cast succeeds")
	var frozen := effect_of("frost_cast")
	check(frozen.from == source.pos and frozen.duration <= 0.5 and game.board.casting_pose.is_empty(),"short, static target marker in reduced motion")
	game.board.set_process(false)
	var before := immutable_state()
	game.board._process(1.5)
	check(before == immutable_state() and game.board.effects.is_empty(),"presentation expiry never reapplies a spell or changes RNG")
	game.board.set_reduced_motion(false)
	game.board.set_process(true)
	await stage()
	source = troop("mage",Vector2i(5,5))
	var card := Fixture.give(game.battle,"frostbind")
	check(not game._apply_with_feedback({"type":"play","card_uid":card.uid,"target":source.pos}).ok and game.board.effects.is_empty(),"an illegal target produces no cast cue")

func exercise_commanders() -> void:
	for id: String in ["warden","pyromancer","grove"]:
		game.current_hero = id
		await stage()
		var leader: Dictionary = game.battle.commander(0)
		var near: Vector2i = leader.pos + Vector2i.UP
		var target := troop("spear",near,int(id == "pyromancer"))
		target.hp -= 2
		var cell: Vector2i = Vector2i(-1,-1) if id == "grove" else near
		check(game._apply_with_feedback({"type":"hero","target":cell}).ok,"commander can use " + id)
		var style: String = {"warden":"ward_cast","pyromancer":"fire_cast","grove":"heal_cast"}[id]
		var effect := effect_of(style)
		check(effect.get("title") == game.battle.hero(0).skill and effect.from == leader.pos,"commander's own name and origin " + id)
		check(effect.cells.has(near),"the affected piece appears in the commander effect")

func run() -> void:
	game = MainScene.instantiate()
	game.deck_store = Store.new("user://cast-art-test-deck.json")
	game.settings_store = Settings.new("user://cast-art-test-settings.cfg")
	root.add_child(game)
	game.audio.stop_playback()
	current_scene = game
	game.board.set_reduced_motion(false)
	await exercise_skills()
	await exercise_cards()
	await exercise_commanders()
	await exercise_accessibility()
	var atlas: Image = CastArt.ATLAS.get_image()
	check(atlas != null and atlas.get_size() == Vector2i(1536,1024) and atlas.get_pixel(1,1).a < 0.01,"packaged atlas retains clear margins")
	print("CAST ART UI: %d CHECKS | FAILURES: %d" % [checks,failures])
	game.audio.stop_playback()
	await create_timer(0.15,true,false,true).timeout
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
