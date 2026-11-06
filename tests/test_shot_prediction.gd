extends GutTest
## E1-S7: a debug shot fired from a button. The prediction runs the same Ball.step ahead of
## time; the live ball, stepped frame by frame in ShotView, lands within one tile of it on
## flat and sloped terrain. The sprite follows the projected path and its shadow sits on
## the ground beneath it.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## The debug shot's course (E1-S7). The main scene starts on the blank plot since E2-S8.
const HEIGHTS_PATH := "res://courses/heights_20x20.json"
const EPS := 0.001
## Uneven frame times (seconds), so the live ball crosses tick boundaries at odd places.
const FRAMES: Array[float] = [0.016, 0.021, 0.009, 0.033, 0.017, 0.05, 0.004]


func _flat(size: int = 40) -> CourseData:
	return CourseData.create(size, size, Surface.Type.FAIRWAY, 0)


## Heights rise one step per tile along +x, to 7.
func _ramp(size: int = 40, surface: Surface.Type = Surface.Type.FAIRWAY) -> CourseData:
	var c := _flat(size)
	for y: int in size:
		for x: int in size:
			c.set_tile(x, y, mini(x, CourseData.MAX_HEIGHT), surface)
	return c


## A plain at height 0 with a 4-step hill (its sides rising one step per tile) in the middle.
func _hill(size: int = 40) -> CourseData:
	var c := CourseData.create(size, size, Surface.Type.ROUGH, 0)
	for y: int in size:
		for x: int in size:
			var d: int = maxi(absi(x - 20), absi(y - 20))
			var h: int = clampi(8 - d, 0, 4)
			c.set_tile(x, y, h, Surface.Type.FAIRWAY if h > 0 else Surface.Type.ROUGH)
	return c


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Fires a live shot in a ShotView and plays it out with uneven frame times.
func _play_live(course: CourseData, start: Vector3, velocity: Vector3, seed_value: int) -> ShotView:
	var view := ShotView.new()
	add_child_autofree(view)
	view.set_process(false)
	view.fire(course, start, velocity, seed_value)
	var i := 0
	while view.playing and i < 100000:
		view.advance(FRAMES[i % FRAMES.size()])
		i += 1
	return view


func _assert_live_matches_prediction(course: CourseData, start: Vector3, velocity: Vector3,
		seed_value: int, label: String) -> void:
	var view := _play_live(course, start, velocity, seed_value)
	var predicted := view.prediction
	var live := view.ball
	assert_false(view.playing, "%s: the live ball came to rest" % label)
	assert_true(live.has_landed, "%s: landed" % label)
	var field := live.field
	var p_land := field.tile_at(predicted.landing.x, predicted.landing.y)
	var l_land := field.tile_at(live.landing_position.x, live.landing_position.y)
	assert_lte(_chebyshev(p_land, l_land), 1, "%s: lands within 1 tile of the prediction" % label)
	var p_rest := field.tile_at(predicted.rest.x, predicted.rest.y)
	var l_rest := field.tile_at(live.position.x, live.position.y)
	assert_lte(_chebyshev(p_rest, l_rest), 1, "%s: rests within 1 tile of the prediction" % label)
	# Same step function and seed, so it is in fact exact.
	assert_eq(live.landing_position, predicted.landing, "%s: same landing point" % label)
	assert_eq(live.position, predicted.rest, "%s: same rest point" % label)
	assert_eq(live.steps, predicted.ticks, "%s: same tick count" % label)


# --- prediction ---

func test_prediction_runs_the_ball_step_function() -> void:
	var course := _hill()
	var start := Vector3(30, 60, 0)
	var v := Ball.launch_velocity(30.0, 30.0, 20.0)
	var predicted := ShotPrediction.run(course, 5, start, v)
	# Step a Ball by hand, one tick at a time: the prediction must be that same sequence.
	var ball := Ball.new(course, 5)
	ball.launch(start, v)
	var path := PackedVector3Array([ball.position])
	while not ball.is_at_rest():
		ball.step()
		path.append(ball.position)
	assert_eq(predicted.path, path, "tick for tick the same path as Ball.step")
	assert_eq(predicted.landing, ball.landing_position)
	assert_eq(predicted.rest, ball.position)
	assert_eq(predicted.ticks, ball.steps)
	assert_eq(predicted.landing_tile, ball.field.tile_at(ball.landing_position.x, ball.landing_position.y))


func test_prediction_carry_matches_parabola_on_flat() -> void:
	var start := Vector3(20, 100, 0)
	var v := Ball.launch_velocity(30.0, 30.0, 0.0)
	var predicted := ShotPrediction.run(_flat(), 1, start, v)
	var g := BallParams.load_default().gravity
	var carry := 2.0 * v.x * v.z / g
	assert_almost_eq(predicted.landing.x - start.x, carry, 0.01, "carry from the analytic parabola")


