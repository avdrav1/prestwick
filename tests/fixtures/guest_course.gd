extends RefCounted
## E3-S4 fixture: three short open par 3s (80 yd) on a flat 48 x 24 New sandbox strip (every
## parcel owned), built through CourseBuilder as tests/fixtures/nine_holes.gd builds its
## holes, so a guest day on it is quick: holes 1 and 2 run east along row 6, hole 3 comes back
## west along row 16. Hole 2's cup to hole 3's tee is a 50 yd walk south.
## E9-S2: far_next_tee, two par 3s whose walk from hole 1's green to hole 2's tee is long, with
## or without a cart path along it.

## [number, tee, cup].
const HOLES: Array = [
	[1, Vector2i(4, 6), Vector2i(20, 6)],
	[2, Vector2i(24, 6), Vector2i(40, 6)],
	[3, Vector2i(40, 16), Vector2i(24, 16)],
]


## The course and the builder that built it (to edit holes mid-day).
static func build() -> CourseBuilder:
	var b := CourseBuilder.new(CourseData.create(48, 24, Surface.Type.ROUGH, 2))
	for spec: Array in HOLES:
		var n: int = spec[0]
		var tee: Vector2i = spec[1]
		var cup: Vector2i = spec[2]
		b.begin_stroke()
		for cell: Vector2i in BuildTool.grid_line(tee, cup):
			b.paint(cell, Surface.Type.FAIRWAY, 3)
		b.end_stroke()
		b.paint(tee, Surface.Type.TEE, 3)
		b.paint(cup, Surface.Type.GREEN, 5)
		b.place_tee(n, tee, 3)
		b.place_cup(n, cup)
	# Each hole opened itself once legal (E8-S1, D64); check they all stand open.
	for spec: Array in HOLES:
		var opened: bool = b.hole(spec[0]).open
		assert(opened, "fixture hole %d opens" % spec[0])
	# E5-S11 (D60): the clubhouse beside hole 1's tee, where guests arrive and leave.
	b.move_clubhouse_beside(HOLES[0][1])
	return b


static func course() -> CourseData:
	return build().course


## E9-S2 (D65): two 80 yd par 3s on a flat 100 x 40 strip, hole 2's tee far from hole 1's cup
## (277 yd, about 7 s over rough: over every guest's walk limit), the clubhouse beside hole 1's
## tee. With `path`, a cart path runs along the walk from beside hole 1's cup to beside hole
## 2's tee (the holes it crosses reopened), so the walk follows it.
const FAR_HOLES: Array = [
	[1, Vector2i(4, 6), Vector2i(20, 6)],
	[2, Vector2i(70, 30), Vector2i(86, 30)],
]


static func far_next_tee(path: bool) -> CourseData:
	var b := CourseBuilder.new(CourseData.create(100, 40, Surface.Type.ROUGH, 2))
	for spec: Array in FAR_HOLES:
		var n: int = spec[0]
		var tee: Vector2i = spec[1]
		var cup: Vector2i = spec[2]
		b.begin_stroke()
		for cell: Vector2i in BuildTool.grid_line(tee, cup):
			b.paint(cell, Surface.Type.FAIRWAY, 3)
		b.end_stroke()
		b.paint(tee, Surface.Type.TEE, 3)
		b.paint(cup, Surface.Type.GREEN, 5)
		b.place_tee(n, tee, 3)
		b.place_cup(n, cup)
	if path:
		b.begin_stroke()
		for cell: Vector2i in BuildTool.grid_line(Vector2i(21, 8), Vector2i(69, 28)):
			b.paint(cell, Surface.Type.CART_PATH, 1)
		b.end_stroke()
	# Each hole opened itself once legal (E8-S1, D64); one the path closed is opened again.
	for spec: Array in FAR_HOLES:
		if not b.hole(spec[0]).open:
			b.open_hole(spec[0])
		var opened: bool = b.hole(spec[0]).open
		assert(opened, "far fixture hole %d opens" % spec[0])
	b.move_clubhouse_beside(FAR_HOLES[0][1])
	return b.course
