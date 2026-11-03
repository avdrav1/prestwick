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
