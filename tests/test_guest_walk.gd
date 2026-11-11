extends GutTest
## E9-S1 (D65): guests walk by time. The base `walk_yd_per_s` over fairway, rough, green, tee
## and painted out of bounds, `walk_surface_speed` times it on each surface (a cart path
## quickest; trees, bunkers and water slower), `walk_climb_s_per_step` for each height step
## climbed from one tile to the next; and a walk follows a cart path only when that is quicker
## than the straight line. docs/design.md Guests and reactions, Walking. (The path search and
## its cache are tested in tests/test_guest_brain.gd, walking.)

var tuning: GuestTuning


func before_all() -> void:
	tuning = GuestTuning.load_default()


## A 40 x 12 strip of `surface` at height 2.
func _strip(surface: Surface.Type = Surface.Type.ROUGH) -> CourseData:
	return CourseData.create(40, 12, surface, 2)


func _paint(c: CourseData, cells: Array, surface: Surface.Type) -> void:
	var b := CourseBuilder.new(c)
	b.begin_stroke()
	for cell: Vector2i in cells:
		b.paint(cell, surface, 1)
	b.end_stroke()


## Row `y` from x0 to x1, both included.
func _row(y: int, x0: int, x1: int) -> Array:
	var out := []
	for x in range(x0, x1 + 1):
		out.append(Vector2i(x, y))
	return out


func test_the_tunables_are_read() -> void:
	assert_gt(tuning.walk_speed(Surface.Type.CART_PATH), tuning.walk_speed(Surface.Type.ROUGH),
			"a cart path is quicker than rough")
	for s: Surface.Type in [Surface.Type.TREES, Surface.Type.BUNKER, Surface.Type.WATER]:
		assert_lt(tuning.walk_speed(s), tuning.walk_speed(Surface.Type.ROUGH),
				"%s is slower than rough" % Surface.NAMES[s])
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE]:
		assert_eq(tuning.walk_speed(s), tuning.walk_yd_per_s, "%s walks at the base speed" % Surface.NAMES[s])
	assert_gt(tuning.walk_climb_s_per_step, 0.0)
	assert_eq(tuning.walk_top_yd_per_s(), tuning.walk_speed(Surface.Type.CART_PATH))


func test_a_walk_over_a_path_is_quicker_than_over_rough_by_the_tuned_factor() -> void:
	# The same 150 yd along row 2, once over rough and once along a path row (no detour).
	var from := Vector2(2.5, 12.5)
	var to := Vector2(152.5, 12.5)
	var rough := GuestWalk.route(_strip(), from, to, tuning)
	assert_almost_eq(rough.duration, 150.0 / tuning.walk_yd_per_s, 1e-6, "rough: the base speed")
	var c := _strip()
	_paint(c, _row(2, 0, 39), Surface.Type.CART_PATH)
	var path := GuestWalk.route(c, from, to, tuning)
	assert_almost_eq(path.length, 150.0, 1e-4, "along the line itself, which is the path")
	assert_almost_eq(path.duration, 150.0 / tuning.walk_speed(Surface.Type.CART_PATH), 1e-6)
	assert_almost_eq(rough.duration / path.duration,
			tuning.walk_surface_speed[Surface.Type.CART_PATH], 1e-6, "by the tuned factor")
	assert_almost_eq(path.straight_s, path.duration, 1e-6, "the straight line is on the path")
	# E9-S2: what the walk takes with no path laid, and how much of it is on path.
	assert_almost_eq(path.bare_s, rough.duration, 1e-6, "with no path, the base speed")
	assert_almost_eq(rough.bare_s, rough.duration, 1e-6)
	assert_almost_eq(path.path_share(), 1.0, 1e-6, "every yard on the path")
	assert_eq(rough.path_share(), 0.0)
	# Walked a second at a time, the path covers the factor's yards a second.
	var at := path.advance(1.0)
	assert_almost_eq(at.distance_to(from), tuning.walk_speed(Surface.Type.CART_PATH), 1e-4)
	var at_rough := rough.advance(1.0)
	assert_almost_eq(at_rough.distance_to(from), tuning.walk_yd_per_s, 1e-4)


func test_trees_bunkers_and_water_slow_a_walk_by_their_factors() -> void:
	# 10 tiles (50 yd) of each in the middle of a 150 yd rough walk.
	var from := Vector2(2.5, 12.5)
	var to := Vector2(152.5, 12.5)
	for s: Surface.Type in [Surface.Type.TREES, Surface.Type.BUNKER, Surface.Type.WATER]:
		var c := _strip()
		_paint(c, _row(2, 10, 19), s)
		var w := GuestWalk.route(c, from, to, tuning)
		assert_false(w.on_path)
		var want := 100.0 / tuning.walk_yd_per_s + 50.0 / tuning.walk_speed(s)
		assert_eq(c.get_height(15, 2), 2, "flat: no climb in it")
		assert_almost_eq(w.duration, want, 1e-6, "%s: 50 yd at its speed" % Surface.NAMES[s])
		assert_gt(w.duration, 150.0 / tuning.walk_yd_per_s, "slower than all rough")


