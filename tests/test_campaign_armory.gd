extends SceneTree

const Session = preload("res://scripts/campaign_session.gd")
const Armory = preload("res://scripts/campaign_armory.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const AI = preload("res://scripts/opponent.gd")
const ACTIVE := "res://tests/fixtures/v049-active-court.json"
const ENDING := "res://tests/fixtures/v048-completed-main.json"
var slot_path: String = "res://.tools/armory-model-%d.json" % OS.get_process_id()

var checks: int = 0
var failures: int = 0
var tested_openings: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value

func test_slots() -> void:
	for completed: int in range(18):
		var expected: int = int(completed >= 2) + int(completed >= 4) + int(completed >= 7)
		check(Armory.unlocked_count(completed) == expected, "unlock progression after %d chapters" % completed)
	var unlocked_cards: Array[String] = []
	for slot: Dictionary in Armory.SLOTS:
		for card: Dictionary in Armory.options(slot):
			check(not unlocked_cards.has(card.id), "a card belongs to just one tier")
			unlocked_cards.append(card.id)
			check(int(card.cost) >= int(slot.min_cost) and int(card.cost) <= int(slot.max_cost), "option cost is in the printed band")
	check(unlocked_cards.size() == 108, "all 108 Mooring Oaths, Pilgrim March and Glassroad Orders cards can enter campaign")
	check(not Armory.validate({"vanguard": "quiet_net"}, 1).is_empty(), "opening is locked until chapter two finishes")
	check(not Armory.validate({"company": "sunken_weir_breach"}, 18).is_empty(), "cannot move heavy card into a cheaper tier")
	check(not Armory.validate({"reserve": "initiative"}, 18).is_empty(), "generated-only cards cannot be equipped")
	check(not Armory.validate({"unknown": "quiet_net"}, 18).is_empty(), "no unknown slots")
	check(not Armory.validate({"vanguard": 3}, 18).is_empty() and not Armory.validate([], 18).is_empty(), "plain data types are validated")

func test_openings() -> void:
	var campaign = Session.Campaign.new()
	for scenario_id: String in campaign.index.scenarios:
		var completed: int = int(scenario_id.substr(1, 2)) - 1
		if Armory.unlocked_count(completed) == 0: continue
		var setup: Dictionary = campaign.index.scenarios[scenario_id]
		var offers: Array = [""] + setup.get("requisition", {}).get("offers", [])
		for requisition: String in offers:
			var regular: Dictionary = Session.create_encounter(setup, requisition)
			if not check(regular.ok, "published start is still legal: " + scenario_id): continue
			var normal: Battle = regular.battle
			var combined: Dictionary = {}
			for slot: Dictionary in Armory.SLOTS:
				if int(slot.unlock_after) > completed: continue
				var options: Array[Dictionary] = Armory.options(slot)
				combined[slot.id] = options.back().id
				for card: Dictionary in options:
					var picks: Dictionary = {}
					picks[slot.id] = card.id
					assert_opening(setup, requisition, picks, normal, scenario_id + "/" + card.id)
			assert_opening(setup, requisition, combined, normal, scenario_id + "/all")

func assert_opening(setup: Dictionary, requisition: String, picks: Dictionary, normal: Battle, label: String) -> void:
	var equipped: Dictionary = Session.create_encounter(setup, requisition, picks)
	if not check(equipped.ok, "legal equipped opening: " + label): return
	tested_openings += 1
	var battle: Battle = equipped.battle
	var blue: Dictionary = battle.players[0]
	var prior: Dictionary = normal.players[0]
	check(blue.hand == prior.hand and blue.mana == prior.mana and blue.card_total == prior.card_total, "authored opener including reward is exact: " + label)
	check(battle.players[1] == normal.players[1] and battle.units == normal.units and battle.objective == normal.objective, "opponent, objectives and board are exact: " + label)
	check(battle.rng.state == normal.rng.state and battle.next_id == normal.next_id and battle.terrain == normal.terrain, "fixed seed and instance allocator remain exact: " + label)
	var changed: Dictionary = {}
	var counts: Dictionary = normal.deck(0).cards.duplicate()
	for slot: Dictionary in Armory.SLOTS:
		if not picks.has(slot.id): continue
		var card: Dictionary = blue.deck[-int(slot.draw)]
		check(card.card_id == picks[slot.id], "enforce the published normal draw slot: " + label)
		changed[card.uid] = true
		for old: Dictionary in prior.deck:
			if old.uid != card.uid: continue
			check((battle.definition(old.card_id).type == "unit") == (battle.definition(card.card_id).type == "unit"), "replacement keeps troop to tactic ratio: " + label)
			counts[old.card_id] = int(counts[old.card_id]) - 1
			if counts[old.card_id] == 0: counts.erase(old.card_id)
			counts[card.card_id] = int(counts.get(card.card_id, 0)) + 1
			break
	var before: Array = prior.deck.filter(func(card: Dictionary) -> bool: return not changed.has(card.uid))
	var after: Array = blue.deck.filter(func(card: Dictionary) -> bool: return not changed.has(card.uid))
	check(before == after and prior.deck.size() == blue.deck.size(), "every other card and the card instance count are preserved: " + label)
	check(battle.deck(0).id == "custom" and battle.deck(0).cards == counts and Armory.Model.DECKS.validate_counts(counts, Armory.Model.CATALOG.cards).is_empty(), "actual composition is the exact legal thirty-card deck: " + label)

func test_running_save() -> void:
	var old_digest: String = FileAccess.get_sha256(ACTIVE)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ACTIVE))
	var previous = Session.new(ACTIVE)
	if not check(raw.version == 4 and previous.load_campaign().ok and previous.encounter != null, "v0.49 active encounter opens from the real older build"): return
	var normalized: Dictionary = JSON.parse_string(JSON.stringify(Snapshot.capture(previous.encounter), "", true, true))
	var expected: Dictionary = raw.encounter.battle.duplicate(true)
	expected.version = float(Snapshot.VERSION)
	expected.rules = Snapshot.rules_signature()
	check(previous.campaign.armory.is_empty() and normalized == expected and FileAccess.get_sha256(ACTIVE) == old_digest, "legacy board, timer, decks and bytes remain exact")
	var session = Session.new(slot_path)
	if not check(session.store.save_progress(raw.progress).ok and session.load_campaign().ok, "old earned court briefing loads with unlocked tiers"): return
	var token: Dictionary = session.token()
	var digest: String = FileAccess.get_sha256(slot_path)
	var picks: Dictionary = {"vanguard": "quiet_net", "company": "shoal_arbalest"}
	check(not session.configure_armory({"reserve": "copper_boltline"}, token).ok and FileAccess.get_sha256(slot_path) == digest, "locked candidate never touches the save")
	check(session.choose_requisition("dawn_weir", token).ok, "the authored opening swap remains selectable")
	check(not session.configure_armory(picks, token).ok, "a stale briefing cannot apply equipment")
	if not check(session.configure_armory(picks, session.token()).ok and session.campaign.armory == picks, "save the loadout through the normal coordinator"): return
	var fresh = Session.new(slot_path)
	if not check(fresh.load_campaign().ok and fresh.campaign.armory == picks and fresh.campaign.requisition == "dawn_weir", "stored briefing has both forms of preparation"): return
	if not check(fresh.begin_battle(fresh.token()).ok, "equip and start the actual court match"): return
	var opening: Dictionary = Snapshot.capture(fresh.encounter)
	check(opening.players[0].hand.any(func(card: Dictionary) -> bool: return card.card_id == "dawn_weir"), "the authored requisition is in the untouched starter hand")
	digest = FileAccess.get_sha256(slot_path)
	check(not fresh.configure_armory({}, fresh.token()).ok and FileAccess.get_sha256(slot_path) == digest, "parked or running battle cannot be retuned")
	var forged: Dictionary = fresh.campaign.snapshot()
	forged.armory.erase("company")
	var attempted: Dictionary = {"scenario": fresh.current().scenario, "revision": fresh.current().revision, "battle": opening}
	check(not fresh.store.save_progress(forged, attempted).ok and FileAccess.get_sha256(slot_path) == digest, "forged campaign choices cannot claim the equipped combat deck")
	var battle: Battle = fresh.encounter
	battle.advance_clock(12.25)
	var in_progress: Dictionary = Snapshot.capture(battle)
	check(fresh.save().ok and fresh.load_campaign().ok and fresh.campaign.armory == picks and Snapshot.capture(fresh.encounter) == in_progress, "active equipment, RNG and fractional timer reload exactly")
	battle = fresh.encounter
	for step: int in range(420):
		if battle.winner != -1: break
		var action: Dictionary = {"type": "end_turn"} if battle.active_side == 0 else AI.choose(battle)
		if not check(battle.apply_action(action).ok, "run a real defensive loss to reach retry"): return
	if not check(battle.winner == 1 and fresh.finish_battle(battle).ok and fresh.campaign.armory == picks, "defeat keeps the saved loadout at the briefing"): return
	check(fresh.begin_battle(fresh.token()).ok and Snapshot.capture(fresh.encounter) == opening, "retry uses the same composed stock and same draw positions")

