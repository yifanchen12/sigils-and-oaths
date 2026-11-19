extends SceneTree

const Session = preload("res://scripts/campaign_session.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Opponent = preload("res://scripts/opponent.gd")
const FIXTURE := "res://tests/fixtures/v048-completed-main.json"
const ACTIVE_FIXTURE := "res://tests/fixtures/v047-court-encounter.json"
const PRIMARY := "res://.tools/v049-replay-main.json"
const ACTIVE := "res://.tools/v049-replay-active.json"
const TRACE := "res://.tools/v049-replay-trace.json"

var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value

func copy_fixture(source: String, destination: String) -> bool:
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination)) == OK

func seek(session: RefCounted, destination: String, choices: Dictionary) -> bool:
	for step: int in range(700):
		var page: Dictionary = session.current()
		if page.node == destination or page.get("scenario", "") == destination: return true
		match page.type:
			"dialogue":
				if not session.advance(session.token()).ok: return false
			"choice":
				var option: String = String(choices.get(page.node, ""))
				if option.is_empty() or not session.choose(option, session.token()).ok: return false
			"end":
				if not session.next_chapter(session.token()).ok: return false
			_: return false
	return false

func all_origins(primary: RefCounted) -> void:
	var original: Dictionary = primary.campaign.snapshot()
	var entries: Array[Dictionary] = primary.campaign.replay_chapters()
	if not check(entries.size() == 18 and primary.campaign.completed_chapter_count() == 18, "genuine final save unlocks all eighteen chapters"): return
	for row: Dictionary in entries:
		var launch: Dictionary = primary.campaign.replay_from(row.id)
		if not check(row.unlocked and launch.ok, "can fork completed chapter " + row.id): continue
		var branch: RefCounted = launch.campaign
		var progress: Dictionary = branch.snapshot()
		check(progress.chapter_id == row.id and progress.story.node == branch.story.graph.start, "fork begins at the authored first node " + row.id)
		check(progress.story.history.is_empty() and progress.story.decisions.is_empty() and progress.story.attempts.is_empty() and branch.requisition.is_empty(), "current chapter has no inherited actions " + row.id)
		check(progress.completed == original.completed.slice(0, row.number - 1), "fork keeps all earned chapters before the origin " + row.id)
		if row.number > 1:
			var previous_flags: Dictionary = original.completed[row.number - 2].story.flags
			for field: String in branch.story.graph.get("inherits", []) + branch.story.graph.get("optional_inherits", []):
				check(progress.story.flags[field] == previous_flags.get(field, branch.story.graph.defaults[field]), "earlier fact preserved " + row.id + " " + field)
	check(primary.campaign.snapshot() == original, "all forks have left the main instance intact")
	for entry: Dictionary in entries:
		check(not entry.end_text.is_empty() and entry.can_revise_covenant == (entry.number == 18),"completed chapter has its own reached final page and correct replay actions")
	var covenant: Dictionary = primary.campaign.replay_from("chapter_18",true)
	if not check(covenant.ok and covenant.campaign.story.current().node == "covenant","return to the actual last choice from an old ending"): return
	var branch: RefCounted = covenant.campaign
	var read: Array = branch.story.state.history
	check(not read.is_empty() and original.story.history.slice(0,read.size()) == read and branch.story.state.decisions.is_empty(),"only the exact earned text prefix is fast-forwarded")
	check(not primary.campaign.replay_from("chapter_09",true).ok, "a covenant cannot bypass encounters in an earlier chapter")
	for option: Dictionary in branch.story.current().options:
		var another: RefCounted = primary.campaign.replay_from("chapter_18",true).campaign
		var page: Dictionary = another.story.current()
		check(another.story.choose(option.id,page.revision).ok,"choose a different visible oath")
		while another.story.current().type == "dialogue": another.story.advance(another.story.current().revision)
		check(another.story.current().node == option.id+"_end","the altered oath reaches its own authored ending")

func play(branch: RefCounted, capture_trace: bool) -> Dictionary:
	var battle: Battle = branch.encounter
	var initial: Dictionary = Snapshot.capture(battle)
	var trace: Array[Dictionary] = []
	var checkpoint: int = -1
	for step: int in range(500):
		if battle.winner != -1: break
		var side: int = battle.active_side
		var action: Dictionary = Opponent.choose(battle)
		battle.advance_clock(0.25)
		if not check(side == battle.active_side and battle.apply_action(action).ok, "branch uses legal rules and clocks"): return {}
		if action.get("target") is Vector2i: action.target = [action.target.x, action.target.y]
		trace.append({"side": side, "action": action})
		if checkpoint == -1 and battle.turn >= 3 and battle.active_side == 0 and battle.winner == -1:
			var before: Dictionary = Snapshot.capture(battle)
			if not check(branch.save().ok, "branch autosave stores live match"): return {}
			var resumed = Session.new(branch.store.path)
			if not check(resumed.load_campaign().ok and Snapshot.capture(resumed.encounter) == before, "separate branch instance restores exact hand, clock and board"): return {}
			branch = resumed
			battle = resumed.encounter
			checkpoint = trace.size()
	if not check(battle.winner == 0 and battle.objective.streak == battle.objective.required and not battle.commander(1).is_empty(), "branch wins by accomplishing the actual scenario objective"): return {}
	var final: Dictionary = Snapshot.capture(battle)
	if not check(branch.finish_battle(battle).ok, "victory advances the branch's story"): return {}
	if capture_trace:
		var file := FileAccess.open(TRACE, FileAccess.WRITE)
		if not check(file != null, "write legitimate replay trace for native acceptance"): return {}
		file.store_string(JSON.stringify({"initial": initial, "trace": trace, "checkpoint_at": checkpoint, "final": final}, "", true, true))
		file.close()
	return {"branch": branch, "actions": trace.size(), "turn": battle.turn, "reload_at_action": checkpoint}

