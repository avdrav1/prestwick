extends GutTest
## E2-S7: the three-click swing (golf/swing.gd), with no scene, and its Play-mode input
## (scenes/swing_control.gd). docs/design.md Swing has the numbers (golf/swing_tuning.tres).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const EPS := 1e-4

var _t: SwingTuning


func before_each() -> void:
	_t = SwingTuning.load_default()


func _yd(tile: Vector2) -> Vector2:
	return (tile + Vector2(0.5, 0.5)) * 5.0


## Fills the bar to `power` (from click 1), clicks, returns it to `accuracy`, clicks, with
## ticks of `dt`. The ticks land exactly on the targets.
func _swing_to(s: Swing, power: float, accuracy: float) -> void:
	s.click()
	s.tick(power / s.rate())
	s.click()
	s.tick((power - accuracy) / s.rate())
	s.click()


# --- the tuning ---

func test_tuning_loads_and_is_usable() -> void:
	assert_not_null(_t, "golf/swing_tuning.tres loads")
	assert_eq(Swing.validate(_t), PackedStringArray())
	assert_almost_eq(_t.fill_time, 1.2, EPS, "the bar fills in 1.2 s (design doc)")
	assert_almost_eq(_t.max_power, 1.1, EPS, "and runs to 110%")
	assert_almost_eq(_t.deg_per_10pct, 2.0, EPS, "2 degrees per 10% off centre")


# --- the bar ---

func test_bar_fills_to_100_in_1_2_s_and_runs_on_to_110() -> void:
	var s := Swing.new(_t)
	assert_eq(s.phase, Swing.Phase.IDLE)
	s.click()
	assert_eq(s.phase, Swing.Phase.POWER)
	s.tick(0.6)
	assert_almost_eq(s.bar, 0.5, EPS, "half way at 0.6 s")
	s.tick(0.6)
	assert_almost_eq(s.bar, 1.0, EPS, "100% at 1.2 s")
	s.tick(0.06)
	assert_almost_eq(s.bar, 1.05, EPS, "it runs on past 100%")
	s.tick(1.0)
	assert_eq(s.phase, Swing.Phase.ACCURACY, "at 110% the power locks by itself")
	assert_almost_eq(s.power, 1.1, EPS, "at 110%")


func test_zero_percent() -> void:
	var s := Swing.new(_t)
	s.click()
	s.click()
	assert_almost_eq(s.power, 0.0, EPS, "two clicks at once lock 0%")
	s.click()
	assert_true(s.is_done())
	assert_almost_eq(s.accuracy, 0.0, EPS, "and the bar is at the centre")
	assert_false(s.is_shank())
	var clubs := ClubSet.load_default()
	var model := ShotModel.new()
	var field := HeightField.new(CourseData.create(40, 40, Surface.Type.FAIRWAY, 0), model.params)
	var shot := s.launch(model, field, clubs.club("7i"), _yd(Vector2(5, 20)), 0.0)
	assert_almost_eq(shot.target_carry, 0.0, EPS, "0% carries nothing")
	var putt := s.launch(model, field, clubs.putter(), _yd(Vector2(5, 20)), 0.0)
	assert_almost_eq(putt.ground_velocity.length(), clubs.putter().putt_min_speed, EPS,
			"a 0% putt starts at the putter's slowest speed")


func test_one_hundred_percent_is_the_clubs_full_carry() -> void:
	var s := Swing.new(_t)
	_swing_to(s, 1.0, 0.0)
	assert_true(s.is_done())
	assert_almost_eq(s.power, 1.0, EPS)
	assert_almost_eq(s.offset_deg(), 0.0, 0.01, "accuracy at the centre: no hook or slice")
	var model := ShotModel.new()
	var field := HeightField.new(CourseData.create(80, 40, Surface.Type.FAIRWAY, 0), model.params)
	var club := model.clubs.club("7i")
	var shot := s.launch(model, field, club, _yd(Vector2(5, 20)), 0.0)
	assert_almost_eq(shot.target_carry, club.carry_yd, 0.01, "100% on fairway is the full carry")
	var perfect := s.perfect_launch(model, field, club, _yd(Vector2(5, 20)), 0.0)
	assert_almost_eq(shot.velocity, perfect.velocity, Vector3.ONE * 1e-3, "the same as a perfect swing")


