class_name Cliffside
extends RefCounted
## E13-S4 fixture: "Cliffside", nine holes along the cliffs of an island, an example course
## shipped in `courses/cliffside.json`. Each hole is modelled on a famous clifftop or ocean hole
## at its real par and yardage (the holes it is modelled on are credited in docs/courses.md,
## which does not ship; no real course or hole name is in the game or the file). Rebuild the
## file with `godot --headless --path . -s res://scripts/save_cliffside.gd` (save only).
##
## The land: a 128 x 128 map, every parcel owned, an unlimited budget (CourseData.create, as New
## sandbox), shaped and painted through CourseBuilder only. The sea is water at height 0 round
## the map's edges (SEA_BANDS) and in its coves (SEA): a western cove across hole 3 (the chasm),
## a narrow inlet between holes 5 and 6, and the bay holes 6, 7 and 1 wrap round. The headland
## under hole 4's green (LAND) stands out into the southern sea. The ground is a plateau
## (`plateau`: 6 steps in the north, 5 across the middle, 4 in the south, so hole 8 climbs and
## hole 9 falls) that drops to the sea one step a tile (`cliff`): every tile is at most its
## distance from the sea in steps, so the bluffs are smooth slopes (D50) of 40% down to the
## water, and a ball that rolls off a fairway's seaward edge runs down into the sea. Inland of
## the bluffs the ground keeps the land's slope rule (edge neighbours one step apart, at most one
## riser every 2 tiles along an axis), so balls settle (D16). The map edge, the sea beyond it,
## is out of bounds; the sea is water (a penalty drop).
##
## Water is painted with `CourseBuilder.level_water` off (D66, Fixtures): the sea touches the
## map's edge, which D66 counts as a drain, so it is laid as paint at height 0, a hollow under
## every shore tile.
##
## Holes are specs in HOLES, as PlaytestNine's (tests/fixtures/playtest_nine.gd, whose shape
## helpers this reuses): tee, cup, tee_lift, fairway polyline and width, green [centre, half
## length, half width, angle, lift, contour direction, steps, run, offset], bunkers and trees as
## ellipses. `yd` is the yardage the hole is laid at (the validator's line of play, within 10 yd),
## `name` its name on the scorecard of docs/courses.md.
##
## Routing: an island played round its bays. The clubhouse stands on the south-east headland by
## the 1st tee and the 9th green. 1 runs north up the bay's eastern bluff; 2 west along the
## northern cliffs; 3 south down the western cliffs, its approach over the chasm; 4 a short
## drop onto the headland; 5 back north along the inlet; 6 south along the inlet's far bluff to
## a clifftop green; 7 across the bay's mouth; 8 north up the hill to a green on the northern
## cliff; 9 home down the eastern shore.

const PATH: String = "res://courses/cliffside.json"
const COURSE_NAME: String = "Cliffside"
const COURSE_AUTHOR: String = "Prestwick"
const SIZE: int = 128
## How far from hole 1's tee the clubhouse may stand, tiles along x and y.
const CLUBHOUSE_REACH: int = 8
## Inland of this many tiles from the sea the ground keeps the land's slope rule.
const BLUFF_TILES: int = 7

## The sea round the map's edges: water on every tile within these rectangles.
const SEA_BANDS: Array[Rect2i] = [
	Rect2i(0, 0, SIZE, 3),  # north
	Rect2i(0, 120, SIZE, 8),  # south
	Rect2i(0, 0, 3, SIZE),  # west
	Rect2i(120, 0, 8, SIZE),  # east
]
## Coves and bays (ellipses [centre, half length, half width, angle]), water.
const SEA: Array = [
	# The chasm: a cove from the western sea across hole 3, short of its green.
	[Vector2(4, 92), 14.0, 2.2, 0.0],
	# The inlet between holes 5 and 6.
	[Vector2(36, 120), 3.0, 50.0, 0.0],
	# The bay: holes 6, 7 and 1 play round it; 7 carries its mouth.
	[Vector2(68, 124), 12.0, 56.0, 0.0],
]
## Land kept out of the sea (ellipses): the headland under hole 4's green.
const LAND: Array = [
	[Vector2(21, 122), 6.0, 5.0, 0.0],
]
## Cart paths: [the green the walk leaves, the tee it reaches, the polyline].
const PATHS: Array = [
	# The 1st green up to the raised 2nd tee.
	[1, 2, [Vector2(83, 27), Vector2(81, 24)]],
	# Round the 3rd green's bunker, up the bluff to the 4th tee.
	[3, 4, [Vector2(13, 105), Vector2(16, 103)]],
	# Off the headland under the 4th green, up the bluff to the 5th tee.
	[4, 5, [Vector2(27, 121), Vector2(27, 116), Vector2(28, 114)]],
	# The 5th green round its bunker to the 6th tee.
	[5, 6, [Vector2(32, 22), Vector2(35, 23), Vector2(37, 27)]],
	# The 8th green along the clifftop to the raised 9th tee.
	[8, 9, [Vector2(105, 10), Vector2(110, 9)]],
]

