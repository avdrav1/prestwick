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
## The routing (E3-S50 rework): four doglegs of about 90 degrees, legs along the tile axes so
## their edges run straight on screen, each a straight leg of about 240 yd to the corner and a
## clearly separate second leg, the inside of the corner blocked by a hill, trees or water;
## every hole's fairway at least 3 tiles of rough or trees from every other hole's. Hole 1
## opens the game framed (Main.frame_first_hole), so it is a dogleg in the north-west whose
## corner points up the screen, clear of the HUD, and the nine finishes beside its tee.
## FILLS are the land's ponds a hole needs the ground of: their water is painted rough and
## raised one step, to the ground round them.
##
## Build order: heights first (greens, tees and ponds set, FILLS raised, the land's other ponds
## kept, the ground round them eased so neighbours differ by one step and at most one riser
## every 2 tiles along an axis, the land generator's slope rule), then FILLS painted rough,
## every hole's trees and clears, then each hole's fairway, bunkers, water, tee box and green,
## then the tees, cups and pars, and last every hole is opened, so no edit lands in an open
## hole's footprint.

const LAND_SEED: int = 7
const PATH: String = "res://courses/playtest_nine.json"
const COURSE_NAME: String = "Playtest Nine"
const COURSE_AUTHOR: String = "E3-S50"

## Land ponds filled (Rect2i, only their water tiles): the pond across hole 1's first leg.
const FILLS: Array[Rect2i] = [Rect2i(0, 32, 21, 14)]

