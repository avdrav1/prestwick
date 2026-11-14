class_name DoglegHollow
extends RefCounted
## E16-S1 fixture: "Dogleg Hollow", nine holes that every one turn, each modelled on a famous
## real dogleg at its real par and yardage (docs/courses.md names the hole each is modelled on;
## the names here are our own). Built through CourseBuilder only, as the other famous courses
## are: shape the ground, paint, place, open. `courses/dogleg_hollow.json` is this course saved
## with CourseSave; rebuild it with
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s res://scripts/save_dogleg_hollow.gd
##
## The land: a blank 128 x 128 plot (BuilderTuning's, every parcel owned, an unlimited budget:
## New sandbox rules) on flat ground at GROUND, so every tee shot is seen (D43) with the tees a
## step up. Every pond is dug one step below the ground round it and painted with the builder's
## `level_water` on, so each floods its own hollow, flat, a step under its rim (D66).
##
## Each hole is a spec in HOLES (tile coordinates, 5 yd a tile), as PineRidge's:
## - tee, tee_lift, fairway (a polyline: tee side, the bend, the green side), width.
## - green: [centre, half length, half width, angle, lift, contour direction, steps, run,
##   offset], PlaytestNine's contours.
## - bunkers, trees, water: ellipses [centre, half length, half width, angle]. The corner of
##   every hole holds trees, water or sand, so the bold line over it is a gamble.
## - bridge (D69): a polyline of tile points whose water tiles get a footbridge
##   (FixtureBridges.lay), laid after the cart paths.
## - yd: the yardage the validator measures (rule 4 round the dogleg, D47), the spec the test
##   holds; turn: the bend's direction, "left" or "right".
##
## Every hole is a dogleg (D47): its fairway leaves rule 4's disc on the straight tee-to-cup
## line empty and runs on round the corner to the green, so the validator measures it round the
## bend (CourseValidator.turn_point), D51 puts its landing zone and footprint on the line of play
## and guests aim at the corner first (D54). The 8th bends twice; the validator measures its
## first bend (the tee shot's), and the second, short of the green, swings back. A tee stands
## where rule 4's ring (240 yd out) meets its fairway's first leg, just short of the bend.
##
## Parkland, as Pine Ridge: every hole plays down its own corridor of rough (CORRIDOR_ROUGH past
## the fairway's edge) walled by a belt of trees (BELT tiles); the belts are painted first and
## every corridor and walk lane cut through them after, so the doglegs read on the map as green
## lanes bending through the woods.
##
## Routing (laid out with a scratch search for nine L shapes that fit the map without touching,
## then placed by hand): the clubhouse stands on the east edge by the 1st tee. 1 runs north up
## the east side and turns left along under the 8th; 2 cuts back south-east down the middle and
## turns right; 3 and 4 are a nested pair in the south-west (3 west then south, 4 north up the
## west edge then east); 5 runs south through the middle and turns right; 6 runs east along the
## south and turns left up to a green by the 2nd's; 7 runs back north-west inside the 2nd's
## corner and turns left; 8, the par 5, plays the whole north from west to east; 9 runs south
## inside the 1st's corner, past its lake, and turns right toward home.
##
## Walks (D65, D68): a lane of rough is cut on every walk (the clubhouse to the 1st tee, each
## green to the next tee), and the walks too long for the least patient guest get a cart path
## (PATHS), checked with GuestWalk.why. Three of them cross another hole's fairway (path_tiles).

const PATH: String = "res://courses/dogleg_hollow.json"
const COURSE_NAME: String = "Dogleg Hollow"
const COURSE_AUTHOR: String = "Prestwick"
## E15-S1 (D70): the famous course's id and version, written into the file. A change to this
## fixture that changes the file needs the next COURSE_VERSION and the new file's hash appended
## to FamousCourses (tests/test_example_courses.gd checks both).
const COURSE_ID: String = "dogleg_hollow"
const COURSE_VERSION: int = 1
## The nine's par: no par 3 turns, so eight par 4s and the par 5.
const PAR: int = 37
## The ground's height in steps, everywhere but the ponds, tees and greens.
const GROUND: int = 2
## Rough kept each side of a fairway's edge (tiles).
const CORRIDOR_ROUGH: float = 3.5
## Rough round a green, from its centre (tiles).
const GREEN_CLEAR: float = 7.0
## The belt of trees beyond a corridor (tiles).
const BELT: float = 4.0
## A walk lane's width (tiles).
const LANE: float = 3.0
## How far from the 1st tee the clubhouse may stand, tiles along x and y.
const CLUBHOUSE_REACH: int = 8