func test_one_hundred_and_ten_percent_overswing() -> void:
	var s := Swing.new(_t)
	s.click()
	s.tick(10.0)
	assert_almost_eq(s.power, 1.1, EPS, "the bar locks at 110%")
	s.tick(1.1 / s.rate())
	s.click()
	assert_false(s.is_shank())
	var model := ShotModel.new()
	var field := HeightField.new(CourseData.create(80, 40, Surface.Type.FAIRWAY, 0), model.params)
	var club := model.clubs.club("7i")
	var shot := s.launch(model, field, club, _yd(Vector2(5, 20)), 0.0)
	assert_almost_eq(shot.target_carry, 1.1 * club.carry_yd, 0.01, "110% carries 1.1 times as far")
	assert_almost_eq(s.zone_half_width(), _t.zone_half * _t.overswing_zone_scale, EPS,
			"the penalty: the zone narrows to its overswing share at 110%")
	var putt := s.launch(model, field, model.clubs.putter(), _yd(Vector2(5, 20)), 0.0)
	assert_almost_eq(putt.ground_velocity.length(), model.clubs.putter().putt_max_speed, EPS,
			"an overswung putt is no faster than a full one")


func test_overswing_narrows_the_zone() -> void:
	var s := Swing.new(_t)
	var inside_at_100 := _t.zone_half * 0.9
	s.set_result(1.0, inside_at_100)
	assert_false(s.is_shank(), "inside the zone at 100%")
	s.set_result(1.05, inside_at_100)
	assert_almost_eq(s.zone_half_width(), _t.zone_half * lerpf(1.0, _t.overswing_zone_scale, 0.5), EPS,
			"half way to 110%, the zone is half way narrowed")
	s.set_result(1.1, inside_at_100)
	assert_true(s.is_shank(), "the same click shanks at 110%")


# --- accuracy: hook, slice and shank ---

func test_each_ten_percent_off_centre_is_two_degrees() -> void:
	var s := Swing.new(_t)
	s.set_result(1.0, 0.1)
	assert_almost_eq(s.offset_deg(), 2.0, EPS, "10% early turns 2 degrees right (slice)")
	s.set_result(1.0, -0.15)
	assert_almost_eq(s.offset_deg(), -3.0, EPS, "15% late turns 3 degrees left (hook)")
	var model := ShotModel.new()
	var field := HeightField.new(CourseData.create(80, 40, Surface.Type.FAIRWAY, 0), model.params)
	var shot := s.launch(model, field, model.clubs.club("7i"), _yd(Vector2(5, 20)), 10.0)
	assert_almost_eq(shot.heading_deg, 7.0, EPS, "a heading offset at launch (D14)")
	var flat := Vector2(shot.velocity.x, shot.velocity.y)
	assert_almost_eq(rad_to_deg(flat.angle()), 7.0, EPS, "the ball leaves along it")


func test_zone_edges_curve_and_just_outside_shanks() -> void:
	var s := Swing.new(_t)
	var edge := _t.zone_half
	var edge_deg := edge / 0.1 * _t.deg_per_10pct
	for side: float in [1.0, -1.0]:
		s.set_result(1.0, side * edge)
		assert_false(s.is_shank(), "the zone's edge (%+.2f) still counts" % (side * edge))
		assert_almost_eq(s.offset_deg(), side * edge_deg, EPS, "and curves 2 degrees per 10%")
		assert_almost_eq(s.effective_power(), 1.0, EPS, "at full power")
		s.set_result(1.0, side * (edge + 0.005))
		assert_true(s.is_shank(), "just outside it (%+.3f) shanks" % (side * (edge + 0.005)))
		assert_almost_eq(s.offset_deg(), side * _t.shank_deg, EPS, "a shank leaves far off line, toward the miss")
		assert_almost_eq(s.effective_power(), _t.shank_power, EPS, "and short")


func test_zone_edges_through_the_bar() -> void:
	var s := Swing.new(_t)
	_swing_to(s, 1.0, _t.zone_half - 0.001)
	assert_false(s.is_shank(), "a third click just inside the early edge curves")
	s.reset()
	_swing_to(s, 1.0, -_t.zone_half - 0.002)
	assert_true(s.is_shank(), "just past the late edge shanks")
	assert_lt(s.offset_deg(), 0.0, "to the left")


func test_no_third_click_is_a_late_shank() -> void:
	var s := Swing.new(_t)
	s.click()
	s.tick(1.0 / s.rate())
	s.click()
	s.tick(100.0)
	assert_true(s.is_done(), "the bar stops at its left end")
	assert_almost_eq(s.accuracy, _t.bar_min, EPS)
	assert_true(s.is_shank())


# --- bar speed (accessibility) ---

