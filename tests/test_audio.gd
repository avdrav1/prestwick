extends GutTest
## E5-S4: the sound. The files scripts/gen_audio.py makes load and the beds loop; the buses
## exist; each sound hook fires on its event (a strike says its lie, a touchdown its surface,
## trees, water, OB and the cup theirs, a guest's verdict its sting); the music drops out during
## a swing; the volumes persist in user://; the F2 panel works by keyboard; the main scene
## starts the music and the bed.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SETTINGS := "user://test_audio_settings.cfg"
const ROW_Y := 27.5

var _params: BallParams


func before_each() -> void:
	_params = BallParams.load_default()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	AudioSettings.new().apply()


func _audio() -> GameAudio:
	var a := GameAudio.new()
	a.settings_path = SETTINGS
	add_child_autofree(a)
	a.set_process(false)
	return a


## A shot view, a swing control and a GameAudio bound to them, no feed.
func _rig(course: CourseData, ball_tile: Vector2i) -> Array:
	var view := ShotView.new()
	add_child_autofree(view)
	view.set_process(false)
	var aim := AimView.new()
	add_child_autofree(aim)
	var sc := SwingControl.new()
	add_child_autofree(sc)
	sc.set_process(false)
	sc.bind(view, aim)
	sc.begin(course, ball_tile, 0.0)
	sc.active = true
	var a := _audio()
	a.bind(sc, view, null)
	return [a, sc, view]


func _course(fill: Surface.Type, width: int = 40, height: int = 11) -> CourseData:
	return CourseData.create(width, height, fill, 0)


func _band(course: CourseData, x0: int, x1: int, surface: Surface.Type) -> void:
	for y in course.height:
		for x in range(x0, x1 + 1):
			course.set_tile(x, y, course.get_height(x, y), surface)


func _carry(carry: float, launch_deg: float) -> Vector3:
	var speed := sqrt(carry * _params.gravity / sin(deg_to_rad(2.0 * launch_deg)))
	return Ball.launch_velocity(speed, launch_deg, 0.0)


## Runs the view's ball to rest, the audio polling each frame.
func _run(a: GameAudio, view: ShotView) -> void:
	var frames := 0
	while view.playing and frames < 5000:
		view.advance(1.0 / 60.0)
		a.advance(1.0 / 60.0)
		frames += 1


func _fire(course: CourseData, carry: float, launch_deg: float = 30.0) -> Array:
	var rig := _rig(course, Vector2i(1, 5))
	var view: ShotView = rig[2]
	view.fire(course, Vector3(7.5, ROW_Y, 0.0), _carry(carry, launch_deg), 7)
	_run(rig[0], view)
	return rig


# --- files and buses -------------------------------------------------------------------

func test_every_sound_file_loads() -> void:
	var a := _audio()
	var ids: Array[StringName] = [GameAudio.MUSIC, GameAudio.AMBIENT, GameAudio.PUTT, GameAudio.SPLASH,
			GameAudio.TREES, GameAudio.OOB, GameAudio.CUP, GameAudio.PRAISE, GameAudio.COMPLAINT]
	ids.append_array(GameAudio.STRIKE.values())
	ids.append_array(GameAudio.LAND.values())
	for id in ids:
		assert_not_null(a.sound(id), "audio/%s.wav loads" % id)


