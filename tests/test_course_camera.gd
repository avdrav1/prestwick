extends GutTest
## E1-S4: the course camera pans with WASD and a middle-mouse drag, and zooms 0.5x, 1x, 2x.

var _cam: CourseCamera


func before_each() -> void:
	_cam = CourseCamera.new()
	add_child_autofree(_cam)


func after_each() -> void:
	for action: StringName in [CourseCamera.PAN_LEFT, CourseCamera.PAN_RIGHT, CourseCamera.PAN_UP, CourseCamera.PAN_DOWN]:
		Input.action_release(action)


func test_tuning_comes_from_the_resource() -> void:
	assert_not_null(_cam.tuning)
	assert_eq(_cam.tuning.zoom_levels, PackedFloat32Array([0.5, 1.0, 2.0]))
	assert_eq(_cam.zoom, Vector2.ONE, "starts at 1x")


func test_zoom_steps_and_stops_at_the_ends() -> void:
	_cam.step_zoom(1)
	assert_eq(_cam.zoom, Vector2(2, 2))
	_cam.step_zoom(1)
	assert_eq(_cam.zoom, Vector2(2, 2), "2x is the closest")
	_cam.step_zoom(-1)
	_cam.step_zoom(-1)
	assert_eq(_cam.zoom, Vector2(0.5, 0.5))
	_cam.step_zoom(-1)
	assert_eq(_cam.zoom, Vector2(0.5, 0.5), "0.5x is the farthest")


func test_zoom_actions() -> void:
	var ev := InputEventAction.new()
	ev.action = CourseCamera.ZOOM_IN
	ev.pressed = true
	_cam._unhandled_input(ev)
	assert_eq(_cam.zoom, Vector2(2, 2))
	ev.action = CourseCamera.ZOOM_OUT
	_cam._unhandled_input(ev)
	assert_eq(_cam.zoom, Vector2.ONE)


func test_wasd_actions_are_bound() -> void:
	for pair: Array in [[CourseCamera.PAN_LEFT, KEY_A], [CourseCamera.PAN_RIGHT, KEY_D],
			[CourseCamera.PAN_UP, KEY_W], [CourseCamera.PAN_DOWN, KEY_S]]:
		var key := InputEventKey.new()
		key.physical_keycode = pair[1]
		key.pressed = true
		assert_true(key.is_action(pair[0]), "%s on %s" % [pair[0], OS.get_keycode_string(pair[1])])


func test_keys_pan_at_tuned_speed_in_screen_pixels() -> void:
	Input.action_press(CourseCamera.PAN_RIGHT)
	_cam._process(0.5)
	assert_almost_eq(_cam.position.x, _cam.tuning.pan_speed * 0.5, 0.01)
	Input.action_release(CourseCamera.PAN_RIGHT)
	_cam.step_zoom(1)  # 2x: the same key time moves half as far in world space
	var x0: float = _cam.position.x
	Input.action_press(CourseCamera.PAN_UP)
	_cam._process(0.5)
	assert_almost_eq(_cam.position.y, -_cam.tuning.pan_speed * 0.25, 0.01)
	assert_almost_eq(_cam.position.x, x0, 0.01)


func test_middle_drag_moves_the_course_with_the_mouse() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	_cam._unhandled_input(press)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(40, -10)
	move.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	_cam._unhandled_input(move)
	assert_eq(_cam.position, Vector2(-40, 10), "view follows the grabbed point")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE
	release.pressed = false
	_cam._unhandled_input(release)
	var hover := InputEventMouseMotion.new()
	hover.relative = Vector2(100, 100)
	_cam._unhandled_input(hover)
	assert_eq(_cam.position, Vector2(-40, 10), "plain mouse moves do not pan")


func test_frame_centers_and_clamps_to_the_course() -> void:
	var rect := Rect2(-640, -128, 1280, 768)
	_cam.frame(rect)
	assert_eq(_cam.position, rect.get_center())
	_cam.pan(Vector2(100000, 100000))
	assert_eq(_cam.position, rect.end + Vector2.ONE * _cam.tuning.edge_margin, "stops past the edge margin")


# --- the play camera (E2-S8) ---

func test_centre_time_comes_from_the_resource() -> void:
	assert_gt(_cam.tuning.centre_time, 0.0)
	assert_lt(_cam.tuning.centre_time, 1.0, "eases onto the ball in well under a second")


func test_centre_on_eases_onto_the_ball() -> void:
	_cam.frame(Rect2(-2000, -2000, 4000, 4000))
	_cam.centre_on(Vector2(300, 120))
	assert_true(_cam.tracking)
	_cam._process(_cam.tuning.centre_time)
	var d: float = _cam.position.distance_to(Vector2(300, 120))
	assert_between(d, 1.0, 323.0 * 0.5, "most of the way after one time constant")
	_cam._process(10.0)
	assert_almost_eq(_cam.position, Vector2(300, 120), Vector2(0.01, 0.01), "and there in the end")


func test_tracking_follows_a_moving_focus() -> void:
	_cam.frame(Rect2(-2000, -2000, 4000, 4000))
	_cam.centre_on(Vector2.ZERO)
	_cam._process(10.0)
	_cam.set_focus(Vector2(50, 0))
	_cam._process(10.0)
	assert_almost_eq(_cam.position.x, 50.0, 0.01, "the camera keeps the ball centred")


func test_a_pan_stops_tracking_and_the_key_snaps_back() -> void:
	_cam.frame(Rect2(-2000, -2000, 4000, 4000))
	_cam.centre_on(Vector2(100, 100))
	_cam._process(10.0)
	_cam.pan(Vector2(400, 0))
	assert_false(_cam.tracking, "panning to scout leaves the ball")
	var scouted: Vector2 = _cam.position
	_cam.set_focus(Vector2(120, 100))
	_cam._process(10.0)
	assert_eq(_cam.position, scouted, "and stays where the player panned")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	assert_true(key.is_action(CourseCamera.SNAP_BACK), "C is the snap-back key")
	var ev := InputEventAction.new()
	ev.action = CourseCamera.SNAP_BACK
	ev.pressed = true
	_cam._unhandled_input(ev)
	assert_true(_cam.tracking)
	_cam._process(10.0)
	assert_almost_eq(_cam.position, Vector2(120, 100), Vector2(0.01, 0.01), "one key snaps it back to the ball")


func test_snap_back_with_no_ball_does_nothing() -> void:
	_cam.frame(Rect2(-640, -128, 1280, 768))
	var at: Vector2 = _cam.position
	_cam.snap_back()
	_cam._process(1.0)
	assert_eq(_cam.position, at)


func test_frame_forgets_the_ball() -> void:
	_cam.centre_on(Vector2(100, 100))
	_cam.frame(Rect2(-640, -128, 1280, 768))
	assert_false(_cam.tracking)
	_cam._process(1.0)
	assert_eq(_cam.position, Rect2(-640, -128, 1280, 768).get_center())