# --- live shot vs prediction ---

func test_live_ball_lands_on_predicted_tile_flat() -> void:
	_assert_live_matches_prediction(_flat(), Vector3(20, 100, 0),
			Ball.launch_velocity(32.0, 30.0, 0.0), 11, "flat, straight")
	_assert_live_matches_prediction(_flat(), Vector3(20, 20, 0),
			Ball.launch_velocity(28.0, 35.0, 45.0), 12, "flat, diagonal")


func test_live_ball_lands_on_predicted_tile_sloped() -> void:
	_assert_live_matches_prediction(_ramp(), Vector3(15, 100, 0),
			Ball.launch_velocity(30.0, 30.0, 0.0), 21, "uphill")
	_assert_live_matches_prediction(_ramp(), Vector3(180, 100, 0),
			Ball.launch_velocity(30.0, 30.0, 180.0), 22, "downhill")
	_assert_live_matches_prediction(_ramp(40, Surface.Type.ROUGH), Vector3(20, 20, 0),
			Ball.launch_velocity(30.0, 30.0, 90.0), 23, "across the slope, on rough with scatter")
	_assert_live_matches_prediction(_hill(), Vector3(40, 102, 0),
			Ball.launch_velocity(32.0, 28.0, 0.0), 24, "over a hill")


func test_debug_shot_on_main_course_lands_on_prediction() -> void:
	var shot := DebugShot.load_default()
	var course := CourseSave.load_file("res://courses/heights_20x20.json")
	assert_not_null(course, "the main scene's course loads")
	var field := HeightField.new(course, BallParams.load_default())
	_assert_live_matches_prediction(course, shot.start_position(field), shot.velocity(),
			shot.rng_seed, "debug shot on heights_20x20")


# --- drawing ---

func test_sprite_follows_projected_path_and_shadow_shows_height() -> void:
	# In flight the sprite is at the projected 3D point; on the ground it and the shadow are
	# on the drawn ground under the ball (D50, E3-S59; D17's tile top before), in flight the
	# shadow too.
	var course := _hill()
	var view := ShotView.new()
	add_child_autofree(view)
	view.set_process(false)
	view.fire(course, Vector3(40, 102, 0), Ball.launch_velocity(32.0, 28.0, 0.0), 3)
	var field := view.ball.field
	var max_gap := 0.0
	var checked := 0
	var on_ground := 0
	while view.playing:
		view.advance(1.0 / 30.0)
		var p := view.ball.position
		var iso := field.iso_point(p)
		var cell := field.tile_at(p.x, p.y)
		var top := field.drawn_steps(p.x, p.y)
		assert_almost_eq(top, field.height_at(p.x, p.y) / field.yards_per_step, 0.0001, "no water here: height_at")
		assert_almost_eq(view.shadow_screen(), Iso.tile_to_screen(Vector2(iso.x, iso.y), top),
				Vector2.ONE * EPS, "shadow on the ground below")
		# The shadow picks back to the tile the ball is over.
		assert_eq(Iso.screen_to_cell(view.shadow_screen(), top), cell)
		if view.ball.state == Ball.State.FLYING:
			assert_almost_eq(view.ball_screen(), Iso.point_to_screen(iso), Vector2.ONE * EPS,
					"in flight the sprite is at the projected 3D position")
			var gap := view.shadow_screen().y - view.ball_screen().y
			assert_almost_eq(gap, (p.z / field.yards_per_step - top) * Iso.STEP_PX, EPS,
					"shadow sits below the ball by its height over the ground")
			max_gap = maxf(max_gap, gap)
		else:
			assert_almost_eq(view.ball_screen(), view.shadow_screen(), Vector2.ONE * EPS,
					"on the ground the ball sits on its shadow, on the ground")
			on_ground += 1
		checked += 1
	assert_gt(checked, 10)
	assert_gt(on_ground, 0, "the ball rolled")
	assert_gt(max_gap, Iso.STEP_PX * 2.0, "in flight the ball rises well clear of its shadow")


func test_ball_sorts_as_an_object_on_its_ground_tile() -> void:
	var course := _hill()
	var view := ShotView.new()
	add_child_autofree(view)
	view.set_process(false)
	view.fire(course, Vector3(40, 102, 0), Ball.launch_velocity(32.0, 28.0, 0.0), 3)
	view.advance(0.8)
	var p := view.ball.position
	var iso := view.ball.field.iso_point(p)
	var ground_steps := view.ball.field.drawn_steps(p.x, p.y)
	var tile := Vector2(iso.x, iso.y)
	assert_true(view.y_sort_enabled, "joins CourseView's painter's order")
	assert_almost_eq(view.sprite.position.y, Iso.object_sort_key(tile, ground_steps), EPS)
	var landing := view.ball.field.iso_point(view.prediction.landing)
	var landing_tile := Vector2(landing.x, landing.y)
	var landing_ground := view.ball.field.drawn_steps(view.prediction.landing.x, view.prediction.landing.y)
	assert_almost_eq(view.marker.position.y, Iso.object_sort_key(landing_tile, landing_ground), EPS,
			"predicted landing marker sorts on its own tile")


