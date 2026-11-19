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
			check(effect.guard and effect.signature == CastArt.Signature.GUARD and effect.cells.has(friend.pos) and not effect.cells.has(foe.pos), "the spear-and-shield links only to adjacent friendly pieces")
		else: check(effect.stroke == CastArt.TROOP_STROKES[kind], "the skill uses its own painted stroke: "+kind)
		if kind == "cavalry":
			check(actor.pos == target and actor.skill_used,"the charge arrives on the actual second move")
			check(effect.rider == actor.id and effect.route == game.battle.last_movement_path and effect.route.front() == home, "hoof marks follow the resolved route")
		if kind == "archer": check(game.board.combat.precision,"a precision shot replaces the ordinary projectile")
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
		check(effect.stroke == (CastArt.Stroke.LEAVES if ally_branch else CastArt.Stroke.ICE), "the same hand card chooses its stroke from its resolved branch")
		check(effect.cost == game.battle.definition("hinge_order").cost and effect.title == game.battle.definition("hinge_order").name, "even inexpensive cards show their real title and cost")
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
	check(play("anchor_snare",Vector2i(4,5)).ok and effect_of("snare_cast").from == anchor.pos and effect_of("snare_cast").signature == CastArt.Signature.MOORING, "the player's tile trap springs a rope on its own tile")
	game.board.reset_effects()
	game.battle.end_turn()
	troop("spear",Vector2i(4,2),1)
	check(play("anchor_snare",Vector2i(4,3),1).ok and game.board.effects.is_empty() and game.board.casting_pose.is_empty(), "enemy placement reveals neither its position nor its caster")

func exercise_interceptions() -> void:
	await stage()
	var ally := troop("sword",Vector2i(5,5))
	var enemy := troop("sword",Vector2i(6,4),1)
	var cell := Vector2i(5,4)
	check(play("gate_veteran",cell).ok,"deploy the guard directly from hand")
	var guard := effect_of("ward_cast")
	check(guard.get("signature") == CastArt.Signature.GUARD and guard.cell == cell and guard.cells.has(ally.pos) and not guard.cells.has(enemy.pos), "entry guard links originate at the summoned spearman")
	game.board.reset_effects()
	check(play("oath_ward",cell).ok and effect_of("snare_cast").signature == CastArt.Signature.COUNTER and not effect_of("snare_cast").get("sprung", false), "a protected ally receives the dormant counter-sigil")
	game.board.reset_effects()
	game.battle.end_turn()
	check(game._apply_with_feedback({"type":"attack","unit_id":enemy.id,"target":cell}).ok, "ordinary attack triggers the face-down ward")
	check(effect_of("snare_cast").get("signature") == CastArt.Signature.COUNTER and effect_of("snare_cast").cell == cell and effect_of("snare_cast").sprung, "reveal the actual ward on its protected defender")
	await stage()
	troop("mage",Vector2i(5,5))
	enemy = troop("sword",Vector2i(4,4),1)
	check(play("anchor_snare",cell).ok,"set the hidden mooring on walkable ground")
	game.board.reset_effects()
	game.battle.end_turn()
	check(game._apply_with_feedback({"type":"move","unit_id":enemy.id,"target":cell}).ok,"an enemy walks onto the actual hand trap")
	check(effect_of("snare_cast").get("signature") == CastArt.Signature.MOORING and effect_of("snare_cast").cell == cell,"the public snare snaps exactly on the stopped unit")
	await stage()
	troop("mage",Vector2i(5,5))
	troop("mage",Vector2i(4,4),1)
	check(play("anchor_snare",cell).ok,"place a second trap for the detection check")
	game.board.reset_effects()
	game.battle.end_turn()
	check(play("reveal_traps",cell,1).ok and game.battle.last_trap_events.size() == 1,"scouting consumes a discovered trap")
	check(not game.board.effects.any(func(e: Dictionary) -> bool: return e.get("signature") == CastArt.Signature.MOORING), "disarming never shows the sprung-trap impact")

