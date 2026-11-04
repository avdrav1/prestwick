extends GutTest
## E2-S7 (D17): on the ground the ball and its shadow are drawn on the top of the tile under
## them, never at the bilinear physics height, so a ball the green holds partway up a
## one-step slope sits on a tile top, not on the riser.

const EPS := 0.001


func _yd(tile: Vector2) -> Vector2:
	return (tile + Vector2(0.5, 0.5)) * 5.0


func _view() -> ShotView:
	var view := ShotView.new()
	add_child_autofree(view)
	view.set_process(false)
	return view


## Projected screen y of the top of the tile under the ball.
func _top_y(view: ShotView) -> float:
	var p := view.ball.position
	var cell := view.ball.field.tile_at(p.x, p.y)
	var iso := view.ball.field.iso_point(p)
	return Iso.tile_to_screen(Vector2(iso.x, iso.y), view.ball.field.course.get_height(cell.x, cell.y)).y


func test_ball_resting_on_a_one_step_green_slope_is_drawn_on_its_tile_top() -> void:
	# The E1-S12 case: an uphill putt at 6 yd/s from the contour's front tier stops short
	# partway up a one-step slope, and the green holds it there (D7).
	var course := GridHeightEvidence.green_contour()
	var model := ShotModel.new()
	var field := HeightField.new(course, model.params)
	var shot := model.putt(field, model.clubs.putter(), 6.0, _yd(Vector2(4.5, 5.5)), 0.0)
	var view := _view()
	view.fire_launch(course, shot, 1)
	view.advance(30.0)
	assert_false(view.playing, "the putt came to rest")
	var p := view.ball.position
	assert_between(p.x, 27.5, 32.5, "on the step's slope")
	var physics_y := Iso.point_to_screen(field.iso_point(p)).y
	assert_gt(absf(physics_y - _top_y(view)), 2.0, "where the physics height is off the tile top")
	assert_almost_eq(view.ball_screen().y, _top_y(view), EPS, "the ball is drawn on the tile top")
	assert_almost_eq(view.shadow_screen().y, _top_y(view), EPS, "and so is its shadow")
	assert_almost_eq(view.ball_screen().x, Iso.point_to_screen(field.iso_point(p)).x, EPS,
			"straight above or below its true point")


func test_a_ball_set_at_rest_is_drawn_on_its_tile_top() -> void:
	var course := GridHeightEvidence.green_contour()
	var view := _view()
	for x: float in [21.0, 24.0, 27.4, 27.6, 31.0]:
		view.show_at_rest(course, Vector2(x, 27.5))
		assert_true(view.visible)
		assert_false(view.playing)
		assert_almost_eq(view.ball_screen().y, _top_y(view), EPS, "x %.1f: on the tile top" % x)


func test_a_rolling_ball_steps_16_px_at_a_riser() -> void:
	# A putt down the contour (mirrored, so it runs downhill along +x) crosses risers; each
	# tile edge it crosses moves the drawn ball by a whole number of steps, never between.
	var course := GridHeightEvidence.green_contour(true)
	var model := ShotModel.new()
	var field := HeightField.new(course, model.params)
	var shot := model.putt(field, model.clubs.putter(), 8.0, _yd(Vector2(4.2, 5.5)), 0.0)
	var view := _view()
	view.fire_launch(course, shot, 1)
	var cells := {}
	while view.playing:
		view.advance(1.0 / 60.0)
		assert_almost_eq(view.ball_screen().y, _top_y(view), EPS, "rolling, on the tile top")
		cells[view.ball.field.tile_at(view.ball.position.x, view.ball.position.y)] = true
	assert_gt(cells.size(), 2, "it crossed tiles")


## E2-S13: a fairway strip along +x with water from tile 20 to 24 on every row.
func _water_strip() -> CourseData:
	var c := CourseData.create(40, 11, Surface.Type.FAIRWAY, 0)
	for y: int in 11:
		for x: int in range(20, 25):
			c.set_tile(x, y, 0, Surface.Type.WATER)
	return c


