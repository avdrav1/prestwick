extends GutTest
## E9-S1 (D65): guests walk by time. The base `walk_yd_per_s` over fairway, rough, green, tee
## and painted out of bounds, `walk_surface_speed` times it on each surface (a cart path
## quickest; trees, bunkers and water slower), `walk_climb_s_per_step` for each height step
## climbed from one tile to the next; and a walk follows a cart path only when that is quicker
## than the straight line. docs/design.md Guests and reactions, Walking. (The path search and
## its cache are tested in tests/test_guest_brain.gd, walking.)

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")

var tuning: GuestTuning


func before_all() -> void:
	tuning = GuestTuning.load_default()


## A 40 x 12 strip of `surface` at height 2.
func _strip(surface: Surface.Type = Surface.Type.ROUGH) -> CourseData:
	return CourseData.create(40, 12, surface, 2)


func _paint(c: CourseData, cells: Array, surface: Surface.Type) -> void:
	var b := CourseBuilder.new(c)
	b.level_water = false  # D66: water as a plain paint here, not a flood
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
	# E14-S2: water is never walked (test_a_pond_on_the_line_is_walked_round).
	for s: Surface.Type in [Surface.Type.TREES, Surface.Type.BUNKER]:
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


# --- E12-S1 (D68): why a walk takes no path, the reach, what a path edit reaches ---

## A walk along row 2 of the strip, tile (2, 2) to tile (36, 2): 170 yd.
const WHY_FROM := Vector2(12.5, 12.5)
const WHY_TO := Vector2(182.5, 12.5)


func _why_text(c: CourseData, from: Vector2 = WHY_FROM, to: Vector2 = WHY_TO) -> String:
	assert_false(GuestWalk.route(c, from, to, tuning).on_path, "the walk takes no path")
	return GuestWalk.why(c, from, to, tuning).text("the 4th green", "the 5th tee")


func test_the_reach_is_40_yd_and_the_share_is_gone() -> void:
	assert_eq(tuning.cart_path_reach_yd, 40.0, "D68: about 40 yd")
	assert_false("walk_path_share" in tuning, "D68: the half-the-walk share is retired")
	# A path whose ends stand 37 yd from each end of the walk, quicker than walking across: taken.
	var c := _strip()
	_paint(c, _row(3, 9, 29), Surface.Type.CART_PATH)
	var w := GuestWalk.route(c, WHY_FROM, WHY_TO, tuning)
	assert_true(w.on_path, "within 40 yd of both ends")
	assert_lt(w.path_share(), 0.7, "even with a good part of the walk off the path")


func test_why_names_each_reason() -> void:
	assert_eq(_why_text(_strip()), "no cart path")
	var far := _strip()
	_paint(far, _row(10, 15, 20), Surface.Type.CART_PATH)
	assert_eq(_why_text(far), "no path within reach of the 4th green")
	# From beside the green to tile (20, 3): its centre 80.2 yd from the tee, 40.2 past reach.
	var short_of_tee := _strip()
	_paint(short_of_tee, _row(3, 3, 20), Surface.Type.CART_PATH)
	assert_eq(_why_text(short_of_tee), "path stops 41 yd short of the 5th tee")
	var why := GuestWalk.why(short_of_tee, WHY_FROM, WHY_TO, tuning)
	assert_eq(why.kind, GuestWalk.Reason.Kind.SHORT)
	assert_eq(why.gap_yd, 41)
	assert_false(why.at_start)
	# The same path laid from the tee's end stops short of the green.
	var short_of_green := _strip()
	_paint(short_of_green, _row(3, 18, 35), Surface.Type.CART_PATH)
	assert_eq(_why_text(short_of_green), "path stops 41 yd short of the 4th green")
	# A path that joins both ends but swings 9 rows away and back: slower than walking across.
	var slow := CourseData.create(40, 20, Surface.Type.ROUGH, 2)
	var cells := []
	for y in range(3, 13):
		cells.append(Vector2i(3, y))
		cells.append(Vector2i(35, y))
	cells.append_array(_row(12, 3, 35))
	_paint(slow, cells, Surface.Type.CART_PATH)
	assert_eq(_why_text(slow), "path is slower than walking across")
	# Through a cache, the same answer, kept until the path changes.
	var cache := GuestWalk.Cache.new()
	var kept := GuestWalk.why(short_of_tee, WHY_FROM, WHY_TO, tuning, 5.0, cache)
	assert_same(GuestWalk.why(short_of_tee, WHY_FROM, WHY_TO, tuning, 5.0, cache), kept)
	_paint(short_of_tee, _row(3, 21, 35), Surface.Type.CART_PATH)
	assert_true(GuestWalk.route(short_of_tee, WHY_FROM, WHY_TO, tuning, 5.0, cache).on_path,
			"extended to the tee, the path serves the walk")


