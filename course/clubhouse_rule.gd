class_name ClubhouseRule
extends RefCounted
## Where the clubhouse may stand, and where a course gets one (D60, E5-S9). Reads CourseData
## only: CourseBuilder (a move, a New course) and CourseSave (an older file) do the writing.
##
## A clubhouse centred on `centre` facing `facing` may stand there when its 3x3 footprint and
## its door tile are on the map, and every footprint tile is owned, not water, not a tee or a
## green (the surface, or a hole's tee marker or cup), and no hole's line of play runs through
## the footprint (its tiles take no tee, cup or hole line). refusal names the first rule that
## fails, in that order, in one line for the Build HUD.
##
## The rule for a course with none (default_spot): inside the starting block
## (LandGenerator.start_block), against the middle of its +y edge (the side toward the
## camera's lower left), door facing +y; when that spot is refused, the allowed spot nearest it
## inside the block. When the block has no room, beside the first hole's tee: the allowed spot
## nearest that tee within BuilderTuning.clubhouse_tee_search tiles, its door facing the tee.
## With neither, none: the course has no clubhouse, and no guests come until one is placed.

const OFF_MAP: String = "off the map"
const ON_WATER: String = "not on water"
const ON_TEE: String = "not on a tee"
const ON_GREEN: String = "not on a green"
const ON_LINE: String = "in the way of hole %s"
## The facing the starting block's clubhouse gets: +y, its door toward the camera.
const BLOCK_FACING: int = 1


## Why a clubhouse centred on `centre` facing `facing` cannot stand there, or "" when it may.
## `lines` is each hole's line of play in CourseData.holes order (CourseBuilder.slot_lines, or
## lines_of_play here); a hole whose tee or cup is not placed has an empty line.
static func refusal(course: CourseData, centre: Vector2i, facing: int,
		lines: Array[PackedVector2Array]) -> String:
	var cells: Array[Vector2i] = CourseData.footprint_cells(centre)
	var door: Vector2i = CourseData.door_of(centre, facing)
	if not course.in_bounds(door.x, door.y):
		return OFF_MAP
	for c: Vector2i in cells:
		if not course.in_bounds(c.x, c.y):
			return OFF_MAP
	for c: Vector2i in cells:
		if not course.is_owned(c.x, c.y):
			return CourseBuilder.NOT_YOUR_LAND
	for c: Vector2i in cells:
		if course.get_surface(c.x, c.y) == Surface.Type.WATER:
			return ON_WATER
	for c: Vector2i in cells:
		if course.get_surface(c.x, c.y) == Surface.Type.TEE:
			return ON_TEE
		for h: HoleData in course.holes:
			if h.tee == c:
				return ON_TEE
	for c: Vector2i in cells:
		if course.get_surface(c.x, c.y) == Surface.Type.GREEN:
			return ON_GREEN
		for h: HoleData in course.holes:
			if h.cup == c:
				return ON_GREEN
	for i: int in mini(lines.size(), course.holes.size()):
		if crosses(lines[i], centre):
			return ON_LINE % course.hole_label(i)
	return ""


## True when the polyline `line` (tile coordinates, a tile's centre at its whole x and y) runs
## through the footprint of a clubhouse centred on `centre`.
static func crosses(line: PackedVector2Array, centre: Vector2i) -> bool:
	var half: float = CourseData.CLUBHOUSE_REACH + 0.5
	var lo := Vector2(centre) - Vector2(half, half)
	var hi := Vector2(centre) + Vector2(half, half)
	var corners: Array[Vector2] = [lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)]
	var box := Rect2(lo, hi - lo)
	for i: int in range(1, line.size()):
		var a: Vector2 = line[i - 1]
		var b: Vector2 = line[i]
		if box.has_point(a) or box.has_point(b):
			return true
		for k: int in 4:
			if Geometry2D.segment_intersects_segment(a, b, corners[k], corners[(k + 1) % 4]) != null:
				return true
	return false


## Each hole's line of play in CourseData.holes order (CourseValidator.line_of_play), empty for
## a hole whose tee or cup is not placed: what refusal reads when no builder is at hand.
static func lines_of_play(course: CourseData, validator: CourseValidator = null) -> Array[PackedVector2Array]:
	var v: CourseValidator = validator if validator != null else CourseValidator.new()
	var out: Array[PackedVector2Array] = []
	for h: HoleData in course.holes:
		if course.in_bounds(h.tee.x, h.tee.y) and course.in_bounds(h.cup.x, h.cup.y):
			out.append(v.line_of_play(course, h))
		else:
			out.append(PackedVector2Array())
	return out


