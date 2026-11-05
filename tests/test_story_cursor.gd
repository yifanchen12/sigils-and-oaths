extends SceneTree

const Story = preload("res://scripts/story_runner.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func fixture() -> Dictionary:
	return {"version": 1, "id": "cursor", "title": "Cursor", "start": "a", "defaults": {"fact": false}, "speakers": {"n": "N"},
		"strings": {"first": "First", "last": "Last", "hidden": "Hidden", "end": "End"}, "nodes": {
		"a": {"type": "dialogue", "lines": [{"id": "first", "speaker": "n"}, {"id": "hidden", "speaker": "n", "when": {"fact": true}}, {"id": "last", "speaker": "n"}], "next": "end"},
		"end": {"type": "end", "text": "end", "ending": "done"}}}
func run() -> void:
	var original: RefCounted = Story.new(fixture())
	original.advance(0)
	var saved: Dictionary = original.snapshot()
	check(saved.line_id == "last" and saved.line == 2, "stable identity is exported with legacy offset")
	var edited: Dictionary = fixture()
	edited.strings["inserted"] = "Inserted"
	edited.nodes.a.lines.insert(0, {"id": "inserted", "speaker": "n"})
	var revised: RefCounted = Story.new(edited)
	check(revised.restore(saved).ok and revised.current().line_id == "last" and revised.state.line == 3, "inserting earlier text keeps the same unread line")
	edited.nodes.a.lines.reverse()
	var reordered: RefCounted = Story.new(edited)
	check(reordered.restore(saved).ok and reordered.state.line == 0, "reordering preserves current identity even with an obsolete offset")
	check(reordered.state.history == saved.history, "editing does not fabricate previously read text")
	var legacy: Dictionary = saved.duplicate(true); legacy.erase("line_id")
	check(original.restore(legacy).ok and original.current().line_id == "last", "legacy index-only save loads")
	check(original.snapshot().line_id == "last", "legacy restore upgrades cursor on next capture")
	var before: Dictionary = original.snapshot()
	for id: Variant in ["gone", "hidden", "end", "", true, 1, []]:
		var broken: Dictionary = saved.duplicate(true); broken.line_id = id
		check(not original.restore(broken).ok and original.snapshot() == before, "invalid or invisible identity rejected atomically")
	edited = fixture(); edited.nodes.a.lines.append(edited.nodes.a.lines[0].duplicate())
	check(not Story.validate(edited).is_empty(), "duplicate dialogue identities rejected")
	edited = fixture(); edited["inherits"] = ["fact", "fact"]
	check(not Story.validate(edited).is_empty(), "duplicate inherited facts rejected")
	edited["inherits"] = ["unknown"]
	check(not Story.validate(edited).is_empty(), "unknown inherited facts rejected")
	check(original.advance(original.current().revision).ok and original.current().type == "end", "restored line advances to end once")
	check(original.snapshot().line_id == "", "non-dialogue cursor has empty identity")
	# Scene changes are presentation metadata, including when restoring old saves.
	var staged: Dictionary = fixture()
	staged.nodes.a["background"] = "scene_foundry"
	staged.nodes.a.lines[2]["background"] = "scene_pump_closed"
	var scenic: RefCounted = Story.new(staged)
	check(scenic.current().background == "scene_foundry", "line without override uses its node scene")
	check(scenic.restore(saved).ok and scenic.current().background == "scene_pump_closed", "old stable cursor restores the authored scene transition")
	check(scenic.snapshot() == saved, "scene metadata does not rewrite progress or history")
	check(scenic.restore(legacy).ok and scenic.current().background == "scene_pump_closed", "legacy offset save also restores the scene")
	scenic.advance(scenic.current().revision)
	check(scenic.current().background == "", "line override does not leak into the next node")
	for invalid: Variant in [false, 3, [], {}, ""]:
		var broken_scene: Dictionary = staged.duplicate(true)
		broken_scene.nodes.a.lines[2].background = invalid
		check(not Story.validate(broken_scene).is_empty(), "invalid line scene rejected")
	staged.nodes.a.background = 7
	check(not Story.validate(staged).is_empty(), "invalid node scene rejected")
	print("STORY CURSOR CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)
