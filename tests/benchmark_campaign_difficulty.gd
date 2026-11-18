extends "res://tests/benchmark_campaign_requisitions.gd"

func run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var shard: int = int(arguments[0]) if arguments.size() > 0 else 0
	var shards: int = int(arguments[1]) if arguments.size() > 1 else 1
	if shard < 0 or shard >= shards:
		push_error("Invalid difficulty sample shard")
		quit(1)
		return
	var catalog: RefCounted = Campaign.new()
	var ids: Array = catalog.index.scenarios.keys()
	ids.sort()
	var results: Array[Dictionary] = []
	var failures: int = 0
	for index: int in range(shard, ids.size(), shards):
		var id: String = ids[index]
		var setup: Dictionary = catalog.index.scenarios[id]
		# Include the same production pilot on both seats for every scenario.
		# Compare the focused pilot too where the published route has one.
		var pilots: Array[bool] = [false]
		if pilot_for(id) != AI: pilots.append(true)
		for focus: bool in pilots:
			for mode: String in [Session.Difficulty.STANDARD, Session.Difficulty.STORY]:
				var value: Dictionary = run_match(id, setup, "", {}, mode, focus)
				value["difficulty"] = mode
				value["focused"] = focus
				results.append(value)
				if not value.error.is_empty(): failures += 1
				print("DIFFICULTY %s %s · focus %s · winner %d · turn %d · actions %d · %s" % [id, mode, focus, value.winner, value.turn, value.actions, value.error])
				await process_frame
	var file := FileAccess.open("res://.tools/v052-difficulty-%d-of-%d.json" % [shard, shards], FileAccess.WRITE)
	if file == null:
		push_error("Unable to write the difficulty sample")
		quit(1)
		return
	file.store_string(JSON.stringify({"matches": results, "failures": failures}, "	", true, true))
	file.close()
	print("DIFFICULTY SAMPLE %d | FAILURES %d" % [results.size(), failures])
	quit(0 if failures == 0 else 1)
