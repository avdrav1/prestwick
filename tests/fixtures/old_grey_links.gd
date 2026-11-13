class_name OldGreyLinks
extends RefCounted
## E13-S2 fixture: "Old Grey Links", nine holes of seaside links, each modelled on a famous real
## links hole at its real par and yardage (docs/courses.md credits them; the names here are
## our own). Laid through CourseBuilder only, on flat land (CourseData.create: every parcel
## owned, an unlimited budget, as New sandbox), the way a player would: shape the ground,
## paint, place, open. `courses/old_grey_links.json` is this course saved with CourseSave;
## rebuild it with `godot --headless --path . -s scripts/save_old_grey_links.gd`
## (with XDG_DATA_HOME set to a temporary folder).
##
## Links: the holes play along valleys between rolling dunes (the ground rises away from every
## hole's line into dunes up to DUNE_TOP steps), fairways are wide and run into the greens,
## there are few trees (gorse clumps in the dunes), many bunkers, some of them pots sunk a
## step, two burns and the sea along the north edge with a strip of beach.
##
## Each hole is a spec in HOLES (tile coordinates, 5 yd a tile), read as PlaytestNine's are:
## - name: the hole's own name; yd: the yardage it is built to (the line of play, rule 4).
## - tee: the tee marker on a 3 x 3 tee box, `tee_lift` steps above the ground round it.
## - fairway: a polyline painted `width` tiles wide ([] for none).
## - green: [centre, half length, half width, angle, lift, contour direction, steps, run,
##   offset], PlaytestNine's green: an ellipse lifted `lift` steps over the mean ground, rising
##   `steps` one-step contours along the direction.
## - bunkers: [centre, half length, half width, angle, sink]: an ellipse of sand, `sink` steps
##   below the ground round it (a pot bunker).
## - burns: [polyline, width]: water dug a step below the lowest ground beside it, each one
##   stopping short on one side so a dry way round it joins tee and cup (rule 3, Interesting).
## - swales: [centre, half length, half width, angle, depth]: ground `depth` steps below the
##   fairway round it (the home hole's valley in front of its green).
## - trees: gorse clumps, ellipses as above.
##
## Build order: heights (dunes, then greens, tees, bunkers, burns and swales set and the ground
## round them eased to the land generator's slope rule), then everything painted rough, the
## sea, the beach and the gorse, then each hole's fairway, bunkers, burns, tee box and green,
## then the cart paths (D65, D68), the tees, cups and pars, the clubhouse beside the first
## tee, the course's name, and last every hole is checked open.

const PATH: String = "res://courses/old_grey_links.json"
const COURSE_NAME: String = "Old Grey Links"
const COURSE_AUTHOR: String = "Prestwick"
const SIZE: int = 128
## The clubhouse stands within this many tiles of hole 1's tee (ClubhouseRule.spot_beside).
const CLUBHOUSE_REACH: int = 8
## The ground the holes play over, in steps, before the roll.
const GROUND: int = 2
## The highest the dunes rise above the ground.
const DUNE_TOP: float = 3.0
## Tiles from a hole's line before the dunes begin to rise, and over how many they reach top.
const DUNE_START: float = 7.0
const DUNE_RAMP: float = 5.0
## The sea: the map's top rows (y below SEA_ROWS) are water, the next BEACH_ROWS sand.
const SEA_ROWS: int = 2
const BEACH_ROWS: int = 1

## Cart paths, polylines of tile centres painted 1 tile wide over rough and trees, each
## [the green the walk leaves, the tee it reaches, the polyline]: the two walks that would
## take the least patient guest over 2.0 s (the 4th green to the raised 5th tee, 81 yd, and the
## 8th green up to the 9th tee, 71 yd).
const PATHS: Array = [
	[4, 5, [Vector2(21, 112), Vector2(29, 108)]],
	# Round the right of the 8th green's bunkers to the 9th tee.
	[8, 9, [Vector2(66, 51), Vector2(75, 51)]],
]

