extends RefCounted
## E3-S23 fixture: tests/fixtures/nine_holes.gd's nine holes (the same land, LandGenerator seed
## 7 with every parcel owned, the same tees, cups and pars) built so guests can praise them.
## nine_holes.gd paints a 3-wide fairway over any pond, so no line crosses a hazard and every
## hole fails interesting; its hole 1 is blind (D43) behind a crest 200 yd out. Here, built
## through CourseBuilder the way a player would fix them:
##
## - each hole gets a 2-tile cross bunker on the centre row of its fairway, the fairway's
##   outer rows going round it (the safe route), so its line crosses a hazard with a way round
##   (interesting, docs/design.md Guests and reactions): on a hole with a rule 5 landing zone
##   (300 yd or more) the bunker sits at the zone's centre (240 yd out), as
##   ReactionHoles.fair_par4's sits near its zone; on a par 3, halfway to the cup;
## - hole 1's crest (tiles 46 to 51 of row 8, height 5) is cut one step under a 3-tile brush,
##   so the tee sees its landing zone (fair).
##
## Used by `scripts/guest_day.gd fixture=hazards` (docs/design.md Guest day, E3-S23) and
## tests/test_reactions.gd. nine_holes.gd stays as it was for the tests and perf scripts that
## read it.

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")

## Hole 1's crest, cut one step: from tile x CREST_FROM to CREST_TO on the tee's row.
const CREST_FROM: int = 46
const CREST_TO: int = 51
## A par 3's bunker sits this fraction of the way from tee to cup.
const PAR3_BUNKER_AT: float = 0.5


## The generated land of `land_seed` with every parcel owned (as nine_holes.gd's).
static func land(land_seed: int = 7) -> CourseData:
	return NineHoles.land(land_seed)


## Builds the nine holes on `b`'s course. Returns the numbers that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var opened: Array[int] = []
	var hole1: Array = NineHoles.HOLES[0]
	var row: int = (hole1[2] as Vector2i).y
	b.begin_stroke()
	for x: int in range(CREST_FROM, CREST_TO + 1):
		b.lower(Vector2i(x, row), 3)
	b.end_stroke()
	for spec: Array in NineHoles.HOLES:
		var n: int = spec[0]
		var par: int = spec[1]
		var tee: Vector2i = spec[2]
		var cup: Vector2i = spec[3]
		b.begin_stroke()
		for cell: Vector2i in BuildTool.grid_line(tee, cup):
			b.paint(cell, Surface.Type.FAIRWAY, 3)
		b.end_stroke()
		b.begin_stroke()
		for cell: Vector2i in bunker_cells(b.validator, n, par, tee, cup):
			b.paint(cell, Surface.Type.BUNKER, 1)
		b.end_stroke()
		b.paint(tee, Surface.Type.TEE, 3)
		b.paint(cup, Surface.Type.GREEN, 5)
		b.place_tee(n, tee, par)
		b.place_cup(n, cup)
		b.set_par(n, par)
		if b.hole(n).open:
			opened.append(n)
	# E5-S11 (D60): the clubhouse beside hole 1's tee, as on NineHoles.
	b.move_clubhouse_beside(NineHoles.HOLES[0][2])
	return opened


## The two bunker tiles of a hole: on the tee-to-cup row at its landing zone's centre (rule 5,
## `validator.landing_zone`) and the next tile toward the cup, or halfway on a shorter hole.
## Every fixture hole runs along one row.
static func bunker_cells(validator: CourseValidator, number: int, par: int, tee: Vector2i,
		cup: Vector2i) -> Array[Vector2i]:
	var zone: Variant = validator.landing_zone(HoleData.new(number, par, tee, cup))
	var dir := signi(cup.x - tee.x)
	var x: int
	if zone != null:
		x = roundi((zone as Vector2).x)
	else:
		x = tee.x + roundi((cup.x - tee.x) * PAR3_BUNKER_AT)
	return [Vector2i(x, tee.y), Vector2i(x + dir, tee.y)]