func test_bar_speed_at_its_minimum_and_maximum() -> void:
	var s := Swing.new(_t)
	assert_almost_eq(s.bar_speed, _t.bar_speed_default, EPS, "starts at the default")
	s.bar_speed = _t.bar_speed_min
	assert_almost_eq(s.fill_seconds(), _t.fill_time / _t.bar_speed_min, EPS, "slowest: the bar takes longer")
	s.click()
	s.tick(_t.fill_time)
	assert_almost_eq(s.bar, _t.bar_speed_min, EPS, "1.2 s fills only that share")
	s.reset()
	s.bar_speed = _t.bar_speed_max
	assert_almost_eq(s.fill_seconds(), _t.fill_time / _t.bar_speed_max, EPS, "fastest")
	s.click()
	s.tick(_t.fill_time / _t.bar_speed_max)
	assert_almost_eq(s.bar, 1.0, EPS, "100% in fill_time / speed")
	s.bar_speed = _t.bar_speed_min * 0.1
	assert_almost_eq(s.bar_speed, _t.bar_speed_min, EPS, "clamped to the range's minimum")
	s.bar_speed = _t.bar_speed_max * 10.0
	assert_almost_eq(s.bar_speed, _t.bar_speed_max, EPS, "and its maximum")
	assert_lt(_t.bar_speed_min, 1.0, "the range lets the bar slow down")


# --- the putter ---

func test_putt_speed_maps_the_bar_across_the_putters_range() -> void:
	var putter := ClubSet.load_default().putter()
	var s := Swing.new(_t)
	s.set_result(0.5, 0.0)
	# E3-S51 (D49): along putt_bar_curve, a blend of linear and geometric.
	var lin := lerpf(putter.putt_min_speed, putter.putt_max_speed, 0.5)
	var geo := sqrt(putter.putt_min_speed * putter.putt_max_speed)
	assert_almost_eq(s.putt_speed(putter), lerpf(lin, geo, putter.putt_bar_curve), EPS)
	assert_lt(s.putt_speed(putter), lin, "a short putt gets more of the bar than a linear map gives it")
	s.set_result(0.0, 0.0)
	assert_almost_eq(s.putt_speed(putter), putter.putt_min_speed, EPS)
	s.set_result(1.0, 0.0)
	assert_almost_eq(s.putt_speed(putter), putter.putt_max_speed, EPS)
	s.set_result(1.1, 0.0)
	assert_almost_eq(s.putt_speed(putter), putter.putt_max_speed, EPS, "overswing adds no speed")


func test_the_putter_curve_inverts_and_rises_with_power() -> void:
	var putter := ClubSet.load_default().putter()
	var last := 0.0
	for i in 21:
		var p := i / 20.0
		var v := putter.putt_speed_at(p)
		assert_gt(v, last - EPS, "rises with power at %.2f" % p)
		last = v
		assert_almost_eq(putter.putt_power_for(v), p, 1e-5, "inverts at %.2f" % p)
	assert_eq(putter.putt_power_for(0.0), 0.0, "below the range: 0%")
	assert_eq(putter.putt_power_for(99.0), 1.0, "above it: 100%")
	var linear := putter.duplicate() as Club
	linear.putt_bar_curve = 0.0
	assert_almost_eq(linear.putt_speed_at(0.25), lerpf(linear.putt_min_speed, linear.putt_max_speed, 0.25), EPS,
			"curve 0 is the E2-S7 linear map")


## A perfect putt through the bar, and a predicted putt at 100% (the putter's marker with no
## cup; with a cup it shows the putt nearest the cup, D21, tests/test_shot_prediction.gd).
func _perfect_putt_vs_marker(course: CourseData, from: Vector2, aim_deg: float) -> Array[Vector3]:
	var model := ShotModel.new()
	var field := HeightField.new(course, model.params)
	var putter := model.clubs.putter()
	var s := Swing.new(_t)
	var marker := ShotPrediction.run_launch(course, 1, s.perfect_launch(model, field, putter, from, aim_deg))
	_swing_to(s, 1.0, 0.0)
	var ball := Ball.new(course, 1)
	s.launch(model, field, putter, from, aim_deg).apply(ball)
	ball.run_to_rest()
	return [marker.rest, ball.position]


func test_perfect_putt_rests_within_a_yard_of_the_marker_on_a_flat_green() -> void:
	var course := CourseData.create(30, 12, Surface.Type.GREEN, 0)
	var r := _perfect_putt_vs_marker(course, _yd(Vector2(2, 6)), 0.0)
	assert_gt(r[0].x - _yd(Vector2(2, 6)).x, 20.0, "a full putt runs a long way")
	assert_lt(Vector2(r[0].x - r[1].x, r[0].y - r[1].y).length(), 1.0, "rests within 1 yd of the marker")


func test_perfect_putt_rests_within_a_yard_of_the_marker_on_a_contour() -> void:
	# Across the E1-S9 contour's steps, diagonally, so the break shows.
	var course := GridHeightEvidence.green_contour()
	var model := ShotModel.new()
	var putter := model.clubs.putter()
	var from := _yd(Vector2(4.2, 2.4))
	var r := _perfect_putt_vs_marker(course, from, 35.0)
	assert_lt(Vector2(r[0].x - r[1].x, r[0].y - r[1].y).length(), 1.0, "rests within 1 yd of the marker")
	# The break is real: the putt does not end on its start line.
	var dir := Vector2.RIGHT.rotated(deg_to_rad(35.0))
	var off := Vector2(r[0].x, r[0].y) - from
	assert_gt(absf(off.cross(dir)), 0.1, "the contour bends the putt off its line")
	assert_not_null(putter)