## The reason the flood of the piece alone gives (_piece_nearest, as `why` read it before E18-S5).
func _why_by_flood(c: CourseData, from: Vector2, to: Vector2) -> Array:
	var grid := GuestWalk.path_grid(c)
	var reach: float = tuning.cart_path_reach_yd
	var a := GuestWalk._nearest_path_tile(c, from, reach, 5.0)
	var b := GuestWalk._nearest_path_tile(c, to, reach, 5.0)
	if grid.find(1) < 0:
		return [GuestWalk.Reason.Kind.NO_PATH]
	if a.x < 0 and b.x < 0:
		return [GuestWalk.Reason.Kind.NOT_NEAR, 0, true]
	var from_start := a.x >= 0
	var origin := a if from_start else b
	var goal := b if from_start else a
	var near := GuestWalk._piece_nearest(c, grid, origin, to if from_start else from, goal, 5.0)
	if origin == goal or near.y > 0.0:
		return [GuestWalk.Reason.Kind.SLOWER]
	return [GuestWalk.Reason.Kind.SHORT, maxi(1, ceili(near.x - reach - 1e-6)), not from_start,
			Vector2i(int(near.z), int(near.w))]


func _reason_of(r: GuestWalk.Reason) -> Array:
	match r.kind:
		GuestWalk.Reason.Kind.NO_PATH, GuestWalk.Reason.Kind.SLOWER:
			return [r.kind]
		GuestWalk.Reason.Kind.NOT_NEAR:
			return [r.kind, 0, r.at_start]
	return [r.kind, r.gap_yd, r.at_start, r.near_tile]