func test_a_water_ball_is_shown_where_it_went_in_before_the_drop() -> void:
	var course := _water_strip()
	var params := BallParams.load_default()
	var speed := sqrt(100.0 * params.gravity / sin(deg_to_rad(60.0)))
	var view := _view()
	var rests: Array[Vector3] = []
	view.came_to_rest.connect(func(at: Vector3) -> void: rests.append(at))
	view.fire(course, Vector3(10, 27.5, 0), Ball.launch_velocity(speed, 30.0, 0.0), 7)
	var dt := 1.0 / 60.0
	var guard := 0
	while not view.ball.is_at_rest() and guard < 6000:
		view.advance(dt)
		guard += 1
	var ball := view.ball
	assert_eq(ball.hazard, Ball.Hazard.WATER, "the carry finds the water")
	assert_ne(ball.drop_point, ball.hazard_position, "the drop is away from where it went in")
	var hold := view.tuning.hazard_show_time
	assert_gt(hold, 0.0)
	assert_true(view.playing, "the shot is not over the tick the ball is dropped")
	assert_true(rests.is_empty(), "no rest yet")
	assert_eq(view.drawn_position(), ball.hazard_position, "drawn where it went in")
	assert_almost_eq(view.ball_screen(), ball.field.tile_top_screen(ball.hazard_position),
			Vector2(EPS, EPS), "on the water's tile top")
	assert_false(view.marker.visible, "the landing cross does not cover the ball in the water")
	assert_true(view.hazard_cue.visible, "a hazard cue marks the water stroke")
	assert_eq(view.hazard_cue.position, view.sprite.position, "the cue sorts with the ball")
	assert_lt(view.hazard_cue.get_index(), view.sprite.get_index(), "the ball draws over its cue")
	# Held for the whole show time, then at the drop.
	var held := dt
	while held < hold - dt * 1.5:
		view.advance(dt)
		held += dt
		assert_true(view.playing, "%.2f s after the splash: still shown in the water" % held)
		assert_eq(view.drawn_position(), ball.hazard_position)
	view.advance(dt * 3.0)
	assert_false(view.playing, "the shot ends once the show time is up")
	assert_eq(rests, [ball.drop_point], "came_to_rest reports the drop, once")
	assert_eq(view.drawn_position(), ball.drop_point, "now drawn at the drop")
	assert_false(view.hazard_cue.visible, "the cue goes with the hold")
	assert_false(view.marker.visible,
			"E6-S13: the landing cross stays hidden after the drop, not back in the water")
	view.advance(5.0)
	assert_false(view.marker.visible, "until the next shot")
	view.fire(course, ball.drop_point, Ball.launch_velocity(10.0, 30.0, 180.0), 3)
	assert_true(view.marker.visible, "the next shot shows its own landing cross")
	assert_almost_eq(view.ball_screen(), ball.field.tile_top_screen(ball.drop_point),
			Vector2(EPS, EPS), "on the drop tile's top")


func test_a_dry_ball_rests_at_once() -> void:
	var course := CourseData.create(40, 11, Surface.Type.FAIRWAY, 0)
	var view := _view()
	var rests: Array[Vector3] = []
	view.came_to_rest.connect(func(at: Vector3) -> void: rests.append(at))
	view.fire(course, Vector3(10, 27.5, 0), Ball.launch_velocity(20.0, 30.0, 0.0), 7)
	while view.playing:
		view.advance(1.0 / 60.0)
		if view.ball.is_at_rest():
			break
	assert_false(view.playing, "no hold without a hazard")
	assert_false(view.hazard_cue.visible, "no hazard cue on a dry ball")
	assert_eq(rests, [view.ball.position])


# --- E6-S16: the land line through the shot, and the hazard cues by shape ---

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


## The E6-S13 OB fixture's course in Play: a par 3 over owned land, the parcel behind the
## green unowned, a long 3-iron struck at full power.
func _ob_main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.shot_view.set_process(false)
	m.swing_control.set_process(false)
	m.camera.set_process(false)
	m.show_course(HazardShot.long_par3())
	m.mode_button.pressed.emit()
	return m


