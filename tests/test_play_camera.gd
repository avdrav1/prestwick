extends GutTest
## E10-S2: the Play camera holds still while the player aims. Small mouse moves turn the aim;
## they do not pan. The camera glides only when the ball or the aim marker would leave the hold
## box (CameraTuning aim_hold_inset of the free view), and then just enough to bring it back.
##
## The frames are stepped by hand at 60 Hz (Main, SwingControl and the camera have their own
## _process turned off), and the mouse is modelled the way the game reads it: a screen pixel,
## turned into the ground under it through the camera as it stands that frame.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DT: float = 1.0 / 60.0
## A camera step smaller than this, in screen px, is not a move.
const STILL_PX: float = 0.5


## Main in Play on hole 6 of courses/playtest_nine.json (a tee in open ground, far from the
## map's edge, so the course bounds never hold the camera), the aim framed and settled, then
## `zoom_ins` presses of the zoom-in key, settled again.
func _main_in_play(zoom_ins: int = 0) -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://courses/playtest_nine.json"
	add_child_autofree(m)
	m.camera.view_size_override = Vector2(1280, 720)
	assert_true(m.frame_hole(6), "hole 6 is picked")
	m.set_mode(Main.Mode.PLAY)
	m.guest_sim.set_process(false)
	m.set_process(false)
	m.camera.set_process(false)
	m.swing_control.set_process(false)
	_frames(m, 180)  # the first framing settles
	for i: int in zoom_ins:
		m.camera.step_zoom(1)
	_frames(m, 300)
	return m


## One frame of Play: the aim, Main's camera hand-off, the camera's glide.
func _frame(m: Main) -> void:
	m.swing_control._process(DT)
	m._process(DT)
	m.camera._process(DT)


func _frames(m: Main, n: int) -> void:
	for i: int in n:
		_frame(m)


## The mouse at screen pixel `px`: aims at the ground under it, as SwingControl does.
func _mouse_at(m: Main, px: Vector2) -> void:
	var cam: CourseCamera = m.camera
	var world: Vector2 = cam.position + (px - cam.view_size() * 0.5) / cam.zoom.x
	var local: Vector2 = m.swing_control.to_local(cam.get_parent().to_global(world))
	m.swing_control.aim_at(m.swing_control._ground_under(local))


func _marker_px(m: Main) -> Vector2:
	return m.camera.screen_point(m._aim_marker_world())


## Where the point the camera keeps in the box for the marker shows: the marker itself, or
## when zoomed in too far for both, the point along the aim line (CourseCamera.held_lead).
func _held_px(m: Main) -> Vector2:
	return m.camera.screen_point(m.camera.held_lead())


func _ball_px(m: Main) -> Vector2:
	return m.camera.screen_point(m._ball_world())


## Moves the mouse `steps` times by `step` px from `start`, one frame each, and returns how
## many frames the camera moved in (and, after them, how many more until it settles).
func _sweep(m: Main, start: Vector2, step: Vector2, steps: int) -> int:
	var moves: int = 0
	var px: Vector2 = start
	for i: int in steps:
		var before: Vector2 = m.camera.position
		_mouse_at(m, px)
		_frame(m)
		if (m.camera.position - before).length() * m.camera.zoom.x > STILL_PX:
			moves += 1
		px += step
	return moves


func test_the_hold_numbers_come_from_the_resource() -> void:
	var t: CameraTuning = CameraTuning.load_default()
	assert_gt(t.aim_hold_inset, 0.0)
	assert_lt(t.aim_hold_inset, 0.25, "the box covers most of the free view")
	assert_gt(t.aim_glide_time, 0.0, "a glide, not a jump")


## The tester's case (rc4): small mouse moves, zoomed in, moved the whole screen every time.
## Before E10-S2, 20 of these 30 nudges moved the camera, at 1x and at 2x alike.
func test_small_mouse_moves_do_not_move_the_camera() -> void:
	for zoom_ins: int in [0, 1, 2]:
		var m := _main_in_play(zoom_ins)
		var z: float = m.camera.zoom.x
		var hold: Rect2 = m.camera.hold_box()
		var start: Vector2 = _held_px(m)
		assert_true(hold.has_point(start), "%sx: the framed marker %s starts in the box %s" % [z, start, hold])
		assert_true(hold.has_point(_ball_px(m)), "%sx: and so does the ball" % z)
		# Thirty 3 px nudges of the mouse around the marker: a player steadying the aim.
		var aim_before: float = m.swing_control.aim_deg
		var moves: int = _sweep(m, start, Vector2(0, 3), 15) + _sweep(m, start + Vector2(0, 45), Vector2(0, -3), 15)
		assert_ne(m.swing_control.aim_deg, aim_before, "%sx: the nudges turned the aim" % z)
		assert_eq(moves, 0, "%sx: the camera holds still while the marker stays in the box" % z)
		assert_true(hold.has_point(_held_px(m)), "%sx: the marker is still in the box" % z)
		m.free()


