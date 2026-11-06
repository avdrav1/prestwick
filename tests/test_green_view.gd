extends GutTest
## E3-S52 (D48): the overhead green view. It opens while the player's ball rests on a green in
## Play, draws the green and its fringe top-down, and shows the AimView's putt (the same
## PuttAim solve) in its own space.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


## The main scene in Play on GreenViewShot's `kind` green, the ball on hole 1's tee.
func _main(kind: String = "flat") -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(GreenViewShot.course(kind).course)
	m.set_mode(Main.Mode.PLAY)
	m.swing_control.set_process(false)
	return m


## Rests the ball at `at` (yards), aims it at `cup` and settles the putt's solve, then lets
## the green view follow, as Main._process does each frame.
func _rest(m: Main, at: Vector2, cup: Vector2i) -> void:
	var sc := m.swing_control
	sc.place_ball(at)
	sc.aim_at(sc.field.tile_center(cup))
	sc._refresh_aim()
	sc.settle_aim()
	m.green_view.follow(m.free_view_rect())


func test_opens_on_a_green_rest_and_not_off_it() -> void:
	var m := _main()
	var gv := m.green_view
	gv.follow(m.free_view_rect())
	assert_ne(m.swing_control.lie_surface(), Surface.Type.GREEN, "the ball starts on the tee")
	assert_false(gv.is_open, "closed off the green")
	assert_false(gv.visible)
	var made := GreenViewShot.course("flat")
	_rest(m, made.ball, made.cup)
	assert_true(gv.is_open, "open with the ball at rest on the green")
	assert_true(gv.visible)
	# Centred in the free view, inside it.
	var free := m.free_view_rect()
	assert_almost_eq(gv.get_rect().get_center().x, free.get_center().x, 1.0)
	assert_almost_eq(gv.get_rect().get_center().y, free.get_center().y, 1.0)
	assert_true(free.encloses(gv.get_rect()), "the panel sits in the free view")
	assert_gte(gv.tile_px, gv.tuning.min_tile_px)
	# Off the green (the fringe's rough): closed again.
	_rest(m, Vector2(16.5, 9.5) * 5.0, made.cup)
	assert_eq(m.swing_control.lie_surface(), Surface.Type.ROUGH)
	assert_false(gv.is_open, "closed once the ball rests off the green")
	assert_false(gv.visible)


func test_closes_when_the_hole_ends_and_in_build() -> void:
	var m := _main()
	var gv := m.green_view
	var made := GreenViewShot.course("flat")
	_rest(m, made.ball, made.cup)
	assert_true(gv.is_open)
	m.swing_control.score.holed = true
	gv.follow(m.free_view_rect())
	assert_false(gv.is_open, "a finished hole closes it")
	m.swing_control.score.holed = false
	gv.follow(m.free_view_rect())
	assert_true(gv.is_open)
	m.set_mode(Main.Mode.BUILD)
	assert_false(gv.is_open, "Build closes it")
	assert_false(gv.visible)


func test_the_toggle_key_hides_and_shows_it() -> void:
	var m := _main()
	var gv := m.green_view
	var made := GreenViewShot.course("flat")
	_rest(m, made.ball, made.cup)
	var key := InputEventAction.new()
	key.action = GreenView.TOGGLE_ACTION
	key.pressed = true
	gv._unhandled_input(key)
	assert_false(gv.visible, "hidden")
	assert_true(gv.is_open, "though still open")
	gv.follow(m.free_view_rect())
	assert_false(gv.visible, "and it stays hidden frame after frame")
	gv._unhandled_input(key)
	assert_true(gv.visible, "shown again")


func test_its_window_is_the_green_and_its_fringe() -> void:
	var made := GreenViewShot.course("flat")
	var c: CourseData = made.course
	var field := HeightField.new(c, BallParams.load_default())
	var g := GreenViewShot.GREEN
	var w := GreenView.green_window(c, field, Vector2i(22, 15), 2)
	assert_eq(w, g.grow(2), "the green's bounding box with 2 tiles round it")
	assert_eq(GreenView.green_window(c, field, Vector2i(22, 15), 0), g)
	# Clipped to the map at its edge.
	var edge := CourseData.create(12, 12, Surface.Type.ROUGH, 2)
	var b := CourseBuilder.new(edge)
	b.paint(Vector2i(1, 1), Surface.Type.GREEN, 3)
	var ef := HeightField.new(edge, BallParams.load_default())
	assert_eq(GreenView.green_window(edge, ef, Vector2i(1, 1), 2), Rect2i(0, 0, 5, 5))
	# Another green two tiles off is not joined to this one.
	b.paint(Vector2i(6, 1), Surface.Type.GREEN, 1)
	assert_eq(GreenView.green_window(edge, ef, Vector2i(1, 1), 0), Rect2i(0, 0, 3, 3))


