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


## A copy of `land` with a fairway lane painted on it, heights kept (E6-S19): from `tee` (a tee
## tile) `length` tiles along `dir`, `half_width` tiles either side, as a player paints a
## hole over generated land. Every surface on the lane, trees and water included, becomes
## fairway, so a pond is a pit.
static func fairway_lane(land: CourseData, tee: Vector2i, dir: Vector2i, length: int,
		half_width: int = 2) -> CourseData:
	var c := CourseData.from_dict(land.to_dict())
	var across := Vector2i(dir.y, dir.x)
	for k in length:
		for w in range(-half_width, half_width + 1):
			var t := tee + dir * k + across * w
			if c.in_bounds(t.x, t.y):
				c.set_tile(t.x, t.y, c.get_height(t.x, t.y),
						Surface.Type.TEE if k == 0 else Surface.Type.FAIRWAY)
	return c