func test_the_land_line_stays_drawn_through_the_flight_and_the_ob_hold() -> void:
	var m := _ob_main()
	var sc := m.swing_control
	var aim := m.aim_view
	assert_true(aim.visible, "the aim shows before the shot")
	var line := aim.land_line.duplicate()
	assert_gt(line.size(), 0, "with the land line")
	var plan := ScriptedRound.Plan.new()
	plan.club = sc.model.clubs.club("3i")
	plan.aim_deg = sc.aim_deg
	plan.ticks = ScriptedRound.ticks_for(sc, 1.0)
	ScriptedRound.swing(sc, plan)
	var view := m.shot_view
	assert_true(view.playing, "struck")
	assert_null(aim.prediction, "the aim's dots and marker go at the strike")
	assert_eq(aim.dots.size(), 0)
	var flying := 0
	var held := 0
	while view.playing:
		view.advance(1.0 / 60.0)
		if not view.playing:
			break
		if view.ball.state == Ball.State.FLYING:
			flying += 1
		if view.showing_hazard():
			held += 1
		assert_true(aim.visible, "the line shows at tick %d" % view.ball.steps)
		assert_eq(aim.land_line, line, "the same line, every edge")
	assert_gt(flying, 30, "checked in flight")
	assert_gt(held, 10, "and through the hold")
	assert_eq(view.ball.hazard, Ball.Hazard.OB, "the 3-iron goes long onto unowned land")
	m.mode_button.pressed.emit()
	assert_false(aim.visible, "Build hides it")
	assert_eq(aim.land_line.size(), 0)


func test_a_fully_owned_course_shows_nothing_in_flight() -> void:
	var course := CourseData.create(40, 11, Surface.Type.FAIRWAY, 0)
	var field := HeightField.new(course, BallParams.load_default())
	var aim := AimView.new()
	add_child_autofree(aim)
	var start := Vector3(10, 27.5, 0)
	aim.show_prediction(field, ShotPrediction.run(course, 7, start,
			Ball.launch_velocity(20.0, 30.0, 0.0)), false, start)
	aim.clear_aim()
	assert_false(aim.visible, "no line on a fully owned course, so nothing in flight")
	assert_null(aim.prediction)


func test_the_ob_cue_keeps_a_fixed_screen_size() -> void:
	for s: float in [0.5, 1.0, 2.0]:
		assert_almost_eq(HazardCue.screen_k(s), 1.0 / s, EPS, "k at %.1fx" % s)
	var view := _view()
	assert_almost_eq(view.cue_k(), 1.0, EPS, "1x with no camera")


func test_the_ob_slash_runs_past_the_ring_and_over_the_ball() -> void:
	var tuning := ShotViewTuning.load_default()
	assert_gt(tuning.ob_slash_reach, 1.0, "past the ring")
	var at := Vector2(100, 50)
	var r := 14.0
	var slash := HazardCue.ob_slash(at, r, tuning.ob_slash_reach)
	assert_eq(slash.size(), 2)
	for p in slash:
		var e := Vector2((p - at).x, (p - at).y * 2.0)  # back to the ring's circle
		assert_gt(e.length(), r + 2.0, "each end past the ring")
	assert_almost_eq((slash[0] + slash[1]) * 0.5, at, Vector2(EPS, EPS), "through the ball")
	# The cue is in two pieces: the ring under the ball and the slash over it.
	var view := _view()
	assert_lt(view.hazard_cue.get_index(), view.sprite.get_index(), "ring under the ball")
	assert_gt(view.hazard_slash.get_index(), view.sprite.get_index(), "slash over the ball")


func test_the_ob_slash_leaves_the_ball_clear_at_every_zoom() -> void:
	var view := _view()
	var at := Vector2(100, 50)
	for s: float in [0.5, 1.0, 2.0]:
		var k := HazardCue.screen_k(s)
		var r := view.hazard_cue_radius * k
		var reach := view.ob_slash_reach_at(k)
		var gap := view.ob_slash_gap(k)
		var whole := HazardCue.ob_slash(at, r, reach)
		var pieces := HazardCue.ob_slash_pieces(at, r, reach, gap)
		assert_eq(pieces.size(), 4)
		assert_almost_eq(pieces[0], whole[0], Vector2(EPS, EPS), "outer end kept at %.1fx" % s)
		assert_almost_eq(pieces[3], whole[1], Vector2(EPS, EPS), "outer end kept at %.1fx" % s)
		# The ball and its outline span ball_draw_radius + ball_outline_width canvas units;
		# the slash's ink (its inner ends) stops at least 1 screen px (k) past that.
		var ball_span := view.ball_draw_radius(k) + view.ball_outline_width(k)
		for p: Vector2 in [pieces[1], pieces[2]]:
			assert_gt((p - at).length() * s, ball_span * s + 0.99,
					"the slash stops clear of the ball at %.1fx" % s)
		# Each piece still has length, so the slash reads on both sides of the ball.
		assert_gt((pieces[1] - pieces[0]).length() * s, 4.0, "lower piece at %.1fx" % s)
		assert_gt((pieces[3] - pieces[2]).length() * s, 4.0, "upper piece at %.1fx" % s)
	# Gap 0 is one unbroken slash (the aim marker's preview has no ball under it).
	var one := HazardCue.ob_slash_pieces(at, 10.0, 1.8, 0.0)
	assert_almost_eq(one[1], at, Vector2(EPS, EPS))
	assert_almost_eq(one[2], at, Vector2(EPS, EPS))