## Turns the aim a quarter (`sign` 1 or -1) at the zoom `zoom_ins` gives and checks the glide.
func _turn_and_glide(zoom_ins: int, turn_deg: float) -> void:
	var m := _main_in_play(zoom_ins)
	var cam: CourseCamera = m.camera
	var hold: Rect2 = cam.hold_box()
	var sc: SwingControl = m.swing_control
	var to := Vector2.from_angle(deg_to_rad(sc.aim_deg + turn_deg)) * 100.0
	sc.aim_at(sc.ball_at + to)
	var before: Vector2 = cam.position
	_frame(m)
	var first: float = (cam.position - before).length() * cam.zoom.x
	_frames(m, 300)
	var total: float = (cam.position - before).length() * cam.zoom.x
	var label: String = "%sx, %s deg" % [cam.zoom.x, turn_deg]
	assert_gt(total, 1.0, "%s: the marker left the box, so the camera moved" % label)
	assert_lt(first, total * 0.25, "%s: it glides: the first frame covers under a quarter of the move" % label)
	var marker: Vector2 = _held_px(m)
	var ball: Vector2 = _ball_px(m)
	assert_true(hold.grow(1.0).has_point(marker), "%s: the marker %s is back in the box %s" % [label, marker, hold])
	assert_true(hold.grow(1.0).has_point(ball), "%s: and the ball %s stays in it" % [label, ball])
	var on_edge: bool = false
	for p: Vector2 in [marker, ball]:
		for axis: int in 2:
			if absf(p[axis] - hold.position[axis]) < 1.0 or absf(p[axis] - hold.end[axis]) < 1.0:
				on_edge = true
	assert_true(on_edge, "%s: just enough: a point rests on the box's edge, not in its middle" % label)
	m.free()


func test_a_marker_leaving_the_box_glides_just_enough_to_bring_it_back() -> void:
	for zoom_ins: int in [0, 2]:
		for turn: float in [90.0, -90.0, 180.0]:
			_turn_and_glide(zoom_ins, turn)


func test_key_turns_and_club_changes_never_jump() -> void:
	var m := _main_in_play()
	var cam: CourseCamera = m.camera
	for i: int in 36:
		var before: Vector2 = cam.position
		m.swing_control.rotate_aim(m.swing_control.tuning.aim_key_step_deg)
		_frame(m)
		var step: float = (cam.position - before).length() * cam.zoom.x
		assert_lt(step, 40.0, "key turn %d: the camera moves at most a glide's step (%.1f px)" % [i, step])
	for i: int in 6:
		var before: Vector2 = cam.position
		var zoom: Vector2 = cam.zoom
		m.swing_control.cycle_club(1)
		_frame(m)
		assert_eq(cam.zoom, zoom, "club %d: the zoom holds" % i)
		var step: float = (cam.position - before).length() * cam.zoom.x
		assert_lt(step, 40.0, "club %d: the camera moves at most a glide's step (%.1f px)" % [i, step])
	m.free()


func test_c_recentres_on_the_framing() -> void:
	var m := _main_in_play()
	var cam: CourseCamera = m.camera
	var framed: Vector2 = cam.position
	# Nudge the aim a little: held, the camera stays put, off the framing's exact centre.
	m.swing_control.rotate_aim(m.swing_control.tuning.aim_key_step_deg * 3.0)
	_frames(m, 60)
	assert_eq(cam.position, framed, "a small turn holds")
	var turned: Vector2 = cam.held_at(cam.framed_at())
	cam.pan(Vector2(300, 200))
	_frames(m, 60)
	assert_false(cam.tracking, "a pan scouts")
	assert_ne(cam.position, framed)
	cam.snap_back()
	_frames(m, 300)
	assert_true(cam.tracking, "C tracks again")
	assert_almost_eq(cam.position, cam._clamped(turned), Vector2(1, 1), "C frames the ball and the turned marker afresh")
	m.free()


func test_the_zoom_keys_still_work_while_aiming() -> void:
	var m := _main_in_play()
	var cam: CourseCamera = m.camera
	var z: float = cam.zoom.x
	cam.step_zoom(1)
	assert_gt(cam.zoom.x, z, "the zoom key zooms in")
	_frames(m, 300)
	assert_true(cam.hold_box().grow(1.0).has_point(_ball_px(m)), "the ball is held in the box")
	assert_true(cam.hold_box().grow(1.0).has_point(_held_px(m)), "and so is the aim line")
	cam.step_zoom(-1)
	assert_eq(cam.zoom.x, z, "and back out")
	m.free()