func exercise_accessibility() -> void:
	await stage()
	game.board.set_reduced_motion(true)
	var source := troop("mage",Vector2i(5,5))
	var target := troop("spear",Vector2i(5,3),1)
	check(play("frostbind",target.pos).ok,"accessible cast succeeds")
	var frozen := effect_of("frost_cast")
	check(frozen.from == source.pos and frozen.duration <= 0.5 and frozen.stroke == CastArt.Stroke.ICE and game.board.casting_pose.is_empty(),"short, static ice marker in reduced motion")
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

func exercise_weather_and_orders() -> void:
	var skies := {"rain":"rain","fog":"fog","snow":"snow","sun":"sun","open_wind":"tailwind","night_muster":"lanterns"}
	for id: String in skies:
		await stage()
		game.board.set_reduced_motion(id in ["fog","sun"])
		game.audio.stopping = false
		game.audio.set_levels(0,100)
		check(play(id,Vector2i(-1,-1)).ok,"weather accepted from the hand: "+id)
		var effect := effect_of("weather_cast")
		check(effect.get("weather") == skies[id] and effect.previous_weather == "clear" and CastArt.SKY_CELS.has(skies[id]),
				"every weather selects its actual painted cel: "+id)
		if DisplayServer.get_name() != "headless":
			check(game.audio.sfx.get_children().any(func(p: AudioStreamPlayer) -> bool:
				return p.playing and p.stream == game.audio.CUES[game.audio.SKY_CUES[skies[id]]]),"audible weather cue: "+id)
		game.board.reset_effects()
		check(play("clear_skies",Vector2i(-1,-1)).ok,"actual weather can be dispelled: "+id)
		effect = effect_of("weather_cast")
		check(effect.weather == "clear" and effect.previous_weather == skies[id] and game.battle.weather_remaining == 0,
				"clearing disperses precisely the previous weather: "+id)
		if DisplayServer.get_name() != "headless":
			check(game.audio.sfx.get_children().any(func(p: AudioStreamPlayer) -> bool:
				return p.playing and p.stream == game.audio.CUES.clearair),"clearing has a distinct sound")
		game.audio.stop_playback()
		await create_timer(0.10,true,false,true).timeout
	game.board.set_reduced_motion(false)
	await stage()
	var ally := troop("sword",game.battle.commander(0).pos+Vector2i.UP)
	var far := troop("archer",Vector2i(5,3))
	ally.hp -= 2; far.hp -= 2
	check(play("lamplight_shift",Vector2i(-1,-1)).ok and effect_of("weather_cast").recipients == [ally.pos],
			"a global lantern front shows a healing ring only on the wounded local recipient")
	await stage()
	troop("mage",Vector2i(5,5))
	var aim := Vector2i(5,4)
	var job: Array = game.battle.roadwork_cells(aim,game.battle.definition("dike_flagstones"))
	check(not job.is_empty() and play("dike_flagstones",aim).ok,"build the defensive works from hand")
	check(effect_of("works_cast").cells == job and effect_of("weather_cast").is_empty() and game.battle.weather == "clear",
			"an environment with earthworks marks exactly the changed cells")
	await stage()
	troop("mage",Vector2i(5,5))
	var victim := troop("sword",aim,1)
	var shielded := troop("spear",aim+Vector2i.RIGHT,1)
	var friend := troop("archer",aim+Vector2i.LEFT)
	shielded.shield = 5
	victim.hp = 1
	check(play("nova",aim).ok, "use a genuine area fire spell on a mixed formation")
	var burst := effect_of("fire_area")
	check(burst.struck.has(aim) and burst.struck.has(shielded.pos) and not burst.struck.has(friend.pos) and burst.struck.size() == 2,
			"impact cels include a defeated enemy and a shield-only hit but exclude friendly and empty tiles")
	for reduced: bool in [false,true]:
		await stage()
		game.board.set_reduced_motion(reduced)
		troop("mage",Vector2i(5,5))
		victim = troop("spear",aim,1)
		var old_hp: int = victim.hp
		check(play("hollow_hammer",aim).ok and victim.hp == old_hp and effect_of("fire_area").is_empty(), "issuing a hammer order causes no immediate impact")
		var mark := effect_of("signal_cast")
		check(mark.cells == game.battle.Orders.footprint(game.battle,game.battle.pending_orders[0]) and effect_of("weather_cast").is_empty(),
				"a public order shows its actual nine-tile cross on the selected grid")
		game.board.reset_effects()
		check(game._apply_with_feedback({"type":"end_turn"}).ok and effect_of("fire_area").is_empty(),"order stays dormant through the opposing turn")
		check(game._apply_with_feedback({"type":"end_turn"}).ok and not game.battle.last_order_event.is_empty(),"order resolves when the issuer next acts")
		burst = effect_of("fire_area")
		check(burst.cell == aim and burst.cells == mark.cells and burst.struck == [aim] and burst.martial and burst.portrait == "hollow_hammer",
				"ordinary and reduced motion reveal the actual order, footprint and damage at resolution")
	game.board.set_reduced_motion(false)

