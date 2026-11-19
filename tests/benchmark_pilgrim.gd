extends "res://tests/benchmark_moorings.gd"

const PILGRIM_PAIRS: Array[Array] = [
	["chalkline_vanguard", "cairn_watch"], ["chalkline_vanguard", "bellfoundry_column"], ["cairn_watch", "bellfoundry_column"],
	["chalkline_vanguard", "breakwater_line"], ["cairn_watch", "lantern_convoy"], ["bellfoundry_column", "frost_engine"]
]

func run() -> void:
	run_suite("pilgrim", 5101, PILGRIM_PAIRS)