const HOLES: Array = [
	{
		# The opener, up the west side; the burn crosses just short of the green.
		"n": 1, "name": "Swilken Water", "par": 4, "yd": 375,
		"tee": Vector2i(10, 104), "cup": Vector2i(10, 29), "tee_lift": 1,
		"fairway": [Vector2(10, 100), Vector2(10, 33)], "width": 8.0,
		"green": [Vector2(10, 29), 4.5, 3.5, 90.0, 0, Vector2(0, -1), 1, 2, 0.0],
		"bunkers": [[Vector2(14, 52), 1.2, 1.2, 0.0, 1]],
		"burns": [[[Vector2(4, 37), Vector2(8, 36), Vector2(13, 37), Vector2(17, 36)], 2.0]],
		"swales": [],
		"trees": [],
	},
	{
		# The long par 5 east along the shore, the great cross bunker on the second shot.
		"n": 2, "name": "The Bishop", "par": 5, "yd": 483,
		"tee": Vector2i(16, 20), "cup": Vector2i(112, 10), "tee_lift": 1,
		"fairway": [Vector2(20, 19.6), Vector2(108, 10.4)], "width": 7.0,
		"green": [Vector2(112, 10), 4.5, 3.5, -6.0, 0, Vector2(1, 0), 1, 2, 0.5],
		"bunkers": [[Vector2(84, 13), 5.5, 1.2, 84.0, 1], [Vector2(46, 20), 1.2, 1.2, 0.0, 1],
				[Vector2(106, 14), 1.2, 1.5, 0.0, 0], [Vector2(107, 6), 1.2, 1.2, 0.0, 0]],
		"burns": [],
		"swales": [],
		"trees": [],
	},
	{
		# South down the east side; the burn crosses twice, the island of fairway between.
		"n": 3, "name": "Island Burn", "par": 4, "yd": 460,
		"tee": Vector2i(120, 20), "cup": Vector2i(116, 112), "tee_lift": 1,
		"fairway": [Vector2(120, 24), Vector2(116, 108)], "width": 7.0,
		"green": [Vector2(116, 112), 4.5, 3.5, 90.0, 0, Vector2(0, 1), 1, 2, 0.5],
		"bunkers": [[Vector2(112, 104), 1.2, 1.2, 0.0, 1], [Vector2(121, 106), 1.2, 1.2, 0.0, 1]],
		"burns": [[[Vector2(105, 60), Vector2(112, 57), Vector2(118, 60), Vector2(124, 57)], 2.0],
				[[Vector2(106, 81), Vector2(113, 78), Vector2(119, 81), Vector2(124, 79)], 2.0]],
		"swales": [],
		"trees": [],
	},
	{
		# The road hole, west along the south: a pot bunker eating into the green's front left
		# and the road (a cart path) behind it.
		"n": 4, "name": "The Road", "par": 4, "yd": 455,
		"tee": Vector2i(111, 121), "cup": Vector2i(20, 117), "tee_lift": 1,
		"fairway": [Vector2(107, 120.8), Vector2(60, 116), Vector2(25, 117)], "width": 7.0,
		"green": [Vector2(20, 117), 5.0, 2.8, -25.0, 0, Vector2(-1, 0.3), 1, 2, 0.5],
		"bunkers": [[Vector2(26, 118), 1.2, 1.2, 0.0, 1], [Vector2(70, 112), 1.5, 1.2, 0.0, 1]],
		"burns": [],
		"swales": [],
		"trees": [],
	},
	{
		# The short par 4 a big hitter can drive, pot bunkers hidden across the fairway.
		"n": 5, "name": "Heather Pots", "par": 4, "yd": 347,
		"tee": Vector2i(32, 106), "cup": Vector2i(100, 92), "tee_lift": 2,
		"fairway": [Vector2(36, 105), Vector2(96, 92.8)], "width": 7.0,
		"green": [Vector2(100, 92), 3.5, 2.5, -10.0, 1, Vector2(1, -0.2), 1, 2, 0.5],
		"bunkers": [[Vector2(80, 96), 1.0, 1.0, 0.0, 0], [Vector2(86, 94), 1.0, 1.0, 0.0, 0],
				[Vector2(84, 98), 1.0, 1.0, 0.0, 0]],
		"burns": [],
		"swales": [],
		"trees": [],
	},
	{
		# The long par 3 north to a green on a plateau two steps up.
		"n": 6, "name": "The Table", "par": 3, "yd": 250,
		"tee": Vector2i(100, 85), "cup": Vector2i(101, 35), "tee_lift": 1,
		"fairway": [Vector2(100, 50), Vector2(101, 40)], "width": 5.0,
		"green": [Vector2(101, 35), 4.0, 3.5, 90.0, 2, Vector2(0, -1), 1, 3, 0.0],
		"bunkers": [[Vector2(97, 41), 1.2, 1.5, 0.0, 0], [Vector2(105, 40), 1.2, 1.5, 0.0, 0],
				[Vector2(101, 48), 1.0, 1.0, 0.0, 1]],
		"burns": [],
		"swales": [],
		"trees": [],
	},
	{
		# The short par 3 west, its green sloping hard to the front, guarded by the hill
		# bunker left and the deep pot short.
		"n": 7, "name": "Estuary", "par": 3, "yd": 173,
		"tee": Vector2i(96, 30), "cup": Vector2i(62, 24), "tee_lift": 1,
		"fairway": [],  "width": 5.0,
		"green": [Vector2(62, 24), 4.0, 3.0, 0.0, 0, Vector2(-1, 0), 2, 2, -1.0],
		"bunkers": [[Vector2(67, 24), 1.0, 1.0, 0.0, 1], [Vector2(64, 28), 1.5, 1.0, 0.0, 1]],
		"burns": [],
		"swales": [],
		"trees": [],
	},
	{
		# The tiny par 3 south from a raised tee to a small green ringed by bunkers.
		"n": 8, "name": "Penny Stamp", "par": 3, "yd": 122,
		"tee": Vector2i(67, 30), "cup": Vector2i(63, 54), "tee_lift": 2,
		"fairway": [], "width": 5.0,
		"green": [Vector2(63, 54), 3.0, 2.2, 80.0, 0, Vector2(0, 1), 1, 2, 0.5],
		"bunkers": [[Vector2(63, 50), 1.6, 0.9, 0.0, 1], [Vector2(66, 55), 0.9, 1.6, 0.0, 0],
				[Vector2(60, 53), 0.9, 1.4, 0.0, 0], [Vector2(63, 58), 1.4, 0.9, 0.0, 0]],
		"burns": [],
		"swales": [],
		"trees": [],
	},
	{
		# Home: over the burn and its bridge off the tee, down the wide fairway to a green
		# with a deep swale across its front.
		"n": 9, "name": "Grey Hollow", "par": 4, "yd": 358,
		"tee": Vector2i(77, 52), "cup": Vector2i(24, 100), "tee_lift": 1,
		"fairway": [Vector2(70, 58.3), Vector2(28, 96.4)], "width": 9.0,
		"green": [Vector2(24, 100), 4.5, 3.5, -42.0, 0, Vector2(-0.74, 0.67), 1, 2, 0.5],
		"bunkers": [],
		"burns": [[[Vector2(69, 53), Vector2(72, 56), Vector2(76, 61)], 1.6]],
		"swales": [[Vector2(28.5, 96), 3.5, 1.5, -42.0, 1]],
		"trees": [],
	},
]

