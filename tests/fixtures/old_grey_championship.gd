class_name OldGreyChampionship
extends RefCounted
## E18-S6 fixture: "Old Grey Links (Championship)", the first famous eighteen. Old Grey Links'
## nine (tests/fixtures/old_grey_links.gd, OldGreyLinks.HOLES, unchanged) is the front nine (Out,
## 1 to 9) on D71's 192 x 192 map; a new back nine (In, 10 to 18, BACK) of nine more famous links
## holes, each at its real par and yardage (docs/courses.md credits them; the names here are our
## own), fills the L of new ground to the south and east. Laid through CourseBuilder only, on
## flat land (CourseData.create: every parcel owned, an unlimited budget, as New sandbox), the
## way OldGreyLinks lays its nine and with its pieces: the dunes, greens, tees, pot bunkers,
## burns, gorse, the sea and beach along the whole north edge, cart paths and bridges.
## `courses/old_grey_championship.json` is this course saved with CourseSave; rebuild it with
## `godot --headless --path . -s scripts/save_old_grey_championship.gd` (with XDG_DATA_HOME set
## to a temporary folder).
##
## The back nine goes out the way the front nine came in and comes home beside it: from the
## clubhouse the 10th runs south-south-east beside its railway, the 11th east along the south
## edge, the 12th and 13th north up the east edge to a green above the beach, the 14th back
## south-west across a chasm, the 15th south down the middle of the new ground, and the 16th to
## 18th west, the home hole ending in front of the clubhouse. The clubhouse stands behind the
## 4th green, between the 1st and 10th tees, with the 9th and 18th greens either side of it, so
## an eighteen turns at its door (D72).
##
## A back-nine spec reads as OldGreyLinks' (tee, cup, fairway, width, green, bunkers, burns,
## swales, trees, bridged), with one more list:
## - lifts: [centre, half length, half width, angle, steps]: ground raised (steps > 0) or
##   lowered (steps < 0) that many steps from the dunes round it, its surface kept (rough or
##   fairway): the railway's embankment, the Pit's wall, Calamity's chasm, the Spectacles' ridge.

const PATH: String = "res://courses/old_grey_championship.json"
const COURSE_NAME: String = "Old Grey Links (Championship)"
const COURSE_AUTHOR: String = "Prestwick"
## D70: the famous course's id and version, written into the file (FamousCourses).
const COURSE_ID: String = "old_grey_championship"
const COURSE_VERSION: int = 1
## D71's map.
const SIZE: int = 192
## The clubhouse: behind the 4th green, its door west toward the 1st and 10th tees.
const CLUBHOUSE: Vector2i = Vector2i(12, 117)
const CLUBHOUSE_FACING: int = 2
## The par of the eighteen: the front nine's 34 and the back's 36.
const PAR: int = 70

## The back nine's cart paths, polylines of tile centres painted 1 tile wide over rough and
## gorse, each [the green the walk leaves (0: none), the tee it reaches (0: none), the polyline]:
## the railway down the 10th's right, on its embankment, and the walks that would take the
## least patient guest over 2.0 s.
const PATHS: Array = [
	[0, 0, [Vector2(2, 131), Vector2(29, 189)]],
	[11, 12, [Vector2(171, 181), Vector2(179, 185)]],
	[13, 14, [Vector2(181, 16), Vector2(174, 22)]],
	[17, 18, [Vector2(103, 148), Vector2(107, 142)]],
]

