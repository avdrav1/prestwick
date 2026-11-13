class_name HarborLinks
extends RefCounted
## E13-S1 fixture: "Harbor Links", nine holes over water, each modelled on a famous real water
## hole at its real par and yardage (docs/courses.md credits them; that file is not shipped,
## and no real course or hole name goes in the game or the course file). Laid like
## PlaytestNine (tests/fixtures/playtest_nine.gd) through CourseBuilder only, on flat land
## of SIZE x SIZE tiles at GROUND, every parcel owned (New sandbox): shape the ground, paint,
## place, and every hole opens itself (D64). `courses/harbor_links.json` is this course saved
## with CourseSave; rebuild it with
## `godot --headless --path . -s scripts/save_harbor_links.gd`.
##
## Each hole is a spec in HOLES (tile coordinates, 5 yd a tile), PlaytestNine's format:
## - tee, cup, par, and `yd`, the yardage the hole is built to (its line of play, D47).
## - fairway: a polyline painted `width` tiles wide, or with `curve` the Bezier sweep its points
##   control (PlaytestNine.centre_line).
## - green: [centre, half length, half width, angle in degrees, lift, contour direction,
##   steps, run, offset], PlaytestNine's contoured green (E3-S57): one-step contours D7 holds a
##   still ball on, rising away from the camera so the risers face it.
## - bunkers, water, trees: ellipses [centre, half length, half width, angle in degrees].
## - island: the green stands on an island one tile wider than it, kept dry inside the water.
##
## Water (D66): every water tile is dug one step below GROUND first and then painted with the
## builder's `level_water` on, so each pond floods its own hollow, flat, one step under its
## rim; no pond touches the map's edge, a tee or a green. LAKES are the two big waters several
## holes share: the harbour between the 5th and the 7th (the 7th's "water left all the way",
## the 5th's left) and the west lake round the 9th's island (the 1st's right, the 8th's left).
## CAUSEWAYS keep a dry way across them: the 9th's walkway to its island, so rule 3 joins tee
## to cup and guests have a safe route (HoleChecks, interesting).
##
## Routing: the front four go anticlockwise round the map's edge (up the west side, along the
## top, down the east side, back west along the bottom), the back five in the middle, round
## the harbour and the west lake, finishing on the island across the lake from the clubhouse. Every
## hole has a hazard on its tee-to-cup line and a dry way round it, and every tee sees its
## target (flat ground, tees one step up, no tree on a sight line).
##
## Cart paths (D65, D68): every walk from a green to the next tee is short enough for the least
## patient guest but the 4th green to the 5th tee, round the 4th's pond; PATHS joins that one.
## The clubhouse (D60) goes on the allowed spot nearest the 1st tee (ClubhouseRule.spot_beside).

const PATH: String = "res://courses/harbor_links.json"
const COURSE_NAME: String = "Harbor Links"
const COURSE_AUTHOR: String = "Prestwick"
const SIZE: int = 128
## The land's height step; water is dug one step below it.
const GROUND: int = 2
## How far from hole 1's tee the clubhouse may stand, tiles along x and y.
const CLUBHOUSE_REACH: int = 8

## Shared water: [centre, half length, half width, angle].
const LAKES: Array = [
	# The harbour, between the 7th (west) and the 5th (east).
	[Vector2(81, 74), 30.0, 10.0, 90.0],
	# The west lake round the 9th's island, right of the 1st, and its arm left of the 8th green.
	[Vector2(30, 74), 18.0, 9.0, 90.0],
	[Vector2(38, 60), 5.0, 3.5, 90.0],
]

## Dry ways across the water: [polyline, width], painted rough and never dug.
const CAUSEWAYS: Array = [
	# The 9th's walkway, from the west shore to the back of the island.
	[[Vector2(19, 73), Vector2(24, 73)], 2.0],
]

## Tree stands between holes: ellipses.
const TREES: Array = [
	# Along the west edge beside the 1st, and a stand on its right before the lake.
	[Vector2(3, 62), 28.0, 2.0, 90.0],
	[Vector2(18, 40), 6.0, 1.5, 90.0],
	# Along the top edge above the 2nd.
	[Vector2(60, 2), 28.0, 1.5, 0.0],
	# Between the 2nd and the 6th.
	[Vector2(81, 18), 10.0, 1.5, 0.0],
	# Between the 3rd and the 5th.
	[Vector2(107.5, 66), 20.0, 1.2, 90.0],
	# Between the 7th and the 8th.
	[Vector2(55, 86), 20.0, 1.2, 90.0],
	# Behind the 8th tee, and south of the harbour by the 5th tee.
	[Vector2(30, 118), 12.0, 2.0, 0.0],
	[Vector2(86, 107), 4.0, 2.0, 0.0],
]