func test_checkpoint_and_failure() -> void:
	var original = Session.new(ENDING)
	if not check(original.load_campaign().ok, "use the earned v0.48 route history"): return
	var raw: Dictionary = original.campaign.snapshot()
	var second_end: Dictionary = raw.completed[1]
	var advancing = Session.new("res://.tools/v050-armory-unlock.json")
	var end_progress: Dictionary = {"chapter_id": second_end.chapter_id, "story": second_end.story, "completed": raw.completed.slice(0, 1)}
	if check(advancing.campaign.restore(end_progress).ok, "reach the earned chapter-two ending as an unlock input"):
		check(advancing.next_chapter(advancing.token()).ok and advancing.notice.contains("先遣补给"), "changing to chapter three announces the actual unlocked slot")
	raw.completed[1]["armory"] = {"vanguard": "quiet_net"}
	check(not original.campaign.restore(raw).ok, "forged early choice in completed history is rejected")
	raw.completed[1].erase("armory")
	var school: Dictionary = {"vanguard": "quiet_net"}
	var later: Dictionary = {"vanguard": "bank_pikeman", "company": "shoal_arbalest", "reserve": "copper_boltline"}
	raw.completed[2]["armory"] = school
	raw.completed[8]["armory"] = later
	raw["armory"] = {"reserve": "sunken_weir_breach"}
	if not check(original.campaign.restore(raw).ok, "allowed choices in historical chapters restore"): return
	for pair: Array in [["chapter_03", {}], ["chapter_04", school], ["chapter_10", later]]:
		var branch: Dictionary = original.campaign.replay_from(pair[0])
		check(branch.ok and branch.campaign.armory == pair[1], "chapter replay uses preceding chapter's own equipment: " + pair[0])
	check(original.campaign.armory == raw.armory, "replay never changes current main settings")
	var unwriteable = Session.new("res://.tools/v050-armory-nonexistent/save.json")
	var active_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ACTIVE))
	if not check(unwriteable.campaign.restore(active_data.progress).ok, "legitimate briefing in memory for a failed write"): return
	var token: Dictionary = unwriteable.token()
	check(not unwriteable.configure_armory(school, token).ok and unwriteable.campaign.armory.is_empty() and unwriteable.token() == token, "failed save leaves equipment and briefing token exact")

func run() -> void:
	test_slots()
	test_openings()
	test_running_save()
	test_checkpoint_and_failure()
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(slot_path + suffix): DirAccess.remove_absolute(slot_path + suffix)
	print("CAMPAIGN ARMORY %d CHECKS | %d FAILURES | %d EQUIPPED OPENINGS" % [checks, failures, tested_openings])
	quit(0 if failures == 0 else 1)
