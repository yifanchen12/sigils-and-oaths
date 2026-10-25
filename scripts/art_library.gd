class_name ArtLibrary
extends RefCounted
## Texture cache and native atlas/crop presentation; generated source files stay intact.

static var textures: Dictionary = {}
const UNIT_ORDER: Array[String] = ["sword", "spear", "cavalry", "archer", "mage", "healer"]
const HERO_ORDER: Array[String] = ["warden", "pyromancer", "grove"]
const TERRAIN_ORDER: Array[String] = ["plain", "forest", "mountain", "road", "water", "bridge", "hill", "ruins", "fort"]
const MAP_PROPS: Array[String] = ["map_forest", "map_mountain", "map_fort"]
const MAP_PROPS_EXTRA: Array[String] = ["map_hill", "map_ruins", "map_harbor_fort"]
const MAP_BIOME_PROPS: Array[String] = ["map_pines", "map_acacia", "map_gate"]
const MAP_LANDFORMS: Array[String] = ["map_rock_mountain", "map_sand_mountain", "map_plateau"]
const SPELL_ATLASES: Dictionary = {
	"spells_1": ["bolt", "nova", "heal"], "spells_2": ["ward", "march", "insight"],
	"weather_1": ["rain", "fog", "sun"], "weather_2": ["snow", "clear_skies", "initiative"],
	"tactics_1": ["repulse", "frostbind", "dispel"], "tactics_2": ["exchange", "onslaught", "rampart"]
}

static func get_texture(asset_id: String) -> Texture2D:
	if textures.has(asset_id): return textures[asset_id]
	var path: String = "res://assets/art/%s.png" % asset_id
	if asset_id == "menu" and ResourceLoader.exists("res://assets/art/menu_cel.png"): path = "res://assets/art/menu_cel.png"
	if asset_id == "trail" and ResourceLoader.exists("res://assets/art/trail_cel.png"): path = "res://assets/art/trail_cel.png"
	if asset_id.begins_with("battlefield_"): path = "res://assets/art/battlefields/%s-v2.png" % asset_id.trim_prefix("battlefield_")
	var texture: Texture2D = null
	for atlas_id: String in SPELL_ATLASES:
		var index: int = SPELL_ATLASES[atlas_id].find(asset_id)
		if index >= 0:
			var spell_path: String = "res://assets/art/%s_cel.png" % atlas_id
			if not ResourceLoader.exists(spell_path): spell_path = "res://assets/art/%s.png" % atlas_id
			texture = _atlas(spell_path, index, 3, 1)
			if texture != null:
				textures[asset_id] = texture
				return texture
	if ResourceLoader.exists(path):
		texture = load(path)
	elif HERO_ORDER.has(asset_id) and ResourceLoader.exists("res://assets/art/heroes.png"):
		var hero_path: String = "res://assets/art/heroes_cel.png" if ResourceLoader.exists("res://assets/art/heroes_cel.png") else "res://assets/art/heroes_mature.png"
		texture = _atlas(hero_path if ResourceLoader.exists(hero_path) else "res://assets/art/heroes.png", HERO_ORDER.find(asset_id), 3, 1)
	elif UNIT_ORDER.has(asset_id) and ResourceLoader.exists("res://assets/art/units.png"):
		var index: int = UNIT_ORDER.find(asset_id)
		var mature_path: String = "res://assets/art/unit_portraits_%d.png" % (index / 3 + 1)
		var cel_path: String = "res://assets/art/unit_portraits_cel_%d.png" % (index / 3 + 1)
		if ResourceLoader.exists(cel_path): mature_path = cel_path
		texture = _atlas(mature_path, index % 3, 3, 1) if ResourceLoader.exists(mature_path) else _atlas("res://assets/art/units.png", index, 3, 2)
	elif MAP_PROPS.has(asset_id):
		texture = _atlas("res://assets/art/map_props.png", MAP_PROPS.find(asset_id), 3, 1)
	elif MAP_PROPS_EXTRA.has(asset_id):
		texture = _atlas("res://assets/art/map_props_extra.png", MAP_PROPS_EXTRA.find(asset_id), 3, 1)
	elif MAP_BIOME_PROPS.has(asset_id):
		texture = _atlas("res://assets/art/map_biome_props.png", MAP_BIOME_PROPS.find(asset_id), 3, 1)
	elif MAP_LANDFORMS.has(asset_id):
		texture = _atlas("res://assets/art/map_landforms.png", MAP_LANDFORMS.find(asset_id), 3, 1)
	elif asset_id.begins_with("ground_"):
		var index: int = ["grass", "sand", "water"].find(asset_id.trim_prefix("ground_"))
		if index >= 0: texture = _atlas("res://assets/art/map_ground.png", index, 3, 1)
	elif asset_id.begins_with("sprite_"):
		var kind: String = asset_id.trim_prefix("sprite_")
		if UNIT_ORDER.has(kind):
			var index: int = UNIT_ORDER.find(kind)
			var sprite_path: String = "res://assets/art/unit_sprites_cel_%d.png" % (index / 3 + 1)
			if not ResourceLoader.exists(sprite_path): sprite_path = "res://assets/art/unit_sprites_mature_%d.png" % (index / 3 + 1)
			texture = _atlas(sprite_path, index % 3, 3, 1)
		elif HERO_ORDER.has(kind):
			var sprite_path: String = "res://assets/art/hero_sprites_cel.png" if ResourceLoader.exists("res://assets/art/hero_sprites_cel.png") else "res://assets/art/hero_sprites_mature.png"
			texture = _atlas(sprite_path, HERO_ORDER.find(kind), 3, 1)
	elif asset_id.begins_with("terrain_"):
		var index: int = TERRAIN_ORDER.find(asset_id.trim_prefix("terrain_"))
		if index >= 0: texture = _atlas("res://assets/art/terrain_%d.png" % (index / 3 + 1), index % 3, 3, 1)
	elif asset_id == "rampart": texture = get_texture("terrain_fort")
	elif asset_id == "trail": texture = get_texture("terrain_road")
	if texture != null: textures[asset_id] = texture
	return texture

