extends GutTest
## E21-S1 (D77): the opening flyover. It plays on first launch (no `intro` key in the hints
## file), then the menu; a second launch goes straight to the menu; the menu's Watch intro
## replays it; any key, click or pad button skips it at any moment and leaves the menu exactly
## as without it; the player's course and save are never touched; it works from the keyboard
## alone. The drive is a real shaped ball (ShotModel.full with the slice, Ball at 60 Hz), aimed at
## the trees and bending round onto the fairway past the corner, played back with a slow motion
## through its bend while the camera leads it.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const HINTS := "user://test_intro_hints.cfg"
const SAVE := "user://test_intro_save.json"
const AUTOSAVES := "user://test_intro_autosaves"
const STEP: float = 1.0 / 60.0


func before_each() -> void:
	for p: String in [HINTS, SAVE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func after_all() -> void:
	before_each()


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	m.intro_settings_path = HINTS
	m.save_path = SAVE
	m.autosave_folder = AUTOSAVES
	add_child_autofree(m)
	m.guest_sim.set_process(false)
	m.feed_panel.set_process(false)
	# The tests step the intro themselves, frame by frame of STEP.
	m.intro.auto_advance = false
	return m


func _key(keycode: Key, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	return e


func _tap(m: Main, keycode: Key) -> void:
	m.get_viewport().push_input(_key(keycode))
	m.get_viewport().push_input(_key(keycode, false))


func _click(m: Main) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = Vector2(640, 360)
	e.pressed = true
	m.get_viewport().push_input(e)
	var up := e.duplicate() as InputEventMouseButton
	up.pressed = false
	m.get_viewport().push_input(up)


## Steps the intro to `t` seconds of its timeline (or its end), STEP at a time.
func _run_to(m: Main, t: float) -> void:
	var guard := 0
	while m.intro.playing and m.intro.time < t and guard < 60 * 60:
		m.intro.advance(STEP)
		guard += 1


func _run_out(m: Main) -> void:
	_run_to(m, INF)


## What the menu at launch looks like: the state a skip must leave exactly.
func _snapshot(m: Main) -> Dictionary:
	var focus := m.get_viewport().gui_get_focus_owner()
	return {
		"menu": m.main_menu.visible,
		"page": m.main_menu.main_page.visible,
		"focus": m.main_menu.main_buttons().find(focus),
		"mode": m.mode,
		"camera_current": m.camera.is_current(),
		"camera_at": m.camera.position,
		"zoom": m.camera.zoom,
		"camera_process": m.camera.is_processing(),
		"hud": m.hud.visible,
		"view": m.course_view.visible,
		"build_tool": m.build_tool.visible,
		"speed": m.guest_sim.speed,
		"course": m.course.content_hash(),
		"music": m.game_audio.music_track,
		"intro_nodes": m.intro.get_child_count(),
	}


# --- the flag ---

func test_the_intro_flag_is_a_user_setting_unseen_until_written() -> void:
	assert_false(HintSettings.load_from(HINTS).intro_seen, "no file: not seen")
	HintSettings.mark_intro_seen(HINTS)
	assert_true(HintSettings.load_from(HINTS).intro_seen, "written and read back")
	assert_true(HintSettings.PATH.begins_with("user://"), "kept in user settings")
	assert_ne(HintSettings.PATH, GameSave.PATH, "not the save")


func test_a_stale_hints_object_never_clears_the_intro_flag() -> void:
	# The swing panel loads its hints at start and saves when the first swing is taken: that
	# save must not write the intro flag back to unseen.
	var stale := HintSettings.load_from(HINTS)
	HintSettings.mark_intro_seen(HINTS)
	stale.swing_seen = true
	stale.save_to(HINTS)
	var now := HintSettings.load_from(HINTS)
	assert_true(now.intro_seen, "the intro flag stays")
	assert_true(now.swing_seen, "and the swing flag is saved")


func test_the_wrappers_skip_switch() -> void:
	assert_false(OpeningFlyover.skip_requested_by("", PackedStringArray()))
	assert_true(OpeningFlyover.skip_requested_by("1", PackedStringArray()))
	assert_false(OpeningFlyover.skip_requested_by("0", PackedStringArray()))
	assert_true(OpeningFlyover.skip_requested_by("", PackedStringArray(["--skip-intro"])))


# --- first and second launch ---

func test_first_launch_plays_the_intro_then_the_menu() -> void:
	var m := _main()
	m.open_at_start()
	assert_true(m.intro.playing, "no settings: the intro plays")
	assert_false(m.main_menu.visible, "the menu waits for it")
	assert_false(m.hud.visible, "the HUD is hidden while it plays")
	assert_false(m.course_view.visible, "and the player's course")
	assert_true(m.intro.camera.is_current(), "its own camera")
	assert_eq(m.guest_sim.speed, 0.0, "the guests' day is held")
	assert_true(HintSettings.load_from(HINTS).intro_seen, "the flag is written as it starts")
	watch_signals(m.intro)
	_run_out(m)
	assert_false(m.intro.playing, "it ends")
	assert_signal_emitted_with_parameters(m.intro, "finished", [false])
	assert_true(m.main_menu.visible, "then the menu")
	assert_same(m.get_viewport().gui_get_focus_owner(), m.main_menu.main_buttons()[0],
			"focus on its first button, as at launch")
	assert_true(m.camera.is_current())
	assert_true(m.hud.visible)
	assert_true(m.course_view.visible)


func test_a_second_launch_goes_straight_to_the_menu() -> void:
	HintSettings.mark_intro_seen(HINTS)
	var m := _main()
	m.open_at_start()
	assert_false(m.intro.playing)
	assert_true(m.main_menu.visible)
	assert_same(m.get_viewport().gui_get_focus_owner(), m.main_menu.main_buttons()[0])


func test_the_intro_runs_twenty_eight_to_thirty_two_seconds_through_its_beats_in_order() -> void:
	var m := _main()
	m.play_intro()
	var seen: Array[int] = []
	var guard := 0
	while m.intro.playing and guard < 60 * 60:
		var b: int = m.intro.beat()
		if seen.is_empty() or seen[-1] != b:
			seen.append(b)
		m.intro.advance(STEP)
		guard += 1
	var B := OpeningFlyover.Beat
	assert_eq(seen, [B.DAWN, B.GLIDE, B.WALK, B.AIM, B.SWING, B.FLIGHT, B.TITLE] as Array[int])
	var total: float = guard * STEP
	assert_between(total, 27.5, 32.0, "%.1f s" % total)


# --- the drive ---

func test_the_drive_is_a_real_shaped_ball_and_the_same_every_time() -> void:
	var rests: Array[Vector3] = []
	for run: int in 2:
		var m := _main()
		m.play_intro()
		_run_to(m, m.intro.strike_time() + STEP * 2.0)
		assert_eq(m.intro.beat(), OpeningFlyover.Beat.FLIGHT)
		var ball: Ball = m.intro.shot_view.ball
		assert_not_null(ball, "a Ball is in flight")
		assert_true(m.intro.launch.is_shaped(), "struck with a shape")
		assert_eq(m.intro.launch.shape.id, m.intro.tuning.shape_id)
		assert_ne(m.intro.course, m.course, "on the intro's own course")
		var predicted := ShotPrediction.run_launch(m.intro.course, m.intro.tuning.rng_seed,
				m.intro.launch, null, null, m.intro.hole.cup)
		_run_to(m, m.intro.title_time())
		assert_true(ball.is_at_rest(), "it rests before the title")
		assert_almost_eq(ball.position, predicted.rest, Vector3.ONE * 0.001,
				"stepped as in play: the live ball rests where the prediction says")
		assert_eq(ball.field.surface_at(ball.position.x, ball.position.y), Surface.Type.FAIRWAY,
				"on the fairway past the corner")
		assert_eq(ball.penalty_strokes, 0)
		rests.append(ball.position)
	assert_eq(rests[0], rests[1], "deterministic")


func test_the_drive_bends_the_way_the_hole_turns() -> void:
	var m := _main()
	m.play_intro()
	_run_to(m, m.intro.title_time())
	var h: HoleData = m.intro.hole
	var field: HeightField = m.intro.shot_view.ball.field
	var tee := field.tile_center(h.tee)
	var turn: Vector2 = GuestHole.turn_of(m.intro.course, h)
	var cup := field.tile_center(h.cup)
	var hole_side := signf((turn - tee).angle_to(cup - turn))
	assert_eq(m.intro.launch.shape.side, int(hole_side), "the shape bends the way the corner turns")
	# The track drawn on screen bends off its start line by about the shape's bend.
	var off: float = m.intro.trail.bend_yd()
	assert_gt(off, m.intro.launch.bend_yd * 0.5, "the drawn track leaves its start line")


func test_the_strike_and_the_landing_are_heard() -> void:
	var m := _main()
	m.play_intro()
	m.game_audio.history.clear()
	_run_to(m, m.intro.title_time())
	assert_has(m.game_audio.history, &"strike_tee")
	var land: Vector3 = m.intro.shot_view.prediction.landing
	var surface: int = m.intro.shot_view.ball.field.surface_at(land.x, land.y)
	assert_has(m.game_audio.history, GameAudio.LAND[surface], "the landing says its surface")
	assert_eq(m.game_audio.music_track, GameAudio.Track.BUILD, "Scaffold plays")


func test_the_drive_is_aimed_at_the_trees_and_rests_on_the_fairway_past_the_corner() -> void:
	var m := _main()
	m.play_intro()
	var intro := m.intro
	var field: HeightField = intro.shot_view.ball.field
	var h: HoleData = intro.hole
	var end: Vector2 = OpeningFlyover.Trail.guide_end_of(intro.launch)
	assert_eq(field.surface_at(end.x, end.y), Surface.Type.TREES, "the start line runs into the trees")
	_run_to(m, intro.title_time())
	var rest := Vector2(intro.shot_view.ball.position.x, intro.shot_view.ball.position.y)
	var turn: Vector2 = GuestHole.turn_of(intro.course, h)
	var cup := field.tile_center(h.cup)
	assert_eq(field.surface_at(rest.x, rest.y), Surface.Type.FAIRWAY)
	assert_lt(rest.distance_to(cup), turn.distance_to(cup), "past the turn")


func test_the_slow_motion_eases_the_playback_not_the_ball() -> void:
	var m := _main()
	m.play_intro()
	var intro := m.intro
	var t := intro.tuning
	var predicted := ShotPrediction.run_launch(intro.course, t.rng_seed, intro.launch, null, null,
			intro.hole.cup)
	var flight_s: float = intro.time_of_tick(intro.land_tick()) - intro.strike_time()
	assert_gt(flight_s, float(intro.land_tick()) / Ball.TICK_HZ + 1.0,
			"the flight plays back over a second longer than its ticks")
	assert_almost_eq(intro.slow_rate_at(0.0), 1.0, 0.001, "full speed off the tee")
	var centre: float = float(intro.apex_tick()) / Ball.TICK_HZ + t.slow_center_s
	assert_almost_eq(intro.slow_rate_at(centre), t.slow_rate, 0.001, "slowest just past the apex")
	assert_almost_eq(intro.slow_rate_at(float(predicted.ticks) / Ball.TICK_HZ), t.roll_rate, 0.001,
			"a little quicker on the roll out")
	# At the slowest, a frame moves the ball slow_rate of a tick.
	var at := intro.time_of_tick(roundi(centre * Ball.TICK_HZ))
	_run_to(m, at)
	var before: float = intro.ball_tick()
	intro.advance(STEP)
	assert_almost_eq(intro.ball_tick() - before, t.slow_rate, 0.03)
	# The live ball steps whole ticks, the same as the prediction's.
	assert_eq(intro.shot_view.ball.steps, floori(intro.ball_tick() + 1e-4))


func test_the_drawn_track_and_start_line_leave_the_raised_tee_without_a_step() -> void:
	var m := _main()
	m.play_intro()
	var intro := m.intro
	var field: HeightField = intro.shot_view.ball.field
	var tee := field.tile_center(intro.hole.tee)
	assert_gt(field.height_at(tee.x, tee.y), field.height_at(tee.x, tee.y - 15.0),
			"the tee stands above the ground in front of it")
	_run_to(m, intro.title_time())
	for line: PackedVector2Array in [intro.track_world().slice(0, intro.land_tick()), intro.guide_world()]:
		assert_gt(line.size(), 100)
		var worst := 0.0
		for i: int in range(1, line.size() - 1):
			worst = maxf(worst, (line[i + 1] - 2.0 * line[i] + line[i - 1]).length())
		gut.p("worst bend %.3f px" % worst)
		# A step down off the tee (Iso.STEP_PX a height step) would bend it by about that.
		assert_lt(worst, 1.0, "no kink: worst bend %.2f px a point" % worst)
	var start := Iso.point_to_screen(field.iso_point(intro.launch.start))
	assert_almost_eq(intro.track_world()[0], start, Vector2.ONE * 0.01, "from the ball on the tee")
	assert_almost_eq(intro.guide_world()[0], start, Vector2.ONE * 0.01)


func test_the_camera_frames_the_corner_then_leads_the_ball() -> void:
	var m := _main()
	m.play_intro()
	var intro := m.intro
	var field: HeightField = intro.shot_view.ball.field
	_run_to(m, intro.strike_time() - STEP)
	var cam: Camera2D = intro.camera
	var size := cam.get_viewport_rect().size / cam.zoom
	var view := Rect2(cam.position - size * 0.5, size)
	var turn: Vector2 = GuestHole.turn_of(intro.course, intro.hole)
	var end: Vector2 = OpeningFlyover.Trail.guide_end_of(intro.launch)
	var rest := ShotPrediction.run_launch(intro.course, intro.tuning.rng_seed, intro.launch, null,
			null, intro.hole.cup).rest
	for p: Vector2 in [field.tile_center(intro.hole.tee), turn, end, Vector2(rest.x, rest.y)]:
		assert_true(view.has_point(intro.world_point(p)), "the swing's frame shows %s" % p)
	# In flight the camera looks ahead of the ball down the line, never behind it.
	var line := intro.guide_world()
	var u := (line[-1] - line[0]).normalized()
	var t := intro.strike_time() + 0.5
	var land := intro.time_of_tick(intro.land_tick())
	var behind := 0
	while t < land:
		_run_to(m, t)
		if (cam.position - intro.shadow_world()).dot(u) <= 0.0:
			behind += 1
		t += 0.25
	assert_eq(behind, 0, "the camera leads the ball through its flight")
	assert_gt(cam.zoom.x, intro.aim_frame()[1], "nearer in flight than the corner frame")


# --- skipping ---

func test_any_key_or_click_skips_at_any_moment_and_leaves_the_menu_as_without_it() -> void:
	HintSettings.mark_intro_seen(HINTS)
	var plain := _main()
	plain.open_at_start()
	var want := _snapshot(plain)
	var moments: Array[float] = [0.0, 2.0, 7.0, 11.0, -1.0, -2.0, -3.0]
	for i: int in moments.size():
		if FileAccess.file_exists(HINTS):
			DirAccess.remove_absolute(HINTS)
		var m := _main()
		m.open_at_start()
		var at: float = moments[i]
		if at == -1.0:
			at = m.intro.strike_time() - 0.1
		elif at == -2.0:
			at = m.intro.strike_time() + 1.5
		elif at == -3.0:
			at = m.intro.title_time() + 0.5
		_run_to(m, at)
		assert_true(m.intro.playing, "still playing at %.1f s" % at)
		# Not watch_signals: GUT's watcher stalls clearing an object the test freed itself.
		var ends: Array[bool] = []
		m.intro.finished.connect(func(skipped: bool) -> void: ends.append(skipped))
		if i % 2 == 0:
			_tap(m, [KEY_SPACE, KEY_ESCAPE, KEY_TAB, KEY_ENTER][i / 2 % 4])
		else:
			_click(m)
		assert_false(m.intro.playing, "skipped at %.1f s" % at)
		assert_eq(ends, [true] as Array[bool], "finished once, skipped")
		await wait_frames(1)  # the intro's world is freed at the frame's end
		var got := _snapshot(m)
		for k: String in want:
			assert_eq(got[k], want[k], "%s after a skip at %.1f s" % [k, at])
		m.queue_free()


func test_moving_the_mouse_does_not_skip() -> void:
	var m := _main()
	m.play_intro()
	var e := InputEventMouseMotion.new()
	e.position = Vector2(100, 100)
	e.relative = Vector2(30, 0)
	m.get_viewport().push_input(e)
	assert_true(m.intro.playing)


func test_a_key_skipping_the_intro_reaches_nothing_under_it() -> void:
	var m := _main()
	m.build_tool.builder.place_tee(1, Vector2i(3, 10), 3)
	m.build_tool.builder.place_cup(1, Vector2i(15, 10))
	m.play_intro()
	_tap(m, KEY_TAB)
	assert_false(m.intro.playing)
	assert_eq(m.mode, Main.Mode.BUILD, "Tab skipped the intro and did not start Play")
	assert_true(m.main_menu.visible)


# --- Watch intro ---

func test_watch_intro_from_the_menu_by_keyboard_replays_it_and_comes_back() -> void:
	HintSettings.mark_intro_seen(HINTS)
	var m := _main()
	m.open_at_start()
	await wait_frames(2)  # the containers lay the buttons out
	var buttons := m.main_menu.main_buttons()
	var watch := buttons[MainMenu.WATCH_INTRO_INDEX]
	assert_eq(watch.text, "Watch intro")
	# Down from the top reaches it (Goals is hidden on a fixture course, so it is skipped).
	var guard := 0
	while m.get_viewport().gui_get_focus_owner() != watch and guard < buttons.size():
		_tap(m, KEY_DOWN)
		guard += 1
	assert_same(m.get_viewport().gui_get_focus_owner(), watch, "the arrows reach Watch intro")
	_tap(m, KEY_ENTER)
	assert_true(m.intro.playing, "Enter plays it")
	assert_false(m.main_menu.visible)
	assert_eq(m.guest_sim.speed, 0.0, "the day stays held")
	_tap(m, KEY_SPACE)
	assert_false(m.intro.playing, "a key skips it")
	assert_true(m.main_menu.visible, "back to the menu")
	assert_same(m.get_viewport().gui_get_focus_owner(), watch, "focus back on Watch intro")


func test_watch_intro_played_through_comes_back_to_the_menu_on_it() -> void:
	HintSettings.mark_intro_seen(HINTS)
	var m := _main()
	m.open_at_start()
	m.main_menu.main_buttons()[MainMenu.WATCH_INTRO_INDEX].pressed.emit()
	assert_true(m.intro.playing)
	_run_out(m)
	assert_true(m.main_menu.visible)
	assert_same(m.get_viewport().gui_get_focus_owner(),
			m.main_menu.main_buttons()[MainMenu.WATCH_INTRO_INDEX])


func test_watch_intro_from_play_keeps_the_round_and_its_music() -> void:
	var m := _main()
	m.build_tool.builder.place_tee(1, Vector2i(3, 10), 3)
	m.build_tool.builder.place_cup(1, Vector2i(15, 10))
	m.set_mode(Main.Mode.PLAY)
	var ball_at: Vector2 = m.swing_control.ball_at
	m.open_menu()
	m.main_menu.main_buttons()[MainMenu.WATCH_INTRO_INDEX].pressed.emit()
	assert_eq(m.game_audio.music_track, GameAudio.Track.BUILD, "Scaffold for the intro")
	assert_false(m.swing_panel.is_visible_in_tree(), "Play's HUD hidden")
	_run_out(m)
	assert_eq(m.mode, Main.Mode.PLAY)
	assert_eq(m.swing_control.ball_at, ball_at, "the ball where it was")
	assert_eq(m.game_audio.music_track, GameAudio.Track.PLAY, "Progress again")
	assert_true(m.swing_panel.is_visible_in_tree())


# --- the player's game ---

func test_the_players_course_and_save_are_untouched() -> void:
	var m := _main()
	m.build_tool.builder.place_tee(1, Vector2i(3, 10), 3)
	m.build_tool.builder.place_cup(1, Vector2i(15, 10))
	assert_eq(m.save_game(), OK)
	var bytes := FileAccess.get_file_as_bytes(SAVE)
	var course := m.course
	var hash_before := course.content_hash()
	var undo := m.build_tool.builder.can_undo()
	m.play_intro()
	_run_out(m)
	await wait_frames(1)
	assert_same(m.course, course, "the same course")
	assert_eq(course.content_hash(), hash_before, "unchanged")
	assert_eq(m.build_tool.builder.can_undo(), undo, "no edit on the undo stack")
	assert_eq(FileAccess.get_file_as_bytes(SAVE), bytes, "the save file byte for byte")
	assert_false(DirAccess.dir_exists_absolute(AUTOSAVES), "no autosave written")
	assert_null(m.intro.world, "the intro's world is gone")
