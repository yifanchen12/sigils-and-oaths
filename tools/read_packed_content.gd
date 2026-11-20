extends SceneTree
## Read resource remaps and their actual bytes from the mounted Windows release.

var content: Array[Dictionary] = []
var fonts: Array[String] = []
var errors: Array[String] = []

func fingerprint(path: String) -> Dictionary:
	var digest := FileAccess.get_sha256(path)
	if digest.length() != 64: errors.append("Missing packed resource: " + path)
	return {"path":path.trim_prefix("res://"), "sha256":digest}

func walk(directory: String) -> void:
	for name: String in DirAccess.get_files_at(directory):
		var full := directory.path_join(name)
		var source := full.trim_suffix(".import").trim_suffix(".remap")
		if source.get_extension().to_lower() in ["otf","ttf","ttc","woff","woff2"]:
			fonts.append(source.trim_prefix("res://"))
		if full.ends_with(".import"):
			var imported := ConfigFile.new()
			if imported.load(full) != OK or imported.get_value("deps","source_file",source) != source:
				errors.append("Invalid import metadata: " + full)
				continue
			var payload: Array[Dictionary] = []
			for key: String in imported.get_section_keys("remap"):
				if key == "path" or key.begins_with("path."):
					payload.append(fingerprint(imported.get_value("remap",key)))
			if payload.is_empty(): errors.append("No imported bytes: " + full)
			content.append({"source":source.trim_prefix("res://"), "payload":payload})
		elif full.begins_with("res://data/") and full.ends_with(".remap"):
			var remap := ConfigFile.new()
			if remap.load(full) != OK:
				errors.append("Invalid data remap: " + full)
				continue
			content.append({"source":source.trim_prefix("res://"), "payload":[fingerprint(remap.get_value("remap","path",""))]})
		elif full.begins_with("res://assets/") or full.begins_with("res://data/"):
			var raw := {"source":full.trim_prefix("res://"), "payload":[fingerprint(full)]}
			if full.ends_with(".json"): raw["json_base64"] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(full))
			content.append(raw)
	for child: String in DirAccess.get_directories_at(directory):
		walk(directory.path_join(child))

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not FileAccess.file_exists("res://project.binary"):
		push_error("Supply a destination and mount the exported pack.")
		quit(1)
		return
	walk("res://")
	if not errors.is_empty():
		for error: String in errors: push_error(error)
		quit(1)
		return
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	if file == null:
		push_error("Cannot write the content inventory.")
		quit(1)
		return
	content.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.source < b.source)
	fonts.sort()
	file.store_string(JSON.stringify({"version":ProjectSettings.get_setting("application/config/version"),"content":content,"fonts":fonts}))
	file.close()
	quit()
