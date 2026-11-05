extends SceneTree

const Campaign = preload("res://scripts/campaign.gd")
const Store = preload("res://scripts/campaign_store.gd")
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
	for future_version: int in [2, 1000000001]:
		var future: String = JSON.stringify({"version": future_version, "progress": beginning})
		check(write_raw(PATH, future), "write future fixture")
		check(store.load_progress().get("future", false), "newer schema is reported without fallback")
		check(not store.save_progress(beginning).ok and FileAccess.get_file_as_string(PATH) == future, "future save remains untouched")
	cleanup(PATH)
	check(write_raw(PATH + ".bak", JSON.stringify({"version": 2, "progress": beginning})), "write future backup fixture")
	check(store.load_progress().get("future", false) and not store.save_progress(beginning).ok, "future backup is protected even without primary")
	cleanup(PATH)
	check(store.save_progress(beginning).ok, "reset fixture")
	check(store.save_progress(checkpoint).ok, "create backup for oversized fixture")
	check(write_raw(PATH, "x".repeat(Store.MAX_BYTES + 1)), "write oversized fixture")
	check(store.load_progress().get("recovered", false), "oversized primary falls back safely")
	check(not Store.new("res://.tools/__campaign_missing_dir__/save.json").save_progress(beginning).ok, "write failure returned without touching original")
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
	print("CAMPAIGN STORE CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
