extends SceneTree

const BattleModel = preload("res://scripts/battle.gd")
const Store = preload("res://scripts/deck_store.gd")
const EnemyAI = preload("res://scripts/opponent.gd")
const PATH: String = "res://.tools/test_custom_deck.json"
const CROSS_PATH: String = "res://.tools/cross_process_deck.json"
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func cleanup(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func counts() -> Dictionary:
	return BattleModel.DECKS.find("balanced").cards.duplicate(true)

func custom_counts() -> Dictionary:
	var result: Dictionary = counts()
	result.sword -= 1
	result.mage += 1
	return result

func run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--write-fixture"):
		cleanup(CROSS_PATH)
		check(Store.new(CROSS_PATH).save_deck(custom_counts()).ok, "first process saves complete deck")
	elif arguments.has("--read-fixture"):
		var loaded: Dictionary = Store.new(CROSS_PATH).load_deck()
		check(loaded.ok and loaded.definition.cards == custom_counts(), "fresh process reads identical saved counts")
		var main = load("res://scenes/main.tscn").instantiate()
		main.deck_store = Store.new(CROSS_PATH)
		root.add_child(main)
		await process_frame
		check(main.custom_deck.cards == custom_counts(), "fresh app restores custom deck definition")
		var found: bool = false
		for index: int in range(main.council.deck_choice.item_count):
			if main.council.deck_choice.get_item_metadata(index) == "custom": found = true
		check(found, "fresh app exposes saved custom deck in war council")
		main.queue_free()
		await process_frame
		cleanup(CROSS_PATH)
	else:
		test_validation()
		test_storage()
		test_battle_snapshot()
		test_custom_matches()
	print("DECK STORE CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func valid(data: Variant) -> bool:
	return BattleModel.DECKS.validate_counts(data, BattleModel.CATALOG.cards).is_empty()

func test_validation() -> void:
	check(valid(counts()), "preset is legal custom starting point")
	for value: Variant in [null, [], "bad"]: check(not valid(value), "reject non-dictionary counts")
	for value: Variant in [-1, 5, 1.5, true, "3", NAN, INF]:
		var broken: Dictionary = counts()
		broken.sword = value
		check(not valid(broken), "reject invalid count " + str(value))
	var short_deck: Dictionary = counts()
	short_deck.sword -= 1
	check(not valid(short_deck), "29 cards cannot be saved")
	for card_id: String in ["initiative", "unknown"]:
		var illegal: Dictionary = counts()
		illegal[card_id] = 0
		check(not valid(illegal), "generated or unknown card rejected even with zero count")
	var spells: Dictionary = {}
	var remaining: int = 30
	for card: Dictionary in BattleModel.CATALOG.cards:
		if card.type == "unit" or card.get("generated_only", false): continue
		spells[card.id] = mini(4, remaining)
		remaining -= int(spells[card.id])
	check(not valid(spells), "all-spell deck cannot start")
	var numeric: Dictionary = counts()
	numeric.sword = 3.0
	check(valid(numeric), "JSON finite whole-number floats accepted")

func write_raw(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func test_storage() -> void:
	cleanup(PATH)
	var store: DeckStore = Store.new(PATH)
	check(not store.load_deck().ok, "missing save is recoverable")
	check(store.save_deck(counts()).ok, "first valid save succeeds")
	check(Store.new(PATH).load_deck().definition.cards == counts(), "new store instance reads saved deck")
	var original: String = FileAccess.get_file_as_string(PATH)
	check(not store.save_deck({"sword": 1}).ok and FileAccess.get_file_as_string(PATH) == original, "invalid save cannot overwrite valid file")
	check(store.save_deck(custom_counts()).ok, "replacement save succeeds")
	check(FileAccess.file_exists(PATH + ".bak"), "replacement preserves last good save")
	write_raw(PATH, "{broken")
	var recovered: Dictionary = store.load_deck()
	check(recovered.ok and recovered.get("recovered", false) and recovered.definition.cards == counts(), "corrupt primary falls back to valid backup")
	check(store.save_deck(custom_counts()).ok, "saving after recovery repairs primary")
	check(Store.new(PATH + ".bak").load_deck().definition.cards == counts(), "corrupt primary never replaces valid backup")
	var future: String = JSON.stringify({"version": 2, "cards": counts()})
	write_raw(PATH, future)
	check(store.load_deck().get("future", false), "future schema is reported instead of silently loading old backup")
	check(not store.save_deck(counts()).ok and FileAccess.get_file_as_string(PATH) == future, "future schema cannot be overwritten")
	check(not Store.new("res://.tools/__deck_store_uncreated__/deck.json").save_deck(counts()).ok, "write error is returned to caller")
	cleanup(PATH)

func test_battle_snapshot() -> void:
	var saved: Dictionary = Store.new(PATH).definition(custom_counts())
	var game: Battle = BattleModel.new(81, "greenwood", "warden", "grove", "custom", "balanced", 90, saved)
	var own_cards: Array = game.players[0].hand + game.players[0].deck
	var mages: int = 0
	for card: Dictionary in own_cards:
		if card.card_id == "mage": mages += 1
	check(game.deck(0).id == "custom" and mages == 4 and own_cards.size() == 30, "custom counts build actual shuffled battle deck")
	check(game.deck(1).id == "balanced" and game.deck(1).cards.mage == 3, "opponent preset remains independent")
	saved.cards.mage = 0
	check(game.deck(0).cards.mage == 4, "battle owns snapshot independent of editor definition")
	check(BattleModel.DECKS.find("balanced").cards.mage == 3, "custom build never mutates shared presets")
	var invalid: Battle = BattleModel.new(82, "greenwood", "warden", "grove", "custom", "balanced", 90, {"cards": {"sword": 1}})
	check(invalid.deck(0).id == "balanced" and invalid.deck_size == 30, "invalid custom input cannot enter battle as invalid deck")

func test_custom_matches() -> void:
	var spell_heavy: Dictionary = {"sword": 1}
	var remaining: int = 29
	for card: Dictionary in BattleModel.CATALOG.cards:
		if card.type == "unit" or card.get("generated_only", false): continue
		spell_heavy[card.id] = mini(4, remaining)
		remaining -= int(spell_heavy[card.id])
	var decks: Array[Dictionary] = [custom_counts(), spell_heavy]
	for deck_counts: Dictionary in decks:
		var game: Battle = BattleModel.new(91, "harbor", "grove", "warden", "custom", "balanced", 90, Store.new(PATH).definition(deck_counts))
		var actions: int = 0
		var legal: bool = true
		while game.winner == -1 and actions < 1000:
			if not game.apply_action(EnemyAI.choose(game)).ok:
				legal = false
				break
			actions += 1
		check(legal and game.winner != -1, "custom deck including minimum-one-troop extreme completes legal AI match")
		for side: int in range(2):
			var cards: Array = game.players[side].hand + game.players[side].deck + game.players[side].discard
			for unit: Dictionary in game.units:
				if unit.side == side and unit.has("card"): cards.append(unit.card)
			var uids: Dictionary = {}
			for card: Dictionary in cards: uids[card.uid] = true
			check(uids.size() == cards.size() and cards.size() == game.players[side].card_total, "custom match preserves unique cards across all zones")
