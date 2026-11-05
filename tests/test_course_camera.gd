extends GutTest
## E1-S4: the course camera pans with WASD and a middle-mouse drag, and zooms 0.5x, 1x, 2x;
## E3-S9 (D45) adds a farthest step, 0.175x.

var _cam: CourseCamera


func before_each() -> void:
	_cam = CourseCamera.new()
	add_child_autofree(_cam)


func after_each() -> void:
	for action: StringName in [CourseCamera.PAN_LEFT, CourseCamera.PAN_RIGHT, CourseCamera.PAN_UP, CourseCamera.PAN_DOWN]:
		Input.action_release(action)


func test_tuning_comes_from_the_resource() -> void:
	assert_not_null(_cam.tuning)
	assert_eq(_cam.tuning.zoom_levels, PackedFloat32Array([0.175, 0.5, 1.0, 2.0]))
	assert_eq(_cam.zoom, Vector2.ONE, "starts at 1x")
	assert_eq(_cam.tuning.aim_farthest_zoom, 0.5, "the aim fit stops at 0.5x")


func test_zoom_steps_and_stops_at_the_ends() -> void:
	_cam.step_zoom(1)
	assert_eq(_cam.zoom, Vector2(2, 2))
	_cam.step_zoom(1)
	assert_eq(_cam.zoom, Vector2(2, 2), "2x is the closest")
	_cam.step_zoom(-1)
	_cam.step_zoom(-1)
	assert_eq(_cam.zoom, Vector2(0.5, 0.5))
	_cam.step_zoom(-1)
	assert_eq(_cam.zoom.x, _cam.tuning.zoom_levels[0], "the player reaches the farthest step, 0.175x (D45)")
	assert_almost_eq(_cam.zoom.x, 0.175, 0.0001)
	_cam.step_zoom(-1)
	assert_eq(_cam.zoom.x, _cam.tuning.zoom_levels[0], "0.175x is the farthest")


func test_a_zoom_is_named_by_its_value() -> void:
	for z: float in [0.175, 0.5, 1.0, 2.0]:
		_cam.set_zoom_level(z)
		assert_almost_eq(_cam.zoom.x, z, 0.0001, "%sx" % z)
	assert_eq(_cam.zoom_index_of(0.6), _cam.zoom_index_of(0.5), "the nearest level")


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


# --- aiming at rest: the ball and the aim marker framed together (E2-S8 review, pillar 2) ---

func _aiming_cam() -> void:
	_cam.view_size_override = Vector2(1280, 720)
	_cam.frame(Rect2(-5000, -5000, 10000, 10000))
	_cam.centre_on(Vector2.ZERO, true)


## True when world point `p` is on screen at least the frame margin inside the edge.
func _on_screen(p: Vector2) -> bool:
	var half := _cam.view_size() * 0.5 / _cam.zoom.x
	var inset := Vector2.ONE * (_cam.tuning.aim_frame_margin - 0.5) / _cam.zoom.x
	var r := Rect2(_cam.position - half + inset, (half - inset) * 2.0)
	return r.has_point(p)


func test_aim_frame_margin_comes_from_the_resource() -> void:
	assert_gt(_cam.tuning.aim_frame_margin, 0.0)


func test_a_lead_that_fits_is_framed_with_the_ball_at_the_midpoint() -> void:
	_aiming_cam()
	_cam.set_lead(Vector2(800, 400))
	_cam._process(10.0)
	assert_eq(_cam.zoom, Vector2.ONE, "it fits at 1x, so the zoom stays")
	assert_almost_eq(_cam.position, Vector2(400, 200), Vector2(0.01, 0.01), "centred between them")
	assert_true(_on_screen(Vector2.ZERO), "the ball is on screen")
	assert_true(_on_screen(Vector2(800, 400)), "and so is the marker")


func test_a_lead_too_far_for_1x_steps_the_zoom_out_until_both_fit() -> void:
	_aiming_cam()
	# The driver's marker from example_par3's tee (E2-S8 review): (1568, 784) px at 1x.
	_cam.set_lead(Vector2(1568, 784))
	_cam._process(10.0)
	assert_eq(_cam.zoom, Vector2(0.5, 0.5), "one step out")
	assert_true(_on_screen(Vector2.ZERO), "the ball is on screen")
	assert_true(_on_screen(Vector2(1568, 784)), "and so is the marker")