func exercise_passing_trap() -> void:
	await stage()
	var start := Vector2i(4,4)
	var trapped := start+Vector2i.RIGHT
	var finish := trapped+Vector2i.RIGHT
	for point: Vector2i in [start,trapped,finish]: game.battle.terrain[point] = "plain"
	troop("mage",trapped+Vector2i.DOWN)
	var rider := troop("cavalry",start,1)
	check(play("severed_pullcord",trapped).ok,"place the hand trap that lets a rider pass")
	game.board.reset_effects()
	game.battle.end_turn()
	check(game._apply_with_feedback({"type":"move","unit_id":rider.id,"target":finish}).ok and rider.pos == finish,
			"the mounted unit continues after crossing the trap")
	var reveal := effect_of("snare_cast")
	check(reveal.cell == trapped and is_equal_approx(float(reveal.age),-game.board.action_duration*0.5),
			"the trap springs halfway through this actual three-cell path")
	var contacts := [0]
	var on_contact := func() -> void: contacts[0] += 1
	game.board.trap_contact.connect(on_contact)
	game.board._process(-reveal.age-0.002)
	check(contacts[0] == 0 and reveal.age < 0,"no contact sound occurs before the rider reaches the snare")
	game.board._process(0.004)
	check(contacts[0] == 1,"the snap is sounded on the first presentation tick after crossing")
	game.board._process(game.board.presentation_remaining+0.01)
	check(contacts[0] == 1 and game.board.effects.is_empty(),"the full reaction and message expire without repeating the snap")
	game.board.trap_contact.disconnect(on_contact)

func exercise_contact() -> void:
	await stage()
	troop("mage",Vector2i(5,5))
	var foe := troop("sword",Vector2i(5,3),1)
	foe.hp = 1
	check(play("bolt",foe.pos).ok,"low-cost bolt defeats its target")
	var bolts := effect_of("fire_cast")
	var ghost := effect_of("departing")
	check(bolts.stroke == CastArt.Stroke.FIRE and bolts.cost == 2 and bolts.title == "星火箭", "the actual two-mana card is shown")
	check(not ghost.is_empty() and ghost.actor.id == foe.id and ghost.cell == foe.pos and game.battle.get_unit(foe.id).is_empty(), "the defeated piece stays visible until the incoming spell arrives")
	var state := immutable_state()
	game.board._process(0.33)
	check(effect_of("departing").is_empty() and immutable_state() == state, "contact removes only the visual piece")
	await stage()
	var archer := troop("archer",Vector2i(5,5))
	var victim := troop("mage",Vector2i(5,3),1)
	var guard := troop("spear",Vector2i(6,3),1)
	guard.guarding = true
	check(game._apply_with_feedback({"type":"unit_skill","unit_id":archer.id,"target":victim.pos}).ok,"shoot at the guarded unit")
	var shot := effect_of("shot_cast")
	check(shot.stroke == CastArt.Stroke.ARROW and shot.cell == guard.pos and game.board.combat.forecast.intercepted and victim.hp == victim.max_hp, "the painted arrow follows the real interception")

