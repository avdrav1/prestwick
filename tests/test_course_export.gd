extends GutTest
## E5-S5: export and import courses. A course is one JSON file (course format v3, CourseSave)
## friends swap: it carries a name and an author, and shows par and yardage derived from its
## holes (CourseExport.summary). An import runs the validator, closes failing holes and lists
## them in one notice with each hole's reason (D35, as E4-S7's load); a malformed file, a saved
## game or a file of a newer format shows why and leaves the game alone. The main menu (New
## course, Load game, Save game, Import course, Export course, Sound settings, Quit) works by keyboard.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## A version 1 course file (no land, no clubhouse) with an open 280 yd par 4 and an open 350 yd
## par 3, both failing rule 4 since D33: the course of tests/fixtures/save_v1_short_par4.json.
const V1_COURSE := "res://tests/fixtures/course_v1_short_par4.json"
const V1_SAVE := "res://tests/fixtures/save_v1_short_par4.json"
const DIR := "user://test_course_export"


func before_each() -> void:
	_clear(DIR)
	_clear(CourseExport.FOLDER)


func after_each() -> void:
	_clear(DIR)
	_clear(CourseExport.FOLDER)


func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.guest_sim.set_process(false)
	m.feed_panel.set_process(false)
	return m


func _key(keycode: Key, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	return e


func _tap(m: Main, keycode: Key) -> void:
	m.get_viewport().push_input(_key(keycode))
	m.get_viewport().push_input(_key(keycode, false))


# --- the file ---

func test_an_exported_course_carries_its_name_and_author_and_imports_identically() -> void:
	var b := GuestCourse.build()
	b.set_info("Three Short", "Ann")
	b.restore_balance(7_250)
	var c := b.course
	c.set_parcel_owned(Vector2i(0, 0), false)
	# 2026-11-10: the file holds the starting balance, not the exporter's money; the land is kept.
	var expect := c.copy()
	expect.set_land_budget(LandPrices.load_default().land_budget)
	var path := DIR.path_join("three_short.json")
	var dropped: Array[int] = []
	assert_eq(CourseExport.write_file(c, path, dropped), OK)
	assert_eq(dropped, [] as Array[int])
	assert_eq(c.land_budget, 7_250, "the exporter keeps their money")
	var text := FileAccess.get_file_as_string(path)
	var data: Dictionary = JSON.parse_string(text)
	assert_eq(data["version"], float(CourseData.FORMAT_VERSION))
	assert_eq(data["name"], "Three Short")
	assert_eq(data["author"], "Ann")
	assert_eq(data["land_budget"], 5000.0, "the starting balance (data/land.json, D57)")
	var errors: Array[String] = []
	var back := CourseExport.read_file(path, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(back)
	if back == null:
		return
	assert_eq(back.content_hash(), expect.content_hash(),
			"the import is the course exported, on the starting balance")
	assert_eq(back.land_budget, 5000)
	assert_false(back.is_parcel_owned(Vector2i(0, 0)), "the land owned is kept")
	assert_true(back.is_parcel_owned(Vector2i(1, 0)))
	assert_eq(back.course_name, "Three Short")
	assert_eq(back.author, "Ann")
	assert_eq(back.clubhouse, c.clubhouse)
	# A second machine: the text alone, copied anywhere, reads to the same course; nothing in
	# it names this machine's folders.
	assert_false(text.contains("user://") or text.contains(OS.get_user_data_dir()),
			"no path of this machine in the file")
	var other := CourseExport.read_text(text, errors)
	assert_eq(other.content_hash(), expect.content_hash())
	assert_eq(CourseSave.to_json(other), text, "and writes back byte for byte")


func test_a_sandbox_course_exports_with_unlimited_money() -> void:
	var c := GuestCourse.course()
	assert_true(c.has_unlimited_budget())
	var text := CourseExport.export_json(c)
	var data: Dictionary = JSON.parse_string(text)
	assert_eq(data["land_budget"], null, "unlimited stays unlimited")
	var back := CourseExport.read_text(text)
	assert_true(back.has_unlimited_budget())
	assert_eq(back.content_hash(), c.content_hash())


func test_the_starting_balance_comes_from_the_prices() -> void:
	var b := GuestCourse.build()
	b.restore_balance(-300)
	var lp := LandPrices.load_default()
	lp.land_budget = 2_000
	var data: Dictionary = JSON.parse_string(CourseExport.export_json(b.course, [], lp))
	assert_eq(data["land_budget"], 2000.0, "a balance below 0 resets too")


func test_the_builder_sets_the_name_and_author_and_keeps_the_rest() -> void:
	var b := GuestCourse.build()
	var before_holes := b.course.holes.size()
	var depth := b.undo_depth()
	b.set_info("  Links  ", " Bo ")
	assert_eq(b.course.course_name, "Links", "trimmed")
	assert_eq(b.course.author, "Bo")
	assert_eq(b.course.holes.size(), before_holes)
	assert_eq(b.undo_depth(), depth, "naming is not an edit to undo")


func test_par_and_yardage_come_from_the_holes() -> void:
	var c := CourseExport.read_file(V1_COURSE)
	assert_not_null(c)
	# 280 yd par 4 and 350 yd par 3, straight holes (rule 4's line of play).
	assert_eq(CourseExport.par(c), 7)
	assert_eq(CourseExport.yards(c), 630)
	assert_eq(CourseExport.summary(c), "2 holes, par 7, 630 yd")
	var v := CourseValidator.new()
	var g := GuestCourse.course()
	var yd := 0
	var p := 0
	for h: HoleData in g.holes:
		yd += v.hole_yardage(g, h)
		p += h.par
	assert_eq(CourseExport.summary(g), "3 holes, par %d, %d yd" % [p, yd])
	assert_eq(CourseExport.summary(CourseData.create(20, 20)), "no holes yet")
	assert_eq(CourseExport.title(c), "\"Saved before D33\" by tests")


func test_a_long_course_writes_its_yardage_with_a_comma() -> void:
	assert_eq(CourseExport.group_digits(3240), "3,240")
	assert_eq(CourseExport.group_digits(630), "630")


func test_a_half_placed_hole_is_left_out_and_named() -> void:
	var b := GuestCourse.build()
	b.place_tee(4, Vector2i(10, 20), 3)
	var dropped: Array[int] = []
	assert_eq(CourseExport.write_file(b.course, DIR.path_join("x.json"), dropped), OK)
	assert_eq(dropped, [4] as Array[int])


func test_a_file_name_comes_from_the_course_name() -> void:
	assert_eq(CourseExport.path_for("Three Short!", DIR), DIR.path_join("three_short.json"))
	assert_eq(CourseExport.path_for("  ", DIR), DIR.path_join("course.json"))
	assert_eq(CourseExport.path_for("St. Andrews / Old", DIR), DIR.path_join("st_andrews_old.json"))


func test_an_older_version_imports_through_the_migration() -> void:
	var errors: Array[String] = []
	var c := CourseExport.read_file(V1_COURSE, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(c)
	assert_true(c.has_unlimited_budget(), "a version 1 file owns all its land")
	assert_true(c.has_clubhouse(), "and gets a clubhouse by rule")


# --- refused files ---

func _refused(text: String) -> Array[String]:
	var errors: Array[String] = []
	var c := CourseExport.read_text(text, errors)
	assert_null(c)
	assert_false(errors.is_empty(), "a reason is given")
	return errors


func test_a_malformed_file_is_refused_with_its_reason() -> void:
	var e := _refused("{\"version\": 3, \"width\": ")
	assert_string_contains(e[0], "not a course file")
	assert_string_contains(e[0], "JSON line")
	assert_string_contains(_refused("[1, 2, 3]")[0], "not a course file")
	assert_string_contains(_refused("{\"name\": \"x\"}")[0], "no version")
	# The right version with a broken body: the field at fault.
	var c := GuestCourse.course()
	var data := c.to_dict()
	data["tiles"] = "AAAA"
	assert_string_contains(_refused(JSON.stringify(data))[0], "tiles")
	data = c.to_dict()
	data["version"] = "three"
	assert_string_contains(_refused(JSON.stringify(data))[0], "version")


func test_a_newer_version_is_refused() -> void:
	var data := GuestCourse.course().to_dict()
	data["version"] = CourseData.FORMAT_VERSION + 1
	var e := _refused(JSON.stringify(data))
	assert_string_contains(e[0], "newer")
	assert_string_contains(e[0], str(CourseData.FORMAT_VERSION + 1))


func test_a_version_below_one_is_refused() -> void:
	var data := GuestCourse.course().to_dict()
	data["version"] = 0
	assert_string_contains(_refused(JSON.stringify(data))[0], "version 0")


func test_a_saved_game_is_not_a_course_file() -> void:
	var e := _refused(FileAccess.get_file_as_string(V1_SAVE))
	assert_string_contains(e[0], "saved game")


func test_a_missing_file_is_refused() -> void:
	var errors: Array[String] = []
	assert_null(CourseExport.read_file(DIR.path_join("none.json"), errors))
	assert_string_contains(errors[0], "not found")


func test_the_folder_lists_each_file_with_its_summary_or_why_it_cannot_be_read() -> void:
	var b := GuestCourse.build()
	b.set_info("Three Short", "Ann")
	CourseExport.write_file(b.course, DIR.path_join("b_three.json"))
	_write(DIR.path_join("a_broken.json"), "{oops")
	_write(DIR.path_join("notes.txt"), "not a course")
	var entries := CourseExport.list_folder(DIR)
	assert_eq(entries.size(), 2, "json files only")
	if entries.size() != 2:
		return
	assert_eq(entries[0].path, DIR.path_join("a_broken.json"))
	assert_null(entries[0].course)
	assert_string_contains(entries[0].label(), "a_broken.json")
	assert_string_contains(entries[0].label(), "not a course file")
	assert_not_null(entries[1].course)
	assert_eq(entries[1].label(), "\"Three Short\" by Ann: %s" % CourseExport.summary(b.course))
	assert_eq(CourseExport.list_folder(DIR.path_join("none")).size(), 0, "no folder, no files")


# --- Main: import and export ---

func test_an_import_lists_every_hole_the_validator_closed_in_one_notice() -> void:
	var m := _main()
	assert_true(m.import_course(V1_COURSE))
	var lines: PackedStringArray = m.save_notice.label.text.split("\n")
	assert_true(m.save_notice.visible)
	assert_eq(lines.size(), 3, "the course, then a line per closed hole: %s" % [lines])
	if lines.size() == 3:
		assert_eq(lines[0], "Imported \"Saved before D33\" by tests: 2 holes, par 7, 630 yd.")
		assert_string_starts_with(lines[1], "Hole 1 closed: 280 yd is a par 3, not par 4")
		assert_string_starts_with(lines[2], "Hole 2 closed: 350 yd is a par 4, not par 3")
	assert_eq(m.course.course_name, "Saved before D33")
	assert_false(m.course.holes[0].open)
	assert_false(m.course.holes[1].open)
	assert_eq(Array(lines.slice(1)), Array(m.build_tool.builder.closed_on_load))


func test_a_clean_import_says_so_in_one_line() -> void:
	var m := _main()
	var b := GuestCourse.build()
	b.set_info("Three Short", "Ann")
	var path := DIR.path_join("three.json")
	CourseExport.write_file(b.course, path)
	assert_true(m.import_course(path))
	assert_eq(m.save_notice.label.text,
			"Imported \"Three Short\" by Ann: %s." % CourseExport.summary(b.course))
	assert_eq(m.course.content_hash(), b.course.content_hash())
	for h: HoleData in m.course.holes:
		assert_true(h.open, "hole %d stays open" % h.number)


func _assert_unchanged(m: Main, path: String, reason: String) -> void:
	var before := m.course
	var hash := m.course.content_hash()
	var builder := m.build_tool.builder
	assert_false(m.import_course(path))
	assert_same(m.course, before, "the game keeps its course")
	assert_same(m.build_tool.builder, builder, "and its builder")
	assert_eq(m.course.content_hash(), hash)
	assert_true(m.save_notice.visible)
	var text := m.save_notice.label.text
	assert_string_starts_with(text, "Could not import %s: " % path.get_file())
	assert_string_contains(text, reason)
	assert_string_ends_with(text, "Your game is unchanged.")


func test_a_malformed_import_leaves_the_game_alone() -> void:
	var m := _main()
	var path := DIR.path_join("broken.json")
	_write(path, "{\"version\": 3, \"tiles\": ")
	_assert_unchanged(m, path, "not a course file")


func test_a_newer_version_import_leaves_the_game_alone() -> void:
	var m := _main()
	var data := GuestCourse.course().to_dict()
	data["version"] = CourseData.FORMAT_VERSION + 1
	var path := DIR.path_join("future.json")
	_write(path, JSON.stringify(data))
	_assert_unchanged(m, path, "newer")


func test_a_saved_game_import_leaves_the_game_alone() -> void:
	var m := _main()
	_assert_unchanged(m, V1_SAVE, "saved game")


func test_an_export_names_the_course_and_writes_it_to_the_course_folder() -> void:
	var m := _main()
	m.show_course(GuestCourse.course())
	assert_eq(m.export_course("Three Short", "Ann"), OK)
	var path := CourseExport.path_for("Three Short")
	assert_true(FileAccess.file_exists(path))
	assert_eq(m.course.course_name, "Three Short")
	assert_eq(m.course.author, "Ann")
	var lines: PackedStringArray = m.save_notice.label.text.split("\n")
	assert_eq(lines[0], "Exported \"Three Short\" by Ann: %s." % CourseExport.summary(m.course))
	assert_string_contains(lines[1], ProjectSettings.globalize_path(path))
	# Import it into a fresh game: the same course.
	var n := _main()
	assert_true(n.import_course(path))
	assert_eq(n.course.content_hash(), m.course.content_hash())


func test_a_course_exported_with_12345_imports_with_5000() -> void:
	var m := _main()
	m.show_course(GuestCourse.course())
	m.build_tool.builder.restore_balance(12_345)
	assert_eq(m.export_course("Rich Man", "Ann"), OK)
	assert_eq(m.course.land_budget, 12_345, "exporting leaves the exporter's money alone")
	var n := _main()
	assert_true(n.import_course(CourseExport.path_for("Rich Man")))
	assert_eq(n.course.land_budget, 5000, "the importer starts on the starting balance")
	assert_eq(n.build_tool.builder.balance(), 5000)
	assert_false(n.course.has_unlimited_budget())


func test_an_export_names_each_hole_it_leaves_out() -> void:
	var m := _main()
	m.show_course(GuestCourse.course())
	m.build_tool.builder.place_tee(4, Vector2i(10, 20), 3)
	assert_eq(m.export_course("Three Short", "Ann", DIR.path_join("t.json")), OK)
	var lines: PackedStringArray = m.save_notice.label.text.split("\n")
	assert_eq(lines[-1], "Hole 4 not exported: it has no cup yet.")


# --- the main menu ---

func test_the_menu_is_closed_when_main_is_not_the_running_scene() -> void:
	var m := _main()
	assert_false(m.main_menu.visible, "tests and playtests start on the course")


func test_the_menu_lists_its_actions_and_takes_keyboard_focus() -> void:
	var m := _main()
	m.open_menu()
	assert_true(m.main_menu.visible)
	var texts: Array[String] = []
	for btn: Button in m.main_menu.main_buttons():
		texts.append(btn.text)
		assert_eq(btn.focus_mode, Control.FOCUS_ALL, "%s takes focus" % btn.text)
	assert_eq(texts, ["Back to the course", "New course", "Load game", "Save game",
			"Import course", "Export course", "Sound settings", "Goals", "Quit"] as Array[String])
	assert_false(m.main_menu.goals_button.visible, "E10-S1: Goals only with a New course's goals")
	assert_same(m.get_viewport().gui_get_focus_owner(), m.main_menu.main_buttons()[0])
	# The focused button draws a clear outline of its own.
	var focus := m.main_menu.main_buttons()[0].get_theme_stylebox("focus") as StyleBoxFlat
	assert_not_null(focus)
	if focus != null:
		assert_gt(focus.border_width_left, 1)


func test_the_arrow_keys_move_the_focus_and_esc_closes_the_menu() -> void:
	var m := _main()
	m.open_menu()
	await wait_frames(2)  # the containers lay the buttons out
	var buttons := m.main_menu.main_buttons()
	_tap(m, KEY_DOWN)
	assert_same(m.get_viewport().gui_get_focus_owner(), buttons[1])
	_tap(m, KEY_ESCAPE)
	assert_false(m.main_menu.visible, "Esc closes it")
	_tap(m, KEY_ESCAPE)
	assert_true(m.main_menu.visible, "and opens it again")


func test_the_menu_pauses_the_camera_while_open() -> void:
	var m := _main()
	m.open_menu()
	assert_false(m.camera.is_processing(), "arrow keys move the focus, not the map")
	m.main_menu.close()
	assert_true(m.camera.is_processing())


func test_the_menu_pauses_the_day_and_gives_back_the_speed() -> void:
	var m := _main()
	m.guest_sim.set_speed(3.0)
	m.open_menu()
	assert_eq(m.guest_sim.speed, 0.0, "the menu pauses the guests' day")
	assert_true((m.sim_speed_panel.buttons[0.0] as Button).button_pressed, "on the panel's Pause")
	m.main_menu.close()
	assert_eq(m.guest_sim.speed, 3.0, "closing it gives back the speed the player had")
	assert_true((m.sim_speed_panel.buttons[3.0] as Button).button_pressed)
	# A day the player paused stays paused.
	m.guest_sim.set_speed(0.0)
	m.open_menu()
	m.main_menu.close()
	assert_eq(m.guest_sim.speed, 0.0)
	# Esc both ways too.
	m.guest_sim.set_speed(1.0)
	_tap(m, KEY_ESCAPE)
	assert_true(m.main_menu.visible)
	assert_eq(m.guest_sim.speed, 0.0)
	_tap(m, KEY_ESCAPE)
	assert_false(m.main_menu.visible)
	assert_eq(m.guest_sim.speed, 1.0)


func test_the_sound_panel_from_the_menu_keeps_the_day_paused() -> void:
	var m := _main()
	m.guest_sim.set_speed(3.0)
	m.open_menu()
	m.main_menu.main_buttons()[MainMenu.SOUND_INDEX].pressed.emit()
	assert_false(m.main_menu.visible)
	assert_true(m.audio_panel.visible)
	assert_eq(m.guest_sim.speed, 0.0, "still paused under the sound panel")
	m.audio_panel.close()
	assert_true(m.main_menu.visible, "back on the menu")
	assert_eq(m.guest_sim.speed, 0.0, "still paused on the menu")
	m.main_menu.close()
	assert_eq(m.guest_sim.speed, 3.0, "the menu path closed: the speed is back")


func test_the_export_page_takes_a_name_and_author_and_exports() -> void:
	var m := _main()
	m.show_course(GuestCourse.course())
	m.open_menu()
	m.main_menu.show_export()
	assert_same(m.get_viewport().gui_get_focus_owner(), m.main_menu.name_edit)
	assert_eq(m.main_menu.summary_label.text, CourseExport.summary(m.course))
	m.main_menu.name_edit.text = ""
	m.main_menu.author_edit.text = "Ann"
	m.main_menu.refresh_export()
	assert_true(m.main_menu.export_button.disabled, "a course file carries a name")
	m.main_menu.name_edit.text = "Three Short"
	m.main_menu.refresh_export()
	assert_false(m.main_menu.export_button.disabled)
	m.main_menu.export_button.pressed.emit()
	assert_false(m.main_menu.visible, "the menu closes on the notice")
	assert_true(FileAccess.file_exists(CourseExport.path_for("Three Short")))
	assert_string_starts_with(m.save_notice.label.text, "Exported \"Three Short\" by Ann")
	# E5-S6: Esc closes the notice first ("OK (Esc)"), then opens the menu.
	_tap(m, KEY_ESCAPE)
	assert_false(m.save_notice.visible, "Esc closes the notice")
	assert_false(m.main_menu.visible)
	_tap(m, KEY_ESCAPE)
	assert_true(m.main_menu.visible)
	_tap(m, KEY_ESCAPE)
	assert_false(m.main_menu.visible)


func test_the_name_is_typed_by_keyboard_and_tab_moves_on() -> void:
	var m := _main()
	m.show_course(GuestCourse.course())
	m.open_menu()
	m.main_menu.show_export()
	await wait_frames(2)
	m.main_menu.name_edit.text = ""
	for k: Key in [KEY_A, KEY_B]:
		var e := _key(k)
		e.unicode = k + 32  # lower case
		m.get_viewport().push_input(e)
		m.get_viewport().push_input(_key(k, false))
	assert_eq(m.main_menu.name_edit.text, "ab", "keys type into the focused name")
	_tap(m, KEY_TAB)
	assert_same(m.get_viewport().gui_get_focus_owner(), m.main_menu.author_edit)


func test_esc_on_a_page_goes_back_to_the_menu() -> void:
	var m := _main()
	m.open_menu()
	m.main_menu.show_export()
	_tap(m, KEY_ESCAPE)
	assert_true(m.main_menu.visible)
	assert_true(m.main_menu.main_page.visible)
	assert_same(m.get_viewport().gui_get_focus_owner(), m.main_menu.main_buttons()[5],
			"focus back on Export course")


func test_the_import_page_lists_the_course_folder_and_imports_the_pick() -> void:
	var m := _main()
	var b := GuestCourse.build()
	b.set_info("Three Short", "Ann")
	CourseExport.write_file(b.course, CourseExport.path_for("Three Short"))
	_write(CourseExport.FOLDER.path_join("broken.json"), "{oops")
	m.open_menu()
	m.main_menu.show_import()
	var picks := m.main_menu.import_buttons()
	assert_eq(picks.size(), 2)
	if picks.size() != 2:
		return
	assert_same(m.get_viewport().gui_get_focus_owner(), picks[0])
	assert_string_contains(picks[0].text, "broken.json")
	assert_eq(picks[1].text, "\"Three Short\" by Ann: %s" % CourseExport.summary(b.course))
	# The broken one: the reason, and the game left alone.
	var hash := m.course.content_hash()
	picks[0].pressed.emit()
	assert_false(m.main_menu.visible)
	assert_string_ends_with(m.save_notice.label.text, "Your game is unchanged.")
	assert_eq(m.course.content_hash(), hash)
	m.open_menu()
	m.main_menu.show_import()
	m.main_menu.import_buttons()[1].pressed.emit()
	assert_eq(m.course.content_hash(), b.course.content_hash())
	assert_false(m.main_menu.visible)


func test_the_import_page_says_where_to_put_files_when_there_are_none() -> void:
	var m := _main()
	m.open_menu()
	m.main_menu.show_import()
	assert_eq(m.main_menu.import_buttons().size(), 0)
	assert_string_contains(m.main_menu.folder_label.text,
			ProjectSettings.globalize_path(CourseExport.FOLDER))
	assert_same(m.get_viewport().gui_get_focus_owner(), m.main_menu.import_back_button)


func test_new_course_and_load_and_save_go_through_main() -> void:
	var m := _main()
	var before := m.course
	m.open_menu()
	m.main_menu.main_buttons()[1].pressed.emit()
	assert_false(m.main_menu.visible)
	assert_not_same(m.course, before, "New course made a new course")
	if FileAccess.file_exists(GameSave.PATH):
		DirAccess.remove_absolute(GameSave.PATH)
	m.open_menu()
	m.main_menu.main_buttons()[MainMenu.SAVE_INDEX].pressed.emit()
	assert_string_starts_with(m.save_notice.label.text, "Saved day")
	# E8-S4: Load game opens the Load page; its pick asks before it loads.
	m.open_menu()
	m.main_menu.main_buttons()[MainMenu.LOAD_INDEX].pressed.emit()
	assert_true(m.main_menu.load_page.visible)
	m.main_menu.load_buttons()[0].pressed.emit()
	assert_true(m.confirm_dialog.visible)
	m.confirm_dialog.answer(true)
	assert_string_starts_with(m.save_notice.label.text, "Loaded day")
	if FileAccess.file_exists(GameSave.PATH):
		DirAccess.remove_absolute(GameSave.PATH)
