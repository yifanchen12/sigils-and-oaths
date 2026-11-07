extends SceneTree

const Campaign = preload("res://scripts/campaign.gd")
const Store = preload("res://scripts/campaign_store.gd")
const Session = preload("res://scripts/campaign_session.gd")
const BattleModel = preload("res://scripts/battle.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const PATH: String = "res://.tools/test_campaign.json"
const CROSS_PATH: String = "res://.tools/cross_process_campaign.json"
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(label)

func cleanup(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func write_raw(path: String, content: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	var ok: bool = file.store_string(content)
	file.close()
	return ok

func at_river_battle() -> RefCounted:
	var campaign: RefCounted = Campaign.new()
	campaign.start()
	while campaign.story.current().type == "dialogue": campaign.story.advance(campaign.story.current().revision)
	campaign.story.choose("river", campaign.story.current().revision)
	while campaign.story.current().type == "dialogue": campaign.story.advance(campaign.story.current().revision)
	return campaign

func test_storage() -> bool:
	cleanup(PATH)
	var store: RefCounted = Store.new(PATH)
	check(store.load_progress().get("missing", false), "missing save reported")
	var campaign: RefCounted = Campaign.new(); campaign.start()
	var beginning: Dictionary = campaign.snapshot()
	check(store.save_progress(beginning).ok, "first chapter save succeeds")
	var loaded: Dictionary = Store.new(PATH).load_progress()
	check(loaded.ok and loaded.progress == beginning, "fresh store reads opening state")
	var old_text: String = FileAccess.get_file_as_string(PATH)
	var invalid: Dictionary = beginning.duplicate(true); invalid.story.node = "absent"
	check(not store.save_progress(invalid).ok and FileAccess.get_file_as_string(PATH) == old_text, "invalid state cannot overwrite a save")
	campaign = at_river_battle()
	check(campaign.story.current().scenario == "c01_river" and not campaign.story.state.flags.witness_present, "checkpoint precedes actual rescue")
	var checkpoint: Dictionary = campaign.snapshot()
	check(store.save_progress(checkpoint).ok, "battle checkpoint saves")
	check(FileAccess.file_exists(PATH + ".bak"), "last valid progress backed up")
	check(write_raw(PATH, "{broken"), "write corrupt fixture")
	loaded = store.load_progress()
	check(loaded.ok and loaded.get("recovered", false) and loaded.progress == beginning, "bad primary recovers actual previous checkpoint")
	check(store.save_progress(checkpoint).ok, "saving after backup recovery succeeds")
	check(Store.new(PATH + ".bak").load_progress().progress == beginning, "bad primary never replaces good backup")
	campaign.story.resolve_battle(1, campaign.story.current().revision)
	check(not campaign.story.state.flags.witness_present, "defeat does not award rescue fact")
	check(store.save_progress(campaign.snapshot()).ok, "failed attempt checkpoint persists")
	var fresh: RefCounted = Campaign.new()
	loaded = Store.new(PATH).load_progress()
	check(fresh.restore(loaded.progress).ok and fresh.story.current().last_outcome == "defeat" and fresh.story.current().attempts == 1, "load restores failure and retry count")
	check(fresh.scenario() == campaign.scenario(), "retry keeps same seed and scenario")
	fresh.story.resolve_battle(0, fresh.story.current().revision)
	check(fresh.story.state.flags.witness_present and fresh.story.current().node == "river_after", "only victory grants witness and advances")
	check(store.save_progress(fresh.snapshot()).ok, "postbattle dialogue persists")
	for future_version: int in [Store.VERSION + 1, 1000000001]:
		var future: String = JSON.stringify({"version": future_version, "progress": beginning})
		check(write_raw(PATH, future), "write future fixture")
		check(store.load_progress().get("future", false), "newer schema is reported without fallback")
		check(not store.save_progress(beginning).ok and FileAccess.get_file_as_string(PATH) == future, "future save remains untouched")
	cleanup(PATH)
	check(write_raw(PATH + ".bak", JSON.stringify({"version": Store.VERSION + 1, "progress": beginning})), "write future backup fixture")
	check(store.load_progress().get("future", false) and not store.save_progress(beginning).ok, "future backup is protected even without primary")
	cleanup(PATH)
	check(store.save_progress(beginning).ok, "reset fixture")
	check(store.save_progress(checkpoint).ok, "create backup for oversized fixture")
	check(write_raw(PATH, "x".repeat(Store.MAX_BYTES + 1)), "write oversized fixture")
	check(store.load_progress().get("recovered", false), "oversized primary falls back safely")
	check(not Store.new("res://.tools/__campaign_missing_dir__/save.json").save_progress(beginning).ok, "write failure returned without touching original")
	cleanup(PATH)
	return true

func test_bridge_deck_migration() -> bool:
	cleanup(PATH)
	var campaign: RefCounted = Campaign.new(); campaign.start()
	for step: int in range(100):
		var page: Dictionary = campaign.story.current()
		if page.type == "battle":
			if page.scenario == "c01_bridge": break
			campaign.story.resolve_battle(0, page.revision) # Fixture-only prior result.
		elif page.type == "dialogue": campaign.story.advance(page.revision)
		elif page.type == "choice": campaign.story.choose("road" if page.node == "route" else page.options[0].id, page.revision)
		else: break
	check(campaign.story.current().get("scenario", "") == "c01_bridge", "legacy fixture reaches the exact bridge encounter")
	if campaign.story.current().get("scenario", "") != "c01_bridge": return false
	var setup: Dictionary = campaign.scenario()
	var old: Battle = BattleModel.new(setup.seed, setup.map, setup.hero, setup.enemy_class, setup.deck, "bastion", 90)
	old.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
	var encounter: Dictionary = {"scenario": "c01_bridge", "revision": campaign.story.current().revision, "battle": Snapshot.capture(old)}
	var store: RefCounted = Store.new(PATH)
	check(store.save_progress(campaign.snapshot(), encounter).ok, "0.29 bridge battle can be retained under the new scenario")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.encounter != null and fresh.encounter.deck(1).id == "bastion", "fresh process restores original in-progress opponent deck")
	if fresh.encounter == null: return false
	check(fresh.save().ok, "resumed old battle can autosave without losing its deck")
	var other: Battle = BattleModel.new(setup.seed, setup.map, setup.hero, setup.enemy_class, setup.deck, "assault", 90)
	other.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
	encounter.battle = Snapshot.capture(other)
	check(not store.save_progress(campaign.snapshot(), encounter).ok, "unrelated opponent deck cannot claim the migration exception")
	fresh.encounter.commander(0).hp = 0
	fresh.encounter._cleanup(); fresh.encounter._check_winner()
	check(fresh.finish_battle(fresh.encounter).ok, "legacy battle failure persists as an ordinary retry")
	var retry: Dictionary = fresh.begin_battle(fresh.token())
	check(retry.ok and retry.battle.deck(1).id == "balanced", "retry uses current balanced bridge opponent")
	cleanup(PATH)
	return true

func test_relief_deck_migration() -> bool:
	cleanup(PATH)
	var campaign: RefCounted = Campaign.new(); campaign.start()
	for step: int in range(200):
		var page: Dictionary = campaign.story.current()
		if page.type == "battle":
			if page.scenario == "c02_relief_bridge": break
			campaign.story.resolve_battle(0, page.revision) # Fixture-only prior result.
		elif page.type == "dialogue": campaign.story.advance(page.revision)
		elif page.type == "choice": campaign.story.choose("road" if page.node == "route" else ("relief" if page.node == "priority" else page.options[0].id), page.revision)
		elif page.type == "end" and not campaign.next_chapter().is_empty(): campaign.advance_chapter()
		else: break
	check(campaign.story.current().get("scenario", "") == "c02_relief_bridge", "legacy fixture reaches the exact relief encounter")
	if campaign.story.current().get("scenario", "") != "c02_relief_bridge": return false
	var setup: Dictionary = campaign.scenario()
	var old: Battle = BattleModel.new(setup.seed, setup.map, setup.hero, setup.enemy_class, setup.deck, "assault", 90)
	old.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
	old.configure_objective(setup.control)
	var encounter: Dictionary = {"scenario": "c02_relief_bridge", "revision": campaign.story.current().revision, "battle": Snapshot.capture(old)}
	var store: RefCounted = Store.new(PATH)
	check(store.save_progress(campaign.snapshot(), encounter).ok, "0.30 relief battle survives its opponent deck change")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.encounter != null and fresh.encounter.deck(1).id == "assault", "old in-progress relief battle keeps assault opponent")
	if fresh.encounter == null: return false
	check(fresh.save().ok, "resumed old relief battle can autosave")
	var other: Battle = BattleModel.new(setup.seed, setup.map, setup.hero, setup.enemy_class, setup.deck, "bastion", 90)
	other.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
	other.configure_objective(setup.control)
	encounter.battle = Snapshot.capture(other)
	check(not store.save_progress(campaign.snapshot(), encounter).ok, "unrelated relief opponent deck is rejected")
	fresh.encounter.commander(0).hp = 0
	fresh.encounter._cleanup(); fresh.encounter._check_winner()
	check(fresh.finish_battle(fresh.encounter).ok, "old relief battle failure remains an ordinary retry")
	var retry: Dictionary = fresh.begin_battle(fresh.token())
	check(retry.ok and retry.battle.deck(1).id == "balanced", "relief retry uses current balanced opponent")
	cleanup(PATH)
	return true

func test_dispatch_deck_migration() -> bool:
	cleanup(PATH)
	var campaign: RefCounted = Campaign.new(); campaign.start()
	for step: int in range(240):
		var page: Dictionary = campaign.story.current()
		if page.type == "battle":
			if page.scenario == "c02_dispatch": break
			campaign.story.resolve_battle(0, page.revision) # Fixture-only prior result.
		elif page.type == "dialogue": campaign.story.advance(page.revision)
		elif page.type == "choice": campaign.story.choose("road" if page.node == "route" else ("relief" if page.node == "priority" else page.options[0].id), page.revision)
		elif page.type == "end" and not campaign.next_chapter().is_empty(): campaign.advance_chapter()
		else: break
	check(campaign.story.current().get("scenario", "") == "c02_dispatch", "legacy fixture reaches dispatch after prior victories")
	if campaign.story.current().get("scenario", "") != "c02_dispatch": return false
	var setup: Dictionary = campaign.scenario()
	var old: Battle = BattleModel.new(setup.seed, setup.map, setup.hero, setup.enemy_class, "assault", setup.enemy_deck, 90)
	old.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
	var encounter: Dictionary = {"scenario": "c02_dispatch", "revision": campaign.story.current().revision, "battle": Snapshot.capture(old)}
	var store: RefCounted = Store.new(PATH)
	check(store.save_progress(campaign.snapshot(), encounter).ok, "0.30 dispatch battle survives its player deck change")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.encounter != null and fresh.encounter.deck(0).id == "assault", "old in-progress dispatch battle keeps assault player deck")
	if fresh.encounter == null: return false
	check(fresh.save().ok, "resumed old dispatch battle can autosave")
	var other: Battle = BattleModel.new(setup.seed, setup.map, setup.hero, setup.enemy_class, "balanced", setup.enemy_deck, 90)
	other.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait)
	encounter.battle = Snapshot.capture(other)
	check(not store.save_progress(campaign.snapshot(), encounter).ok, "unrelated dispatch player deck is rejected")
	fresh.encounter.commander(0).hp = 0
	fresh.encounter._cleanup(); fresh.encounter._check_winner()
	check(fresh.finish_battle(fresh.encounter).ok, "old dispatch battle failure remains an ordinary retry")
	var retry: Dictionary = fresh.begin_battle(fresh.token())
	check(retry.ok and retry.battle.deck(0).id == "bastion", "dispatch retry uses current bastion player deck")
	cleanup(PATH)
	return true

