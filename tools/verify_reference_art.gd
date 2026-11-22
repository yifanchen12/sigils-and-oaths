extends SceneTree
## Replay legal actions and verify all renamed cards and full-art identities.
## The same external script can run against an exported Windows PCK.

const Scene = preload("res://scenes/main.tscn")
const Model = preload("res://scripts/battle.gd")
const AI = preload("res://scripts/opponent.gd")
const Art = preload("res://scripts/art_library.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Settings = preload("res://scripts/settings_store.gd")
const Campaign = preload("res://scripts/campaign_session.gd")
const DeckStore = preload("res://scripts/deck_store.gd")
const SUBJECTS := ["shore_medic", "ash_notary"]
const DECK := {"id": "custom", "name": "美术验收", "description": "",
	"cards": {"shore_medic": 4, "ash_notary": 4, "sword": 4, "spear": 4, "archer": 4, "healer": 4, "ward": 2, "heal": 2, "insight": 2}}
var game: Control
var viewport: SubViewport
var checks := 0
var failures := 0
var output: String

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
	return condition

func photograph(name: String) -> void:
	for frame in 6:
		await process_frame
		game._position_battle_peek()
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image.get_size() == Vector2i(1920, 1080) and image.save_png(output.path_join(name + ".png")) == OK, "native screenshot")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or not DirAccess.dir_exists_absolute(args[0]) or DisplayServer.get_name() == "headless":
		push_error("Supply an existing absolute output directory and use a native renderer.")
		quit(2)
		return
	output = args[0]
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.size_2d_override = Vector2i(1778, 1000)
	viewport.size_2d_override_stretch = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	game = Scene.instantiate()
	game.settings_store = Settings.new(output.path_join("preferences.cfg"))
	game.campaign_session = Campaign.new(output.path_join("campaign.json"))
	game.deck_store = DeckStore.new(output.path_join("deck.json"))
	check(game.deck_store.save_deck(DECK.cards).ok, "valid custom deck")
	viewport.add_child(game)
	game.set_process(false)
	game.audio.stop_playback()
	AudioServer.set_bus_mute(0, true)
	for frame in 5: await process_frame
	game.council.open("rivergate", "grove", false, "custom", "balanced")
	game.council.start_button.pressed.emit()
	var battle: Battle = game.battle
	if not check(battle.deck(0).cards == DECK.cards and battle.deck(1).id == "balanced", "normal council uses selected decks"):
		quit(1)
		return
	var captured: Dictionary = {}
	var identities: Dictionary = {}
	var verified_skills: Dictionary = {}
	for step in 400:
		if battle.winner != -1: break
		var action := AI.choose(battle)
		if battle.active_side == 0:
			for legal in battle.get_legal_actions(0):
				if legal.type == "play" and battle.hand_card(0, legal.card_uid).card_id in SUBJECTS:
					var id: String = battle.hand_card(0, legal.card_uid).card_id
					if not captured.has(id):
						action = legal
						break
			for legal in battle.get_legal_actions(0):
				if legal.type == "unit_skill":
					var id := battle.unit_art_id(battle.get_unit(legal.unit_id))
					if id in SUBJECTS and not verified_skills.has(id):
						action = legal
						verified_skills[id] = true
						break
		var arriving: String = ""
		if battle.active_side == 0 and action.type == "play":
			arriving = battle.hand_card(0, action.card_uid).card_id
		if not check(game._apply_with_feedback(action).ok, "legal action before art verification"): break
		if arriving in SUBJECTS and not captured.has(arriving):
			var actor: Dictionary = battle.unit_at(action.target)
			if not check(not actor.is_empty() and battle.unit_art_id(actor) == arriving, "deployed troop keeps card ID"): break
			identities[arriving] = actor.id
			captured[arriving] = true
			game.board.set_process(false)
			game.board.reset_effects()
			game.board.fit_map()
			for frame in 3: await process_frame
			game.board.zoom_at(game.board.size / 2, 1.45)
			game.board.pan_by(Vector2(0, game.board.size.y * 0.55 - game.board.cell_center(actor.pos).y))
			game.selected_unit = actor.id
			game.board.hover_cell = actor.pos
			game._on_cell_hovered(actor.pos)
			game._refresh()
			var standing := Art.get_texture("sprite_" + arriving) as AtlasTexture
			var portrait := Art.get_texture(arriving) as AtlasTexture
			check(standing.atlas.resource_path.ends_with("/pieces/cast-28.png") and portrait.atlas.resource_path.ends_with("/expansion/cast-28.png"), "new portrait and chibi figure are both active")
			check(game.battle_peek.portrait.texture == portrait, "hover portrait follows the same deployed card")
			await photograph("27-white-feather-medic" if arriving == "shore_medic" else "28-crimson-parasol-mage")
			check(game.battle_peek.is_visible_in_tree(), "card portrait is visible beside board")
			var loaded := Snapshot.restore(JSON.parse_string(JSON.stringify(Snapshot.capture(battle), "", true, true)))
			check(loaded.ok and loaded.battle.unit_art_id(loaded.battle.get_unit(actor.id)) == arriving, "round-trip restores new visual identity")
			print("REDRAW | ", arriving, " | action ", step + 1, " | unit ", actor.id, " | ", battle.cell_name(actor.pos))
			game.board.set_process(true)
		if captured.size() == 2 and verified_skills.size() == 2: break
		if step % 20 == 0: await process_frame
	check(captured.size() == 2, "both new characters deployed and photographed")
	check(verified_skills.size() == 2, "each new character used its normal active skill")
	game._open_library()
	for card: Dictionary in Model.CATALOG.cards:
		game._library_details(card, 0)
		check(game.get_node("%LibraryDetails").text.contains(card.name), "current name reaches the native library")
		check(game.get_node("%LibraryArtButton").disabled == (card.type != "unit"), "full artwork is available only for unit cards")
		if card.type == "unit":
			game._open_character_art()
			check(game.get_node("%CharacterArt").texture == Art.Redrawn.full_body(card.id), "full-body viewer keeps selected identity")
			check(game.get_node("%CharacterArtTitle").text == card.name, "full artwork uses current card name")
			game.get_node("%CharacterArtDialog").hide()
	game._library_details(Model.CATALOG.find("ash_notary"), 0)
	await photograph("29-renamed-card-library")
	game.get_node("%LibraryArtButton").pressed.emit()
	await photograph("30-parasol-full-art")
	check(game.get_node("%CharacterArtDialog").visible, "full-body viewer opened from the visible button")
	game.get_node("%CharacterArtDialog").hide()
	viewport.size = Vector2i(1008, 700)
	viewport.size_2d_override = Vector2i(1008, 700)
	for frame in 5: await process_frame
	game._open_character_art()
	for frame in 5: await process_frame
	var art_dialog: Window = game.get_node("%CharacterArtDialog")
	check(Rect2i(Vector2i.ZERO, viewport.size).encloses(Rect2i(art_dialog.position, art_dialog.size)), "full illustration dialog fits the minimum window")
	check(game.get_node("%CharacterArt").size.y > 350, "minimum window retains a usable full-art area")
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(output.path_join("31-full-art-small.png")) == OK, "minimum-window illustration screenshot")
	art_dialog.hide()
	game.get_node("%CardsDialog").hide()
	print("REFERENCE ART | ", checks, " checks | ", failures, " failures")
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
