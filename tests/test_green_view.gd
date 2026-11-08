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
	# E3-S71: the map's top-down drawing turned by `turn`, tiles still square.
	var p := Vector2(103.0, 71.5)
	var east := gv.to_panel(p + Vector2(5.0, 0.0)) - gv.to_panel(p)
	var south := gv.to_panel(p + Vector2(0.0, 5.0)) - gv.to_panel(p)
	assert_almost_eq(east, Vector2(gv.tile_px, 0.0).rotated(gv.turn), Vector2(0.001, 0.001),
			"+x runs along the turned panel's x")
	assert_almost_eq(south, Vector2(0.0, gv.tile_px).rotated(gv.turn), Vector2(0.001, 0.001),
			"+y along its y, square tiles")
	assert_almost_eq(gv.to_yards(gv.to_panel(p)).distance_to(p), 0.0, 0.001)
	# Turned by none (no cup ahead of the ball), the window is the drawn tiles and maps as before.
	gv.turn_to(0.0)
	assert_eq(gv.drawn, gv.window, "map-aligned, the panel is the window")
	assert_almost_eq(gv.to_panel(Vector2(gv.window.position) * 5.0),
			Vector2(gv.tuning.inset_px, gv.tuning.inset_px + gv.tuning.header_px), Vector2(0.001, 0.001),
			"a tile's corner in yards is its square's corner")
	assert_almost_eq(gv.to_yards(gv.to_panel(p)).distance_to(p), 0.0, 0.001)


# --- E3-S71: the putt runs up the panel ---


func test_the_putt_runs_up_the_panel_for_four_headings() -> void:
	var made := GreenViewShot.course("flat")
	var cup: Vector2i = made.cup  # (24, 12)
	# The ball south, west, north and east of the cup, and one off a diagonal.
	for tile: Vector2i in [Vector2i(24, 17), Vector2i(19, 12), Vector2i(24, 10), Vector2i(26, 12),
			Vector2i(20, 16)]:
		var m := _main()
		var gv := m.green_view
		var ball := (Vector2(tile) + Vector2(0.5, 0.5)) * 5.0
		_rest(m, ball, cup)
		assert_true(gv.is_open, "open with the ball on %s" % tile)
		var b := gv.to_panel(ball)
		var c := gv.to_panel(m.swing_control.field.tile_center(cup))
		assert_gt(b.y, c.y, "the ball below the cup from %s" % tile)
		assert_almost_eq(b.x, c.x, 0.01, "straight below it from %s" % tile)
		assert_almost_eq(gv.ball_panel().distance_to(b), 0.0, 0.001)
		# The marker and the dots turn with it: the marker is the solve's rest in the turned panel.
		var rest: Vector3 = m.swing_control.aim_putt.prediction.rest
		var mp: Variant = gv.marker_panel()
		assert_not_null(mp)
		assert_almost_eq((mp as Vector2).distance_to(gv.to_panel(Vector2(rest.x, rest.y))), 0.0, 0.001)
		# The panel still sits in the free view, and its turned tiles cover it.
		var free := m.free_view_rect()
		assert_true(free.encloses(gv.get_rect()), "the panel sits in the free view from %s" % tile)
		assert_true(gv.drawn.encloses(gv.window), "every tile of the window is drawn")
		# The window's corners all land inside the panel's content.
		var content := Rect2(Vector2(gv.tuning.inset_px, gv.tuning.inset_px + gv.tuning.header_px),
				gv.size - Vector2(2.0 * gv.tuning.inset_px, 2.0 * gv.tuning.inset_px + gv.tuning.header_px))
		for k: Vector2i in [Vector2i.ZERO, Vector2i(gv.window.size.x, 0), gv.window.size, Vector2i(0, gv.window.size.y)]:
			var at := gv.to_panel(Vector2(gv.window.position + k) * 5.0)
			assert_true(content.grow(0.01).has_point(at), "the window's corner %s is in the panel" % k)


func test_the_turn_holds_while_the_putt_rolls_and_refits_on_the_next() -> void:
	var m := _main("contoured")
	var gv := m.green_view
	var sc := m.swing_control
	var made := GreenViewShot.course("contoured")
	_rest(m, made.ball, made.cup)
	var turned := gv.turn
	assert_ne(turned, 0.0, "the contoured putt runs off the map's axes")
	sc.rotate_aim(12.0)  # miss the cup, so the ball rests on the green elsewhere
	sc._refresh_aim()
	sc.settle_aim()
	sc.swing.set_result(sc.aim_power, 0.0)
	sc._strike()
	var frames := 0
	while sc.is_ball_moving() and frames < 2000:
		m.shot_view.advance(1.0 / 60.0)
		gv.follow(m.free_view_rect())
		if sc.is_ball_moving():
			assert_eq(gv.turn, turned, "the turn holds while the putt rolls")
		frames += 1
	assert_false(sc.score.holed, "the turned aim missed")
	assert_eq(sc.lie_surface(), Surface.Type.GREEN, "and rested on the green")
	sc.aim_at(sc.field.tile_center(made.cup))
	sc._refresh_aim()
	sc.settle_aim()
	gv.follow(m.free_view_rect())
	assert_ne(gv.turn, turned, "the next putt turns the panel again")
	var b := gv.to_panel(sc.ball_at)
	var c := gv.to_panel(sc.field.tile_center(made.cup))
	assert_gt(b.y, c.y, "the ball below the cup again")
	assert_almost_eq(b.x, c.x, 0.01)


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


