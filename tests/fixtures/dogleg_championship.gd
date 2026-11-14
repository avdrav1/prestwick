class_name DoglegChampionship
extends RefCounted
## E19-S1 fixture: "Dogleg Hollow (Championship)", eighteen famous doglegs, every hole bending.
## Dogleg Hollow's nine (tests/fixtures/dogleg_hollow.gd, DoglegHollow.HOLES, unchanged) is the
## front nine (Out, 1 to 9) where it lies, on D71's 192 x 192 map; a new back nine (In, 10 to 18,
## BACK) of nine more famous real doglegs, each at its real par and yardage (docs/courses.md
## credits them; the names here are our own), fills the L of new ground to the east and south
## and the empty corner south-east of the 9th green. Laid through CourseBuilder only, with
## DoglegHollow.lay, on flat land at BuilderTuning's ground (CourseData.create: every parcel
## owned, an unlimited budget, as New sandbox): the same parkland, every hole down its own
## corridor of rough walled by a belt of trees, trees, water or sand in every corner.
## `courses/dogleg_hollow_championship.json` is this course saved with CourseSave; rebuild it with
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s res://scripts/save_dogleg_championship.gd
##
## The back nine's specs read as DoglegHollow's (tee, tee_lift, fairway, width, green, bunkers,
## trees, water, yd, turn). Every one is a dogleg the validator measures round its bend (D47):
## rule 4's disc on the straight tee-to-cup line holds no fairway and the ring 240 yd out meets
## each first leg just short of its bend. No par 3 turns: D47 measures a turn only on a hole of
## 240 yd or more straight, and a par 3 is under 320 yd, so a par 3 could bend only in its last 80
## yd, past a tee shot of 240 (no real par 3 is played so), and the back nine is par 4s and 5s as
## the front is.
##
## The back nine (docs/courses.md has the routing) was laid out with a scratch annealing search
## for nine L shapes that keep clear of each other and the front nine and chain green to tee, then
## placed by hand; each corner hazard sits on the inside of its bend, by the fairway.
##
## The turn (D72): the clubhouse stands south-east of the 9th green (23 tiles), a cart path's walk
## from the 1st tee, with the 10th tee (69 yd) and the 18th green (105 yd) beside it, so an
## eighteen turns at its door. Walks: a lane of rough on every walk of a round (the door to the 1st and 10th tees, the
## 9th and 18th greens to the door, each other green to the next tee), and a cart path (PATHS) on
## every walk too long for the least patient guest.

const PATH: String = "res://courses/dogleg_hollow_championship.json"
const COURSE_NAME: String = "Dogleg Hollow (Championship)"
const COURSE_AUTHOR: String = "Prestwick"
## D70: the famous course's id and version, written into the file (FamousCourses).
const COURSE_ID: String = "dogleg_hollow_championship"
const COURSE_VERSION: int = 1
## D71's map.
const SIZE: int = 192
## The clubhouse and the way its door faces (CourseData.FACINGS).
const CLUBHOUSE: Vector2i = Vector2i(122, 104)
const CLUBHOUSE_FACING: int = 1
## The par of the eighteen: the front nine's 37 and the back's.
const PAR: int = 74

## The eighteen's own cart paths (beside DoglegHollow.PATHS), as there: [the green the walk
## leaves (0: the clubhouse), the tee it reaches, the polyline]: the door up to the 1st tee, and
## each back-nine walk the least patient guest would find too long, laid off the straight line so
## the path is the quicker way (GuestWalk.route); the 10-11 path crosses the 13th fairway on a 45
## degree diagonal (DoglegHollow.path_tiles).
const PATHS: Array = [
	[0, 1, [Vector2(121, 102), Vector2(121, 80), Vector2(120, 78)]],
	[10, 11, [Vector2(91, 165), Vector2(91, 153), Vector2(84, 146), Vector2(84, 139)]],
	[11, 12, [Vector2(15, 173), Vector2(11, 181)]],
	[13, 14, [Vector2(121, 100), Vector2(126, 93)]],
	[14, 15, [Vector2(129, 18), Vector2(128, 11)]],
	[15, 16, [Vector2(186, 20), Vector2(186, 32), Vector2(184, 34)]],
]

