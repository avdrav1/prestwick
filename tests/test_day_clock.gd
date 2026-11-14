extends GutTest
## E4-S3: the day clock and its speeds (docs/design.md Economy and time). A day is `day_s` 540
## simulated seconds, 9 real minutes at 1x and 3 at 3x; pause holds it; skip to morning runs the
## rest of the day at once (sliced over frames by `skip_frame_ms` and `skip_steps_per_frame`,
## E7-S4: whole seconds, the guests' Ball work on several threads) and gives the same end-of-day
## state as running it at the same seed;
## each day ends once, through GuestSim.day_ended (the hook E4-S4's fees and upkeep attach to),
## and the next morning starts at once.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## E7-S4's Accept: a full day of D58's most guests on the playtest nine skips in under 3 real
## seconds (the window adds its frames: scripts/skip_perf.gd times that).
const NINE_GUESTS := 24
const NINE_SKIP_MAX_S := 3.0
const SEED := 3
## E5-S12: the most real time a day at 3x may be held for its Ball work (GuestBrain.held_frames).
const MAX_HELD_S := 0.5


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
		# The day's own brain, read each frame: at dusk sim.brain is already the next day's.
		var held := 0
		var frames := 0
		while sim.day <= 1 and frames < 200000:
			sim.advance(delta)
			frames += 1
			if sim.day == 1 and sim.brain != null:
				held = sim.brain.held_frames
		assert_lt(frames, 200000, "day 1 ends")
		var real_s := frames * delta
		var want := tuning.day_s / speed
		if speed == 1.0:
			assert_almost_eq(real_s, want, 2.0 * delta + 1e-3,
					"1x: the day takes %.1f real s (9 minutes)" % want)
		else:
			# E5-S12: a due step waits for its second's Ball work (E3-S35, E4-S3), so a busy
			# second makes the day late, never different: by the frames held, and no more.
			assert_lte(held * delta, MAX_HELD_S, "%dx: held for Ball work at most %.1f s a day" % [
					int(speed), MAX_HELD_S])
			assert_almost_eq(real_s, want + held * delta, 2.0 * delta + 1e-3,
					"%dx: the day takes %.1f real s (3 minutes) and the %d frames held for its Ball work" % [
						int(speed), want, held])
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


func test_a_skip_frame_runs_whole_seconds_within_its_time() -> void:
	var sim := _sim()
	sim.skip_to_morning()
	var steps_max := sim.tuning.skip_steps_per_frame
	var frames := 0
	var worked := 0
	while sim.skipping:
		var b := sim.brain
		var ticks := b.ticks
		var second := b.second
		var stepped := sim.skip_frame()
		frames += 1
		assert_between(stepped, 1, steps_max, "at least one second a frame, at most %d" % steps_max)
		if not b.day_over:
			assert_eq(b.second, second + stepped, "whole seconds: the clock moved by the steps")
		assert_eq(b.frame_ticks, b.ticks - ticks, "frame_ticks counts what the frame served")
		worked = maxi(worked, b.frame_ticks)
	assert_gt(worked, 0, "the skip did Ball work")
	assert_gt(frames, 1, "over frames")
	# With no time to spare, each frame runs one second.
	var tight := _sim()
	tight.tuning = GuestTuning.from_file(GuestTuning.PATH)
	tight.tuning.skip_frame_ms = 0.001
	tight.skip_to_morning()
	tight.skip_frame()
	assert_eq(tight.brain.second, 1, "one second when the frame's time is spent")


## E7-S4: the playtest nine with D58's most guests, the busiest day the game draws.
func _nine_brain() -> GuestBrain:
	return GuestBrain.new(CourseSave.load_file(PlaytestNine.PATH), 1, null, null, [], null,
			NINE_GUESTS)