const HOLES: Array = [
	{
		"n": 1, "name": "Bay Bluff", "par": 4, "yd": 395,
		"tee": Vector2i(84, 111), "cup": Vector2i(84, 32), "tee_lift": 0,
		"fairway": [Vector2(84, 102), Vector2(84, 38)],
		"width": 5.0,
		"green": [Vector2(84, 32), 4.0, 3.0, 90.0, 0, Vector2(0.3, -1), 1, 2, 0.0],
		"bunkers": [[Vector2(84, 62), 1.5, 1.2, 0.0], [Vector2(80, 35), 1.7, 1.8, 0.0]],
		"trees": [[Vector2(92, 84), 2.5, 9.0, 0.0], [Vector2(92, 50), 2.0, 7.0, 0.0]],
	},
	{
		"n": 2, "name": "North Ledge", "par": 4, "yd": 363,
		"tee": Vector2i(80, 22), "cup": Vector2i(8, 13), "tee_lift": 2,
		"fairway": [Vector2(73, 21), Vector2(13, 14)],
		"width": 5.0,
		"green": [Vector2(8, 13), 3.5, 3.0, 0.0, 0, Vector2(-1, 0.3), 1, 2, 0.0],
		"bunkers": [[Vector2(35, 17), 1.8, 1.7, 0.0], [Vector2(12, 17), 1.8, 1.7, 0.0]],
		"trees": [[Vector2(56, 28), 9.0, 2.5, 0.0], [Vector2(64, 46), 6.0, 4.0, 30.0]],
	},
	{
		"n": 3, "name": "The Chasm", "par": 4, "yd": 430,
		"tee": Vector2i(10, 24), "cup": Vector2i(9, 110), "tee_lift": 2,
		"fairway": [Vector2(9, 32), Vector2(9, 86)],
		"width": 5.0,
		"green": [Vector2(9, 110), 4.5, 3.5, 90.0, 0, Vector2(0.3, -1), 1, 2, 0.0],
		"bunkers": [[Vector2(14, 70), 1.7, 2.8, 0.0], [Vector2(14, 108), 1.7, 1.8, 0.0]],
		"trees": [[Vector2(18, 48), 2.5, 9.0, 0.0]],
	},
	{
		"n": 4, "name": "Little Point", "par": 3, "yd": 107,
		"tee": Vector2i(18, 101), "cup": Vector2i(22, 122), "tee_lift": 2,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(22, 122), 3.5, 3.0, 0.0, 0, Vector2(-1, -0.3), 1, 2, 0.0],
		"bunkers": [[Vector2(25, 118), 1.7, 1.7, 0.0], [Vector2(21, 117), 1.5, 1.0, 0.0]],
		"trees": [],
	},
	{
		"n": 5, "name": "Long Bluff", "par": 4, "yd": 445,
		"tee": Vector2i(28, 112), "cup": Vector2i(28, 23), "tee_lift": 0,
		"fairway": [Vector2(28, 104), Vector2(28, 29)],
		"width": 5.0,
		"green": [Vector2(28, 23), 4.0, 3.0, 90.0, 0, Vector2(-0.3, -1), 1, 2, 0.0],
		"bunkers": [[Vector2(28, 64), 1.5, 1.2, 0.0], [Vector2(32, 26), 1.7, 1.8, 0.0]],
		"trees": [[Vector2(19, 80), 2.5, 7.0, 0.0]],
	},
	{
		"n": 6, "name": "Cliff Edge", "par": 4, "yd": 332,
		"tee": Vector2i(38, 30), "cup": Vector2i(46, 96), "tee_lift": 0,
		"fairway": [Vector2(39, 38), Vector2(45, 90)],
		"width": 5.0,
		"green": [Vector2(46, 96), 4.0, 3.0, 85.0, 0, Vector2(0.3, -1), 1, 2, 0.0],
		"bunkers": [[Vector2(43, 70), 1.5, 1.2, 0.0], [Vector2(50, 94), 1.7, 1.8, 0.0]],
		"trees": [[Vector2(53, 52), 2.5, 9.0, 0.0]],
	},
	{
		"n": 7, "name": "The Crossing", "par": 3, "yd": 231,
		"tee": Vector2i(50, 108), "cup": Vector2i(96, 113), "tee_lift": 0,
		"fairway": [],
		"width": 5.0,
		"green": [Vector2(96, 113), 3.5, 3.0, 0.0, 0, Vector2(1, -0.3), 1, 2, 0.0],
		"bunkers": [[Vector2(92, 117), 1.8, 1.7, 0.0]],
		"trees": [],
		# E14-S3 (D69): a footbridge straight over the cove beside the line, so guests cross with their balls
		# instead of walking round the cove's head (300 yd and more).
		"bridge": [Vector2(50, 110), Vector2(90, 110)],
	},
	{
		"n": 8, "name": "Headland", "par": 5, "yd": 525,
		"tee": Vector2i(104, 113), "cup": Vector2i(100, 8), "tee_lift": 0,
		"fairway": [Vector2(104, 105), Vector2(100, 14)],
		"width": 5.0,
		"green": [Vector2(100, 9), 4.0, 3.0, 0.0, 0, Vector2(-1, 0.3), 1, 2, 0.0],
		"bunkers": [[Vector2(102, 53), 1.5, 1.2, 0.0], [Vector2(104, 28), 1.7, 2.4, 0.0]],
		"trees": [[Vector2(107, 80), 1.0, 12.0, 0.0], [Vector2(107, 40), 1.0, 10.0, 0.0]],
	},
	{
		"n": 9, "name": "Homeward", "par": 5, "yd": 525,
		"tee": Vector2i(112, 11), "cup": Vector2i(112, 116), "tee_lift": 2,
		"fairway": [Vector2(112, 19), Vector2(112, 110)],
		"width": 5.0,
		"green": [Vector2(112, 115), 4.0, 3.0, 90.0, 0, Vector2(-1, -0.3), 1, 2, 0.0],
		"bunkers": [[Vector2(112, 57), 1.5, 1.2, 0.0], [Vector2(108, 108), 1.7, 1.8, 0.0]],
		"trees": [],
	},
]


