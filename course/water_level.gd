class_name WaterLevel
extends RefCounted
## D66, E10-S4: where painted water goes. Reads a CourseData, never writes it: course/builder.gd
## applies what this finds.
##
## A water tile's height is its water surface. The basin of a tile at fill level L is the tiles
## connected to it through their 4 edges at height L or lower. A basin holds while none of its
## tiles is on the map's edge or next to a tile the player does not own: off the map and off
## owned land are drains, whatever their height. Painting water on a tile raises L from the
## tile's own height a step at a time while the basin holds; the first L at which it would reach
## a drain is the spill height (the lowest rim tile's height), and the water lies one step under
## it. When the basin at the tile's own height already reaches a drain the water runs off.
##
## The search is a flood fill over CourseData.packed_tiles(), level by level (each rim tile is
## kept in a bucket by its height until the level reaches it, so every tile is read once), depth
## first, and stops at the first drain, so it never leaves owned land.

## What a search found.
class Basin:
	extends RefCounted
	## The fill level, or -1 when the water runs off.
	var level: int = -1
	## The basin's tiles at that level (index y * width + x), the seed first; empty when it runs off.
	var cells: PackedInt32Array = PackedInt32Array()
	## Tiles the search found that run off on their own (in the region that reached a drain, at
	## the height it reached it at): painting water on any of them would run off too, while the
	## ground stays as it is.
	var runoff: PackedInt32Array = PackedInt32Array()

	func holds() -> bool:
		return level >= 0


## The basin painting water on `seed` would fill. `over` gives heights (index -> height) that
## stand in for the course's own: a lower being planned. With `fixed` 0 or more the level does
## not rise: the basin at that level, or a runoff Basin when it reaches a drain (re-levelling
## water that stands at `fixed`).
static func fill(course: CourseData, seed: Vector2i, over: Dictionary = {}, fixed: int = -1) -> Basin:
	var out := Basin.new()
	var w: int = course.width
	var h: int = course.height
	if seed.x < 0 or seed.y < 0 or seed.x >= w or seed.y >= h:
		return out
	var tiles: PackedByteArray = course.packed_tiles()
	var own: PackedByteArray = _owned_mask(course)
	var has_over: bool = not over.is_empty()
	var s: int = seed.y * w + seed.x
	var level: int = fixed if fixed >= 0 else _height(tiles, over, has_over, s)
	# 0 unseen, 1 in the region, 2 waiting in a bucket for its level. The neighbours are spelled
	# out, not looped or called: a search reads up to the whole map (E3-S75's reason).
	var mark := PackedByteArray()
	mark.resize(w * h)
	var buckets: Array[PackedInt32Array] = []
	for i: int in CourseData.MAX_HEIGHT + 1:
		buckets.append(PackedInt32Array())
	var region := PackedInt32Array([s])
	mark[s] = 1
	# Depth first: on open ground the search runs straight to a drain instead of spreading over
	# the whole plain round it (the basin found is the same in any order).
	var stack := PackedInt32Array()
	stack.resize(w * h)
	stack[0] = s
	var top: int = 1
	var good_level: int = -1
	var good_count: int = 0
	var last_row: int = w * (h - 1)
	while true:
		var drained: bool = false
		while top > 0:
			top -= 1
			var i: int = stack[top]
			var x: int = i % w
			# A tile on the map's edge, or next to land not owned, reaches a drain.
			if x == 0 or x == w - 1 or i < w or i >= last_row \
					or own[i + 1] == 0 or own[i - 1] == 0 or own[i + w] == 0 or own[i - w] == 0:
				drained = true
				break
			var j: int = i + 1
			var hj: int = 0
			if mark[j] == 0:
				hj = tiles[j] >> 4
				if has_over and over.has(j):
					hj = over[j]
				if hj <= level:
					mark[j] = 1
					region.append(j)
					stack[top] = j
					top += 1
				else:
					mark[j] = 2
					buckets[hj].append(j)
			j = i - 1
			if mark[j] == 0:
				hj = tiles[j] >> 4
				if has_over and over.has(j):
					hj = over[j]
				if hj <= level:
					mark[j] = 1
					region.append(j)
					stack[top] = j
					top += 1
				else:
					mark[j] = 2
					buckets[hj].append(j)
			j = i + w
			if mark[j] == 0:
				hj = tiles[j] >> 4
				if has_over and over.has(j):
					hj = over[j]
				if hj <= level:
					mark[j] = 1
					region.append(j)
					stack[top] = j
					top += 1
				else:
					mark[j] = 2
					buckets[hj].append(j)
			j = i - w
			if mark[j] == 0:
				hj = tiles[j] >> 4
				if has_over and over.has(j):
					hj = over[j]
				if hj <= level:
					mark[j] = 1
					region.append(j)
					stack[top] = j
					top += 1
				else:
					mark[j] = 2
					buckets[hj].append(j)
		if drained:
			for r: int in region:
				if (tiles[r] >> 4) == level and not (has_over and over.has(r)):
					out.runoff.append(r)
			break
		good_level = level
		good_count = region.size()
		if fixed >= 0 or level >= CourseData.MAX_HEIGHT:
			break
		level += 1
		for j: int in buckets[level]:
			mark[j] = 1
			stack[top] = j
			top += 1
		region.append_array(buckets[level])
		buckets[level].clear()
	if good_level >= 0:
		out.level = good_level
		out.cells = region.slice(0, good_count)
	return out