## Gorse in the dunes, well off every line: ellipses [centre, half length, half width, angle].
const GORSE: Array = [
	[Vector2(42, 64), 3.0, 1.5, 30.0], [Vector2(84, 66), 3.0, 1.5, -20.0],
	[Vector2(30, 76), 2.0, 1.5, 0.0], [Vector2(58, 84), 2.5, 1.5, 10.0],
	[Vector2(86, 44), 2.0, 1.2, 0.0],
]


## The finished course as `courses/old_grey_links.json` holds it.
static func course() -> CourseData:
	var c := land()
	var b := CourseBuilder.new(c)
	build(b)
	b.set_info(COURSE_NAME, COURSE_AUTHOR)
	return c


## Flat land, every parcel owned, an unlimited budget (New sandbox).
static func land() -> CourseData:
	return CourseData.create(SIZE, SIZE, Surface.Type.ROUGH, 0)


## The spec of hole `n`.
static func spec(n: int) -> Dictionary:
	for s: Dictionary in HOLES:
		if int(s["n"]) == n:
			return s
	return {}


## Builds the course on `b`'s course. Returns the numbers that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var course: CourseData = b.course
	var level_water: bool = b.level_water
	# Burns and the sea are dug to their level here, so they are laid as paint.
	b.level_water = false
	_shape(b, course)
	var all: Array[Vector2i] = []
	for y: int in SIZE:
		for x: int in SIZE:
			all.append(Vector2i(x, y))
	_paint(b, course, all, Surface.Type.ROUGH)
	_paint(b, course, _rows(0, SEA_ROWS), Surface.Type.WATER)
	_paint(b, course, _rows(SEA_ROWS, SEA_ROWS + BEACH_ROWS), Surface.Type.BUNKER)
	for e: Array in GORSE:
		_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.TREES)
	for s: Dictionary in HOLES:
		_paint_hole(b, course, s)
	for p: Array in PATHS:
		_paint(b, course, PlaytestNine.path_tiles(course, p[2]), Surface.Type.CART_PATH)
	# The bridge over the home hole's burn, on its line.
	_paint(b, course, [Vector2i(72, 56), Vector2i(73, 56)] as Array[Vector2i], Surface.Type.CART_PATH)
	for s: Dictionary in HOLES:
		var n: int = s["n"]
		b.place_tee(n, s["tee"], s["par"])
		b.place_cup(n, s["cup"])
		b.set_par(n, s["par"])
	var first: Vector2i = (HOLES[0] as Dictionary)["tee"]
	var spot: Array = ClubhouseRule.spot_beside(course, first, b.slot_lines(), CLUBHOUSE_REACH)
	b.move_clubhouse(spot[0], spot[1])
	b.level_water = level_water
	var opened: Array[int] = []
	for s: Dictionary in HOLES:
		if b.hole(s["n"]).open:
			opened.append(s["n"])
	return opened