func test_a_lead_too_far_for_any_zoom_keeps_the_ball_on_screen() -> void:
	_aiming_cam()
	_cam.set_lead(Vector2(6000, 0))
	_cam._process(10.0)
	assert_eq(_cam.zoom, Vector2(0.5, 0.5), "the aim fit's farthest level, aim_farthest_zoom (D45)")
	assert_true(_on_screen(Vector2.ZERO), "the ball never leaves the screen")
	assert_gt(_cam.position.x, 0.0, "the view leans toward the marker")


func test_the_next_aim_comes_back_to_the_players_zoom() -> void:
	_aiming_cam()
	_cam.set_lead(Vector2(1568, 784))
	assert_eq(_cam.zoom, Vector2(0.5, 0.5))
	_cam.clear_lead()
	_cam.centre_on(Vector2(1568, 784))
	assert_eq(_cam.zoom, Vector2(0.5, 0.5), "a strike keeps the framed zoom for the flight")
	_cam.centre_on(Vector2(1568, 784), true)
	assert_eq(_cam.zoom, Vector2.ONE, "the next aim starts from the player's 1x")
	assert_false(_cam.has_lead)


func test_from_the_farthest_step_the_aim_keeps_the_players_zoom() -> void:
	_aiming_cam()
	_cam.step_zoom(-1)
	_cam.step_zoom(-1)
	_cam.centre_on(Vector2.ZERO, true)
	assert_eq(_cam.zoom.x, _cam.tuning.zoom_levels[0], "the player's own 0.175x")
	_cam.set_lead(Vector2(1568, 784))
	assert_eq(_cam.zoom.x, _cam.tuning.zoom_levels[0], "the fit never zooms in")


func test_a_zoom_key_wins_over_the_fit() -> void:
	_aiming_cam()
	_cam.step_zoom(1)
	_cam.set_lead(Vector2(1568, 784))
	assert_eq(_cam.zoom, Vector2(2, 2), "the player zoomed in, so the fit does not undo it")
	_cam._process(10.0)
	assert_true(_on_screen(Vector2.ZERO), "the ball stays on screen")
	_cam.centre_on(Vector2.ZERO, true)
	assert_eq(_cam.zoom, Vector2(2, 2), "and 2x is now the player's level")


func test_without_a_lead_the_camera_follows_the_ball_alone() -> void:
	_aiming_cam()
	_cam.set_lead(Vector2(800, 400))
	_cam.clear_lead()
	_cam._process(10.0)
	assert_almost_eq(_cam.position, Vector2.ZERO, Vector2(0.01, 0.01))


func test_a_panned_camera_does_not_zoom_for_the_lead() -> void:
	_aiming_cam()
	_cam.pan(Vector2(10, 0))
	_cam.set_lead(Vector2(1568, 784))
	assert_eq(_cam.zoom, Vector2.ONE, "scouting: the player has the camera")


# --- framing a hole clear of the whole HUD (E3-S9) ---

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")


func test_a_long_hole_keeps_its_tee_inside_the_safe_area_in_every_direction() -> void:
	_cam.view_size_override = Vector2(1280, 720)
	_cam.frame(Rect2(-20000, -20000, 40000, 40000))
	var safe := Rect2(196, 0, 735, 622)
	var inner: Rect2 = safe.grow(-_cam.tuning.aim_frame_margin + 0.5)
	for dir: Vector2 in [Vector2(2, 1), Vector2(-2, -1), Vector2(2, -1), Vector2(-2, 1)]:
		var tee := Vector2(300, -200)
		var cup: Vector2 = tee + dir * 4000.0
		_cam.frame_points(tee, cup, safe)
		assert_eq(_cam.zoom.x, _cam.tuning.zoom_levels[0], "%s: the farthest zoom" % dir)
		assert_false(_cam.fits(tee, cup, _cam.zoom.x, safe.size), "%s: too long even there" % dir)
		var t: Vector2 = _cam.screen_point(tee)
		assert_true(inner.has_point(t), "%s: the tee %s shows inside %s" % [dir, t, safe])
		var toward: Vector2 = _cam.screen_point(cup) - t
		assert_gt(toward.dot(dir), 0.0, "%s: the view leans toward the cup" % dir)
		var mid_on_screen: Vector2 = t + toward.normalized() * 100.0
		assert_true(safe.has_point(mid_on_screen), "%s: the hole runs into the free view" % dir)


