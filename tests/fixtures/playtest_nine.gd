class_name PlaytestNine
extends RefCounted
## E3-S50 fixture: a nine-hole course worth a hand playtest, on generated land (LandGenerator
## seed LAND_SEED, every parcel owned, an unlimited budget: New sandbox rules), built through
## CourseBuilder only, the way a player would: shape the ground, paint, place, open.
## `courses/playtest_nine.json` is this course saved with CourseSave; rebuild it with
## `godot --headless --path . -s scripts/play_course.gd -- playtest --save-only`.
##
## Each hole is a spec in HOLES (tile coordinates, 5 yd a tile):
## - tee: the tee marker, on a 3 x 3 tee box (`tee_lift` steps above the ground it sits on).
## - fairway: a polyline of points, painted `width` tiles wide (4 to 7). On a dogleg the
##   fairway bends away from the straight tee-to-cup line, so rule 4 (D47) measures the hole
##   round the corner (CourseValidator.turn_point) and the line of play sets its par.
## - green: [centre, half length, half width, angle in degrees, lift, contour direction,
##   steps, run, offset]: an ellipse of 25 to 60 tiles, `lift` steps above the mean ground
##   under it, rising `steps` one-step contours along `contour direction`, one every `run`
##   tiles, the first `offset` tiles past the centre. Adjacent green tiles never differ by
##   more than one step, so every contour is one D7 holds a still ball on. Most rise toward
##   -x or -y, away from the camera, so their risers face it and the tiers read on screen.
## - bunkers, water, trees: ellipses [centre, half length, half width, angle in degrees]. Water
##   is dug one step below the lowest ground round it, as the land's own ponds are.
## - clear: [polyline, width] painted rough: a chute cut through a tree stand.
##
## Build order: heights first (greens, tees and ponds set, the land's own ponds kept, the
## ground round them eased so neighbours differ by one step and at most one riser every 2
## tiles along an axis, the land generator's slope rule), then every hole's trees and clears,
## then each hole's fairway, bunkers, water, tee box and green, then the tees, cups and pars,
## and last every hole is opened, so no edit lands in an open hole's footprint.

const LAND_SEED: int = 7
const PATH: String = "res://courses/playtest_nine.json"
const COURSE_NAME: String = "Playtest Nine"
const COURSE_AUTHOR: String = "E3-S50"