func test_the_beds_loop_and_the_one_shots_do_not() -> void:
	var a := _audio()
	for id: StringName in [GameAudio.MUSIC, GameAudio.AMBIENT]:
		var s := a.sound(id) as AudioStreamWAV
		assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops (its smpl chunk)" % id)
	for id: StringName in [GameAudio.PUTT, GameAudio.SPLASH, GameAudio.PRAISE]:
		assert_eq((a.sound(id) as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s plays once" % id)


func test_the_bus_layout_has_master_music_ambient_and_sfx() -> void:
	for bus in AudioSettings.BUSES:
		assert_gt(AudioServer.get_bus_index(bus), -1, "bus %s" % bus)


func test_players_sit_on_their_buses() -> void:
	var a := _audio()
	assert_eq(a.music_player.bus, &"Music")
	assert_eq(a.ambient_player.bus, &"Ambient")
	for p in a.sfx_players:
		assert_eq(p.bus, &"SFX")


func test_every_surface_has_a_touchdown_sound_and_every_lie_a_strike() -> void:
	for s in Surface.COUNT:
		assert_true(GameAudio.LAND.has(s), "%s has a touchdown sound" % Surface.name_of(s))
	for s: Surface.Type in [Surface.Type.TEE, Surface.Type.FAIRWAY, Surface.Type.ROUGH,
			Surface.Type.BUNKER, Surface.Type.CART_PATH, Surface.Type.GREEN]:
		assert_true(GameAudio.STRIKE.has(s), "%s has a strike" % Surface.name_of(s))


func test_each_surface_sounds_different() -> void:
	# Pillar 2: no two lies share a strike, and only the tee lands like the fairway.
	var strikes := {}
	for id: StringName in GameAudio.STRIKE.values():
		strikes[id] = true
	assert_eq(strikes.size(), GameAudio.STRIKE.size(), "one strike per lie")
	var lands := {}
	for id: StringName in GameAudio.LAND.values():
		lands[id] = true
	assert_eq(lands.size(), GameAudio.LAND.size() - 1, "one touchdown per surface, the tee's the fairway's")


# --- hooks -----------------------------------------------------------------------------

func test_a_strike_says_its_lie() -> void:
	var want := {
		Surface.Type.TEE: &"strike_tee", Surface.Type.FAIRWAY: &"strike_fairway",
		Surface.Type.ROUGH: &"strike_rough", Surface.Type.BUNKER: &"strike_bunker",
		Surface.Type.CART_PATH: &"strike_cart_path", Surface.Type.GREEN: &"putt",
	}
	for lie: Surface.Type in want:
		var course := _course(Surface.Type.FAIRWAY)
		course.set_tile(1, 5, 0, lie)
		var rig := _rig(course, Vector2i(1, 5))
		var a: GameAudio = rig[0]
		var sc: SwingControl = rig[1]
		assert_eq(sc.lie_surface(), lie)
		sc.swing.set_perfect()
		sc._strike()
		assert_eq(a.history.front() if not a.history.is_empty() else &"", want[lie],
				"a strike from %s" % Surface.name_of(lie))


func test_a_touchdown_says_its_surface() -> void:
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.GREEN,
			Surface.Type.BUNKER, Surface.Type.CART_PATH]:
		var course := _course(Surface.Type.FAIRWAY)
		_band(course, 15, 39, s)
		var rig := _fire(course, 100.0)
		var a: GameAudio = rig[0]
		assert_eq(a.history.front() if not a.history.is_empty() else &"", GameAudio.LAND[s],
				"a ball landing on %s" % Surface.name_of(s))


func test_water_splashes_once() -> void:
	var course := _course(Surface.Type.FAIRWAY)
	_band(course, 15, 25, Surface.Type.WATER)
	var a: GameAudio = _fire(course, 100.0)[0]
	assert_eq(a.history, [GameAudio.SPLASH] as Array[StringName], "one splash, the drop says nothing more")


func test_out_of_bounds_says_so_once() -> void:
	var course := _course(Surface.Type.FAIRWAY)
	_band(course, 15, 39, Surface.Type.OOB)
	var a: GameAudio = _fire(course, 100.0)[0]
	assert_eq(a.history, [GameAudio.OOB] as Array[StringName])


func test_a_ball_rolling_into_water_splashes_when_it_stops_there() -> void:
	# Lands on the fairway short of the water and runs in: the touchdown, then the splash.
	var course := _course(Surface.Type.FAIRWAY)
	_band(course, 18, 39, Surface.Type.WATER)
	var a: GameAudio = _fire(course, 70.0, 12.0)[0]
	assert_eq(a.history, [&"land_fairway", GameAudio.SPLASH] as Array[StringName])


func test_trees_rustle_when_they_block_the_flight() -> void:
	var course := _course(Surface.Type.FAIRWAY)
	_band(course, 3, 4, Surface.Type.TREES)
	var rig := _fire(course, 100.0, 12.0)
	var view: ShotView = rig[2]
	assert_true(view.ball.scattered, "the trees block this flight")
	var a: GameAudio = rig[0]
	assert_eq(a.history.front() if not a.history.is_empty() else &"", GameAudio.TREES)
	assert_eq(a.history.count(GameAudio.TREES), 1, "once")


func test_a_holed_putt_plays_the_cup_and_no_touchdown() -> void:
	var course := _course(Surface.Type.GREEN)
	var model := ShotModel.new()
	var field := HeightField.new(course, model.params)
	var cup := Vector2i(3, 5)
	var at := Vector2(7.5, ROW_Y)
	var speed := -1.0
	for k in 200:
		var v := 0.5 + k * 0.1
		var b := Ball.new(course, 1)
		b.set_cup(cup)
		model.putt(field, model.clubs.putter(), v, at, 0.0).apply(b)
		b.run_to_rest()
		if b.holed:
			speed = v
			break
	assert_gt(speed, 0.0, "some putt along the row holes")
	var rig := _rig(course, Vector2i(1, 5))
	var a: GameAudio = rig[0]
	var view: ShotView = rig[2]
	var shot := model.putt(field, model.clubs.putter(), speed, at, 0.0)
	view.fire_launch(course, shot, 1, cup)
	a._on_struck(shot)
	_run(a, view)
	assert_eq(a.history, [GameAudio.PUTT, GameAudio.CUP] as Array[StringName])


func test_music_drops_out_during_a_swing_and_comes_back() -> void:
	var rig := _rig(_course(Surface.Type.FAIRWAY), Vector2i(1, 5))
	var a: GameAudio = rig[0]
	var sc: SwingControl = rig[1]
	a.advance(0.1)
	assert_eq(a.music_offset_db, 0.0, "full before the swing")
	sc.swing.click()
	assert_true(a.music_ducked(), "the first click starts the swing")
	a.advance(a.tuning.music_fade_out_s + 0.01)
	assert_almost_eq(a.music_offset_db, a.tuning.music_swing_db, 0.01, "down within the fade out")
	assert_almost_eq(a.music_player.volume_db, a.tuning.music_level_db + a.tuning.music_swing_db, 0.01)
	sc.swing.reset()
	assert_false(a.music_ducked())
	a.advance(a.tuning.music_fade_in_s * 0.5)
	assert_lt(a.music_offset_db, 0.0, "it fades back, not jumps")
	a.advance(a.tuning.music_fade_in_s * 0.5 + 0.01)
	assert_almost_eq(a.music_offset_db, 0.0, 0.01, "full again")


func test_music_stays_down_while_the_ball_moves() -> void:
	var rig := _rig(_course(Surface.Type.FAIRWAY), Vector2i(1, 5))
	var a: GameAudio = rig[0]
	var sc: SwingControl = rig[1]
	sc.swing.set_perfect()
	sc._strike()
	assert_true(sc.is_ball_moving())
	assert_true(a.music_ducked(), "the swing is over, the ball is not")


func test_praise_and_complaint_stings_with_a_gap() -> void:
	var a := _audio()
	var feed := ReactionFeed.new(50, 20)
	var sc := SwingControl.new()
	add_child_autofree(sc)
	var view := ShotView.new()
	add_child_autofree(view)
	a.bind(sc, view, feed)
	var e := ReactionFeed.Entry.new()
	e.kind = GuestReaction.Kind.PRAISE
	feed.added.emit(e)
	assert_eq(a.history, [GameAudio.PRAISE] as Array[StringName])
	var c := ReactionFeed.Entry.new()
	c.kind = GuestReaction.Kind.COMPLAINT
	feed.added.emit(c)
	assert_eq(a.history.size(), 1, "a second sting within the gap is dropped")
	a.advance(a.tuning.sting_min_gap_s)
	feed.added.emit(c)
	assert_eq(a.history.back(), GameAudio.COMPLAINT, "after the gap a complaint stings")
	a.advance(a.tuning.sting_min_gap_s)
	var n := ReactionFeed.Entry.new()
	n.kind = GuestReaction.Kind.NEUTRAL
	feed.added.emit(n)
	assert_eq(a.history.size(), 2, "a neutral is quiet")


# --- settings --------------------------------------------------------------------------

func test_defaults_come_from_the_tuning() -> void:
	var t := AudioTuning.load_default()
	var s := AudioSettings.load_from(SETTINGS, t)
	for bus in AudioSettings.BUSES:
		assert_eq(s.volume(bus), t.default_volume(bus), "default %s" % bus)


func test_volumes_persist_and_apply() -> void:
	var a := _audio()
	a.set_volume(&"Music", 0.3)
	a.set_volume(&"SFX", 0.0)
	a.set_volume(&"Ambient", 1.7)
	assert_true(FileAccess.file_exists(SETTINGS), "saved in user://")
	var back := AudioSettings.load_from(SETTINGS)
	assert_almost_eq(back.volume(&"Music"), 0.3, 0.0001)
	assert_eq(back.volume(&"SFX"), 0.0)
	assert_eq(back.volume(&"Ambient"), 1.0, "clamped to 1")
	var music := AudioServer.get_bus_index(&"Music")
	assert_almost_eq(AudioServer.get_bus_volume_db(music), linear_to_db(0.3), 0.01, "applied to the bus")
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "0 mutes")
	# A new GameAudio (the next launch) reads them back.
	var next := _audio()
	assert_almost_eq(next.volume(&"Music"), 0.3, 0.0001)


