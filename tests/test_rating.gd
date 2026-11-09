extends GutTest
## E4-S5 (D58): the course rating. The mean of praise 5, neutral 3, complaint 1 over the last
## `rating_window` (50) reactions, a short window filled with neutrals and a cleared reaction
## counting as neutral; 1 to 5 stars to the half star on the HUD; each morning's arrivals
## 8 + 4 a star, at most 24, replacing E3's flat number; the closing rating of each day kept in
## Main.rating_history, which a save carries.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var economy: EconomyTuning
var window: int


func before_all() -> void:
	economy = EconomyTuning.load_default()
	window = GuestTuning.load_default().rating_window


func _reaction(kind: GuestReaction.Kind, hole: int = 1) -> GuestReaction:
	var r := GuestReaction.new()
	r.hole_number = hole
	r.kind = kind
	r.text = "Hole %d: %s." % [hole, GuestReaction.KIND_NAMES[kind]]
	return r


## Pushes `n` reactions of `kind` about hole 1 (slot 0).
func _push(feed: ReactionFeed, kind: GuestReaction.Kind, n: int) -> void:
	for i in n:
		feed.push(_reaction(kind), 1, i, 0)


func _feed() -> ReactionFeed:
	return ReactionFeed.new(window, 100)


func _rating(feed: ReactionFeed) -> float:
	return feed.rating(economy.rating_points)


func test_the_window_and_points_are_d58s() -> void:
	assert_eq(window, 50)
	assert_eq(Array(economy.rating_points), [5.0, 3.0, 1.0], "praise 5, neutral 3, complaint 1")


func test_a_new_course_rates_three_stars() -> void:
	var feed := _feed()
	assert_almost_eq(_rating(feed), 3.0, 1e-9, "an empty window is all neutral")
	assert_eq(EconomyTuning.stars_of(_rating(feed)), 3.0)


func test_fewer_than_fifty_are_padded_with_neutrals() -> void:
	var feed := _feed()
	_push(feed, GuestReaction.Kind.PRAISE, 10)
	assert_almost_eq(_rating(feed), (10 * 5.0 + 40 * 3.0) / 50.0, 1e-9, "10 praise and 40 neutrals")
	_push(feed, GuestReaction.Kind.COMPLAINT, 5)
	assert_almost_eq(_rating(feed), (10 * 5.0 + 5 * 1.0 + 35 * 3.0) / 50.0, 1e-9)
	var one := _feed()
	_push(one, GuestReaction.Kind.COMPLAINT, 1)
	assert_almost_eq(_rating(one), (1.0 + 49 * 3.0) / 50.0, 1e-9,
			"one complaint barely moves a new course")


func test_exactly_fifty_is_the_plain_mean() -> void:
	var feed := _feed()
	_push(feed, GuestReaction.Kind.PRAISE, 20)
	_push(feed, GuestReaction.Kind.NEUTRAL, 10)
	_push(feed, GuestReaction.Kind.COMPLAINT, 20)
	assert_eq(feed.recent.size(), 50)
	assert_almost_eq(_rating(feed), (20 * 5.0 + 10 * 3.0 + 20 * 1.0) / 50.0, 1e-9)
	var best := _feed()
	_push(best, GuestReaction.Kind.PRAISE, 50)
	assert_almost_eq(_rating(best), 5.0, 1e-9, "all praise is 5")
	var worst := _feed()
	_push(worst, GuestReaction.Kind.COMPLAINT, 50)
	assert_almost_eq(_rating(worst), 1.0, 1e-9, "all complaints is 1")


func test_the_51st_pushes_out_the_oldest() -> void:
	var feed := _feed()
	feed.push(_reaction(GuestReaction.Kind.PRAISE), 1, 0, 0)
	_push(feed, GuestReaction.Kind.COMPLAINT, 49)
	assert_almost_eq(_rating(feed), (5.0 + 49 * 1.0) / 50.0, 1e-9, "the praise is in")
	feed.push(_reaction(GuestReaction.Kind.COMPLAINT), 1, 60, 0)
	assert_eq(feed.recent.size(), 50, "the window keeps 50")
	assert_almost_eq(_rating(feed), 1.0, 1e-9, "the oldest, the praise, is out")


func test_a_cleared_reaction_counts_as_neutral_over_the_full_window() -> void:
	var feed := _feed()
	var c := GuestCourse.course()
	_push(feed, GuestReaction.Kind.COMPLAINT, 30)  # hole 1, slot 0
	for i in 20:
		feed.push(_reaction(GuestReaction.Kind.PRAISE, 2), 1, 100 + i, 1)
	assert_almost_eq(_rating(feed), (30 * 1.0 + 20 * 5.0) / 50.0, 1e-9)
	feed.clear_slot(c.holes, 0)
	assert_eq(feed.recent.size(), 50, "cleared reactions keep their place")
	assert_almost_eq(_rating(feed), (30 * 3.0 + 20 * 5.0) / 50.0, 1e-9,
			"hole 1's fixed complaints count as neutral, divided by 50, not by the 20 left")
	var uncounted := _feed()
	uncounted.push(_reaction(GuestReaction.Kind.COMPLAINT), 1, 0, 0, false)
	assert_almost_eq(_rating(uncounted), 3.0, 1e-9, "a verdict pushed uncounted is neutral too")


func test_stars_are_shown_to_the_half_star_from_one_to_five() -> void:
	var cases := [[1.0, 1.0], [1.2, 1.0], [1.25, 1.5], [2.74, 2.5], [2.75, 3.0], [3.1, 3.0],
			[3.4, 3.5], [4.76, 5.0], [5.0, 5.0], [0.0, 1.0], [6.0, 5.0]]
	for c: Array in cases:
		assert_eq(EconomyTuning.stars_of(c[0]), c[1], "rating %s" % c[0])