## The finished course as `courses/cliffside.json` holds it, named. The name is file data, so
## it goes through CourseSave (to_json, from_dict); nothing else writes CourseData.
static func course() -> CourseData:
	var c := CourseData.create(SIZE, SIZE, Surface.Type.ROUGH, 4)
	build(CourseBuilder.new(c))
	var data: Dictionary = JSON.parse_string(CourseSave.to_json(c))
	data["name"] = COURSE_NAME
	data["author"] = COURSE_AUTHOR
	return CourseSave.from_dict(data)


## Builds the course on `b`'s course. Returns the numbers that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var course: CourseData = b.course
	var level_water: bool = b.level_water
	b.level_water = false
	var sea := sea_mask()
	_shape(b, course, sea)
	var water: Array[Vector2i] = []
	for y: int in SIZE:
		for x: int in SIZE:
			if sea[y * SIZE + x] == 1:
				water.append(Vector2i(x, y))
	_paint(b, course, water, Surface.Type.WATER)
	for spec: Dictionary in HOLES:
		for e: Array in spec["trees"]:
			_paint(b, course, _dry(PlaytestNine.ellipse(e), sea), Surface.Type.TREES)
	for spec: Dictionary in HOLES:
		_paint(b, course, _dry(PlaytestNine.fairway_tiles(spec), sea), Surface.Type.FAIRWAY)
		for e: Array in spec["bunkers"]:
			_paint(b, course, _dry(PlaytestNine.ellipse(e), sea), Surface.Type.BUNKER)
		for e: Array in spec.get("line_trees", []):
			_paint(b, course, _dry(PlaytestNine.ellipse(e), sea), Surface.Type.TREES)
		_paint(b, course, PlaytestNine.tee_tiles(spec), Surface.Type.TEE)
		_paint(b, course, PlaytestNine.green_tiles(spec), Surface.Type.GREEN)
	for p: Array in PATHS:
		_paint(b, course, PlaytestNine.path_tiles(course, p[2]), Surface.Type.CART_PATH)
	for spec: Dictionary in HOLES:
		if spec.has("bridge"):
			FixtureBridges.lay(b, spec["bridge"])
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


