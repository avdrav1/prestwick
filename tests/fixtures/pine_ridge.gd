class_name PineRidge
extends RefCounted
## E13-S3 fixture: "Pine Ridge", nine holes of tree-lined parkland, each modelled on a famous
## real parkland or heathland hole at its real par and yardage (scaled only where the 128 x 128
## map forces it; docs/courses.md names the hole each is modelled on). Course and hole names
## are original. Built through CourseBuilder only, the way tests/fixtures/playtest_nine.gd is:
## shape the ground, paint, place, open. `courses/pine_ridge.json` is this course saved with
## CourseSave; rebuild it with
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s res://tests/fixtures/pine_ridge_save.gd
##
## The land: a blank 128 x 128 plot (BuilderTuning's, every parcel owned, an unlimited budget:
## New sandbox rules) raised into a pine ridge by RIDGE: a long rise in the west where the
## clubhouse, the 1st tee and the 9th green stand, and a plateau in the east centre the 8th
## drops off. Heights are eased so edge neighbours differ by one step at most and there is at
## most one riser every 2 tiles along an axis (the land generator's slope rule).
##
## Each hole is a spec in HOLES (tile coordinates, 5 yd a tile), as PlaytestNine's:
## - tee, tee_lift, fairway (polyline, or with `curve` the Bezier curve it controls), width.
## - green: [centre, half length, half width, angle, lift, contour direction, steps, run,
##   offset], PlaytestNine's contours; a contour direction of Vector2.ZERO crowns the green
##   instead (`steps` one-step rings rising to its middle, each an equal share of the
##   ellipse's radius): the turtleback, whose edges shed a ball.
## - bunkers, trees: ellipses [centre, half length, half width, angle]. `pews` lays rows of
##   thin bunkers beside the fairway, across the line of play: [from, to (tiles from the tee
##   along the tee-to-cup line), spacing, offset to the left of the line, half length].
## - creek: [polyline, width] of water, dug one step below the lowest ground near it.
## - yd: the yardage the validator measures (rule 4, D47's line of play), the spec the test holds.
##
## Parkland: every hole plays down its own corridor of rough (CORRIDOR_ROUGH past the fairway's
## edge, or round a par 3's line) walled by a belt of pines (BELT tiles), so the holes are
## tree-lined and apart; the belts are painted first and every corridor and walk lane cut
## through them after, so no belt closes another hole's corridor. WOODS adds stands in the open
## ground between. The doglegs (holes 1, 5 and 9) bow far enough off the straight tee-to-cup
## line that rule 4's disc holds no fairway, so D47 measures them round the bend and D51 puts
## their zone and footprint on the line of play.
##
## Walks (D65, D68): a lane of rough is cut on every walk (the clubhouse door to the 1st tee,
## each green to the next tee), and the walks too long for the Walk check get a cart path
## (PATHS), checked with GuestWalk.why.
##
## Build order (PlaytestNine's): heights first (greens, tees and creeks set, the rest eased),
## then the belts, corridors, lanes and woods, then each hole's fairway, bunkers, water, tee box
## and green, then the cart paths, the tees, cups and pars, the clubhouse beside the 1st tee
## (ClubhouseRule.spot_beside), and every hole opens as its cup is placed.

const PATH: String = "res://courses/pine_ridge.json"
const COURSE_NAME: String = "Pine Ridge"
const COURSE_AUTHOR: String = "Prestwick"
## The ground every rise in RIDGE starts from.
const BASE_HEIGHT: float = 1.0
## The rises: [centre, sigma (tiles), height in steps], summed as Gaussian bumps.
const RIDGE: Array = [
	[Vector2(10, 74), 24.0, 4.0],
	[Vector2(86, 80), 18.0, 4.0],
	[Vector2(28, 22), 14.0, 1.5],
	[Vector2(118, 40), 16.0, 1.5],
]
## Rough kept each side of a fairway's edge (tiles), and round a par 3's line.
const CORRIDOR_ROUGH: float = 4.0
const PAR3_HALF: float = 6.0
## Rough round a green, from its centre (tiles).
const GREEN_CLEAR: float = 7.0
## The pine belt beyond a corridor (tiles).
const BELT: float = 6.0
## A walk lane's width (tiles).
const LANE: float = 3.0
## How far from the 1st tee the clubhouse may stand, tiles along x and y.
const CLUBHOUSE_REACH: int = 8