## Screen length of one OB slash piece (outer end to the gap round the ball) at view scale s.
func _slash_piece_screen(view: ShotView, s: float) -> float:
	var k := HazardCue.screen_k(s)
	var pieces := HazardCue.ob_slash_pieces(Vector2.ZERO, view.hazard_cue_radius * k,
			view.ob_slash_reach_at(k), view.ob_slash_gap(k))
	return minf((pieces[1] - pieces[0]).length(), (pieces[3] - pieces[2]).length()) * s


func test_the_ball_keeps_a_minimum_screen_size_when_zoomed_out() -> void:
	# E6-S27: at 0.5x the ball no longer shrinks to about 2 px; it draws at least
	# ShotViewTuning.ball_min_screen_radius on screen, and it still scales with the map above.
	var tuning := ShotViewTuning.load_default()
	assert_gt(tuning.ball_min_screen_radius, 2.0, "bigger than the 0.5x ball before E6-S27")
	var view := _view()
	var radius_1x := view.ball_draw_radius(1.0)
	assert_almost_eq(radius_1x, view.ball_radius, EPS, "1x is unchanged")
	for s: float in [0.5, 1.0, 2.0]:
		var k := HazardCue.screen_k(s)
		var on_screen := view.ball_draw_radius(k) * s
		assert_gte(on_screen, tuning.ball_min_screen_radius - EPS, "ball at %.1fx" % s)
		assert_gte(view.ball_outline_width(k) * s, 1.0 - EPS, "outline at %.1fx" % s)
		assert_gte(on_screen, minf(view.ball_radius * s, view.ball_radius) - EPS,
				"never smaller than the map would draw it at %.1fx" % s)
	assert_almost_eq(view.ball_draw_radius(HazardCue.screen_k(0.5)) * 0.5,
			tuning.ball_min_screen_radius, EPS, "0.5x is held at the minimum")
	assert_almost_eq(view.ball_draw_radius(HazardCue.screen_k(2.0)) * 2.0,
			view.ball_radius * 2.0, EPS, "2x still grows with the map")


func test_the_ob_slash_at_2x_is_as_long_on_screen_as_at_1x() -> void:
	# E6-S27: at 2x the ball fills more of the fixed-size ring, so the slash reaches further
	# out and each piece stays at least its 1x length on screen; at 0.5x too.
	var view := _view()
	var at_1x := _slash_piece_screen(view, 1.0)
	assert_gt(at_1x, 12.0, "the 1x piece is longer than E6-S16's 2x piece")
	assert_gte(_slash_piece_screen(view, 2.0), at_1x - EPS, "2x piece")
	assert_gte(_slash_piece_screen(view, 0.5), at_1x - EPS, "0.5x piece")
	var tuning := ShotViewTuning.load_default()
	assert_almost_eq(view.ob_slash_reach_at(1.0), tuning.ob_slash_reach, EPS, "1x reach kept")
	assert_gt(view.ob_slash_reach_at(HazardCue.screen_k(2.0)), tuning.ob_slash_reach,
			"2x reaches further past the ring")


func test_ob_water_and_blocked_differ_by_shape() -> void:
	var at := Vector2.ZERO
	var r := 10.0
	# OB: one ring struck through by a slash past it (above). Blocked is a filled octagon with a bar, not a slashed ring.
	var octagon := HazardCue.blocked_outline(at, r)
	assert_eq(octagon.size(), 8)
	var bar := HazardCue.blocked_bar(at, r)
	assert_almost_eq(bar[0].y, bar[1].y, EPS, "the bar is level")
	# Water: two rings, no slash.
	assert_eq(HazardCue.water_rings(r).size(), 2)
