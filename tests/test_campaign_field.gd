extends SceneTree
## Both fixtures were written by the published 0.57 pack replaying legal campaign actions.
const Session = preload("res://scripts/campaign_session.gd")
const Snap = preload("res://scripts/battle_snapshot.gd")
const BRIDGE = "res://tests/fixtures/v057-bridge-last-turn.json"
const CHANNEL = "res://tests/fixtures/v057-channel-result.json"
const SLOT = "user://campaign-field-check.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(pred: bool, label: String) -> bool:
	checks += 1
	if not pred:
		failures += 1
		push_error(label)
	return pred

func copy_slot(fixture: String) -> RefCounted:
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(SLOT+suffix): DirAccess.remove_absolute(SLOT+suffix)
	check(DirAccess.copy_absolute(fixture,SLOT) == OK, "the old published profile is readable")
	var session = Session.new(SLOT)
	check(session.load_campaign().ok, "the current build continues the old profile")
	return session

func bridge() -> void:
	var session = copy_slot(BRIDGE)
	var b: Battle = session.encounter
	if not check(b != null and b.winner == -1 and session.last_attempt.is_empty(), "the old active bridge battle resumes"): return
	b.advance_clock(0.35)
	var action := {"type":"attack","unit_id":80,"target":Vector2i(5,9)}
	if not check(b.active_side == 1 and b.apply_action(action).ok and b.winner == 1, "the original final cavalry attack is still legal"): return
	check(session.finish_battle(b).ok and not session.finish_battle(b).ok, "exactly one defeat is recorded")
	var terminal := Snap.capture(b)
	check(session.inspect_field(session.token(),true).battle.result_reason().contains(b.hero(0).name), "the review names the fallen commander")
	var prev: Dictionary = session.token()
	var data := FileAccess.get_sha256(SLOT)
	var opening: Dictionary = session.inspect_field(prev,false)
	check(opening.ok and opening.battle.turn == 1 and opening.battle.winner == -1, "preview constructs the actual opening")
	opening.battle.commander(0).hp = 1
	check(session.inspect_field(prev,false).battle.commander(0).hp != 1 and session.encounter == null, "inspecting a detached field cannot affect deployment")
	check(FileAccess.get_sha256(SLOT) == data and session.token() == prev, "inspection writes nothing and leaves revision and RNG untouched")
	check(session.choose_difficulty("story",prev).ok and not session.inspect_field(prev,true).ok, "difficulty updates invalidate an old button")
	session = Session.new(SLOT)
	if not check(session.load_campaign().ok, "the new difficulty and previous attempt load together"): return
	var review: Dictionary = session.inspect_field(session.token(),true)
	check(review.difficulty == "standard" and Snap.capture(review.battle) == terminal,"standard defeat retains its complete old battlefield")
	opening = session.inspect_field(session.token(),false)
	check(opening.difficulty == "story" and opening.battle.objective.cells.size() == 2, "story retry uses the chosen two-point objective")
	var before := Snap.capture(opening.battle)
	var launched: Dictionary = session.begin_battle(session.token())
	check(launched.ok and Snap.capture(launched.battle) == before and session.last_attempt.is_empty(), "deploying uses exactly the displayed field, including hand, clock and mana")
	check(not session.inspect_field(session.token(),true).ok, "a live battle cannot open a previous defeat")

func channel() -> void:
	var session = copy_slot(CHANNEL)
	if not check(session.encounter == null and not session.last_attempt.is_empty(), "an earned terminal v6 save is resolved into its report on load"): return
	var archived: Dictionary = session.inspect_field(session.token(),true)
	var b: Battle = archived.battle
	check(not b.commander(0).is_empty() and not b.commander(1).is_empty() and b.result_reason().contains("期限"), "the lost deadline is distinguished from a commander death")
	check(b.turn == 45 and b.objective.streak == 0 and b.objective.required == 2 and b.objective.round_limit == 22,"the final occupation and complete-round count match the actual match")
	var attempts: int = session.current().attempts
	var progress: Dictionary = session.campaign.snapshot()
	var report: Dictionary = session.last_attempt
	var store = session.store
	check(store._validate(progress,{},report).ok, "the exact terminal record validates")
	for key: String in ["scenario","attempt","revision","difficulty","requisition","armory"]:
		var bad := report.duplicate(true)
		bad[key] = {"scenario":"c01_bridge","attempt":attempts+1,"revision":0,"difficulty":"invalid","requisition":"unknown","armory":{"invalid":"unknown"}}[key]
		check(not store._validate(progress,{},bad).ok, "reject a mismatched " + key)
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHANNEL))
	check(not store._validate(progress,old.encounter,report).ok, "a live field and completed report cannot occupy the same slot")
	var changed := report.duplicate(true)
	changed.battle.match_seed += 1
	check(not store._validate(progress,{},changed).ok,"foreign seed rejected")
	changed = report.duplicate(true)
	changed.battle.winner = -1
	check(not store._validate(progress,{},changed).ok, "unfinished field cannot masquerade as a defeat")
	var session2 = Session.new(SLOT)
	check(session2.load_campaign().ok and session2.current().attempts == attempts and session2.last_attempt == report,"loading a review twice cannot add another attempt")
	var old_brief := {"version":6, "progress":progress,"encounter":{}}
	var output := FileAccess.open(SLOT,FileAccess.WRITE)
	output.store_string(JSON.stringify(old_brief)); output.close()
	check(store._read_path(SLOT).ok and store._read_path(SLOT).last_attempt.is_empty(),"old briefings without a terminal board remain playable")
	old_brief["last_attempt"] = report
	output = FileAccess.open(SLOT,FileAccess.WRITE)
	output.store_string(JSON.stringify(old_brief)); output.close()
	check(not store._read_path(SLOT).ok,"the previous format cannot inject a review")

func run() -> void:
	bridge()
	channel()
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(SLOT+suffix): DirAccess.remove_absolute(SLOT+suffix)
	print("CAMPAIGN FIELD ",checks," CHECKS | ",failures," FAILURES")
	quit(0 if failures == 0 else 1)