## Cart paths, polylines of tile centres painted 1 tile wide over rough, trees and fairway
## (path_tiles):
## [the green the walk leaves (0 the clubhouse), the tee it reaches, the polyline].
const PATHS: Array = [
	# Off the 2nd green, diagonally across the 5th's fairway short of its corner, to the 3rd tee.
	[2, 3, [Vector2(71, 86), Vector2(59, 74), Vector2(52, 74)]],
	# Off the 3rd green west to the 4th tee.
	[3, 4, [Vector2(20, 118), Vector2(13, 116), Vector2(10, 114)]],
	# Off the 6th green, diagonally across the 2nd's fairway, up to the 7th tee.
	[6, 7, [Vector2(89, 87), Vector2(81, 79), Vector2(81, 71)]],
	# Off the 7th green north-west to the 8th tee.
	[7, 8, [Vector2(32, 38), Vector2(23, 33), Vector2(20, 32)]],
	# Off the 8th green, diagonally across the 1st's fairway, down to the 9th tee.
	[8, 9, [Vector2(111, 15), Vector2(96, 30), Vector2(99, 33)]],
]

const HOLES: Array = [
	{
		# The Cape: a lake fills the inside of the bend left; the more of it the tee shot
		# bites off, the shorter the approach.
		"n": 1, "name": "Bite Off", "par": 4, "yd": 433, "turn": "left",
		"tee": Vector2i(120, 76), "cup": Vector2i(76, 23), "tee_lift": 1,
		"fairway": [Vector2(119.5, 71), Vector2(116, 27), Vector2(82, 24)], "width": 5,
		"green": [Vector2(76, 23), 4.0, 3.2, -173, 0, Vector2(-0.99, -0.13), 1, 1, 0.5],
		"bunkers": [[Vector2(80.5, 19.5), 1.2, 2, -143]],
		"trees": [],
		"water": [[Vector2(109, 43), 12, 5, -96]],
	},
	{
		# Sharp right round a pond, willows on the corner; the bold line carries both.
		"n": 2, "name": "Willow Pond", "par": 4, "yd": 405, "turn": "right",
		"tee": Vector2i(67, 28), "cup": Vector2i(75, 90), "tee_lift": 1,
		"fairway": [Vector2(70, 32), Vector2(99.5, 66.5), Vector2(79, 85.5)], "width": 5,
		"green": [Vector2(75, 90), 4.0, 3.2, 134, 0, Vector2(-0.69, 0.72), 1, 1, 0.5],
		"bunkers": [[Vector2(75, 84.5), 1.2, 2, 164]],
		"trees": [],
		"water": [[Vector2(90, 66), 4.5, 3.5, -87]],
	},
	{
		# Short, left round one great bunker; a big drive carries it toward the green.
		"n": 3, "name": "Sand Sea", "par": 4, "yd": 325, "turn": "left",
		"tee": Vector2i(49, 72), "cup": Vector2i(24, 120), "tee_lift": 1,
		"fairway": [Vector2(45, 75), Vector2(14.5, 97.5), Vector2(22, 114.5)], "width": 5,
		"green": [Vector2(24, 120), 4.0, 3.2, 70, 0, Vector2(0.34, 0.94), 1, 1, 0.5],
		"bunkers": [[Vector2(23.5, 100), 4.5, 2.5, 105], [Vector2(19, 117.5), 1.2, 2, 100]],
		"trees": [],
		"water": [],
	},
	{
		# Right round a sand-filled shoulder; the green sits on a slope beyond.
		"n": 4, "name": "Shoulder", "par": 4, "yd": 428, "turn": "right",
		"tee": Vector2i(7, 113), "cup": Vector2i(45, 55), "tee_lift": 1,
		"fairway": [Vector2(7, 108), Vector2(5.5, 64.5), Vector2(39, 56.5)], "width": 5,
		"green": [Vector2(45, 55), 4.0, 3.2, -15, 0, Vector2(0.97, -0.26), 1, 1, 0.5],
		"bunkers": [[Vector2(13, 70), 3, 1.5, 127], [Vector2(42, 60), 1.2, 2, 15]],
		"trees": [],
		"water": [],
	},
	{
		# Right round bunkers on the corner to a green set out on its own.
		"n": 5, "name": "Chalk Bend", "par": 4, "yd": 374, "turn": "right",
		"tee": Vector2i(57, 51), "cup": Vector2i(35, 109), "tee_lift": 1,
		"fairway": [Vector2(57.5, 56), Vector2(61.5, 99.5), Vector2(40.5, 107)], "width": 5,
		"green": [Vector2(35, 109), 4.0, 3.2, 158, 0, Vector2(-0.93, 0.37), 1, 1, 0.5],
		"bunkers": [[Vector2(53.5, 94.5), 3, 1.5, -57], [Vector2(34, 104), 2, 1, 158], [Vector2(38, 113.5), 2, 1, 158]],
		"trees": [],
		"water": [],
	},
	{
		# Left round tall trees to a small green held in a horseshoe of sand.
		"n": 6, "name": "Plank Bunker", "par": 4, "yd": 373, "turn": "left",
		"tee": Vector2i(35, 120), "cup": Vector2i(91, 92), "tee_lift": 1,
		"fairway": [Vector2(40, 119.5), Vector2(84, 117.5), Vector2(89, 97.5)], "width": 5,
		"green": [Vector2(91, 92), 4.0, 3.2, -72, 0, Vector2(0.3, -0.95), 1, 1, 0.5],
		"bunkers": [[Vector2(89.5, 97), 1, 3, -72], [Vector2(94.5, 96), 1.6, 1, -72], [Vector2(86, 93), 1.6, 1, -72]],
		"trees": [[Vector2(78, 110), 5.5, 3, -38]],
		"water": [],
	},
	{
		# The short one: left round a stand of trees, water short of the green; the brave
		# go straight at the green over both.
		"n": 7, "name": "Brave Line", "par": 4, "yd": 325, "turn": "left",
		"tee": Vector2i(82, 68), "cup": Vector2i(36, 40), "tee_lift": 1,
		"fairway": [Vector2(79, 64), Vector2(58.5, 32.5), Vector2(42, 38.5)], "width": 5,
		"green": [Vector2(36, 40), 4.0, 3.2, 165, 0, Vector2(-0.96, 0.26), 1, 1, 0.5],
		"bunkers": [],
		"trees": [[Vector2(55.5, 41.5), 5.5, 3, 199]],
		"water": [[Vector2(44.5, 42.5), 2.5, 3, 165]],
	},
	{
		# The par 5 bends twice: right round a waste bunker, then back left past a pond
		# to the green.
		"n": 8, "name": "Twin Elbows", "par": 5, "yd": 520, "turn": "right",
		"tee": Vector2i(17, 31), "cup": Vector2i(114, 11), "tee_lift": 1,
		"fairway": [Vector2(21.5, 28.5), Vector2(58.5, 6), Vector2(104, 16.5), Vector2(108.5, 14)], "width": 6,
		"green": [Vector2(114, 11), 4.0, 3.2, -29, 0, Vector2(0.88, -0.48), 1, 1, 0.5],
		"bunkers": [[Vector2(60, 15.5), 3, 1.5, 171], [Vector2(112.5, 16.5), 1.2, 2, 1]],
		"trees": [],
		"water": [[Vector2(103, 9), 4, 2.5, -9]],
	},
	{
		# Right over sandy dunes on the corner to a green between two bunkers.
		"n": 9, "name": "Dune Elbow", "par": 4, "yd": 363, "turn": "right",
		"tee": Vector2i(101, 36), "cup": Vector2i(99, 102), "tee_lift": 1,
		"fairway": [Vector2(102, 41), Vector2(114, 82.5), Vector2(102.5, 97)], "width": 5,
		"green": [Vector2(99, 102), 4.0, 3.2, 124, 0, Vector2(-0.56, 0.83), 1, 1, 0.5],
		"bunkers": [[Vector2(104.5, 81), 3, 1.5, -80], [Vector2(95.5, 98.5), 2, 1, 124], [Vector2(103.5, 104), 2, 1, 124]],
		"trees": [],
		"water": [],
	},
]


