extends GutTest
## E10-S4 (D66): water finds its level. Painting water floods the basin the tile sits in (the
## tiles connected through their edges at the fill level or lower), flat at one step under the
## lowest rim tile; off the map and off owned land are drains, so water that would run off is
## refused. One undo step, water's price a tile changed. Tees, greens, a hole's tee or cup, the
## clubhouse and decor refuse a flood. Raise and lower skip water; lowering a tile to the level
## of water beside it spreads or drains that water in the same step. Loaded courses keep their
## water; generated ponds sit in hollows.

const W := Surface.Type.WATER
const R := Surface.Type.ROUGH

var _refusals: Array[String] = []
var _econ: EconomyTuning


func before_all() -> void:
	_econ = EconomyTuning.load_default()


func before_each() -> void:
	_refusals.clear()


## A `size` x `size` map of rough at `ground`, every parcel owned, with $`money`. The test's own
## fixture: written before any builder is made, as tests/fixtures do.
func _flat(size: int = 32, ground: int = 2, money: int = 5000) -> CourseData:
	var c := CourseData.create(size, size, R, ground)
	c.set_land_budget(money)
	return c


## Sets the tiles of `rect` to height `h` (rough), before a builder is made.
func _dig(c: CourseData, rect: Rect2i, h: int) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			c.set_tile(x, y, h, R)


func _builder(c: CourseData) -> CourseBuilder:
	var b := CourseBuilder.new(c)
	b.refused.connect(func(reason: String) -> void: _refusals.append(reason))
	return b


func _cells_of(c: CourseData, surface: Surface.Type) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in c.height:
		for x: int in c.width:
			if c.get_surface(x, y) == surface:
				out.append(Vector2i(x, y))
	return out


func _all(c: CourseData, rect: Rect2i, h: int, s: Surface.Type) -> bool:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if c.get_height(x, y) != h or c.get_surface(x, y) != s:
				return false
	return true


# --- the fill rule ---

func test_painting_water_in_a_hollow_fills_it_flat_as_one_undo_step() -> void:
	var c := _flat()
	_dig(c, Rect2i(10, 10, 3, 3), 1)
	c.set_tile(11, 11, 0, R)  # a deeper middle: the flood raises it to the level
	var b := _builder(c)
	var before: String = c.content_hash()
	var money: int = b.balance()
	assert_true(b.paint(Vector2i(10, 10), W, 1), "one dab on the hollow's corner")
	assert_true(_all(c, Rect2i(10, 10, 3, 3), 1, W), "the whole hollow is water, flat at 1")
	assert_eq(_cells_of(c, W).size(), 9, "nothing past the rim")
	assert_eq(b.balance(), money - 9 * _econ.price_of(W), "water's price for each tile flooded")
	assert_eq(b.undo_depth(), 1)
	assert_true(b.undo())
	assert_eq(c.content_hash(), before, "one undo puts the hollow back, the deep middle too")
	assert_eq(b.balance(), money)


func test_water_lies_one_step_under_the_lowest_rim() -> void:
	# A bowl in high ground: the hollow at 1, its rim at 4 but for a channel at 2 that runs to
	# the map's edge. The water stands at 1: at 2 it would run out down the channel.
	var c := _flat(32, 4)
	_dig(c, Rect2i(10, 10, 4, 4), 1)
	_dig(c, Rect2i(0, 11, 10, 1), 2)
	var b := _builder(c)
	assert_true(b.paint(Vector2i(12, 12), W, 1))
	assert_true(_all(c, Rect2i(10, 10, 4, 4), 1, W))
	assert_eq(_cells_of(c, W).size(), 16, "the channel at 2 stays dry")
	assert_true(_all(c, Rect2i(0, 11, 10, 1), 2, R))


func test_a_closed_channel_fills_with_the_hollow_up_to_the_next_rim() -> void:
	# The same bowl, but the channel stops a tile short of the edge: water rises to 3, one under
	# the rim at 4, over the hollow and the channel alike.
	var c := _flat(32, 4)
	_dig(c, Rect2i(10, 10, 4, 4), 1)
	_dig(c, Rect2i(1, 11, 9, 1), 2)
	var b := _builder(c)
	assert_true(b.paint(Vector2i(12, 12), W, 1))
	assert_true(_all(c, Rect2i(10, 10, 4, 4), 3, W))
	assert_true(_all(c, Rect2i(1, 11, 9, 1), 3, W))
	assert_eq(_cells_of(c, W).size(), 25)
	assert_eq(WaterLevel.fill(c, Vector2i(5, 11)).level, 3, "the same level from any tile in it")


