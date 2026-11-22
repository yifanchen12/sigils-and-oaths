extends SceneTree

const Model = preload("res://scripts/battle.gd")
const Art = preload("res://scripts/art_library.gd")
const Fixture = preload("res://tests/fixtures/saved_battle.gd")

var checked := 0
var failures := 0

func expect(value: bool, label: String) -> void:
	checked += 1
	if not value:
		failures += 1
		push_error(label)

func digest(image: Image) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	return hash.finish().hex_encode()

func _initialize() -> void:
	var identities := {}
	var troop_count := 0
	for card: Dictionary in Model.CATALOG.cards:
		if card.type != "unit": continue
		troop_count += 1
		var key: String = card.id
		expect(Art.Redrawn.available(key), "every troop uses the new miniature: " + key)
		expect(Art.Redrawn.full_body(key) != null, "every troop has full-body artwork: " + key)
		var texture := Art.get_texture("sprite_" + key) as AtlasTexture
		expect(texture != null, "missing battlefield figure " + key)
		if texture == null: continue
		var ink := texture.get_image()
		expect(ink != null and ink.get_used_rect().has_area(), "empty figure " + key)
		if ink == null: continue
		var fingerprint := digest(ink)
		expect(not identities.has(fingerprint), "same illustration used for two cards: " + key)
		identities[fingerprint] = key
		var portrait := Art.get_texture(key) as AtlasTexture
		expect(texture.atlas.resource_path.get_file() == portrait.atlas.resource_path.get_file()
			and texture.atlas.resource_path.get_base_dir() == "res://assets/art/pieces",
			"figure and portrait should have matching atlas names: " + key)
		var region := portrait.region.grow(2)
		expect(texture.region.position == (region.position / region.size).round() * 256,
			"figure occupies its own portrait's slot: " + key)
		for pose: int in range(3):
			expect(Art.get_action_texture(key, pose) == null, "combat must not substitute an old character: " + key)
		for side: int in [0, 1]:
			var battle := Model.new(6200)
			if side == 1: battle.apply_action({"type":"end_turn"})
			battle.players[side].max_mana = 10
			battle.players[side].mana = 10
			var instance := Fixture.give(battle, key, side)
			var target: Vector2i = battle.deployment_cells(side)[0]
			var played := battle.apply_action({"type":"play", "card_uid":instance.uid, "target":target})
			var actor := battle.unit_at(target)
			expect(played.ok and not actor.is_empty() and battle.unit_art_id(actor) == key,
				"the deployed figure keeps the hand card identity on side %d: %s" % [side, key])
	expect(identities.size() == troop_count, "one unique illustration for every troop in the catalog")
	for key: String in Art.HERO_ORDER:
		var texture := Art.get_texture("sprite_" + key)
		expect(texture != null and Art.Redrawn.available(key), "redrawn commander miniature: " + key)
		var fingerprint := digest(texture.get_image())
		expect(not identities.has(fingerprint), "commander has a distinct identity: " + key)
		identities[fingerprint] = key
		expect(Art.get_narrative_portrait(key) == Art.Redrawn.full_body(key), "dialogue uses the same redesigned commander")
		for pose: int in range(3):
			expect(Art.get_action_texture(key, pose) == null, "commander does not switch to old action artwork")
	expect(identities.size() == 84, "all 81 troops and three commanders are distinct")
	var campaign := Model.new()
	campaign.set_commander_identity(1, "晒场守卫", "spear")
	expect(campaign.unit_art_id(campaign.commander(1)) == "spear", "honor a campaign commander's own portrait")
	print("UNIT PIECE IDENTITY | %d figures | %d checks | %d failures" % [identities.size(), checked, failures])
	quit(0 if failures == 0 else 1)