## The blank plot the course is laid on: D10's 128 x 128 (BuilderTuning.D10_PLOT_SIZE, pinned
## by D71 so the course stays as built), BuilderTuning's surface and ground, every parcel owned,
## an unlimited budget (New sandbox), no clubhouse yet.
static func land() -> CourseData:
	var t := BuilderTuning.load_default()
	var size: Vector2i = BuilderTuning.D10_PLOT_SIZE
	return CourseData.create(size.x, size.y, t.plot_surface, t.plot_ground)


## The finished course as `courses/dogleg_hollow.json` holds it: land() built by build(), then
## named through CourseSave (to_json, from_dict), which makes the named course.
static func course() -> CourseData:
	var c := land()
	build(CourseBuilder.new(c))
	var data: Dictionary = JSON.parse_string(CourseSave.to_json(c))
	data["name"] = COURSE_NAME
	data["author"] = COURSE_AUTHOR
	data["course_id"] = COURSE_ID
	data["course_version"] = COURSE_VERSION
	return CourseSave.from_dict(data)


## The spec of hole `n`, or an empty Dictionary.
static func spec_of(n: int) -> Dictionary:
	for spec: Dictionary in HOLES:
		if spec["n"] == n:
			return spec
	return {}


## Builds the course on `b`'s course, water levelled as painted (D66). Returns the numbers that
## opened.
static func build(b: CourseBuilder) -> Array[int]:
	lay(b, HOLES, walks(), PATHS)
	var first: Vector2i = (HOLES[0] as Dictionary)["tee"]
	var spot: Array = ClubhouseRule.spot_beside(b.course, first, b.slot_lines(), CLUBHOUSE_REACH)
	b.move_clubhouse(spot[0], spot[1])
	return opened(b, HOLES)


