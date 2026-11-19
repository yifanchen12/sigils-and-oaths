extends SceneTree

const Store = preload("res://scripts/settings_store.gd")
const PATH = "user://test-042-settings.cfg"
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func cleanup() -> void:
	for path: String in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func run() -> void:
	cleanup()
	var store := Store.new(PATH)
	var first: Dictionary = Store.DEFAULTS.duplicate()
	first.merge({"fullscreen": true, "reading_size": 115, "music": 0, "effects": 45}, true)
	check(store.load_preferences().values == Store.DEFAULTS, "missing settings use canonical defaults")
	check(store.save_preferences(first).ok and Store.new(PATH).load_preferences().values == first, "all typed settings persist in a fresh object")
	var next: Dictionary = first.duplicate()
	next.merge({"reading_size": 130, "reduce_motion": true, "music": 110, "effects": -1}, true)
	var written: Dictionary = store.save_preferences(next)
	check(written.ok and written.values.music == 100 and written.values.effects == 0, "input limits prevent invalid bus gain")
	check(Store.new(PATH).load_preferences().values == written.values, "second write replaces the primary file")
	check(FileAccess.file_exists(PATH + ".bak"), "previous valid file backs up a replacement")
	var invalid := ConfigFile.new()
	invalid.set_value("settings", "version", 0)
	check(invalid.save(PATH) == OK, "prepare damaged version fixture")
	check(store.load_preferences().values == first and not store.load_preferences().notice.is_empty(), "damaged primary recovers the previous values")
	check(store.save_preferences(written.values).ok and store.load_preferences().values == written.values, "repaired primary preserves continuity")
	var future := ConfigFile.new()
	future.set_value("settings", "version", Store.VERSION + 2)
	future.set_value("settings", "future_setting", true)
	check(future.save(PATH) == OK, "prepare future file without modifying developer or player defaults")
	var before: String = FileAccess.get_sha256(PATH)
	check(not store.load_preferences().writable and store.load_preferences().values == Store.DEFAULTS, "older build defers to defaults for future file")
	check(not store.save_preferences(first).ok and FileAccess.get_sha256(PATH) == before, "saving from an older build leaves newer bytes intact")
	cleanup()
	print("PREFERENCES: %d CHECKS | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