## The guests a sim's first day on the guest course draws, after `kinds` (n of each) went into
## its feed.
func _first_day_guests(kinds: Dictionary) -> int:
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(GuestCourse.course(), 7)
	for k: GuestReaction.Kind in kinds:
		_push(sim.feed, k, kinds[k])
	sim.advance(0.0)
	var n := 0
	for g: GuestGroup in sim.brain.groups:
		n += g.guests.size()
	return n


func test_daily_arrivals_scale_with_the_rating() -> void:
	assert_eq(_first_day_guests({}), 8 + 4 * 3, "a new course at 3 stars: 20, not E3's flat 16")
	assert_eq(_first_day_guests({GuestReaction.Kind.COMPLAINT: 50}), 8 + 4 * 1, "1 star: 12")
	assert_eq(_first_day_guests({GuestReaction.Kind.PRAISE: 25, GuestReaction.Kind.NEUTRAL: 25}),
			8 + 4 * 4, "4 stars: 24")
	assert_eq(_first_day_guests({GuestReaction.Kind.PRAISE: 50}), 24, "5 stars is capped at 24")
	assert_eq(_first_day_guests({GuestReaction.Kind.PRAISE: 13, GuestReaction.Kind.NEUTRAL: 37}),
			22, "3.5 stars (3.52): 8 + 4 x 3.5 = 22, the half star counts")


func test_a_day_keeps_its_morning_count_and_the_next_morning_reads_the_new_rating() -> void:
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(GuestCourse.course(), 7)
	sim.advance(0.0)
	var first := sim.brain
	assert_eq(sim.arrivals_today(), 20)
	_push(sim.feed, GuestReaction.Kind.COMPLAINT, 50)
	assert_eq(sim.arrivals_today(), 12, "the rating fell")
	assert_eq(sim.brain, first, "the day under way keeps its guests")
	first.day_over = true
	sim.advance(0.0)
	var n := 0
	for g: GuestGroup in sim.brain.groups:
		n += g.guests.size()
	assert_eq(sim.day, 2)
	assert_eq(n, 12, "the next morning draws by the new rating")
	assert_eq(sim.day_arrivals, 12, "and says so")


func test_the_rating_changes_signal_on_every_window_change() -> void:
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.start(GuestCourse.course(), 7)
	watch_signals(sim)
	sim.feed.push(_reaction(GuestReaction.Kind.NEUTRAL), 1, 0, 0)
	assert_signal_emit_count(sim, "rating_changed", 1, "a neutral moves the window too")
	sim.feed.push(_reaction(GuestReaction.Kind.PRAISE), 1, 1, 0)
	assert_signal_emitted_with_parameters(sim, "rating_changed", [(5.0 + 49 * 3.0) / 50.0])
	sim.feed.clear_slot(GuestCourse.course().holes, 0)
	assert_signal_emitted_with_parameters(sim, "rating_changed", [3.0])


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(GuestCourse.course())
	m.guest_sim.set_process(false)
	return m


func test_the_hud_shows_the_stars_in_build_and_play() -> void:
	var m := _main()
	var row: RatingRow = m.rating_row
	assert_true(row.stars_view.is_visible_in_tree(), "Build shows the stars")
	assert_eq(row.stars_view.stars, 3.0)
	assert_eq(row.rating_label.text, "3 stars")
	_push(m.guest_sim.feed, GuestReaction.Kind.PRAISE, 13)
	assert_eq(row.stars_view.stars, 3.5, "a reaction redraws it")
	assert_eq(row.rating_label.text, "3.5 stars")
	assert_string_contains(row.stars_view.tooltip_text, "3.52")
	_push(m.guest_sim.feed, GuestReaction.Kind.COMPLAINT, 50)
	assert_eq(row.rating_label.text, "1 star")
	m.set_mode(Main.Mode.PLAY)
	await get_tree().process_frame
	assert_true(row.stars_view.is_visible_in_tree(), "and Play")
	assert_true(row in m.hud_controls(), "the free view counts it")
	var at := m._hud_rect(row)
	assert_false(at.intersects(m._hud_rect(m.mode_label)), "beside the mode label")
	assert_false(at.intersects(m._hud_rect(m.mode_button)), "above the mode button")
	assert_true(at.end.x <= m._hud_rect(m.feed_panel).end.x, "inside the left column")


func test_star_fill_goes_by_halves() -> void:
	assert_eq([StarsView.fill_of(0, 2.5), StarsView.fill_of(1, 2.5), StarsView.fill_of(2, 2.5),
			StarsView.fill_of(3, 2.5)], [1.0, 1.0, 0.5, 0.0])


func test_each_days_closing_rating_is_kept_and_saved() -> void:
	var m := _main()
	assert_eq(m.rating_history, [] as Array[float])
	m.guest_sim.day_ended.emit(1, null)
	_push(m.guest_sim.feed, GuestReaction.Kind.PRAISE, 50)
	m.guest_sim.day_ended.emit(2, null)
	assert_eq(m.rating_history, [3.0, 5.0] as Array[float], "one rating a day, oldest first")
	var s := GameSave.State.new()
	m.economy_to_save(s)
	assert_eq(s.rating_history, [3.0, 5.0] as Array[float], "the save carries it")
	m.show_course(GuestCourse.course())
	assert_eq(m.rating_history, [] as Array[float], "a new course starts it again")
	m.economy_from_save(s)
	assert_eq(m.rating_history, [3.0, 5.0] as Array[float], "a load brings it back")
