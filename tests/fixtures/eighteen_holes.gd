extends RefCounted
## E18-S3 fixture: eighteen open holes on D71's 192 x 192 generated land (LandGenerator seed
## LAND_SEED with today's LandTuning, every parcel owned, an unlimited budget, as LandGenerator
## gives it), built through CourseBuilder the way tests/fixtures/nine_holes.gd builds its nine:
## a 3 x 3 tee box, a 3-wide fairway along the line, a 5 x 5 green, tee, cup, par, Open, and
## nine_holes_hazards.gd's 2-tile cross bunker on each line, so the holes can be praised.
## Two copies of the nine's layout (NineHoles.HOLES, pars 4 3 5 3 4 4 3 5 4): the front nine
## (Out, 1 to 9) mirrored up the map so it plays away from the middle, rows FRONT_BASE - y; the
## back nine (In, 10 to 18) as laid, rows BACK_SHIFT + y. Hole 1's tee and hole 10's tee face each
## other across the middle of the left edge, and the clubhouse stands between them, so an
## eighteen turns at its door between the 9th green and the 10th tee (D72), and a nine-hole group
## sent to the back nine walks out to the 10th as the front's walk out to the 1st.
## Used by tests/test_guest_brain.gd (rounds of nine and eighteen), scripts/guest_day.gd
## `fixture=eighteen` and the eighteen-hole rows of /balance reactions (ReactionField).

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const NineHolesHazards := preload("res://tests/fixtures/nine_holes_hazards.gd")
const LAND_SEED: int = 1
## Front nine tile row = FRONT_BASE - the nine's row; back nine = BACK_SHIFT + the nine's row.
const FRONT_BASE: int = 90
const BACK_SHIFT: int = 102


## [number, par, tee, cup] for all eighteen holes.
static func holes() -> Array:
	var out: Array = []
	for spec: Array in NineHoles.HOLES:
		var tee: Vector2i = spec[2]
		var cup: Vector2i = spec[3]
		out.append([spec[0], spec[1], Vector2i(tee.x, FRONT_BASE - tee.y),
				Vector2i(cup.x, FRONT_BASE - cup.y)])
	for spec: Array in NineHoles.HOLES:
		var tee: Vector2i = spec[2]
		var cup: Vector2i = spec[3]
		out.append([int(spec[0]) + 9, spec[1], Vector2i(tee.x, BACK_SHIFT + tee.y),
				Vector2i(cup.x, BACK_SHIFT + cup.y)])
	return out


## The generated 192 x 192 land of `land_seed`, every parcel owned.
static func land(land_seed: int = LAND_SEED) -> CourseData:
	return LandGenerator.generate(land_seed, LandTuning.load_default())


## Builds the eighteen holes on `b`'s course, the clubhouse between the 1st and 10th tees.
## Returns the numbers that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var opened: Array[int] = []
	for spec: Array in holes():
		var n: int = spec[0]
		var tee: Vector2i = spec[2]
		var cup: Vector2i = spec[3]
		b.begin_stroke()
		for cell: Vector2i in BuildTool.grid_line(tee, cup):
			b.paint(cell, Surface.Type.FAIRWAY, 3)
		b.end_stroke()
		b.begin_stroke()
		for cell: Vector2i in NineHolesHazards.bunker_cells(b.validator, n, spec[1], tee, cup):
			b.paint(cell, Surface.Type.BUNKER, 1)
		b.end_stroke()
		b.paint(tee, Surface.Type.TEE, 3)
		b.paint(cup, Surface.Type.GREEN, 5)
		b.place_tee(n, tee, spec[1])
		b.place_cup(n, cup)
		b.set_par(n, spec[1])
	for spec: Array in holes():
		if b.hole(spec[0]).open:
			opened.append(spec[0])
	@warning_ignore("integer_division")
	b.move_clubhouse_beside(Vector2i(6, (FRONT_BASE - 8 + BACK_SHIFT + 8) / 2))
	return opened


## The course built: {course, opened}.
static func course(land_seed: int = LAND_SEED) -> Dictionary:
	var c := land(land_seed)
	var opened := build(CourseBuilder.new(c))
	return {"course": c, "opened": opened}