# --- shapes ---

## The tiles of rows `from` to `to` (excluded), the map's width.
static func _rows(from: int, to: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(from, to):
		for x: int in SIZE:
			out.append(Vector2i(x, y))
	return out


## A hole's line, tee to cup through its fairway's points, in tiles.
static func line(s: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(s["tee"])]
	for p: Vector2 in s["fairway"]:
		out.append(p)
	out.append(Vector2(s["cup"]))
	return out


static func _tee_tiles(s: Dictionary) -> Array[Vector2i]:
	return PlaytestNine.tee_tiles(s)


static func _green_tiles(s: Dictionary) -> Array[Vector2i]:
	return PlaytestNine.green_tiles(s)


static func _burn_tiles(burn: Array) -> Array[Vector2i]:
	return PlaytestNine.strip(burn[0], burn[1])


# --- heights ---

## The ground before any hole is set: GROUND plus a gentle roll, rising into dunes away from
## every hole's line.
static func dune_height(x: int, y: int, lines: Array) -> int:
	var p := Vector2(x, y)
	var d := INF
	for l: Array in lines:
		for i: int in l.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, l[i], l[i + 1])
			d = minf(d, p.distance_to(q))
	var roll := 0.45 * sin(x * 0.11 + 0.5) + 0.45 * sin(y * 0.09 + 1.7) + 0.3 * sin((x - y) * 0.05)
	var lumps := 0.5 + 0.25 * sin(x * 0.41 + y * 0.13) + 0.25 * sin(y * 0.37 - x * 0.19 + 2.0)
	var ramp := clampf((d - DUNE_START) / DUNE_RAMP, 0.0, 1.0)
	var h := GROUND + roll + ramp * DUNE_TOP * (0.4 + 0.6 * lumps)
	return clampi(roundi(h), 0, CourseData.MAX_HEIGHT)


