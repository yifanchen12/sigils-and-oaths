extends RefCounted
## Shared identity map for adult card art, dialogue cutouts and battle miniatures.
const SHEETS: Dictionary = {
	"cast-00": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"warden",
			"pyromancer",
			"grove"
		]
	},
	"cast-01": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"sword",
			"spear",
			"cavalry"
		]
	},
	"cast-02": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"archer",
			"mage",
			"healer"
		]
	},
	"cast-03": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"reed_scout",
			"gate_veteran",
			"ridge_courier"
		]
	},
	"cast-04": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"ridge_archer",
			"scribe_warden",
			"breakwater_guard"
		]
	},
	"cast-05": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"bronze_watch",
			"quay_lantern",
			"lantern_bearer"
		]
	},
	"cast-06": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"mink_watcher",
			"ferry_pikeman",
			"willow_outlook"
		]
	},
	"cast-07": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"quartermaster",
			"moth_cavalry",
			"kiln_wardens"
		]
	},
	"cast-08": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"carriage_cloak",
			"last_bridge_clinic",
			"copper_gate_requiem"
		]
	},
	"cast-09": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"cinder_runner",
			"ridge_pioneer",
			"quay_salver"
		]
	},
	"cast-10": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"reed_harrier",
			"byway_guard",
			"kiln_outrider"
		]
	},
	"cast-11": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"sandbar_physician",
			"night_surveyor",
			"levee_marshal"
		]
	},
	"cast-12": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"storm_saddle",
			"indigo_gate_mage",
			"sunbreak_column"
		]
	},
	"cast-13": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"lamp_patrol",
			"reed_watch",
			"slate_quartermaster"
		]
	},
	"cast-14": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"bell_winch",
			"rain_saddle",
			"levee_brothers"
		]
	},
	"cast-15": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"rising_oath_watch",
			"lantern_surgeon",
			"saltfield_runner"
		]
	},
	"cast-16": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"bank_pikeman",
			"bastion_driller",
			"shrike_saddler"
		]
	},
	"cast-17": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"sill_physician",
			"shoal_arbalest",
			"oathroad_mender"
		]
	},
	"cast-18": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"undertow_knight",
			"claywatch_sage",
			"crownless_vanguard"
		]
	},
	"cast-19": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"chalk_courier",
			"ridge_listener",
			"linen_lantern"
		]
	},
	"cast-20": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"coalroad_broker",
			"shale_lancer",
			"bracken_hussar"
		]
	},
	"cast-21": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"cairn_colossus",
			"bellfoundry_oracle",
			"whitecord_marshal"
		]
	},
	"cast-22": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"kiln_sparks",
			"marl_shield",
			"river_wasp"
		]
	},
	"cast-23": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"granary_warden",
			"glassroad_runner",
			"rook_pickets"
		]
	},
	"cast-24": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"reedglass_bow",
			"saltband_surgeon",
			"hinge_lancer"
		]
	},
	"cast-25": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"cinder_coxswain",
			"quarry_bugler",
			"copper_cistern"
		]
	},
	"cast-26": {
		"columns": 3,
		"rows": 1,
		"ids": [
			"breakline_sappers",
			"skylens_sentinel",
			"bellroad_captain"
		]
	},
	"cast-27": {
		"columns": 1,
		"rows": 1,
		"ids": [
			"silver_bulwark"
		]
	},
	"cast-28": {
		"columns": 2,
		"rows": 1,
		"ids": [
			"shore_medic",
			"ash_notary"
		]
	}
}

static func texture(kind: String, battlefield: bool = false) -> Texture2D:
	for sheet: String in SHEETS:
		var layout: Dictionary = SHEETS[sheet]
		var slot: int = layout.ids.find(kind)
		if slot < 0: continue
		var path: String = "res://assets/art/%s/%s.png" % ["pieces" if battlefield else "expansion", sheet]
		if not ResourceLoader.exists(path): return null
		var source: Texture2D = load(path)
		var size: Vector2 = source.get_size() / Vector2(layout.columns, layout.rows)
		var result := AtlasTexture.new()
		result.atlas = source
		result.region = Rect2(Vector2(slot, 0) * size, size)
		if not battlefield: result.region = result.region.grow(-2)
		result.filter_clip = true
		return result
	return null

static func full_body(kind: String) -> Texture2D:
	var path: String = "res://assets/art/characters/v3/full/%s.png" % kind
	return load(path) if ResourceLoader.exists(path) else null

static var availability: Dictionary = {}

static func available(kind: String) -> bool:
	if availability.has(kind): return availability[kind]
	for sheet: String in SHEETS:
		if SHEETS[sheet].ids.has(kind):
			availability[kind] = ResourceLoader.exists("res://assets/art/pieces/%s.png" % sheet)
			return availability[kind]
	availability[kind] = false
	return false
