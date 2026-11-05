class_name ReactionHoles
extends RefCounted
## E3-S8 fixture: the holes `/balance reactions` plays its field on (scripts/balance_sim.gd,
## BalanceSim.measure_reactions; docs/design.md Balance targets, reactions). Each course holds
## one open hole, numbered 1, built through CourseBuilder the way a player builds one: a
## 3 x 3 tee box, a fairway along the line, a 5 x 5 green, the tee, the cup, the par, Open.
## Here, not in scripts/, because shaping the land (a ridge, unowned parcels) writes
## CourseData, which only course/builder.gd, course/save.gd and test fixtures may do.
##
## - fair_par4: the design's "fair par 4", 380 yd on level rough with a 5-wide fairway and
##   a cross bunker on the line 220 yd out with fairway round it, so every static check
##   passes (seen from the tee, a hazard on the line and a way round).
## - blind_par4: the same hole with a one-step ridge across the land 60 yd out, which hides
##   the landing zone from the tee (D43) and changes little else.
## - corridor_par4: a 380 yd par 4 on generated land (LandGenerator) in a corridor one parcel
##   (16 tiles, 80 yd) wide, every other parcel unowned (planning notes, Routing on land).
## - dogleg_par4: New sandbox, a fairway east 250 yd then south 220 yd round a pond filling
##   the inside corner; the straight tee-to-cup line is 333 yd and the fairway's centre line
##   470 yd. Rule 4 measures its line of play round the corner, 450 yd, a par 4 (D47).
## - crossing_holes (E3-S22): two open holes that cross. Hole 1 is the fair par 4's shape
##   without its bunker (380 yd east, a 5-wide fairway), and hole 2 a 90 yd par 3 coming
##   north to a green on hole 1's line 250 yd out, so a group putting on hole 2 stands in
##   the landing area of the next group's drives on hole 1.

const W: int = 90
const H: int = 30
const TEE := Vector2i(6, 15)
## 76 tiles from the tee: 380 yd.
const CUP := Vector2i(82, 15)
const BUNKER := Rect2i(50, 14, 2, 3)
const RIDGE_X: int = 18
const GROUND: int = 1

## Corridor: tiles of the parcel row it runs along, and its tee and cup.
const CORRIDOR_ROW: int = 3
const CORRIDOR_TEE := Vector2i(20, 56)
const CORRIDOR_CUP := Vector2i(96, 56)

const DOG_W: int = 70
const DOG_H: int = 60
const DOG_TEE := Vector2i(6, 6)
const DOG_CORNER := Vector2i(56, 6)
const DOG_CUP := Vector2i(56, 50)
const DOG_POND := Rect2i(14, 12, 38, 34)

## Crossing holes: hole 1 along row 10, hole 2 north up column 56 to a cup 4 rows below it.
const CROSS_W: int = 90
const CROSS_H: int = 40
const CROSS_TEE_1 := Vector2i(6, 10)
const CROSS_CUP_1 := Vector2i(82, 10)
const CROSS_TEE_2 := Vector2i(56, 32)
const CROSS_CUP_2 := Vector2i(56, 14)


static func fair_par4() -> CourseData:
	var c := CourseData.create(W, H, Surface.Type.ROUGH, GROUND)
	var b := CourseBuilder.new(c)
	_fairway(b, TEE, CUP, 5)
	_bunker(c)
	_finish(b, TEE, CUP, 4)
	return c


static func blind_par4() -> CourseData:
	var c := CourseData.create(W, H, Surface.Type.ROUGH, GROUND)
	for y in H:
		for x in range(RIDGE_X, RIDGE_X + 2):
			c.set_tile(x, y, GROUND + 1, c.get_surface(x, y))
	var b := CourseBuilder.new(c)
	_fairway(b, TEE, CUP, 5)
	_bunker(c)
	_finish(b, TEE, CUP, 4)
	return c


## Generated land of `land_seed`, owning only parcel row CORRIDOR_ROW; null when the hole
## does not open there.
static func corridor_par4(land_seed: int) -> CourseData:
	var c := LandGenerator.generate(land_seed)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), q == CORRIDOR_ROW)
	var b := CourseBuilder.new(c)
	_fairway(b, CORRIDOR_TEE, CORRIDOR_CUP, 5)
	if not _finish(b, CORRIDOR_TEE, CORRIDOR_CUP, 4):
		return null
	return c


static func dogleg_par4() -> CourseData:
	var c := CourseData.create(DOG_W, DOG_H, Surface.Type.ROUGH, GROUND)
	for y in range(DOG_POND.position.y, DOG_POND.end.y):
		for x in range(DOG_POND.position.x, DOG_POND.end.x):
			c.set_tile(x, y, GROUND, Surface.Type.WATER)
	var b := CourseBuilder.new(c)
	_fairway(b, DOG_TEE, DOG_CORNER, 5)
	_fairway(b, DOG_CORNER, DOG_CUP, 5)
	_finish(b, DOG_TEE, DOG_CUP, 4)
	return c


## E3-S22: hole 1 (par 4) and hole 2 (par 3, its green on hole 1's line 250 yd out), both
## open; New sandbox on level rough.
static func crossing_holes() -> CourseData:
	var c := CourseData.create(CROSS_W, CROSS_H, Surface.Type.ROUGH, GROUND)
	var b := CourseBuilder.new(c)
	for spec: Array in [[1, CROSS_TEE_1, CROSS_CUP_1, 4, 5], [2, CROSS_TEE_2, CROSS_CUP_2, 3, 3]]:
		var tee: Vector2i = spec[1]
		var cup: Vector2i = spec[2]
		_fairway(b, tee, cup, spec[4])
		b.paint(tee, Surface.Type.TEE, 3)
		b.paint(cup, Surface.Type.GREEN, 5)
		b.place_tee(spec[0], tee, spec[3])
		b.place_cup(spec[0], cup)
		b.set_par(spec[0], spec[3])
	# Each hole's painting sits in the other's footprint: open them last.
	for n: int in [1, 2]:
		var opened := b.open_hole(n)
		assert(opened, "crossing hole %d opens" % n)
	return c


static func _fairway(b: CourseBuilder, from: Vector2i, to: Vector2i, width: int) -> void:
	b.begin_stroke()
	for cell: Vector2i in BuildTool.grid_line(from, to):
		b.paint(cell, Surface.Type.FAIRWAY, width)
	b.end_stroke()


static func _bunker(c: CourseData) -> void:
	for y in range(BUNKER.position.y, BUNKER.end.y):
		for x in range(BUNKER.position.x, BUNKER.end.x):
			c.set_tile(x, y, c.get_height(x, y), Surface.Type.BUNKER)


static func _finish(b: CourseBuilder, tee: Vector2i, cup: Vector2i, par: int) -> bool:
	b.paint(tee, Surface.Type.TEE, 3)
	b.paint(cup, Surface.Type.GREEN, 5)
	b.place_tee(1, tee, par)
	b.place_cup(1, cup)
	b.set_par(1, par)
	return b.open_hole(1)