## Sort key of the row of ground (E3-S58) holding iso point `iso`.
func _own_row_key(iso: Vector3) -> int:
	return Iso.depth_key(Vector2i(floori(iso.x + 0.5), floori(iso.y + 0.5)))


func test_ball_and_marker_sort_over_their_own_row_of_ground_along_the_debug_shot() -> void:
	# The debug shot leaves a 7-step pillar and rolls down its slopes. The pieces must draw over
	# the row of ground they stand on, and under the next.
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = HEIGHTS_PATH
	add_child_autofree(main)
	main.shot_view.set_process(false)
	main.set_mode(Main.Mode.PLAY)
	main.fire_debug_shot()
	var view := main.shot_view
	var landing := view.ball.field.iso_point(view.prediction.landing)
	assert_gt(view.marker.position.y, float(_own_row_key(landing)), "landing marker draws over its row")
	assert_lt(view.marker.position.y, float(_own_row_key(landing) + Iso.HALF_H), "and under the next")
	var ticks := 0
	var under := 0
	while view.playing and ticks < 100000:
		var p := view.ball.position
		var ground := view.ball.field.iso_point(view._ground_below(p))
		var key := float(_own_row_key(ground))
		if view.sprite.position.y <= key or view.sprite.position.y >= key + Iso.HALF_H:
			under += 1
		view.advance(1.0 / Ball.TICK_HZ)
		ticks += 1
	assert_gt(ticks, 100, "the shot ran")
	assert_eq(under, 0, "the ball always sorts over its own row and under the next")


func test_live_ball_steps_at_60_hz_whatever_the_frame_rate() -> void:
	var view := ShotView.new()
	add_child_autofree(view)
	view.set_process(false)
	view.fire(_flat(), Vector3(20, 100, 0), Ball.launch_velocity(30.0, 30.0, 0.0), 1)
	view.advance(0.5)
	assert_eq(view.ball.steps, 30, "half a second is 30 ticks")
	for i in 10:
		view.advance(0.01)
	assert_eq(view.ball.steps, 36, "a tenth of a second more in small frames is 6 ticks")


# --- the debug key (E2-S8; the button until then) ---

func test_play_mode_debug_key_fires_the_debug_shot() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = HEIGHTS_PATH
	add_child_autofree(main)
	main.shot_view.set_process(false)
	var key := InputEventAction.new()
	key.action = Main.DEBUG_SHOT_ACTION
	key.pressed = true
	main._unhandled_input(key)
	assert_false(main.shot_view.playing, "no debug shot while building")
	var f3 := InputEventKey.new()
	f3.physical_keycode = KEY_F3
	f3.pressed = true
	assert_true(f3.is_action(Main.DEBUG_SHOT_ACTION), "F3 is the debug key")
	main.set_mode(Main.Mode.PLAY)
	assert_false(main.shot_view.playing)
	main._unhandled_input(key)
	assert_true(main.shot_view.playing, "the key launches the ball")
	assert_not_null(main.shot_view.prediction, "and predicts where it lands")
	var shot := main.debug_shot
	var field := main.shot_view.ball.field
	assert_eq(main.shot_view.ball.velocity, shot.velocity(), "at the fixed power and angle")
	var expected := ShotPrediction.run(main.course, shot.rng_seed, shot.start_position(field), shot.velocity())
	assert_eq(main.shot_view.prediction.landing, expected.landing)
	main.shot_view.advance(30.0)
	assert_false(main.shot_view.playing)
	assert_eq(main.shot_view.ball.landing_position, expected.landing, "lands where predicted")
	main.set_mode(Main.Mode.BUILD)
	assert_false(main.can_fire_debug_shot(), "not in Build")
	assert_false(main.shot_view.visible, "the shot is cleared from the Build view")


# --- the swing (E2-S7) ---

