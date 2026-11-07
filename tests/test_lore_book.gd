extends "res://tests/test_unit_skills_ui.gd"

func run() -> void:
	create_timer(60).timeout.connect(func() -> void: push_error("lore book timeout"); quit(2))
	game = MainScene.instantiate(); game.deck_store = Store.new("res://.tools/lore_deck.json")
	root.add_child(game); current_scene = game
	await stage()
	game._open_council(); await settle()
	await click(game.council.lore_button.get_global_rect().get_center())
	var book: Control = game.lore_book
	check(book.visible and book.selected_id == game.council.selected_hero, "real menu opens chosen commander's profile")
	check(book.entries.size() == 18 and book.entry_buttons.size() == 18, "all eighteen entries have directory buttons")
	check(book.close_button.size.y <= 64, "header text does not wrap into a tall narrow column")
	for entry: Dictionary in book.entries:
		var button: Button = book.entry_buttons[entry.id]
		button.get_parent().get_parent().ensure_control_visible(button)
		await settle()
		await click(button.get_global_rect().get_center())
		check(book.selected_id == entry.id and book.heading.text == entry.title, "directory click reaches " + str(entry.id))
		check(book.portrait.texture != null, "profile has existing original artwork " + str(entry.id))
		check(book.paragraphs.get_child_count() == entry.body.size(), "all prose paragraphs rendered " + str(entry.id))
		for index: int in range(entry.body.size()):
			check(book.paragraphs.get_child(index).text == entry.body[index].text, "body matches authored paragraph")
		if entry.id in ["warden", "world_sigils", "place_harbor"]: await capture("lore-" + str(entry.id))
	var selected: String = book.selected_id
	book.select_entry("missing")
	check(book.selected_id == selected, "unknown entry preserves current reading")
	book.scroll.scroll_vertical = 9999; await settle()
	check(book.scroll.scroll_horizontal == 0, "reader has no horizontal text scrolling")
	await key(KEY_ESCAPE)
	check(not book.visible and game.council.visible, "Escape closes only archive, not underlying council")
	# Also verify modal isolation without relying on the council's existing pause.
	game.council.hide(); book.open("warden"); await settle()
	var state: String = immutable_state()
	var clock_before: float = game.battle.time_remaining
	var zoom_before: float = game.board.zoom
	var expanded_before: bool = game.expanded_battlefield
	for code: Key in [KEY_SPACE, KEY_Q, KEY_1, KEY_G, KEY_PLUS, KEY_TAB]: await key(code)
	await create_timer(0.35).timeout
	check(state == immutable_state() and game.battle.time_remaining == clock_before, "reading pauses battle and rejects combat shortcuts")
	check(game.board.zoom == zoom_before and game.expanded_battlefield == expanded_before, "reading shortcuts do not alter board view")
	await key(KEY_ESCAPE)
	check(not book.visible, "modal closes without council")
	await create_timer(0.1).timeout
	check(game.battle.time_remaining < clock_before, "clock resumes after reading")
	# Smaller desktop window still uses the declared virtual canvas and wraps all text.
	DisplayServer.window_set_size(Vector2i(1008, 700))
	game._open_council(); book.open("warden"); await settle()
	check(book.close_button.get_global_rect().end.x <= game.get_viewport_rect().size.x, "close button stays within logical viewport")
	check(book.paragraphs.size.x > 300 and book.scroll.size.y > 300, "reading retains useful width and height")
	await capture("lore-small-window")
	print("LORE UI CHECKS: %d | FAILURES: %d | DISPLAY: %s" % [checks, failures, DisplayServer.get_name()])
	game.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)