## 1 on every sea tile (SEA_BANDS and SEA, less LAND), row by row.
static func sea_mask() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SIZE * SIZE)
	for r: Rect2i in SEA_BANDS:
		for y: int in range(r.position.y, mini(r.end.y, SIZE)):
			for x: int in range(r.position.x, mini(r.end.x, SIZE)):
				out[y * SIZE + x] = 1
	for e: Array in SEA:
		for t: Vector2i in PlaytestNine.ellipse(e):
			if t.x >= 0 and t.y >= 0 and t.x < SIZE and t.y < SIZE:
				out[t.y * SIZE + t.x] = 1
	for e: Array in LAND:
		for t: Vector2i in PlaytestNine.ellipse(e):
			if t.x >= 0 and t.y >= 0 and t.x < SIZE and t.y < SIZE:
				out[t.y * SIZE + t.x] = 0
	return out


## Each tile's distance from the sea in tiles (0 on the sea), a chamfer distance (1 along an
## axis, 1.414 diagonally), which changes by at most 1 between edge neighbours.
static func sea_distance(sea: PackedByteArray) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(SIZE * SIZE)
	var far := float(SIZE * 2)
	for i: int in d.size():
		d[i] = 0.0 if sea[i] == 1 else far
	var diag := sqrt(2.0)
	for y: int in SIZE:
		for x: int in SIZE:
			var i := y * SIZE + x
			if x > 0:
				d[i] = minf(d[i], d[i - 1] + 1.0)
			if y > 0:
				d[i] = minf(d[i], d[i - SIZE] + 1.0)
				if x > 0:
					d[i] = minf(d[i], d[i - SIZE - 1] + diag)
				if x < SIZE - 1:
					d[i] = minf(d[i], d[i - SIZE + 1] + diag)
	for y: int in range(SIZE - 1, -1, -1):
		for x: int in range(SIZE - 1, -1, -1):
			var i := y * SIZE + x
			if x < SIZE - 1:
				d[i] = minf(d[i], d[i + 1] + 1.0)
			if y < SIZE - 1:
				d[i] = minf(d[i], d[i + SIZE] + 1.0)
				if x < SIZE - 1:
					d[i] = minf(d[i], d[i + SIZE + 1] + diag)
				if x > 0:
					d[i] = minf(d[i], d[i + SIZE - 1] + diag)
	return d


## The plateau's height at a tile before the bluffs cut it: rolling ground of 3 to 7 steps,
## higher in the north (about 6) than the south (about 4), so hole 8 climbs and hole 9 falls.
static func plateau(x: int, y: int) -> int:
	var roll := 0.9 * sin(x * 0.11 + 1.0) + 0.8 * cos(y * 0.09 + 0.5)
	return clampi(roundi(5.0 + roll - (y - 64) / 64.0), 3, CourseData.MAX_HEIGHT)


## `cells` less the sea's tiles.
static func _dry(cells: Array[Vector2i], sea: PackedByteArray) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t: Vector2i in cells:
		if t.x >= 0 and t.y >= 0 and t.x < SIZE and t.y < SIZE and sea[t.y * SIZE + t.x] == 0:
			out.append(t)
	return out


