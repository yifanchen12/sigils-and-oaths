extends RefCounted

const VERSION: int = 1
const READING_SIZES: Array[int] = [100, 115, 130]
const DEFAULTS: Dictionary = {
	"fullscreen": false, "reading_size": 100, "reduce_motion": false,
	"music": 55, "effects": 70,
}

var path: String

func _init(settings_path: String = "user://settings.cfg") -> void:
	path = settings_path

static func normalize(values: Dictionary) -> Dictionary:
	var result: Dictionary = DEFAULTS.duplicate()
	for key: String in ["fullscreen", "reduce_motion"]:
		if values.get(key) is bool: result[key] = values[key]
	var reading: Variant = values.get("reading_size")
	if reading is int and READING_SIZES.has(reading): result.reading_size = reading
	for key: String in ["music", "effects"]:
		if values.get(key) is int: result[key] = clampi(values[key], 0, 100)
	return result

func _read(source: String) -> Dictionary:
	if not FileAccess.file_exists(source): return {"state": "missing"}
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null or file.get_length() > 8192: return {"state": "invalid"}
	file.close()
	var config := ConfigFile.new()
	if config.load(source) != OK: return {"state": "invalid"}
	var version: Variant = config.get_value("settings", "version", 0)
	if version is int and version > VERSION: return {"state": "future"}
	if version != VERSION: return {"state": "invalid"}
	var values: Dictionary = {}
	for key: String in DEFAULTS: values[key] = config.get_value("settings", key, DEFAULTS[key])
	return {"state": "valid", "values": normalize(values)}

func load_preferences() -> Dictionary:
	var current: Dictionary = _read(path)
	if current.state == "valid": return {"values": current.values, "notice": "", "writable": true}
	if current.state == "future":
		return {"values": DEFAULTS.duplicate(), "notice": "设置来自较新版本。本次使用默认值，原文件已保留。", "writable": false}
	var backup: Dictionary = _read(path + ".bak")
	if backup.state == "valid": return {"values": backup.values, "notice": "已读取上次有效设置。", "writable": true}
	return {"values": DEFAULTS.duplicate(), "notice": "设置文件无法读取，已使用默认值。" if current.state == "invalid" else "", "writable": true}

func save_preferences(values: Dictionary) -> Dictionary:
	var current: Dictionary = _read(path)
	if current.state == "future": return {"ok": false, "message": "设置来自较新版本，原文件已保留。"}
	var config := ConfigFile.new()
	var normalized: Dictionary = normalize(values)
	config.set_value("settings", "version", VERSION)
	for key: String in normalized: config.set_value("settings", key, normalized[key])
	var temporary: String = path + ".tmp"
	if config.save(temporary) != OK:
		return {"ok": false, "message": "无法写入设置，原设置仍在使用。"}
	if current.state == "valid" and DirAccess.copy_absolute(path, path + ".bak") != OK:
		return {"ok": false, "message": "无法备份设置，原设置仍在使用。"}
	if DirAccess.rename_absolute(temporary, path) != OK:
		return {"ok": false, "message": "无法替换设置，原设置仍在使用。"}
	return {"ok": true, "values": normalized}