func test_fall_arrows_only_on_steep_tiles() -> void:
	# E3-S56: an arrow only where the fall reaches arrow_steep_fall (2 steps a tile).
	var m := _main("tiered")
	var gv := m.green_view
	var made := GreenViewShot.course("tiered")
	_rest(m, made.ball, made.cup)
	assert_true(gv.is_open)
	assert_eq(gv.tuning.arrow_steep_fall, 2.0)
	var arrows := gv.arrow_cells()
	var field := m.swing_control.field
	assert_true(Vector2i(22, 13) in arrows, "the top of the two-step bank")
	assert_true(Vector2i(22, 14) in arrows, "and its foot")
	assert_almost_eq(GreenView.steep_fall_at(field, Vector2i(22, 13)), Vector2(0, 2), Vector2(0.001, 0.001),
			"pointing down the bank, toward +y")
	assert_false(Vector2i(22, 16) in arrows, "no arrow on the one-step slope to the front tier")
	assert_false(Vector2i(22, 11) in arrows, "none on the flat back tier")
	for cell: Vector2i in arrows:
		assert_gte(GreenView.steep_fall_at(field, cell).length(), 2.0 - 0.001)
	# The contoured green falls one step at a time: no arrows on it or its fringe, only lines.
	# (E3-S71: the turned panel also draws the fixture's raised plot's banks past the fringe.)
	var mc := _main("contoured")
	var tilt := GreenViewShot.course("contoured")
	_rest(mc, tilt.ball, tilt.cup)
	assert_true(mc.green_view.is_open)
	for cell: Vector2i in mc.green_view.arrow_cells():
		assert_false(mc.green_view.window.has_point(cell), "no arrow in the window: %s" % cell)
	assert_gt(mc.green_view.contours.size(), 0)


func test_its_contours_follow_the_ground_and_a_flat_green_has_none() -> void:
	# E3-S56: smooth lines every half step from ContourTracer, an index line every whole step.
	var m := _main("flat")
	var made := GreenViewShot.course("flat")
	_rest(m, made.ball, made.cup)
	assert_true(m.green_view.is_open)
	assert_eq(m.green_view.contours.size(), 0, "a flat green and its flat fringe: no lines")
	assert_eq(m.green_view.arrow_cells().size(), 0)
	var mt := _main("tiered")
	var gv := mt.green_view
	var tiered := GreenViewShot.course("tiered")
	_rest(mt, tiered.ball, tiered.cup)
	var field := mt.swing_control.field
	var levels: Array[float] = []
	var area := Rect2(Vector2(gv.drawn.position) * 5.0, Vector2(gv.drawn.size) * 5.0).grow(0.001)
	for entry: Array in gv.contours:
		var level: float = entry[0]
		levels.append(level)
		var off := gv.tuning.contour_offset
		assert_eq(entry[1], is_equal_approx(level - off, roundf(level - off)),
				"an index line every whole step from the offset")
		for line: PackedVector2Array in entry[2]:
			for p: Vector2 in line:
				assert_almost_eq(field.height_at(p.x, p.y) / field.yards_per_step, level, 0.001)
				assert_true(area.has_point(p), "inside the drawn tiles")
	# The tiers 5, 3 and 2 (and the rough at 2 round them): every half step from 2.5 to 5.
	assert_eq(levels, [2.5, 3.0, 3.5, 4.0, 4.5, 5.0] as Array[float])


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


# --- E3-S53: aim and putt in the green view ---

## Counts the mouse buttons that reach unhandled input (where TagClicks, BuildTool,
## SwingControl and the camera take them).
class ClickProbe:
	extends Node
	var seen: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			seen += 1


## GUT's own output panel sits over the middle of the root viewport and would take the mouse
## events these tests push there: hidden while a test runs.
func before_each() -> void:
	_gut_layer(false)


func after_each() -> void:
	_gut_layer(true)


func _gut_layer(shown: bool) -> void:
	var layer := get_tree().root.get_node_or_null("GutRunner/GutLayer") as CanvasLayer
	if layer != null:
		layer.visible = shown


## Sends a mouse event to the viewport at screen point `at`, as the real mouse does.
func _push(m: Main, ev: InputEventMouse, at: Vector2) -> void:
	ev.position = at
	ev.global_position = at
	m.get_viewport().push_input(ev, true)


