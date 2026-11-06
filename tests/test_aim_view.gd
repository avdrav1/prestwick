extends GutTest
## E3-S59 (D50): the aim marker, its hazard cue and the putt's dots are drawn on the ground the
## course view draws (HeightField.ground_screen: height_at, water flat at its level), not on
## the tile top (D17). The aim's other rules are in tests/test_swing.gd and test_ball_land.gd.

const EPS := 0.001

var params := BallParams.load_default()


## A long slope along +x: column x stands at x / 3 steps (a rise every third tile), fairway, with
## a pond at its level across columns 30 to 33.
func _slope() -> CourseData:
	var c := CourseData.create(48, 9, Surface.Type.FAIRWAY, 0)
	for y: int in c.height:
		for x: int in c.width:
			var h: int = mini(x / 3, CourseData.MAX_HEIGHT)
			c.set_tile(x, y, h, Surface.Type.WATER if x >= 30 and x <= 33 else Surface.Type.FAIRWAY)
	return c


func _carry(carry: float, launch_deg: float) -> Vector3:
	var speed := sqrt(carry * params.gravity / sin(deg_to_rad(2.0 * launch_deg)))
	return Ball.launch_velocity(speed, launch_deg, 0.0)


## Screen point of the ground (height_at) at `p` (yards).
func _ground(field: HeightField, p: Vector3) -> Vector2:
	return Iso.point_to_screen(field.iso_point(Vector3(p.x, p.y, field.height_at(p.x, p.y))))


func test_the_aim_marker_sits_on_the_slope_at_height_at() -> void:
	var c := _slope()
	var field := HeightField.new(c, params)
	var view := AimView.new()
	add_child_autofree(view)
	var start := Vector3(10, 22.5, field.height_at(10, 22.5))
	var off_top := 0
	for carry: float in [40.0, 55.0, 70.0, 85.0]:
		var p := ShotPrediction.run(c, 7, start, _carry(carry, 30.0))
		if p.penalty_strokes > 0:
			continue
		view.show_prediction(field, p, false, start)
		assert_almost_eq(view.marker_screen, _ground(field, p.landing), Vector2(EPS, EPS), "carry %d: on the ground" % carry)
		var cell := field.tile_at(p.landing.x, p.landing.y)
		var iso := field.iso_point(p.landing)
		var top := Iso.tile_to_screen(Vector2(iso.x, iso.y), c.get_height(cell.x, cell.y))
		if absf(top.y - view.marker_screen.y) > 1.0:
			off_top += 1
	assert_gt(off_top, 0, "somewhere the old tile top would have put it off the slope")


func test_a_water_cue_sits_on_the_water_at_its_level() -> void:
	var c := _slope()
	var field := HeightField.new(c, params)
	var view := AimView.new()
	add_child_autofree(view)
	var start := Vector3(100, 22.5, field.height_at(100, 22.5))
	var p := ShotPrediction.run(c, 7, start, _carry(65.0, 35.0))
	assert_eq(p.hazard, Ball.Hazard.WATER, "the carry finds the pond")
	view.show_prediction(field, p, false, start)
	var iso := field.iso_point(p.hazard_position)
	var level: float = c.get_height(31, 4)
	assert_almost_eq(view.hazard_screen, Iso.tile_to_screen(Vector2(iso.x, iso.y), level), Vector2(EPS, EPS),
			"the water lies flat at its level")


func test_a_putts_marker_lies_on_the_ground() -> void:
	var c := _slope()
	for y: int in c.height:
		for x: int in range(0, 12):
			c.set_tile(x, y, mini(x / 3, 7), Surface.Type.GREEN)
	var field := HeightField.new(c, params)
	var view := AimView.new()
	add_child_autofree(view)
	var start := Vector3(25, 22.5, field.height_at(25, 22.5))
	var model := ShotModel.new()
	var shot := model.putt(field, model.clubs.putter(), 9.0, Vector2(start.x, start.y), 160.0)
	var p := ShotPrediction.run_launch(c, 1, shot)
	view.show_prediction(field, p, true, start)
	# Each dot is on the ground at its point of the roll (tests/test_swing.gd samples them).
	assert_gt(view.dots.size(), 0)
	assert_almost_eq(view.marker_screen, _ground(field, p.rest), Vector2(EPS, EPS), "the marker at the rest point")