## One byte a tile, 1 on owned land (CourseData.is_owned), kept while the course and its land
## stay the same (CourseData.land_revision): built once, not per search.
static var _mask: PackedByteArray = PackedByteArray()
static var _mask_key: Array = []


static func _owned_mask(course: CourseData) -> PackedByteArray:
	var key: Array = [course.get_instance_id(), course.land_revision, course.width, course.height]
	if key == _mask_key:
		return _mask
	var w: int = course.width
	var out := PackedByteArray()
	var row := PackedByteArray()
	row.resize(w)
	for y: int in course.height:
		if y % CourseData.PARCEL_TILES == 0:
			for x: int in w:
				row[x] = 1 if course.is_owned(x, y) else 0
		out.append_array(row)
	_mask = out
	_mask_key = key
	return out


## What in `cells` (indices on `course`) refuses a flood, named for the refusal ("a green", "a
## tee", "hole 2's cup", "the clubhouse", "decor"), or "" when nothing does. The first such tile
## in `cells` order names it; a hole's tee or cup is named before the surface under it.
static func blocker(course: CourseData, cells: PackedInt32Array) -> String:
	var w: int = course.width
	var marks := {}
	for hd: HoleData in course.holes:
		if course.in_bounds(hd.tee.x, hd.tee.y):
			marks[hd.tee.y * w + hd.tee.x] = "hole %d's tee" % hd.number
		if course.in_bounds(hd.cup.x, hd.cup.y):
			marks[hd.cup.y * w + hd.cup.x] = "hole %d's cup" % hd.number
	var tiles: PackedByteArray = course.packed_tiles()
	var club: bool = course.has_clubhouse()
	var decor: bool = not course.decor_cells().is_empty()
	for i: int in cells:
		if marks.has(i):
			return marks[i]
		var s: int = tiles[i] & 0x0F
		if s == Surface.Type.GREEN:
			return "a green"
		if s == Surface.Type.TEE:
			return "a tee"
		@warning_ignore("integer_division")
		var y: int = i / w
		var x: int = i - y * w
		if club and course.is_clubhouse(x, y):
			return "the clubhouse"
		if decor and course.decor_at(x, y) != CourseData.NO_DECOR:
			return "decor"
	return ""


static func _height(tiles: PackedByteArray, over: Dictionary, has_over: bool, i: int) -> int:
	if has_over and over.has(i):
		return over[i]
	return tiles[i] >> 4
