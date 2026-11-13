extends GutTest
## E15-S1 (D70): the famous courses. The four built-in courses carry their id and version, the
## main menu's Famous courses page lists them and starts a new game on the shipped version (the
## starting balance, Day 1, no goals; it asks first over a game under way), E13-S5's copies in the
## course folder are tidied away once (unchanged ones removed by their bytes against every
## shipped version, edited ones kept as "<name> (my copy)"), and a save on an older version loads
## as saved with "A newer version of Cliffside is available." on the Load and Famous courses
## pages.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## A user folder of these tests' own (scripts/run_tests.sh gives each job its own user://).
const DIR := "user://test_famous_courses"
const FOLDER := DIR + "/courses"
const RECORD := DIR + "/famous_courses.cfg"
const SAVE := DIR + "/save.json"
const AUTO := DIR + "/autosaves"
## Files of rc8 to rc10 (git show v0.6.0-rcN:courses/<file>), as E13-S5 copied them.
const OLD := "res://tests/fixtures/famous_old"


func before_each() -> void:
	_clear(DIR)


func after_each() -> void:
	_clear(DIR)


func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d: String in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(d))
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	m.save_path = SAVE
	m.autosave_folder = AUTO
	add_child_autofree(m)
	m.guest_sim.set_process(false)
	m.feed_panel.set_process(false)
	return m


func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var w := FileAccess.open(to, FileAccess.WRITE)
	w.store_buffer(FileAccess.get_file_as_bytes(from))
	w.close()


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var w := FileAccess.open(path, FileAccess.WRITE)
	w.store_string(text)
	w.close()


func _files(dir: String) -> Array:
	var out := Array(DirAccess.get_files_at(dir)) if DirAccess.dir_exists_absolute(dir) else []
	out.sort()
	return out


## Cliffside as shipped, but at `version` (an older one: a save made on it).
func _cliffside_at(version: int) -> CourseData:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FamousCourses.path("cliffside")))
	data["course_version"] = version
	return CourseSave.from_dict(data)


# --- the courses ---

func test_the_four_ship_with_their_id_and_latest_version() -> void:
	assert_eq(FamousCourses.ids(), PackedStringArray(["harbor_links", "old_grey_links",
			"pine_ridge", "cliffside"]))
	for id: String in FamousCourses.ids():
		var errors: Array[String] = []
		var c := FamousCourses.load_course(id, errors)
		assert_eq(errors, [] as Array[String], id)
		if c == null:
			continue
		assert_eq(c.course_id, id)
		assert_eq(c.course_version, FamousCourses.latest_version(id), "%s at its latest version" % id)
		assert_true(c.is_famous())
		assert_eq(c.course_name, FamousCourses.display_name(id))
		assert_false(String(FamousCourses.spec(id)["style"]).is_empty(), "%s has a style line" % id)
	assert_null(FamousCourses.load_course("no_such_course"))


func test_the_id_and_version_round_trip_and_other_courses_write_neither() -> void:
	var c := FamousCourses.load_course("pine_ridge")
	var back := CourseSave.from_json(CourseSave.to_json(c))
	assert_eq([back.course_id, back.course_version], ["pine_ridge", c.course_version])
	assert_eq(back.content_hash(), c.content_hash())
	assert_eq(c.copy().course_id, "pine_ridge", "a copy keeps it")
	var plain := CourseData.create(20, 20)
	assert_false(plain.is_famous())
	assert_false(plain.to_dict().has("course_id"), "a course with no id writes neither field")
	assert_false(plain.to_dict().has("course_version"))


func test_a_bad_id_or_version_is_refused() -> void:
	var data := CourseData.create(20, 20).to_dict()
	for bad: Array in [[3, 1], ["", 1], ["cliffside", 0], ["cliffside", null], ["cliffside", 1.5]]:
		var d := data.duplicate()
		d["course_id"] = bad[0]
		d["course_version"] = bad[1]
		var errors: Array[String] = []
		assert_null(CourseData.from_dict(d, errors), "%s refused" % [bad])
		assert_eq(errors.size(), 1, "%s: %s" % [bad, errors])


