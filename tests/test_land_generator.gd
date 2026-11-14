extends GutTest
## Natural land generator (E6-S2): course/land_generator.gd with course/land_tuning.tres,
## against the targets in docs/design.md Land, "Generated land", over seeds 1 to 20.

const SEEDS: int = 20
## Tolerances from docs/design.md Land (the targets themselves live in the tuning).
const TREE_SHARE := Vector2(0.08, 0.16)
const WATER_SHARE := Vector2(0.02, 0.06)
const HIGH_SHARE := Vector2(0.08, 0.25)

var _maps: Array[CourseData] = []
var _t: LandTuning


func before_all() -> void:
	_t = LandTuning.load_default()
	for s: int in range(1, SEEDS + 1):
		var errors: Array[String] = []
		var c := LandGenerator.generate(s, null, errors)
		assert_not_null(c, "seed %d generates: %s" % [s, errors])
		_maps.append(c)


func after_all() -> void:
	_maps.clear()


# --- helpers ---

func _count(c: CourseData, surface: Surface.Type, rect: Rect2i) -> int:
	var n: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if c.get_surface(x, y) == surface:
				n += 1
	return n


## 4-connected patches of `surface`: each an Array of Vector2i.
func _patches(c: CourseData, surface: Surface.Type) -> Array:
	var seen := PackedByteArray()
	seen.resize(c.width * c.height)
	var out: Array = []
	for y: int in c.height:
		for x: int in c.width:
			if seen[y * c.width + x] == 1 or c.get_surface(x, y) != surface:
				continue
			var patch: Array[Vector2i] = []
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			seen[y * c.width + x] = 1
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				patch.append(p)
				for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					var q: Vector2i = p + d
					if c.in_bounds(q.x, q.y) and seen[q.y * c.width + q.x] == 0 \
							and c.get_surface(q.x, q.y) == surface:
						seen[q.y * c.width + q.x] = 1
						stack.append(q)
			out.append(patch)
	return out


# --- seeded ---

func test_same_seed_gives_the_same_map() -> void:
	var a := LandGenerator.generate(7)
	var b := LandGenerator.generate(7)
	assert_eq(a.content_hash(), b.content_hash(), "seed 7 twice")
	assert_eq(a.content_hash(), _maps[6].content_hash(), "and as in before_all")
	assert_ne(a.content_hash(), LandGenerator.generate(8).content_hash(), "seed 8 differs")


func test_map_size_and_no_holes() -> void:
	for c: CourseData in _maps:
		assert_eq(Vector2i(c.width, c.height), _t.map_size)
		assert_eq(c.holes.size(), 0)


# --- heights and surfaces ---

func test_only_rough_trees_and_water_at_heights_0_to_7() -> void:
	for s: int in SEEDS:
		var c := _maps[s]
		var bad: int = 0
		for y: int in c.height:
			for x: int in c.width:
				var h := c.get_height(x, y)
				var surf := c.get_surface(x, y)
				if h < 0 or h > CourseData.MAX_HEIGHT:
					bad += 1
				if surf != Surface.Type.ROUGH and surf != Surface.Type.TREES and surf != Surface.Type.WATER:
					bad += 1
		assert_eq(bad, 0, "seed %d: tiles out of range or of a built surface" % (s + 1))


func test_lowland_sits_at_the_base_height_with_hills_above_it() -> void:
	for s: int in SEEDS:
		var c := _maps[s]
		var per_height := PackedInt32Array()
		per_height.resize(CourseData.MAX_HEIGHT + 1)
		for y: int in c.height:
			for x: int in c.width:
				per_height[c.get_height(x, y)] += 1
		var most: int = 0
		for h: int in per_height.size():
			if per_height[h] > per_height[most]:
				most = h
		assert_eq(most, _t.base_height, "seed %d: most ground at the base height" % (s + 1))
		var lowest: int = 0
		while per_height[lowest] == 0:
			lowest += 1
		assert_true(lowest >= _t.base_height - 1, "seed %d: nothing below a pond's floor (lowest %d)" % [s + 1, lowest])
		var top: int = CourseData.MAX_HEIGHT
		while per_height[top] == 0:
			top -= 1
		assert_true(top >= _t.base_height + _t.hill_peak_min and top <= _t.base_height + _t.hill_peak_max,
				"seed %d: highest peak %d steps above the base" % [s + 1, top - _t.base_height])


