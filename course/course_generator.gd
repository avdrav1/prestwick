class_name CourseGenerator
extends RefCounted
## Builds the one-hole courses `/course-file generate <par> [flat|hilly] [water|dry]` writes
## (course/course_file.gd), used as test fixtures and smoke playtest courses. Every course it
## makes passes all six rules of course/validator.gd (tests/test_validator.gd checks).
##
## It never writes a CourseData: it lays the tiles out as course format data (every parcel
## owned, an unlimited land budget) and
## constructs a new course from that with CourseData.from_dict, the loader course/save.gd
## uses, so CourseData keeps its two writers (CLAUDE.md Architecture).
##
## Layout, along +x on a D10 plot (rough at height 2): a 3x3 tee box round the tee, a fairway
## corridor 5 tiles wide from 40 yd out to the green's front, a round green round the cup,
## and with water a pond 3 tiles long across the corridor at 60% of the way, dug one step,
## with dry rough round both ends. `hilly` lays the same hole over natural land: the heights of
## LandGenerator (HILLY_LAND_SEED), cropped round the map's centre, with the tee box, the green
## and the pond (with a one-tile dry ring) levelled flat (hilly_heights, below). Only heights
## differ from the flat hole, so the surfaces and the six rules are the flat hole's.

## Hole lengths in tiles at 5 yd per tile: 160, 380 and 520 yd. Fixture shapes, not tunables.
const LENGTH_TILES: Dictionary = {3: 32, 4: 76, 5: 104}
const MAP_ROWS: int = 25
const END_MARGIN: int = 6
const PLOT_HEIGHT: int = 2
const FAIRWAY_HALF_WIDTH: int = 2
const FAIRWAY_START: int = 8
const GREEN_RADIUS: float = 3.2
const POND_AT: float = 0.6
const POND_LENGTH: int = 3
const POND_HALF_WIDTH: int = 4
## The land generator seed `hilly` lays its hole over (D19, E6-S20). A fixture choice: seed 7
## gives one to six steps of relief under every par's window.
const HILLY_LAND_SEED: int = 7


## A new one-hole course, or null with a reason in `errors` for a par outside 3 to 5.
static func generate(par: int, hilly: bool, water: bool, errors: Array[String] = []) -> CourseData:
	if not LENGTH_TILES.has(par):
		errors.append("par must be 3, 4 or 5, got %d" % par)
		return null
	var length: int = LENGTH_TILES[par]
	var w: int = length + 2 * END_MARGIN
	var h: int = MAP_ROWS
	var mid: int = h / 2
	var tee := Vector2i(END_MARGIN, mid)
	var cup := Vector2i(END_MARGIN + length, mid)
	var pond_x: int = tee.x + roundi(length * POND_AT)

	var heights := PackedByteArray()
	if hilly:
		heights = hilly_heights(w, h, tee, cup, pond_x, water)
	else:
		heights.resize(w * h)
		heights.fill(PLOT_HEIGHT)
		for y: int in h:
			for x: int in w:
				if water and _in_pond(x, y, pond_x, mid, 0):
					heights[y * w + x] = PLOT_HEIGHT - 1
	var tiles := PackedByteArray()
	tiles.resize(w * h)
	for y: int in h:
		for x: int in w:
			var s: Surface.Type = Surface.Type.ROUGH
			var height: int = heights[y * w + x]
			var on_corridor: bool = absi(y - mid) <= FAIRWAY_HALF_WIDTH
			if on_corridor and x >= tee.x + FAIRWAY_START and x < cup.x:
				s = Surface.Type.FAIRWAY
			if water and _in_pond(x, y, pond_x, mid, 0):
				s = Surface.Type.WATER
			if _on_green(x, y, cup):
				s = Surface.Type.GREEN
			if _on_tee_box(x, y, tee):
				s = Surface.Type.TEE
			tiles[y * w + x] = (height << 4) | s

	var data := {
		"version": CourseData.FORMAT_VERSION,
		"name": "Par %d, %s, %s" % [par, "hilly" if hilly else "flat", "water" if water else "dry"],
		"author": "course-file generate",
		"width": w,
		"height": h,
		"tiles": Marshalls.raw_to_base64(tiles),
		"holes": [HoleData.new(1, par, tee, cup, true).to_dict()],
		"thumbnail": "",
		# A fixture plays on land it owns, with no budget, as New sandbox does (D26).
		"owned": CourseData.all_owned_rows(w, h),
		"land_budget": null,
	}
	return CourseData.from_dict(data, errors)