const BACK: Array = [
	{
		# Out from the clubhouse, a straight drive with the railway all down the right.
		"n": 10, "name": "The Line", "par": 4, "yd": 342,
		"tee": Vector2i(8, 124), "cup": Vector2i(37, 186), "tee_lift": 1,
		"fairway": [Vector2(9.7, 127.6), Vector2(35.3, 182.4)], "width": 7.0,
		"green": [Vector2(37, 186), 4.5, 3.5, 64.9, 0, Vector2(0.42, 0.91), 1, 2, 0.5],
		"bunkers": [[Vector2(30.3, 163.3), 1.2, 1.2, 0.0, 1], [Vector2(34, 179.7), 1.2, 1.2, 0.0, 1]],
		"burns": [],
		"swales": [],
		"trees": [],
		"lifts": [[Vector2(15.5, 160), 33.0, 1.2, 65.0, 1]],
	},
	{
		# The long par 5 east along the south edge: two bunkers in the middle of the fairway at
		# the drive leave an alley left of them, and the burn crosses before the green.
		"n": 11, "name": "Long Alley", "par": 5, "yd": 580,
		"tee": Vector2i(50, 183), "cup": Vector2i(166, 180), "tee_lift": 1,
		"fairway": [Vector2(54, 182.9), Vector2(162, 180.1)], "width": 9.0,
		"green": [Vector2(166, 180), 4.5, 3.5, -1.5, 0, Vector2(1, 0), 1, 2, 0.5],
		"bunkers": [[Vector2(98, 181.7), 1.5, 1.5, 0.0, 1], [Vector2(104, 183.6), 1.5, 1.5, 0.0, 1],
				[Vector2(162, 176.5), 1.2, 1.2, 0.0, 1], [Vector2(163, 184), 1.2, 1.2, 0.0, 0]],
		"burns": [[[Vector2(140, 175), Vector2(137, 180), Vector2(140, 185), Vector2(138, 191)], 2.0]],
		"swales": [],
		"trees": [],
		"lifts": [],
		"bridged": true,
	},
	{
		# North up the east edge; the burn in its gully crosses just short of the green.
		"n": 12, "name": "Wee Water", "par": 4, "yd": 450,
		"tee": Vector2i(181, 186), "cup": Vector2i(182, 96), "tee_lift": 1,
		"fairway": [Vector2(181, 182), Vector2(182, 100)], "width": 7.0,
		"green": [Vector2(182, 96), 4.5, 3.5, -89.4, 0, Vector2(0, -1), 1, 2, 0.5],
		"bunkers": [[Vector2(177.5, 99), 1.2, 1.2, 0.0, 1], [Vector2(178, 140), 1.2, 1.2, 0.0, 0]],
		"burns": [[[Vector2(176, 104), Vector2(181, 102), Vector2(186, 104), Vector2(191, 102)], 2.0]],
		"swales": [],
		"trees": [],
		"lifts": [],
		"bridged": true,
	},
	{
		# On north to the beach: a wall (a one-step ridge) right across the fairway in front of
		# a green sunk a step in its pit, the sea just over its back.
		"n": 13, "name": "The Wall", "par": 4, "yd": 370,
		"tee": Vector2i(184, 86), "cup": Vector2i(184, 12), "tee_lift": 1,
		"fairway": [Vector2(184, 82), Vector2(184, 16)], "width": 7.0,
		"green": [Vector2(184, 12), 4.5, 3.5, -90.0, -1, Vector2(0, -1), 1, 2, 0.5],
		"bunkers": [[Vector2(184, 40), 1.2, 1.2, 0.0, 1], [Vector2(188.5, 15), 1.0, 1.2, 0.0, 0]],
		"burns": [],
		"swales": [],
		"trees": [],
		"lifts": [[Vector2(184, 18.5), 4.5, 0.8, 0.0, 1]],
	},
	{
		# The long par 3 back south-west to a green perched over a chasm on its right.
		"n": 14, "name": "Misfortune", "par": 3, "yd": 234,
		"tee": Vector2i(172, 22), "cup": Vector2i(136, 52), "tee_lift": 1,
		"fairway": [Vector2(147, 42.8), Vector2(140, 48.6)], "width": 5.0,
		"green": [Vector2(136, 52), 4.0, 3.5, 140.2, 1, Vector2(-0.77, 0.64), 1, 2, 0.0],
		"bunkers": [[Vector2(141.4, 47.5), 1.0, 1.0, 0.0, 1]],
		"burns": [],
		"swales": [],
		"trees": [],
		"lifts": [[Vector2(137.6, 43.0), 6.0, 2.5, 140.2, -2]],
	},
	{
		# The par 5 south down the middle: two pot bunkers side by side in a ridge across the
		# fairway short of the green.
		"n": 15, "name": "The Goggles", "par": 5, "yd": 511,
		"tee": Vector2i(141, 58), "cup": Vector2i(146, 160), "tee_lift": 1,
		"fairway": [Vector2(141.2, 62), Vector2(145.8, 156)], "width": 8.0,
		"green": [Vector2(146, 160), 4.5, 3.5, 87.2, 0, Vector2(0.05, 1), 1, 2, 0.5],
		"bunkers": [[Vector2(144.6, 149.5), 1.2, 1.2, 0.0, 1], [Vector2(147.8, 149.5), 1.2, 1.2, 0.0, 1]],
		"burns": [],
		"swales": [],
		"trees": [],
		"lifts": [[Vector2(145.5, 149.5), 7.0, 1.6, 0.0, 1]],
	},
	{
		# West, a cluster of bunkers in the middle of the fairway at the drive and one beyond.
		"n": 16, "name": "The Nose", "par": 4, "yd": 421,
		"tee": Vector2i(136, 166), "cup": Vector2i(52, 160), "tee_lift": 1,
		"fairway": [Vector2(132, 165.7), Vector2(56, 160.3)], "width": 8.0,
		"green": [Vector2(52, 160), 4.5, 3.5, -175.9, 0, Vector2(-1, -0.07), 1, 2, 0.5],
		"bunkers": [[Vector2(84, 162.6), 1.2, 1.2, 0.0, 1], [Vector2(86.5, 165), 1.0, 1.0, 0.0, 1],
				[Vector2(86, 160.6), 1.0, 1.0, 0.0, 1], [Vector2(72, 161.6), 1.2, 1.2, 0.0, 1]],
		"burns": [],
		"swales": [],
		"trees": [],
		"lifts": [],
	},
	{
		# The short par 3 back east to a long, narrow green sunk in a hollow, bunkers both sides.
		"n": 17, "name": "Sandhill Hollow", "par": 3, "yd": 191,
		"tee": Vector2i(60, 154), "cup": Vector2i(98, 150), "tee_lift": 1,
		"fairway": [], "width": 5.0,
		"green": [Vector2(98, 150), 5.0, 2.5, -6.0, -1, Vector2(1, -0.1), 1, 2, 0.5],
		"bunkers": [[Vector2(93, 150.5), 1.0, 1.0, 0.0, 1], [Vector2(97.5, 146.5), 1.6, 0.9, -6.0, 1],
				[Vector2(98.5, 153.5), 1.6, 0.9, -6.0, 1]],
		"burns": [],
		"swales": [],
		"trees": [],
		"lifts": [],
	},
	{
		# Home, west to a green under the clubhouse windows: bunkers across the fairway on a
		# diagonal at the drive and either side of the green's front.
		"n": 18, "name": "Home Rows", "par": 4, "yd": 411,
		"tee": Vector2i(108, 140), "cup": Vector2i(26, 134), "tee_lift": 1,
		"fairway": [Vector2(104, 139.7), Vector2(30, 134.3)], "width": 8.0,
		"green": [Vector2(26, 134), 4.5, 3.5, -175.8, 0, Vector2(-1, -0.07), 1, 2, 0.5],
		"bunkers": [[Vector2(62, 136.6), 1.2, 1.2, 0.0, 1], [Vector2(58, 139), 1.0, 1.0, 0.0, 1],
				[Vector2(66, 134.2), 1.0, 1.0, 0.0, 1], [Vector2(31, 131), 1.0, 1.2, 0.0, 1],
				[Vector2(31, 137.5), 1.0, 1.2, 0.0, 1]],
		"burns": [],
		"swales": [],
		"trees": [],
		"lifts": [],
	},
]