func test_isolate_deck_migration() -> bool:
	cleanup(PATH)
	var campaign: RefCounted = Campaign.new(); campaign.start()
	for step: int in range(1600):
		var page: Dictionary = campaign.story.current()
		if page.type == "battle":
			if page.scenario == "c08_isolate": break
			campaign.story.resolve_battle(0, page.revision) # Fixture-only prior result.
		elif page.type == "dialogue": campaign.story.advance(page.revision)
		elif page.type == "choice": campaign.story.choose("road" if campaign.story.graph.id == "chapter_01" and page.node == "route" else ("relief" if page.node == "priority" else ("isolate" if page.node == "pressure" else page.options[0].id)), page.revision)
		elif page.type == "end" and not campaign.next_chapter().is_empty(): campaign.advance_chapter()
		else: break
	check(campaign.story.current().get("scenario", "") == "c08_isolate", "legacy fixture reaches the exact Sunspire isolation encounter")
	if campaign.story.current().get("scenario", "") != "c08_isolate": return false
	var setup: Dictionary = campaign.scenario()
	var old: Battle = BattleModel.new(setup.seed, setup.map, setup.hero, setup.enemy_class, setup.deck, "bastion", 90)
	old.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait); old.configure_objective(setup.control)
	var encounter: Dictionary = {"scenario": "c08_isolate", "revision": campaign.story.current().revision, "battle": Snapshot.capture(old)}
	var store: RefCounted = Store.new(PATH)
	check(store.save_progress(campaign.snapshot(), encounter).ok, "0.31 isolation battle survives its opponent deck change")
	var fresh: RefCounted = Session.new(PATH)
	check(fresh.load_campaign().ok and fresh.encounter != null and fresh.encounter.deck(1).id == "bastion", "old in-progress isolation battle keeps bastion opponent")
	if fresh.encounter == null: return false
	check(fresh.save().ok, "resumed old isolation battle can autosave")
	var other: Battle = BattleModel.new(setup.seed, setup.map, setup.hero, setup.enemy_class, setup.deck, "assault", 90)
	other.set_commander_identity(1, setup.enemy_name, setup.enemy_portrait); other.configure_objective(setup.control)
	encounter.battle = Snapshot.capture(other)
	check(not store.save_progress(campaign.snapshot(), encounter).ok, "unrelated isolation opponent deck is rejected")
	fresh.encounter.commander(0).hp = 0
	fresh.encounter._cleanup(); fresh.encounter._check_winner()
	check(fresh.finish_battle(fresh.encounter).ok, "old isolation battle failure remains an ordinary retry")
	var retry: Dictionary = fresh.begin_battle(fresh.token())
	check(retry.ok and retry.battle.deck(1).id == "balanced", "isolation retry uses current balanced opponent")
	cleanup(PATH)
	return true