func test_slopes_rise_one_step_at_most_once_every_two_tiles() -> void:
	for s: int in SEEDS:
		var c := _maps[s]
		var steep: int = 0
		var crowded: int = 0
		for y: int in c.height:
			for x: int in c.width:
				for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var a: Vector2i = Vector2i(x, y) + d
					if not c.in_bounds(a.x, a.y):
						continue
					var rise1: int = c.get_height(a.x, a.y) - c.get_height(x, y)
					if absi(rise1) > 1:
						steep += 1
					var b: Vector2i = a + d
					if c.in_bounds(b.x, b.y) and rise1 != 0 and c.get_height(b.x, b.y) != c.get_height(a.x, a.y):
						crowded += 1
		assert_eq(steep, 0, "seed %d: edges rising more than one step" % (s + 1))
		assert_eq(crowded, 0, "seed %d: risers on two neighbouring edges" % (s + 1))


func test_no_valley_floor_so_floor_keep_never_acts_on_generated_land() -> void:
	# E6-S19 checks E6-S10's floor_keep_speed (20 yd/s) on generated land. A floor thud needs
	# a tile centre where the ground falls toward it and rises past it along one axis. The
	# 2 x 2 terrace cells put every riser on a cell edge, so no centre has one on both sides,
	# and a valley floor is two tiles wide at least: rolls across generated land settle the
	# same with floor_keep 1.0 (no thud), whatever floor_keep_speed is.
	var plain := SurfaceTable.load_default()
	var no_thud := SurfaceTable.new()
	for r0: SurfaceRow in plain.rows:
		var r: SurfaceRow = r0.duplicate()
		r.floor_keep = 1.0
		no_thud.rows.append(r)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var rolled := 0
	for s: int in 2:
		var c := _maps[s]
		for k: int in 100:
			var at := Vector2(rng.randf_range(40.0, 600.0), rng.randf_range(40.0, 600.0))
			var v := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, 25.0)
			var a := Ball.new(c, k, null, plain)
			if not a.may_place_on(a.field.tile_at(at.x, at.y)):
				continue
			var b := Ball.new(c, k, null, no_thud)
			a.start_roll(at, v)
			b.start_roll(at, v)
			var ta := a.run_to_rest()
			var tb := b.run_to_rest()
			rolled += 1
			assert_eq(ta, tb, "seed %d roll %d settles in the same ticks" % [s + 1, k])
			assert_eq(a.position, b.position, "seed %d roll %d rests in the same place" % [s + 1, k])
			assert_lt(ta, 600, "seed %d roll %d settles under D16's 10 s" % [s + 1, k])
	assert_gt(rolled, 150, "most starts are on open ground")


# --- rates ---

func test_tree_water_and_high_ground_shares_within_tolerance() -> void:
	for s: int in SEEDS:
		var c := _maps[s]
		var all := Rect2i(0, 0, c.width, c.height)
		var n := float(c.width * c.height)
		var trees: float = _count(c, Surface.Type.TREES, all) / n
		var water: float = _count(c, Surface.Type.WATER, all) / n
		var high: int = 0
		for y: int in c.height:
			for x: int in c.width:
				if c.get_height(x, y) >= 4:
					high += 1
		assert_between(trees, TREE_SHARE.x, TREE_SHARE.y, "seed %d trees" % (s + 1))
		assert_between(water, WATER_SHARE.x, WATER_SHARE.y, "seed %d water" % (s + 1))
		assert_between(high / n, HIGH_SHARE.x, HIGH_SHARE.y, "seed %d height 4 or more" % (s + 1))


