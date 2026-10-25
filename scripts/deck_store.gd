class_name DeckStore
extends RefCounted
## Plain-data single-slot persistence, isolated from the shared card Resources.

const CATALOG = preload("res://data/cards.tres")
const DECKS = preload("res://data/decks.tres")
const VERSION: int = 1
var path: String

func _init(save_path: String = "user://custom_deck.json") -> void:
	path = save_path

func definition(counts: Dictionary) -> Dictionary:
	return {"id": "custom", "name": "自定义军势", "description": "本地保存的自定义套牌；己方使用，AI使用均衡军势。", "cards": DECKS.canonical_counts(counts, CATALOG.cards)}

func _read_path(source: String) -> Dictionary:
	if not FileAccess.file_exists(source): return {"ok": false, "message": "尚未保存自定义套牌。"}
	var file: FileAccess = FileAccess.open(source, FileAccess.READ)
	if file == null or file.get_length() > 65536: return {"ok": false, "message": "无法读取套牌文件。"}
	var parser := JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary: return {"ok": false, "message": "套牌文件格式损坏。"}
	var data: Dictionary = parser.data
	var version: Variant = data.get("version", null)
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(version)) or float(version) != floorf(float(version)):
		return {"ok": false, "message": "套牌版本无效。"}
	if version > VERSION: return {"ok": false, "future": true, "message": "套牌来自较新版本，当前版本不会覆盖它。"}
	if version != VERSION: return {"ok": false, "message": "不支持此套牌版本。"}
	var message: String = DECKS.validate_counts(data.get("cards"), CATALOG.cards)
	if not message.is_empty(): return {"ok": false, "message": message}
	return {"ok": true, "definition": definition(data.cards)}

func load_deck() -> Dictionary:
	var primary: Dictionary = _read_path(path)
	if primary.ok or primary.get("future", false): return primary
	var backup: Dictionary = _read_path(path + ".bak")
	if backup.ok:
		backup["recovered"] = true
		backup["message"] = "已从上次有效备份恢复套牌。"
		return backup
	return primary

func save_deck(counts: Variant) -> Dictionary:
	var message: String = DECKS.validate_counts(counts, CATALOG.cards)
	if not message.is_empty(): return {"ok": false, "message": message}
	var existing: Dictionary = _read_path(path)
	if existing.get("future", false): return existing
	var target: Dictionary = definition(counts)
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return {"ok": false, "message": "保存失败：无法写入本地套牌文件。"}
	var stored: bool = file.store_string(JSON.stringify({"version": VERSION, "cards": target.cards}, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not stored or write_error != OK: return {"ok": false, "message": "保存失败：写入未完成，原套牌已保留。"}
	if existing.ok:
		var backup_error: Error = DirAccess.copy_absolute(path, path + ".bak")
		if backup_error != OK: return {"ok": false, "message": "保存失败：无法保留上次套牌，未覆盖原文件。"}
	var rename_error: Error = DirAccess.rename_absolute(path + ".tmp", path)
	if rename_error != OK: return {"ok": false, "message": "保存失败：无法替换文件，可从上次备份恢复。"}
	return {"ok": true, "definition": target}