func test_water_on_open_ground_runs_off_and_says_why() -> void:
	var c := _flat()
	var b := _builder(c)
	var money: int = b.balance()
	assert_false(b.paint(Vector2i(16, 16), W, 3), "flat ground reaches the map's edge")
	assert_eq(_refusals, [CourseBuilder.RUNS_OFF] as Array[String])
	assert_eq(_cells_of(c, W).size(), 0)
	assert_eq(b.balance(), money)
	assert_false(b.can_undo())


func test_water_on_a_peak_runs_off() -> void:
	var c := _flat()
	c.set_tile(16, 16, 5, R)
	var b := _builder(c)
	assert_false(b.paint(Vector2i(16, 16), W, 1))
	assert_eq(_refusals, [CourseBuilder.RUNS_OFF] as Array[String])
	assert_eq(c.get_surface(16, 16), R)


func test_unowned_land_is_a_drain() -> void:
	# Own only parcel (0, 0), tiles 0 to 15. A hollow touching the unowned parcel runs off;
	# one inside the owned parcel fills.
	var c := _flat()
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), p == 0 and q == 0)
	_dig(c, Rect2i(14, 4, 2, 2), 1)
	_dig(c, Rect2i(16, 4, 2, 2), 1)  # the same hollow runs on into unowned land
	_dig(c, Rect2i(5, 9, 2, 2), 1)
	var b := _builder(c)
	assert_false(b.paint(Vector2i(14, 4), W, 1), "next to unowned land")
	assert_eq(_refusals, [CourseBuilder.RUNS_OFF] as Array[String])
	assert_true(b.paint(Vector2i(5, 9), W, 1))
	assert_eq(_cells_of(c, W).size(), 4)


func test_a_hollow_on_the_map_edge_runs_off() -> void:
	var c := _flat()
	_dig(c, Rect2i(0, 8, 3, 3), 1)
	var b := _builder(c)
	assert_false(b.paint(Vector2i(1, 9), W, 1))
	assert_eq(_refusals, [CourseBuilder.RUNS_OFF] as Array[String])


func test_a_brush_floods_the_hollows_it_covers_and_skips_open_ground() -> void:
	var c := _flat()
	c.set_tile(10, 10, 1, R)
	c.set_tile(12, 12, 1, R)
	var b := _builder(c)
	assert_true(b.paint(Vector2i(11, 11), W, 3), "two one-tile hollows under a 3 x 3 brush")
	assert_eq(_cells_of(c, W), [Vector2i(10, 10), Vector2i(12, 12)] as Array[Vector2i])
	assert_eq(_refusals, [] as Array[String], "open ground under the brush is skipped quietly")
	assert_eq(b.paint_cost(Vector2i(11, 11), W, 3), 0, "water over water costs nothing")


func test_paint_cost_counts_the_flood() -> void:
	var c := _flat()
	_dig(c, Rect2i(10, 10, 4, 4), 1)
	var b := _builder(c)
	assert_eq(b.paint_cost(Vector2i(10, 10), W, 1), 16 * _econ.price_of(W))
	assert_eq(b.paint_cost(Vector2i(20, 20), W, 1), 0, "runs off: nothing to pay")


func test_a_flood_over_the_balance_is_refused_whole() -> void:
	var c := _flat(32, 2, 10 * EconomyTuning.load_default().price_of(Surface.Type.WATER))
	_dig(c, Rect2i(10, 10, 4, 4), 1)
	var b := _builder(c)
	assert_false(b.paint(Vector2i(10, 10), W, 1), "16 tiles, money for 10")
	assert_eq(_refusals.size(), 1)
	assert_string_starts_with(_refusals[0], "costs ")
	assert_eq(_cells_of(c, W).size(), 0)