func test_a_broken_settings_file_falls_back_to_the_defaults() -> void:
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	f.store_string("[volume]\nMusic=\"loud\"\nnot a config")
	f.close()
	var s := AudioSettings.load_from(SETTINGS)
	assert_eq(s.volume(&"Music"), AudioTuning.load_default().default_music)


# --- the panel -------------------------------------------------------------------------

func _panel(a: GameAudio) -> AudioPanel:
	var p := AudioPanel.new()
	add_child_autofree(p)
	p.bind(a)
	return p


func _action(name: StringName) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


func test_f2_opens_the_panel_with_focus_and_escape_closes_it() -> void:
	var a := _audio()
	var p := _panel(a)
	assert_false(p.visible)
	p._unhandled_input(_action(AudioPanel.ACTION))
	assert_true(p.visible, "F2 opens it")
	assert_eq(p.get_viewport().gui_get_focus_owner(), p.sliders[&"Master"], "focus on the first slider")
	p._input(_action(&"ui_cancel"))
	assert_false(p.visible, "Escape closes it")
	p._unhandled_input(_action(AudioPanel.ACTION))
	p._unhandled_input(_action(AudioPanel.ACTION))
	assert_false(p.visible, "F2 again closes it")


func test_a_slider_sets_and_saves_its_bus() -> void:
	var a := _audio()
	var p := _panel(a)
	p.open()
	assert_eq((p.sliders[&"Music"] as HSlider).value, roundf(a.volume(&"Music") * 100.0), "shows the volume")
	(p.sliders[&"Music"] as HSlider).value = 25.0
	assert_almost_eq(a.volume(&"Music"), 0.25, 0.0001)
	assert_almost_eq(AudioSettings.load_from(SETTINGS).volume(&"Music"), 0.25, 0.0001, "saved")