func test_an_older_version_gets_the_newer_note() -> void:
	var latest := FamousCourses.latest_version("cliffside")
	assert_eq(FamousCourses.newer_note(_cliffside_at(latest - 1)),
			"A newer version of Cliffside is available.")
	assert_eq(FamousCourses.newer_note(_cliffside_at(latest)), "")
	assert_eq(FamousCourses.newer_note(_cliffside_at(latest + 1)), "", "a newer game's version")
	assert_eq(FamousCourses.newer_note(CourseData.create(20, 20)), "", "not a famous course")
	assert_eq(FamousCourses.newer_note(null), "")
	var other := CourseData.create(20, 20)
	other.set_course_id("st_elsewhere", 1)
	assert_eq(FamousCourses.newer_note(other), "", "an id this game does not know")


func test_an_export_is_the_players_course_with_no_id() -> void:
	var c := FamousCourses.load_course("cliffside")
	var data: Dictionary = JSON.parse_string(CourseExport.export_json(c))
	assert_false(data.has("course_id"))
	assert_false(data.has("course_version"))
	assert_eq(c.course_id, "cliffside", "the course itself keeps it")


# --- the migration ---

func test_the_shipped_hashes_hold_every_old_copy() -> void:
	for f: String in ["cliffside_rc8.json", "harbor_links_rc9.json", "old_grey_links_rc10.json",
			"pine_ridge_rc8.json"]:
		var id: String = f.left(f.rfind("_"))
		assert_has(FamousCourses.shipped_hashes(id), FileAccess.get_sha256(OLD.path_join(f)), f)
	for id: String in FamousCourses.ids():
		assert_eq(FamousCourses.shipped_hashes(id)[-1], FileAccess.get_sha256(FamousCourses.path(id)),
				"%s: the latest hash is the shipped file's" % id)


func test_a_fresh_folder_has_nothing_to_tidy_and_runs_once() -> void:
	var m := FamousCourses.migrate_copies(FOLDER, RECORD)
	assert_true(m.ran)
	assert_eq([m.removed.size(), m.renamed.size(), m.kept.size()], [0, 0, 0])
	assert_true(FileAccess.file_exists(RECORD), "it records that it ran")
	assert_eq(CourseExport.list_folder(FOLDER).size(), 0, "no copies in Import")
	assert_false(FamousCourses.migrate_copies(FOLDER, RECORD).ran, "and does not run again")


## rc10's folder: an rc10 copy, an rc9 one (unchanged since), an rc8 one (the course changed
## since), an edited Cliffside, and a friend's course.
func test_an_rc10_folder_loses_its_unchanged_copies_and_keeps_the_edited_one_as_mine() -> void:
	_copy(OLD.path_join("old_grey_links_rc10.json"), FOLDER.path_join("old_grey_links.json"))
	_copy(OLD.path_join("harbor_links_rc9.json"), FOLDER.path_join("harbor_links.json"))
	_copy(OLD.path_join("pine_ridge_rc8.json"), FOLDER.path_join("pine_ridge.json"))
	var edited: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD.path_join("cliffside_rc8.json")))
	edited["land_budget"] = 1234
	_write(FOLDER.path_join("cliffside.json"), JSON.stringify(edited, "  ", false))
	var mine := CourseSave.from_dict(edited)
	_write(FOLDER.path_join("from_a_friend.json"), CourseSave.to_json(CourseData.create(20, 20)))
	var m := FamousCourses.migrate_copies(FOLDER, RECORD)
	assert_true(m.ran)
	assert_eq(m.removed.size(), 3, "the three unchanged copies: %s" % [m.removed])
	assert_eq(m.renamed, {FOLDER.path_join("cliffside.json"): FOLDER.path_join("cliffside_my_copy.json")})
	assert_eq(_files(FOLDER), ["cliffside_my_copy.json", "from_a_friend.json"])
	var kept := CourseExport.read_file(FOLDER.path_join("cliffside_my_copy.json"))
	assert_not_null(kept)
	if kept == null:
		return
	assert_eq(kept.course_name, "Cliffside (my copy)", "its name field matches")
	assert_false(kept.is_famous(), "the player's course, no famous id")
	assert_eq(kept.land_budget, 1234)
	assert_eq(kept.packed_tiles(), mine.packed_tiles(), "the course as the player left it")
	assert_eq(kept.holes.size(), mine.holes.size())
	var labels: Array[String] = []
	for e: CourseExport.Entry in CourseExport.list_folder(FOLDER):
		labels.append(e.label())
	assert_eq(labels[0], "\"Cliffside (my copy)\" by Prestwick: 9 holes, par 36, 3,353 yd",
			"Import lists the copy")


