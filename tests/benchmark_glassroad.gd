extends "res://tests/benchmark_moorings.gd"

const GLASSROAD_PAIRS: Array[Array] = [
	["glassroad_vanguard", "glassroad_reserve"], ["glassroad_vanguard", "glassroad_ambush"],
	["glassroad_vanguard", "glassroad_edict"], ["glassroad_reserve", "glassroad_ambush"],
	["glassroad_reserve", "glassroad_edict"], ["glassroad_ambush", "glassroad_edict"],
	["glassroad_vanguard", "bellfoundry_column"], ["glassroad_reserve", "bellfoundry_column"],
	["glassroad_ambush", "balanced"], ["glassroad_edict", "frost_engine"]
]

func run() -> void:
	run_suite("glassroad", 5301, GLASSROAD_PAIRS)