## Stands of pines in the open ground between the belts.
const WOODS: Array = [
	[Vector2(78, 60), 12.0, 7.0, 30.0],
	[Vector2(60, 76), 6.0, 5.0, 0.0],
	[Vector2(88, 108), 6.0, 3.0, -30.0],
	[Vector2(30, 40), 5.0, 4.0, 60.0],
	[Vector2(64, 106), 5.0, 3.0, 0.0],
]

## Cart paths, polylines of tile centres painted 1 tile wide over rough and trees:
## [the green the walk leaves (0 the clubhouse), the tee it reaches, the polyline].
const PATHS: Array = [
	# Off the 7th green's north-east, up onto the plateau to the raised 8th tee (102 yd).
	[7, 8, [Vector2(77, 91), Vector2(90, 89)]],
]

const HOLES: Array = [
	{
		# Dogleg right round a stand of pines: down off the ridge north, turning east at the
		# corner to a green below the knoll.
		"n": 1, "name": "Sentry Pines", "par": 4, "yd": 345,
		"tee": Vector2i(14, 66), "cup": Vector2i(36, 8), "tee_lift": 1,
		"fairway": [Vector2(13, 61), Vector2(9, 8), Vector2(29, 8)], "curve": true,
		"width": 5.0,
		"green": [Vector2(36, 8), 4.5, 3.2, 0.0, 0, Vector2(-0.3, -1), 1, 1, 0.5],
		"bunkers": [[Vector2(40, 4.5), 1.5, 1.0, 0.0], [Vector2(32, 12.5), 1.5, 1.0, 0.0]],
		"trees": [[Vector2(24, 26), 6.0, 3.5, -50.0]],
	},
	{
		# A short par 4 along the north, bunkers left of the landing and one in front.
		"n": 2, "name": "Long Meadow", "par": 4, "yd": 350,
		"tee": Vector2i(46, 8), "cup": Vector2i(116, 8), "tee_lift": 0,
		"fairway": [Vector2(51, 8), Vector2(108, 8)],
		"width": 5.0,
		"green": [Vector2(116, 8), 4.0, 3.0, 0.0, 0, Vector2(-0.3, -1), 1, 1, 0.5],
		"bunkers": [[Vector2(92, 4), 1.5, 0.8, 0.0], [Vector2(97, 3.5), 1.2, 0.8, 0.0],
				[Vector2(111, 8.5), 1.0, 1.2, 0.0]],
		"trees": [],
	},
	{
		# The little par 3, a small green ringed with sand.
		"n": 3, "name": "Thimble", "par": 3, "yd": 125,
		"tee": Vector2i(121, 16), "cup": Vector2i(121, 41), "tee_lift": 2,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(121, 41), 3.5, 3.0, 90.0, 0, Vector2(-1, 0.2), 1, 1, 0.5],
		"bunkers": [[Vector2(121, 36.5), 1.5, 0.8, 0.0], [Vector2(116.5, 41), 0.8, 1.8, 0.0],
				[Vector2(125.2, 40), 0.6, 1.5, 0.0]],
		"trees": [],
	},
	{
		# Straight down the east side to a crowned green that sheds a ball off every edge.
		"n": 4, "name": "Turtle Back", "par": 4, "yd": 372,
		"tee": Vector2i(124, 49), "cup": Vector2i(116, 123), "tee_lift": 0,
		"fairway": [Vector2(123, 54), Vector2(117, 112)],
		"width": 5.0,
		"green": [Vector2(116, 123), 4.5, 3.5, 0.0, 1, Vector2.ZERO, 1, 2, 0.0],
		"bunkers": [[Vector2(119, 86), 1.2, 2.0, 0.0], [Vector2(116.5, 116.5), 1.2, 1.0, 0.0]],
		"trees": [],
	},
	{
		# The par 5: north up the plateau's flank, sweeping left round the pines to a green
		# behind a creek that runs down the inside of the bend and across the front.
		"n": 5, "name": "Creekside Bend", "par": 5, "yd": 513,
		"tee": Vector2i(108, 118), "cup": Vector2i(64, 30), "tee_lift": 0,
		"fairway": [Vector2(107, 113), Vector2(104, 50), Vector2(74, 32)], "curve": true,
		"width": 6.0,
		"green": [Vector2(64, 30), 4.5, 3.5, 20.0, 0, Vector2(-1, -0.3), 1, 1, 0.5],
		"bunkers": [[Vector2(59, 25.5), 1.2, 1.8, 30.0], [Vector2(60, 35), 1.0, 1.5, 0.0]],
		"creek": [[Vector2(86, 52), Vector2(77, 43), Vector2(69.5, 36), Vector2(69.5, 26)], 2.0],
		"trees": [[Vector2(88, 68), 8.0, 4.0, 50.0]],
	},
	{
		# Long and straight down the west side, rows of narrow bunkers left of the landing.
		"n": 6, "name": "Chapel Rows", "par": 4, "yd": 427,
		"tee": Vector2i(57, 22), "cup": Vector2i(33, 104), "tee_lift": 1,
		"fairway": [Vector2(56, 27), Vector2(36, 95)],
		"width": 6.0,
		"green": [Vector2(33, 104), 4.5, 3.2, 75.0, 0, Vector2(-1, -0.3), 2, 1, -1.0],
		"bunkers": [[Vector2(35, 99), 1.0, 1.2, 0.0]],
		"pews": [36.0, 54.0, 3.0, 6.0, 2.8],
		"trees": [],
	},
	{
		# The short par 3 over the creek to a wide, shallow green, sand in front and behind.
		"n": 7, "name": "Footbridge", "par": 3, "yd": 155,
		"tee": Vector2i(42, 94), "cup": Vector2i(73, 94), "tee_lift": 0,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(73, 94), 2.6, 5.0, 0.0, 0, Vector2(0, -1), 1, 2, 0.0],
		"bunkers": [[Vector2(69.5, 97), 0.8, 1.6, 0.0], [Vector2(77, 90), 0.9, 1.4, 0.0],
				[Vector2(77.5, 98), 0.9, 1.4, 0.0]],
		"creek": [[Vector2(66, 92), Vector2(67, 103)], 2.0],
		"trees": [],
	},
	{
		# Downhill off the plateau to a green framed by pines.
		"n": 8, "name": "Ridge Drop", "par": 3, "yd": 180,
		"tee": Vector2i(93, 90), "cup": Vector2i(76, 122), "tee_lift": 1,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(76, 122), 4.0, 3.2, 0.0, 0, Vector2(-1, -0.4), 1, 1, 0.5],
		"bunkers": [[Vector2(79, 117), 1.2, 1.0, 30.0], [Vector2(81, 123), 0.9, 1.4, 0.0]],
		"trees": [],
	},
	{
		# The closer: west along the south through a chute of pines, turning right at the
		# corner and climbing to a green on the ridge beside the clubhouse.
		"n": 9, "name": "Homeward Climb", "par": 4, "yd": 457,
		"tee": Vector2i(64, 120), "cup": Vector2i(8, 73), "tee_lift": 0,
		"fairway": [Vector2(59, 120), Vector2(14, 121), Vector2(7, 121), Vector2(8, 79)],
		"curve": true,
		"width": 5.0,
		"green": [Vector2(8, 73), 4.0, 3.2, 90.0, 0, Vector2(0.3, -1), 1, 1, 0.0],
		"bunkers": [[Vector2(4, 124), 1.5, 1.2, 0.0], [Vector2(12.5, 78.5), 1.2, 1.0, -40.0]],
		"trees": [],
	},
]