# --- heights ---

static func _shape(b: CourseBuilder, course: CourseData, sea: PackedByteArray) -> void:
	var w := SIZE
	var dist := sea_distance(sea)
	var target := PackedInt32Array()
	target.resize(w * w)
	# The bluffs' cut: no land tile stands higher than its distance from the sea in steps.
	var cut := PackedInt32Array()
	cut.resize(w * w)
	var locked := {}
	var bluff := {}
	for y: int in w:
		for x: int in w:
			var i := y * w + x
			if sea[i] == 1:
				target[i] = 0
				locked[Vector2i(x, y)] = true
				continue
			cut[i] = clampi(floori(dist[i]), 1, CourseData.MAX_HEIGHT)
			target[i] = mini(plateau(x, y), cut[i])
			if dist[i] <= BLUFF_TILES:
				bluff[Vector2i(x, y)] = true
	_ease(target, w, locked, bluff, cut)
	# Greens and tees on the ground they stand on, under the cut (a clifftop green falls toward
	# the sea; a tee box stays level at its lowest tile's cut), then the ground round them eased
	# again.
	var plain := target.duplicate()
	for spec: Dictionary in HOLES:
		var g: Array = spec["green"]
		var cells := PlaytestNine.green_tiles(spec)
		var base: int = _mean(plain, cells) + int(g[4])
		var centre: Vector2 = g[0]
		var dir: Vector2 = (g[5] as Vector2).normalized()
		var steps: int = g[6]
		var run: float = float(g[7])
		var off: float = g[8]
		for t: Vector2i in cells:
			var proj := (Vector2(t) - centre).dot(dir)
			var rise := 0
			if proj >= off:
				rise = clampi(floori((proj - off) / run) + 1, 0, steps)
			target[t.y * w + t.x] = clampi(base + rise, 1, cut[t.y * w + t.x])
			locked[t] = true
		var tees := PlaytestNine.tee_tiles(spec)
		var tee_h: int = clampi(_mean(plain, tees) + int(spec["tee_lift"]), 1, CourseData.MAX_HEIGHT)
		for t: Vector2i in tees:
			tee_h = mini(tee_h, cut[t.y * w + t.x])
		for t: Vector2i in tees:
			target[t.y * w + t.x] = tee_h
			locked[t] = true
	_ease(target, w, locked, bluff, cut)
	for pass_i: int in CourseData.MAX_HEIGHT + 1:
		var moved := false
		b.begin_stroke()
		for y: int in w:
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


## Eases the unlocked ground so edge neighbours differ by one step at most and, off the bluffs,
## tiles two apart along an axis by one step at most (one riser every 2 tiles), never above
## `cut`, so a bluff never rises more than a step a tile from the sea.
static func _ease(target: PackedInt32Array, w: int, locked: Dictionary, bluff: Dictionary,
		cut: PackedInt32Array) -> void:
	var near: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var far: Array[Vector2i] = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
	for it: int in 64:
		var changed := false
		for y: int in w:
			for x: int in w:
				var t := Vector2i(x, y)
				if locked.has(t):
					continue
				var lo := 1
				var hi: int = cut[y * w + x]
				var ds: Array[Vector2i] = near if bluff.has(t) else near + far
				for d: Vector2i in ds:
					var nx := x + d.x
					var ny := y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= w:
						continue
					var nh: int = target[ny * w + nx]
					if nh == 0:
						continue  # the sea: the cut holds a bluff a step a tile above it
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


static func _mean(target: PackedInt32Array, cells: Array[Vector2i]) -> int:
	var sum := 0
	var n := 0
	for t: Vector2i in cells:
		if t.x >= 0 and t.y >= 0 and t.x < SIZE and t.y < SIZE:
			sum += target[t.y * SIZE + t.x]
			n += 1
	return roundi(float(sum) / maxi(n, 1))


static func _paint(b: CourseBuilder, course: CourseData, cells: Array[Vector2i], surface: Surface.Type) -> void:
	b.begin_stroke()
	for t: Vector2i in cells:
		if course.in_bounds(t.x, t.y):
			b.paint(t, surface, 1)
	b.end_stroke()
