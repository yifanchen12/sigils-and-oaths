extends "res://tests/benchmark_campaign_requisitions.gd"
## Compare authored starts, using declared alternatives in the same scenario.

const PROFILES: Array[Dictionary] = [
	{"vanguard": "quiet_net", "company": "shoal_arbalest", "reserve": "copper_boltline"},
	{"vanguard": "seam_shot", "company": "levee_echo", "reserve": "unbroken_ember_line"},
	{"vanguard": "bank_pikeman", "company": "sluice_flags", "reserve": "sunken_weir_breach"},
	{"vanguard": "saltfield_runner", "company": "cress_ribbon", "reserve": "crownless_vanguard"},
]
const SCENARIOS: Array[String] = ["c03_vent", "c04_pump", "c05_nursery", "c06_court", "c07_saltlane_school",
	"c08_isolate", "c10_split_gate", "c12_split_depot", "c14_upstream_channel", "c16_bridge", "c17_screen"]

func loadouts(completed: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = [{}]
	if Campaign.Armory.unlocked_count(completed) == 1:
		for card: Dictionary in Campaign.Armory.options(Campaign.Armory.SLOTS[0]):
			result.append({"vanguard": card.id})
		return result
	for profile: Dictionary in PROFILES:
		var active: Dictionary = {}
		for slot: Dictionary in Campaign.Armory.SLOTS:
			if completed >= int(slot.unlock_after): active[slot.id] = profile[slot.id]
		result.append(active)
	return result

func run() -> void:
	var catalog = Campaign.new()
	var scenarios: Array[String] = SCENARIOS.duplicate()
	var destination: String = "res://.tools/v050-armory-diagnostic.json"
	var shard: int = 0
	var shards: int = 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="): scenarios = [arg.trim_prefix("--scenario=")]
		if arg.begins_with("--report="): destination = arg.trim_prefix("--report=")
		if arg.begins_with("--shard="): shard = int(arg.trim_prefix("--shard="))
		if arg.begins_with("--shards="): shards = int(arg.trim_prefix("--shards="))
	if shards <= 0 or shard < 0 or shard >= shards:
		push_error("Invalid armory shard")
		quit(1)
		return
	var rows: Array[Dictionary] = []
	var errors: int = 0
	for index: int in range(scenarios.size()):
		if index % shards != shard: continue
		var id: String = scenarios[index]
		if not catalog.index.scenarios.has(id):
			push_error("Unknown scenario " + id)
			quit(1)
			return
		var setup: Dictionary = catalog.index.scenarios[id]
		for equipped: Dictionary in loadouts(int(id.substr(1, 2)) - 1):
			var result: Dictionary = run_match(id, setup, "", equipped)
			rows.append(result)
			if not result.error.is_empty(): errors += 1
			print("ARMORY %s | %s | winner %d | turn %d | actions %d | %s" % [id, equipped, result.winner, result.turn, result.actions, result.error])
			await process_frame
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		push_error("Could not write armory report")
		quit(2)
		return
	file.store_string(JSON.stringify({"matches": rows, "failures": errors}, "\t", true, true))
	file.close()
	print("ARMORY MATCHES %d | ERRORS %d" % [rows.size(), errors])
	quit(0 if errors == 0 else 1)
