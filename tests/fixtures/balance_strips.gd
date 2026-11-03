class_name BalanceStrips
extends RefCounted
## Test strips for scripts/balance_sim.gd (BalanceSim). They live here, not in scripts/,
## because they call CourseData.set_tile, which only course/builder.gd, course/save.gd and
## test fixtures may do (course/course_data.gd WRITERS). BalanceSim only reads them.
##
## Every strip is STRIP_W x STRIP_H fairway at height 0, with the ball started at the centre
## of tee_tile().

## Long enough for a driver's roll, wide enough for a sidehill curve.
const STRIP_W: int = 120
const STRIP_H: int = 24


static func tee_tile() -> Vector2i:
	return Vector2i(4, STRIP_H / 2)


## Flat fairway with a tee tile at the start (a fairway `surface`), or the start tile on
## `surface` otherwise.
static func strip(surface: Surface.Type) -> CourseData:
	return from(surface if surface != Surface.Type.FAIRWAY else Surface.Type.TEE)


## Flat fairway with only the start tile on `surface`.
static func from(surface: Surface.Type) -> CourseData:
	var c := CourseData.create(STRIP_W, STRIP_H, Surface.Type.FAIRWAY, 0)
	var t := tee_tile()
	c.set_tile(t.x, t.y, 0, surface)
	return c


## Fairway at height 0 up to and including the start tile's column, then `steps` up: the
## start tile centre is where the riser the ball faces begins (rise `steps`).
static func uphill(steps: int = 2) -> CourseData:
	var c := CourseData.create(STRIP_W, STRIP_H, Surface.Type.FAIRWAY, 0)
	var t := tee_tile()
	for y in STRIP_H:
		for x in range(t.x + 1, STRIP_W):
			c.set_tile(x, y, steps, Surface.Type.FAIRWAY)
	return c


## Fairway at height 0 up to and including the start tile's row, then 1 step up on +y: a
## 1-step band begins beside the aim (+x) at the start tile centre (tilt -1, right higher).
static func sidehill() -> CourseData:
	var c := CourseData.create(STRIP_W, STRIP_H, Surface.Type.FAIRWAY, 0)
	var t := tee_tile()
	for y in range(t.y + 1, STRIP_H):
		for x in STRIP_W:
			c.set_tile(x, y, 1, Surface.Type.FAIRWAY)
	return c