func write_cross_process() -> bool:
	cleanup(CROSS_PATH)
	var campaign: RefCounted = at_river_battle()
	campaign.story.resolve_battle(1, campaign.story.current().revision)
	check(Store.new(CROSS_PATH).save_progress(campaign.snapshot()).ok, "first process writes failed river checkpoint")
	return true

func read_cross_process() -> bool:
	var loaded: Dictionary = Store.new(CROSS_PATH).load_progress()
	check(loaded.ok, "second process reads disk checkpoint")
	if not loaded.ok: return false
	var campaign: RefCounted = Campaign.new()
	check(campaign.restore(loaded.progress).ok, "second process reconstructs campaign")
	check(campaign.story.current().scenario == "c01_river" and campaign.story.current().last_outcome == "defeat", "second process restores correct retry point")
	check(campaign.story.state.flags.route == "river" and not campaign.story.state.flags.witness_present, "second process preserves decision without granting victory")
	check(campaign.story.current().attempts == 1 and campaign.scenario().seed == 1318, "second process restores attempts and reproducible encounter")
	campaign.story.resolve_battle(0, campaign.story.current().revision)
	check(campaign.story.current().node == "river_after" and campaign.story.state.flags.witness_present, "restored game can continue after victory")
	cleanup(CROSS_PATH)
	return true

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var method: String = "write_cross_process" if args.has("--write") else ("read_cross_process" if args.has("--read") else "test_storage")
	check(call(method) == true, method + " completed without runtime interruption")
	if method == "test_storage":
		check(test_bridge_deck_migration(), "bridge deck migration completed without runtime interruption")
		check(test_relief_deck_migration(), "relief deck migration completed without runtime interruption")
		check(test_dispatch_deck_migration(), "dispatch deck migration completed without runtime interruption")
		check(test_isolate_deck_migration(), "isolation deck migration completed without runtime interruption")
	print("CAMPAIGN STORE CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
