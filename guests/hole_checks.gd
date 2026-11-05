class_name HoleChecks
extends RefCounted
## The static half of the four checks (E3-S6; docs/design.md Guests and reactions, Fair and
## Interesting): whether a hole's tee shot is blind (D43) and whether the hole is interesting
## (E3-S1). Both read only the course (CourseData's getters) and the hole's tee and cup, never
## a guest, so they are measured once per hole and kept until the hole's tee or cup or the
## course's terrain (heights, surfaces, owned land) changes. Pace and challenge read the
## guest's own play (GuestReaction).
##
## A reader only: like the validator, it never writes the course.

## The surfaces a hole's line can cross that make it interesting (with unowned land): the
## hazards of the ball (water, oob) and the ones that cost a shot (bunker, trees).
const HAZARDS: Array[Surface.Type] = [
	Surface.Type.WATER, Surface.Type.BUNKER, Surface.Type.TREES, Surface.Type.OOB,
]


## What the static checks found for one hole.
class Statics:
	extends RefCounted
	## D43: the target cannot be seen from the tee.
	var blind: bool = false
	## The tile where the sight line first meets ground or trees (when blind).
	var blind_at: Vector2i = Vector2i(-1, -1)
	## The sight line's target, in yards (the landing zone's centre or the cup).
	var target: Vector2 = Vector2.ZERO
	## True when the target is the landing zone's centre (holes of zone_from_yd or more).
	var target_is_zone: bool = false
	## The tee-to-cup line (rule 3's walk) crosses a hazard tile.
	var hazard_on_line: bool = false
	## A path of non-hazard tiles joins tee to cup (4 neighbours).
	var safe_route: bool = false

	func interesting() -> bool:
		return hazard_on_line and safe_route

	func fair() -> bool:
		return not blind


var tuning: GuestTuning
var validator_tuning: ValidatorTuning
var surfaces: SurfaceTable
var yards_per_tile: float
var yards_per_step: float
## How many times a hole's statics were measured (tests read it to see the cache work).
var measured: int = 0

## {Vector4i(tee, cup): Statics} for the terrain `_terrain_key` names.
var _cache: Dictionary = {}
var _terrain_key: String = ""
## hazard_grid of that terrain (empty until a hole with a hazard on its line needs it).
var _hazard := PackedByteArray()


func _init(p_tuning: GuestTuning = null, p_params: BallParams = null,
		p_validator_tuning: ValidatorTuning = null, p_surfaces: SurfaceTable = null) -> void:
	tuning = p_tuning if p_tuning != null else GuestTuning.load_default()
	var params := p_params if p_params != null else BallParams.load_default()
	yards_per_tile = params.yards_per_tile
	yards_per_step = params.yards_per_step
	validator_tuning = p_validator_tuning if p_validator_tuning != null \
			else ValidatorTuning.load_default()
	surfaces = p_surfaces if p_surfaces != null else SurfaceTable.load_default()


## The course's terrain as one key: its tiles (heights and surfaces) and owned land. Equal
## terrain gives an equal key; any tile or parcel edit changes it. About a millisecond on
## 128 x 128, so a caller checking many holes on an unchanged course passes it to `statics`.
static func terrain_key(course: CourseData) -> String:
	var d := course.to_dict()
	return ("%d:%d:%s:%s" % [course.width, course.height, d["tiles"], str(d["owned"])]).md5_text()


## `hole`'s statics on `course`, measured once and kept while its tee and cup and the
## terrain stay the same. `key` is terrain_key(course), when the caller already has it.
func statics(course: CourseData, hole: HoleData, key: String = "") -> Statics:
	if key == "":
		key = terrain_key(course)
	if key != _terrain_key:
		_cache.clear()
		_hazard = PackedByteArray()
		_terrain_key = key
	var k := Vector4i(hole.tee.x, hole.tee.y, hole.cup.x, hole.cup.y)
	if not _cache.has(k):
		_cache[k] = measure(course, hole, true)
	return _cache[k]


## Measures `hole`'s statics now (no cache). `cached` (from `statics`) reuses the hazard grid
## of the terrain `statics` last saw; otherwise it is read afresh.
func measure(course: CourseData, hole: HoleData, cached: bool = false) -> Statics:
	measured += 1
	var s := Statics.new()
	_sight(course, hole, s)
	var line := line_walk(hole.tee, hole.cup)
	for t: Vector2i in line:
		if is_hazard(course, t):
			s.hazard_on_line = true
			break
	if s.hazard_on_line:
		if not cached or _hazard.is_empty():
			_hazard = hazard_grid(course)
		s.safe_route = _route(course, _hazard, hole.tee, hole.cup)
	return s


