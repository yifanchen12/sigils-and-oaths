extends SceneTree

const Session = preload("res://scripts/campaign_session.gd")
const Difficulty = preload("res://scripts/campaign_difficulty.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")
const AI = preload("res://scripts/opponent.gd")
const OLD_BATTLE := "res://tests/fixtures/v051-active-bridge.json"
const OLD_ARMORY := "res://tests/fixtures/v050-active-armory.json"
const OLD_HISTORY := "res://tests/fixtures/v048-completed-main.json"

var checks: int = 0
var failures: int = 0
var save_path: String = "res://.tools/v052-difficulty-%d.json" % OS.get_process_id()

func _initialize() -> void: call_deferred("run")

func check(condition: bool, task: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error(task)
	return condition

func run() -> void:
	var catalog: RefCounted = Session.Campaign.new()
	test_openings(catalog)
	test_objectives(catalog)
	test_loading_and_retry()
	test_history()
	for path: String in [save_path, save_path + ".bak", save_path + ".tmp", save_path + ".fake", save_path + ".branch"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("CAMPAIGN DIFFICULTY %d CHECKS | %d FAILURES" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_openings(catalog: RefCounted) -> void:
	for id: String in catalog.index.scenarios:
		var setup: Dictionary = catalog.index.scenarios[id]
		check(Session.Campaign.validate_scenario(setup).is_empty(), "valid authored scenario in both modes: " + id)
		var standard: Dictionary = Session.create_encounter(setup)
		var story: Dictionary = Session.create_encounter(setup, "", {}, Difficulty.STORY)
		if not check(standard.ok and story.ok, "both modes use the real encounter factory: " + id): continue
		var original: Battle = standard.battle
		var assisted: Battle = story.battle
		var blue: Dictionary = original.players[0]
		var support: Dictionary = assisted.players[0]
		check(support.mana == blue.mana + 2 and support.max_mana == blue.max_mana + 2, "story opens with the promised mana and cap: " + id)
		check(assisted.commander(0).shield == mini(5, int(original.commander(0).shield) + 2), "shield cap applies: " + id)
		check(assisted.turn == 1 and assisted.time_remaining == 90 and assisted.turn_time_limit == 90, "original per-turn clock remains: " + id)
		check(original.players[1] == assisted.players[1] and original.rng.state == assisted.rng.state and original.next_id == assisted.next_id, "opponent opener and allocator remain exact: " + id)
		check(blue.hand == support.hand and blue.deck == support.deck and assisted.terrain == original.terrain, "same cards and terrain: " + id)
		var objective: Script = original.ControlObjective
		if setup.has("story_control"):
			check(objective.config(assisted.objective) == objective.config(setup.story_control) and Difficulty.objective_for(setup, Difficulty.STORY) != setup.objective, "briefing and board share the authored variant: " + id)
		elif objective.has_deadline(original.objective):
			check(assisted.objective.round_limit == original.objective.round_limit + 3 and assisted.objective.cells == original.objective.cells, "standard timed goal receives three extra rounds: " + id)
		else:
			check(assisted.objective == original.objective, "commander victory is retained: " + id)
		check(Snapshot.validate(Snapshot.capture(assisted)).ok, "new opener survives snapshot validation: " + id)
	var court: Dictionary = catalog.index.scenarios.c06_court.duplicate(true)
	court["commander_shield"] = 3
	court["bonus_card"] = "lantern_stretcher"
	var army: Dictionary = {"vanguard": "petal_signal", "company": "cairn_curtain"}
	var setup: Dictionary = Session.create_encounter(court, "dawn_weir", army, Difficulty.STORY)
	if check(setup.ok, "story mode opens with authored aid, a requisition and two armory cards"):
		var battle: Battle = setup.battle
		check(battle.commander(0).shield == 5, "opening aid stacks up to the display cap")
		var blue: Dictionary = battle.players[0]
		check(blue.hand.any(func(card: Dictionary) -> bool: return card.card_id == "dawn_weir") and blue.hand.back().card_id == "lantern_stretcher", "opening hand retains both preparations")
		check(blue.deck[-2].card_id == "petal_signal" and blue.deck[-5].card_id == "cairn_curtain", "ordinary draw positions stay precise")
	check(not Session.create_encounter(court, "", {}, "invalid").ok, "encounter factory rejects unknown difficulty")

func test_objectives(catalog: RefCounted) -> void:
	var bridge: Battle = Session.create_encounter(catalog.index.scenarios.c01_bridge, "", {}, Difficulty.STORY).battle
	for action: int in range(10): bridge.end_turn()
	check(bridge.winner == -1 and bridge.objective.last_check == 11 and bridge.objective.streak == 0 and Snapshot.validate(Snapshot.capture(bridge)).ok, "untimed hold can continue through multiple missed checks")
	for cell: Array in bridge.objective.cells:
		Fixture.troop(bridge, "sword", bridge.ControlObjective.position(cell))
	check(bridge.end_turn().ok and bridge.winner == -1, "both objectives must survive the red turn")
	check(bridge.end_turn().ok and bridge.winner == 0 and bridge.objective.streak == 1 and Snapshot.validate(Snapshot.capture(bridge)).ok, "two occupied points win at the next blue turn")
	var timed: Dictionary = catalog.index.scenarios.c02_relief_bridge
	var standard: Battle = Session.create_encounter(timed).battle
	var story: Battle = Session.create_encounter(timed, "", {}, Difficulty.STORY).battle
	for action: int in range(24):
		standard.end_turn()
		story.end_turn()
	check(standard.winner == 1 and story.winner == -1 and story.turn == 25, "only the standard mission expires after twelve full rounds")
	for action: int in range(6): story.end_turn()
	check(story.winner == 1 and story.turn == 31, "story mission expires after fifteen full rounds")
	for id: String in ["c07_saltlane_school", "c17_screen"]:
		var invalid: Dictionary = catalog.index.scenarios[id].duplicate(true)
		invalid.control.round_limit = 0
		check(not Session.Campaign.validate_scenario(invalid).is_empty(), "linear objective still requires a real deadline: " + id)

func test_loading_and_retry() -> void:
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_BATTLE))
	var session = Session.new(OLD_BATTLE)
	if not check(old.version == 5 and session.load_campaign().ok and session.encounter != null, "executable-generated v0.51 bridge save opens"): return
	var original: Dictionary = JSON.parse_string(JSON.stringify(Snapshot.capture(session.encounter), "", true, true))
	var expected: Dictionary = old.encounter.battle.duplicate(true)
	expected.version = float(Snapshot.VERSION)
	expected.rules = Snapshot.rules_signature()
	for unit: Dictionary in expected.units:
		var card_id: String = unit.get("card", {}).get("card_id", "")
		if preload("res://scripts/card_names.gd").PREVIOUS.get(card_id, "") == unit.name:
			unit.name = Snapshot.Model.CATALOG.find(card_id).name
	check(original == expected and session.encounter.hand_played_this_turn and session.campaign.difficulty == Difficulty.STANDARD, "mid-turn card flag, timer, board and legacy rule restore exactly")
	check(Session.new(OLD_ARMORY).load_campaign().ok, "actual 0.50 armory save also opens")
	var short_save = Session.new(save_path)
	if not check(short_save.store.save_progress(old.progress).ok and short_save.load_campaign().ok, "earned bridge briefing loads into isolated slot"): return
	var token: Dictionary = short_save.token()
	var digest: String = FileAccess.get_sha256(save_path)
	check(not short_save.choose_difficulty("invalid", token).ok and FileAccess.get_sha256(save_path) == digest and short_save.token() == token, "invalid option is harmless")
	var failed = Session.new("res://.tools/v052-nonexistent-dest/session.json")
	if check(failed.campaign.restore(old.progress).ok, "can inspect a legitimate briefing even if output is unusable"):
		var prior: Dictionary = failed.token()
		check(not failed.choose_difficulty(Difficulty.STORY, prior).ok and failed.token() == prior and failed.campaign.difficulty == Difficulty.STANDARD, "failed save leaves mode and token unchanged")
	if not check(short_save.choose_difficulty(Difficulty.STORY, token).ok and short_save.token() != token, "difficulty switch commits atomically and invalidates old actions"): return
	check(not short_save.begin_battle(token).ok, "stale briefing cannot launch")
	var loaded = Session.new(save_path)
	if not check(loaded.load_campaign().ok and loaded.campaign.difficulty == Difficulty.STORY and loaded.encounter == null, "restart keeps the pre-battle choice"): return
	if not check(loaded.begin_battle(loaded.token()).ok and loaded.encounter.objective.round_limit == 0, "normal launch applies the alternative goal"): return
	loaded.encounter.advance_clock(8.25)
	var active: Dictionary = Snapshot.capture(loaded.encounter)
	if not check(loaded.leave_battle().ok and not loaded.choose_difficulty(Difficulty.STANDARD, loaded.token()).ok, "parked battle rejects difficulty changes"): return
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(file.version == Session.Store.VERSION and file.progress.difficulty == Difficulty.STORY and file.encounter.difficulty == Difficulty.STORY, "both parts of persistent state agree")
	var forged: Dictionary = file.encounter.duplicate(true)
	forged.erase("difficulty")
	digest = FileAccess.get_sha256(save_path)
	check(not loaded.store.save_progress(file.progress, forged).ok and FileAccess.get_sha256(save_path) == digest, "forged encounter difficulty cannot overwrite the save")
	forged = file.encounter.duplicate(true)
	forged.battle.objective.required = 2
	check(not loaded.store.save_progress(file.progress, forged).ok and FileAccess.get_sha256(save_path) == digest, "altered objective cannot overwrite the save")
	var invalid_legacy := FileAccess.open(save_path + ".fake", FileAccess.WRITE)
	invalid_legacy.store_string(JSON.stringify(file.merged({"version": 5}, true)))
	invalid_legacy.close()
	check(not Session.Store.new(save_path + ".fake").load_progress().ok, "story state cannot be presented as a v0.51 save")
	var resumed = Session.new(save_path)
	if not check(resumed.load_campaign().ok and resumed.campaign.difficulty == Difficulty.STORY and Snapshot.capture(resumed.encounter) == active, "new session opens the exact saved battle"): return
	var battle: Battle = resumed.encounter
	for action: int in range(700):
		if battle.winner != -1: break
		if not check(battle.apply_action({"type": "end_turn"} if battle.active_side == 0 else AI.choose(battle)).ok, "real defeat uses only legal actions"): return
	if not check(battle.winner == 1 and resumed.finish_battle(battle).ok and resumed.current().attempts == 1, "defeat leaves the story at the same briefing"): return
	check(resumed.choose_difficulty(Difficulty.STANDARD, resumed.token()).ok and resumed.begin_battle(resumed.token()).ok, "retry can switch back to standard")
	check(resumed.encounter.objective.is_empty() and resumed.encounter.players[0].mana == 1 and resumed.encounter.time_remaining == 90, "retry rebuilds the corresponding objective, mana and clock")

func test_history() -> void:
	var legacy = Session.new(OLD_HISTORY)
	if not check(legacy.load_campaign().ok, "published completed story is available for branch testing"): return
	var source: Dictionary = legacy.campaign.snapshot()
	source.completed[0]["difficulty"] = Difficulty.STORY
	source["difficulty"] = Difficulty.STANDARD
	var primary = Session.new(save_path)
	if not check(primary.store.save_progress(source).ok and primary.load_campaign().ok, "history records the earlier choice"): return
	var sha: String = FileAccess.get_sha256(save_path)
	var branch = Session.new(save_path + ".branch")
	if not check(branch.start_replay_from(primary, "chapter_02").ok, "start chapter two in a separate branch slot"): return
	check(branch.campaign.difficulty == Difficulty.STORY and branch.campaign.story.graph.id == "chapter_02", "chapter replay inherits the previous chapter's setting")
	check(primary.campaign.difficulty == Difficulty.STANDARD and FileAccess.get_sha256(save_path) == sha, "main story slot is untouched by its replays")
	source.completed[0].difficulty = 2
	check(not primary.campaign.restore(source).ok, "historical mode type is validated")
