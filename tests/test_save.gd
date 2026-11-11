extends GutTest
## E4-S7: save and load. The course, the land owned, the day, the money, the rating history and
## the guest feed go to one JSON file in user:// (GameSave) and come back whole; a load resumes
## at the morning of the saved day; a corrupt file shows an error and leaves the game alone; a
## load lists every hole the validator closed with its reason (D35, D47); a save names the
## half-placed holes it leaves out (E2-S12).
## E8-S4: a save over the saved game and a load each ask first; each morning after a dusk the game
## writes an autosave, the newest 3 of the game kept apart from the manual save; the Load page's
## list holds the manual save and every autosave, a broken one listed as unreadable.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const V1_SAVE := "res://tests/fixtures/save_v1_short_par4.json"
const PATH := "user://test_save.json"
## E8-S4: the autosaves' folder in these tests.
const AUTO := "user://test_autosaves/"


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	for n: int in range(1, 6):
		var p := GameSave.autosave_path(n, AUTO)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.guest_sim.set_process(false)
	m.feed_panel.set_process(false)
	return m


func _reaction(hole: int, kind: GuestReaction.Kind, text: String) -> GuestReaction:
	var r := GuestReaction.new()
	r.hole_number = hole
	r.kind = kind
	r.text = text
	r.score = 4
	r.par = 3
	r.passed = [true, false, true, false, true]
	return r


func _texts(f: ReactionFeed) -> PackedStringArray:
	var out := PackedStringArray()
	for e: ReactionFeed.Entry in f.entries:
		out.append("%d %d %s x%d%s" % [e.day, e.second, e.text, e.count, " edited" if e.edited else ""])
	return out


# --- the file ---

func test_a_state_round_trips_through_the_file() -> void:
	var c := GuestCourse.course()
	var s := GameSave.State.new()
	s.course = c
	s.seed_value = 42
	s.day = 3
	s.money = 1234
	s.rating_history = [2.5, 3.0] as Array[float]
	var feed := ReactionFeed.new(50, 100)
	feed.push(_reaction(1, GuestReaction.Kind.COMPLAINT, "Hole 1: too hard."), 1, 30, 0)
	feed.push(_reaction(2, GuestReaction.Kind.NEUTRAL, "Hole 2: fine."), 2, 40, 1)
	feed.push(_reaction(2, GuestReaction.Kind.PRAISE, "Hole 2: loved it."), 2, 50, 1, false)
	s.feed_data = feed.to_save(3)
	assert_eq(GameSave.save_file(s, PATH), OK)
	assert_false(FileAccess.file_exists(PATH + ".tmp"), "the temp file is renamed over the save")
	var errors: Array[String] = []
	var back := GameSave.load_file(PATH, errors)
	assert_not_null(back, "it loads: %s" % [errors])
	if back == null:
		return
	assert_eq(back.course.content_hash(), c.content_hash(), "the same course, land and holes")
	assert_eq(back.seed_value, 42)
	assert_eq(back.day, 3)
	assert_eq(back.money, 1234)
	assert_false(back.unlimited_money)
	assert_eq(back.rating_history, [2.5, 3.0] as Array[float])
	assert_eq(_texts(back.feed), _texts(feed), "the feed's lines, folds and dimming")
	assert_eq(back.feed.recent.size(), 3, "the window, neutrals included")
	assert_eq(back.feed.recent_slots, [0, 1, ReactionFeed.CLEARED] as Array[int])
	assert_eq(back.feed.slot_tallies(c), feed.slot_tallies(c), "the tags count the same")
	assert_eq(back.feed.recent[0].failed_line(), feed.recent[0].failed_line())
	assert_eq(back.feed.recent[0].lead_line(), feed.recent[0].lead_line())
	assert_eq(back.feed.total, 3)
	assert_eq(back.feed.newest_id(), feed.newest_id())


func test_unlimited_money_saves_as_null() -> void:
	var s := GameSave.State.new()
	s.course = GuestCourse.course()
	s.unlimited_money = true
	s.feed_data = ReactionFeed.new().to_save(1)
	var data: Dictionary = JSON.parse_string(GameSave.to_json(s))
	assert_true(data.has("money") and data["money"] == null)
	var back := GameSave.from_json(GameSave.to_json(s))
	assert_true(back.unlimited_money)