## Cart paths: [the green the walk leaves, the tee it reaches, the polyline], 1 tile wide over
## rough and trees only.
const PATHS: Array = [
	# The 4th green north of its pond and east to the 5th tee.
	[4, 5, [Vector2(75, 114), Vector2(80, 111), Vector2(97, 111), Vector2(98, 112)]],
]

const HOLES: Array = [
	{
		# "Heron's Reach": a par 4 up the west edge, the west lake on its right, a creek across
		# the approach.
		"n": 1, "name": "Heron's Reach", "par": 4, "yd": 435,
		"tee": Vector2i(12, 102), "cup": Vector2i(12, 15), "tee_lift": 1,
		"fairway": [Vector2(12, 92), Vector2(12, 31)], "width": 6.0,
		"green": [Vector2(12, 15), 4.5, 3.2, 90.0, 0, Vector2(0.3, -1), 2, 2, -1.0],
		"bunkers": [[Vector2(17.5, 13), 2.2, 1.6, 90.0], [Vector2(6.5, 18), 2.2, 1.6, 90.0],
				[Vector2(7, 58), 1.5, 3.0, 90.0]],
		"water": [[Vector2(13, 26), 8.0, 1.6, 0.0]],
		"trees": [],
	},
	{
		# "Creek Bend": a par 5 along the top, bowing south then back north, a creek across the
		# front of the green; reachable in two.
		"n": 2, "name": "Creek Bend", "par": 5, "yd": 516,
		"tee": Vector2i(19, 7), "cup": Vector2i(122, 12), "tee_lift": 1,
		"fairway": [Vector2(28, 8), Vector2(72, 13), Vector2(104, 12)], "curve": true,
		"width": 7.0,
		"green": [Vector2(122, 12), 4.0, 3.5, 0.0, 0, Vector2(0.3, -1), 2, 2, -1.0],
		"bunkers": [[Vector2(118, 6), 2.4, 1.6, 0.0], [Vector2(80, 7), 2.5, 1.5, 0.0]],
		"water": [[Vector2(108, 12), 1.5, 7.0, 10.0]],
		"trees": [],
	},
	{
		# "Long Wharf": a par 5 down the east edge, a pond right of the green, a bunker in front.
		"n": 3, "name": "Long Wharf", "par": 5, "yd": 517,
		"tee": Vector2i(112, 20), "cup": Vector2i(121, 123), "tee_lift": 1,
		"fairway": [Vector2(113, 30), Vector2(120.5, 112)], "width": 7.0,
		"green": [Vector2(121, 123), 4.5, 3.2, 0.0, 0, Vector2(-1, -0.3), 1, 1, 0.5],
		"bunkers": [[Vector2(120, 115), 2.4, 1.6, 0.0], [Vector2(114.5, 119), 2.2, 1.6, 90.0]],
		"water": [[Vector2(111, 110), 6.0, 3.5, 70.0]],
		"trees": [],
	},
	{
		# "Lantern Pond": a par 3 over a pond to a shallow green set across the line.
		"n": 4, "name": "Lantern Pond", "par": 3, "yd": 185,
		"tee": Vector2i(110, 121), "cup": Vector2i(73, 121), "tee_lift": 1,
		"fairway": [], "width": 5.0,
		"green": [Vector2(73, 121), 5.0, 2.6, 90.0, 0, Vector2(-1, -0.4), 1, 1, 0.5],
		"bunkers": [[Vector2(68.5, 119), 2.4, 1.6, 90.0], [Vector2(77, 116), 2.4, 1.6, 0.0]],
		"water": [[Vector2(90, 121), 10.0, 3.5, 0.0]],
		"trees": [],
	},
	{
		# "Breakwater": a long par 4 north, the harbour on the left, water short and right of
		# the green.
		"n": 5, "name": "Breakwater", "par": 4, "yd": 460,
		"tee": Vector2i(100, 112), "cup": Vector2i(100, 20), "tee_lift": 1,
		"fairway": [Vector2(100, 102), Vector2(100, 30)], "width": 6.0,
		"green": [Vector2(100, 20), 4.0, 3.2, 0.0, 0, Vector2(-0.3, -1), 2, 2, -1.0],
		"bunkers": [[Vector2(95, 15.5), 2.2, 1.6, 0.0], [Vector2(105, 66), 1.5, 3.0, 90.0]],
		"water": [[Vector2(103, 29), 5.0, 3.0, 45.0]],
		"trees": [],
	},
	{
		# "Ferry Crossing": a par 3 west over a creek to a wide, shallow green.
		"n": 6, "name": "Ferry Crossing", "par": 3, "yd": 156,
		"tee": Vector2i(90, 26), "cup": Vector2i(59, 22), "tee_lift": 1,
		"fairway": [], "width": 5.0,
		"green": [Vector2(59, 22), 5.0, 2.5, 90.0, 0, Vector2(-1, -0.3), 1, 1, 0.5],
		"bunkers": [[Vector2(54.5, 18), 2.2, 1.6, 90.0], [Vector2(54.5, 26), 2.2, 1.6, 90.0]],
		"water": [[Vector2(65, 21), 1.4, 5.5, 0.0]],
		"trees": [],
	},
	{
		# "Long Shore": a long par 4 south, the harbour on the left all the way and a bay short
		# and left of the green.
		"n": 7, "name": "Long Shore", "par": 4, "yd": 461,
		"tee": Vector2i(67, 30), "cup": Vector2i(61, 122), "tee_lift": 1,
		"fairway": [Vector2(66.5, 40), Vector2(61.5, 104)], "width": 6.0,
		"green": [Vector2(61, 122), 4.5, 3.2, 0.0, 0, Vector2(-1, -0.3), 2, 2, -1.0],
		"bunkers": [[Vector2(55, 121), 2.4, 1.6, 90.0], [Vector2(58.5, 70), 1.5, 3.0, 90.0]],
		"water": [[Vector2(66, 111), 6.0, 2.5, 0.0]],
		"trees": [],
	},
	{
		# "Short Tack": a short par 4 north, drivable, the west lake's arm left of the green.
		"n": 8, "name": "Short Tack", "par": 4, "yd": 332,
		"tee": Vector2i(51, 118), "cup": Vector2i(44, 52), "tee_lift": 1,
		"fairway": [Vector2(50.5, 108), Vector2(44.5, 60)], "width": 6.0,
		"green": [Vector2(44, 52), 4.0, 3.0, 90.0, 0, Vector2(0.3, -1), 1, 1, 0.5],
		"bunkers": [[Vector2(45, 58.5), 2.2, 1.6, 0.0], [Vector2(49.5, 50), 2.2, 1.6, 90.0]],
		"water": [],
		"trees": [],
	},
	{
		# "Lighthouse Isle": a short par 3 to an island green, a walkway at its back.
		"n": 9, "name": "Lighthouse Isle", "par": 3, "yd": 138,
		"tee": Vector2i(34, 46), "cup": Vector2i(28, 73), "tee_lift": 1,
		"fairway": [], "width": 5.0,
		"green": [Vector2(28, 73), 3.5, 3.0, 0.0, 0, Vector2(-1, -0.5), 1, 2, 0.0],
		"bunkers": [],
		"water": [],
		"trees": [],
		"island": true,
	},
]