func test_trees_grow_in_separate_stands_of_the_set_size() -> void:
	for s: int in SEEDS:
		var stands := _patches(_maps[s], Surface.Type.TREES)
		assert_between(stands.size(), _t.count(_t.tree_stands_min), _t.count(_t.tree_stands_max),
				"seed %d stands" % (s + 1))
		for stand: Array in stands:
			assert_between(stand.size(), _t.tree_stand_min_tiles, _t.tree_stand_max_tiles,
					"seed %d stand at %s" % [s + 1, stand[0]])


func test_ponds_of_the_set_size_flat_and_one_step_below_their_shore() -> void:
	for s: int in SEEDS:
		var c := _maps[s]
		var ponds := _patches(c, Surface.Type.WATER)
		assert_between(ponds.size(), _t.count(_t.ponds_min), _t.count(_t.ponds_max), "seed %d ponds" % (s + 1))
		for pond: Array in ponds:
			var at: Vector2i = pond[0]
			assert_between(pond.size(), _t.pond_min_tiles, _t.pond_max_tiles, "seed %d pond at %s" % [s + 1, at])
			var level: int = c.get_height(at.x, at.y)
			var off: int = 0
			for p: Vector2i in pond:
				if c.get_height(p.x, p.y) != level:
					off += 1
				for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					var q: Vector2i = p + d
					if c.in_bounds(q.x, q.y) and c.get_surface(q.x, q.y) != Surface.Type.WATER \
							and c.get_height(q.x, q.y) != level + 1:
						off += 1
			assert_eq(off, 0, "seed %d pond at %s: flat, every shore tile one step above" % [s + 1, at])
			assert_true(level >= 0)


# --- floors ---

func test_every_parcel_keeps_its_rough_floor_and_is_never_all_water() -> void:
	for s: int in SEEDS:
		var c := _maps[s]
		for q: int in ceili(c.height / float(CourseData.PARCEL_TILES)):
			for p: int in ceili(c.width / float(CourseData.PARCEL_TILES)):
				var rect := Rect2i(p * CourseData.PARCEL_TILES, q * CourseData.PARCEL_TILES,
						CourseData.PARCEL_TILES, CourseData.PARCEL_TILES).intersection(
						Rect2i(0, 0, c.width, c.height))
				var rough: int = _count(c, Surface.Type.ROUGH, rect)
				var water: int = _count(c, Surface.Type.WATER, rect)
				assert_true(rough >= _t.parcel_min_rough * rect.get_area(),
						"seed %d parcel (%d, %d): %d of %d rough" % [s + 1, p, q, rough, rect.get_area()])
				assert_true(water < rect.get_area(), "seed %d parcel (%d, %d) all water" % [s + 1, p, q])


func test_the_starting_block_is_mostly_rough_and_dry() -> void:
	assert_eq(LandGenerator.start_block(128, 128), Rect2i(32, 32, 64, 64), "D67: parcels 2 to 5 on each axis")
	var block := LandGenerator.start_block(_t.map_size.x, _t.map_size.y)
	assert_eq(block, Rect2i(64, 64, 64, 64), "D71: parcels 4 to 7 of 192 x 192's 12 x 12")
	assert_eq(LandGenerator.start_block(128, 128, LandTuning.D26_BLOCK_PARCELS), Rect2i(48, 48, 32, 32),
			"D26's 2 x 2: parcels 3 and 4")
	for s: int in SEEDS:
		var c := _maps[s]
		var rough: int = _count(c, Surface.Type.ROUGH, block)
		assert_true(rough >= _t.start_block_min_rough * block.get_area(),
				"seed %d block: %d of %d rough" % [s + 1, rough, block.get_area()])
		assert_eq(_count(c, Surface.Type.WATER, block), 0, "seed %d block has no water" % (s + 1))