func test_the_feed_is_saved_as_it_stood_at_the_morning_of_the_saved_day() -> void:
	var feed := ReactionFeed.new(50, 100)
	feed.push(_reaction(1, GuestReaction.Kind.COMPLAINT, "Hole 1: day one."), 1, 30, 0)
	feed.push(_reaction(1, GuestReaction.Kind.PRAISE, "Hole 1: day two."), 2, 30, 0)
	var d: Dictionary = feed.to_save(2)
	assert_eq((d["lines"] as Array).size(), 1, "day 2 plays again from its morning")
	assert_eq((d["window"] as Array).size(), 1)
	assert_eq(d["total"], 1)
	assert_eq(d["next_id"], 2)


## E4-S11: the morning's stars drew its arrivals and set its fee ceiling, so the saved window is
## the morning's whole: a reaction of the saved day that pushed an older one out puts it back.
func test_the_saved_window_is_the_mornings_even_when_the_day_pushed_reactions_out() -> void:
	var points := EconomyTuning.load_default().rating_points
	var feed := ReactionFeed.new(4, 100)
	for i in 4:
		feed.push(_reaction(1, GuestReaction.Kind.COMPLAINT, "Hole 1: day one %d." % i), 1, i, 0)
	var morning := feed.rating(points)
	assert_eq(morning, 1.0)
	for i in 3:
		feed.push(_reaction(2, GuestReaction.Kind.PRAISE, "Hole 2: day two %d." % i), 2, i, 1)
	assert_gt(feed.rating(points), morning, "day 2 pushed three of day 1's out")
	var errors: Array[String] = []
	var back := ReactionFeed.from_save(feed.to_save(2), 4, 100, errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(back.recent.size(), 4, "the morning's window, whole")
	assert_eq(back.rating(points), morning, "so the load's morning has the stars the day began with")
	assert_eq(back.recent_days, [1, 1, 1, 1] as Array[int])
	# An edit made today clears the morning's verdicts on that hole, pushed out or not (E4-S7).
	feed.clear_slot(GuestCourse.course().holes, 0)
	back = ReactionFeed.from_save(feed.to_save(2), 4, 100, errors)
	assert_eq(back.recent_slots, [ReactionFeed.CLEARED, ReactionFeed.CLEARED, ReactionFeed.CLEARED,
			ReactionFeed.CLEARED] as Array[int], "hole 1's verdicts count for no hole")
	# A new day's spill starts afresh: day 3's morning held day 1's last and day 2's three, not
	# the day 1 reactions day 2 had already pushed out.
	feed.push(_reaction(2, GuestReaction.Kind.PRAISE, "Hole 2: day three."), 3, 0, 1)
	back = ReactionFeed.from_save(feed.to_save(3), 4, 100, errors)
	assert_eq(back.recent_days, [1, 2, 2, 2] as Array[int])


## E4-S12: the saved total is the morning's, even when the saved day's own reactions have
## passed the window (pushed out by later ones of the same day), so a load that replays the day
## ends with the uninterrupted day's total.
func test_the_saved_total_is_the_mornings_when_the_day_pushed_its_own_reactions_out() -> void:
	var feed := ReactionFeed.new(4, 100)
	for i in 4:
		feed.push(_reaction(1, GuestReaction.Kind.COMPLAINT, "Hole 1: day one %d." % i), 1, i, 0)
	for i in 6:
		feed.push(_reaction(2, GuestReaction.Kind.PRAISE, "Hole 2: day two %d." % i), 2, i, 1)
	assert_eq(feed.recent_days, [2, 2, 2, 2] as Array[int], "day 2 pushed two of its own out")
	var d: Dictionary = feed.to_save(2)
	assert_eq(d["total"], 4, "the morning's four, none of day 2's")
	var errors: Array[String] = []
	var back := ReactionFeed.from_save(d, 4, 100, errors)
	assert_eq(errors, [] as Array[String])
	for i in 6:
		back.push(_reaction(2, GuestReaction.Kind.PRAISE, "Hole 2: day two %d." % i), 2, i, 1)
	assert_eq(back.total, feed.total, "the replayed day ends with the uninterrupted day's total")
	# A save the next morning, before day 3 has pushed anything, keeps every reaction.
	assert_eq(feed.to_save(3)["total"], 10)
	# A new course starts the count afresh.
	feed.clear()
	feed.push(_reaction(1, GuestReaction.Kind.PRAISE, "Hole 1: day five."), 5, 0, 0)
	assert_eq(feed.to_save(5)["total"], 0)


func test_a_file_that_is_not_a_whole_save_is_refused_with_a_reason() -> void:
	var good := GameSave.State.new()
	good.course = GuestCourse.course()
	good.feed_data = ReactionFeed.new().to_save(1)
	var text := GameSave.to_json(good)
	var cases := {
		"cut short": text.substr(0, text.length() / 2),
		"not an object": "[1, 2]",
		"a course file": FileAccess.get_file_as_string("res://tests/fixtures/flat_20x20.json"),
		"a later version": text.replace("\"save_version\": 1", "\"save_version\": 9"),
		"day 0": text.replace("\"day\": 1", "\"day\": 0"),
		"a bad course": text.replace("\"width\": 48", "\"width\": -3"),
		"a bad feed": text.replace("\"lines\": []", "\"lines\": 7"),
	}
	for name: String in cases:
		var errors: Array[String] = []
		assert_null(GameSave.from_json(cases[name], errors), name)
		assert_false(errors.is_empty(), "%s says why" % name)


# --- the game ---

func test_save_quit_and_load_restores_course_day_feed_and_economy() -> void:
	var m := _main()
	m.land_seed = 5
	m.show_course(GuestCourse.course())
	m.guest_sim.advance(0.0)
	m.guest_sim.brain.run_day()
	m.guest_sim.advance(0.0)  # dusk: day 2 starts
	assert_eq(m.guest_sim.day, 2)
	var lines := _texts(m.guest_sim.feed)
	assert_gt(lines.size(), 0, "day 1 gave lines")
	m.rating_history = [3.5] as Array[float]
	var hash_before: String = m.course.content_hash()
	assert_eq(m.save_game(PATH), OK)
	assert_true(m.save_notice.visible)
	assert_string_starts_with(m.save_notice.label.text, "Saved day 2")
	# Quit: a fresh game, on another course.
	var n := _main()
	assert_ne(n.course.content_hash(), hash_before)
	assert_true(n.load_game(PATH))
	assert_eq(n.course.content_hash(), hash_before, "the course, its land and holes")
	assert_eq(n.guest_sim.base_seed, 5, "the days keep their seeds")
	assert_eq(_texts(n.guest_sim.feed), lines, "the feed")
	assert_eq(n.guest_sim.feed.slot_tallies(n.course), m.guest_sim.feed.slot_tallies(m.course), "the tags")
	assert_eq(n.rating_history, [3.5] as Array[float], "the rating history")
	assert_eq(n.save_notice.label.text, "Loaded day 2.")
	n.guest_sim.advance(0.0)
	assert_eq(n.guest_sim.day, 2, "it resumes on the saved day")
	assert_eq(n.guest_sim.brain.second, 0, "at its morning")
	assert_eq(n.guest_sim.guests_on_course(), 0, "no guest is out at the morning")


func test_a_load_mid_day_replays_the_day_from_its_morning() -> void:
	var m := _main()
	m.show_course(GuestCourse.course())
	m.guest_sim.advance(0.0)
	m.guest_sim.brain.run_day()
	var whole_day := _texts(m.guest_sim.feed)
	m.show_course(GuestCourse.course())
	m.guest_sim.advance(0.0)
	while m.guest_sim.feed.entries.is_empty() and not m.guest_sim.brain.day_over:
		m.guest_sim.brain.step()
	assert_gt(m.guest_sim.feed.entries.size(), 0, "the day is under way, with lines")
	assert_false(m.guest_sim.brain.day_over)
	assert_eq(m.save_game(PATH), OK)
	assert_string_starts_with(m.save_notice.label.text, "Saved day 1")
	var n := _main()
	assert_true(n.load_game(PATH))
	assert_eq(n.guest_sim.feed.entries.size(), 0, "day 1's lines are its own, so it starts empty")
	n.guest_sim.advance(0.0)
	n.guest_sim.brain.run_day()
	assert_eq(_texts(n.guest_sim.feed), whole_day, "the day plays again, the same lines once each")


func test_a_corrupt_save_shows_an_error_and_leaves_the_game_alone() -> void:
	var m := _main()
	m.show_course(GuestCourse.course())
	var c: CourseData = m.course
	var hash_before: String = c.content_hash()
	m.guest_sim.feed.push(_reaction(1, GuestReaction.Kind.PRAISE, "Hole 1: loved it."), 1, 10, 0)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{\"save_version\": 1, \"course\": {")
	f.close()
	assert_false(m.load_game(PATH))
	assert_same(m.course, c, "the same course")
	assert_eq(c.content_hash(), hash_before)
	assert_eq(m.guest_sim.feed.entries.size(), 1, "the same feed")
	assert_true(m.save_notice.visible)
	assert_string_starts_with(m.save_notice.label.text, "Could not load the saved game")
	assert_string_ends_with(m.save_notice.label.text, "Your game is unchanged.")
	DirAccess.remove_absolute(PATH)
	assert_false(m.load_game(PATH), "no save at all")
	assert_string_contains(m.save_notice.label.text, "no saved game")


## D35: a course saved before D33 (a version 1 course) with an open 280 yd par 4, and an open
## 350 yd par 3: one notice lists both holes the validator closed, each with its reason.
func test_a_load_lists_every_hole_the_validator_closed_in_one_notice() -> void:
	var m := _main()
	assert_true(m.load_game(V1_SAVE))
	var lines: PackedStringArray = m.save_notice.label.text.split("\n")
	assert_eq(lines.size(), 3, "the day, then a line per closed hole: %s" % [lines])
	if lines.size() == 3:
		assert_eq(lines[0], "Loaded day 4.")
		assert_string_starts_with(lines[1], "Hole 1 closed: 280 yd is a par 3, not par 4")
		assert_string_starts_with(lines[2], "Hole 2 closed: 350 yd is a par 4, not par 3")
	assert_false(m.course.holes[0].open)
	assert_false(m.course.holes[1].open)
	assert_true(m.course.has_unlimited_budget(), "a version 1 course owns all its land")


func test_a_save_names_each_half_placed_hole_it_leaves_out() -> void:
	var m := _main()
	m.show_course(GuestCourse.course())
	var b: CourseBuilder = m.build_tool.builder
	b.place_tee(4, Vector2i(10, 20), 3)
	b.place_cup(5, Vector2i(30, 20))
	assert_eq(m.save_game(PATH), OK)
	var lines: PackedStringArray = m.save_notice.label.text.split("\n")
	assert_eq(lines, PackedStringArray(["Saved day 1 (F9 loads it).",
			"Hole 4 not saved: it has no cup yet.", "Hole 5 not saved: it has no tee yet."]))
	var back := GameSave.load_file(PATH)
	assert_eq(back.course.holes.size(), 3, "the whole holes only")
	assert_eq(m.course.holes.size(), 5, "the game keeps them")


func test_the_keys_save_and_load() -> void:
	var m := _main()
	for action: String in [Main.SAVE_ACTION, Main.LOAD_ACTION]:
		assert_true(InputMap.has_action(action), action)
	assert_true(GameSave.PATH.begins_with("user://"))


# --- E8-S4: autosaves, the Load page's list, the questions ---

## A save of game `id` on `day`, written `at` (Unix seconds).
func _state(id: String, day: int, at: int = 1_700_000_000) -> GameSave.State:
	var s := GameSave.State.new()
	s.course = GuestCourse.course()
	s.feed_data = ReactionFeed.new().to_save(day)
	s.day = day
	s.money = 100 * day
	s.save_id = id
	s.saved_at = at
	return s


func _auto_days() -> Array[int]:
	var out: Array[int] = []
	for e: GameSave.Entry in GameSave.list_saves(PATH, AUTO, 3):
		if e.is_autosave and e.readable():
			out.append(e.state.day)
	return out


func test_the_save_id_and_time_round_trip_and_an_old_save_has_none() -> void:
	var s := _state("g1", 2, 1_762_860_000)
	var back := GameSave.from_json(GameSave.to_json(s))
	assert_eq(back.save_id, "g1")
	assert_eq(back.saved_at, 1_762_860_000)
	assert_eq(back.autosave, 0, "a manual save is no autosave")
	var old := GameSave.load_file(V1_SAVE)
	assert_not_null(old, "an old save.json still loads")
	assert_eq(old.save_id, "")
	assert_eq(old.saved_at, 0)


func test_autosaves_keep_the_newest_three_and_never_touch_the_manual_save() -> void:
	assert_eq(GameSave.save_file(_state("g1", 1), PATH), OK)
	var manual := FileAccess.get_file_as_string(PATH)
	for day: int in range(2, 7):
		assert_eq(GameSave.autosave_file(_state("g1", day, 1_700_000_000 + day), AUTO, 3), OK)
	assert_eq(_auto_days(), [6, 5, 4] as Array[int], "the newest three, newest first")
	assert_false(FileAccess.file_exists(GameSave.autosave_path(4, AUTO)), "three slots, no more")
	assert_eq(FileAccess.get_file_as_string(PATH), manual, "the manual save is as it was")
	for n: int in range(1, 4):
		assert_false(FileAccess.file_exists(GameSave.autosave_path(n, AUTO) + ".tmp"),
				"each written whole, temp then rename")
	# Written within one second, the number still tells the newest.
	for day: int in [7, 8]:
		GameSave.autosave_file(_state("g1", day, 1_700_000_100), AUTO, 3)
	assert_eq(_auto_days(), [8, 7, 6] as Array[int])


func test_a_new_course_keeps_the_old_courses_autosaves_until_it_writes_its_own() -> void:
	for day: int in [2, 3, 4]:
		GameSave.autosave_file(_state("old", day, 1_700_000_000 + day), AUTO, 3)
	var m := _main()
	m.autosave_folder = AUTO
	m.save_path = PATH
	m.new_course(7)
	assert_ne(m.save_id, "old", "a New course is a new game")
	assert_eq(_auto_days(), [4, 3, 2] as Array[int], "starting it leaves the old game's autosaves")
	assert_eq(m.autosave(), OK)
	var entries := GameSave.list_saves(PATH, AUTO, 3)
	assert_eq(entries.size(), 1, "its own autosave replaces the old game's")
	assert_eq(entries[0].state.save_id, m.save_id)


func test_a_broken_autosave_is_listed_as_unreadable_and_leaves_the_game_alone() -> void:
	GameSave.autosave_file(_state("g1", 2, 1_700_000_002), AUTO, 3)
	var f := FileAccess.open(GameSave.autosave_path(2, AUTO), FileAccess.WRITE)
	f.store_string("{\"save_version\": 1, \"course\": {")
	f.close()
	var entries := GameSave.list_saves(PATH, AUTO, 3)
	assert_eq(entries.size(), 2)
	assert_true(entries[0].readable())
	assert_false(entries[1].readable(), "listed, after the readable ones")
	assert_string_starts_with(entries[1].label(), "Autosave: can't be read (")
	var m := _main()
	m.show_course(GuestCourse.course())
	var c: CourseData = m.course
	m.request_load(entries[1].path)
	assert_false(m.confirm_dialog.visible, "nothing to ask: it cannot load")
	assert_same(m.course, c, "the game is left alone")
	assert_string_ends_with(m.save_notice.label.text, "Your game is unchanged.")
	# The next autosave takes the broken slot.
	m.save_id = "g1"
	m.autosave_folder = AUTO
	m.autosave()
	for e: GameSave.Entry in GameSave.list_saves(PATH, AUTO, 3):
		assert_true(e.readable())


func test_the_load_list_gives_each_saves_day_balance_and_date() -> void:
	GameSave.save_file(_state("g1", 5, 1_762_860_000), PATH)
	GameSave.autosave_file(_state("g1", 7, 1_762_870_000), AUTO, 3)
	var sandbox := _state("g1", 8, 1_762_880_000)
	sandbox.unlimited_money = true
	GameSave.autosave_file(sandbox, AUTO, 3)
	var labels: Array[String] = []
	for e: GameSave.Entry in GameSave.list_saves(PATH, AUTO, 3):
		labels.append(e.label())
	assert_eq(labels, [
		"Saved game: Day 5, $500, %s" % GameSave.date_text(1_762_860_000),
		"Autosave: Day 8, unlimited money, %s" % GameSave.date_text(1_762_880_000),
		"Autosave: Day 7, $700, %s" % GameSave.date_text(1_762_870_000),
	] as Array[String], "the manual save first, then the autosaves, newest first")
	var re := RegEx.create_from_string("^\\d{1,2} [A-Z][a-z]{2} \\d{4} \\d{2}:\\d{2}$")
	assert_not_null(re.search(GameSave.date_text(1_762_860_000)), "a real date and time: %s" %
			GameSave.date_text(1_762_860_000))


func test_each_morning_after_a_dusk_autosaves_without_changing_the_day_and_loads_as_any_save() -> void:
	var m := _main()
	m.autosaves = true
	m.autosave_folder = AUTO
	m.save_path = PATH
	m.land_seed = 5
	var c := GuestCourse.course()
	c.set_land_budget(5000)
	m.show_course(c)
	m.guest_sim.advance(0.0)
	assert_eq(_auto_days(), [] as Array[int], "day 1's own morning writes none")
	m.guest_sim.brain.run_day()
	m.guest_sim.advance(0.0)  # dusk: upkeep, then day 2's morning
	assert_eq(m.guest_sim.day, 2)
	assert_eq(m.guest_sim.brain.second, 0, "the autosave left the day at its morning")
	assert_false(m.guest_sim.brain.day_over)
	assert_eq(_auto_days(), [2] as Array[int], "day 2's morning wrote one")
	var entry: GameSave.Entry = GameSave.list_saves(PATH, AUTO, 3)[0]
	assert_eq(entry.state.money, m.build_tool.builder.balance(), "after day 1's accounting")
	assert_eq(entry.state.rating_history, m.rating_history, "day 1's rating included")
	assert_eq(entry.state.save_id, m.save_id)
	assert_false(FileAccess.file_exists(PATH), "the manual save is not written")
	# Day 2 run through, then the autosave loaded in a fresh game and day 2 replayed.
	m.guest_sim.brain.run_day()
	m.guest_sim.advance(0.0)
	var lines := _texts(m.guest_sim.feed)
	var balance: int = m.build_tool.builder.balance()
	var history := m.rating_history.duplicate()
	var n := _main()
	assert_true(n.load_game(entry.path))
	assert_eq(n.save_id, m.save_id, "the loaded game is the same game")
	assert_eq(n.guest_sim.morning_day(), 2)
	n.guest_sim.advance(0.0)
	n.guest_sim.brain.run_day()
	n.guest_sim.advance(0.0)
	assert_eq(_texts(n.guest_sim.feed), lines, "the replayed day gives the same lines")
	assert_eq(n.build_tool.builder.balance(), balance, "and ends on the same balance")
	assert_eq(n.rating_history, history, "and the same rating history")


func test_a_save_over_the_saved_game_and_a_load_ask_first() -> void:
	var m := _main()
	m.save_path = PATH
	m.show_course(GuestCourse.course())
	m.request_save()
	assert_false(m.confirm_dialog.visible, "no saved game: it saves straight away")
	assert_string_starts_with(m.save_notice.label.text, "Saved day 1")
	var first := FileAccess.get_file_as_string(PATH)
	m.guest_sim.advance(0.0)
	m.guest_sim.brain.run_day()
	m.guest_sim.advance(0.0)
	m.request_save()
	assert_true(m.confirm_dialog.visible)
	assert_eq(m.confirm_dialog.label.text, "Save over your saved game from Day 1?")
	m.confirm_dialog.answer(false)
	assert_eq(FileAccess.get_file_as_string(PATH), first, "no leaves the saved game")
	m.request_save()
	m.confirm_dialog.answer(true)
	assert_eq(GameSave.load_file(PATH).day, 2, "yes saves over it")
	var c: CourseData = m.course
	m.request_load()
	assert_eq(m.confirm_dialog.label.text, "Load Day 2 and lose today's progress?")
	m.confirm_dialog.answer(false)
	assert_same(m.course, c, "no leaves the game")
	m.request_load()
	m.confirm_dialog.answer(true)
	assert_not_same(m.course, c, "yes loads")
	assert_eq(m.save_notice.label.text, "Loaded day 2.")
