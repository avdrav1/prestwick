extends GutTest
## E4-S7: save and load. The course, the land owned, the day, the money, the rating history and
## the guest feed go to one JSON file in user:// (GameSave) and come back whole; a load resumes
## at the morning of the saved day; a corrupt file shows an error and leaves the game alone; a
## load lists every hole the validator closed with its reason (D35, D47); a save names the
## half-placed holes it leaves out (E2-S12).

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const V1_SAVE := "res://tests/fixtures/save_v1_short_par4.json"
const PATH := "user://test_save.json"


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


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
	r.passed = [true, false, true, false]
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