## Lays the holes `specs` (HOLES' form) on `b`'s course as this nine is laid: the ground, the
## belts of trees and their corridors, a lane on each walk of `walk_lines` (tile polylines), the
## trees, fairways, sand, tees, greens and water (levelled, D66), the cart paths `paths`
## (PATHS' form), the bridges, then each hole's tee, cup and par. No clubhouse. E19-S1's
## eighteen (DoglegChampionship) lays its eighteen with it.
static func lay(b: CourseBuilder, specs: Array, walk_lines: Array, paths: Array) -> void:
	var course: CourseData = b.course
	var level_water: bool = b.level_water
	b.level_water = true
	var water := water_tiles(course, specs)
	_shape(b, course, water, specs)
	var belts: Array[Vector2i] = []
	var cuts: Array[Vector2i] = []
	for spec: Dictionary in specs:
		var line := corridor_line(spec)
		var half := corridor_half(spec)
		belts.append_array(PlaytestNine.strip(line, 2.0 * (half + BELT)))
		var cup := Vector2(spec["cup"] as Vector2i)
		belts.append_array(PlaytestNine.strip([cup, cup], 2.0 * (GREEN_CLEAR + BELT)))
		cuts.append_array(PlaytestNine.strip(line, 2.0 * half))
		cuts.append_array(PlaytestNine.strip([cup, cup], 2.0 * GREEN_CLEAR))
	_paint(b, course, belts, Surface.Type.TREES)
	_paint(b, course, cuts, Surface.Type.ROUGH)
	var lanes: Array[Vector2i] = []
	for w: Array in walk_lines:
		lanes.append_array(PlaytestNine.strip(w, LANE))
	_paint(b, course, lanes, Surface.Type.ROUGH)
	for spec: Dictionary in specs:
		for e: Array in spec["trees"]:
			_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.TREES)
	for spec: Dictionary in specs:
		_paint(b, course, PlaytestNine.fairway_tiles(spec), Surface.Type.FAIRWAY)
	for spec: Dictionary in specs:
		for e: Array in spec["bunkers"]:
			_paint(b, course, PlaytestNine.ellipse(e), Surface.Type.BUNKER)
		_paint(b, course, PlaytestNine.tee_tiles(spec), Surface.Type.TEE)
		_paint(b, course, PlaytestNine.green_tiles(spec), Surface.Type.GREEN)
	# Water last: each dab on a dug tile floods its hollow (D66); a tile already flooded by an
	# earlier dab is skipped.
	b.begin_stroke()
	for t: Vector2i in water:
		if course.get_surface(t.x, t.y) != Surface.Type.WATER:
			b.paint(t, Surface.Type.WATER, 1)
	b.end_stroke()
	for p: Array in paths:
		_paint(b, course, path_tiles(course, p[2]), Surface.Type.CART_PATH)
	for spec: Dictionary in specs:
		if spec.has("bridge"):
			FixtureBridges.lay(b, spec["bridge"])
	for spec: Dictionary in specs:
		var n: int = spec["n"]
		b.place_tee(n, spec["tee"], spec["par"])
		b.place_cup(n, spec["cup"])
		b.set_par(n, spec["par"])
	b.level_water = level_water