func check_field_audio() -> void:
	if DisplayServer.get_name() == "headless": return
	for kind: String in ["cavalry","archer","mage","healer","frostbind"]:
		await stage()
		game.audio.stopping = false
		game.audio.set_levels(0,100)
		var actor := troop("mage" if kind == "frostbind" else kind,Vector2i(5,5))
		var aim := troop("spear",Vector2i(5,4),0 if kind=="healer" else 1)
		aim.hp -= 1
		var cell: Vector2i = aim.pos
		if kind == "cavalry":
			actor.moved = true
			actor.last_move_distance = 1
			cell = game.battle.skill_targets(actor)[0]
		var result: Dictionary = play(kind,cell) if kind == "frostbind" else game._apply_with_feedback({"type":"unit_skill","unit_id":actor.id,"target":cell})
		var cue: String = {"cavalry":"canter","archer":"bowstring","mage":"flare","healer":"sprout","frostbind":"rime"}[kind]
		check(result.ok and game.audio.sfx.get_children().any(func(p: AudioStreamPlayer) -> bool:
			return p.playing and p.stream == game.audio.CUES[cue]),"the matching field sound starts on the resolved action: "+cue)
		game.audio.stop_playback()
		await create_timer(0.15,true,false,true).timeout

func exercise_commanders() -> void:
	for id: String in ["warden","pyromancer","grove"]:
		game.current_hero = id
		await stage()
		var leader: Dictionary = game.battle.commander(0)
		var near: Vector2i = leader.pos + Vector2i.UP
		var target := troop("spear",near,int(id == "pyromancer"))
		target.hp -= 2
		var cell: Vector2i = Vector2i(-1,-1) if id == "grove" else near
		if DisplayServer.get_name() != "headless":
			game.audio.stopping = false
			game.audio.set_levels(0,100)
		check(game._apply_with_feedback({"type":"hero","target":cell}).ok,"commander can use " + id)
		if DisplayServer.get_name() != "headless":
			var cue: String = {"warden":"bulwark","pyromancer":"comet","grove":"willow"}[id]
			check(game.audio.sfx.get_children().any(func(p: AudioStreamPlayer) -> bool:
				return p.playing and p.stream == game.audio.CUES[cue]), "the matching commander sound starts at cast time: " + cue)
			game.audio.stopping = true
		var style: String = {"warden":"ward_cast","pyromancer":"fire_cast","grove":"heal_cast"}[id]
		var effect := effect_of(style)
		check(effect.get("title") == game.battle.hero(0).skill and effect.from == leader.pos,"commander's own name and origin " + id)
		check(effect.get("signature") == CastArt.COMMANDER_SIGNATURES[game.battle.hero(0).effect], "the commander uses the right river emblem " + id)
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
	await exercise_interceptions()
	await exercise_commanders()
	await exercise_accessibility()
	await exercise_contact()
	await check_field_audio()
	await exercise_weather_and_orders()
	await exercise_passing_trap()
	var atlas: Image = CastArt.ATLAS.get_image()
	check(atlas != null and atlas.get_size() == Vector2i(1536,1024) and atlas.get_pixel(1,1).a < 0.01,"packaged atlas retains clear margins")
	atlas = CastArt.SIGNATURE_ATLAS.get_image()
	check(atlas != null and atlas.get_size() == Vector2i(1536,1024) and atlas.get_pixel(1,1).a < 0.01, "the six new emblems keep their transparency")
	atlas = CastArt.FIELD_ATLAS.get_image()
	check(atlas.get_size() == Vector2i(1536,1024) and atlas.get_pixel(512,512).a < 0.02, "painted field strokes retain transparent gutters")
	atlas = CastArt.SKY_ATLAS.get_image()
	check(atlas.get_size() == Vector2i(1536,1024) and atlas.get_pixel(512,512).a < 0.025 and CastArt.SKY_CELS.values().size() == 6,"weather atlas is imported with transparent gutters")
	print("CAST ART UI: %d CHECKS | FAILURES: %d" % [checks,failures])
	game.audio.stop_playback()
	await create_timer(0.15,true,false,true).timeout
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
