extends RefCounted
## E3-S4 fixture: three short open par 3s (80 yd) on a flat 48 x 24 New sandbox strip (every
## parcel owned), built through CourseBuilder as tests/fixtures/nine_holes.gd builds its
## holes, so a guest day on it is quick: holes 1 and 2 run east along row 6, hole 3 comes back
## west along row 16. Hole 2's cup to hole 3's tee is a 50 yd walk south.

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
	# Hole 2's tee sits in hole 1's footprint, so painting it closed hole 1: open them last.
	for spec: Array in HOLES:
		var opened := b.open_hole(spec[0])
		assert(opened, "fixture hole %d opens" % spec[0])
	return b


static func course() -> CourseData:
	return build().course