static func _shape(b: CourseBuilder, course: CourseData) -> void:
	var w: int = course.width
	var h: int = course.height
	var lines: Array = []
	for s: Dictionary in HOLES:
		lines.append(line(s))
	var target := PackedInt32Array()
	target.resize(w * h)
	for y: int in h:
		for x: int in w:
			target[y * w + x] = dune_height(x, y, lines)
	var locked := {}
	# The sea a step below the beach, the beach at the ground.
	for t: Vector2i in _rows(0, SEA_ROWS + BEACH_ROWS):
		target[t.y * w + t.x] = 0 if t.y < SEA_ROWS else 1
		locked[t] = true
	for s: Dictionary in HOLES:
		var g: Array = s["green"]
		var cells := _green_tiles(s)
		var base: int = _mean(target, w, cells) + int(g[4])
		var centre: Vector2 = g[0]
		var dir: Vector2 = (g[5] as Vector2).normalized()
		for t: Vector2i in cells:
			if not course.in_bounds(t.x, t.y):
				continue
			var proj := (Vector2(t) - centre).dot(dir)
			var rise := 0
			if proj >= float(g[8]):
				rise = clampi(floori((proj - float(g[8])) / float(g[7])) + 1, 0, int(g[6]))
			target[t.y * w + t.x] = clampi(base + rise, 0, CourseData.MAX_HEIGHT)
			locked[t] = true
		var tees := _tee_tiles(s)
		var tee_h: int = clampi(_mean(target, w, tees) + int(s["tee_lift"]), 0, CourseData.MAX_HEIGHT)
		for t: Vector2i in tees:
			target[t.y * w + t.x] = tee_h
			locked[t] = true
		for e: Array in s["bunkers"]:
			var pot := PlaytestNine.ellipse(e)
			var level: int = maxi(_mean(target, w, pot) - int(e[4]), 0)
			for t: Vector2i in pot:
				if course.in_bounds(t.x, t.y) and not locked.has(t):
					target[t.y * w + t.x] = level
					locked[t] = true
		for e: Array in s["swales"]:
			var dip := PlaytestNine.ellipse(e)
			var level: int = maxi(_mean(target, w, dip) - int(e[4]), 0)
			for t: Vector2i in dip:
				if course.in_bounds(t.x, t.y) and not locked.has(t):
					target[t.y * w + t.x] = level
					locked[t] = true
		for burn: Array in s["burns"]:
			var cells_b := _burn_tiles(burn)
			var low := CourseData.MAX_HEIGHT
			for t: Vector2i in cells_b:
				for dy: int in range(-2, 3):
					for dx: int in range(-2, 3):
						if course.in_bounds(t.x + dx, t.y + dy):
							low = mini(low, target[(t.y + dy) * w + t.x + dx])
			for t: Vector2i in cells_b:
				if course.in_bounds(t.x, t.y):
					target[t.y * w + t.x] = maxi(low - 1, 0)
					locked[t] = true
	_ease(target, w, h, locked)
	for pass_i: int in CourseData.MAX_HEIGHT + 1:
		var moved := false
		b.begin_stroke()
		for y: int in h:
			for x: int in w:
				var now := course.get_height(x, y)
				var want: int = target[y * w + x]
				if want > now:
					b.raise(Vector2i(x, y), 1)
					moved = true
				elif want < now:
					b.lower(Vector2i(x, y), 1)
					moved = true
		b.end_stroke()
		if not moved:
			break


## PlaytestNine's slope rule: eases the unlocked ground so edge neighbours differ by one step
## at most and tiles two apart along an axis by one step at most.
static func _ease(target: PackedInt32Array, w: int, h: int, locked: Dictionary) -> void:
	for it: int in 64:
		var changed := false
		for y: int in h:
			for x: int in w:
				if locked.has(Vector2i(x, y)):
					continue
				var lo := 0
				var hi := CourseData.MAX_HEIGHT
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
						Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
					var nx := x + d.x
					var ny := y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var nh: int = target[ny * w + nx]
					lo = maxi(lo, nh - 1)
					hi = mini(hi, nh + 1)
				var cur: int = target[y * w + x]
				var want := cur
				if cur < lo:
					want = lo
				elif cur > hi:
					want = maxi(hi, lo)
				if want != cur:
					target[y * w + x] = want
					changed = true
		if not changed:
			return


static func _mean(target: PackedInt32Array, w: int, cells: Array[Vector2i]) -> int:
	var sum := 0
	var n := 0
	for t: Vector2i in cells:
		if t.x >= 0 and t.y >= 0 and t.x < w and t.y < target.size() / w:
			sum += target[t.y * w + t.x]
			n += 1
	return roundi(float(sum) / maxi(n, 1))


# --- surfaces ---

static func _paint_hole(b: CourseBuilder, course: CourseData, s: Dictionary) -> void:
	var fw: Array[Vector2i] = []
	if not (s["fairway"] as Array).is_empty():
		fw = PlaytestNine.strip(s["fairway"], s["width"])
	for e: Array in s["swales"]:
		fw.append_array(PlaytestNine.ellipse(e))
	_paint(b, course, fw, Surface.Type.FAIRWAY)
	for e: Array in s["bunkers"]:
		_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.BUNKER)
	for burn: Array in s["burns"]:
		_paint(b, course, _burn_tiles(burn), Surface.Type.WATER)
	_paint(b, course, _tee_tiles(s), Surface.Type.TEE)
	_paint(b, course, _green_tiles(s), Surface.Type.GREEN)


static func _paint(b: CourseBuilder, course: CourseData, cells: Array[Vector2i], surface: Surface.Type) -> void:
	b.begin_stroke()
	for t: Vector2i in cells:
		if course.in_bounds(t.x, t.y):
			b.paint(t, surface, 1)
	b.end_stroke()
