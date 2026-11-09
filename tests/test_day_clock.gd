extends GutTest
## E4-S3: the day clock and its speeds (docs/design.md Economy and time). A day is `day_s` 540
## simulated seconds, 9 real minutes at 1x and 3 at 3x; pause holds it; skip to morning runs the
## rest of the day at once (sliced over frames by `skip_frame_ticks` and
## `skip_steps_per_frame`) and gives the same end-of-day state as running it at the same seed;
## each day ends once, through GuestSim.day_ended (the hook E4-S4's fees and upkeep attach to),
## and the next morning starts at once.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SEED := 3


func _sim(base_seed: int = SEED) -> GuestSim:
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(GuestCourse.course(), base_seed)
	sim.running = true
	return sim


## Everything a day leaves behind that E4 can read at its end: the feed (every line, its day,
## second, hole, slot, kind and fold), the reaction count, and each guest's day (its holes'
## records, when and how it left), plus the brain's own totals.
static func _end_state(sim: GuestSim, b: GuestBrain) -> Array:
	var feed: Array = []
	for e: ReactionFeed.Entry in sim.feed.entries:
		feed.append([e.day, e.second, e.hole_number, e.slot, e.kind, e.text, e.count, e.edited])
	var guests: Array = []
	for g: Guest in b.guests:
		var recs: Array = []
		for r: Guest.HoleRecord in g.records:
			recs.append([r.number, r.score, r.holed, r.picked_up, r.wait_s, r.walk_yd, r.start_s,
					r.end_s, r.reaction.kind if r.reaction != null else -1])
		guests.append([g.id, g.skill, g.state, g.arrived_s, g.left_s, g.left_at_dusk, g.ticks, recs])
	return [feed, sim.feed.total, guests, b.second, b.day_over, b.turned_away, b.ticks]


## Runs `sim` in `delta`-second frames until its day `d` ends; returns the frames run. Fails
## past `max_frames`.
func _run_until_day_ends(sim: GuestSim, d: int, delta: float, max_frames: int) -> int:
	var frames := 0
	while sim.day <= d and frames < max_frames:
		sim.advance(delta)
		frames += 1
	assert_lt(frames, max_frames, "day %d ends within %d frames" % [d, max_frames])
	return frames


## Skips `sim` to the morning in its own frames; returns the frames the skip took.
func _skip(sim: GuestSim, max_frames: int = 100000) -> int:
	sim.skip_to_morning()
	var frames := 0
	while sim.skipping and frames < max_frames:
		sim.skip_frame()
		frames += 1
	assert_false(sim.skipping, "the skip reaches the morning")
	return frames


func _ended_states(sim: GuestSim) -> Array:
	var out: Array = []
	sim.day_ended.connect(func(d: int, b: GuestBrain) -> void:
		out.append([d, _end_state(sim, b)]))
	return out


func test_a_day_is_day_s_and_takes_its_real_minutes_at_1x_and_3x() -> void:
	var tuning := GuestTuning.load_default()
	assert_eq(tuning.day_s, 540.0, "a day is 540 simulated seconds (D46, E3-S60)")
	for speed: float in [1.0, 3.0]:
		var sim := _sim()
		sim.set_speed(speed)
		var delta := 1.0 / 60.0
		var frames := _run_until_day_ends(sim, 1, delta, 200000)
		var real_s := frames * delta
		var want := tuning.day_s / speed
		assert_almost_eq(real_s, want, 2.0 * delta + 1e-3,
				"%dx: the day takes %.1f real s (9 minutes at 1x, 3 at 3x)" % [int(speed), want])
		assert_eq(sim.day, 2, "%dx: the next morning has started" % int(speed))
		assert_eq(sim.brain.second, 0, "%dx: at its first second" % int(speed))


func test_pause_holds_the_clock_and_1x_moves_it_one_second_a_second() -> void:
	var sim := _sim()
	sim.advance(1.0 / 60.0)
	sim.set_speed(0.0)
	var t := sim.clock_s()
	for i: int in 600:
		sim.advance(1.0 / 60.0)
	assert_eq(sim.clock_s(), t, "paused: ten real seconds and the clock has not moved")
	sim.set_speed(1.0)
	for i: int in 600:
		sim.advance(1.0 / 60.0)
	assert_almost_eq(sim.clock_s() - t, 10.0, 0.05, "1x: ten real seconds, ten simulated")
	sim.set_speed(3.0)
	var t3 := sim.clock_s()
	for i: int in 600:
		sim.advance(1.0 / 60.0)
	assert_almost_eq(sim.clock_s() - t3, 30.0, 0.05, "3x: ten real seconds, thirty simulated")


func test_skip_from_morning_gives_the_day_run_at_3x() -> void:
	var run := _sim()
	var run_ends := _ended_states(run)
	run.set_speed(3.0)
	_run_until_day_ends(run, 1, 1.0 / 60.0, 100000)
	var skipped := _sim()
	var skip_ends := _ended_states(skipped)
	var frames := _skip(skipped)
	assert_eq(run_ends.size(), 1, "the run ended one day")
	assert_eq(skip_ends.size(), 1, "the skip ended one day")
	assert_eq(skip_ends[0][0], 1, "day 1 ended")
	assert_true(skip_ends[0][1][4], "the day was over when it ended")
	assert_gt((skip_ends[0][1][0] as Array).size(), 0, "the day gave the feed lines")
	assert_eq(skip_ends[0][1], run_ends[0][1], "the same end-of-day state, every guest and line")
	assert_eq(_end_state(skipped, skipped.brain), _end_state(run, run.brain),
			"and the same next morning")
	assert_eq(skipped.day, 2, "the skip lands on the next morning")
	assert_eq(skipped.clock_s(), 0.0, "at 0:00")
	assert_gt(frames, 1, "spread over frames, not one long frame")