## Flat land, SIZE x SIZE at GROUND, every parcel owned (New sandbox).
static func land() -> CourseData:
	return CourseData.create(SIZE, SIZE, Surface.Type.ROUGH, GROUND)


## The finished course as `courses/harbor_links.json` holds it: land() built by build(), then
## named through CourseSave (to_json, from_dict), as PlaytestNine.course does.
static func course() -> CourseData:
	var c := land()
	build(CourseBuilder.new(c))
	var data: Dictionary = JSON.parse_string(CourseSave.to_json(c))
	data["name"] = COURSE_NAME
	data["author"] = COURSE_AUTHOR
	return CourseSave.from_dict(data)


## The spec of hole `n`.
static func spec(n: int) -> Dictionary:
	for s: Dictionary in HOLES:
		if int(s["n"]) == n:
			return s
	return {}


## Builds the course on `b`'s course, water levelled as painted (D66). Returns the numbers
## that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var course: CourseData = b.course
	b.level_water = true
	var water := water_tiles(course)
	_shape(b, course, water)
	for e: Array in TREES:
		_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.TREES)
	for s: Dictionary in HOLES:
		for e: Array in s["trees"]:
			_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.TREES)
	for s: Dictionary in HOLES:
		_paint(b, course, PlaytestNine.fairway_tiles(s), Surface.Type.FAIRWAY)
	for s: Dictionary in HOLES:
		for e: Array in s["bunkers"]:
			_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.BUNKER)
		_paint(b, course, PlaytestNine.tee_tiles(s), Surface.Type.TEE)
		_paint(b, course, PlaytestNine.green_tiles(s), Surface.Type.GREEN)
	for cw: Array in CAUSEWAYS:
		_paint(b, course, PlaytestNine.strip(cw[0], cw[1]), Surface.Type.ROUGH)
	for s: Dictionary in HOLES:
		if s.get("island", false):
			_paint(b, course, _ring(PlaytestNine.green_tiles(s)), Surface.Type.ROUGH)
	# Water last: each dab on a dug tile floods its hollow (D66); a tile already flooded by
	# an earlier dab is skipped.
	b.begin_stroke()
	for t: Vector2i in water:
		if course.get_surface(t.x, t.y) != Surface.Type.WATER:
			b.paint(t, Surface.Type.WATER, 1)
	b.end_stroke()
	for p: Array in PATHS:
		_paint(b, course, PlaytestNine.path_tiles(course, p[2]), Surface.Type.CART_PATH)
	for s: Dictionary in HOLES:
		var n: int = s["n"]
		b.place_tee(n, s["tee"], s["par"])
		b.place_cup(n, s["cup"])
		b.set_par(n, s["par"])
	var first: Vector2i = (HOLES[0] as Dictionary)["tee"]
	var spot: Array = ClubhouseRule.spot_beside(course, first, b.slot_lines(), CLUBHOUSE_REACH)
	b.move_clubhouse(spot[0], spot[1])
	var opened: Array[int] = []
	for s: Dictionary in HOLES:
		if b.hole(s["n"]).open:
			opened.append(s["n"])
	return opened