static func _atlas(path: String, index: int, columns: int, rows: int) -> Texture2D:
	if not ResourceLoader.exists(path): return null
	var source: Texture2D = load(path)
	var cell_size: Vector2 = source.get_size() / Vector2(columns, rows)
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.filter_clip = true
	atlas.region = Rect2(Vector2(index % columns, index / columns) * cell_size, cell_size)
	if path.ends_with("unit_sprites_cel_2.png"): atlas.region = atlas.region.grow(-3)
	return atlas

static func draw_cover(canvas: CanvasItem, texture: Texture2D, rect: Rect2, focus: Vector2 = Vector2(0.5, 0.37)) -> void:
	var source_size: Vector2 = texture.get_size()
	var crop: Vector2 = source_size
	var ratio: float = rect.size.x / rect.size.y
	if ratio > source_size.x / source_size.y: crop.y = source_size.x / ratio
	else: crop.x = source_size.y * ratio
	var start: Vector2 = (source_size * focus - crop / 2).clamp(Vector2.ZERO, source_size - crop)
	canvas.draw_texture_rect_region(texture, rect, Rect2(start, crop))

static func card_focus(card: Dictionary) -> Vector2:
	if card.type == "unit": return Vector2(0.5, 0.37)
	var effect_heights: Dictionary = {"trail": 0.64, "bolt": 0.45, "heal": 0.68, "march": 0.34, "insight": 0.58, "frostbind": 0.70, "onslaught": 0.40, "rampart": 0.60, "clear_skies": 0.60}
	return Vector2(0.5, float(effect_heights.get(card.id, 0.5)))

static func draw_round_portrait(canvas: CanvasItem, texture: Texture2D, center: Vector2, radius: float, tint: Color = Color.WHITE) -> void:
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	for step: int in range(40):
		var direction: Vector2 = Vector2.from_angle(step * TAU / 40)
		points.append(center + direction * radius)
		uv.append(Vector2(0.5, 0.36) + direction * Vector2(0.34, 0.34))
	canvas.draw_polygon(points, PackedColorArray([tint]), uv, texture)