## D71: a New course's land is 192 x 192, and the hill, stand and pond count bounds scale with its
## area over 128 x 128's, rounded (shares and sizes as they were); D67's tuning on D10's map
## (LandTuning.load_d67, which the fixtures' land keeps) has the counts as written.
func test_d71_map_and_counts_scaled_by_area() -> void:
	assert_eq(_t.map_size, Vector2i(192, 192))
	assert_eq(_t.count_map_size, Vector2i(128, 128))
	assert_eq([_t.count(_t.hill_count_min), _t.count(_t.hill_count_max)], [9, 18], "hills")
	assert_eq([_t.count(_t.tree_stands_min), _t.count(_t.tree_stands_max)], [34, 79], "stands")
	assert_eq([_t.count(_t.ponds_min), _t.count(_t.ponds_max)], [9, 23], "ponds")
	var d67 := LandTuning.load_d67()
	assert_eq(d67.map_size, LandTuning.D10_MAP_SIZE)
	assert_eq(LandTuning.D10_MAP_SIZE, Vector2i(128, 128))
	assert_eq(d67.start_block_parcels, 4)
	for n: int in [d67.hill_count_min, d67.hill_count_max, d67.tree_stands_min, d67.tree_stands_max,
			d67.ponds_min, d67.ponds_max]:
		assert_eq(d67.count(n), n, "128 x 128 keeps the count %d" % n)
	assert_eq(LandTuning.load_d26().map_size, Vector2i(128, 128), "D26's land is on D10's map too")
	assert_eq(LandTuning.load_default().map_size, Vector2i(192, 192), "the copies leave the default")
	var c := LandGenerator.generate(7, d67)
	assert_eq(Vector2i(c.width, c.height), Vector2i(128, 128))
	assert_eq(Vector2i(c.parcels_wide, c.parcels_high), Vector2i(8, 8))
	assert_eq(Vector2i(_maps[0].parcels_wide, _maps[0].parcels_high), Vector2i(12, 12), "D71: 144 parcels")


## D67: D26's tuning (LandTuning.load_d26) keeps the pre-D67 land, whose starting block is
## the 2 x 2 one, dry.
func test_d26_tuning_keeps_the_old_block_dry() -> void:
	var d26 := LandTuning.load_d26()
	assert_eq(d26.start_block_parcels, 2)
	assert_eq(LandTuning.load_default().start_block_parcels, 4, "the default is unchanged by the copy")
	var old_block := LandGenerator.start_block(128, 128, 2)
	for land_seed: int in [1, 7]:
		var c := LandGenerator.generate(land_seed, d26)
		assert_eq(_count(c, Surface.Type.WATER, old_block), 0, "seed %d: D26's block dry" % land_seed)
		assert_eq(LandGenerator.generate(land_seed, d26).content_hash(), c.content_hash(), "deterministic")


## E6-S15: generated land comes back with every parcel owned and no land budget (D26, D19:
## the starting block and the $5,000 budget are the builder's New course to set).
func test_generated_land_is_fully_owned_with_an_unlimited_budget() -> void:
	for s: int in SEEDS:
		var c := _maps[s]
		assert_true(c.has_unlimited_budget(), "seed %d has an unlimited budget" % (s + 1))
		for q: int in c.parcels_high:
			for p: int in c.parcels_wide:
				assert_true(c.is_parcel_owned(Vector2i(p, q)),
						"seed %d parcel (%d, %d) owned" % [s + 1, p, q])
				var r := c.parcel_rect(Vector2i(p, q))
				assert_true(c.is_owned(r.position.x, r.position.y) and c.is_owned(r.end.x - 1, r.end.y - 1),
						"seed %d parcel (%d, %d) tiles owned" % [s + 1, p, q])


# --- tunables ---

func test_the_tuning_resource_drives_the_generator() -> void:
	var t := LandTuning.load_default().duplicate() as LandTuning
	t.map_size = Vector2i(64, 48)
	t.water_share = 0.0
	t.ponds_min = 0
	t.ponds_max = 0
	t.tree_share = 0.0
	t.tree_stands_min = 0
	t.tree_stands_max = 0
	t.hill_count_min = 0
	t.hill_count_max = 0
	var c := LandGenerator.generate(3, t)
	assert_eq(Vector2i(c.width, c.height), Vector2i(64, 48))
	var all := Rect2i(0, 0, c.width, c.height)
	assert_eq(_count(c, Surface.Type.ROUGH, all), c.width * c.height, "no trees, no water")
	var flat := true
	for y: int in c.height:
		for x: int in c.width:
			flat = flat and c.get_height(x, y) == t.base_height
	assert_true(flat, "no hills: all at the base height")