func test_perfect_swing_lands_within_a_tile_of_the_aim_marker() -> void:
	# Through the Play HUD: the marker comes from the aim's prediction, the ball from a swing
	# clicked at 100% and at the centre, flown live in ShotView.
	for club_id: String in ["driver", "5i", "9i", "sw"]:
		var main := MAIN_SCENE.instantiate() as Main
		main.course_path = "res://courses/example_par3.json"
		add_child_autofree(main)
		main.shot_view.set_process(false)
		main.swing_control.set_process(false)
		main.set_mode(Main.Mode.PLAY)
		var sc := main.swing_control
		sc.select_club(sc.model.clubs.club(club_id))
		sc.rotate_aim(-4.0)
		sc._refresh_aim()
		var marker := main.aim_view.marker_point
		assert_eq(marker, sc.aim_prediction.landing, "%s: the marker is the predicted touchdown" % club_id)
		sc.press()
		sc.advance(1.0 / sc.swing.rate())
		sc.press()
		sc.advance(1.0 / sc.swing.rate())
		sc.press()
		var view := main.shot_view
		var i := 0
		while view.playing and i < 100000:
			view.advance(FRAMES[i % FRAMES.size()])
			i += 1
		var field := view.ball.field
		var want := field.tile_at(marker.x, marker.y)
		var got := field.tile_at(view.ball.landing_position.x, view.ball.landing_position.y)
		assert_lte(_chebyshev(want, got), 1, "%s: lands within 1 tile of the marker" % club_id)
		assert_lt(Vector2(marker.x - view.ball.landing_position.x, marker.y - view.ball.landing_position.y).length(),
				0.5, "%s: in fact within half a yard" % club_id)


## D20: at the foot of a riser, a club the face stops at once is shown as blocked in the
## marker and the club picker; a club that flies keeps its plain marker, and its perfect
## swing lands on it. The physics is kept, so a blocked club can still be struck.
func test_the_marker_and_picker_show_a_club_blocked_at_the_foot_of_a_riser() -> void:
	for steps: int in [1, 2]:
		var main := MAIN_SCENE.instantiate() as Main
		main.course_path = "res://tests/fixtures/flat_20x20.json"
		add_child_autofree(main)
		main.shot_view.set_process(false)
		main.swing_control.set_process(false)
		main.show_course(BalanceStrips.uphill(steps))
		main.set_mode(Main.Mode.PLAY)
		var sc := main.swing_control
		var at := (Vector2(BalanceStrips.tee_tile()) + Vector2(0.5, 0.5)) * 5.0
		sc.place_ball(at, true)
		sc.aim_deg = 0.0
		for c in sc.legal:
			sc.select_club(c)
			sc._refresh_aim()
			var want := sc.model.clubs.is_blocked(sc.perfect_launch(), sc.aim_prediction)
			assert_eq(sc.aim_blocked, want, "%d steps, %s: the control reads the rule" % [steps, c.id])
			assert_eq(main.aim_view.blocked, want, "%d steps, %s: the marker says so" % [steps, c.id])
			assert_eq(main.swing_panel.club_label.text.contains("blocked"), want,
					"%d steps, %s: the picker says so" % [steps, c.id])
			assert_eq(main.aim_view.marker_point, sc.aim_prediction.landing,
					"%d steps, %s: the marker is still the first touchdown" % [steps, c.id])
			assert_eq(main.aim_view.dots.is_empty(), want,
					"%d steps, %s: a blocked club draws no dots" % [steps, c.id])
		sc.select_club(sc.model.clubs.club("driver"))
		sc._refresh_aim()
		assert_true(sc.aim_blocked, "%d steps: the driver is blocked" % steps)
		if steps == 1:
			sc.select_club(sc.model.clubs.club("7i"))
			sc._refresh_aim()
			assert_false(sc.aim_blocked, "the 7i clears one step")
		# Strike a perfect swing; a blocked club is still struck (the physics is kept).
		var marker := main.aim_view.marker_point
		sc.press()
		sc.advance(1.0 / sc.swing.rate())
		sc.press()
		sc.advance(1.0 / sc.swing.rate())
		sc.press()
		assert_eq(sc.strokes, 1, "%d steps: the swing is struck" % steps)
		var view := main.shot_view
		var i := 0
		while view.playing and i < 100000:
			view.advance(FRAMES[i % FRAMES.size()])
			i += 1
		var got := view.ball.landing_position
		assert_lt(Vector2(marker.x - got.x, marker.y - got.y).length(), 0.5,
				"%d steps: the ball lands on the marker" % steps)


func test_debug_shot_tunables_come_from_a_resource() -> void:
	var shot := DebugShot.load_default()
	assert_not_null(shot, "golf/debug_shot.tres loads")
	assert_gt(shot.speed, 0.0)
	assert_between(shot.launch_deg, 1.0, 89.0)
	assert_eq(shot.velocity(), Ball.launch_velocity(shot.speed, shot.launch_deg, shot.heading_deg))


# --- the putter's marker (E2-S20, D21) ---

## A Main in Play on `course` with hole 1 from `tee` to `cup`; the ball then rests at `at`
## (yards), aimed at the cup turned by `off_deg`.
func _putt_main(course: CourseData, tee: Vector2i, cup: Vector2i, at: Vector2,
		off_deg: float = 0.0) -> Main:
	course.set_holes([HoleData.new(1, 3, tee, cup, true)] as Array[HoleData])
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(main)
	main.shot_view.set_process(false)
	main.swing_control.set_process(false)
	main.show_course(course)
	main.set_mode(Main.Mode.PLAY)
	var sc := main.swing_control
	sc.place_ball(at)
	sc.aim_at(sc.field.tile_center(cup))
	sc.rotate_aim(off_deg)
	sc._refresh_aim()
	sc.settle_aim()
	return main