const HOLES: Array = [
	{
		"n": 1, "par": 5, "tee": Vector2i(121, 5), "cup": Vector2i(120, 112), "tee_lift": 1,
		"fairway": [Vector2(121, 16), Vector2(118, 40), Vector2(122, 66), Vector2(119, 92),
				Vector2(120, 106)],
		"width": 6.0,
		"green": [Vector2(120, 112), 4.5, 3.2, 90.0, 0, Vector2(-1, 0.3), 2, 1, -1.0],
		"bunkers": [[Vector2(115, 45), 2.5, 1.5, 70.0], [Vector2(125, 72), 2.5, 1.5, 100.0],
				[Vector2(115, 110), 1.5, 2.5, 0.0], [Vector2(125, 115), 1.5, 2.0, 0.0]],
		"water": [],
		"trees": [[Vector2(112, 30), 3.0, 2.0, 80.0], [Vector2(126, 42), 1.5, 3.5, 0.0],
				[Vector2(113, 86), 2.5, 2.0, 0.0]],
		"clear": [],
	},
	{
		"n": 2, "par": 3, "tee": Vector2i(116, 121), "cup": Vector2i(88, 114), "tee_lift": 1,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(88, 114), 4.0, 3.0, 20.0, 1, Vector2(-1, 0.3), 1, 1, 0.5],
		"bunkers": [[Vector2(92, 110), 1.5, 2.0, 0.0]],
		"water": [],
		"trees": [],
		"clear": [[[Vector2(114, 120), Vector2(104, 118)], 5.0]],
	},
	{
		"n": 3, "par": 4, "tee": Vector2i(80, 108), "cup": Vector2i(14, 104), "tee_lift": 0,
		"fairway": [Vector2(70, 108), Vector2(56, 106), Vector2(40, 107), Vector2(22, 104)],
		"width": 5.0,
		"green": [Vector2(14, 104), 4.0, 3.0, 100.0, 0, Vector2(-1, 0), 2, 2, -1.0],
		"bunkers": [[Vector2(44, 103), 2.0, 1.2, 0.0], [Vector2(18, 99), 1.5, 1.2, 0.0],
				[Vector2(19, 108), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [[Vector2(60, 112), 4.0, 2.0, 0.0], [Vector2(52, 101), 3.0, 1.5, 0.0]],
		"clear": [],
	},
	{
		"n": 4, "par": 4, "tee": Vector2i(20, 96), "cup": Vector2i(54, 44), "tee_lift": 0,
		"fairway": [Vector2(20, 88), Vector2(19, 70), Vector2(20, 54), Vector2(26, 47),
				Vector2(40, 45), Vector2(50, 44)],
		"width": 5.0,
		"green": [Vector2(54, 44), 4.5, 3.0, 30.0, 0, Vector2(0, -1), 1, 1, 0.5],
		"bunkers": [[Vector2(15, 50), 1.5, 2.5, 0.0], [Vector2(50, 40), 1.5, 1.2, 0.0],
				[Vector2(58, 48), 1.5, 1.2, 0.0]],
		"water": [[Vector2(30, 54), 3.5, 2.5, 0.0]],
		"trees": [[Vector2(25, 80), 2.0, 3.0, 0.0], [Vector2(14, 62), 1.5, 3.0, 0.0]],
		"clear": [],
	},
	{
		"n": 5, "par": 3, "tee": Vector2i(50, 36), "cup": Vector2i(28, 20), "tee_lift": 0,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(28, 20), 3.5, 3.0, 35.0, 0, Vector2(-0.6, -1), 1, 1, 0.5],
		"bunkers": [[Vector2(32, 25), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [],
		"clear": [],
	},
	{
		"n": 6, "par": 4, "tee": Vector2i(22, 12), "cup": Vector2i(88, 3), "tee_lift": 0,
		"fairway": [Vector2(30, 15), Vector2(50, 16), Vector2(70, 16), Vector2(84, 14),
				Vector2(88, 8)],
		"width": 5.0,
		"green": [Vector2(88, 3), 4.0, 2.6, 0.0, 0, Vector2(0, -1), 2, 1, -1.5],
		"bunkers": [[Vector2(82, 6), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [[Vector2(52, 21), 4.0, 1.5, 0.0], [Vector2(74, 9), 2.5, 2.0, 0.0]],
		"clear": [],
	},
	{
		"n": 7, "par": 4, "tee": Vector2i(94, 12), "cup": Vector2i(108, 72), "tee_lift": 0,
		"fairway": [Vector2(93, 20), Vector2(92, 40), Vector2(93, 58), Vector2(100, 66),
				Vector2(104, 70)],
		"width": 5.0,
		"green": [Vector2(108, 72), 4.0, 3.0, 30.0, 0, Vector2(0.4, -1), 1, 1, 0.5],
		"bunkers": [[Vector2(89, 58), 1.2, 2.0, 0.0], [Vector2(106, 76), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [[Vector2(86, 32), 2.0, 4.0, 0.0]],
		"clear": [],
	},
	{
		"n": 8, "par": 3, "tee": Vector2i(101, 80), "cup": Vector2i(56, 76), "tee_lift": 1,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(56, 76), 5.0, 3.5, 0.0, 0, Vector2(-1, 0), 2, 1, 0.0],
		"bunkers": [[Vector2(62, 72), 1.5, 1.2, 0.0], [Vector2(61, 80), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [],
		"clear": [],
	},
	{
		"n": 9, "par": 4, "tee": Vector2i(34, 94), "cup": Vector2i(100, 96), "tee_lift": 0,
		"fairway": [Vector2(44, 95), Vector2(64, 96), Vector2(80, 93), Vector2(94, 95)],
		"width": 5.0,
		"green": [Vector2(100, 96), 4.5, 3.2, 0.0, 0, Vector2(0.2, -1), 1, 2, 0.0],
		"bunkers": [[Vector2(72, 98), 2.0, 1.2, 0.0], [Vector2(104, 92), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [[Vector2(58, 100), 4.0, 1.5, 0.0], [Vector2(78, 89), 3.0, 1.5, 0.0]],
		"clear": [],
	},
]


## The generated land of `land_seed` with every parcel owned.
static func land(land_seed: int = LAND_SEED) -> CourseData:
	return LandGenerator.generate(land_seed)


## The finished course as `courses/playtest_nine.json` holds it: land() built by build(), then
## named. The name is file data, so it goes through CourseSave (to_json, from_dict), which
## makes the named course; nothing else writes CourseData.
static func course() -> CourseData:
	var c := land()
	build(CourseBuilder.new(c))
	var data: Dictionary = JSON.parse_string(CourseSave.to_json(c))
	data["name"] = COURSE_NAME
	data["author"] = COURSE_AUTHOR
	return CourseSave.from_dict(data)


## Builds the course on `b`'s course. Returns the numbers that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var course: CourseData = b.course
	_shape(b, course)
	for spec: Dictionary in HOLES:
		for e: Array in spec["trees"]:
			_paint(b, course, ellipse(e), Surface.Type.TREES)
		for c: Array in spec["clear"]:
			_paint(b, course, strip(c[0], c[1]), Surface.Type.ROUGH)
	for spec: Dictionary in HOLES:
		_paint_hole(b, course, spec)
	for spec: Dictionary in HOLES:
		var n: int = spec["n"]
		b.place_tee(n, spec["tee"], spec["par"])
		b.place_cup(n, spec["cup"])
		b.set_par(n, spec["par"])
	var opened: Array[int] = []
	for spec: Dictionary in HOLES:
		if b.open_hole(spec["n"]):
			opened.append(spec["n"])
	return opened


# --- shapes ---

## Tiles whose centres fall inside the ellipse [centre, half length, half width, angle].
static func ellipse(e: Array) -> Array[Vector2i]:
	var c: Vector2 = e[0]
	var a: float = e[1]
	var r: float = e[2]
	var ang: float = deg_to_rad(e[3])
	var u := Vector2(cos(ang), sin(ang))
	var v := Vector2(-u.y, u.x)
	var reach := ceili(maxf(a, r))
	var out: Array[Vector2i] = []
	for dy: int in range(-reach - 1, reach + 2):
		for dx: int in range(-reach - 1, reach + 2):
			var t := Vector2i(roundi(c.x) + dx, roundi(c.y) + dy)
			var d := Vector2(t) - c
			var p := d.dot(u) / a
			var q := d.dot(v) / r
			if p * p + q * q <= 1.0:
				out.append(t)
	return out


## Tiles whose centres are within `width` / 2 of the polyline `points`.
static func strip(points: Array, width: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if points.is_empty():
		return out
	var seen := {}
	var half := width / 2.0
	var reach := ceili(half) + 1
	for i: int in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[mini(i + 1, points.size() - 1)]
		var lo := Vector2i(floori(minf(a.x, b.x)) - reach, floori(minf(a.y, b.y)) - reach)
		var hi := Vector2i(ceili(maxf(a.x, b.x)) + reach, ceili(maxf(a.y, b.y)) + reach)
		for y: int in range(lo.y, hi.y + 1):
			for x: int in range(lo.x, hi.x + 1):
				var t := Vector2i(x, y)
				if seen.has(t):
					continue
				var p := Vector2(t)
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= half:
					seen[t] = true
					out.append(t)
	return out


## The green's tiles of a spec.
static func green_tiles(spec: Dictionary) -> Array[Vector2i]:
	var g: Array = spec["green"]
	return ellipse([g[0], g[1], g[2], g[3]])


## The tee box's tiles of a spec: 3 x 3 round the tee.
static func tee_tiles(spec: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var t: Vector2i = spec["tee"]
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			out.append(t + Vector2i(dx, dy))
	return out


# --- heights ---

static func _shape(b: CourseBuilder, course: CourseData) -> void:
	var w: int = course.width
	var h: int = course.height
	var target := PackedInt32Array()
	target.resize(w * h)
	for y: int in h:
		for x: int in w:
			target[y * w + x] = course.get_height(x, y)
	# The land's own ponds keep their level.
	var locked := {}
	for y: int in h:
		for x: int in w:
			if course.get_surface(x, y) == Surface.Type.WATER:
				locked[Vector2i(x, y)] = true
	for spec: Dictionary in HOLES:
		var g: Array = spec["green"]
		var cells := green_tiles(spec)
		var base: int = _mean_height(course, cells) + int(g[4])
		var centre: Vector2 = g[0]
		var dir: Vector2 = (g[5] as Vector2).normalized()
		var steps: int = g[6]
		var run: float = float(g[7])
		var off: float = g[8]
		for t: Vector2i in cells:
			if not course.in_bounds(t.x, t.y):
				continue
			var proj := (Vector2(t) - centre).dot(dir)
			var rise := 0
			if proj >= off:
				rise = clampi(floori((proj - off) / run) + 1, 0, steps)
			target[t.y * w + t.x] = clampi(base + rise, 0, CourseData.MAX_HEIGHT)
			locked[t] = true
		var tees := tee_tiles(spec)
		var tee_h: int = clampi(_mean_height(course, tees) + int(spec["tee_lift"]), 0, CourseData.MAX_HEIGHT)
		for t: Vector2i in tees:
			if course.in_bounds(t.x, t.y):
				target[t.y * w + t.x] = tee_h
				locked[t] = true
		for e: Array in spec["water"]:
			var pond := ellipse(e)
			var level: int = maxi(_min_height(course, pond, 2) - 1, 0)
			for t: Vector2i in pond:
				if course.in_bounds(t.x, t.y):
					target[t.y * w + t.x] = level
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


## Eases the unlocked ground round the locked tiles so edge neighbours differ by one step at
## most and tiles two apart along an axis by one step at most (one riser every 2 tiles).
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


static func _mean_height(course: CourseData, cells: Array[Vector2i]) -> int:
	var sum := 0
	var n := 0
	for t: Vector2i in cells:
		if course.in_bounds(t.x, t.y):
			sum += course.get_height(t.x, t.y)
			n += 1
	return roundi(float(sum) / maxi(n, 1))


## The lowest ground within `margin` tiles of `cells` (the cells included).
static func _min_height(course: CourseData, cells: Array[Vector2i], margin: int) -> int:
	var low := CourseData.MAX_HEIGHT
	for t: Vector2i in cells:
		for dy: int in range(-margin, margin + 1):
			for dx: int in range(-margin, margin + 1):
				if course.in_bounds(t.x + dx, t.y + dy):
					low = mini(low, course.get_height(t.x + dx, t.y + dy))
	return low


# --- surfaces ---

static func _paint_hole(b: CourseBuilder, course: CourseData, spec: Dictionary) -> void:
	_paint(b, course, strip(spec["fairway"], spec["width"]), Surface.Type.FAIRWAY)
	for e: Array in spec["bunkers"]:
		_paint(b, course, ellipse(e), Surface.Type.BUNKER)
	for e: Array in spec["water"]:
		_paint(b, course, ellipse(e), Surface.Type.WATER)
	_paint(b, course, tee_tiles(spec), Surface.Type.TEE)
	_paint(b, course, green_tiles(spec), Surface.Type.GREEN)


static func _paint(b: CourseBuilder, course: CourseData, cells: Array[Vector2i], surface: Surface.Type) -> void:
	b.begin_stroke()
	for t: Vector2i in cells:
		if course.in_bounds(t.x, t.y):
			b.paint(t, surface, 1)
	b.end_stroke()