func test_a_copy_of_the_current_version_goes_and_a_file_that_is_no_course_stays() -> void:
	_copy(FamousCourses.path("cliffside"), FOLDER.path_join("cliffside.json"))
	_write(FOLDER.path_join("pine_ridge.json"), "my notes, not a course")
	var m := FamousCourses.migrate_copies(FOLDER, RECORD)
	assert_eq(m.removed, [FOLDER.path_join("cliffside.json")] as Array[String])
	assert_eq(m.kept, [FOLDER.path_join("pine_ridge.json")] as Array[String])
	assert_eq(FileAccess.get_file_as_string(FOLDER.path_join("pine_ridge.json")), "my notes, not a course")


func test_my_copy_takes_a_free_name() -> void:
	var c := FamousCourses.load_course("harbor_links")
	var data := CourseSave.to_data(c)
	data["land_budget"] = 99
	_write(FOLDER.path_join("harbor_links.json"), CourseSave.stringify(data))
	_write(FOLDER.path_join("harbor_links_my_copy.json"), "taken")
	var m := FamousCourses.migrate_copies(FOLDER, RECORD)
	assert_eq(m.renamed.values(), [FOLDER.path_join("harbor_links_my_copy_2.json")])
	assert_eq(FileAccess.get_file_as_string(FOLDER.path_join("harbor_links_my_copy.json")), "taken")
	assert_eq(FamousCourses.my_copy_name("Harbor Links (my copy)"), "Harbor Links (my copy)",
			"no second (my copy)")


func test_after_it_ran_an_export_named_cliffside_is_left_alone() -> void:
	FamousCourses.migrate_copies(FOLDER, RECORD)
	_copy(FamousCourses.path("cliffside"), FOLDER.path_join("cliffside.json"))
	assert_false(FamousCourses.migrate_copies(FOLDER, RECORD).ran)
	assert_true(FileAccess.file_exists(FOLDER.path_join("cliffside.json")))


## Only the game itself migrates (Main as the running scene): a test adding Main leaves the
## record unwritten.
func test_main_added_by_a_test_does_not_migrate() -> void:
	_main()
	assert_false(FileAccess.file_exists(FamousCourses.MIGRATION_PATH))


# --- the game ---

func test_a_famous_course_starts_a_new_game_on_the_shipped_version() -> void:
	var m := _main()
	var old_id := m.save_id
	assert_true(m.start_famous("cliffside"))
	assert_eq(m.course.content_hash(), _shipped_with_start_balance("cliffside").content_hash(),
			"the shipped file, on the starting balance")
	assert_eq(m.course.course_id, "cliffside")
	assert_eq(m.build_tool.builder.balance(), LandPrices.load_default().land_budget, "$5,000 (D57)")
	assert_false(m.build_tool.builder.has_unlimited_money())
	assert_false(m.build_tool.builder.can_undo(), "a fresh builder")
	assert_null(m.goals, "E10-S1: only a New course has goals")
	assert_false(m.main_menu.goals_button.visible)
	assert_ne(m.save_id, old_id, "a new game")
	assert_eq(m.guest_sim.morning_day(), 1, "Day 1")
	for h: HoleData in m.course.holes:
		assert_true(h.open, "hole %d open" % h.number)
	assert_string_starts_with(m.save_notice.label.text,
			"New game on \"Cliffside\" by Prestwick: 9 holes, par 36, 3,353 yd.")


func _shipped_with_start_balance(id: String) -> CourseData:
	var data := CourseSave.to_data(FamousCourses.load_course(id))
	data["land_budget"] = LandPrices.load_default().land_budget
	return CourseSave.from_dict(data)


func test_a_pick_asks_first_over_a_game_under_way() -> void:
	var m := _main()
	assert_false(m.game_in_progress(), "the empty plot is no game to lose")
	m.request_famous("pine_ridge")
	assert_false(m.confirm_dialog.visible, "nothing to lose: it starts at once")
	assert_eq(m.course.course_id, "pine_ridge")
	var c: CourseData = m.course
	m.request_famous("cliffside", true)
	assert_true(m.confirm_dialog.visible)
	assert_eq(m.confirm_dialog.label.text,
			"Start a new game on Cliffside? Today's game is lost unless you saved it.")
	m.confirm_dialog.answer(false)
	assert_same(m.course, c, "no leaves the game")
	assert_true(m.main_menu.famous_page.visible, "and goes back to the Famous courses page")
	m.main_menu.close()
	m.request_famous("cliffside")
	m.confirm_dialog.answer(true)
	assert_eq(m.course.course_id, "cliffside", "yes starts it")