## The rest nearest the cup over the bar from 0 to 100% in 1% steps, yards from its centre.
## E2-S16: every 5%, then every 1% within 4% of the nearest of those (29 putts, not 101).
## Sweep.full() tries every 1% step.
func _brute_nearest(sc: SwingControl) -> float:
	var cup := sc.field.tile_center(sc.cup_tile())
	var miss := func(i: int) -> float:
		var s := PuttAim.launch_at(sc.model, sc.tuning, sc.field, sc.ball_at, sc.aim_deg, i / 100.0)
		var p := ShotPrediction.run_launch(sc.course, sc.next_seed(), s, null, null, sc.cup_tile())
		return 0.0 if p.holed else Vector2(p.rest.x, p.rest.y).distance_to(cup)
	var step := 1 if Sweep.full() else 5
	var best := INF
	var at := 0
	for i in range(0, 101, step):
		var d: float = miss.call(i)
		if d < best:
			best = d
			at = i
	if step > 1:
		for i in range(maxi(at - step + 1, 0), mini(at + step, 101)):
			if i != at:
				best = minf(best, miss.call(i))
	return best


## The marker shows the putt at the solved power, nearest the cup; a putt struck through the
## bar at that power rests within 1 yd of it; a putt at 100% still runs past (the bar decides).
## `nearest` is `_brute_nearest(sc)` when the caller has it already (E2-S16: 101 putts each).
func _assert_putt_marker(main: Main, label: String, nearest: float = NAN) -> void:
	var sc := main.swing_control
	if is_nan(nearest):
		nearest = _brute_nearest(sc)
	assert_true(sc.club.is_putter(), "%s: the putter" % label)
	var cup := sc.field.tile_center(sc.cup_tile())
	var marker := main.aim_view.marker_point
	assert_eq(marker, sc.aim_prediction.rest, "%s: the marker is the shown putt's rest" % label)
	assert_eq(sc.aim_prediction, sc.aim_putt.prediction, "%s: the shown putt is the solve's" % label)
	assert_lt(sc.aim_power, 1.0, "%s: not the 100%% putt" % label)
	var miss := Vector2(marker.x, marker.y).distance_to(cup)
	assert_almost_eq(miss, 0.0 if sc.aim_prediction.holed else sc.aim_putt.miss_yd, 1e-4, label)
	assert_lte(miss, nearest + 0.15, "%s: as near the cup as any power on the bar" % label)
	var last :=sc.aim_prediction.path[sc.aim_prediction.path.size() - 1]
	assert_eq(Vector2(last.x, last.y), Vector2(marker.x, marker.y), "%s: the dots' roll ends on the marker" % label)
	var full := ShotPrediction.run_launch(sc.course, sc.next_seed(),
			PuttAim.launch_at(sc.model, sc.tuning, sc.field, sc.ball_at, sc.aim_deg, 1.0), null, null, sc.cup_tile())
	assert_gt(Vector2(full.rest.x, full.rest.y).distance_to(Vector2(marker.x, marker.y)), 3.0,
			"%s: a 100%% putt rests elsewhere" % label)
	# Strike through the bar at the solved power, accuracy at the centre.
	var power := sc.aim_power
	sc.press()
	sc.advance(power / sc.swing.rate())
	sc.press()
	sc.advance(power / sc.swing.rate())
	sc.press()
	assert_eq(sc.strokes, 1, "%s: struck" % label)
	var view := main.shot_view
	var i := 0
	while view.playing and i < 100000:
		view.advance(FRAMES[i % FRAMES.size()])
		i += 1
	var got := view.ball.position
	assert_lt(Vector2(got.x - marker.x, got.y - marker.y).length(), 1.0,
			"%s: the putt struck at that power rests within 1 yd of the marker" % label)


func test_putter_marker_shows_the_pace_that_reaches_the_cup_on_a_flat_green() -> void:
	var cup := Vector2i(10, 6)
	for case: Array in [[3.0, 0.0], [8.0, 0.0], [17.0, 0.0], [12.0, 6.0]]:
		var course := CourseData.create(30, 12, Surface.Type.GREEN, 0)
		var at := Vector2(52.5 - float(case[0]), 32.5)
		var main := _putt_main(course, Vector2i(2, 6), cup, at, case[1])
		var label := "flat, %.0f yd, %.0f deg off" % [case[0], case[1]]
		if is_zero_approx(case[1]):
			assert_lt(main.swing_control.aim_putt.miss_yd, 0.3, "%s: on the cup" % label)
		_assert_putt_marker(main, label)