func test_a_drag_is_one_undo_step_and_one_charge() -> void:
	var c := _flat()
	_dig(c, Rect2i(4, 4, 2, 2), 1)
	_dig(c, Rect2i(20, 4, 2, 2), 1)
	var b := _builder(c)
	var money: int = b.balance()
	b.begin_stroke()
	for x: int in range(4, 22):
		b.paint(Vector2i(x, 4), W, 1)
	b.end_stroke()
	assert_eq(_cells_of(c, W).size(), 8)
	assert_eq(b.undo_depth(), 1)
	assert_eq(b.balance(), money - 8 * _econ.price_of(W))
	b.undo()
	assert_eq(_cells_of(c, W).size(), 0)
	assert_eq(b.balance(), money)


# --- what a flood respects ---

func _refused_with(c: CourseData, b: CourseBuilder, at: Vector2i, reason: String) -> void:
	var before: String = c.content_hash()
	_refusals.clear()
	assert_false(b.paint(at, W, 1), reason)
	assert_eq(_refusals, [reason] as Array[String])
	assert_eq(c.content_hash(), before, "nothing flooded")


func test_greens_and_tees_refuse_a_flood() -> void:
	var c := _flat()
	_dig(c, Rect2i(10, 10, 4, 4), 1)
	c.set_tile(13, 13, 1, Surface.Type.GREEN)
	c.set_tile(10, 20, 1, R)
	c.set_tile(10, 20, 1, Surface.Type.TEE)
	var b := _builder(c)
	_refused_with(c, b, Vector2i(10, 10), CourseBuilder.FLOODS % "a green")
	_refused_with(c, b, Vector2i(10, 20), CourseBuilder.FLOODS % "a tee")


func test_a_holes_tee_or_cup_refuses_a_flood() -> void:
	var c := _flat()
	_dig(c, Rect2i(10, 10, 4, 4), 1)
	_dig(c, Rect2i(20, 10, 4, 4), 1)
	var b := _builder(c)
	assert_true(b.place_tee(2, Vector2i(11, 11), 3))
	assert_true(b.place_cup(2, Vector2i(21, 11), 3))
	_refused_with(c, b, Vector2i(10, 10), CourseBuilder.FLOODS % "hole 2's tee")
	_refused_with(c, b, Vector2i(20, 10), CourseBuilder.FLOODS % "hole 2's cup")


func test_the_clubhouse_and_decor_refuse_a_flood() -> void:
	var c := _flat()
	_dig(c, Rect2i(10, 10, 5, 5), 1)
	c.set_clubhouse(Vector2i(12, 12), 1)
	_dig(c, Rect2i(20, 20, 3, 3), 1)
	c.set_decor(Vector2i(21, 21), 0)
	var b := _builder(c)
	_refused_with(c, b, Vector2i(10, 10), CourseBuilder.FLOODS % "the clubhouse")
	_refused_with(c, b, Vector2i(20, 20), CourseBuilder.FLOODS % "decor")


func test_bunkers_trees_and_fairway_flood() -> void:
	var c := _flat()
	_dig(c, Rect2i(10, 10, 3, 1), 1)
	c.set_tile(10, 10, 1, Surface.Type.BUNKER)
	c.set_tile(11, 10, 1, Surface.Type.TREES)
	c.set_tile(12, 10, 1, Surface.Type.FAIRWAY)
	var b := _builder(c)
	assert_true(b.paint(Vector2i(10, 10), W, 1))
	assert_true(_all(c, Rect2i(10, 10, 3, 1), 1, W))


# --- raise and lower ---

func _pond(c: CourseData) -> CourseBuilder:
	_dig(c, Rect2i(10, 10, 4, 4), 1)
	var b := _builder(c)
	assert_true(b.paint(Vector2i(10, 10), W, 1))
	return b


func test_raise_and_lower_skip_water() -> void:
	var c := _flat()
	var b := _pond(c)
	var before: String = c.content_hash()
	assert_false(b.raise(Vector2i(11, 11), 1))
	assert_eq(_refusals, [CourseBuilder.KEEPS_LEVEL] as Array[String])
	assert_false(b.lower(Vector2i(12, 12), 1))
	assert_eq(c.content_hash(), before)
	# A 3 x 3 brush on the pond's corner moves its 5 dry tiles and none of its 4 water tiles.
	assert_true(b.raise(Vector2i(10, 10), 3))
	assert_true(_all(c, Rect2i(10, 10, 2, 2), 1, W))
	assert_eq(c.get_height(9, 9), 3)
	assert_eq(c.get_height(9, 11), 3)