func test_climbing_costs_time_and_going_down_does_not() -> void:
	# A hill three steps high, one step a tile up and down, across the line.
	var c := _strip()
	var b := CourseBuilder.new(c)
	for x: int in [14, 15, 16, 17, 18, 19, 20]:
		var up := 3 - absi(x - 17)
		for i in up:
			b.raise(Vector2i(x, 2), 1)
	assert_eq(c.get_height(17, 2), 5)
	var from := Vector2(2.5, 12.5)
	var to := Vector2(152.5, 12.5)
	var w := GuestWalk.route(c, from, to, tuning)
	var flat := 150.0 / tuning.walk_yd_per_s
	assert_almost_eq(w.duration, flat + 3 * tuning.walk_climb_s_per_step, 1e-6,
			"three steps up, three down: only the climb costs")
	var back := GuestWalk.route(c, to, from, tuning)
	assert_almost_eq(back.duration, w.duration, 1e-6, "the same hill either way")
	# The position is by time: at the climb's end the guest has walked fewer yards than on flat.
	var flat_w := GuestWalk.route(_strip(), from, to, tuning)
	var t := 0.5 * w.duration
	assert_lt(w.point_at_time(t).x, flat_w.point_at_time(t).x + 1e-6)
	assert_eq(w.point_at_time(w.duration), to)
	assert_eq(w.point_at_time(0.0), from)


func test_a_path_that_saves_time_is_taken_and_one_that_costs_time_is_not() -> void:
	var from := Vector2(12.5, 12.5)   # tile (2, 2)
	var to := Vector2(162.5, 12.5)    # tile (32, 2)
	# A path one row down: a little longer than the line, quicker by the path's speed.
	var near := _strip()
	_paint(near, _row(3, 3, 31), Surface.Type.CART_PATH)
	var straight := GuestWalk.route(_strip(), from, to, tuning)
	var w := GuestWalk.route(near, from, to, tuning)
	assert_true(w.on_path, "quicker along the path")
	assert_gt(w.length, straight.length)
	assert_lt(w.duration, straight.duration)
	# A path that swings 9 rows away and back: slower than walking straight, so it is not
	# taken.
	var c := CourseData.create(40, 20, Surface.Type.ROUGH, 2)
	var cells := []
	for y in range(3, 13):
		cells.append(Vector2i(3, y))
		cells.append(Vector2i(31, y))
	cells.append_array(_row(12, 3, 31))
	_paint(c, cells, Surface.Type.CART_PATH)
	var slow := GuestWalk.route(c, from, to, tuning)
	assert_false(slow.on_path, "slower than the straight line: not taken")
	assert_eq(slow.points, PackedVector2Array([from, to]))
	# Measured the other way round: the path's own time is over the straight walk's.
	var ends := PackedVector2Array()
	var times := PackedFloat64Array()
	var poly := PackedVector2Array([from])
	for y in range(3, 13):
		poly.append((Vector2(3, y) + Vector2(0.5, 0.5)) * 5.0)
	for x in range(4, 32):
		poly.append((Vector2(x, 12) + Vector2(0.5, 0.5)) * 5.0)
	for y in range(11, 2, -1):
		poly.append((Vector2(31, y) + Vector2(0.5, 0.5)) * 5.0)
	poly.append(to)
	var path_s := GuestWalk.time_pieces(c, poly, tuning, 5.0, ends, times)
	assert_gt(path_s, slow.duration, "but slower")
	# Through a wood the straight walk slows, and the same path is now the quicker way.
	var wood := c.copy()
	_paint(wood, _row(2, 5, 29), Surface.Type.TREES)
	var round_wood := GuestWalk.route(wood, from, to, tuning)
	assert_true(round_wood.on_path, "round the wood on the path")
	assert_lt(round_wood.duration, round_wood.straight_s)


func test_a_walk_steps_by_time_and_ends_where_it_should() -> void:
	var c := _strip()
	_paint(c, _row(2, 10, 19), Surface.Type.BUNKER)
	var from := Vector2(2.5, 12.5)
	var to := Vector2(152.5, 12.5)
	var w := GuestWalk.route(c, from, to, tuning)
	var prev := from
	var seconds := 0
	while not w.is_done():
		var p := w.advance(1.0)
		seconds += 1
		assert_lte(prev.distance_to(p), tuning.walk_top_yd_per_s() + 1e-4, "never past the top speed")
		assert_gt(p.x, prev.x - 1e-6, "always onward")
		prev = p
	assert_eq(seconds, ceili(w.duration))
	assert_eq(w.position(), to)
	assert_almost_eq(w.elapsed, w.duration, 1e-9)
	# A walk to where it stands takes no time.
	var none := GuestWalk.route(c, from, from, tuning)
	assert_eq(none.duration, 0.0)
	assert_true(none.is_done())
	assert_eq(none.position(), from)