## E2-S20 review: with the aim turned well off the cup, the shown putt is still the one that
## rests nearest it (the miss is measured along the aim), and a cup square to the aim or
## behind it shows the 0% putt.
func test_putter_marker_with_the_aim_turned_off_the_cup() -> void:
	var cup := Vector2i(10, 6)
	for off: float in [20.0, 30.0, 60.0, -60.0, 90.0, 135.0, 180.0]:
		var course := CourseData.create(30, 12, Surface.Type.GREEN, 0)
		var main := _putt_main(course, Vector2i(2, 6), cup, Vector2(40.0, 32.5), off)
		var sc := main.swing_control
		var label := "flat, 12.5 yd, %.0f deg off" % off
		var marker := main.aim_view.marker_point
		var miss := Vector2(marker.x, marker.y).distance_to(sc.field.tile_center(cup))
		var nearest := _brute_nearest(sc)
		assert_lte(miss, nearest + 0.15, "%s: as near the cup as any power on the bar" % label)
		assert_lte(sc.aim_putt.runs, sc.tuning.putt_aim_max_runs)
		if absf(off) >= 90.0:
			assert_eq(sc.aim_power, 0.0, "%s: the cup is not ahead, the 0%% putt" % label)
		else:
			assert_almost_eq(miss, 12.5 * sin(deg_to_rad(absf(off))), 0.3,
					"%s: rests level with the cup along the aim" % label)
		if absf(off) <= 60.0:
			_assert_putt_marker(main, label, nearest)


func test_putter_marker_shows_the_pace_that_reaches_the_cup_on_a_contour() -> void:
	# The E1-S9 contour (terraces one step apart, two tiles deep): up across it diagonally,
	# along it, and down the mirrored one.
	for case: Array in [[false, Vector2(22.5, 37.5), Vector2i(7, 5)],
			[false, Vector2(32.5, 22.5), Vector2i(7, 8)],
			[true, Vector2(32.5, 22.5), Vector2i(10, 7)]]:
		var course := GridHeightEvidence.green_contour(case[0])
		var main := _putt_main(course, Vector2i(1, 5), case[2], case[1])
		_assert_putt_marker(main, "contour%s from %s to %s" % [" mirrored" if case[0] else "", case[1], case[2]])


func test_putter_marker_with_no_cup_is_the_full_putt() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(main)
	main.shot_view.set_process(false)
	main.swing_control.set_process(false)
	main.show_course(GridHeightEvidence.green_contour())
	main.set_mode(Main.Mode.PLAY)
	var sc := main.swing_control
	sc.place_ball(Vector2(27.5, 27.5))
	sc._refresh_aim()
	assert_eq(sc.cup_tile(), Ball.NO_CUP)
	assert_eq(sc.aim_power, 1.0, "no cup: the marker is the 100% putt")
	var want := ShotPrediction.run_launch(sc.course, sc.next_seed(), sc.perfect_launch())
	assert_eq(sc.aim_prediction.rest, want.rest)


## The solve runs while the player aims, so it must stay cheap: a sweep of the aim, warm
## started from the last solve, takes few runs per update. Prints its cost.
func test_putter_marker_solve_is_cheap_while_aiming() -> void:
	var course := GridHeightEvidence.green_contour()
	var main := _putt_main(course, Vector2i(1, 5), Vector2i(7, 5), Vector2(22.5, 37.5), -6.0)
	var sc := main.swing_control
	var runs := 0
	var usec := 0
	var worst := 0
	var updates := 25
	for i in updates:
		sc.rotate_aim(0.5)
		var t0 := Time.get_ticks_usec()
		sc._refresh_aim()
		sc.settle_aim()
		usec += Time.get_ticks_usec() - t0
		runs += sc.aim_putt.runs
		worst = maxi(worst, sc.aim_putt.runs)
		assert_lte(sc.aim_putt.runs, sc.tuning.putt_aim_max_runs)
	gut.p("putter aim solve: %.1f runs and %.1f ms per update (worst %d runs)" % [
			float(runs) / updates, usec / 1000.0 / updates, worst])
	assert_lt(float(runs) / updates, 4.0, "warm started: under 4 putts per update on average")
	# A cold start (a new ball position) from the flat-roll guess.
	sc.aim_putt = null
	var t1 := Time.get_ticks_usec()
	sc._refresh_aim()
	sc.settle_aim()
	gut.p("putter aim solve, cold: %d runs, %.1f ms" % [sc.aim_putt.runs,
			(Time.get_ticks_usec() - t1) / 1000.0])
	assert_lte(sc.aim_putt.runs, sc.tuning.putt_aim_max_runs)


# --- steep banks (E6-S12) ---

