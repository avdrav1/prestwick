extends GutTest
## E3-S57: the contour overlay over the whole course in Play (course/topo_overlay.gd).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


## The main scene on GreenViewShot's tiered course (a 40 x 32 plot with a two-step and a
## one-step tier), in `mode`.
func _main(mode: Main.Mode = Main.Mode.PLAY) -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(GreenViewShot.course("tiered").course)
	m.set_mode(mode)
	m.swing_control.set_process(false)
	m.set_process(false)
	m.camera.tracking = false
	return m


func test_off_in_build_on_in_play_and_the_key_toggles_it() -> void:
	var m := _main(Main.Mode.BUILD)
	var topo := m.course_view.topo
	assert_false(topo.visible, "never drawn in Build")
	assert_eq(topo.rows().size(), 0, "nothing laid out in Build")
	# The key does nothing in Build.
	var ev := InputEventAction.new()
	ev.action = TopoOverlay.TOGGLE_ACTION
	ev.pressed = true
	topo._unhandled_input(ev)
	assert_false(topo.user_hidden)
	assert_false(topo.visible)
	m.set_mode(Main.Mode.PLAY)
	assert_true(topo.visible, "on by default in Play")
	assert_gt(topo.rows().size(), 0, "and drawn")
	topo._unhandled_input(ev)
	assert_true(topo.user_hidden, "toggle_topo hides it")
	assert_false(topo.visible)
	topo._unhandled_input(ev)
	assert_true(topo.visible, "and shows it again")
	topo.toggle()
	m.set_mode(Main.Mode.BUILD)
	m.set_mode(Main.Mode.PLAY)
	assert_false(topo.visible, "the player's choice holds across modes")
	topo.toggle()
	m.set_mode(Main.Mode.BUILD)
	assert_false(topo.visible)
	# T is the key.
	var keys: Array[int] = []
	for e: InputEvent in InputMap.action_get_events(TopoOverlay.TOGGLE_ACTION):
		if e is InputEventKey:
			keys.append((e as InputEventKey).physical_keycode)
	assert_eq(keys, [KEY_T] as Array[int])


func test_its_lines_are_the_tracers_for_the_visible_window() -> void:
	var m := _main()
	var topo := m.course_view.topo
	for z: float in [0.175, 0.5, 1.0, 2.0]:
		m.camera.set_zoom_level(z)
		m.camera.position = m.tile_world(Vector2i(22, 14))
		topo.refresh()
		var view := topo.visible_window()
		assert_true(view.size.x > 0 and view.size.y > 0)
		assert_true(topo.traced_window.encloses(view), "the visible tiles are traced at %.3fx" % z)
		var levels := topo.levels_for(topo.traced_window)
		var traced := ContourTracer.trace_levels(m.swing_control.field, levels, topo.traced_window, topo.tuning.subdiv)
		var want := 0
		for lines: Array in traced:
			want += lines.size()
		assert_gt(want, 0)
		assert_eq(topo.line_count(), want, "the tracer's line count at %.3fx" % z)