static func _brain_state(b: GuestBrain) -> Array:
	var out: Array = []
	for g: Guest in b.guests:
		var hole: Array = []
		if g.hole != null:
			hole = [g.hole.state, g.hole.ball_at, g.hole.ticks, g.hole.strokes.size(),
					g.hole.score.strokes]
		var recs: Array = []
		for r: Guest.HoleRecord in g.records:
			recs.append([r.number, r.score, r.wait_s, r.start_s, r.end_s])
		out.append([g.id, g.state, g.position, g.ticks, g.second_ticks, hole, recs])
	return [b.second, b.ticks, b.max_second_ticks, b.capped_seconds, out]


func test_threads_serve_a_second_as_one_thread_does() -> void:
	var one := _nine_brain()
	var threaded := _nine_brain()
	var ahead := _nine_brain()
	var seconds := 150
	while one.second < seconds:
		one.serve(-1)
		one.step()
		threaded.advance_skip(1, -1, true)
		# Part of the next second served while the frame is drawn (GuestSim, frame_pre_draw),
		# counted after (frame_post_draw), then the frame's own seconds.
		ahead.serve_ahead()
		ahead.settle()
		ahead.advance_skip(1, -1, true)
		if one.second % 15 == 0:
			assert_eq(_brain_state(threaded), _brain_state(one), "threads, second %d" % one.second)
			assert_eq(_brain_state(ahead), _brain_state(one), "served ahead, second %d" % one.second)
	assert_gt(one.guests.size(), 12, "the morning's guests are out")
	assert_gt(one.ticks, 100000, "and busy")


func test_serve_ahead_waits_for_its_batch_before_anything_reads_the_guests() -> void:
	var b := _nine_brain()
	while b.second < 60:
		b.advance_skip(10, -1, true)
	var plain := _nine_brain()
	while plain.second < 60:
		plain.advance_skip(10, -1, false)
	assert_true(b.serve_ahead(), "a batch starts")
	assert_false(b.serve_ahead(), "one at a time")
	b.step()  # settles first: the second's work is all counted, then the step
	plain.serve(-1)
	plain.step()
	assert_eq(_brain_state(b), _brain_state(plain))
	assert_eq(b.settle(), 0, "nothing left to count")


func test_a_full_day_on_the_playtest_nine_skips_in_under_3_s() -> void:
	if BestTime.later(self):
		return
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(CourseSave.load_file(PlaytestNine.PATH), 0)
	sim.resume_at(1, NINE_GUESTS)
	sim.running = true
	var ends := _ended_states(sim)
	var t0 := Time.get_ticks_usec()
	var frames := _skip(sim)
	var real_s := (Time.get_ticks_usec() - t0) / 1e6
	assert_eq(ends.size(), 1, "the day ended")
	assert_eq((ends[0][1][2] as Array).size(), NINE_GUESTS, "with all its guests")
	gut.p("a %d-guest day on the playtest nine: skipped in %.2f s over %d frames (headless)" % [
			NINE_GUESTS, real_s, frames])
	assert_lt(real_s, NINE_SKIP_MAX_S, "a full day skips in under %.0f s%s" % [NINE_SKIP_MAX_S,
			BestTime.load_note()])


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


func test_the_golfers_leave_the_course_while_a_skip_runs_and_come_back_after() -> void:
	var m := _main()
	var sim := m.guest_sim
	var view: GuestView = m.guest_view
	sim.set_speed(3.0)
	while sim.clock_s() < 120.0:
		sim.advance(1.0 / 60.0)
	view.update_view(1.0 / 60.0, sim.effective_speed())
	var out := view.figures().size()
	assert_gt(out, 0, "golfers out on the course at 2:00")
	sim.skip_to_morning()
	sim.skip_frame()
	view.update_view(1.0 / 60.0, sim.effective_speed())
	assert_eq(view.figures().size(), 0, "none drawn while the day jumps: the speed panel's line shows it")
	assert_string_contains(m.sim_speed_panel.status_text(), "skipping")
	sim.set_speed(1.0)  # stops the skip where it is
	view.update_view(1.0 / 60.0, sim.effective_speed())
	assert_eq(view.figures().size(), sim.brain.on_course().size(), "drawn again where the skip stopped")
	assert_gt(view.figures().size(), 0)


# --- E8-S2 (D64): a late start when the first hole opens, at any speed and through a load ---