## A 30 x 12 green rising two steps per tile along +x from tile 10 (heights 0, 2, 4, 6, then
## 7): a bank a ball cannot rest on, so a harder uphill putt can roll back further.
func _steep_bank() -> CourseData:
	var course := CourseData.create(30, 12, Surface.Type.GREEN, 0)
	for y in 12:
		for x in 30:
			course.set_tile(x, y, clampi((x - 10) * 2, 0, 7), Surface.Type.GREEN)
	return course


## E6-S12 review: a 60 x 60 staircase bank whose risers run diagonally, each two steps in one
## tile (height ((x + y) / 2 - 10) * 2, clamped to 0 to 7), so the bands are not aligned with
## the grid axes.
func _diagonal_staircase() -> CourseData:
	var course := CourseData.create(60, 60, Surface.Type.GREEN, 0)
	for y in 60:
		for x in 60:
			course.set_tile(x, y, clampi(((x + y) / 2 - 10) * 2, 0, 7), Surface.Type.GREEN)
	return course


## How far from the cup (yards, 0 when holed) the putt at `percent` of the bar rests.
func _putt_miss(sc: SwingControl, percent: int) -> float:
	var cup := sc.field.tile_center(sc.cup_tile())
	var s := PuttAim.launch_at(sc.model, sc.tuning, sc.field, sc.ball_at, sc.aim_deg, percent / 100.0)
	var p := ShotPrediction.run_launch(sc.course, sc.next_seed(), s, null, null, sc.cup_tile())
	return 0.0 if p.holed else Vector2(p.rest.x, p.rest.y).distance_to(cup)


## The brute-force nearest putt: every 1% of the bar, as [yards from the cup (0 when holed),
## the first percent that rests there]. A capture window on a bank can be 2% wide, so no
## coarse first pass.
func _brute_nearest_every_percent(sc: SwingControl) -> Array:
	var best := INF
	var at := 0
	for i in 101:
		var d := _putt_miss(sc, i)
		if d < best:
			best = d
			at = i
	return [best, at]


## E6-S12 Accept: on a bank of two steps per tile the marker rests within 1 yd of the
## brute-force nearest putt. Before the scan the solve stopped up to 7 yd off on these:
## a cup on the bank holed only in a narrow window (0.83 to 0.88, and 0.77 to 0.78 from just
## off the line), a cup up the bank out of reach (the nearest rest is at its foot, from a
## soft putt), and downhill over the bank's edge. E6-S12 review, on the diagonal staircase:
## the nearest rest is the hardest putt that stops before it rolls back (3.9 yd at 71%, 7.6
## yd at 72%; the scan and golden search alone stopped at 6.6 yd), and a downhill putt whose
## reach jumps where it crests a riser (false position spent every run on the jump, 1.7 yd
## off).
##
## E6-S22: the brute force (101 putts a case) runs only under Sweep.full(). By default each
## case strikes the one putt the full run found nearest, pinned as [percent, yards] below:
## the marker must be within 1 yd of it, and that putt must still rest where it was measured,
## so a physics change that moves it fails here and sends you to `--full` to re-pin. Only a
## better putt somewhere else on the bar is left to `--full`. Re-pinned in E3-S51 (D49: the
## putter's bar curve moved every power, and cup_radius 0.3 holes the diagonal staircase's
## first case at 100%); the percents and yards above E3-S51 in this note are the old bar's.
func test_putter_marker_on_a_steep_bank_is_near_the_nearest_putt() -> void:
	# [cup, ball at, on the diagonal staircase, aim turned (deg), [nearest percent, yards]]
	for case: Array in [
			[Vector2i(11, 6), Vector2(42.5, 32.5), false, 0.0, [94, 0.0]],
			[Vector2i(11, 6), Vector2(45.0, 31.0), false, 0.0, [91, 0.0]],
			[Vector2i(12, 6), Vector2(42.5, 32.5), false, 0.0, [70, 10.11]],
			[Vector2i(13, 6), Vector2(35.0, 22.5), false, 0.0, [88, 15.80]],
			[Vector2i(15, 6), Vector2(47.5, 32.5), false, 0.0, [51, 25.07]],
			[Vector2i(13, 6), Vector2(80.0, 22.5), false, 0.0, [84, 0.0]],
			[Vector2i(9, 6), Vector2(92.5, 31.0), false, 0.0, [97, 3.35]],
			[Vector2i(11, 11), Vector2(41.0, 43.0), true, 0.0, [100, 0.0]],
			[Vector2i(11, 11), Vector2(90.0, 70.0), true, 4.0, [99, 10.18]]]:
		var cup: Vector2i = case[0]
		var at: Vector2 = case[1]
		var diagonal: bool = case[2]
		var off: float = case[3]
		var pinned: Array = case[4]
		var course := _diagonal_staircase() if diagonal else _steep_bank()
		var main := _putt_main(course, Vector2i(1, 6), cup, at, off)
		var sc := main.swing_control
		var label := "%s, cup %s from %s, %+.0f deg" % [
				"diagonal staircase" if diagonal else "steep bank", cup, at, off]
		var pinned_miss := _putt_miss(sc, pinned[0])
		assert_almost_eq(pinned_miss, float(pinned[1]), 0.01,
				"%s: the pinned nearest putt (%d%%) still rests where it was measured; if the physics moved it, re-pin from scripts/run_tests.sh --full" % [label, pinned[0]])
		var nearest := pinned_miss
		if Sweep.full():
			var brute := _brute_nearest_every_percent(sc)
			gut.p("%s: brute nearest %.2f yd at %d%%" % [label, brute[0], brute[1]])
			assert_almost_eq(float(brute[0]), float(pinned[1]), 0.01,
					"%s: the pinned putt is the nearest the bar makes (brute %.2f yd at %d%%)" % [label, brute[0], brute[1]])
			nearest = brute[0]
		var marker := main.aim_view.marker_point
		assert_eq(marker, sc.aim_putt.prediction.rest, "%s: the marker is the solve's rest" % label)
		assert_true(sc.aim_putt.done, "%s: solved" % label)
		assert_lte(sc.aim_putt.runs, sc.tuning.putt_aim_max_runs, label)
		var miss := 0.0 if sc.aim_putt.prediction.holed \
				else Vector2(marker.x, marker.y).distance_to(sc.field.tile_center(cup))
		gut.p("%s: marker %.2f yd from the cup, nearest %.2f, %d runs%s" % [label, miss, nearest,
				sc.aim_putt.runs, ", scanned" if sc.aim_putt.scanned else ""])
		assert_lte(miss, nearest + 1.0, "%s: within 1 yd of the nearest putt the bar makes" % label)