func test_other_routes(primary: RefCounted) -> void:
	var branch = Session.new(Session.replay_path(PRIMARY))
	if not check(branch.start_replay_from(primary, "chapter_07").ok, "start earlier chapter through real separate save entry"): return
	check(not branch.advance(primary.token()).ok, "main token cannot mutate branch")
	var choices: Dictionary = {"camp": "clinic", "saltlane_call": "answer_call", "saltlane_route": "school"}
	if not check(seek(branch, "c07_saltlane_school", choices) and branch.begin_battle(branch.token()).ok, "choose the other bridge and enter actual escort"): return
	var result: Dictionary = play(branch, false)
	if result.is_empty(): return
	branch = result.branch
	if not check(seek(branch, "c08_isolate", {"pressure": "isolate"}) and branch.campaign.scenario().bonus_card == "lantern_stretcher", "branch escort earns its own chapter-eight assistance"): return
	check(primary.campaign.completed[6].story.flags.saltlane_result == "kiln", "main retains kiln rescue")
	evidence["other_bridge"] = {"actions": result.actions, "turn": result.turn, "reload": result.reload_at_action, "chapter_eight_card": "lantern_stretcher"}
	if not check(branch.start_replay_from(primary, "chapter_17").ok, "replace branch from another completed origin"): return
	if not check(seek(branch, "c17_screen", {"kit": "screen"}) and branch.begin_battle(branch.token()).ok, "switch to the other three-lantern route"): return
	result = play(branch, true)
	if result.is_empty(): return
	branch = result.branch
	if not check(seek(branch, "hold_end", {"covenant": "hold"}), "earned rescue result reaches a different authored conclusion"): return
	var reload = Session.new(branch.store.path)
	check(reload.load_campaign().ok and reload.current().node == "hold_end" and reload.campaign.story.state.flags.rescue_kit == "screen", "separate process state restores the new ending and earlier kit")
	check(primary.current().node == "joint_end" and primary.campaign.story.state.flags.rescue_kit == "runner", "main stays on the original ending and kit")
	evidence["other_ending_from_battle"] = {"actions": result.actions, "turn": result.turn, "reload": result.reload_at_action, "ending": "hold_end"}
	if not check(branch.start_replay_from(primary, "chapter_18").ok and seek(branch, "split_end", {"covenant": "split"}), "replay the last chapter to earn the third ending"): return
	reload = Session.new(branch.store.path)
	check(reload.load_campaign().ok and reload.current().node == "split_end", "third ending persisted")
	evidence["third_ending"] = "split_end"

func test_active_and_protected() -> void:
	if not check(copy_fixture(ACTIVE_FIXTURE, ACTIVE), "copy genuine old active main without changing its source"): return
	var primary = Session.new(ACTIVE)
	var original: String = FileAccess.get_sha256(ACTIVE)
	if not check(primary.load_campaign().ok and primary.encounter != null and primary.campaign.completed_chapter_count() == 5, "old active main unlocks only finished chapters"): return
	var active_before: Dictionary = Snapshot.capture(primary.encounter)
	var branch = Session.new(Session.replay_path(ACTIVE))
	check(not branch.start_replay_from(primary, "chapter_06").ok and branch.campaign.story == null, "incomplete current chapter stays locked")
	var locked: Dictionary = primary.campaign.replay_chapters().back()
	check(not locked.unlocked and not locked.has("end_text") and not locked.has("decisions") and not branch.start_replay_from(primary,"chapter_18",true).ok,"locked chapters reveal no choices, ending prose or covenant")
	check(not primary.start_replay_from(primary, "chapter_04").ok, "cannot reuse the main slot for a branch")
	if not check(branch.start_replay_from(primary, "chapter_04").ok and branch.advance(branch.token()).ok, "branch can progress while original battle is active"): return
	var fresh = Session.new(ACTIVE)
	check(fresh.load_campaign().ok and Snapshot.capture(fresh.encounter) == active_before and FileAccess.get_sha256(ACTIVE) == original, "old active main reloads with exact clock and board")
	var later := "res://.tools/v049-replay-future.json"
	var file := FileAccess.open(later, FileAccess.WRITE)
	if not check(file != null, "write independent future-version test slot"): return
	file.store_string(JSON.stringify({"version": Session.Store.VERSION + 1}))
	file.close()
	var protected := FileAccess.get_sha256(later)
	var incompatible = Session.new(later)
	var result: Dictionary = incompatible.start_replay_from(primary, "chapter_04")
	check(not result.ok and result.get("future", false) and incompatible.campaign.story == null and FileAccess.get_sha256(later) == protected, "future branch remains protected without adopting a replacement")

func run() -> void:
	if not check(copy_fixture(FIXTURE, PRIMARY) and copy_fixture(FIXTURE, PRIMARY + ".bak"), "genuine main and its backup copied for acceptance"): quit(1); return
	var main_hash: String = FileAccess.get_sha256(PRIMARY)
	var backup_hash: String = FileAccess.get_sha256(PRIMARY + ".bak")
	var primary = Session.new(PRIMARY)
	if not check(primary.load_campaign().ok and primary.current().node == "joint_end", "released save supplies main provenance"): quit(1); return
	all_origins(primary)
	test_other_routes(primary)
	test_active_and_protected()
	check(FileAccess.get_sha256(PRIMARY) == main_hash and FileAccess.get_sha256(PRIMARY + ".bak") == backup_hash, "main and backup byte-for-byte unchanged through branch creation and completion")
	print("CHAPTER REPLAY %d CHECKS | FAILURES %d | %s" % [checks, failures, JSON.stringify(evidence)])
	quit(0 if failures == 0 else 1)
