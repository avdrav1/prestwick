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
	# on the top of the tile under the ball (D17, E2-S7), in flight the shadow too.
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
		var top := float(course.get_height(cell.x, cell.y))
		assert_almost_eq(view.shadow_screen(), Iso.tile_to_screen(Vector2(iso.x, iso.y), top),
				Vector2.ONE * EPS, "shadow on the top of the tile below")
		# The shadow picks back to the tile the ball is over.
		assert_eq(Iso.screen_to_cell(view.shadow_screen(), top), cell)
		if view.ball.state == Ball.State.FLYING:
			assert_almost_eq(view.ball_screen(), Iso.point_to_screen(iso), Vector2.ONE * EPS,
					"in flight the sprite is at the projected 3D position")
			var gap := view.shadow_screen().y - view.ball_screen().y
			assert_almost_eq(gap, (p.z / field.yards_per_step - top) * Iso.STEP_PX, EPS,
					"shadow sits below the ball by its height over the tile top")
			max_gap = maxf(max_gap, gap)
		else:
			assert_almost_eq(view.ball_screen(), view.shadow_screen(), Vector2.ONE * EPS,
					"on the ground the ball sits on the tile top")
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
	var ground_steps := view.ball.field.height_at(p.x, p.y) / view.ball.field.yards_per_step
	var tile := Vector2(iso.x, iso.y)
	assert_true(view.y_sort_enabled, "joins CourseView's painter's order")
	assert_almost_eq(view.sprite.position.y,
			Iso.object_sort_key(tile, view.sort_ground(tile, ground_steps)), EPS)
	var landing := view.ball.field.iso_point(view.prediction.landing)
	var landing_tile := Vector2(landing.x, landing.y)
	assert_almost_eq(view.marker.position.y,
			Iso.object_sort_key(landing_tile, view.sort_ground(landing_tile, landing.z)), EPS,
			"predicted landing marker sorts on its own tile")


## Sort key of the drawn top of the cell holding iso point `iso`.
func _own_top_key(course: CourseData, iso: Vector3) -> int:
	var cell := Vector2i(floori(iso.x + 0.5), floori(iso.y + 0.5))
	return Iso.top_sort_key(cell, course.get_height(cell.x, cell.y))


func test_ball_and_marker_sort_over_their_own_tile_top_along_the_debug_shot() -> void:
	# The debug shot leaves a 7-step pillar and rolls past tiles with lower neighbours, where
	# the bilinear ground sits under the drawn top. The pieces must still draw over that top.
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = HEIGHTS_PATH
	add_child_autofree(main)
	main.shot_view.set_process(false)
	main.set_mode(Main.Mode.PLAY)
	main.fire_debug_shot()
	var view := main.shot_view
	var course := main.course
	var landing := view.ball.field.iso_point(view.prediction.landing)
	assert_gt(view.marker.position.y, float(_own_top_key(course, landing)),
			"landing marker draws over its tile's top")
	var ticks := 0
	var under := 0
	while view.playing and ticks < 100000:
		var p := view.ball.position
		var ground := view.ball.field.iso_point(view._ground_below(p))
		if view.sprite.position.y <= float(_own_top_key(course, ground)):
			under += 1
		view.advance(1.0 / Ball.TICK_HZ)
		ticks += 1
	assert_gt(ticks, 100, "the shot ran")
	assert_eq(under, 0, "the ball never sorts under its own tile's top")


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