## E3-S9 Accept (D45): every nine_holes hole framed at 1280 x 720 (the hole list showing all
## nine rows) puts its tee and its cup inside the free view, clear of every HUD control: the
## top-left column, the hole panel and the build palette. The farthest zoom, 0.175x, is sized
## for the longest, hole 3 (520 yd, 3328 x 1680 px at 1x, against a free view of 731 x 622):
## it fits there and not at 0.5x. Each hole frames at the nearest level that fits it.
func test_every_nine_holes_hole_frames_clear_of_the_hud() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	m.show_course(c)
	m.camera.view_size_override = Vector2(1280, 720)
	var cam: CourseCamera = m.camera
	var levels: PackedFloat32Array = cam.tuning.zoom_levels
	var framed_at: Dictionary = {}
	for h: HoleData in c.holes:
		assert_true(m.frame_hole(h.number), "hole %d frames" % h.number)
		assert_eq(m.build_tool.hole_number, h.number, "and is picked")
		var free: Rect2 = m.free_view_rect()
		var controls: Array[Control] = m.hud_controls()
		var names: PackedStringArray = []
		for ctl: Control in controls:
			names.append(ctl.name)
		for want: String in ["ModeButton", "NewSandboxButton", "HolePanel", "BuildPalette"]:
			assert_has(names, want, "%s is counted" % want)
		for ctl: Control in controls:
			var r: Rect2 = m._hud_rect(ctl)
			assert_false(free.intersects(r), "hole %d: the free view %s misses %s %s" % [h.number, free, ctl.name, r])
		var tee_w: Vector2 = m.tile_world(h.tee)
		var cup_w: Vector2 = m.tile_world(h.cup)
		var tee: Vector2 = cam.screen_point(tee_w)
		var cup: Vector2 = cam.screen_point(cup_w)
		var inner: Rect2 = free.grow(-cam.tuning.aim_frame_margin + 0.5)
		assert_true(inner.has_point(tee), "hole %d: its tee %s shows inside %s" % [h.number, tee, free])
		assert_true(inner.has_point(cup), "hole %d: its cup %s shows inside %s" % [h.number, cup, free])
		for ctl: Control in controls:
			var r: Rect2 = m._hud_rect(ctl)
			assert_false(r.has_point(tee), "hole %d: %s does not cover its tee" % [h.number, ctl.name])
			assert_false(r.has_point(cup), "hole %d: %s does not cover its cup" % [h.number, ctl.name])
		var at: int = cam.zoom_index
		if at < levels.size() - 1 and at < cam.tuning.start_zoom_index:
			assert_false(cam.fits(tee_w, cup_w, levels[at + 1], free.size),
					"hole %d: framed at the nearest level that fits" % h.number)
		framed_at[h.number] = levels[at]
	gut.p("E3-S9: zoom each nine_holes hole frames at: %s" % [framed_at])
	for n: int in [2, 4, 7]:
		assert_eq(framed_at[n], 0.5, "par 3 hole %d fits at 0.5x" % n)
	for n: int in [1, 3, 5, 6, 8, 9]:
		assert_eq(framed_at[n], levels[0], "hole %d needs the farthest step" % n)
	var h3: HoleData = c.holes[2]
	assert_eq(h3.number, 3)
	var free3: Rect2 = m.free_view_rect()
	assert_false(cam.fits(m.tile_world(h3.tee), m.tile_world(h3.cup), 0.5, free3.size),
			"the longest hole does not fit at 0.5x")
	assert_true(cam.fits(m.tile_world(h3.tee), m.tile_world(h3.cup), levels[0], free3.size),
			"and fits at the farthest step")