# --- Play-mode input (scenes/swing_control.gd) ---

func _main_on(course: CourseData) -> Main:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(main)
	main.shot_view.set_process(false)
	main.swing_control.set_process(false)
	main.show_course(course)
	main.set_mode(Main.Mode.PLAY)
	return main


func _par3() -> CourseData:
	return CourseSave.load_file("res://courses/example_par3.json")


func test_play_puts_the_ball_on_the_tee_aimed_at_the_cup() -> void:
	var course := _par3()
	var main := _main_on(course)
	var sc := main.swing_control
	var hole: HoleData = course.holes[0]
	assert_eq(sc.ball_at, sc.field.tile_center(hole.tee), "on hole 1's tee")
	var to := sc.field.tile_center(hole.cup) - sc.ball_at
	assert_almost_eq(sc.aim_deg, fposmod(rad_to_deg(to.angle()), 360.0), 0.01, "aimed at the cup")
	assert_true(sc.driver_stroke, "the tee shot may use the driver")
	assert_eq(sc.club.id, "driver", "the longest legal club first")
	assert_true(main.aim_view.visible, "the aim shows")
	assert_true(main.swing_panel.visible, "and the swing panel")
	main.set_mode(Main.Mode.BUILD)
	assert_false(main.aim_view.visible, "neither shows in Build")
	assert_false(main.swing_panel.visible)


func test_club_picker_offers_only_legal_clubs() -> void:
	var course := _par3()
	var main := _main_on(course)
	var sc := main.swing_control
	assert_eq(sc.legal, sc.model.clubs.legal(Surface.Type.TEE, true))
	sc.cycle_club(1)
	assert_eq(sc.club.id, "3w", "down steps to a shorter club")
	sc.cycle_club(-5)
	assert_eq(sc.club.id, "driver", "and stops at the ends")
	# On the green, the putter only.
	var hole: HoleData = course.holes[0]
	sc.place_ball(sc.field.tile_center(hole.cup) - Vector2(4, 0))
	assert_eq(sc.lie_surface(), Surface.Type.GREEN)
	assert_eq(sc.legal.size(), 1)
	assert_true(sc.club.is_putter(), "the putter is picked on the green")
	sc.select_club(sc.model.clubs.club("7i"))
	assert_true(sc.club.is_putter(), "an illegal club cannot be picked")


func test_aim_keys_and_mouse_turn_the_aim() -> void:
	var main := _main_on(_par3())
	var sc := main.swing_control
	var before := sc.aim_deg
	var ev := InputEventAction.new()
	ev.action = SwingControl.AIM_RIGHT
	ev.pressed = true
	sc._unhandled_input(ev)
	assert_almost_eq(sc.aim_deg, fposmod(before + _t.aim_key_step_deg, 360.0), EPS, "right turns by the step")
	ev.action = SwingControl.AIM_LEFT
	sc._unhandled_input(ev)
	sc._unhandled_input(ev)
	assert_almost_eq(sc.aim_deg, fposmod(before - _t.aim_key_step_deg, 360.0), EPS, "left turns back")
	sc.aim_at(sc.ball_at + Vector2(0, 30))
	assert_almost_eq(sc.aim_deg, 90.0, EPS, "the mouse aims at the ground point under it")


func test_the_aim_follows_the_club_and_aim() -> void:
	var main := _main_on(_par3())
	var sc := main.swing_control
	sc._refresh_aim()
	var driver_landing := sc.aim_prediction.landing
	sc.cycle_club(6)
	sc._refresh_aim()
	assert_lt(sc.aim_prediction.landing.distance_to(Vector3(sc.ball_at.x, sc.ball_at.y, 0)),
			driver_landing.distance_to(Vector3(sc.ball_at.x, sc.ball_at.y, 0)),
			"a shorter club moves the marker in")
	assert_eq(main.aim_view.marker_point, sc.aim_prediction.landing, "the marker is the prediction's touchdown")
	assert_gt(main.aim_view.dots.size(), 10, "with a dotted line to it")