## Gorse in the new dunes, well off every line, as OldGreyLinks.GORSE.
const GORSE: Array = [
	[Vector2(162, 120), 3.0, 1.5, 80.0], [Vector2(162, 64), 2.5, 1.5, 70.0],
	[Vector2(165, 150), 2.0, 1.5, 0.0], [Vector2(40, 148), 2.0, 1.2, 10.0],
	[Vector2(118, 152), 2.5, 1.2, 0.0],
]


## The eighteen holes' specs: Old Grey Links' nine, then the back nine.
static func holes() -> Array:
	var out: Array = OldGreyLinks.HOLES.duplicate()
	out.append_array(BACK)
	return out


## The spec of hole `n`.
static func spec(n: int) -> Dictionary:
	for s: Dictionary in holes():
		if int(s["n"]) == n:
			return s
	return {}


## The finished course as `courses/old_grey_championship.json` holds it.
static func course() -> CourseData:
	var c := land()
	var b := CourseBuilder.new(c)
	build(b)
	b.set_info(COURSE_NAME, COURSE_AUTHOR)
	c.set_course_id(COURSE_ID, COURSE_VERSION)
	return c


## Flat land, every parcel owned, an unlimited budget (New sandbox).
static func land() -> CourseData:
	return CourseData.create(SIZE, SIZE, Surface.Type.ROUGH, 0)