const LATE_SAVE := "user://test_day_clock_late.json"
const LATE_AT := 120
const LATE_START := 5000


func after_each() -> void:
	if FileAccess.file_exists(LATE_SAVE):
		DirAccess.remove_absolute(LATE_SAVE)


## The guest course with every hole closed by hand, and its builder.
static func _closed_build() -> CourseBuilder:
	var b := GuestCourse.build()
	for n: int in [1, 2, 3]:
		b.close_hole(n)
	return b


## A sim on a fresh closed guest course, its builder alongside.
func _closed_sim() -> Array:
	var b := _closed_build()
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(b.course, SEED)
	sim.running = true
	return [sim, b]


## Advances `sim` in `delta` frames until its brain is at second LATE_AT, then opens every hole.
func _open_at_late(sim: GuestSim, b: CourseBuilder, delta: float) -> void:
	sim.advance(0.0)
	while sim.brain.second < LATE_AT:
		sim.advance(delta)
	assert_eq(sim.brain.second, LATE_AT, "the holes open just as second %d comes" % LATE_AT)
	assert_eq(sim.brain.turned_away, sim.brain.groups.size(), "every group went home to a closed course")
	for n: int in [1, 2, 3]:
		b.open_hole(n)


func test_a_skip_after_a_late_start_gives_the_day_run_at_3x() -> void:
	var run_pair := _closed_sim()
	var run: GuestSim = run_pair[0]
	var run_ends := _ended_states(run)
	run.set_speed(3.0)
	_open_at_late(run, run_pair[1], 1.0 / 60.0)
	_run_until_day_ends(run, 1, 1.0 / 60.0, 100000)
	var pair := _closed_sim()
	var sim: GuestSim = pair[0]
	var ends := _ended_states(sim)
	_open_at_late(sim, pair[1], 1.0 / 60.0)
	while sim.brain.second <= LATE_AT:
		sim.advance(1.0 / 60.0)
	assert_eq(sim.brain.late_starts, [Vector3i(0, LATE_AT, sim.brain.groups.size())] as Array[Vector3i],
			"the step after the opening sends every group from that second")
	_skip(sim)
	assert_eq(ends.size(), 1)
	assert_gt((ends[0][1][2] as Array).size(), 0, "the late guests came")
	assert_eq(ends[0][1], run_ends[0][1], "the same end-of-day state as the day run at 3x")


func _late_main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	var c := _closed_build().course
	c.set_land_budget(LATE_START)
	m.land_seed = SEED
	m.show_course(c)
	m.guest_sim.set_process(false)
	m.feed_panel.set_process(false)
	return m


func _main_open_at_late(m: Main) -> void:
	m.guest_sim.advance(0.0)
	while m.guest_sim.brain.second < LATE_AT:
		m.guest_sim.advance(1.0)
	assert_eq(m.ledger.guests, 0, "nobody paid at a closed course")
	for n: int in [1, 2, 3]:
		assert_true(m.build_tool.builder.open_hole(n))


func _main_skip(m: Main) -> void:
	m.guest_sim.skip_to_morning()
	var frames := 0
	while m.guest_sim.skipping and frames < 100000:
		m.guest_sim.skip_frame()
		frames += 1
	assert_eq(m.guest_sim.day, 2, "the skip reaches day 2's morning")


func _feed_lines(m: Main) -> PackedStringArray:
	var out := PackedStringArray()
	for e: ReactionFeed.Entry in m.guest_sim.feed.entries:
		out.append("%d %d %s x%d" % [e.day, e.second, e.text, e.count])
	return out