func _move(m: Main, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	_push(m, ev, at)


func _click(m: Main, at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_push(m, ev, at)


## The screen point of panel point `local`.
func _screen(gv: GreenView, local: Vector2) -> Vector2:
	return gv.get_global_transform_with_canvas() * local


func test_a_cursor_on_the_panel_aims_at_the_tile_under_it() -> void:
	var m := _main("contoured")
	var gv := m.green_view
	var sc := m.swing_control
	var made := GreenViewShot.course("contoured")
	_rest(m, made.ball, made.cup)
	await get_tree().process_frame
	assert_ne(gv.turn, 0.0, "E3-S71: the panel is turned to the putt")
	for target: Vector2i in [Vector2i(25, 11), Vector2i(19, 12), Vector2i(23, 18)]:
		var local := gv.to_panel(sc.field.tile_center(target))
		assert_almost_eq(gv.to_yards(local).distance_to(sc.field.tile_center(target)), 0.0, 0.001)
		_move(m, _screen(gv, local))
		var to := sc.field.tile_center(target) - sc.ball_at
		assert_almost_eq(sc.aim_deg, fposmod(rad_to_deg(to.angle()), 360.0), 0.01,
				"the heading from the ball to tile %s" % target)
	# The isometric aim line follows the same heading once its solve catches up.
	sc._refresh_aim()
	sc.settle_aim()
	assert_almost_eq(sc.aim_prediction_deg, sc.aim_deg, 0.001, "the aim line is along it")
	assert_same(m.aim_view.prediction, sc.aim_putt.prediction)
	# The aim keys still turn it, and the mouse takes it back only once it moves on.
	var before := sc.aim_deg
	var key := InputEventAction.new()
	key.action = SwingControl.AIM_RIGHT
	key.pressed = true
	m.get_viewport().push_input(key, true)
	assert_almost_eq(sc.aim_deg, fposmod(before + sc.tuning.aim_key_step_deg, 360.0), 0.001,
			"an aim key turns it")
	var turned := sc.aim_deg
	var still := m.get_viewport().get_mouse_position()
	_move(m, still)
	assert_almost_eq(sc.aim_deg, turned, 0.001, "a mouse that has not moved keeps the key's aim")


func test_a_click_on_the_panel_swings_and_never_reaches_the_map() -> void:
	var m := _main()
	var gv := m.green_view
	var made := GreenViewShot.course("flat")
	_rest(m, made.ball, made.cup)
	await get_tree().process_frame
	var probe := ClickProbe.new()
	m.add_child(probe)
	var at := _screen(gv, gv.to_panel(m.swing_control.field.tile_center(gv.window.get_center())))
	assert_true(gv.get_global_rect().has_point(at), "the click is on the panel")
	var before := m.course.content_hash()
	_click(m, at, true)
	_click(m, at, false)
	assert_eq(probe.seen, 0, "neither the press nor the release reaches TagClicks or the map")
	assert_false(m.tag_clicks._held)
	assert_eq(m.mode, Main.Mode.PLAY, "no Build switch")
	assert_true(m.swing_control.swing.in_progress(), "the click is a swing click")
	assert_eq(m.course.content_hash(), before)
	# The wheel and the middle button go on to the camera (zoom, drag), so a drag let go over
	# the panel never sticks.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_MIDDLE
	wheel.pressed = false
	_push(m, wheel, at)
	assert_eq(probe.seen, 1, "a middle button release on the panel reaches the camera")
	probe.seen = 0
	# A click off the panel still reaches the map, as before.
	m.swing_control.swing.reset()
	var off := Vector2(gv.get_global_rect().position.x - 20.0, gv.get_global_rect().get_center().y)
	assert_false(gv.get_global_rect().has_point(off))
	_click(m, off, true)
	_click(m, off, false)
	assert_gt(probe.seen, 0, "a click on the map goes on to it")


func test_the_ball_in_the_panel_follows_the_putt_each_frame() -> void:
	var m := _main("contoured")
	var gv := m.green_view
	var sc := m.swing_control
	var made := GreenViewShot.course("contoured")
	_rest(m, made.ball, made.cup)
	assert_almost_eq(gv.ball_panel().distance_to(gv.to_panel(made.ball)), 0.0, 0.001)
	sc.swing.set_result(sc.aim_power, 0.0)
	sc._strike()
	assert_true(sc.is_ball_moving())
	var frames := 0
	var moved := 0.0
	var last := gv.ball_panel()
	while sc.is_ball_moving() and frames < 2000:
		m.shot_view.advance(1.0 / 60.0)
		gv.follow(m.free_view_rect())
		if not sc.is_ball_moving():
			break
		var p := m.shot_view.drawn_position()
		assert_true(gv.is_open, "open while the putt rolls")
		assert_almost_eq(gv.ball_panel().distance_to(gv.to_panel(Vector2(p.x, p.y))), 0.0, 0.001)
		moved += gv.ball_panel().distance_to(last)
		last = gv.ball_panel()
		frames += 1
	assert_gt(frames, 30, "the roll took frames")
	assert_gt(moved, gv.tile_px * 2.0, "and the drawn ball crossed the panel")
	assert_eq(gv.dot_points().size(), 0, "no aim line while it rolls")