func test_the_menu_lists_the_famous_courses_and_esc_comes_back_to_the_button() -> void:
	var m := _main()
	m.open_menu()
	var button := m.main_menu.main_buttons()[MainMenu.FAMOUS_INDEX]
	assert_eq(button.text, "Famous courses")
	assert_eq(button.focus_mode, Control.FOCUS_ALL)
	button.pressed.emit()
	assert_true(m.main_menu.famous_page.visible)
	assert_false(m.main_menu.main_page.visible)
	var picks := m.main_menu.famous_buttons()
	var texts: Array[String] = []
	for b: Button in picks:
		texts.append(b.text.get_slice("\n", 0))
		assert_eq(b.focus_mode, Control.FOCUS_ALL)
	assert_eq(texts, ["Harbor Links: 9 holes, par 35, 3,200 yd",
			"Old Grey Links: 9 holes, par 34, 3,023 yd", "Pine Ridge: 9 holes, par 34, 2,935 yd",
			"Cliffside: 9 holes, par 36, 3,353 yd"] as Array[String])
	assert_eq(picks[3].text.get_slice("\n", 1), FamousCourses.spec("cliffside")["style"])
	assert_same(m.get_viewport().gui_get_focus_owner(), picks[0], "focus on the first")
	assert_eq(m.main_menu.famous_notes(), {}, "no save, no note")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_frames(2)
	assert_true(m.main_menu.main_page.visible, "Esc goes back to the menu")
	assert_same(m.get_viewport().gui_get_focus_owner(), button, "focus on Famous courses")


func test_picking_a_course_on_the_page_starts_it() -> void:
	var m := _main()
	m.open_menu()
	m.main_menu.show_famous()
	m.main_menu.famous_buttons()[1].pressed.emit()
	assert_false(m.main_menu.visible, "the menu closes")
	assert_eq(m.course.course_id, "old_grey_links")


func test_a_save_on_an_older_version_loads_as_saved_and_both_pages_say_a_newer_one_ships() -> void:
	var m := _main()
	m.start_famous("cliffside")
	var older := FamousCourses.latest_version("cliffside") - 1
	var s := m.save_state()
	s.course = _cliffside_at(older)
	DirAccess.make_dir_recursive_absolute(DIR)
	assert_eq(GameSave.save_file(s, SAVE), OK)
	m.new_course(7)
	assert_true(m.load_game(SAVE))
	assert_eq(m.course.course_id, "cliffside")
	assert_eq(m.course.course_version, older, "the load keeps the saved version")
	assert_eq(m.course.packed_tiles(), s.course.packed_tiles(), "and its course")
	m.open_menu()
	m.main_menu.show_load()
	var load_text := m.main_menu.load_buttons()[0].text
	assert_eq(load_text.get_slice("\n", 1), "A newer version of Cliffside is available.",
			"the Load page: %s" % load_text)
	m.main_menu.show_famous()
	assert_eq(m.main_menu.famous_notes(), {"cliffside":
			"A newer version of Cliffside is available. Your saved game from Day 1 keeps the version it was saved with."})


func test_a_save_on_the_latest_version_has_no_note() -> void:
	var m := _main()
	m.start_famous("cliffside")
	DirAccess.make_dir_recursive_absolute(DIR)
	assert_eq(m.save_game(SAVE), OK)
	var e := GameSave.read_entry(SAVE, false)
	assert_eq(e.state.course.course_id, "cliffside", "the save records the id")
	assert_eq(e.state.course.course_version, FamousCourses.latest_version("cliffside"), "and the version")
	assert_eq(e.newer_note(), "")
	m.open_menu()
	m.main_menu.show_load()
	assert_false(m.main_menu.load_buttons()[0].text.contains("\n"))
	m.main_menu.show_famous()
	assert_eq(m.main_menu.famous_notes(), {})