## Builds the course on `b`'s course. Returns the numbers that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var course: CourseData = b.course
	var level_water: bool = b.level_water
	b.level_water = false
	var specs := holes()
	_shape(b, course, specs)
	var all: Array[Vector2i] = []
	for y: int in SIZE:
		for x: int in SIZE:
			all.append(Vector2i(x, y))
	_paint(b, course, all, Surface.Type.ROUGH)
	_paint(b, course, _rows(0, OldGreyLinks.SEA_ROWS), Surface.Type.WATER)
	_paint(b, course, _rows(OldGreyLinks.SEA_ROWS, OldGreyLinks.SEA_ROWS + OldGreyLinks.BEACH_ROWS),
			Surface.Type.BUNKER)
	for e: Array in OldGreyLinks.GORSE + GORSE:
		_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.TREES)
	for s: Dictionary in specs:
		_paint_hole(b, course, s)
	for p: Array in OldGreyLinks.PATHS + PATHS:
		_paint(b, course, PlaytestNine.path_tiles(course, p[2]), Surface.Type.CART_PATH)
	# Old Grey Links' bridges, as its nine lays them, then the back nine's on its burns' lines.
	FixtureBridges.lay(b, [Vector2(74, 56), Vector2(70, 56)])
	for s: Dictionary in specs:
		if s.get("bridged", false):
			FixtureBridges.lay(b, OldGreyLinks.line(s))
	for s: Dictionary in specs:
		var n: int = s["n"]
		b.place_tee(n, s["tee"], s["par"])
		b.place_cup(n, s["cup"])
		b.set_par(n, s["par"])
	if not b.move_clubhouse(CLUBHOUSE, CLUBHOUSE_FACING):
		push_error("OldGreyChampionship: the clubhouse refused at %s" % CLUBHOUSE)
	b.level_water = level_water
	var opened: Array[int] = []
	for s: Dictionary in specs:
		if b.hole(s["n"]).open:
			opened.append(s["n"])
	return opened


static func _rows(from: int, to: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(from, to):
		for x: int in SIZE:
			out.append(Vector2i(x, y))
	return out


# --- heights: OldGreyLinks._shape over all eighteen lines, with the back nine's lifts ---

static func _shape(b: CourseBuilder, course: CourseData, specs: Array) -> void:
	var w: int = course.width
	var h: int = course.height
	var lines: Array = []
	for s: Dictionary in specs:
		lines.append(OldGreyLinks.line(s))
	var target := PackedInt32Array()
	target.resize(w * h)
	for y: int in h:
		for x: int in w:
			target[y * w + x] = OldGreyLinks.dune_height(x, y, lines)
	var locked := {}
	for t: Vector2i in _rows(0, OldGreyLinks.SEA_ROWS + OldGreyLinks.BEACH_ROWS):
		target[t.y * w + t.x] = 0 if t.y < OldGreyLinks.SEA_ROWS else 1
		locked[t] = true
	for s: Dictionary in specs:
		for e: Array in s.get("lifts", []):
			var cells := PlaytestNine.ellipse(e)
			var level: int = clampi(OldGreyLinks._mean(target, w, cells) + int(e[4]), 0, CourseData.MAX_HEIGHT)
			for t: Vector2i in cells:
				if course.in_bounds(t.x, t.y) and not locked.has(t):
					target[t.y * w + t.x] = level
					locked[t] = true
	for s: Dictionary in specs:
		var g: Array = s["green"]
		var cells := PlaytestNine.green_tiles(s)
		var base: int = OldGreyLinks._mean(target, w, cells) + int(g[4])
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
		var tees := PlaytestNine.tee_tiles(s)
		var tee_h: int = clampi(OldGreyLinks._mean(target, w, tees) + int(s["tee_lift"]), 0, CourseData.MAX_HEIGHT)
		for t: Vector2i in tees:
			target[t.y * w + t.x] = tee_h
			locked[t] = true
		for e: Array in s["bunkers"]:
			var pot := PlaytestNine.ellipse(e)
			var level: int = maxi(OldGreyLinks._mean(target, w, pot) - int(e[4]), 0)
			for t: Vector2i in pot:
				if course.in_bounds(t.x, t.y) and not locked.has(t):
					target[t.y * w + t.x] = level
					locked[t] = true
		for e: Array in s["swales"]:
			var dip := PlaytestNine.ellipse(e)
			var level: int = maxi(OldGreyLinks._mean(target, w, dip) - int(e[4]), 0)
			for t: Vector2i in dip:
				if course.in_bounds(t.x, t.y) and not locked.has(t):
					target[t.y * w + t.x] = level
					locked[t] = true
		for burn: Array in s["burns"]:
			var cells_b := PlaytestNine.strip(burn[0], burn[1])
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
	OldGreyLinks._ease(target, w, h, locked)
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
		_paint(b, course, PlaytestNine.strip(burn[0], burn[1]), Surface.Type.WATER)
	_paint(b, course, PlaytestNine.tee_tiles(s), Surface.Type.TEE)
	_paint(b, course, PlaytestNine.green_tiles(s), Surface.Type.GREEN)


static func _paint(b: CourseBuilder, course: CourseData, cells: Array[Vector2i], surface: Surface.Type) -> void:
	b.begin_stroke()
	for t: Vector2i in cells:
		if course.in_bounds(t.x, t.y):
			b.paint(t, surface, 1)
	b.end_stroke()
