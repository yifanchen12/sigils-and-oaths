extends SceneTree

const Session = preload("res://scripts/campaign_session.gd")
const Store = preload("res://scripts/campaign_store.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const AI = preload("res://scripts/opponent.gd")
const PATH: String = "res://.tools/test_battle_save.json"
const CROSS_PATH: String = "res://.tools/cross_process_battle.json"
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(label)

func cleanup(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func write_raw(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()

func road_session(path: String) -> RefCounted:
	var session: RefCounted = Session.new(path)
	session.new_campaign()
	while session.current().type == "dialogue": session.advance(session.token())
	session.choose("road", session.token())
	while session.current().type == "dialogue": session.advance(session.token())
	return session

func rich_session(path: String) -> RefCounted:
	var session: RefCounted = road_session(path)
	session.begin_battle(session.token())
	session.encounter = Fixture.rich()
	return session

func test_storage_and_migration() -> bool:
	cleanup(PATH)
	var session: RefCounted = road_session(PATH)
	var checkpoint: Dictionary = session.campaign.snapshot()
	write_raw(PATH, {"version": 1, "progress": checkpoint})
	var old_file: String = FileAccess.get_file_as_string(PATH)
	var loaded: Dictionary = Store.new(PATH).load_progress()
	check(loaded.ok and loaded.get("migrated", false) and loaded.encounter.is_empty(), "v1 migrates to an explicit empty encounter")
	check(FileAccess.get_file_as_string(PATH) == old_file, "loading v1 does not rewrite the source file")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.encounter == null and fresh.current().type == "battle", "old chapter checkpoint still starts at briefing")
	check(fresh.begin_battle(fresh.token()).ok and fresh.encounter != null, "old save can enter a new full-save battle")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(PATH)).version) == Store.VERSION, "next successful write upgrades to current schema")
	session = rich_session(PATH)
	var before: Dictionary = Snapshot.capture(session.encounter)
	check(session.save().ok, "complex mid-battle state persists")
	check(fresh.load_campaign().ok and Snapshot.capture(fresh.encounter) == before, "fresh session restores every battle field")
	var valid_file: String = FileAccess.get_file_as_string(PATH)
	var data: Dictionary = JSON.parse_string(valid_file)
	var legacy: Dictionary = data.duplicate(true)
	legacy.version = 2; legacy.progress.erase("completed"); legacy.progress.story.erase("line_id")
	legacy.encounter.battle.version = 1; legacy.encounter.battle.erase("objective")
	write_raw(PATH, legacy)
	var legacy_file: String = FileAccess.get_file_as_string(PATH)
	check(fresh.load_campaign().ok and Snapshot.capture(fresh.encounter) == before, "v2 full battle and legacy dialogue cursor migrate without board drift")
	check(FileAccess.get_file_as_string(PATH) == legacy_file, "loading v2 does not rewrite it")
	check(fresh.save().ok and int(JSON.parse_string(FileAccess.get_file_as_string(PATH)).version) == Store.VERSION, "next save upgrades full battle schema")
	valid_file = FileAccess.get_file_as_string(PATH)
	data = JSON.parse_string(valid_file)
	var wrong: Dictionary = data.encounter.duplicate(true); wrong.scenario = "c01_river"
	check(not Store.new(PATH).save_progress(data.progress, wrong).ok and FileAccess.get_file_as_string(PATH) == valid_file, "wrong scenario cannot overwrite progress")
	wrong = data.encounter.duplicate(true); wrong.revision += 1
	check(not Store.new(PATH).save_progress(data.progress, wrong).ok, "wrong story revision rejected")
	wrong = data.encounter.duplicate(true); wrong.battle.match_seed += 1
	check(not Store.new(PATH).save_progress(data.progress, wrong).ok, "wrong battle seed rejected")
	wrong = data.encounter.duplicate(true); wrong.battle.players[1].identity.name = "别处的守卫"
	check(not Store.new(PATH).save_progress(data.progress, wrong).ok, "wrong NPC identity rejected")
	wrong = data.encounter.duplicate(true); wrong.battle.players[0].hero_id = "grove"
	check(not Store.new(PATH).save_progress(data.progress, wrong).ok, "wrong hero class rejected")
	# Save a last-good copy, then break the newest board rather than its JSON syntax.
	check(session.save().ok, "last-good full board backup created")
	data = JSON.parse_string(valid_file); data.encounter.battle.units[0].pos = [-1, 0]
	write_raw(PATH, data)
	loaded = Store.new(PATH).load_progress()
	check(loaded.ok and loaded.get("recovered", false) and loaded.encounter.battle == before, "invalid newest board recovers full previous board")
	check(session.save().ok, "repaired snapshot can replace corrupt primary")
	data = JSON.parse_string(FileAccess.get_file_as_string(PATH)); data.encounter.battle.version = 1000000001
	write_raw(PATH, data)
	var protected_file: String = FileAccess.get_file_as_string(PATH)
	check(Store.new(PATH).load_progress().get("protected", false), "future battle schema protects outer v2 save")
	check(not session.save().ok and FileAccess.get_file_as_string(PATH) == protected_file, "future battle schema cannot be overwritten")
	data.encounter.battle.version = Snapshot.VERSION; data.encounter.battle.rules = "f".repeat(64)
	write_raw(PATH, data)
	check(Store.new(PATH).load_progress().get("protected", false) and not session.new_campaign().ok, "changed rules protect both loading and new-game overwrite")
	cleanup(PATH)
	return true