## The numbers of `specs` whose holes are open on `b`'s course.
static func opened(b: CourseBuilder, specs: Array) -> Array[int]:
	var out: Array[int] = []
	for spec: Dictionary in specs:
		if b.hole(spec["n"]).open:
			out.append(spec["n"])
	return out


## The walks a round takes, as tile polylines: the 1st tee toward the clubhouse (CLUBHOUSE_WALK),
## then each green to the next tee.
static func walks() -> Array:
	var out: Array = []
	var first: Vector2i = (HOLES[0] as Dictionary)["tee"]
	out.append([Vector2(first), Vector2(first) + CLUBHOUSE_WALK])
	for i: int in HOLES.size() - 1:
		var a: Dictionary = HOLES[i]
		var c: Dictionary = HOLES[i + 1]
		out.append([Vector2(a["cup"]), Vector2(c["tee"])])
	return out


## Where the lane from the 1st tee runs: west, toward the clubhouse's spot on the edge's side.
const CLUBHOUSE_WALK: Vector2 = Vector2(-CLUBHOUSE_REACH, 0)


## A cart path's tiles: PlaytestNine.strip one tile wide along `points`, over rough, trees and
## fairway (never a tee, green, bunker or water). A path crosses a fairway only on a 45 degree
## diagonal, a chain of tiles touching at their corners, so the fairway either side still
## joins through 8 neighbours and the validator's turn (D47) follows it past the path.
static func path_tiles(course: CourseData, points: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t: Vector2i in PlaytestNine.strip(points, 1.0):
		if not course.in_bounds(t.x, t.y):
			continue
		var s := course.get_surface(t.x, t.y)
		if s == Surface.Type.ROUGH or s == Surface.Type.TREES or s == Surface.Type.FAIRWAY:
			out.append(t)
	return out


## A hole's corridor centre line: tee, the fairway's centre line, cup.
static func corridor_line(spec: Dictionary) -> Array:
	var out: Array = [Vector2(spec["tee"] as Vector2i)]
	for p: Vector2 in PlaytestNine.centre_line(spec):
		out.append(p)
	out.append(Vector2(spec["cup"] as Vector2i))
	return out


## Half the corridor's width: the fairway's half width and CORRIDOR_ROUGH.
static func corridor_half(spec: Dictionary) -> float:
	return float(spec["width"]) / 2.0 + CORRIDOR_ROUGH


## The tiles dug and flooded: every hole's water (of `specs`), less every tee box and green, one
## tile in from the map's edge (so no pond drains off it, D66), sorted.
static func water_tiles(course: CourseData, specs: Array = HOLES) -> Array[Vector2i]:
	var dry := {}
	for s: Dictionary in specs:
		for t: Vector2i in PlaytestNine.green_tiles(s):
			dry[t] = true
		for t: Vector2i in PlaytestNine.tee_tiles(s):
			dry[t] = true
	var wet := {}
	for s: Dictionary in specs:
		var cells: Array[Vector2i] = []
		for e: Array in s.get("water", []):
			cells.append_array(PlaytestNine.ellipse(e))
		for t: Vector2i in cells:
			if t.x >= 1 and t.y >= 1 and t.x < course.width - 1 and t.y < course.height - 1 \
					and not dry.has(t):
				wet[t] = true
	var out: Array[Vector2i] = []
	for t: Vector2i in wet:
		out.append(t)
	out.sort_custom(func(a: Vector2i, c: Vector2i) -> bool: return a.y < c.y or (a.y == c.y and a.x < c.x))
	return out


## The angle a hole's line of play turns at its bend, in degrees: tee to turn against turn to
## cup, positive to the right (clockwise on the map), negative to the left. 0 for a hole the
## validator measures straight.
static func turn_angle(course: CourseData, h: HoleData, v: CourseValidator) -> float:
	var turn: Variant = v.turn_point(course, h)
	if turn == null:
		return 0.0
	var a: Vector2 = (turn as Vector2) - Vector2(h.tee)
	var b: Vector2 = Vector2(h.cup) - (turn as Vector2)
	return rad_to_deg(a.angle_to(b))


# --- heights ---

## Heights: flat GROUND, every green contoured, every tee box lifted, each pond dug one step
## below the lowest ground round it, flat; the ground round them eased as PlaytestNine eases it
## (neighbours one step apart at most, one riser every 2 tiles along an axis).
static func _shape(b: CourseBuilder, course: CourseData, water: Array[Vector2i],
		specs: Array = HOLES) -> void:
	var w: int = course.width
	var h: int = course.height
	var target := PackedInt32Array()
	target.resize(w * h)
	for y: int in h:
		for x: int in w:
			target[y * w + x] = GROUND
	var locked := {}
	# Each pond (a 4-connected run of water tiles) flat, one step under its lowest neighbour.
	var wet := {}
	for t: Vector2i in water:
		wet[t] = true
	var done := {}
	for t0: Vector2i in water:
		if done.has(t0):
			continue
		var pond: Array[Vector2i] = [t0]
		done[t0] = true
		var i := 0
		var low := CourseData.MAX_HEIGHT
		while i < pond.size():
			var p: Vector2i = pond[i]
			i += 1
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					var q := p + Vector2i(dx, dy)
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and not wet.has(q):
						low = mini(low, target[q.y * w + q.x])
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := p + d
				if wet.has(q) and not done.has(q):
					done[q] = true
					pond.append(q)
		for p: Vector2i in pond:
			target[p.y * w + p.x] = maxi(low - 1, 0)
			locked[p] = true
	for spec: Dictionary in specs:
		var g: Array = spec["green"]
		var cells := PlaytestNine.green_tiles(spec)
		var base: int = _mean_target(target, w, h, cells) + int(g[4])
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
		var tees := PlaytestNine.tee_tiles(spec)
		var tee_h: int = clampi(_mean_target(target, w, h, tees) + int(spec["tee_lift"]), 0,
				CourseData.MAX_HEIGHT)
		for t: Vector2i in tees:
			if course.in_bounds(t.x, t.y):
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


static func _paint(b: CourseBuilder, course: CourseData, cells: Array[Vector2i], surface: Surface.Type) -> void:
	b.begin_stroke()
	for t: Vector2i in cells:
		if course.in_bounds(t.x, t.y):
			b.paint(t, surface, 1)
	b.end_stroke()