func test_the_debug_key_waits_while_a_swing_is_in_progress_or_the_ball_moves() -> void:
	var main := _main_on(_par3())
	var sc := main.swing_control
	assert_true(main.can_fire_debug_shot(), "the debug key works in Play (E2-S8)")
	var ev := InputEventAction.new()
	ev.action = SwingControl.SWING_ACTION
	ev.pressed = true
	sc._unhandled_input(ev)
	assert_true(sc.swing.in_progress(), "the swing has its own input")
	assert_false(main.can_fire_debug_shot(), "not while the swing is in progress")
	sc.advance(1.0 / sc.swing.rate())
	sc._unhandled_input(ev)
	sc.advance(1.0 / sc.swing.rate())
	sc._unhandled_input(ev)
	assert_false(sc.swing.in_progress())
	assert_true(main.shot_view.playing, "the third click strikes the ball")
	assert_false(main.can_fire_debug_shot(), "nor while the struck ball moves")
	var at_strike := main.shot_view.ball
	var key := InputEventAction.new()
	key.action = Main.DEBUG_SHOT_ACTION
	key.pressed = true
	main._unhandled_input(key)
	assert_eq(main.shot_view.ball, at_strike, "the debug shot cannot replace the ball in flight")
	main.shot_view.advance(60.0)
	assert_false(main.shot_view.playing)
	assert_true(main.can_fire_debug_shot(), "the key works again once the ball rests")
	assert_eq(sc.strokes, 1)


func test_a_debug_shot_in_play_leaves_the_swing_ball_and_strokes_alone() -> void:
	var main := _main_on(CourseSave.load_file("res://courses/heights_20x20.json"))
	var sc := main.swing_control
	var before := sc.ball_at
	var strokes := sc.strokes
	main.fire_debug_shot()
	assert_true(main.shot_view.playing, "the debug shot flies")
	main.shot_view.advance(60.0)
	assert_false(main.shot_view.playing, "and rests")
	assert_eq(sc.ball_at, before, "the swing ball has not moved")
	assert_eq(sc.strokes, strokes, "and no stroke is counted")
	# A real swing afterwards still rests the swing ball.
	sc.cycle_club(8)
	sc.press()
	sc.advance(1.0 / sc.swing.rate())
	sc.press()
	sc.advance(1.0 / sc.swing.rate())
	sc.press()
	main.shot_view.advance(60.0)
	var rest := main.shot_view.ball.position
	assert_eq(sc.ball_at, Vector2(rest.x, rest.y), "the swing's own stroke moves it")
	assert_eq(sc.strokes, strokes + 1)


func test_an_aim_key_turn_survives_a_small_mouse_nudge() -> void:
	var main := _main_on(_par3())
	var sc := main.swing_control
	var ev := InputEventAction.new()
	ev.action = SwingControl.AIM_RIGHT
	ev.pressed = true
	sc._unhandled_input(ev)
	var keyed := sc.aim_deg
	var mouse := main.get_viewport().get_mouse_position()
	var nudge := InputEventMouseMotion.new()
	nudge.position = mouse + Vector2(_t.mouse_reaim_px * 0.5, 0.0)
	sc._unhandled_input(nudge)
	assert_almost_eq(sc.aim_deg, keyed, EPS, "a small mouse motion keeps the key aim")
	assert_false(sc.mouse_takes_aim(mouse + Vector2(1, 1)), "inside the threshold the keys keep it")
	assert_true(sc.mouse_takes_aim(mouse + Vector2(_t.mouse_reaim_px + 1.0, 0.0)),
			"past the threshold the mouse takes the aim back")
	assert_true(sc.mouse_takes_aim(mouse), "and keeps it until the next key turn")


func test_a_left_click_swing_does_not_re_aim() -> void:
	var main := _main_on(_par3())
	var sc := main.swing_control
	sc.rotate_aim(7.0)
	var aimed := sc.aim_deg
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(3, 3)
	sc._unhandled_input(click)
	assert_true(sc.swing.in_progress(), "the click starts the swing")
	assert_almost_eq(sc.aim_deg, aimed, EPS, "and keeps the aim")


func test_the_mouse_aims_at_the_drawn_top_of_a_higher_or_lower_tile() -> void:
	# heights_20x20: the ball on the 7-step tee pillar at (15, 4); targets lower and higher.
	var course := CourseSave.load_file("res://courses/heights_20x20.json")
	var main := _main_on(course)
	var sc := main.swing_control
	sc.place_ball(_yd(Vector2(15, 4)))
	var checked := 0
	for target: Vector2i in [Vector2i(5, 4), Vector2i(2, 2), Vector2i(10, 15), Vector2i(4, 10), Vector2i(12, 12)]:
		var h := course.get_height(target.x, target.y)
		# A point of the target's top that still shows (a nearer hill may hide its centre).
		for off: Vector2 in [Vector2.ZERO, Vector2(0.3, 0.3), Vector2(0.3, 0.0), Vector2(0.0, 0.3), Vector2(0.4, 0.4)]:
			var spot := Vector2(target) + off
			var screen := Iso.tile_to_screen(spot, h)
			if TilePicker.pick(course, screen) != target:
				continue
			checked += 1
			var at := sc._ground_under(screen)
			assert_eq(sc.field.tile_at(at.x, at.y), target, "the aim point is on the tile under the cursor %s" % target)
			sc.aim_at(at)
			var want := fposmod(rad_to_deg(((spot + Vector2(0.5, 0.5)) * 5.0 - sc.ball_at).angle()), 360.0)
			assert_almost_eq(sc.aim_deg, want, 0.01, "aimed at the point seen on %s (h%d)" % [target, h])
			break
	assert_gt(checked, 2, "most targets are visible")