## The tiles dug and flooded: LAKES and every hole's water, less the CAUSEWAYS, every island
## (its green and the ring round it), tee box and green, sorted.
static func water_tiles(course: CourseData) -> Array[Vector2i]:
	var dry := {}
	for cw: Array in CAUSEWAYS:
		for t: Vector2i in PlaytestNine.strip(cw[0], cw[1]):
			dry[t] = true
	for s: Dictionary in HOLES:
		var green := PlaytestNine.green_tiles(s)
		for t: Vector2i in green:
			dry[t] = true
		if s.get("island", false):
			for t: Vector2i in _ring(green):
				dry[t] = true
		for t: Vector2i in PlaytestNine.tee_tiles(s):
			dry[t] = true
	var wet := {}
	var shapes: Array = LAKES.duplicate()
	for s: Dictionary in HOLES:
		shapes.append_array(s["water"])
	for e: Array in shapes:
		for t: Vector2i in PlaytestNine.ellipse(e):
			# One tile in from the map's edge, so no pond drains off it (D66).
			if t.x >= 1 and t.y >= 1 and t.x < course.width - 1 and t.y < course.height - 1 \
					and not dry.has(t):
				wet[t] = true
	var out: Array[Vector2i] = []
	for t: Vector2i in wet:
		out.append(t)
	out.sort_custom(func(a: Vector2i, c: Vector2i) -> bool: return a.y < c.y or (a.y == c.y and a.x < c.x))
	return out


## The tiles touching `cells` (8 neighbours) that are not in it.
static func _ring(cells: Array[Vector2i]) -> Array[Vector2i]:
	var inside := {}
	for t: Vector2i in cells:
		inside[t] = true
	var seen := {}
	var out: Array[Vector2i] = []
	for t: Vector2i in cells:
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var n := t + Vector2i(dx, dy)
				if not inside.has(n) and not seen.has(n):
					seen[n] = true
					out.append(n)
	return out


# --- heights ---

## Heights: every green contoured and every tee box lifted on the flat land, the water dug one
## step below GROUND, the ground round them eased as PlaytestNine eases it (neighbours one step
## apart at most, one riser every 2 tiles along an axis).
static func _shape(b: CourseBuilder, course: CourseData, water: Array[Vector2i]) -> void:
	var w: int = course.width
	var h: int = course.height
	var target := PackedInt32Array()
	target.resize(w * h)
	target.fill(GROUND)
	var locked := {}
	for t: Vector2i in water:
		target[t.y * w + t.x] = GROUND - 1
		locked[t] = true
	for s: Dictionary in HOLES:
		var g: Array = s["green"]
		var centre: Vector2 = g[0]
		var dir: Vector2 = (g[5] as Vector2).normalized()
		var steps: int = g[6]
		var run: float = float(g[7])
		var off: float = g[8]
		var base: int = GROUND + int(g[4])
		for t: Vector2i in PlaytestNine.green_tiles(s):
			var proj := (Vector2(t) - centre).dot(dir)
			var rise := 0
			if proj >= off:
				rise = clampi(floori((proj - off) / run) + 1, 0, steps)
			target[t.y * w + t.x] = clampi(base + rise, 0, CourseData.MAX_HEIGHT)
			locked[t] = true
		var tee_h: int = clampi(GROUND + int(s["tee_lift"]), 0, CourseData.MAX_HEIGHT)
		for t: Vector2i in PlaytestNine.tee_tiles(s):
			target[t.y * w + t.x] = tee_h
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


## PlaytestNine's easing: the unlocked ground round the locked tiles, so edge neighbours differ
## by one step at most and tiles two apart along an axis by one step at most.
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


static func _paint(b: CourseBuilder, course: CourseData, cells: Array[Vector2i], surface: Surface.Type) -> void:
	b.begin_stroke()
	for t: Vector2i in cells:
		if course.in_bounds(t.x, t.y):
			b.paint(t, surface, 1)
	b.end_stroke()
