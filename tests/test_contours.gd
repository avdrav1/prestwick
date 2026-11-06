extends GutTest
## E3-S56: ContourTracer traces the lines where HeightField.height_at equals a level, by
## marching squares on the tile-centre grid.

const YPT: float = 5.0


func _field(c: CourseData) -> HeightField:
	return HeightField.new(c, BallParams.load_default())


## A 20 x 12 plot at height 2 rising one step a tile along +x from x = 6 to height 7 at 11.
func _ramp() -> CourseData:
	var c := CourseData.create(20, 12, Surface.Type.GREEN, 2)
	for y: int in c.height:
		for x: int in c.width:
			c.set_tile(x, y, clampi(x - 4, 2, 7), Surface.Type.GREEN)
	return c


## A 16 x 16 plot at height 2 with a hill: a 3 x 3 block at 4 round (8, 8), its centre at 5.
func _hill() -> CourseData:
	var c := CourseData.create(16, 16, Surface.Type.GREEN, 2)
	for y: int in range(7, 10):
		for x: int in range(7, 10):
			c.set_tile(x, y, 5 if x == 8 and y == 8 else 4, Surface.Type.GREEN)
	return c


func _steps_at(f: HeightField, p: Vector2) -> float:
	return f.height_at(p.x, p.y) / f.yards_per_step


func test_a_ramps_line_lies_where_the_ground_is_at_its_level() -> void:
	var c := _ramp()
	var f := _field(c)
	var window := Rect2i(0, 0, c.width, c.height)
	for level: float in [2.5, 3.0, 4.25, 6.5]:
		for sub: int in [1, 3]:
			var lines := ContourTracer.trace(f, level, window, sub)
			assert_eq(lines.size(), 1, "one line across the ramp at %.2f (subdiv %d)" % [level, sub])
			var worst := 0.0
			for line: PackedVector2Array in lines:
				for p: Vector2 in line:
					worst = maxf(worst, absf(_steps_at(f, p) - level))
				# It crosses the whole window, edge to edge.
				assert_almost_eq(minf(line[0].y, line[line.size() - 1].y), 0.0, 0.001)
				assert_almost_eq(maxf(line[0].y, line[line.size() - 1].y), c.height * YPT, 0.001)
			assert_lt(worst, 0.001, "every vertex at the level %.2f" % level)
	# The 2.5 line is the boundary between the tiles at 2 and 3 (x = 7 * 5 yd), and the 3.0
	# line runs through the centres of the height-3 tiles: the terrace's falling edge.
	var half := ContourTracer.trace(f, 2.5, window)[0]
	var whole := ContourTracer.trace(f, 3.0, window)[0]
	for p: Vector2 in half:
		assert_almost_eq(p.x, 35.0, 0.01)
	for p: Vector2 in whole:
		assert_almost_eq(p.x, 37.5, 0.01)


func test_a_curved_lines_chords_stay_near_the_level() -> void:
	# Inside a cell the level line is a hyperbola; sub-cells keep the chords on it.
	var c := _hill()
	var f := _field(c)
	var lines := ContourTracer.trace(f, 3.0, Rect2i(0, 0, 16, 16), 4)
	assert_eq(lines.size(), 1)
	var worst := 0.0
	var line := lines[0]
	for i: int in range(1, line.size()):
		worst = maxf(worst, absf(_steps_at(f, (line[i - 1] + line[i]) * 0.5) - 3.0))
	assert_lt(worst, 0.05, "chord midpoints within 0.05 steps of the level")


func test_a_flat_window_has_no_lines() -> void:
	var c := CourseData.create(12, 12, Surface.Type.GREEN, 3)
	var f := _field(c)
	for level: float in [2.0, 2.5, 3.0, 3.5]:
		assert_eq(ContourTracer.trace(f, level, Rect2i(0, 0, 12, 12), 2).size(), 0, "none at %.1f" % level)
	# A window on the flat part of the hill's plot sees none either.
	var h := _field(_hill())
	for level: float in [2.5, 3.0, 4.0]:
		assert_eq(ContourTracer.trace(h, level, Rect2i(0, 0, 5, 5)).size(), 0)
	assert_eq(ContourTracer.levels_between(2, 2, 0.5).size(), 0, "no levels on a flat window")


func test_a_closed_hill_gives_a_closed_loop_round_its_top() -> void:
	var f := _field(_hill())
	var top := f.tile_center(Vector2i(8, 8))
	for level: float in [2.5, 3.0, 3.5, 4.0, 4.5]:
		var lines := ContourTracer.trace(f, level, Rect2i(0, 0, 16, 16), 2)
		assert_eq(lines.size(), 1, "one line at %.1f" % level)
		var loop := lines[0]
		assert_eq(loop[0], loop[loop.size() - 1], "closed at %.1f" % level)
		assert_true(Geometry2D.is_point_in_polygon(top, loop), "round the top at %.1f" % level)
	# The summit is a point: its own level leaves no line.
	assert_eq(ContourTracer.trace(f, 5.0, Rect2i(0, 0, 16, 16), 2).size(), 0)
	# Clipped by a window through the hill, the loop opens into pieces inside the window.
	var cut := ContourTracer.trace(f, 3.0, Rect2i(0, 0, 8, 16), 2)
	assert_gt(cut.size(), 0)
	for piece: PackedVector2Array in cut:
		for p: Vector2 in piece:
			assert_lte(p.x, 40.0 + 0.001)


func test_ticks_point_downhill() -> void:
	for c: CourseData in [_ramp(), _hill()]:
		var f := _field(c)
		var window := Rect2i(0, 0, c.width, c.height)
		var count := 0
		for level: float in [2.5, 3.0, 3.5, 4.5]:
			for line: PackedVector2Array in ContourTracer.trace(f, level, window, 3):
				var t := ContourTracer.ticks(line, 2.0, 0.5)
				for k: int in range(0, t.size(), 2):
					count += 1
					var foot := _steps_at(f, t[k])
					var tip := _steps_at(f, t[k + 1])
					assert_lt(tip, foot, "the tick at %s falls" % t[k])
					# And the ground the other way rises (or holds, on a terrace edge).
					var back := _steps_at(f, t[k] * 2.0 - t[k + 1])
					assert_gte(back, foot - 0.001)
		assert_gt(count, 10)


func test_levels_between() -> void:
	assert_eq(ContourTracer.levels_between(2, 4, 0.5), PackedFloat32Array([2.5, 3.0, 3.5, 4.0]))
	assert_eq(ContourTracer.levels_between(2, 5, 1.0), PackedFloat32Array([3.0, 4.0, 5.0]))
	assert_eq(ContourTracer.levels_between(0, 2, 1.0, 0.5), PackedFloat32Array([0.5, 1.5]))
	assert_eq(ContourTracer.height_range(_field(_hill()), Rect2i(6, 6, 2, 2)), Vector2i(2, 5))


func test_it_only_reads_the_course() -> void:
	var c := _hill()
	var heights := PackedInt32Array()
	for y: int in c.height:
		for x: int in c.width:
			heights.append(c.get_height(x, y))
	ContourTracer.trace_levels(_field(c), PackedFloat32Array([2.5, 3.0, 4.0]), Rect2i(0, 0, 16, 16), 3)
	var after := PackedInt32Array()
	for y: int in c.height:
		for x: int in c.width:
			after.append(c.get_height(x, y))
	assert_eq(after, heights)
