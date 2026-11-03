class_name LandGenerator
extends RefCounted
## Natural land for a new course (E6-S2, docs/design.md Land, "Generated land"): hills, tree
## stands and ponds on rough, from an integer seed. The same seed and tuning give the same map.
## It uses only rough, trees and water, and heights 0 to CourseData.MAX_HEIGHT; fairway, green,
## tee, bunker, cart path and oob are the player's to build. Tunables: course/land_tuning.tres.
##
## It never writes a CourseData: like CourseGenerator it lays the tiles out as course format
## data and constructs a new course with CourseData.from_dict, the loader course/save.gd uses,
## so CourseData keeps its two writers (CLAUDE.md Architecture).
##
## What it guarantees, exactly (tests/test_land_generator.gd):
## - Slopes: edge neighbours differ by one step at most, and along either axis two neighbouring
##   edges never both rise, so there is at most one riser every 2 tiles. Hills are terraces on a
##   grid of TERRACE x TERRACE tile cells, whose levels are clamped so neighbouring cells differ
##   by one step at most: a riser can only sit on a cell edge, and cell edges are 2 tiles apart.
## - Ponds: flat, one step below every shore tile (so below the lowest), never below 0. A pond
##   is a union of 2 x 2 squares (every row and column of it at least 2 tiles), dug into ground
##   that is flat for POND_MARGIN tiles all round, so its risers keep the slope rule too.
## - Floors: every parcel keeps parcel_min_rough of its tiles rough (so it is never all water),
##   and the starting block (D26) start_block_min_rough, with no water at all.

## Parcel size in tiles (D26). The format constant CourseData.PARCEL_TILES (E6-S3) has the same
## value; the generator keeps its own copy only until that lands.
const PARCEL_TILES: int = 16
## Hill terrace cell, in tiles. Structural (it is what makes the slope rule exact), not a tunable.
const TERRACE: int = 2
## Flat ground every pond tile needs round it, in tiles (Chebyshev). Structural, as TERRACE.
const POND_MARGIN: int = 2
## Random spots tried for a pond's or a stand's first tile before giving up on it.
const SEED_TRIES: int = 400
## Attempts per pond or stand, as a multiple of how many are wanted, before the generator stops.
const PLACE_TRIES: int = 30
## Bisection steps for the hill radius factor (hill_scale_min to hill_scale_max).
const HILL_SCALE_STEPS: int = 10


## A new course of generated land, or null with reasons in `errors` (only if the tuning makes
## tiles the loader refuses). `tuning` defaults to course/land_tuning.tres.
static func generate(land_seed: int, tuning: LandTuning = null, errors: Array[String] = []) -> CourseData:
	if tuning == null:
		tuning = LandTuning.load_default()
	var run := _Run.new(land_seed, tuning)
	run.build()
	var tiles := PackedByteArray()
	tiles.resize(run.w * run.h)
	for i: int in tiles.size():
		tiles[i] = (run.heights[i] << 4) | run.surf[i]
	var data := {
		"version": CourseData.FORMAT_VERSION,
		"name": "Land %d" % land_seed,
		"author": "land generator",
		"width": run.w,
		"height": run.h,
		"tiles": Marshalls.raw_to_base64(tiles),
		"holes": [],
		"thumbnail": "",
		# Every parcel owned, no budget: the format version 2 fields (E6-S3), which version 1
		# from_dict ignores. Ownership of a new course (the starting block, the $5,000 budget)
		# is the builder's to set (CourseBuilder.new_course, E6-S6), not the land's.
		"owned": _all_owned_rows(run.w, run.h),
		"land_budget": null,
	}
	return CourseData.from_dict(data, errors)


## The "owned" field with every parcel owned: one string of "1"s per parcel row. The same as
## CourseData.all_owned_rows (E6-S3); swap to it once both stories are on one branch.
static func _all_owned_rows(w: int, h: int) -> Array:
	var rows: Array = []
	var row := "1".repeat(ceili(w / float(PARCEL_TILES)))
	for q: int in ceili(h / float(PARCEL_TILES)):
		rows.append(row)
	return rows


