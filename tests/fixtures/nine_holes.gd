extends RefCounted
## E3-S2 fixture: nine open holes in New sandbox on generated land: LandGenerator.generate(seed)
## (every parcel owned, an unlimited budget, as LandGenerator gives it), built through
## CourseBuilder the way a player would: a 3 x 3 tee box, a 3-wide fairway along the line
## (it paints over any pond, so rule 3 passes), a 5 x 5 green, the tee and cup, the par, Open.
## Pars 4 3 5 3 4 4 3 5 4 (35), in rows 11 to 14 tiles apart so no hole's painting touches
## another's footprint and no tee sits in a landing zone. Used by scripts/nine_holes_perf.gd
## (docs/design.md Plot's nine-hole frame and validator times) and the hole list screenshot.

## [number, par, tee, cup].
const HOLES: Array = [
	[1, 4, Vector2i(6, 8), Vector2i(82, 8)],
	[2, 3, Vector2i(92, 8), Vector2i(122, 8)],
	[3, 5, Vector2i(120, 19), Vector2i(16, 19)],
	[4, 3, Vector2i(8, 31), Vector2i(40, 31)],
	[5, 4, Vector2i(50, 31), Vector2i(122, 31)],
	[6, 4, Vector2i(120, 44), Vector2i(44, 44)],
	[7, 3, Vector2i(34, 44), Vector2i(6, 44)],
	[8, 5, Vector2i(6, 58), Vector2i(110, 58)],
	[9, 4, Vector2i(120, 72), Vector2i(44, 72)],
]


## The generated land of `land_seed` with every parcel owned.
static func land(land_seed: int = 7) -> CourseData:
	return LandGenerator.generate(land_seed)


## Builds the nine holes on `b`'s course. Returns the numbers that opened.
static func build(b: CourseBuilder) -> Array[int]:
	var opened: Array[int] = []
	for spec: Array in HOLES:
		var n: int = spec[0]
		var tee: Vector2i = spec[2]
		var cup: Vector2i = spec[3]
		b.begin_stroke()
		for cell: Vector2i in BuildTool.grid_line(tee, cup):
			b.paint(cell, Surface.Type.FAIRWAY, 3)
		b.end_stroke()
		b.paint(tee, Surface.Type.TEE, 3)
		b.paint(cup, Surface.Type.GREEN, 5)
		b.place_tee(n, tee, spec[1])
		b.place_cup(n, cup)
		b.set_par(n, spec[1])
		if b.hole(n).open:
			opened.append(n)
	# E5-S11 (D60): the clubhouse beside hole 1's tee, where guests arrive and leave.
	b.move_clubhouse_beside(HOLES[0][2])
	return opened