func test_the_morning_line_counts_the_late_guests_and_a_load_replays_them() -> void:
	# The day run through: closed until 120 s, then opened.
	var a := _late_main()
	var came := [0]
	a.guest_sim.day_ended.connect(func(_d: int, b: GuestBrain) -> void: came[0] = b.guests.size())
	_main_open_at_late(a)
	_main_skip(a)
	assert_gt(came[0], 0, "the late guests came")
	assert_string_contains(a.ledger.last_line, "(%d guests)" % came[0], "the morning line counts them")
	assert_eq(a.money_panel.day_label.text.contains("%d guests" % came[0]), true)
	# The same day saved after a few late guests paid, loaded into a fresh game, run to its end.
	var b := _late_main()
	_main_open_at_late(b)
	while b.ledger.guests < 2:
		b.guest_sim.advance(1.0)
	assert_eq(b.save_game(LATE_SAVE), OK)
	var text := FileAccess.get_file_as_string(LATE_SAVE)
	assert_string_contains(text, "late_starts", "the save keeps the late start")
	var n := _late_main()
	assert_true(n.load_game(LATE_SAVE))
	n.guest_sim.advance(0.0)
	assert_eq(n.guest_sim.brain.late_starts, b.guest_sim.brain.late_starts, "the replay's late start")
	_main_skip(n)
	assert_eq(n.build_tool.builder.balance(), a.build_tool.builder.balance(), "the same balance")
	assert_eq(n.money_panel.day_label.text, a.money_panel.day_label.text, "the same day's line")
	assert_eq(_feed_lines(n), _feed_lines(a), "the same feed")
	assert_eq(n.rating_history, a.rating_history, "the same rating")
	# A save holds the field only when there was a late start.
	var errors: Array[String] = []
	var state := GameSave.from_json(text, errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(state.late_starts, b.guest_sim.brain.late_starts)
	var data: Dictionary = JSON.parse_string(text)
	data["late_starts"] = [[0, -5, 2]]
	assert_null(GameSave.from_json(JSON.stringify(data), errors), "a bad late start is refused")


## E14-S2 (D69): on a course whose walks go round water (the dogleg round its pond, searched
## routes cached by GuestBrain's GuestWalk.Cache), a skip from morning gives the day run at 3x.
func test_a_day_of_walks_round_water_skips_as_it_runs() -> void:
	var sims: Array[GuestSim] = []
	var ends: Array = []
	for i: int in 2:
		var sim := GuestSim.new()
		add_child_autofree(sim)
		sim.set_process(false)
		sim.start(ReactionHoles.dogleg_par4(), SEED)
		sim.running = true
		sims.append(sim)
		ends.append(_ended_states(sim))
	sims[0].set_speed(3.0)
	_run_until_day_ends(sims[0], 1, 1.0 / 60.0, 100000)
	_skip(sims[1])
	assert_eq((ends[1] as Array).size(), 1)
	assert_gt(((ends[1] as Array)[0][1][0] as Array).size(), 0, "the day gave feed lines")
	assert_eq((ends[1] as Array)[0][1], (ends[0] as Array)[0][1], "the same day, skipped or run")


# --- E18-S3 (D72): the eighteen-hole day ---

const EighteenHoles := preload("res://tests/fixtures/eighteen_holes.gd")


func _eighteen_sim() -> GuestSim:
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(EighteenHoles.course().course, 0)
	sim.running = true
	return sim


## On a course with all eighteen open the day is eighteen_day_s long, the clock reads it, a skip
## ends it at that dusk with every round finished, and the skipped day is the day stepped.
func test_an_eighteen_hole_day_runs_eighteen_day_s_and_a_skip_gives_the_same_day() -> void:
	var tuning := GuestTuning.load_default()
	assert_eq(tuning.eighteen_day_s, 1020.0, "D72: 17 minutes at 1x")
	var sim := _eighteen_sim()
	var ends := _ended_states(sim)
	sim.advance(0.0)
	assert_true(sim.brain.eighteen_day)
	assert_eq(sim.day_length(), tuning.eighteen_day_s)
	assert_eq(sim.morning_eighteen(), 1, "a save now keeps the eighteen-hole day")
	var panel := SimSpeedPanel.new()
	panel.sim = sim
	assert_string_contains(panel.status_text(), "0:00 / 17:00", "the clock counts to 17:00")
	panel.free()
	var stepped := GuestBrain.new(sim.course, GuestSim.day_seed(0, 1), tuning, null, [], null,
			sim.day_arrivals)
	stepped.run_day()
	_skip(sim)
	assert_eq(ends.size(), 1)
	assert_eq(stepped.second, int(tuning.eighteen_day_s) + 1, "dusk at eighteen_day_s")
	var gone := 0
	for g: Guest in stepped.guests:
		assert_false(g.left_at_dusk, "guest %d finished its round of %d" % [g.id, g.round_holes])
		gone += 1
	assert_gt(gone, 0)
	var feed: Array = ends[0][1][2]
	var mine: Array = []
	for g: Guest in stepped.guests:
		var recs: Array = []
		for r: Guest.HoleRecord in g.records:
			recs.append([r.number, r.score, r.holed, r.picked_up, r.wait_s, r.walk_yd, r.start_s,
					r.end_s, r.reaction.kind if r.reaction != null else -1])
		mine.append([g.id, g.skill, g.state, g.arrived_s, g.left_s, g.left_at_dusk, g.ticks, recs])
	assert_eq(feed, mine, "the skipped day is the day stepped, guest for guest")
	# A loaded nine-hole morning stays a nine whatever was opened since (E4-S11's replay).
	sim.resume_at(1, sim.day_arrivals, [], 0)
	sim.advance(0.0)
	assert_false(sim.brain.eighteen_day, "the saved morning's day, not the course's now")
	assert_eq(sim.day_length(), tuning.day_s)


# --- E18-S5: skip to morning on the eighteen-hole day ---

## E18-S5: the eighteen-hole day of D58's most guests skips in under E7-S4's 3 s too.
const EIGHTEEN_SKIP_MAX_S := 3.0


func _eighteen_brain() -> GuestBrain:
	return GuestBrain.new(EighteenHoles.course().course, 1, null, null, [], null, NINE_GUESTS)


## E18-S5: a batch passes over guests with no Ball work (a play READY to strike or FINISHED), as
## serve does, so more guests with work run side by side; every second on the eighteen-hole day,
## busier than a nine's, is still served as one thread serves it, with and without serve_ahead.
func test_threads_serve_the_eighteen_hole_day_as_one_thread_does() -> void:
	var one := _eighteen_brain()
	var threaded := _eighteen_brain()
	var ahead := _eighteen_brain()
	assert_true(one.eighteen_day)
	var busiest := 0
	while one.second < 420:
		one.serve(-1)
		var working := 0
		for g: Guest in one.guests:
			if g.second_ticks > 0:
				working += 1
		busiest = maxi(busiest, working)
		one.step()
		threaded.advance_skip(1, -1, true)
		ahead.serve_ahead()
		ahead.settle()
		ahead.advance_skip(1, -1, true)
		if one.second % 20 == 0:
			assert_eq(_brain_state(threaded), _brain_state(one), "threads, second %d" % one.second)
			assert_eq(_brain_state(ahead), _brain_state(one), "served ahead, second %d" % one.second)
	assert_eq(one.guests.size(), NINE_GUESTS, "every guest is out")
	gut.p("the busiest second had %d guests at Ball work" % busiest)
	assert_gt(busiest, 4, "seconds with many guests at work")


func test_a_full_eighteen_hole_day_skips_in_under_3_s() -> void:
	if BestTime.later(self):
		return
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(EighteenHoles.course().course, 0)
	sim.resume_at(1, NINE_GUESTS)
	sim.running = true
	var ends := _ended_states(sim)
	var t0 := Time.get_ticks_usec()
	var frames := _skip(sim)
	var real_s := (Time.get_ticks_usec() - t0) / 1e6
	assert_eq(ends.size(), 1, "the day ended")
	assert_eq((ends[0][1][2] as Array).size(), NINE_GUESTS, "with all its guests")
	gut.p("a %d-guest eighteen-hole day (%d s): skipped in %.2f s over %d frames (headless)" % [
			NINE_GUESTS, roundi(GuestTuning.load_default().eighteen_day_s), real_s, frames])
	assert_lt(real_s, EIGHTEEN_SKIP_MAX_S, "a full eighteen-hole day skips in under %.0f s%s" % [
			EIGHTEEN_SKIP_MAX_S, BestTime.load_note()])
