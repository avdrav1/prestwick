extends GutTest
## E3-S57: the contour overlay over the whole course in Play (course/topo_overlay.gd); since
## E3-S59 drawn at its own heights, on the smooth ground (D50).

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


func test_every_line_is_drawn_at_its_own_height_on_the_ground() -> void:
	# E3-S59 (D50): the course view draws the bilinear ground the tracer follows, so each line is
	# drawn at its level, which is the ground's height where it runs: every drawn point, read
	# back off the screen at one of the levels, lands where the ground stands at that level.
	var m := _main()
	var c := CourseData.create(30, 30, Surface.Type.ROUGH, 2)
	for y: int in c.height:
		for x: int in c.width:
			var d := maxi(absi(x - 15), absi(y - 13))
			c.set_tile(x, y, 2 + clampi(4 - d / 2, 0, 4), Surface.Type.ROUGH)
	c.set_tile(3, 3, 2, Surface.Type.WATER)
	m.set_mode(Main.Mode.BUILD)
	m.show_course(c)
	m.set_mode(Main.Mode.PLAY)
	m.set_process(false)
	m.camera.tracking = false
	m.camera.set_zoom_level(0.5)
	m.camera.position = m.tile_world(Vector2i(15, 13))
	var topo := m.course_view.topo
	topo.refresh()
	assert_eq(topo.tuning.offset, 0.5, "a line half way up each step")
	var levels: Array[float] = []
	for entry: Array in topo.lines:
		levels.append(entry[0])
	assert_eq(levels, [2.5, 3.5, 4.5, 5.5] as Array[float])
	var count := 0
	var off := 0
	for row: Node2D in topo.rows():
		var pts := PackedVector2Array((row as TopoOverlay.Row).segs)
		# Each tick's first point is on its line; its foot runs downhill on the ground.
		var ticks := (row as TopoOverlay.Row).ticks
		for k: int in range(0, ticks.size(), 2):
			pts.append(ticks[k])
		for q: Vector2 in pts:
			var screen := q + row.position
			var best := INF
			for level: float in levels:
				var t := Iso.screen_to_tile(screen, level)
				best = minf(best, absf(TerrainMesh.bilinear(c, t) - level))
			count += 1
			# A piece cut at a tile edge ends on the tracer's chord, which stays within 0.05 steps
			# of the level (tests/test_contours.gd), and a tick starts on it: a pixel at most at 1x.
			if best > 0.08:
				off += 1
	assert_gt(count, 100)
	assert_eq(off, 0, "every point on the ground at its level")
	# Lines are unbroken: the pieces of one line meet end to end on screen.
	for entry: Array in topo.lines:
		for line: PackedVector2Array in entry[1]:
			for i: int in range(1, line.size()):
				var a := Iso.tile_to_screen(line[i - 1] / 5.0 - Vector2(0.5, 0.5), entry[0])
				var b := Iso.tile_to_screen(line[i] / 5.0 - Vector2(0.5, 0.5), entry[0])
				assert_lt(a.distance_to(b), float(Iso.TILE_W), "a chord, not a jump")


func test_no_line_is_drawn_over_water() -> void:
	var m := _main()
	var topo := m.course_view.topo
	var c := CourseData.create(20, 20, Surface.Type.ROUGH, 2)
	for y: int in range(5, 15):
		for x: int in range(5, 15):
			c.set_tile(x, y, 1, Surface.Type.WATER)
	m.set_mode(Main.Mode.BUILD)
	m.show_course(c)
	m.set_mode(Main.Mode.PLAY)
	m.set_process(false)
	m.camera.tracking = false
	m.camera.set_zoom_level(0.5)
	m.camera.position = m.tile_world(Vector2i(10, 10))
	topo.refresh()
	assert_gt(topo.line_count(), 0, "the bank round the pond is traced")
	for row: Node2D in topo.rows():
		var key := row.position.y - TopoOverlay.SORT_BIAS
		var r := roundi(key / Iso.HALF_H)
		# A row inside the pond's rows: every piece on it is on its land, not over the water.
		for q: Vector2 in (row as TopoOverlay.Row).segs:
			var t := Iso.screen_to_tile(q + row.position, 1.0)
			var cell := Vector2i(floori(t.x + 0.5), floori(t.y + 0.5))
			if cell.x + cell.y == r:
				assert_ne(c.get_surface(cell.x, cell.y), Surface.Type.WATER, "no piece at %s" % t)


func test_rows_sort_after_their_ground_and_before_objects() -> void:
	var m := _main()
	var topo := m.course_view.topo
	topo.refresh()
	assert_true(topo.y_sort_enabled)
	assert_eq(topo.get_parent(), m.course_view, "Y-sorted with the terrain")
	for row: Node2D in topo.rows():
		var key := row.position.y
		var base := key - TopoOverlay.SORT_BIAS
		# A row of ground's key (Iso.depth_key): a multiple of 16.
		assert_almost_eq(base, float(roundi(base)), 0.0001)
		assert_eq(roundi(base) % roundi(Iso.HALF_H), 0, "a row of ground's key")
	assert_gt(TopoOverlay.SORT_BIAS, 0.0, "over the row's ground")
	assert_lt(TopoOverlay.SORT_BIAS, 1.5, "under an object on it (Iso.object_sort_key: the row's + 1.5 or more)")
	# The flag on the cup and the ball sort after the rows of their own tiles.
	var cup := m.swing_control.cup_tile()
	var flag_key := Iso.object_sort_key(Vector2(cup), m.course.get_height(cup.x, cup.y))
	assert_gt(flag_key, Iso.depth_key(cup) + TopoOverlay.SORT_BIAS)


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