## The blank plot the course is laid on: BuilderTuning's size, surface and ground, every
## parcel owned, an unlimited budget (New sandbox), no clubhouse yet.
static func land() -> CourseData:
	var t := BuilderTuning.load_default()
	return CourseData.create(t.plot_size.x, t.plot_size.y, t.plot_surface, t.plot_ground)


## The finished course as `courses/pine_ridge.json` holds it: land() built by build(), then
## named through CourseSave (to_json, from_dict), which makes the named course.
static func course() -> CourseData:
	var c := land()
	build(CourseBuilder.new(c))
	var data: Dictionary = JSON.parse_string(CourseSave.to_json(c))
	data["name"] = COURSE_NAME
	data["author"] = COURSE_AUTHOR
	return CourseSave.from_dict(data)


## The spec of hole `n`, or an empty Dictionary.
static func spec_of(n: int) -> Dictionary:
	for spec: Dictionary in HOLES:
		if spec["n"] == n:
			return spec
	return {}


## Builds the course on `b`'s course. Returns the numbers that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var course: CourseData = b.course
	var level_water: bool = b.level_water
	b.level_water = false
	_shape(b, course)
	var belts: Array[Vector2i] = []
	var cuts: Array[Vector2i] = []
	for spec: Dictionary in HOLES:
		var line := corridor_line(spec)
		var half := corridor_half(spec)
		belts.append_array(PlaytestNine.strip(line, 2.0 * (half + BELT)))
		var cup := Vector2(spec["cup"] as Vector2i)
		belts.append_array(PlaytestNine.strip([cup, cup], 2.0 * (GREEN_CLEAR + BELT)))
		cuts.append_array(PlaytestNine.strip(line, 2.0 * half))
		cuts.append_array(PlaytestNine.strip([cup, cup], 2.0 * GREEN_CLEAR))
	_paint(b, course, belts, Surface.Type.TREES)
	for e: Array in WOODS:
		_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.TREES)
	_paint(b, course, cuts, Surface.Type.ROUGH)
	var lanes: Array[Vector2i] = []
	for w: Array in walks():
		lanes.append_array(PlaytestNine.strip(w, LANE))
	_paint(b, course, lanes, Surface.Type.ROUGH)
	for spec: Dictionary in HOLES:
		for e: Array in spec["trees"]:
			_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.TREES)
	for spec: Dictionary in HOLES:
		_paint_hole(b, course, spec)
	for p: Array in PATHS:
		_paint(b, course, PlaytestNine.path_tiles(course, p[2]), Surface.Type.CART_PATH)
	for spec: Dictionary in HOLES:
		var n: int = spec["n"]
		b.place_tee(n, spec["tee"], spec["par"])
		b.place_cup(n, spec["cup"])
		b.set_par(n, spec["par"])
	var first: Vector2i = (HOLES[0] as Dictionary)["tee"]
	var spot: Array = ClubhouseRule.spot_beside(course, first, b.slot_lines(), CLUBHOUSE_REACH)
	b.move_clubhouse(spot[0], spot[1])
	b.level_water = level_water
	var opened: Array[int] = []
	for spec: Dictionary in HOLES:
		if b.hole(spec["n"]).open:
			opened.append(spec["n"])
	return opened