func test_whole_step_lines_lie_on_their_terrace_so_they_sit_on_the_ground() -> void:
	# At the default whole-step levels a line runs on top of the tiles at its own level (the
	# terrace's falling edge) wherever the ground rises one step at a time, so drawing it on the
	# tile top (D17) is drawing it at its own height, unbroken.
	var m := _main()
	var c := CourseData.create(30, 30, Surface.Type.ROUGH, 2)
	for y: int in c.height:
		for x: int in c.width:
			var d := maxi(absi(x - 15), absi(y - 13))
			c.set_tile(x, y, 2 + clampi(4 - d / 2, 0, 4), Surface.Type.ROUGH)
	m.set_mode(Main.Mode.BUILD)
	m.show_course(c)
	m.set_mode(Main.Mode.PLAY)
	m.set_process(false)
	m.camera.tracking = false
	m.camera.set_zoom_level(0.5)
	m.camera.position = m.tile_world(Vector2i(15, 13))
	var topo := m.course_view.topo
	topo.refresh()
	assert_eq(topo.tuning.placement, TopoTuning.Placement.GROUND)
	assert_eq(topo.tuning.offset, 0.0)
	var field := m.swing_control.field
	var levels: Array[float] = []
	var count := 0
	for entry: Array in topo.lines:
		var level: float = entry[0]
		levels.append(level)
		for line: PackedVector2Array in entry[1]:
			for i: int in range(1, line.size()):
				var mid := (line[i - 1] + line[i]) * 0.5
				var t := field.tile_at(mid.x, mid.y)
				assert_eq(float(c.get_height(t.x, t.y)), level, "the piece at %s on its terrace" % mid)
				count += 1
	assert_eq(levels, [3.0, 4.0, 5.0, 6.0] as Array[float])
	assert_gt(count, 40)
	# Down a multi-step bank the levels between fall between the centres, off any terrace of
	# their own: drawn on the tile under them, at the bank's top or its foot.
	var tiered := _main()
	tiered.course_view.topo.refresh()
	var tc := tiered.course
	var tf := tiered.swing_control.field
	for entry: Array in tiered.course_view.topo.lines:
		var level: float = entry[0]
		for line: PackedVector2Array in entry[1]:
			for i: int in range(1, line.size()):
				var mid := (line[i - 1] + line[i]) * 0.5
				var t := tf.tile_at(mid.x, mid.y)
				var h := tc.get_height(t.x, t.y)
				if h == level:
					continue
				var bank := false
				# (A piece cut at a tile's corner may meet the bank across the diagonal.)
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var n := t + Vector2i(dx, dy)
						if tc.in_bounds(n.x, n.y) and absi(tc.get_height(n.x, n.y) - h) >= 2:
							bank = true
				assert_true(bank, "off its terrace only beside a bank, at %s" % mid)


func test_rows_sort_after_the_tops_and_before_objects() -> void:
	var m := _main()
	var topo := m.course_view.topo
	topo.refresh()
	assert_true(topo.y_sort_enabled)
	assert_eq(topo.get_parent(), m.course_view, "Y-sorted with the terrain")
	var c := m.course
	for row: Node2D in topo.rows():
		var key := row.position.y
		var base := key - TopoOverlay.SORT_BIAS
		# A top's key (Iso.top_sort_key): depth (a multiple of 16) plus 2h + 1, an odd remainder.
		assert_almost_eq(base, float(roundi(base)), 0.0001)
		assert_eq(roundi(base) % 16 % 2, 1, "a top's key")
		assert_gt(key, base, "over the top")
		assert_lt(key, base + 0.5, "under an object on that tile (Iso.object_sort_key: the top's + 0.5)")
	assert_gt(TopoOverlay.SORT_BIAS, 0.0)
	assert_lt(TopoOverlay.SORT_BIAS, 0.5, "objects sort at the top's key + 0.5")
	# The flag on the cup and the ball sort after the rows of their own tiles.
	var cup := m.swing_control.cup_tile()
	var flag_key := Iso.object_sort_key(Vector2(cup), c.get_height(cup.x, cup.y))
	assert_gt(flag_key, Iso.top_sort_key(cup, c.get_height(cup.x, cup.y)) + TopoOverlay.SORT_BIAS)


func test_it_does_not_trace_or_lay_out_again_each_frame() -> void:
	var m := _main()
	var topo := m.course_view.topo
	m.camera.set_zoom_level(0.5)
	m.camera.position = m.tile_world(Vector2i(22, 14))
	await wait_frames(3)
	var traces := topo.trace_count
	var layouts := topo.layout_count
	await wait_frames(10)
	assert_eq(topo.trace_count, traces, "a still view never traces again")
	assert_eq(topo.layout_count, layouts, "nor lays out again")
	# A small pan inside the traced window costs nothing either.
	m.camera.position += Vector2(40, 20)
	await wait_frames(3)
	assert_eq(topo.trace_count, traces)
	assert_eq(topo.layout_count, layouts)
	# A zoom step lays out again (screen-px widths and ticks), without tracing.
	m.camera.set_zoom_level(1.0)
	await wait_frames(2)
	assert_eq(topo.trace_count, traces)
	assert_eq(topo.layout_count, layouts + 1)


func test_it_only_reads_the_course() -> void:
	var m := _main()
	var c := m.course
	var before := CourseSave.to_json(c)
	m.course_view.topo.refresh()
	m.course_view.topo.mark_dirty()
	m.course_view.topo.refresh()
	assert_eq(CourseSave.to_json(c), before)