const BACK: Array = [
	{
		# Augusta's 1st: right round a long bunker on the inside of the corner.
		"n": 10, "name": "Long Sand", "par": 4, "yd": 441, "turn": "right",
		"tee": Vector2i(129, 118), "cup": Vector2i(89, 170), "tee_lift": 1,
		"fairway": [Vector2(129.0, 123.0), Vector2(129.5, 168.7), Vector2(94.5, 169.8)], "width": 5,
		"green": [Vector2(89, 170), 4.0, 3.2, 178.0, 0, Vector2(-1.0, 0.03), 1, 1, 0.5],
		"bunkers": [[Vector2(123.7, 161.8), 4, 2, 89.0], [Vector2(95.5, 169.9), 1.2, 2, 178.0]],
		"trees": [],
		"water": [],
	},
	{
		# Harbour Town's 18th: left along water down the inside of the bend.
		"n": 11, "name": "Sound Side", "par": 4, "yd": 460, "turn": "left",
		"tee": Vector2i(85, 135), "cup": Vector2i(15, 169), "tee_lift": 1,
		"fairway": [Vector2(80.0, 134.6), Vector2(34.1, 131.0), Vector2(17.5, 164.1)], "width": 5,
		"green": [Vector2(15, 169), 4.0, 3.2, 117.0, 0, Vector2(-0.45, 0.89), 1, 1, 0.5],
		"bunkers": [[Vector2(16.3, 162.7), 1.2, 2, 117.0]],
		"trees": [],
		"water": [[Vector2(40.5, 139.0), 7, 3.5, -176.0]],
	},
	{
		# Machrihanish's 1st: left, the drive carrying as much water (the beach) as it dares.
		"n": 12, "name": "Beach Carry", "par": 4, "yd": 431, "turn": "left",
		"tee": Vector2i(8, 182), "cup": Vector2i(59, 144), "tee_lift": 1,
		"fairway": [Vector2(13.0, 182.0), Vector2(58.8, 181.6), Vector2(59.0, 149.5)], "width": 5,
		"green": [Vector2(59, 144), 4.0, 3.2, -90.0, 0, Vector2(0.01, -1.0), 1, 1, 0.5],
		"bunkers": [[Vector2(59.0, 150.5), 1.2, 2, -90.0]],
		"trees": [],
		"water": [[Vector2(51.7, 174.2), 7, 3.5, -0.0]],
	},
	{
		# Augusta's 5th: left round two deep bunkers in the corner, to a green by the clubhouse.
		"n": 13, "name": "Deep Corner", "par": 4, "yd": 455, "turn": "left",
		"tee": Vector2i(67, 147), "cup": Vector2i(117, 102), "tee_lift": 1,
		"fairway": [Vector2(72.0, 146.8), Vector2(118.1, 144.8), Vector2(117.1, 107.5)], "width": 5,
		"green": [Vector2(117, 102), 4.0, 3.2, -91.0, 0, Vector2(-0.03, -1.0), 1, 1, 0.5],
		"bunkers": [[Vector2(107.9, 140.1), 2.2, 1.4, -2.0], [Vector2(113.9, 140.9), 2.2, 1.4, -2.0], [Vector2(117.2, 108.5), 1.2, 2, -91.0]],
		"trees": [],
		"water": [],
	},
	{
		# Royal Lytham's 17th: left round the bunkers in the corner.
		"n": 14, "name": "Mashie Shot", "par": 4, "yd": 451, "turn": "left",
		"tee": Vector2i(126, 90), "cup": Vector2i(128, 23), "tee_lift": 1,
		"fairway": [Vector2(129.3, 86.2), Vector2(159.3, 52.0), Vector2(132.0, 26.7)], "width": 5,
		"green": [Vector2(128, 23), 4.0, 3.2, -137.0, 0, Vector2(-0.73, -0.68), 1, 1, 0.5],
		"bunkers": [[Vector2(148.9, 56.2), 2.2, 1.4, -49.0], [Vector2(153.6, 52.3), 2.2, 1.4, -49.0], [Vector2(132.9, 27.3), 1.2, 2, -137.0]],
		"trees": [],
		"water": [],
	},
	{
		# The Country Club's 17th: left round one bunker in the elbow.
		"n": 15, "name": "The Elbow", "par": 4, "yd": 369, "turn": "left",
		"tee": Vector2i(126, 9), "cup": Vector2i(183, 15), "tee_lift": 1,
		"fairway": [Vector2(130.1, 11.9), Vector2(167.2, 38.1), Vector2(179.9, 19.6)], "width": 5,
		"green": [Vector2(183, 15), 4.0, 3.2, -56.0, 0, Vector2(0.56, -0.83), 1, 1, 0.5],
		"bunkers": [[Vector2(164.8, 29.4), 4, 2, 35.0], [Vector2(179.3, 20.3), 1.2, 2, -56.0]],
		"trees": [],
		"water": [],
	},
	{
		# Muirfield's 8th: right round a cluster of bunkers in the corner.
		"n": 16, "name": "Corner Cluster", "par": 4, "yd": 442, "turn": "right",
		"tee": Vector2i(182, 36), "cup": Vector2i(142, 89), "tee_lift": 1,
		"fairway": [Vector2(182.0, 41.0), Vector2(182.0, 86.7), Vector2(147.5, 88.7)], "width": 5,
		"green": [Vector2(142, 89), 4.0, 3.2, 177.0, 0, Vector2(-1.0, 0.06), 1, 1, 0.5],
		"bunkers": [[Vector2(176.9, 76.7), 2.2, 1.4, 90.0], [Vector2(177.9, 82.7), 2.2, 1.4, 90.0], [Vector2(148.5, 88.9), 1.2, 2, 177.0]],
		"trees": [],
		"water": [],
	},
	{
		# Bay Hill's 6th, the bending par 5: right, wrapping round a lake.
		"n": 17, "name": "Wraparound", "par": 5, "yd": 553, "turn": "right",
		"tee": Vector2i(134, 98), "cup": Vector2i(179, 176), "tee_lift": 1,
		"fairway": [Vector2(138.7, 99.6), Vector2(182.0, 114.0), Vector2(179.3, 170.5)], "width": 6,
		"green": [Vector2(179, 176), 4.0, 3.2, 93.0, 0, Vector2(-0.05, 1.0), 1, 1, 0.5],
		"bunkers": [[Vector2(180.5, 169.7), 1.2, 2, 93.0]],
		"trees": [],
		"water": [[Vector2(172.8, 119.4), 7, 3.5, 18.0]],
	},
	{
		# Hazeltine's 16th: right round a pond in the corner, home to the clubhouse.
		"n": 18, "name": "Lakeside", "par": 4, "yd": 405, "turn": "right",
		"tee": Vector2i(172, 182), "cup": Vector2i(142, 112), "tee_lift": 1,
		"fairway": [Vector2(168.9, 178.1), Vector2(140.1, 142.4), Vector2(141.7, 117.5)], "width": 5,
		"green": [Vector2(142, 112), 4.0, 3.2, -86.0, 0, Vector2(0.06, -1.0), 1, 1, 0.5],
		"bunkers": [[Vector2(138.4, 116.8), 1.2, 2, -86.0]],
		"trees": [],
		"water": [[Vector2(150.3, 143.1), 7, 3.5, -129.0]],
	},
]