## E18-S5 (D71): on E3-S15's lattice, one cart path piece over the whole map, `why` answers by a
## search from one end's path tile toward the other's, not a flood of the piece (15.4 ms on
## 256 x 160, which failed the D52 gate), and on pieces apart, a gap or a lattice cut in two it
## gives the flood's reason every time.
func test_why_on_a_lattice_answers_as_the_flood_without_flooding() -> void:
	var c := CourseData.create(128, 80, Surface.Type.ROUGH, 0)
	var cells := []
	for y: int in c.height:
		for x: int in c.width:
			if (x % 3 == 0 or y % 3 == 0) and not (x >= 60 and x <= 64 and y >= 20):
				cells.append(Vector2i(x, y))
	_paint(c, cells, Surface.Type.CART_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	var spent: Array[float] = []
	var kinds := {}
	for k: int in 40:
		var from := Vector2(rng.randf_range(5, 635), rng.randf_range(5, 395))
		var to := Vector2(rng.randf_range(5, 635), rng.randf_range(5, 395))
		var t0 := Time.get_ticks_usec()
		var r := GuestWalk.why(c, from, to, tuning)
		spent.append((Time.get_ticks_usec() - t0) / 1000.0)
		assert_eq(_reason_of(r), _why_by_flood(c, from, to), "%s to %s" % [from, to])
		kinds[r.kind] = true
	assert_true(kinds.has(GuestWalk.Reason.Kind.SLOWER), "walks on one piece")
	spent.sort()
	gut.p("E18-S5: why on a 128 x 80 lattice, median %.2f ms, worst %.2f" % [spent[20], spent[-1]])
	# Two pieces, a gap and none in reach, as the flood answers them.
	var two := _strip()
	_paint(two, _row(3, 3, 12) + _row(3, 15, 35), Surface.Type.CART_PATH)
	assert_eq(_reason_of(GuestWalk.why(two, WHY_FROM, WHY_TO, tuning)), _why_by_flood(two, WHY_FROM, WHY_TO))
	assert_false(GuestWalk._joins(GuestWalk.path_grid(two), two.width + 2, Vector2i(3, 3), Vector2i(35, 3)),
			"no search joins two pieces")
	assert_true(GuestWalk._joins(GuestWalk.path_grid(two), two.width + 2, Vector2i(15, 3), Vector2i(35, 3)))


func test_the_path_grid_marks_every_cart_path_and_bridge_tile() -> void:
	var c := LandGenerator.generate(7)
	_paint(c, _row(5, 2, 40) + _row(9, 30, 90), Surface.Type.CART_PATH)
	var grid := GuestWalk.path_grid(c)
	var w: int = c.width + 2
	var bad: int = 0
	for y: int in range(-1, c.height + 1):
		for x: int in range(-1, c.width + 1):
			var want: int = 1 if GuestWalk._is_path(c, Vector2i(x, y)) else 0
			if grid[(y + 1) * w + x + 1] != want:
				bad += 1
	assert_eq(bad, 0)


## E18-S5: the nearest path tile read from the path grid's bytes (a route through a cache) is the
## one read tile by tile through CourseData, ties and all: scattered path tiles, bridges, points
## by every edge and corner of the map and off it, and a course with no path at all.
func test_the_nearest_path_tile_from_the_grid_is_the_one_read_tile_by_tile() -> void:
	var c := LandGenerator.generate(7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var cells := []
	for k: int in 400:
		cells.append(Vector2i(rng.randi_range(0, c.width - 1), rng.randi_range(0, c.height - 1)))
	cells.append_array(_row(0, 0, 20) + _row(c.height - 1, c.width - 20, c.width - 1))
	_paint(c, cells, Surface.Type.CART_PATH)
	var bridges := 0
	for i: int in CourseValidator.surface_indices(c.packed_tiles(), Surface.Type.WATER):
		if i % 7 == 0:
			@warning_ignore("integer_division")
			c.set_bridge(Vector2i(i % c.width, i / c.width), true)
			bridges += 1
	assert_gt(bridges, 0, "some water bridged")
	var reach: float = tuning.cart_path_reach_yd
	var side: float = c.width * 5.0
	var points: Array[Vector2] = [Vector2(0, 0), Vector2(side, side), Vector2(-30, 40),
			Vector2(side + 30, 7), Vector2(2.5, side - 2.5), Vector2(-60, -60)]
	for k: int in 600:
		points.append(Vector2(rng.randf_range(-50, side + 50), rng.randf_range(-50, side + 50)))
	var found := 0
	var bad: Array = []
	for course: CourseData in [c, CourseData.create(60, 40, Surface.Type.ROUGH, 2)]:
		var grid := GuestWalk.path_grid(course)
		for at: Vector2 in points:
			var want := GuestWalk._nearest_path_tile(course, at, reach, 5.0)
			if GuestWalk._nearest_path_tile(course, at, reach, 5.0, grid) != want:
				bad.append(at)
			if want.x >= 0:
				found += 1
	assert_eq(bad, [], "points where the two differ")
	assert_gt(found, 100, "many points have a path tile in reach")


func test_a_path_edit_reaches_a_walk_on_its_piece_or_within_reach_of_its_ends() -> void:
	var c := _strip()
	_paint(c, _row(3, 3, 20), Surface.Type.CART_PATH)
	var reaches := func(cell: Vector2i) -> bool:
		return GuestWalk.path_edit_reaches(c, WHY_FROM, WHY_TO, [cell] as Array[Vector2i], tuning)
	assert_true(reaches.call(Vector2i(21, 3)), "laid on the end of the piece by the green")
	assert_true(reaches.call(Vector2i(21, 4)), "diagonally beside it")
	assert_true(reaches.call(Vector2i(10, 3)), "taken up from the piece")
	assert_true(reaches.call(Vector2i(34, 5)), "within reach of the tee")
	assert_false(reaches.call(Vector2i(28, 9)), "beside no piece the walk can use, out of reach")
	assert_false(reaches.call(Vector2i(23, 3)), "two tiles past the piece's end")


func test_round_walks_are_the_walks_guests_take_to_each_tee() -> void:
	var c: CourseData = GuestCourse.far_next_tee(false)
	var walks := GuestWalk.round_walks(c)
	assert_eq(walks.size(), 2)
	assert_eq(walks[0].from, (Vector2(c.clubhouse_door()) + Vector2(0.5, 0.5)) * 5.0)
	assert_eq([walks[0].from_hole, walks[0].to_hole, walks[0].to_slot], [0, 1, 0])
	assert_eq(walks[1].from, (Vector2(c.holes[0].cup) + Vector2(0.5, 0.5)) * 5.0)
	assert_eq(walks[1].to, (Vector2(c.holes[1].tee) + Vector2(0.5, 0.5)) * 5.0)
	assert_eq([walks[1].from_hole, walks[1].to_hole, walks[1].to_slot], [1, 2, 1])
	# A closed hole is skipped, as GuestBrain.next_open_hole skips it.
	c.holes[0].open = false
	walks = GuestWalk.round_walks(c)
	assert_eq(walks.size(), 1)
	assert_eq([walks[0].from_hole, walks[0].to_hole], [0, 2])
	# The brain walks the same: every record of hole 2 left from where round_walks says.
	c.holes[0].open = true
	var brain := GuestBrain.new(c, 3, tuning)
	brain.run_day()
	for g: Guest in brain.guests:
		for r: Guest.HoleRecord in g.records:
			var w: Dictionary = GuestWalk.round_walks(c)[r.number - 1]
			assert_eq(r.walk_from_hole, int(w.from_hole))
			assert_almost_eq(r.walk_s, GuestWalk.route(c, w.from, w.to, tuning).duration, 1e-6)


# --- E14-S2 (D69): guests never wade ---

## A 40 x 24 map of rough at 2 with a pond, x 15 to 24, y 6 to 17, across the walk along row 12.
func _pond() -> CourseData:
	var c := CourseData.create(40, 24, Surface.Type.ROUGH, 2)
	for y: int in range(6, 18):
		for x: int in range(15, 25):
			c.set_tile(x, y, 2, Surface.Type.WATER)
	return c


## True when no point of `w`, sampled every `step` s of its time, ends and corners included,
## stands on a tile of open water (water with no bridge).
func _dry(c: CourseData, w: GuestWalk, step: float = 0.01) -> bool:
	var t := 0.0
	while t <= w.duration + step:
		var p := w.point_at_time(minf(t, w.duration))
		if not GuestWalk.walkable(c, floori(p.x / 5.0), floori(p.y / 5.0)):
			return false
		t += step
	for p: Vector2 in w.points:
		if not GuestWalk.walkable(c, floori(p.x / 5.0), floori(p.y / 5.0)):
			return false
	return true


func test_a_pond_on_the_line_is_walked_round() -> void:
	var c := _pond()
	var from := Vector2(27.5, 62.5)
	var to := Vector2(172.5, 62.5)
	var w := GuestWalk.route(c, from, to, tuning)
	assert_true(w.searched, "the straight walk wades, so the route is searched")
	assert_true(_dry(c, w), "no point of the walk is on the pond")
	assert_eq(w.end(), to, "it gets there")
	assert_eq(w.goal, to)
	assert_false(w.on_path)
	assert_gt(w.length, 145.0, "longer than the straight 145 yd")
	assert_lt(w.length, 200.0, "but round the near end, not far out: %.1f yd" % w.length)
	assert_lt(w.points.size(), 8, "straightened, not a tile staircase: %s" % w.points)
	# The route round is no slower than the tile route it was straightened from.
	var raw := GuestWalk._dry_route(c, from, to, tuning, 5.0, GuestWalk.DryGrid.new(c, tuning))
	assert_eq(raw, w.points, "the search gives the walk's points")
	var again := GuestWalk.route(c, from, to, tuning)
	assert_eq(again.points, w.points, "the same route every time")
	assert_eq(again.duration, w.duration)


func test_a_bridge_across_the_pond_is_taken_as_a_path() -> void:
	var c := _pond()
	var round := GuestWalk.route(c, Vector2(27.5, 62.5), Vector2(172.5, 62.5), tuning)
	var b := CourseBuilder.new(c)
	b.begin_stroke()
	for x: int in range(15, 25):
		b.paint(Vector2i(x, 12), Surface.Type.CART_PATH, 1)
	b.end_stroke()
	assert_eq(c.bridge_cells().size(), 10)
	var w := GuestWalk.route(c, Vector2(27.5, 62.5), Vector2(172.5, 62.5), tuning)
	assert_true(_dry(c, w), "over the bridge, not the water")
	assert_almost_eq(w.path_yd, 50.0, 1e-4, "its 50 yd on the bridge")
	assert_lt(w.duration, round.duration, "quicker than the walk round")
	var slant := GuestWalk.route(c, Vector2(27.5, 47.5), Vector2(172.5, 77.5), tuning)
	assert_true(slant.searched, "a slanting walk would wade off the bridge: searched")
	assert_true(_dry(c, slant), "it finds the bridge")
	assert_true(slant.on_path, "a searched walk over a bridge follows a path")
	assert_gt(slant.path_yd, 45.0)
	assert_almost_eq(w.duration, 95.0 / tuning.walk_yd_per_s + 50.0 / tuning.walk_speed(Surface.Type.CART_PATH),
			1e-6, "the bridge walks at cart path's speed")


func test_a_cart_path_walk_that_would_wade_is_not_taken() -> void:
	# A path in reach of both ends, but its last leg cuts across the pond's corner.
	var c := _pond()
	var b := CourseBuilder.new(c)
	b.level_water = false
	b.begin_stroke()
	for y: int in range(2, 6):
		b.paint(Vector2i(12, y), Surface.Type.CART_PATH, 1)
	for x: int in range(12, 30):
		b.paint(Vector2i(x, 5), Surface.Type.CART_PATH, 1)
	b.end_stroke()
	var w := GuestWalk.route(c, Vector2(57.5, 22.5), Vector2(112.5, 72.5), tuning)
	assert_true(_dry(c, w), "never on the pond")


func test_a_point_no_dry_route_reaches_ends_at_the_nearest_reachable_tile() -> void:
	var c := _pond()
	c.set_tile(20, 12, 2, Surface.Type.ROUGH)  # an island in the pond
	var to := Vector2(102.5, 62.5)
	var w := GuestWalk.route(c, Vector2(27.5, 62.5), to, tuning)
	assert_true(_dry(c, w), "it does not wade out to the island")
	assert_eq(w.goal, to, "the goal stays the island")
	assert_ne(w.end(), to)
	assert_almost_eq(w.end().x, 127.5, 1e-4, "on the bank's tile nearest it, x 25")
	assert_almost_eq(w.end().y, 62.5, 1e-4)


func test_dry_routes_are_cached_until_the_course_changes() -> void:
	var c := _pond()
	var cache := GuestWalk.Cache.new()
	var a := GuestWalk.route(c, Vector2(27.5, 62.5), Vector2(172.5, 62.5), tuning, 5.0, cache)
	assert_eq(cache.dry.size(), 1, "the search is kept")
	var b := GuestWalk.route(c, Vector2(27.5, 62.5), Vector2(172.5, 62.5), tuning, 5.0, cache)
	assert_eq(b.points, a.points, "a kept route is the fresh one")
	var dry := GuestWalk.route(c, Vector2(27.5, 12.5), Vector2(172.5, 12.5), tuning, 5.0, cache)
	assert_false(dry.searched, "a dry straight walk searches nothing")
	assert_eq(cache.dry.size(), 1)
	var builder := CourseBuilder.new(c)
	builder.paint(Vector2i(16, 12), Surface.Type.CART_PATH, 1)
	GuestWalk.route(c, Vector2(27.5, 62.5), Vector2(172.5, 62.5), tuning, 5.0, cache)
	assert_eq(cache.dry.size(), 1, "an edit dropped the old route, the new one is kept")


func test_a_diagonal_never_cuts_a_corner_of_water() -> void:
	# Two water tiles meeting at a corner, the walk's tile route squeezing between them.
	var c := CourseData.create(20, 20, Surface.Type.ROUGH, 2)
	for y: int in 20:
		if y != 10:
			c.set_tile(10, y, 2, Surface.Type.WATER)
	c.set_tile(11, 9, 2, Surface.Type.WATER)
	var w := GuestWalk.route(c, Vector2(22.5, 27.5), Vector2(77.5, 77.5), tuning)
	assert_true(w.searched, "the straight walk wades")
	assert_true(_dry(c, w, 0.002), "through the one gap, round the corner tile: %s" % w.points)
	for i: int in range(1, w.points.size()):
		assert_true(GuestWalk._segment_dry(c, w.points[i - 1], w.points[i], 5.0), "segment %d of %s" % [i, w.points])


## E18-S5: the dry routes searched side by side (GuestWalk.prefetch_dry) are the ones route
## searches one at a time, and a route after them reads them and gives the same walk.
func test_prefetched_dry_routes_are_the_routes_searched_alone() -> void:
	var c := _pond()
	var to := Vector2(172.5, 62.5)
	var froms := PackedVector2Array([Vector2(27.5, 62.5), Vector2(31.2, 55.7), Vector2(22.5, 82.5),
			Vector2(172.5, 12.5), Vector2(27.5, 62.5)])
	var cache := GuestWalk.Cache.new()
	var n := GuestWalk.prefetch_dry(c, froms, to, tuning, 5.0, cache)
	assert_eq(n, 3, "three wade (one dry straight walk, one twice): searched once each")
	assert_eq(cache.dry.size(), 3)
	for from: Vector2 in froms:
		var alone := GuestWalk.route(c, from, to, tuning)
		var kept := GuestWalk.route(c, from, to, tuning, 5.0, cache)
		assert_eq(kept.points, alone.points, "from %s: the same route" % from)
		assert_eq(kept.duration, alone.duration)
		assert_eq(kept.searched, alone.searched)
		assert_eq(kept.path_yd, alone.path_yd)
	assert_eq(cache.dry.size(), 3, "every searched walk read its prefetched route")
	assert_eq(GuestWalk.prefetch_dry(c, froms, to, tuning, 5.0, cache), 0, "nothing left to search")
	var one := GuestWalk.Cache.new()
	assert_eq(GuestWalk.prefetch_dry(c, PackedVector2Array([froms[0]]), to, tuning, 5.0, one), 0,
			"one alone waits for its walk by default")
	assert_eq(GuestWalk.prefetch_dry(c, PackedVector2Array([froms[0]]), to, tuning, 5.0, one, 1), 1)
	assert_eq(one.dry[Vector4(froms[0].x, froms[0].y, to.x, to.y)],
			GuestWalk.route(c, froms[0], to, tuning).points)


## E18-S5: path_edit_reaches reads the squares round a walk's ends from the path grid; its
## answer is the one the tile-by-tile reading (_is_path through CourseData, as before) gives, on
## scattered path pieces, bridges and points by every edge of the map and off it.
func test_path_edit_reaches_from_the_grid_answers_as_tile_by_tile() -> void:
	var c := LandGenerator.generate(7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var cells := []
	for k: int in 60:
		var at := Vector2i(rng.randi_range(0, c.width - 1), rng.randi_range(0, c.height - 1))
		for d: int in rng.randi_range(1, 12):
			cells.append(at + Vector2i(d, 0))
	cells.append_array(_row(0, 0, 20) + _row(c.height - 1, c.width - 20, c.width - 1))
	_paint(c, cells, Surface.Type.CART_PATH)
	for i: int in CourseValidator.surface_indices(c.packed_tiles(), Surface.Type.WATER):
		if i % 5 == 0:
			@warning_ignore("integer_division")
			c.set_bridge(Vector2i(i % c.width, i / c.width), true)
	var side: float = c.width * 5.0
	var grid := GuestWalk.path_grid(c)
	var yes := 0
	for k: int in 300:
		var from := Vector2(rng.randf_range(-40, side + 40), rng.randf_range(-40, side + 40))
		var to := Vector2(rng.randf_range(-40, side + 40), rng.randf_range(-40, side + 40))
		var edit: Array[Vector2i] = [Vector2i(rng.randi_range(0, c.width - 1), rng.randi_range(0, c.height - 1))]
		edit.append(cells[rng.randi_range(0, cells.size() - 1)] + Vector2i(rng.randi_range(-1, 1), 1))
		var want := _reaches_tile_by_tile(c, from, to, edit, grid)
		yes += 1 if want else 0
		assert_eq(GuestWalk.path_edit_reaches(c, from, to, edit, tuning, 5.0, grid), want,
				"%s to %s, %s" % [from, to, edit])
		assert_eq(GuestWalk.path_edit_reaches(c, from, to, edit, tuning), want)
	assert_gt(yes, 5, "some edits reach their walk")
	assert_lt(yes, 280, "and some do not")


## path_edit_reaches as it read the course before E18-S5 (tile by tile through _is_path).
func _reaches_tile_by_tile(course: CourseData, from: Vector2, to: Vector2, cells: Array[Vector2i],
		grid: PackedByteArray) -> bool:
	var reach := tuning.cart_path_reach_yd
	for cell: Vector2i in cells:
		var cc := (Vector2(cell) + Vector2(0.5, 0.5)) * 5.0
		if cc.distance_to(from) <= reach or cc.distance_to(to) <= reach:
			return true
	var w := course.width + 2
	var seeds: Array = []
	var r := ceili(reach / 5.0) + 1
	for end: Vector2 in [from, to]:
		var at := Vector2i(floori(end.x / 5.0), floori(end.y / 5.0))
		for y in range(at.y - r, at.y + r + 1):
			for x in range(at.x - r, at.x + r + 1):
				var t := Vector2i(x, y)
				if GuestWalk._is_path(course, t) and ((Vector2(t) + Vector2(0.5, 0.5)) * 5.0).distance_to(end) <= reach:
					seeds.append((y + 1) * w + x + 1)
	if seeds.is_empty():
		return false
	var mark := {}
	for i: int in GuestWalk._piece(grid, w, seeds):
		mark[i] = true
	for cell: Vector2i in cells:
		var i := (cell.y + 1) * w + cell.x + 1
		if mark.has(i):
			return true
		for d: Vector2i in GuestWalk.NEIGHBOURS:
			if mark.has(i + d.y * w + d.x):
				return true
	return false