## The walks a round takes, as tile polylines: the clubhouse spot beside the 1st tee is not
## known before the build, so the first lane runs from the 1st tee toward the ridge's crest
## (east of it, where the clubhouse stands); then each green to the next tee.
static func walks() -> Array:
	var out: Array = []
	var first: Vector2i = (HOLES[0] as Dictionary)["tee"]
	out.append([Vector2(first), Vector2(first) + Vector2(CLUBHOUSE_REACH, 0)])
	for i: int in HOLES.size() - 1:
		var a: Dictionary = HOLES[i]
		var c: Dictionary = HOLES[i + 1]
		out.append([Vector2(a["cup"]), Vector2(c["tee"])])
	return out


## A hole's corridor centre line: tee, the fairway's centre line, cup.
static func corridor_line(spec: Dictionary) -> Array:
	var out: Array = [Vector2(spec["tee"] as Vector2i)]
	for p: Vector2 in PlaytestNine.centre_line(spec):
		out.append(p)
	out.append(Vector2(spec["cup"] as Vector2i))
	return out


## Half the corridor's width: the fairway's half width and CORRIDOR_ROUGH, or PAR3_HALF.
static func corridor_half(spec: Dictionary) -> float:
	if (spec["fairway"] as Array).is_empty():
		return PAR3_HALF
	return float(spec["width"]) / 2.0 + CORRIDOR_ROUGH


## The pews' bunkers of a spec: thin ellipses across the tee-to-cup line, `spacing` apart from
## `from` to `to` tiles out, `offset` tiles to the left of the line.
static func pews(spec: Dictionary) -> Array:
	var out: Array = []
	if not spec.has("pews"):
		return out
	var p: Array = spec["pews"]
	var tee := Vector2(spec["tee"] as Vector2i)
	var dir := (Vector2(spec["cup"] as Vector2i) - tee).normalized()
	var left := Vector2(dir.y, -dir.x)
	var ang := rad_to_deg(left.angle())
	var t: float = p[0]
	while t <= float(p[1]) + 0.001:
		out.append([tee + dir * t + left * float(p[3]), float(p[4]), 0.8, ang])
		t += float(p[2])
	return out


## A spec's creek tiles.
static func creek_tiles(spec: Dictionary) -> Array[Vector2i]:
	if not spec.has("creek"):
		return [] as Array[Vector2i]
	var c: Array = spec["creek"]
	return PlaytestNine.strip(c[0], c[1])


## The designed ground at tile (x, y) before easing, in whole steps.
static func ridge_height(x: int, y: int) -> int:
	var h := BASE_HEIGHT
	var p := Vector2(x, y)
	for r: Array in RIDGE:
		var s: float = r[1]
		h += float(r[2]) * exp(-p.distance_squared_to(r[0]) / (2.0 * s * s))
	return clampi(roundi(h), 0, CourseData.MAX_HEIGHT)