const HOLES: Array = [
	{
		# Dogleg right, the opening hole: north up the west edge, then right along the north
		# flank of the hill, which with its trees fills the inside corner.
		"n": 1, "par": 4, "tee": Vector2i(10, 56), "cup": Vector2i(44, 8), "tee_lift": 1,
		"fairway": [Vector2(10, 51), Vector2(10, 8), Vector2(38, 8)],
		"width": 5.0,
		"green": [Vector2(44, 8), 4.5, 3.2, 0.0, 0, Vector2(-1, 0.3), 2, 1, -1.0],
		"bunkers": [[Vector2(5, 4), 1.5, 2.5, 0.0], [Vector2(41, 12), 1.5, 1.2, 0.0],
				[Vector2(49, 11), 1.2, 1.2, 0.0]],
		"water": [],
		"trees": [[Vector2(19, 18), 5.0, 2.5, 55.0], [Vector2(27, 13), 3.0, 1.5, 0.0],
				[Vector2(16, 49), 1.5, 9.0, 0.0]],
		"clear": [],
	},
	{
		"n": 2, "par": 3, "tee": Vector2i(50, 4), "cup": Vector2i(78, 4), "tee_lift": 0,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(78, 4), 4.0, 3.0, 0.0, 0, Vector2(-1, -0.4), 1, 1, 0.5],
		"bunkers": [[Vector2(73, 8), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [],
		"clear": [],
	},
	{
		# Dogleg right round a pond and the trees inside the corner.
		"n": 3, "par": 4, "tee": Vector2i(70, 12), "cup": Vector2i(118, 52), "tee_lift": 0,
		"fairway": [Vector2(75, 12), Vector2(118, 12), Vector2(118, 46)],
		"width": 5.0,
		"green": [Vector2(118, 52), 4.5, 3.2, 90.0, 0, Vector2(0.3, -1), 2, 1, -1.0],
		"bunkers": [[Vector2(122, 8), 1.5, 2.5, 0.0], [Vector2(113, 55), 1.2, 2.0, 0.0]],
		"water": [[Vector2(110, 20), 4.5, 3.5, 0.0]],
		"trees": [[Vector2(107, 36), 2.5, 6.0, 0.0], [Vector2(124, 30), 1.5, 8.0, 0.0]],
		"clear": [],
	},
	{
		"n": 4, "par": 3, "tee": Vector2i(122, 64), "cup": Vector2i(122, 96), "tee_lift": 0,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(122, 96), 4.0, 3.0, 90.0, 1, Vector2(-1, 0.3), 1, 1, 0.5],
		"bunkers": [[Vector2(117, 93), 1.2, 1.5, 0.0]],
		"water": [],
		"trees": [],
		"clear": [],
	},
	{
		# Dogleg right, the par 5: west between two of the land's ponds, then north up the hill.
		"n": 5, "par": 5, "tee": Vector2i(126, 112), "cup": Vector2i(76, 52), "tee_lift": 0,
		"fairway": [Vector2(121, 112), Vector2(76, 112), Vector2(76, 60)],
		"width": 5.0,
		"green": [Vector2(76, 52), 4.5, 3.0, 0.0, 0, Vector2(0, -1), 1, 1, 0.5],
		"bunkers": [[Vector2(81, 116), 2.5, 1.2, 0.0], [Vector2(82, 55), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [],
		"clear": [],
	},
	{
		# Dogleg left, the other par 5: west through the trees, then south past the pond.
		"n": 6, "par": 5, "tee": Vector2i(71, 46), "cup": Vector2i(22, 108), "tee_lift": 0,
		"fairway": [Vector2(66, 46), Vector2(22, 46), Vector2(22, 102)],
		"width": 5.0,
		"green": [Vector2(22, 108), 4.5, 3.2, 90.0, 0, Vector2(-1, -0.3), 1, 2, 0.0],
		"bunkers": [[Vector2(17, 80), 1.2, 2.5, 0.0], [Vector2(27, 105), 1.2, 2.0, 0.0]],
		"water": [],
		"trees": [[Vector2(30, 56), 3.0, 3.0, 0.0]],
		"clear": [],
	},
	{
		"n": 7, "par": 3, "tee": Vector2i(30, 100), "cup": Vector2i(60, 98), "tee_lift": 1,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(60, 98), 4.5, 3.0, 0.0, 0, Vector2(-1, 0), 2, 2, -1.0],
		"bunkers": [[Vector2(64, 102), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [],
		"clear": [],
	},
	{
		# Straight along the crest of the south hill.
		"n": 8, "par": 4, "tee": Vector2i(70, 118), "cup": Vector2i(6, 118), "tee_lift": 0,
		"fairway": [Vector2(64, 118), Vector2(12, 118)],
		"width": 6.0,
		"green": [Vector2(6, 118), 4.5, 3.0, 0.0, 0, Vector2(0, -1), 1, 1, 0.0],
		"bunkers": [[Vector2(44, 122), 2.0, 1.2, 0.0], [Vector2(11, 113), 1.5, 1.2, 0.0]],
		"water": [],
		"trees": [[Vector2(40, 112), 12.0, 1.5, 0.0], [Vector2(36, 125), 10.0, 1.5, 0.0]],
		"clear": [],
	},
	{
		# Long par 3 up the west edge over the land's pond, finishing beside the first tee.
		"n": 9, "par": 3, "tee": Vector2i(8, 108), "cup": Vector2i(8, 62), "tee_lift": 0,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(8, 62), 4.0, 3.0, 90.0, 0, Vector2(0.2, -1), 1, 2, 0.0],
		"bunkers": [[Vector2(13, 65), 1.2, 1.5, 0.0]],
		"water": [],
		"trees": [],
		"clear": [[[Vector2(8, 106), Vector2(8, 96)], 5.0]],
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
	var filled := _filled(course)
	_shape(b, course, filled)
	_paint(b, course, filled, Surface.Type.ROUGH)
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

## The land's water tiles inside FILLS.
static func _filled(course: CourseData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r: Rect2i in FILLS:
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				if course.in_bounds(x, y) and course.get_surface(x, y) == Surface.Type.WATER:
					out.append(Vector2i(x, y))
	return out


static func _shape(b: CourseBuilder, course: CourseData, filled: Array[Vector2i]) -> void:
	var w: int = course.width
	var h: int = course.height
	var target := PackedInt32Array()
	target.resize(w * h)
	for y: int in h:
		for x: int in w:
			target[y * w + x] = course.get_height(x, y)
	# The land's own ponds keep their level, but for the filled ones, raised to their banks.
	var fill := {}
	for t: Vector2i in filled:
		fill[t] = true
		target[t.y * w + t.x] = mini(course.get_height(t.x, t.y) + 1, CourseData.MAX_HEIGHT)
	var locked := {}
	for y: int in h:
		for x: int in w:
			if course.get_surface(x, y) == Surface.Type.WATER and not fill.has(Vector2i(x, y)):
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