func test_skip_from_mid_day_and_while_paused_gives_the_same_day() -> void:
	var run := _sim()
	var run_ends := _ended_states(run)
	run.set_speed(3.0)
	_run_until_day_ends(run, 1, 1.0 / 30.0, 100000)
	# 1x in 60 fps frames to 200 s, paused, then skipped.
	var sim := _sim()
	var ends := _ended_states(sim)
	while sim.clock_s() < 200.0:
		sim.advance(1.0 / 60.0)
	sim.set_speed(0.0)
	_skip(sim)
	assert_eq(ends.size(), 1)
	assert_eq(ends[0][1], run_ends[0][1], "the same end-of-day state")
	assert_eq(sim.day, 2)
	assert_true(sim.is_paused(), "a skip from pause lands on the morning paused")
	var t := sim.clock_s()
	for i: int in 60:
		sim.advance(1.0 / 60.0)
	assert_eq(sim.clock_s(), t, "and stays there")


func test_a_skip_frame_keeps_to_its_budget() -> void:
	var sim := _sim()
	sim.skip_to_morning()
	var budget := sim.tuning.skip_frame_ticks
	var steps_max := sim.tuning.skip_steps_per_frame
	var worst := 0
	while sim.skipping:
		var b := sim.brain
		var stepped := sim.skip_frame()
		assert_true(stepped <= steps_max, "at most %d seconds a frame (%d)" % [steps_max, stepped])
		worst = maxi(worst, b.frame_ticks)
	assert_gt(worst, 0, "the skip did Ball work")
	assert_true(worst <= budget, "no skip frame served more than %d ticks (%d)" % [budget, worst])


func test_a_speed_pressed_while_skipping_stops_the_skip_where_it_is() -> void:
	var sim := _sim()
	sim.skip_to_morning()
	for i: int in 3:
		sim.skip_frame()
	assert_true(sim.skipping)
	var second := sim.brain.second
	assert_gt(second, 0, "the skip ran some of the day")
	sim.set_speed(1.0)  # the speed it already had
	assert_false(sim.skipping, "pressing a speed stops the skip")
	assert_eq(sim.day, 1, "on the same day")
	assert_eq(sim.brain.second, second, "where it had reached")
	for i: int in 120:
		sim.advance(1.0 / 60.0)
	assert_between(sim.brain.second, second + 1, second + 2, "and the day runs on at 1x")


func test_each_day_ends_once_and_the_next_morning_follows_at_once() -> void:
	var sim := _sim()
	var order: Array = []
	sim.day_ended.connect(func(d: int, b: GuestBrain) -> void:
		assert_true(b.day_over, "day %d is over when it ends" % d)
		assert_eq(sim.brain, b, "the finished day is still the sim's while the hook runs")
		order.append("end %d" % d))
	sim.day_started.connect(func(d: int) -> void: order.append("start %d" % d))
	sim.set_speed(3.0)
	_run_until_day_ends(sim, 1, 1.0 / 60.0, 100000)
	_skip(sim)
	_skip(sim)
	assert_eq(order, ["start 1", "end 1", "start 2", "end 2", "start 3", "end 3", "start 4"])
	# A day the brain ran on its own (tests, tools) still ends once, at the next frame.
	sim.brain.run_day()
	sim.advance(0.0)
	sim.advance(0.0)
	assert_eq(order.slice(-2), ["end 4", "start 5"])


func test_skip_with_no_course_does_nothing() -> void:
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.skip_to_morning()
	assert_false(sim.skipping)
	assert_eq(sim.skip_frame(), 0)


# --- the HUD ---

func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(GuestCourse.course())
	m.guest_sim.set_process(false)
	return m


func test_the_speed_panel_has_skip_to_morning_by_button_and_key_in_build_and_play() -> void:
	var m := _main()
	var panel: SimSpeedPanel = m.sim_speed_panel
	for mode: Main.Mode in [Main.Mode.BUILD, Main.Mode.PLAY]:
		m.set_mode(mode)
		assert_true(panel.visible, "the speed panel shows in %s" % Main.Mode.keys()[mode])
		var skip: Button = panel.skip_button
		assert_not_null(skip)
		assert_true(skip.is_visible_in_tree(), "skip to morning is on the panel")
		assert_string_contains(skip.text, "(M)")
		var day := maxi(m.guest_sim.day, 1)
		skip.pressed.emit()
		assert_true(m.guest_sim.skipping, "the button starts the skip")
		m.guest_sim.skip_frame()
		panel._process(0.0)
		assert_string_contains(panel.status_text(), "  skipping")
		assert_true(skip.disabled, "the button rests while it skips")
		while m.guest_sim.skipping:
			m.guest_sim.skip_frame()
		panel._process(0.0)
		assert_eq(m.guest_sim.day, day + 1, "the next morning")
		assert_false(skip.disabled)
		assert_string_contains(panel.status_text(), "Day %d  0:00 / 9:00" % (day + 1))
	# The key.
	var key := InputEventAction.new()
	key.action = &"sim_skip"
	key.pressed = true
	var day := m.guest_sim.day
	panel._unhandled_input(key)
	assert_true(m.guest_sim.skipping, "M starts the skip")
	key.action = &"sim_pause"
	panel._unhandled_input(key)
	assert_false(m.guest_sim.skipping, "P stops it, paused")
	assert_true(m.guest_sim.is_paused())
	assert_eq(m.guest_sim.day, day)
	assert_true(InputMap.has_action(&"sim_skip"), "the M key is in the input map")
