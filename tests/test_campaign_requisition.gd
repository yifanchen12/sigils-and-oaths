extends SceneTree

const Campaign = preload("res://scripts/campaign.gd")
const Session = preload("res://scripts/campaign_session.gd")
const Store = preload("res://scripts/campaign_store.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Opponent = preload("res://scripts/opponent.gd")
const LEGACY := "res://tests/fixtures/v047-court-encounter.json"
const SLOT := "res://.tools/v048-requisition-rules.json"
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value

func test_all_openings() -> void:
	var catalog = Campaign.new()
	var scenarios: int = 0
	var swaps: int = 0
	for id: String in catalog.index.scenarios:
		var setup: Dictionary = catalog.index.scenarios[id]
		check(Campaign.validate_scenario(setup).is_empty(), "valid published setup " + id)
		if not setup.has("requisition"): continue
		scenarios += 1
		var original: Dictionary = Session.create_encounter(setup)
		if not check(original.ok, "original setup " + id): continue
		var start: Battle = original.battle
		var blue: Dictionary = start.players[0]
		var index: int = -1
		for i: int in range(blue.hand.size()):
			if blue.hand[i].card_id == setup.requisition.replace:
				index = i
				break
		if not check(index >= 0, "actual opening holds the outgoing card " + id): continue
		var start_state: Dictionary = Snapshot.capture(start)
		for card_id: String in setup.requisition.offers:
			swaps += 1
			var case_name: String = "%s → %s" % [id, card_id]
			var selected: Dictionary = Session.create_encounter(setup, card_id)
			if not check(selected.ok, "all offers start through normal factory " + case_name): continue
			var battle: Battle = selected.battle
			var new_state: Dictionary = Snapshot.capture(battle)
			var expected: Array = start_state.players[0].hand.duplicate(true)
			expected[index].card_id = card_id
			check(expected == new_state.players[0].hand and start_state.players[0].deck == new_state.players[0].deck, "exactly one hand slot exchanged and next draws stable " + case_name)
			check(start_state.players[1] == new_state.players[1] and start_state.units == new_state.units and start_state.objective == new_state.objective, "opponent, board and objective stable " + case_name)
			check(start.rng.state == battle.rng.state and start.next_id == battle.next_id and blue.mana == battle.players[0].mana, "same RNG, instance identity and opening resources " + case_name)
			check(battle.deck(0).cards == Campaign.Requisition.counts_for(setup, card_id) and Snapshot.validate(new_state).ok, "actual deck composition and card conservation " + case_name)
			if setup.has("bonus_card"):
				check(battle.players[0].hand.back().card_id == setup.bonus_card, "authored reward remains in the opening " + case_name)
	check(scenarios == 20 and swaps == 60, "twenty briefings and sixty real swaps")

func test_store_and_retry() -> void:
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
	var prior = Session.new(LEGACY)
	if not check(legacy.version == 3 and prior.load_campaign().ok, "restore actual v0.47 court encounter with old save envelope"): return
	var old: Dictionary = JSON.parse_string(JSON.stringify(Snapshot.capture(prior.encounter), "", true, true))
	check(old == legacy.encounter.battle and prior.campaign.requisition.is_empty(), "original deck, exact clock, identity and board restored without a swap")
	var model := Store.new(SLOT)
	if not check(model.save_progress(legacy.progress).ok, "restore the earned briefing to a per-test slot"): return
	var session = Session.new(SLOT)
	if not check(session.load_campaign().ok and session.current().scenario == "c06_court", "earnings resolve to the actual court briefing"): return
	var first: Dictionary = session.token()
	var original: String = FileAccess.get_file_as_string(SLOT)
	check(not session.choose_requisition("span_kit", first).ok and FileAccess.get_file_as_string(SLOT) == original, "an unoffered card cannot touch selection or disk")
	if not check(session.choose_requisition("dawn_weir", first).ok, "select the new ten-cost order through the coordinator"): return
	check(not session.begin_battle(first).ok and session.encounter == null, "old briefing token cannot launch after choice changed")
	session = Session.new(SLOT)
	if not check(session.load_campaign().ok and session.campaign.requisition == "dawn_weir" and session.encounter == null, "preparation persists across reloading before battle"): return
	if not check(session.begin_battle(session.token()).ok, "launch selected campaign loadout"): return
	var opening: Dictionary = Snapshot.capture(session.encounter)
	var wrong: Dictionary = session.campaign.snapshot()
	wrong.requisition = "floodline_warning"
	check(not model.save_progress(wrong, {"scenario": "c06_court", "revision": session.current().revision, "battle": opening}).ok, "saved selection must match exact deployed deck")
	check(not session.choose_requisition("floodline_warning", session.token()).ok, "cannot switch supplies after deployment")
	session.encounter.advance_clock(11.25)
	var active: Dictionary = Snapshot.capture(session.encounter)
	check(session.save().ok, "save an active encounter with swapped card")
	var fresh = Session.new(SLOT)
	if not check(fresh.load_campaign().ok and fresh.encounter != null, "reload active encounter"): return
	check(Snapshot.capture(fresh.encounter) == active and fresh.campaign.requisition == "dawn_weir", "chosen order and precise timer round-trip")
	var battle: Battle = fresh.encounter
	for step: int in range(400):
		if battle.winner != -1: break
		var action: Dictionary = {"type": "end_turn"} if battle.active_side == 0 else Opponent.choose(battle)
		if not check(battle.apply_action(action).ok, "the opponent earns the rehearsal defeat through legal actions"): return
	if not check(battle.winner == 1 and fresh.finish_battle(battle).ok, "actual defeat returns to the same briefing"): return
	session = Session.new(SLOT)
	if not check(session.load_campaign().ok and session.campaign.requisition == "dawn_weir" and session.current().attempts == 1, "attempt count and preparation survive reload after defeat"): return
	check(session.begin_battle(session.token()).ok and Snapshot.capture(session.encounter) == opening, "rebooting and retrying recreate the same chosen hand")
	check(not session.begin_battle(session.token()).ok, "cannot start on top of a running encounter")

func test_no_options_and_rollback() -> void:
	var session = Session.new("res://.tools/v048-requisition-opening.json")
	if not check(session.new_campaign().ok, "start new campaign normally"): return
	check(not session.choose_requisition("dawn_weir", session.token()).ok and session.campaign.requisition.is_empty(), "opening chapter cannot requisition")
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
	session = Session.new("res://.tools/v048-missing-requisition-dir/save.json")
	if not check(session.campaign.restore(prior.progress).ok, "prepare the briefing for a failed write"): return
	var token: Dictionary = session.token()
	check(not session.choose_requisition("dawn_weir", token).ok and session.campaign.requisition.is_empty() and session.token() == token, "failed disk write rolls back selection and page token")

func run() -> void:
	test_all_openings()
	test_store_and_retry()
	test_no_options_and_rollback()
	print("REQUISITION RULES %d CHECKS | %d FAILURES" % [checks, failures])
	quit(0 if failures == 0 else 1)