func test_next_swing_starts_where_the_ball_rests() -> void:
	var main := _main_on(_par3())
	var sc := main.swing_control
	sc.cycle_club(8)  # 9i
	sc.press()
	sc.advance(1.0 / sc.swing.rate())
	sc.press()
	sc.advance(1.0 / sc.swing.rate())
	sc.press()
	main.shot_view.advance(60.0)
	assert_false(main.shot_view.playing)
	var rest := main.shot_view.ball.position
	assert_eq(sc.ball_at, Vector2(rest.x, rest.y), "the next swing is from the rest point")
	assert_false(sc.driver_stroke, "and is no longer the tee shot")


# --- the aim line, marker and landing cross agree (E2-S7 review) ---

func _perfect_swing(sc: SwingControl) -> void:
	sc.press()
	sc.advance(1.0 / sc.swing.rate())
	sc.press()
	sc.advance(1.0 / sc.swing.rate())
	sc.press()


func test_a_perfect_swing_lands_its_cross_on_the_aim_ring() -> void:
	var course := CourseSave.load_file("res://courses/heights_20x20.json")
	var main := _main_on(course)
	var sc := main.swing_control
	sc.place_ball(_yd(Vector2(15, 4)))
	var checked := 0
	for club_id: String in ["7i", "9i", "sw"]:
		for aim: float in [150.0, 180.0, 200.0, 225.0]:
			sc.place_ball(_yd(Vector2(15, 4)))
			sc.select_club(sc.model.clubs.club(club_id))
			sc.rotate_aim(aim - sc.aim_deg)
			sc._refresh_aim()
			var ring := main.aim_view.marker_screen
			_perfect_swing(sc)
			assert_true(main.shot_view.playing)
			assert_almost_eq(main.shot_view.marker_screen().distance_to(ring), 0.0, 0.01,
					"%s at %d: the cross sits on the ring" % [club_id, aim])
			main.shot_view.advance(60.0)
			checked += 1
	assert_eq(checked, 12)


func test_a_flight_line_starts_at_the_ball_from_a_raised_tee() -> void:
	var main := _main_on(CourseSave.load_file("res://courses/heights_20x20.json"))
	var sc := main.swing_control
	sc.place_ball(_yd(Vector2(15, 4)))
	sc.select_club(sc.model.clubs.club("sw"))
	sc.rotate_aim(180.0 - sc.aim_deg)
	sc._refresh_aim()
	var view := main.aim_view
	var ball := main.shot_view.ball_screen()
	assert_gt(view.dots.size(), 10)
	var spacing_px := view.dots[0].distance_to(view.dots[1])
	assert_lt(view.dots[0].distance_to(ball), spacing_px * 1.5, "the first dot is next to the ball")
	# The dots are one straight screen segment from the ball to the marker.
	for d in view.dots:
		var off := Geometry2D.get_closest_point_to_segment(d, ball, view.marker_screen).distance_to(d)
		assert_lt(off, 0.01, "on the chord")


func test_a_putt_line_follows_the_ground_without_tile_edge_jumps() -> void:
	# The E1-S9 green contour (one step per tile): a putt across the slope.
	var course := GridHeightEvidence.green_contour()
	var main := _main_on(course)
	var sc := main.swing_control
	sc.place_ball(_yd(Vector2(4.5, 5.5)))
	assert_true(sc.club.is_putter())
	sc.rotate_aim(-25.0 - sc.aim_deg)
	sc._refresh_aim()
	sc.settle_aim()
	var view := main.aim_view
	var dots := view.dots
	assert_gt(dots.size(), 4)
	assert_lt(_max_turn(dots), Iso.STEP_PX * 0.5, "the dots run smoothly: no tier jumps")
	# The same roll sampled on the ground (E3-S59: each dot is there) and on the tile tops (D17's
	# old rule), for comparison.
	var path := sc.aim_prediction.path
	var tops := PackedVector2Array()
	var carry := view.dot_spacing_yd
	for i in range(1, path.size()):
		var a := Vector2(path[i - 1].x, path[i - 1].y)
		var b := Vector2(path[i].x, path[i].y)
		var seg := a.distance_to(b)
		while carry <= seg:
			var q := a.lerp(b, carry / seg)
			assert_almost_eq(dots[tops.size()], sc.field.ground_screen(Vector3(q.x, q.y, 0.0)), Vector2.ONE * 0.001,
					"dot %d on the ground" % tops.size())
			var cell := sc.field.tile_at(q.x, q.y)
			var iso := sc.field.iso_point(Vector3(q.x, q.y, 0.0))
			tops.append(Iso.tile_to_screen(Vector2(iso.x, iso.y), course.get_height(cell.x, cell.y)))
			carry += view.dot_spacing_yd
		carry -= seg
	assert_eq(tops.size(), dots.size())
	assert_gt(_max_turn(tops), Iso.STEP_PX * 0.5, "where tile-top dots would jump a tier")


