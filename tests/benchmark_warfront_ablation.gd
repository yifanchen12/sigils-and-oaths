extends "res://tests/benchmark_warfront.gd"
## Isolated balance probes. Changes apply to this test process only.

func run() -> void:
	var variant: String = "capstone"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe="): variant = arg.trim_prefix("--probe=")
	var deck: Dictionary = Model.DECKS.find("frost_engine")
	var counts: Dictionary = deck.cards
	match variant:
		"capstone":
			counts.erase("last_hearth")
			counts["rampart"] = 1
		"early_reach":
			counts.erase("kiln_lance")
			counts.erase("scribe_warden")
			counts.erase("ridge_archer")
			counts["cavalry"] += 1
			counts["healer"] = 1
			counts["rampart"] = 1
		"area_core":
			for card: String in ["last_hearth", "signal_torrent", "hammer_sweep", "mist_spike"]: counts.erase(card)
			counts["nova"] = 1
			counts["bolt"] = 1
			counts["rampart"] = 1
			counts["heal"] = 1
			counts["reveal_traps"] = 1
		_:
			push_error("Unknown probe")
			quit(1)
			return
	var problem: String = Model.DECKS.validate_counts(counts, Model.CATALOG.cards)
	if not problem.is_empty():
		push_error(problem)
		quit(1)
		return
	print("WARFRONT PROBE ", variant)
	await super.run()