## Where the rule puts a clubhouse on `course` (above): [centre, facing], or
## [CourseData.NO_CLUBHOUSE, BLOCK_FACING] when there is no room. Ignores any clubhouse the
## course has. `block_parcels` is the starting block's side (LandGenerator.start_block; 0, the
## default, is a New course's, 4 since D67); a file from before format version 3 and
## CourseGenerator's courses pass D26's 2 (LandTuning.D26_BLOCK_PARCELS), so they keep the
## clubhouse they had.
static func default_spot(course: CourseData, lines: Array[PackedVector2Array] = [],
		tuning: BuilderTuning = null, block_parcels: int = 0) -> Array:
	var t: BuilderTuning = tuning if tuning != null else BuilderTuning.load_default()
	if lines.is_empty() and not course.holes.is_empty():
		lines = lines_of_play(course)
	var block: Rect2i = LandGenerator.start_block(course.width, course.height, block_parcels)
	var reach: int = CourseData.CLUBHOUSE_REACH
	# The middle of the block's +y edge, its door on the block's last row.
	var anchor := Vector2i(block.position.x + floori(block.size.x / 2.0), block.end.y - 2 - reach)
	var spots: Array[Vector2i] = []
	for y: int in range(block.position.y + reach, block.end.y - 1 - reach):
		for x: int in range(block.position.x + reach, block.end.x - reach):
			spots.append(Vector2i(x, y))
	var best: Variant = _nearest(course, spots, anchor, func(_c: Vector2i) -> int: return BLOCK_FACING, lines)
	if best != null:
		return [best, BLOCK_FACING]
	var first: HoleData = _first_tee(course)
	if first == null:
		return [CourseData.NO_CLUBHOUSE, BLOCK_FACING]
	return spot_beside(course, first.tee, lines, t.clubhouse_tee_search)


## The allowed spot nearest tile `at` within `reach` tiles of it (along x and along y), its door
## facing `at` (facing_toward): [centre, facing], or [CourseData.NO_CLUBHOUSE, BLOCK_FACING].
## The rule's fallback beside the first tee.
static func spot_beside(course: CourseData, at: Vector2i, lines: Array[PackedVector2Array],
		reach: int) -> Array:
	var spots: Array[Vector2i] = []
	for y: int in range(at.y - reach, at.y + reach + 1):
		for x: int in range(at.x - reach, at.x + reach + 1):
			spots.append(Vector2i(x, y))
	var toward := func(c: Vector2i) -> int: return facing_toward(c, at)
	var best: Variant = _nearest(course, spots, at, toward, lines)
	if best != null:
		return [best, facing_toward(best, at)]
	return [CourseData.NO_CLUBHOUSE, BLOCK_FACING]


## The facing whose door looks most nearly from `centre` toward `at` (the larger axis; on a
## tie, along y).
static func facing_toward(centre: Vector2i, at: Vector2i) -> int:
	var d: Vector2i = at - centre
	if absi(d.x) > absi(d.y):
		return 0 if d.x > 0 else 2
	return 1 if d.y >= 0 else 3


## The placed hole with the lowest number (its tee on the map), or null.
static func _first_tee(course: CourseData) -> HoleData:
	var best: HoleData = null
	for h: HoleData in course.holes:
		if course.in_bounds(h.tee.x, h.tee.y) and (best == null or h.number < best.number):
			best = h
	return best


## Of `spots`, the allowed one nearest `anchor` (ties: lower y, then lower x), each with the
## facing `facing_of` gives it; null when none is allowed.
static func _nearest(course: CourseData, spots: Array[Vector2i], anchor: Vector2i,
		facing_of: Callable, lines: Array[PackedVector2Array]) -> Variant:
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = (a - anchor).length_squared()
		var db: int = (b - anchor).length_squared()
		if da != db:
			return da < db
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	for c: Vector2i in spots:
		if refusal(course, c, facing_of.call(c), lines).is_empty():
			return c
	return null