## Heights (row-major, index y * w + x) of a hilly hole on a `w` x `h` map, laid on the terrace
## cells of LandGenerator.generate(HILLY_LAND_SEED) (course/land_tuning.tres) so that it keeps
## the land's slope rule: edge neighbours one step apart at most, and along either axis at most
## one riser every 2 tiles (E6-S29, D16; tests/test_course_file.gd). The window is the w x h
## one centred on the land map. The land's own ponds are filled back to their shore (the hole
## drops their water, and a basin left as a rough pit would have risers off the cell edges),
## which gives back the land's per-cell levels exactly. Then, on those LandGenerator.TERRACE
## cells: each flat part's cells (every cell holding a tile of it) are levelled to their lowest
## cell, the tee box, the green and with `water` the pond grown by POND_MARGIN tiles, and every
## cell is lowered to at most one step above each edge-neighbouring cell (the least over all
## cells of level + cell distance, in two raster passes), repeated until nothing moves. Risers
## then sit only on cell edges, 2 tiles apart, as on the land. Last the pond's own tiles are dug
## one step below that level (never below 0): the next riser out from a pond's edge is on a cell
## edge at least POND_MARGIN tiles out, and its one-tile dry ring is level. Only lowers past
## the filled ponds, so 0 to 7 holds.
static func hilly_heights(w: int, h: int, tee: Vector2i, cup: Vector2i, pond_x: int,
		water: bool) -> PackedByteArray:
	var land := LandGenerator.generate(HILLY_LAND_SEED)
	var t: int = LandGenerator.TERRACE
	var x0: int = clampi((land.width - w) / 2, 0, maxi(0, land.width - w))
	var y0: int = clampi((land.height - h) / 2, 0, maxi(0, land.height - h))
	var mid: int = h / 2
	# The terrace cells under the window: cell (cx, cy) holds land tiles from (cx0 + cx) * t.
	var cx0: int = x0 / t
	var cy0: int = y0 / t
	var cw: int = (x0 + w - 1) / t - cx0 + 1
	var ch: int = (y0 + h - 1) / t - cy0 + 1
	var cell_of := func(x: int, y: int) -> int:
		return ((y0 + y) / t - cy0) * cw + (x0 + x) / t - cx0
	var level := PackedInt32Array()
	level.resize(cw * ch)
	for y: int in h:
		for x: int in w:
			var lx: int = clampi(x0 + x, 0, land.width - 1)
			var ly: int = clampi(y0 + y, 0, land.height - 1)
			var filled: int = land.get_height(lx, ly)
			if land.get_surface(lx, ly) == Surface.Type.WATER:
				filled += 1
			level[cell_of.call(x, y)] = filled
	var parts: Array[Callable] = [
		func(x: int, y: int) -> bool: return _on_tee_box(x, y, tee),
		func(x: int, y: int) -> bool: return _on_green(x, y, cup),
	]
	if water:
		parts.append(func(x: int, y: int) -> bool:
				return _in_pond(x, y, pond_x, mid, LandGenerator.POND_MARGIN))
	var part_cells: Array[PackedInt32Array] = []
	for part: Callable in parts:
		var cells := {}
		for y: int in h:
			for x: int in w:
				if part.call(x, y):
					cells[cell_of.call(x, y)] = true
		part_cells.append(PackedInt32Array(cells.keys()))
	var moved: bool = true
	while moved:
		moved = false
		for cells: PackedInt32Array in part_cells:
			var lowest: int = CourseData.MAX_HEIGHT
			for i: int in cells:
				lowest = mini(lowest, level[i])
			for i: int in cells:
				if level[i] != lowest:
					level[i] = lowest
					moved = true
		var before := level.duplicate()
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
		if level != before:
			moved = true
	var out := PackedByteArray()
	out.resize(w * h)
	for y: int in h:
		for x: int in w:
			var height: int = level[cell_of.call(x, y)]
			if water and _in_pond(x, y, pond_x, mid, 0):
				height = maxi(0, height - 1)
			out[y * w + x] = height
	return out


static func _on_tee_box(x: int, y: int, tee: Vector2i) -> bool:
	return absi(x - tee.x) <= 1 and absi(y - tee.y) <= 1


static func _on_green(x: int, y: int, cup: Vector2i) -> bool:
	return Vector2(x - cup.x, y - cup.y).length() <= GREEN_RADIUS


## The pond's water across the corridor at row `mid`, grown by `ring` tiles on every side.
static func _in_pond(x: int, y: int, pond_x: int, mid: int, ring: int) -> bool:
	return x >= pond_x - ring and x < pond_x + POND_LENGTH + ring \
			and absi(y - mid) <= POND_HALF_WIDTH + ring