## The largest change between consecutive dot-to-dot steps, screen px.
func _max_turn(dots: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(2, dots.size()):
		var step_a := dots[i - 1] - dots[i - 2]
		var step_b := dots[i] - dots[i - 1]
		worst = maxf(worst, step_a.distance_to(step_b))
	return worst


# --- the putter's solve over frames (E6-S12) ---

## A green rising two steps per tile along +x from tile 10, with hole 1's cup on the bank
## at `cup` and the ball at `at` below it. From the defaults no putt rests near the cup: the
## cold solve pins, scans and refines: 14 putts, about 3,500 Ball ticks (some 130 ms).
func _steep_bank_main(cup: Vector2i = Vector2i(12, 6), at: Vector2 = Vector2(42.5, 32.5)) -> Main:
	var course := CourseData.create(30, 12, Surface.Type.GREEN, 0)
	for y in 12:
		for x in 30:
			course.set_tile(x, y, clampi((x - 10) * 2, 0, 7), Surface.Type.GREEN)
	course.set_holes([HoleData.new(1, 3, Vector2i(1, 6), cup, true)] as Array[HoleData])
	var main := _main_on(course)
	var sc := main.swing_control
	sc.place_ball(at)
	sc.aim_at(sc.field.tile_center(cup))
	return main


## E6-S12 Accept: no aim update takes more than one frame. Each frame steps the solve by at
## most putt_aim_frame_ticks Ball ticks and putt_aim_frame_usec; the marker shows a first
## answer, then the refined putt, the same one the solve at once finds. Prints the worst and
## the mean update (E6-S12 review: the worst varies with the machine's load).
func test_the_putter_solve_spreads_over_frames_within_a_frame_budget() -> void:
	if BestTime.later(self):
		return
	var main := _steep_bank_main()
	var sc := main.swing_control
	var budget := sc.tuning.putt_aim_frame_ticks
	assert_gt(budget, 0, "the cap lives in golf/swing_tuning.tres")
	assert_gt(sc.tuning.putt_aim_frame_usec, 0, "and its time cap")
	var t0 := Time.get_ticks_usec()
	sc._process(1.0 / 60.0)  # the aim is dirty: this frame starts the solve
	var worst_usec := Time.get_ticks_usec() - t0
	var total_usec := worst_usec
	assert_lte(sc.aim_putt.ticks, budget, "the first frame stays inside the budget")
	var frames := 1
	var first_answer := -1
	while sc.is_aim_solving() and frames < 10000:
		var before := sc.aim_putt.ticks
		var t := Time.get_ticks_usec()
		sc._process(1.0 / 60.0)
		var took := Time.get_ticks_usec() - t
		worst_usec = maxi(worst_usec, took)
		total_usec += took
		assert_lte(sc.aim_putt.ticks - before, budget, "frame %d: inside the budget" % frames)
		if first_answer < 0 and sc.aim_prediction != null:
			first_answer = frames
		frames += 1
	gut.p("putter solve over frames: %d runs, %d ticks, %d frames (first answer at frame %d), worst update %.1f ms, mean %.1f ms" % [
			sc.aim_putt.runs, sc.aim_putt.ticks, frames, first_answer, worst_usec / 1000.0,
			total_usec / 1000.0 / frames])
	assert_lt(float(total_usec) / frames, sc.tuning.putt_aim_frame_usec * 1.5,
			"a frame's aim work stays near its time cap on average" + BestTime.load_note())
	assert_false(sc.is_aim_solving(), "the solve ends")
	assert_true(sc.aim_putt.scanned, "this one needs the scan")
	assert_gt(frames, 2, "a cold solve on a steep bank needs several frames")
	assert_between(first_answer, 0, frames - 2, "a first answer shows before the solve ends")
	assert_lt(worst_usec, 16667, "no aim update takes more than a 60 Hz frame" + BestTime.load_note())
	var whole := PuttAim.solve(sc.course, sc.field, sc.model, sc.tuning, sc.ball_at, sc.aim_deg,
			sc.cup_tile(), sc.next_seed())
	assert_eq(sc.aim_power, whole.power, "the same putt as the solve at once")
	assert_eq(sc.aim_prediction.rest, whole.prediction.rest)
	assert_eq(main.aim_view.marker_point, whole.prediction.rest, "and the marker shows it")


## Turning the aim mid-solve starts again from there, once the running solve's first putt
## has rested (E6-S12 review); striking stops it, so the struck
## ball's flight is never overdrawn by a late marker.
func test_the_putter_solve_restarts_on_a_turn_and_stops_on_a_strike() -> void:
	var main := _steep_bank_main()
	var sc := main.swing_control
	sc._process(1.0 / 60.0)
	var first := sc.aim_putt
	assert_true(sc.is_aim_solving())
	sc.rotate_aim(1.0)
	var waited := 0
	while sc.aim_putt == first and waited < 30:
		sc._process(1.0 / 60.0)
		waited += 1
	assert_ne(sc.aim_putt, first, "a new solve for the new aim")
	assert_not_null(first.prediction, "once the old aim's first putt had rested")
	assert_almost_eq(sc.aim_putt.get_aim_deg(), sc.aim_deg, 1e-4, "along the new aim")
	assert_true(sc.is_aim_solving())
	sc.press()
	sc.advance(0.3 / sc.swing.rate())
	sc.press()
	sc.advance(0.3 / sc.swing.rate())
	sc.press()
	assert_true(main.shot_view.playing, "struck")
	sc._process(1.0 / 60.0)
	assert_false(sc.is_aim_solving(), "a moving ball stops the solve")
	assert_false(main.aim_view.visible, "no marker over the moving ball")


## E6-S12 review: the frame a ball comes to rest spends one budget, not two. ShotView's
## came_to_rest only starts the new solve; that frame's `_process` steps it.
func test_the_frame_a_ball_rests_spends_one_aim_budget() -> void:
	var main := _steep_bank_main()
	var sc := main.swing_control
	sc.settle_aim()
	_perfect_swing(sc)
	assert_true(main.shot_view.playing, "struck")
	var i := 0
	while main.shot_view.playing and i < 100000:
		main.shot_view.advance(1.0 / 60.0)
		i += 1
	assert_false(main.shot_view.playing, "the putt came to rest")
	if sc.is_finished():
		pass_test("holed: no next putt to aim")
		return
	assert_true(sc.is_aim_solving(), "came_to_rest started a solve from the new spot")
	assert_eq(sc.aim_putt.ticks, 0, "and stepped none of it")
	sc._process(1.0 / 60.0)
	assert_lte(sc.aim_putt.ticks, sc.tuning.putt_aim_frame_ticks, "one budget in that frame")


## E6-S12 review: a sweep of the aim on a steep downhill putt. Each frame turns the aim; a
## turned aim waits for the running solve's first putt, so the marker keeps up: it moves at
## least every few frames and the putt it shows was aimed close to the current aim. (Before,
## each turn threw the first putt away mid-roll and the marker froze for the whole sweep,
## up to 30 degrees behind.)
## E6-S22: each frame spends the tick budget alone (the time cap lifted on a copy of the
## tuning), so the count does not hang on how busy the machine is: under parallel test jobs the
## 6,000 us cap cut frames short and the lag reached 14 degrees. The time cap has its own test
## above. E6-S30: so this test is not a timed one; with every hardware thread kept busy it
## measured the same lags (8.0 and 6.0 degrees) as on an idle machine.
func test_a_sweep_of_the_aim_on_a_steep_bank_keeps_the_marker_up() -> void:
	for case: Array in [[Vector2i(9, 6), Vector2(92.5, 31.0)], [Vector2i(13, 6), Vector2(80.0, 22.5)]]:
		var main := _steep_bank_main(case[0], case[1])
		var sc := main.swing_control
		sc.tuning = sc.tuning.duplicate() as SwingTuning
		sc.tuning.putt_aim_frame_usec = 1000000000
		sc._process(1.0 / 60.0)
		sc.settle_aim()
		var label := "cup %s from %s" % [case[0], case[1]]
		var shown := sc.aim_prediction
		var since := 0
		var longest := 0
		var moves := 0
		var worst_lag := 0.0
		for f in 60:
			sc.rotate_aim(1.0)
			sc._process(1.0 / 60.0)
			if sc.aim_prediction != shown:
				shown = sc.aim_prediction
				moves += 1
				since = 0
			else:
				since += 1
				longest = maxi(longest, since)
			worst_lag = maxf(worst_lag, absf(angle_difference(deg_to_rad(sc.aim_prediction_deg),
					deg_to_rad(sc.aim_deg))))
		gut.p("%s, sweep 1 deg a frame: marker moved on %d of 60 frames, longest still %d, worst lag %.1f deg" % [
				label, moves, longest, rad_to_deg(worst_lag)])
		assert_gte(moves, 6, "%s: the marker moves while the aim sweeps" % label)
		assert_lte(longest, 10, "%s: never still for more than 10 frames of turning" % label)
		assert_lte(rad_to_deg(worst_lag), 12.0, "%s: the shown putt trails the aim by little" % label)
