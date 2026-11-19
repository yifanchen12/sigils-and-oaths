extends SceneTree
## Run against a release PCK from a separate process, with an isolated AppData folder.

const Session = preload("res://scripts/campaign_session.gd")
const Settings = preload("res://scripts/settings_store.gd")
const AI = preload("res://scripts/opponent.gd")
const SAVE_PATH := "user://campaign_autosave.json"
const DECK_PATH := "user://custom_deck.json"
const SETTINGS_PATH := "user://settings.cfg"
const PREFERENCES: Dictionary = {"fullscreen": false, "reading_size": 130, "reduce_motion": true, "music": 31, "effects": 42}
const EXPECTED_TIME := 83.75

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not require(args.size() == 2 and args[0] in ["seed", "resume"], "Use seed or resume and the expected build version."): return
	var isolated: String = OS.get_environment("SIGILS_INSTALL_TEST_PROFILE").replace("\\", "/").simplify_path()
	var actual: String = OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if not require(not isolated.is_empty() and actual.to_lower().begins_with(isolated.to_lower() + "/"), "The game data folder is outside the isolated install test profile."): return
	if not require(ProjectSettings.get_setting("application/config/version") == args[1], "The loaded PCK must match the expected build version."): return
	if args[0] == "seed":
		if not require(not FileAccess.file_exists(SAVE_PATH) and not FileAccess.file_exists(DECK_PATH) and not FileAccess.file_exists(SETTINGS_PATH), "Start with a fresh test profile."): return
		if not require(Settings.new().save_preferences(PREFERENCES).ok, "Write preferences in the old build."): return
		if not require(DeckStore.new().save_deck(Battle.DECKS.find("glassroad_reserve").cards).ok, "Write a legal custom deck."): return
		if not require(seed_campaign(), "Play and save the old build's first campaign battle."): return
	if not read_profile(): return
	print("INSTALLER PROFILE ", args[0], " OK | ", args[1], " | campaign, deck, settings")
	quit(0)

func seed_campaign() -> bool:
	var session = Session.new()
	if not session.new_campaign().ok: return false
	for step: int in range(350):
		var page: Dictionary = session.current()
		match String(page.type):
			"dialogue":
				if not session.advance(session.token()).ok: return false
			"choice":
				var choice: String = "road" if page.node == "route" else page.options[0].id
				if not session.choose(choice, session.token()).ok: return false
			"battle":
				if not session.choose_difficulty("story", session.token()).ok or not session.begin_battle(session.token()).ok: return false
				var battle: Battle = session.encounter
				for action: int in range(100):
					if battle.active_side == 0 and battle.hand_played_this_turn:
						battle.advance_clock(90.0 - EXPECTED_TIME)
						return session.save().ok
					if not battle.apply_action(AI.choose(battle)).ok: return false
				return false
			_:
				return false
	return false

func read_profile() -> bool:
	var preferences: Dictionary = Settings.new().load_preferences()
	if not require(preferences.values == PREFERENCES and preferences.notice.is_empty(), "Preferences reopen at the same values."): return false
	var deck: Dictionary = DeckStore.new().load_deck()
	if not require(deck.ok and deck.definition.cards == Battle.DECKS.find("glassroad_reserve").cards, "Custom cards reopen at the same counts."): return false
	var session = Session.new()
	if not require(session.load_campaign().ok and session.encounter != null, "Campaign resumes in the battle saved in the old build."): return false
	var battle: Battle = session.encounter
	if not require(session.campaign.difficulty == "story" and battle.active_side == 0 and battle.hand_played_this_turn and battle.time_remaining == EXPECTED_TIME,
			"Campaign difficulty, active side, hand action and clock are preserved."): return false
	return require(battle.apply_action(AI.choose(battle)).ok, "The restored battle still accepts a legal action.")