## The eighteen holes' specs: Dogleg Hollow's nine, then the back nine.
static func holes() -> Array:
	var out: Array = DoglegHollow.HOLES.duplicate()
	out.append_array(BACK)
	return out


## The spec of hole `n`, or an empty Dictionary.
static func spec(n: int) -> Dictionary:
	for s: Dictionary in holes():
		if int(s["n"]) == n:
			return s
	return {}


## The finished course as `courses/dogleg_hollow_championship.json` holds it.
static func course() -> CourseData:
	var c := land()
	var b := CourseBuilder.new(c)
	build(b)
	b.set_info(COURSE_NAME, COURSE_AUTHOR)
	c.set_course_id(COURSE_ID, COURSE_VERSION)
	return c


## Flat land at BuilderTuning's surface and ground, every parcel owned, an unlimited budget (New
## sandbox), as DoglegHollow.land but D71's size.
static func land() -> CourseData:
	var t := BuilderTuning.load_default()
	return CourseData.create(SIZE, SIZE, t.plot_surface, t.plot_ground)


## Builds the course on `b`'s course. Returns the numbers that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var specs := holes()
	DoglegHollow.lay(b, specs, walks(), DoglegHollow.PATHS + PATHS)
	if not b.move_clubhouse(CLUBHOUSE, CLUBHOUSE_FACING):
		push_error("DoglegChampionship: the clubhouse refused at %s" % CLUBHOUSE)
	return DoglegHollow.opened(b, specs)


## The clubhouse door's tile (CourseData.clubhouse_door for CLUBHOUSE and CLUBHOUSE_FACING).
static func door() -> Vector2i:
	var c := CourseData.create(SIZE, SIZE)
	c.set_clubhouse(CLUBHOUSE, CLUBHOUSE_FACING)
	return c.clubhouse_door()


## The walks of a round, as tile polylines: the door to the 1st tee, each green to the next tee
## through the nine, the 9th green to the door and the door to the 10th tee (the turn, D72), on
## through the back nine, and the 18th green to the door.
static func walks() -> Array:
	var specs := holes()
	var d := Vector2(door())
	var out: Array = []
	for i: int in specs.size():
		var s: Dictionary = specs[i]
		var tee := Vector2(s["tee"] as Vector2i)
		var n: int = s["n"]
		if n == 1 or n == 10:
			out.append([d, tee])
		else:
			out.append([Vector2((specs[i - 1] as Dictionary)["cup"] as Vector2i), tee])
		if n == 9 or n == 18:
			out.append([Vector2(s["cup"] as Vector2i), d])
	return out
