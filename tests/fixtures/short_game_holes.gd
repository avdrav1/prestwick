class_name ShortGameHoles
extends RefCounted
## E3-S24 fixture: the greens `/balance reactions` measures guests' short game on
## (scripts/scoring_edges.gd, ScoringEdges; docs/design.md Balance targets, reactions). Each
## course is a 21 x 21 tile plot of fairway at height 0 with a 7 x 7 green round the cup at
## its centre, CUP. Here, not in scripts/, because shaping a green writes CourseData, which
## only course/builder.gd, course/save.gd and test fixtures may do. A start is one hole whose
## tee is the tile the guest's ball starts on (GuestHole starts a guest on its tee marker),
## so a "hole" here is one putt or one chip played out.
##
## - flat_green: the green level with the fairway.
## - sloped_green: the green rising one step a tile along +x (heights 0 to 6 across it, the
##   fairway round it following its column's height), so every putt on it feels D6's 3%
##   slope (`slope_scale` 0.075 on a 0.4 band) and D7's hold keeps a still ball where it
##   stops. The steepest green a still ball rests on (D7: two steps a tile trickles).
## - tier_green: the green's east half (x from the cup's column on) one step up, a one-step
##   contour across the line of every east-west putt.

const SIZE: int = 21
const CUP := Vector2i(10, 10)
const GREEN_HALF: int = 3


static func flat_green() -> CourseData:
	return _green(func(_x: int, _y: int) -> int: return 0)


static func sloped_green() -> CourseData:
	return _green(func(x: int, _y: int) -> int:
		return clampi(x - (CUP.x - GREEN_HALF), 0, 2 * GREEN_HALF))


static func tier_green() -> CourseData:
	return _green(func(x: int, _y: int) -> int: return 1 if x >= CUP.x else 0)


## The putt starts on a green: every green tile `tiles` (Chebyshev rings 2 and 3) from the
## cup along the eight compass directions, so uphill, downhill, sidehill and diagonal putts
## of 10 and 15 yd (14 and 21 on the diagonals).
static func putt_starts() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r: int in [2, 3]:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			out.append(CUP + d * r)
	return out


## A chip's start on the fairway `off_tiles` tiles off the green's west edge on the cup's
## row: 5 yd a tile, so 1 is 5 yd off and 20 yd from the cup.
static func chip_start(off_tiles: int) -> Vector2i:
	return Vector2i(CUP.x - GREEN_HALF - off_tiles, CUP.y)


## `course` with one hole, par 3, from `start` to the cup (not validated: a start on the
## green is no tee box, and nothing here is opened in Build).
static func with_start(course: CourseData, start: Vector2i) -> HoleData:
	var hole := HoleData.new(1, 3, start, CUP, true)
	course.set_holes([hole] as Array[HoleData])
	return hole


static func _green(height: Callable) -> CourseData:
	var c := CourseData.create(SIZE, SIZE, Surface.Type.FAIRWAY, 0)
	for y in SIZE:
		for x in SIZE:
			var on := absi(x - CUP.x) <= GREEN_HALF and absi(y - CUP.y) <= GREEN_HALF
			c.set_tile(x, y, int(height.call(x, y)), Surface.Type.GREEN if on else Surface.Type.FAIRWAY)
	return c