## Fair (D43): the line from an eye `eye_height_yd` above the tee tile's drawn top to a mark
## `mark_height_yd` above the target tile's drawn top, sampled every `sight_step_yd` from one
## step past the tee up to the target, is at or below the drawn top of the tile under it, or
## under its top plus `block_height` on a trees tile (painted trees block wherever they stand,
## as they do for the ball).
func _sight(course: CourseData, hole: HoleData, s: Statics) -> void:
	var eye := _center(hole.tee)
	var zone: Variant = CourseValidator.new(validator_tuning).landing_zone(hole)
	if zone != null:
		s.target = ((zone as Vector2) + Vector2(0.5, 0.5)) * yards_per_tile
		s.target_is_zone = true
	else:
		s.target = _center(hole.cup)
	var eye_z := _top(course, hole.tee) + tuning.eye_height_yd
	var mark_z := _top(course, _tile_at(s.target)) + tuning.mark_height_yd
	var length := eye.distance_to(s.target)
	if length <= 0.0 or tuning.sight_step_yd <= 0.0:
		return
	var trees: float = surfaces.row(Surface.Type.TREES).block_height
	var d := tuning.sight_step_yd
	while d < length:
		var f := d / length
		var p := eye.lerp(s.target, f)
		var z := lerpf(eye_z, mark_z, f)
		var t := _tile_at(p)
		var top := _top(course, t)
		if z <= top or (course.get_surface(t.x, t.y) == Surface.Type.TREES and z < top + trees):
			s.blind = true
			s.blind_at = t
			return
		d += tuning.sight_step_yd


## True when `tile` is a hazard for Interesting: water, bunker, trees or oob, or unowned land.
static func is_hazard(course: CourseData, tile: Vector2i) -> bool:
	if not course.is_owned(tile.x, tile.y):
		return true
	return course.get_surface(tile.x, tile.y) in HAZARDS


## A 4-connected path of non-hazard tiles joins `from` and `to` (breadth-first, heights
## ignored, as rule 3's path).
static func safe_route(course: CourseData, from: Vector2i, to: Vector2i) -> bool:
	return _route(course, hazard_grid(course), from, to)


## 1 per hazard tile (is_hazard), row-major, for the whole map: one pass over the surfaces and
## one per unowned parcel, as the validator's rule 3 graph reads them.
static func hazard_grid(course: CourseData) -> PackedByteArray:
	var grid: PackedByteArray = course.surface_grid()
	var out := PackedByteArray()
	out.resize(grid.size())
	for i in grid.size():
		var t: int = grid[i]
		out[i] = 1 if (t == Surface.Type.WATER or t == Surface.Type.BUNKER
				or t == Surface.Type.TREES or t == Surface.Type.OOB) else 0
	for q: int in course.parcels_high:
		for p: int in course.parcels_wide:
			if course.is_parcel_owned(Vector2i(p, q)):
				continue
			var r: Rect2i = course.parcel_rect(Vector2i(p, q))
			for y: int in range(r.position.y, r.end.y):
				for x: int in range(r.position.x, r.end.x):
					out[y * course.width + x] = 1
	return out


static func _route(course: CourseData, hazard: PackedByteArray, from: Vector2i, to: Vector2i) -> bool:
	if not course.in_bounds(from.x, from.y) or not course.in_bounds(to.x, to.y):
		return false
	var w := course.width
	var last := w * course.height - 1
	var start := from.y * w + from.x
	var goal := to.y * w + to.x
	if hazard[start] == 1 or hazard[goal] == 1:
		return false
	var seen := PackedByteArray()
	seen.resize(last + 1)
	var queue := PackedInt32Array()
	queue.resize(last + 1)
	queue[0] = start
	seen[start] = 1
	var head := 0
	var tail := 1
	while head < tail:
		var i: int = queue[head]
		head += 1
		if i == goal:
			return true
		var x: int = i % w
		if x > 0 and seen[i - 1] == 0 and hazard[i - 1] == 0:
			seen[i - 1] = 1
			queue[tail] = i - 1
			tail += 1
		if x < w - 1 and seen[i + 1] == 0 and hazard[i + 1] == 0:
			seen[i + 1] = 1
			queue[tail] = i + 1
			tail += 1
		if i >= w and seen[i - w] == 0 and hazard[i - w] == 0:
			seen[i - w] = 1
			queue[tail] = i - w
			tail += 1
		if i + w <= last and seen[i + w] == 0 and hazard[i + w] == 0:
			seen[i + w] = 1
			queue[tail] = i + w
			tail += 1
	return false


## Rule 3's 4-connected walk along the tee-to-cup line (CourseValidator's
## _first_blocked_on_line steps the same way): every tile from `from` to `to`, both included.
static func line_walk(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [from]
	var line := Vector2(to - from)
	var p: Vector2i = from
	while p != to:
		var sx: int = signi(to.x - p.x)
		var sy: int = signi(to.y - p.y)
		if sx == 0:
			p.y += sy
		elif sy == 0:
			p.x += sx
		else:
			var px := Vector2(p + Vector2i(sx, 0) - from)
			var py := Vector2(p + Vector2i(0, sy) - from)
			p = p + (Vector2i(sx, 0) if absf(line.cross(px)) <= absf(line.cross(py)) else Vector2i(0, sy))
		out.append(p)
	return out


func _center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * yards_per_tile


func _tile_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / yards_per_tile), floori(p.y / yards_per_tile))


## The drawn top of `tile` in yards (its whole height; off the map, 0).
func _top(course: CourseData, tile: Vector2i) -> float:
	return course.get_height(tile.x, tile.y) * yards_per_step