func test_raising_beside_water_moves_no_water() -> void:
	var c := _flat()
	var b := _pond(c)
	assert_true(b.raise(Vector2i(9, 12), 1))
	assert_true(_all(c, Rect2i(10, 10, 4, 4), 1, W))
	assert_eq(_cells_of(c, W).size(), 16)


func test_lowering_a_rim_tile_to_the_level_spreads_the_water_in_the_same_step() -> void:
	var c := _flat()
	var b := _pond(c)
	var before: String = c.content_hash()
	var money: int = b.balance()
	assert_true(b.lower(Vector2i(14, 12), 1))
	assert_eq(c.get_surface(14, 12), W, "the water spreads onto the lowered tile")
	assert_eq(c.get_height(14, 12), 1)
	assert_eq(_cells_of(c, W).size(), 17)
	assert_eq(b.balance(), money - _econ.height_step_price - _econ.price_of(W))
	assert_eq(b.lift_cost(Vector2i(15, 12), 1, -1), _econ.height_step_price + _econ.price_of(W),
			"the next tile out would spread it too")
	b.undo()
	assert_eq(c.content_hash(), before, "one undo puts back the ground and the water")
	assert_eq(b.balance(), money)


func test_lowering_a_rim_tile_into_a_ditch_drains_the_water() -> void:
	# A ditch at 1 runs from the map's edge to one tile short of the pond; lowering that tile
	# opens the pond to the edge, and its water drains to rough.
	var c := _flat()
	_dig(c, Rect2i(0, 12, 9, 1), 1)
	var b := _pond(c)
	var before: String = c.content_hash()
	var money: int = b.balance()
	assert_true(b.lower(Vector2i(9, 12), 1))
	assert_eq(_cells_of(c, W).size(), 0, "the pond drained")
	assert_true(_all(c, Rect2i(10, 10, 4, 4), 1, R), "its ground stays where the water was")
	assert_eq(b.balance(), money - _econ.height_step_price, "draining is free")
	b.undo()
	assert_eq(c.content_hash(), before)


func test_lowering_beside_water_that_would_flood_a_green_is_refused() -> void:
	var c := _flat()
	var b := _pond(c)
	_refusals.clear()
	b.paint(Vector2i(15, 12), Surface.Type.GREEN, 1)
	b.lower(Vector2i(15, 12), 1)  # the green sits at 1, a tile past the rim
	var before: String = c.content_hash()
	assert_false(b.lower(Vector2i(14, 12), 1), "the gap would let the water onto the green")
	assert_true(CourseBuilder.FLOODS % "a green" in _refusals)
	assert_eq(c.content_hash(), before)