func test_the_panel_maps_tiles_and_yards_both_ways() -> void:
	var m := _main()
	var gv := m.green_view
	var made := GreenViewShot.course("flat")
	_rest(m, made.ball, made.cup)
	var w := gv.window
	var r := gv.tile_rect(w.position)
	assert_eq(r.size, Vector2.ONE * gv.tile_px, "square tiles")
	assert_eq(gv.tile_rect(w.position + Vector2i(1, 0)).position, r.position + Vector2(gv.tile_px, 0),
			"+x runs right")
	assert_eq(gv.tile_rect(w.position + Vector2i(0, 1)).position, r.position + Vector2(0, gv.tile_px),
			"+y runs down")
	var p := Vector2(103.0, 71.5)
	assert_almost_eq(gv.to_yards(gv.to_panel(p)).distance_to(p), 0.0, 0.001)
	assert_almost_eq(gv.to_panel(Vector2(w.position) * 5.0).distance_to(r.position), 0.0, 0.001,
			"a tile's corner in yards is its square's corner")


func test_a_tiles_slope_arrow_points_downhill_on_a_known_contour() -> void:
	var made := GreenViewShot.course("tiered")
	var c: CourseData = made.course
	var field := HeightField.new(c, BallParams.load_default())
	# The back tier (height 5) over the middle (3) over the front (2), stepping toward +y.
	assert_eq(c.get_height(22, 13), 5)
	assert_eq(c.get_height(22, 14), 3)
	assert_eq(c.get_height(22, 17), 2)
	var bank := GreenView.fall_at(field, Vector2i(22, 13))
	assert_almost_eq(bank.x, 0.0, 0.001)
	assert_almost_eq(bank.y, 1.0, 0.001, "two steps over the edge: half of it at each centre, toward +y")
	var step := GreenView.fall_at(field, Vector2i(22, 16))
	assert_almost_eq(step.y, 0.5, 0.001, "one step down to the front tier")
	assert_almost_eq(GreenView.fall_at(field, Vector2i(22, 11)).length(), 0.0, 0.001,
			"flat on the back tier")
	# The contoured green falls toward the front right: both components positive.
	var tilt := GreenViewShot.course("contoured")
	var tf := HeightField.new(tilt.course, BallParams.load_default())
	var tc: CourseData = tilt.course
	var f := GreenView.fall_at(tf, Vector2i(23, 16))
	assert_eq(tc.get_height(22, 16) - tc.get_height(24, 16), 1, "a step down toward +x")
	assert_eq(tc.get_height(23, 15) - tc.get_height(23, 17), 1, "and toward +y")
	assert_almost_eq(f, Vector2(0.5, 0.5), Vector2(0.001, 0.001), "so it falls toward the front right")


func test_the_marker_is_the_putt_aims_rest_in_the_panel() -> void:
	var m := _main("contoured")
	var gv := m.green_view
	var made := GreenViewShot.course("contoured")
	_rest(m, made.ball, made.cup)
	var sc := m.swing_control
	assert_not_null(sc.aim_putt, "the putter's solve ran")
	assert_true(sc.aim_putt.done)
	var rest: Vector3 = sc.aim_putt.prediction.rest
	var mp: Variant = gv.marker_panel()
	assert_not_null(mp)
	assert_almost_eq((mp as Vector2).distance_to(gv.to_panel(Vector2(rest.x, rest.y))), 0.0, 0.001)
	assert_same(m.aim_view.prediction, sc.aim_putt.prediction, "the view draws that same solve")
	var dots := gv.dot_points()
	assert_gt(dots.size(), 2, "the putt line's dots")
	assert_almost_eq(gv.to_panel(made.ball).distance_to(dots[0]),
			m.aim_view.dot_spacing_yd / 5.0 * gv.tile_px, 1.0, "the first dot a spacing from the ball")


func test_it_only_reads_the_course() -> void:
	var m := _main("tiered")
	var before := m.course.content_hash()
	var made := GreenViewShot.course("tiered")
	_rest(m, made.ball, made.cup)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(m.green_view.is_open)
	assert_eq(m.course.content_hash(), before)