func test_autosave_and_resume() -> bool:
	cleanup(PATH)
	var session: RefCounted = rich_session(PATH)
	check(session.save().ok, "autosave fixture starts")
	var original: RefCounted = session.encounter
	var before_file: String = FileAccess.get_file_as_string(PATH)
	original.advance_clock(2)
	check(not session.autosave_tick(2).saved and FileAccess.get_file_as_string(PATH) == before_file, "clock saving is throttled")
	check(not session.autosave_tick(-1).saved and not session.autosave_tick(NAN).saved, "invalid autosave delta ignored")
	original.advance_clock(3)
	check(session.autosave_tick(3).saved, "five active seconds persist the actual timer")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.encounter.time_remaining == original.time_remaining, "timer not reset to ninety on load")
	check(session.leave_battle().ok and session.suspended, "switching mode saves and suspends")
	before_file = FileAccess.get_file_as_string(PATH)
	check(not session.autosave_tick(100).saved and FileAccess.get_file_as_string(PATH) == before_file, "suspended battle is not periodically rewritten")
	check(session.resume_encounter().battle == original and not session.suspended, "returning from skirmish preserves same board")
	var old_instance: RefCounted = session.encounter
	check(session.load_campaign().ok and session.encounter != old_instance, "disk reload gets a separate battle instance")
	check(not session.finish_battle(old_instance).ok, "old-instance result rejected after disk reload")
	# Actual spell action, then the same save hook invoked by Main's changed signal.
	var healer: Dictionary = session.encounter.unit_at(Vector2i(6, 5))
	check(session.encounter.apply_action({"type": "unit_skill", "unit_id": healer.id, "target": healer.pos}).ok, "restored healer can use a real skill")
	check(session.save().ok and fresh.load_campaign().ok, "accepted action saves and reloads")
	check(fresh.encounter.get_unit(healer.id).skill_used and fresh.encounter.get_unit(healer.id).hp == healer.hp, "skill use and healing cannot be replayed after load")
	before_file = FileAccess.get_file_as_string(PATH)
	session.store.path = "res://.tools/__battle_missing_dir__/save.json"
	check(not session.save().ok and session.unsaved, "failed disk write visible")
	check(FileAccess.get_file_as_string(PATH) == before_file, "failed save preserves actual last-good file")
	check(not session.leave_battle().ok and not session.suspended, "failed mode-switch save leaves session active")
	session.store.path = PATH
	check(session.save().ok and not session.unsaved, "manual retry clears failure after successful write")
	# A terminal snapshot loaded before the story callback is applied exactly once.
	session.encounter.commander(1).hp = 0
	session.encounter._cleanup(); session.encounter._check_winner()
	check(session.save().ok, "terminal snapshot can be saved before narrative acknowledgement")
	check(fresh.load_campaign().ok and fresh.encounter == null and fresh.current().node == "road_after", "terminal reload applies story victory once")
	check(fresh.campaign.story.state.flags.seal_copy and fresh.campaign.story.state.attempts.road_battle == 1, "terminal reload grants one evidence fact and one attempt")
	check(fresh.load_campaign().ok and fresh.campaign.story.state.attempts.road_battle == 1, "subsequent reload cannot grant the result again")
	cleanup(PATH)
	return true

func write_cross_process() -> bool:
	cleanup(CROSS_PATH)
	var session: RefCounted = rich_session(CROSS_PATH)
	check(session.save().ok, "first process saves full rich battle")
	return true

func read_cross_process() -> bool:
	var session: RefCounted = Session.new(CROSS_PATH)
	check(session.load_campaign().ok and session.encounter != null, "second process loads a full battle")
	if session.encounter == null: return false
	var expected: RefCounted = Fixture.rich()
	var actual: RefCounted = session.encounter
	check(Snapshot.capture(actual) == Snapshot.capture(expected), "second process restores exact independent baseline")
	check(actual.apply_action({"type": "end_turn"}).ok and expected.apply_action({"type": "end_turn"}).ok, "both continue to enemy turn")
	check(Snapshot.capture(actual) == Snapshot.capture(expected), "new draw and turn-start effects match after process restart")
	var choice: Dictionary = AI.choose(actual)
	check(choice == AI.choose(expected), "restored AI chooses same legal action")
	check(actual.apply_action(choice).ok and expected.apply_action(choice).ok, "AI continuation resolves normally")
	check(Snapshot.capture(actual) == Snapshot.capture(expected), "AI result remains exactly equal")
	for index: int in range(8): check(actual.rng.randi() == expected.rng.randi(), "cross-process future RNG " + str(index))
	check(session.save().ok, "restored game remains saveable after continued action")
	cleanup(CROSS_PATH)
	return true

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--write"): check(write_cross_process(), "writer completed")
	elif args.has("--read"): check(read_cross_process(), "reader completed")
	else:
		check(test_storage_and_migration(), "storage tests completed")
		check(test_autosave_and_resume(), "resume tests completed")
	print("FULL BATTLE SAVE CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