## The starting block (D26): 2 x 2 parcels at the centre of a `w` x `h` map, clipped to it.
## On the 128 x 128 map, parcels 3 and 4 on each axis: tiles 48 to 79.
static func start_block(w: int, h: int) -> Rect2i:
	var pw: int = ceili(w / float(PARCEL_TILES))
	var ph: int = ceili(h / float(PARCEL_TILES))
	var block := Rect2i((pw / 2 - 1) * PARCEL_TILES, (ph / 2 - 1) * PARCEL_TILES,
			2 * PARCEL_TILES, 2 * PARCEL_TILES)
	return block.intersection(Rect2i(0, 0, w, h))


## One generation: the state the passes share. Heights first, then ponds (which need flat
## ground), then tree stands (which may grow up to a pond's shore).
class _Run:
	var w: int
	var h: int
	var heights: PackedByteArray
	var surf: PackedByteArray
	var _t: LandTuning
	var _rng := RandomNumberGenerator.new()
	var _pw: int
	## Tiles per parcel that may be trees or water, and how many are.
	var _parcel_cap: PackedInt32Array
	var _parcel_used: PackedInt32Array
	var _block: Rect2i
	var _block_cap: int
	var _block_used: int = 0
	## Tree stand id per tile, 0 for none, so stands never touch.
	var _stand: PackedInt32Array

	func _init(land_seed: int, tuning: LandTuning) -> void:
		_t = tuning
		_rng.seed = land_seed
		w = tuning.map_size.x
		h = tuning.map_size.y
		heights.resize(w * h)
		heights.fill(clampi(tuning.base_height, 0, CourseData.MAX_HEIGHT))
		surf.resize(w * h)
		surf.fill(Surface.Type.ROUGH)
		_stand.resize(w * h)
		_pw = ceili(w / float(PARCEL_TILES))
		var ph: int = ceili(h / float(PARCEL_TILES))
		_parcel_cap.resize(_pw * ph)
		_parcel_used.resize(_pw * ph)
		for q: int in ph:
			for p: int in _pw:
				var tiles: int = (mini(w, (p + 1) * PARCEL_TILES) - p * PARCEL_TILES) \
						* (mini(h, (q + 1) * PARCEL_TILES) - q * PARCEL_TILES)
				_parcel_cap[q * _pw + p] = floori((1.0 - tuning.parcel_min_rough) * tiles + 1e-6)
		_block = LandGenerator.start_block(w, h)
		_block_cap = floori((1.0 - tuning.start_block_min_rough) * _block.get_area() + 1e-6)

	func build() -> void:
		_hills()
		_ponds()
		_trees()

	# --- hills ---

	func _hills() -> void:
		var cw: int = ceili(w / float(TERRACE))
		var ch: int = ceili(h / float(TERRACE))
		# Each lobe: [centre, peak, radius]. A hill is a main lobe and up to hill_lobes_max smaller
		# ones round it, which make it irregular.
		var lobes: Array = []
		var count: int = _rng.randi_range(_t.hill_count_min, _t.hill_count_max)
		for _i: int in count:
			var peak := float(_rng.randi_range(_t.hill_peak_min, _t.hill_peak_max))
			var radius: float = peak * _rng.randf_range(_t.hill_radius_per_step_min, _t.hill_radius_per_step_max)
			var centre := Vector2(_rng.randf_range(0.0, w), _rng.randf_range(0.0, h))
			lobes.append([centre, peak, radius])
			for _k: int in _rng.randi_range(0, _t.hill_lobes_max):
				var offset: float = radius * _rng.randf_range(_t.hill_lobe_offset_min, _t.hill_lobe_offset_max)
				var at: Vector2 = centre + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * offset
				var s: float = _rng.randf_range(_t.hill_lobe_scale_min, _t.hill_lobe_scale_max)
				lobes.append([at, peak * s, radius * s])
		# Every radius is then scaled by one factor, found by bisection, so the share of ground at
		# high_ground_level or more comes as close to high_ground_share as the hills allow. The
		# share only grows with the factor, so bisection finds it.
		var lo: float = _t.hill_scale_min
		var hi: float = _t.hill_scale_max
		var best := _levels(lobes, lo, cw, ch)
		var best_miss: float = absf(_high_share(best) - _t.high_ground_share)
		for _step: int in HILL_SCALE_STEPS:
			var mid: float = (lo + hi) * 0.5
			var level := _levels(lobes, mid, cw, ch)
			var share: float = _high_share(level)
			if absf(share - _t.high_ground_share) < best_miss:
				best = level
				best_miss = absf(share - _t.high_ground_share)
			if share < _t.high_ground_share:
				lo = mid
			else:
				hi = mid
		for y: int in h:
			for x: int in w:
				heights[y * w + x] = best[(y / TERRACE) * cw + x / TERRACE]

	## Whole steps per terrace cell for `lobes` with every radius times `scale`, clamped so
	## edge-neighbouring cells differ by one step at most: each cell becomes the least over all
	## cells of (level + cell distance), the exact 4-neighbour envelope, in two raster passes. It
	## only lowers, so heights stay in range.
	func _levels(lobes: Array, scale: float, cw: int, ch: int) -> PackedInt32Array:
		var field := PackedFloat32Array()
		field.resize(cw * ch)
		for lobe: Array in lobes:
			_add_lobe(field, cw, ch, lobe[0], lobe[1], lobe[2] * scale)
		var level := PackedInt32Array()
		level.resize(cw * ch)
		for i: int in level.size():
			level[i] = clampi(_t.base_height + floori(field[i] + 0.5), 0, CourseData.MAX_HEIGHT)
		for cy: int in ch:
			for cx: int in cw:
				var i: int = cy * cw + cx
				if cx > 0:
					level[i] = mini(level[i], level[i - 1] + 1)
				if cy > 0:
					level[i] = mini(level[i], level[i - cw] + 1)
		for cy: int in range(ch - 1, -1, -1):
			for cx: int in range(cw - 1, -1, -1):
				var i: int = cy * cw + cx
				if cx < cw - 1:
					level[i] = mini(level[i], level[i + 1] + 1)
				if cy < ch - 1:
					level[i] = mini(level[i], level[i + cw] + 1)
		return level

	## Share of terrace cells at high_ground_level or more (the tile share on a map whose sides
	## are a multiple of TERRACE).
	func _high_share(level: PackedInt32Array) -> float:
		var n: int = 0
		for v: int in level:
			if v >= _t.high_ground_level:
				n += 1
		return n / float(level.size())

	## Raises `field` (per terrace cell) to a cosine bell of `peak` steps and `radius` tiles.
	func _add_lobe(field: PackedFloat32Array, cw: int, ch: int, centre: Vector2, peak: float,
			radius: float) -> void:
		if radius <= 0.0:
			return
		var lo_x: int = maxi(0, floori((centre.x - radius) / TERRACE))
		var hi_x: int = mini(cw - 1, floori((centre.x + radius) / TERRACE))
		var lo_y: int = maxi(0, floori((centre.y - radius) / TERRACE))
		var hi_y: int = mini(ch - 1, floori((centre.y + radius) / TERRACE))
		for cy: int in range(lo_y, hi_y + 1):
			for cx: int in range(lo_x, hi_x + 1):
				var cell_centre := Vector2((cx + 0.5) * TERRACE, (cy + 0.5) * TERRACE)
				var u: float = cell_centre.distance_to(centre) / radius
				if u >= 1.0:
					continue
				var v: float = peak * 0.5 * (1.0 + cos(PI * u))
				var i: int = cy * cw + cx
				field[i] = maxf(field[i], v)

	# --- ponds ---

	func _ponds() -> void:
		var target: int = roundi(_t.water_share * w * h)
		var n_lo: int = mini(maxi(_t.ponds_min, ceili(target / float(_t.pond_max_tiles))), _t.ponds_max)
		var n: int = _rng.randi_range(n_lo, _t.ponds_max)
		var placed: int = 0
		var total: int = 0
		var tries: int = 0
		while placed < n and tries < n * PLACE_TRIES:
			tries += 1
			var share: float = maxf(0.0, target - total) / float(n - placed)
			var want: int = clampi(roundi(share * _rng.randf_range(0.7, 1.3)), _t.pond_min_tiles, _t.pond_max_tiles)
			var pond := _grow_pond(want)
			if pond.size() < _t.pond_min_tiles:
				continue
			for i: int in pond:
				heights[i] -= 1
				surf[i] = Surface.Type.WATER
				_parcel_used[_parcel_of(i)] += 1
			placed += 1
			total += pond.size()

	## Tile indices of a pond of about `want` tiles (at most pond_max_tiles), grown from one
	## 2 x 2 square by adding 2 x 2 squares that touch it. Empty when no seed square fits.
	func _grow_pond(want: int) -> PackedInt32Array:
		var pond := PackedInt32Array()
		var member := {}
		var pending := {}
		var level: int = -1
		for _s: int in SEED_TRIES:
			var x0: int = _rng.randi_range(0, w - 2)
			var y0: int = _rng.randi_range(0, h - 2)
			var hh: int = heights[y0 * w + x0]
			if hh >= 1 and _add_square(x0, y0, hh, pond, member, pending):
				level = hh
				break
		if level < 0:
			return pond
		var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
		var tries: int = want * PLACE_TRIES
		while pond.size() < want and tries > 0:
			tries -= 1
			var t: int = pond[_rng.randi_range(0, pond.size() - 1)]
			var d: Vector2i = dirs[_rng.randi_range(0, 3)]
			var x0: int = t % w + d.x - _rng.randi_range(0, 1)
			var y0: int = t / w + d.y - _rng.randi_range(0, 1)
			_add_square(x0, y0, level, pond, member, pending)
		return pond

	## Adds the 2 x 2 square at (x0, y0) to `pond` when every new tile of it may be dug at
	## `level` and the pond stays within pond_max_tiles and every parcel's floor. True if added.
	func _add_square(x0: int, y0: int, level: int, pond: PackedInt32Array, member: Dictionary,
			pending: Dictionary) -> bool:
		var fresh: Array[int] = []
		for dy: int in 2:
			for dx: int in 2:
				var x: int = x0 + dx
				var y: int = y0 + dy
				if x < 0 or y < 0 or x >= w or y >= h:
					return false
				var i: int = y * w + x
				if member.has(i):
					continue
				if _block.has_point(Vector2i(x, y)) or not _diggable(x, y, level):
					return false
				fresh.append(i)
		if fresh.is_empty() or pond.size() + fresh.size() > _t.pond_max_tiles:
			return false
		# No one-tile gap between two tiles of the pond along an axis: the dry tile would have
		# a riser on both sides.
		for i: int in fresh:
			var x: int = i % w
			var y: int = i / w
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var gx: int = x + d.x
				var gy: int = y + d.y
				var fx: int = x + 2 * d.x
				var fy: int = y + 2 * d.y
				if fx < 0 or fy < 0 or fx >= w or fy >= h:
					continue
				var gap: int = gy * w + gx
				var far: int = fy * w + fx
				if not member.has(gap) and not fresh.has(gap) and (member.has(far) or fresh.has(far)):
					return false
		var extra := {}
		for i: int in fresh:
			var p: int = _parcel_of(i)
			extra[p] = int(extra.get(p, 0)) + 1
		for p: int in extra:
			if _parcel_used[p] + int(pending.get(p, 0)) + int(extra[p]) > _parcel_cap[p]:
				return false
		for p: int in extra:
			pending[p] = int(pending.get(p, 0)) + int(extra[p])
		for i: int in fresh:
			member[i] = true
			pond.append(i)
		return true

	## True when every tile within POND_MARGIN of (x, y) (clipped to the map) is rough at `level`.
	func _diggable(x: int, y: int, level: int) -> bool:
		for yy: int in range(maxi(0, y - POND_MARGIN), mini(h, y + POND_MARGIN + 1)):
			for xx: int in range(maxi(0, x - POND_MARGIN), mini(w, x + POND_MARGIN + 1)):
				var i: int = yy * w + xx
				if heights[i] != level or surf[i] != Surface.Type.ROUGH:
					return false
		return true

	# --- trees ---

	func _trees() -> void:
		var target: int = roundi(_t.tree_share * w * h)
		var n_lo: int = maxi(_t.tree_stands_min, ceili(target / float(_t.tree_stand_max_tiles)))
		var n_hi: int = maxi(n_lo, mini(_t.tree_stands_max, floori(target / float(_t.tree_stand_min_tiles))))
		var n: int = _rng.randi_range(n_lo, n_hi)
		var placed: int = 0
		var total: int = 0
		var tries: int = 0
		while placed < n and tries < n * PLACE_TRIES:
			tries += 1
			var share: float = maxf(0.0, target - total) / float(n - placed)
			var want: int = clampi(roundi(share * _rng.randf_range(0.6, 1.4)),
					_t.tree_stand_min_tiles, _t.tree_stand_max_tiles)
			var stand := _grow_stand(want)
			if stand.size() < _t.tree_stand_min_tiles:
				continue
			placed += 1
			for i: int in stand:
				surf[i] = Surface.Type.TREES
				_stand[i] = placed
				_parcel_used[_parcel_of(i)] += 1
				if _block.has_point(Vector2i(i % w, i / w)):
					_block_used += 1
			total += stand.size()

	## Tile indices of a stand of about `want` tiles, grown from one tile by adding a random
	## tile next to it (4 neighbours), so it is one patch. Never touches another stand.
	func _grow_stand(want: int) -> PackedInt32Array:
		var stand := PackedInt32Array()
		var member := {}
		var pending := {}
		var pending_block: Array[int] = [0]
		var frontier := PackedInt32Array()
		for _s: int in SEED_TRIES:
			var i: int = _rng.randi_range(0, w * h - 1)
			if _plantable(i, member, pending, pending_block):
				_plant(i, stand, member, pending, pending_block, frontier)
				break
		while stand.size() < want and not frontier.is_empty():
			var k: int = _rng.randi_range(0, frontier.size() - 1)
			var i: int = frontier[k]
			frontier[k] = frontier[frontier.size() - 1]
			frontier.resize(frontier.size() - 1)
			if _plantable(i, member, pending, pending_block):
				_plant(i, stand, member, pending, pending_block, frontier)
		return stand

	func _plant(i: int, stand: PackedInt32Array, member: Dictionary, pending: Dictionary,
			pending_block: Array[int], frontier: PackedInt32Array) -> void:
		member[i] = true
		stand.append(i)
		var p: int = _parcel_of(i)
		pending[p] = int(pending.get(p, 0)) + 1
		var x: int = i % w
		var y: int = i / w
		if _block.has_point(Vector2i(x, y)):
			pending_block[0] += 1
		if x > 0:
			frontier.append(i - 1)
		if x < w - 1:
			frontier.append(i + 1)
		if y > 0:
			frontier.append(i - w)
		if y < h - 1:
			frontier.append(i + w)

	func _plantable(i: int, member: Dictionary, pending: Dictionary, pending_block: Array[int]) -> bool:
		if member.has(i) or surf[i] != Surface.Type.ROUGH:
			return false
		var x: int = i % w
		var y: int = i / w
		if (x > 0 and _stand[i - 1] != 0) or (x < w - 1 and _stand[i + 1] != 0) \
				or (y > 0 and _stand[i - w] != 0) or (y < h - 1 and _stand[i + w] != 0):
			return false
		var p: int = _parcel_of(i)
		if _parcel_used[p] + int(pending.get(p, 0)) + 1 > _parcel_cap[p]:
			return false
		if _block.has_point(Vector2i(x, y)) and _block_used + pending_block[0] + 1 > _block_cap:
			return false
		return true

	func _parcel_of(i: int) -> int:
		return ((i / w) / PARCEL_TILES) * _pw + (i % w) / PARCEL_TILES