# --- heights ---

static func _shape(b: CourseBuilder, course: CourseData) -> void:
	var w: int = course.width
	var h: int = course.height
	var target := PackedInt32Array()
	target.resize(w * h)
	for y: int in h:
		for x: int in w:
			target[y * w + x] = ridge_height(x, y)
	var locked := {}
	for spec: Dictionary in HOLES:
		var g: Array = spec["green"]
		var cells := PlaytestNine.green_tiles(spec)
		var base: int = _mean_target(target, w, h, cells) + int(g[4])
		var centre: Vector2 = g[0]
		var dir: Vector2 = g[5]
		var steps: int = g[6]
		var run: float = float(g[7])
		var off: float = g[8]
		var u := Vector2.from_angle(deg_to_rad(g[3]))
		var v := Vector2(-u.y, u.x)
		for t: Vector2i in cells:
			if not course.in_bounds(t.x, t.y):
				continue
			var d := Vector2(t) - centre
			var rise := 0
			if dir == Vector2.ZERO:
				# The crown: `steps` rings, each an equal share of the ellipse's radius.
				var pq := Vector2(d.dot(u) / float(g[1]), d.dot(v) / float(g[2]))
				rise = clampi(steps - floori(pq.length() * (steps + 1)), 0, steps)
			else:
				var proj := d.dot(dir.normalized())
				if proj >= off:
					rise = clampi(floori((proj - off) / run) + 1, 0, steps)
			target[t.y * w + t.x] = clampi(base + rise, 0, CourseData.MAX_HEIGHT)
			locked[t] = true
		var tees := PlaytestNine.tee_tiles(spec)
		var tee_h: int = clampi(_mean_target(target, w, h, tees) + int(spec["tee_lift"]), 0,
				CourseData.MAX_HEIGHT)
		for t: Vector2i in tees:
			if course.in_bounds(t.x, t.y):
				target[t.y * w + t.x] = tee_h
				locked[t] = true
	for spec: Dictionary in HOLES:
		var creek := creek_tiles(spec)
		if creek.is_empty():
			continue
		# Each tile of the creek one step under the lowest ground within 2 tiles of it, so the
		# water steps down the slope it runs along.
		var levels := {}
		for t: Vector2i in creek:
			if course.in_bounds(t.x, t.y):
				levels[t] = maxi(_min_target(target, w, h, t, 2) - 1, 0)
		for t: Vector2i in levels:
			target[t.y * w + t.x] = levels[t]
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
## most and tiles two apart along an axis by one step at most (PlaytestNine's rule).
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


static func _mean_target(target: PackedInt32Array, w: int, h: int, cells: Array[Vector2i]) -> int:
	var sum := 0
	var n := 0
	for t: Vector2i in cells:
		if t.x >= 0 and t.y >= 0 and t.x < w and t.y < h:
			sum += target[t.y * w + t.x]
			n += 1
	return roundi(float(sum) / maxi(n, 1))


static func _min_target(target: PackedInt32Array, w: int, h: int, t: Vector2i, margin: int) -> int:
	var low := CourseData.MAX_HEIGHT
	for dy: int in range(-margin, margin + 1):
		for dx: int in range(-margin, margin + 1):
			var x := t.x + dx
			var y := t.y + dy
			if x >= 0 and y >= 0 and x < w and y < h:
				low = mini(low, target[y * w + x])
	return low


# --- surfaces ---

static func _paint_hole(b: CourseBuilder, course: CourseData, spec: Dictionary) -> void:
	_paint(b, course, PlaytestNine.fairway_tiles(spec), Surface.Type.FAIRWAY)
	for e: Array in spec["bunkers"]:
		_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.BUNKER)
	for e: Array in pews(spec):
		_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.BUNKER)
	_paint(b, course, creek_tiles(spec), Surface.Type.WATER)
	_paint(b, course, PlaytestNine.tee_tiles(spec), Surface.Type.TEE)
	_paint(b, course, PlaytestNine.green_tiles(spec), Surface.Type.GREEN)


static func _paint(b: CourseBuilder, course: CourseData, cells: Array[Vector2i], surface: Surface.Type) -> void:
	b.begin_stroke()
	for t: Vector2i in cells:
		if course.in_bounds(t.x, t.y):
			b.paint(t, surface, 1)
	b.end_stroke()
