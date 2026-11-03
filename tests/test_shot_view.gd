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