func test_edits_round_a_pond_then_undos_restore_the_hash() -> void:
	# Generated land, every parcel owned: 80 random paints of water and rough, raises and
	# lowers round a generated pond, each its own step; undoing them all gives the land back.
	var c: CourseData = LandGenerator.generate(3)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), true)
	var pond := Vector2i(-1, -1)
	for i: int in c.width * c.height:
		@warning_ignore("integer_division")
		var t := Vector2i(i % c.width, i / c.width)
		if c.get_surface(t.x, t.y) == W and t.x > 10 and t.y > 10 and t.x < c.width - 10 and t.y < c.height - 10:
			pond = t
			break
	assert_ne(pond, Vector2i(-1, -1), "seed 3 has a pond off the edge")
	var original: String = c.content_hash()
	var b := CourseBuilder.new(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 66
	var steps: int = 0
	var floods: int = 0
	for n: int in 80:
		var at := pond + Vector2i(rng.randi_range(-8, 8), rng.randi_range(-8, 8))
		var size: int = [1, 3, 5][rng.randi_range(0, 2)]
		var changed: bool
		match rng.randi_range(0, 3):
			0:
				changed = b.paint(at, W, size)
				floods += 1 if changed else 0
			1:
				changed = b.paint(at, R, size)
			2:
				changed = b.raise(at, size)
			3:
				changed = b.lower(at, size)
		steps += 1 if changed else 0
	assert_gt(floods, 0, "some water found a basin")
	assert_eq(b.undo_depth(), steps)
	while b.undo():
		pass
	assert_eq(c.content_hash(), original)


# --- courses as they are ---

func test_loaded_water_above_its_rim_stays_as_it_is() -> void:
	var c := _flat()
	c.set_tile(16, 16, 5, W)
	var b := _builder(c)
	assert_eq(c.get_surface(16, 16), W)
	assert_eq(c.get_height(16, 16), 5, "a towering pool from before D66 loads as it was")
	assert_false(b.can_undo())


func test_level_water_off_paints_water_as_before() -> void:
	var c := _flat()
	var b := _builder(c)
	b.level_water = false
	assert_true(b.paint(Vector2i(16, 16), W, 3))
	assert_eq(_cells_of(c, W).size(), 9)
	assert_eq(c.get_height(16, 16), 2)


func test_generated_ponds_sit_in_hollows() -> void:
	# D66: every generated pond is flat and one step below every shore tile on the map.
	for s: int in range(1, 11):
		var c: CourseData = LandGenerator.generate(s)
		var bad: int = 0
		for y: int in c.height:
			for x: int in c.width:
				if c.get_surface(x, y) != W:
					continue
				var h: int = c.get_height(x, y)
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n := Vector2i(x, y) + d
					if not c.in_bounds(n.x, n.y):
						continue
					var wet: bool = c.get_surface(n.x, n.y) == W
					if (wet and c.get_height(n.x, n.y) != h) or (not wet and c.get_height(n.x, n.y) <= h):
						bad += 1
		assert_eq(bad, 0, "seed %d: a shore at or below its pond" % s)


# --- cost ---

func test_a_big_pond_fills_inside_a_frame() -> void:
	if BestTime.later(self):
		return
	# A sandbox-sized 128 x 128, every tile owned and no clubhouse: a 60 x 60 hollow (3,600 tiles) whose search
	# rises to the plain round it before it finds the map's edge.
	var ms_fill: Array[float] = []
	var ms_undo: Array[float] = []
	for run: int in BestTime.RUNS:
		var c := CourseData.create(128, 128, R, 2)
		_dig(c, Rect2i(34, 34, 60, 60), 1)
		var b := CourseBuilder.new(c)
		var t0: int = Time.get_ticks_usec()
		assert_true(b.paint(Vector2i(60, 60), W, 1))
		ms_fill.append((Time.get_ticks_usec() - t0) / 1000.0)
		assert_eq(_cells_of(c, W).size(), 3600)
		t0 = Time.get_ticks_usec()
		b.undo()
		ms_undo.append((Time.get_ticks_usec() - t0) / 1000.0)
	ms_fill.sort()
	ms_undo.sort()
	gut.p("big pond (3,600 tiles) fill %.1f ms, undo %.1f ms (best of %d)" % [ms_fill[0], ms_undo[0], BestTime.RUNS])
	assert_lt(ms_fill[0], 16.7, "the fill and its validator rerun inside a frame. " + BestTime.load_note())
	assert_lt(ms_undo[0], 16.7, "its undo too. " + BestTime.load_note())


func test_dragging_water_over_open_ground_is_cheap() -> void:
	if BestTime.later(self):
		return
	# Every dab on a sandbox-sized open plain runs off; within a stroke the tiles found to run
	# off are remembered, so a drag searches the plain once, not once a frame.
	var c := CourseData.create(128, 128, R, 2)
	var b := CourseBuilder.new(c)
	b.begin_stroke()
	b.paint(Vector2i(64, 64), W, 5)
	var t0: int = Time.get_ticks_usec()
	for x: int in range(65, 95):
		b.paint(Vector2i(x, 64), W, 5)
	var each: float = (Time.get_ticks_usec() - t0) / 1000.0 / 30.0
	b.end_stroke()
	gut.p("water drag over open ground: %.2f ms a dab" % each)
	assert_lt(each, 2.0, BestTime.load_note())


func test_the_game_builds_with_water_finding_its_level() -> void:
	# Main's builder (what the Build tool paints through) never turns level_water off: water on
	# the flat startup course runs off, and the HUD shows why.
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	var tool: BuildTool = m.build_tool
	assert_true(tool.builder.level_water)
	tool.builder.refused.connect(func(reason: String) -> void: _refusals.append(reason))
	tool.select_surface(W)
	tool.brush_size = 3
	tool.press_at(Iso.tile_to_screen(Vector2(4, 4), 0) + Vector2(0.5, 0.5))
	tool.release()
	assert_eq(_cells_of(m.course, W).size(), 0, "flat ground holds no water")
	assert_eq(_refusals, [CourseBuilder.RUNS_OFF] as Array[String])