func test_the_sliders_chain_by_up_and_down() -> void:
	var p := _panel(_audio())
	var master: HSlider = p.sliders[&"Master"]
	assert_eq(master.get_node(master.focus_neighbor_bottom), p.sliders[&"Music"])
	assert_eq(master.get_node(master.focus_neighbor_top), p.close_button)


# --- the main scene --------------------------------------------------------------------

func test_the_main_scene_plays_the_music_and_the_bed() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	assert_not_null(m.game_audio.music_player.stream)
	assert_true(m.game_audio.music_player.playing, "music")
	assert_true(m.game_audio.ambient_player.playing, "ambient bed")
	assert_eq(m.audio_panel._audio, m.game_audio, "the panel is bound")


func _tap(m: Main, keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		m.get_viewport().push_input(e)


func test_the_main_menu_opens_the_sound_panel_by_keyboard_and_comes_back() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.guest_sim.set_process(false)
	m.open_menu()
	await wait_frames(2)
	var sound := m.main_menu.main_buttons()[MainMenu.SOUND_INDEX]
	assert_eq(sound.text, "Sound settings")
	for i in MainMenu.SOUND_INDEX:
		_tap(m, KEY_DOWN)
	assert_same(m.get_viewport().gui_get_focus_owner(), sound, "the arrows reach it")
	_tap(m, KEY_ENTER)
	assert_true(m.audio_panel.visible, "Enter opens the sound panel")
	assert_false(m.main_menu.visible)
	assert_same(m.get_viewport().gui_get_focus_owner(), m.audio_panel.sliders[&"Master"])
	_tap(m, KEY_ESCAPE)
	assert_false(m.audio_panel.visible, "Esc closes the panel")
	assert_true(m.main_menu.visible, "back on the menu")
	assert_same(m.get_viewport().gui_get_focus_owner(), sound, "on Sound settings")