## A solve stepped a few Ball ticks at a time ends on the same putt as one run at once: a
## budget only spreads it over frames.
func test_putter_solve_over_frames_matches_the_solve_at_once() -> void:
	var course := _steep_bank()
	var model := ShotModel.new()
	var tuning := SwingTuning.load_default()
	var field := HeightField.new(course, model.params)
	var cup := Vector2i(11, 6)
	var at := Vector2(42.5, 32.5)
	var aim := rad_to_deg((field.tile_center(cup) - at).angle())
	var whole := PuttAim.solve(course, field, model, tuning, at, aim, cup, 1)
	var spread := PuttAim.begin(course, field, model, tuning, at, aim, cup, 1)
	var calls := 0
	while not spread.done and calls < 100000:
		assert_lte(spread.advance(37), 37, "never more than the budget")
		calls += 1
	assert_true(spread.done)
	assert_gt(calls, whole.runs, "spread over many calls")
	assert_eq(spread.power, whole.power)
	assert_eq(spread.runs, whole.runs)
	assert_eq(spread.ticks, whole.ticks)
	assert_eq(spread.prediction.rest, whole.prediction.rest)
	assert_eq(spread.prediction.holed, whole.prediction.holed)


## E3-S51 (D49): once a putt holes, the solve centres its pace: a dry roll (no cup) at the
## solved power runs putt_aim_past_yd past the cup, within its tolerance, and still drops with
## the cup, so a click a little soft or firm drops too. With putt_aim_past_yd 0 the solve stops
## at the first pace that drops, softer than the centred one.
func test_the_putter_solve_centres_a_holed_putts_pace() -> void:
	var course := ShortGameHoles.flat_green()
	var model := ShotModel.new()
	var tuning := SwingTuning.load_default()
	assert_gt(tuning.putt_aim_past_yd, 0.0)
	var edge := tuning.duplicate() as SwingTuning
	edge.putt_aim_past_yd = 0.0
	var field := HeightField.new(course, model.params)
	var cup_tile := ShortGameHoles.CUP
	var cup := field.tile_center(cup_tile)
	for d: float in [1.0, 3.0, 8.0]:
		var at := cup - Vector2(d, 0.0)
		var a := PuttAim.solve(course, field, model, tuning, at, 0.0, cup_tile, 1)
		assert_true(a.prediction.holed, "%.0f yd: holed" % d)
		assert_lte(a.runs, tuning.putt_aim_max_runs, "%.0f yd" % d)
		var dry := ShotPrediction.run_launch(course, 1, PuttAim.launch_at(model, tuning, field, at, 0.0, a.power))
		var past := dry.rest.x - cup.x
		assert_almost_eq(past, tuning.putt_aim_past_yd, tuning.putt_aim_past_tolerance_yd + 0.01,
				"%.0f yd: with no cup it runs out %.2f yd past" % [d, past])
		var first := PuttAim.solve(course, field, model, edge, at, 0.0, cup_tile, 1)
		assert_true(first.prediction.holed)
		assert_lt(first.power, a.power, "%.0f yd: the first pace that drops is softer" % d)
