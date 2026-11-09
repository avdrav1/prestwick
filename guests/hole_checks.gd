class_name HoleChecks
extends RefCounted
## The static half of the four checks (E3-S6; docs/design.md Guests and reactions, Fair and
## Interesting): whether a hole's tee shot is blind (D43, D55) and whether the hole is
## interesting (E3-S1). Both read only the course (CourseData's getters) and the hole's tee and
## cup, never a guest, so they are measured once per hole and kept until the hole's tee or cup
## or the terrain they read (heights, hazard surfaces, owned land: terrain_key) changes, or a
## fairway edit moves a dogleg's turn (the sight line's target, D55). Pace and challenge read
## the guest's own play (GuestReaction).
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
	## The sight line's target, in yards (a dogleg's turn, the landing zone's centre or the cup).
	var target: Vector2 = Vector2.ZERO
	## True when the target is where tee shots land, not the cup: a dogleg's turn (D55) or the
	## landing zone's centre (holes of zone_from_yd or more).
	var target_is_zone: bool = false
	## The dogleg turn the target was taken from (CourseValidator.turn_point, in tiles), or
	## null on a hole measured straight, and the fairway revision it was found at: a fairway
	## edit looks again and measures the hole afresh only if the turn moved.
	var turn: Variant = null
	var fairway_revision: int = -1
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
var _params: BallParams
var _validator: CourseValidator
## How many times a hole's statics were measured (tests read it to see the cache work).
var measured: int = 0

## {Vector4i(tee, cup): Statics} for the terrain `_terrain_key` names.
var _cache: Dictionary = {}
var _terrain_key: String = ""
## hazard_grid of that terrain (empty until a hole with a hazard on its line needs it).
var _hazard := PackedByteArray()
## E3-S34: route_parts of that hazard grid, labelled once per terrain (null until needed), so
## each hole's safe route is a lookup, not a flood: a step judging several freshly measured
## holes floods the map once, not once a hole.
var _parts: Parts = null
## The hazard grids and labellings made (tests and the perf script read it).
var parted: int = 0


## E3-S34: the 4-connected parts of a map's non-hazard tiles, as row runs (Hoshen-Kopelman):
## each row's runs of non-hazard tiles, found with PackedByteArray.find, joined to the runs of
## the row above they touch. Two tiles are joined by a safe route exactly when they lie in runs
## of the same part, which is what the breadth-first search finds.
class Parts:
	extends RefCounted
	var width: int = 0
	## The first run of each row, and one past the last row's last run (height + 1 entries).
	var row_first := PackedInt32Array()
	## Each run's first x and one past its last x.
	var x0 := PackedInt32Array()
	var x1 := PackedInt32Array()
	## Each run's part (the root run of its union-find tree, after labelling).
	var part := PackedInt32Array()

	## The part of tile (x, y), or -1 on a hazard tile.
	func part_of(x: int, y: int) -> int:
		for r: int in range(row_first[y], row_first[y + 1]):
			if x < x0[r]:
				return -1
			if x < x1[r]:
				return part[r]
		return -1


func _init(p_tuning: GuestTuning = null, p_params: BallParams = null,
		p_validator_tuning: ValidatorTuning = null, p_surfaces: SurfaceTable = null) -> void:
	tuning = p_tuning if p_tuning != null else GuestTuning.load_default()
	_params = p_params if p_params != null else BallParams.load_default()
	yards_per_tile = _params.yards_per_tile
	yards_per_step = _params.yards_per_step
	validator_tuning = p_validator_tuning if p_validator_tuning != null \
			else ValidatorTuning.load_default()
	_validator = CourseValidator.new(validator_tuning)
	surfaces = p_surfaces if p_surfaces != null else SurfaceTable.load_default()


## The terrain the statics read, as one key: `course` itself, its heights (the sight line),
## its hazard surfaces (HAZARDS: the line, the safe route, and trees blocking the sight line)
## and its owned land. An edit that changes none of them (rough painted over fairway, a cart
## path laid) keeps the key, so every hole's statics stand; any other changes it (E3-S74:
## before, a hash of every tile and parcel, about a millisecond, and any paint dropped every
## hole's statics). Read from CourseData's counters, so it costs nothing; another course,
## or a copy, has another key.
static func terrain_key(course: CourseData) -> String:
	var key := "%d:%d:%d" % [course.get_instance_id(), course.height_revision, course.land_revision]
	for s: Surface.Type in HAZARDS:
		key += ":%d" % course.surface_revision(s)
	return key


## `hole`'s statics on `course`, measured once and kept while its tee and cup and the
## terrain stay the same. `key` is terrain_key(course), when the caller already has it.
func statics(course: CourseData, hole: HoleData, key: String = "") -> Statics:
	if key == "":
		key = terrain_key(course)
	if key != _terrain_key:
		_cache.clear()
		_hazard = PackedByteArray()
		_parts = null
		_terrain_key = key
	var k := Vector4i(hole.tee.x, hole.tee.y, hole.cup.x, hole.cup.y)
	if _cache.has(k):
		var kept: Statics = _cache[k]
		var rev := course.surface_revision(Surface.Type.FAIRWAY)
		if kept.fairway_revision == rev:
			return kept
		# D55: fairway paint can move a dogleg's turn, the sight line's target. Painting that
		# leaves the turn where it was (any edit on a straight hole) keeps the statics.
		if kept.turn == _validator.turn_point(course, hole):
			kept.fairway_revision = rev
			return kept
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
		if not cached or _parts == null:
			_hazard = hazard_grid(course)
			_parts = route_parts(course, _hazard)
			parted += 1
		s.safe_route = joined(course, _parts, hole.tee, hole.cup)
	return s


## Fair (D43, D55): the line from an eye `eye_height_yd` above the drawn ground at the tee
## marker to a mark `mark_height_yd` above the drawn ground at the target, sampled every
## `sight_step_yd` from one step past the tee up to the target, stays above the drawn ground
## under it (HeightField.drawn_steps, the smooth surface the course view draws and the ball
## plays, D50), and on a trees tile above the tile's top plus `block_height` (painted trees
## block wherever they stand, as they do for the ball, Ball._blocks). The target is a
## dogleg's turn (CourseValidator.turn_point, where guests aim their tee shots, D54), else the
## landing zone's centre on a hole of zone_from_yd or more, else the cup.
func _sight(course: CourseData, hole: HoleData, s: Statics) -> void:
	var field := HeightField.new(course, _params)
	var eye := _center(hole.tee)
	s.fairway_revision = course.surface_revision(Surface.Type.FAIRWAY)
	s.turn = _validator.turn_point(course, hole)
	var zone: Variant = s.turn if s.turn != null else _validator.landing_zone(hole)
	if zone != null:
		s.target = ((zone as Vector2) + Vector2(0.5, 0.5)) * yards_per_tile
		s.target_is_zone = true
	else:
		s.target = _center(hole.cup)
	var eye_z := _ground(field, eye) + tuning.eye_height_yd
	var mark_z := _ground(field, s.target) + tuning.mark_height_yd
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
		if z <= _ground(field, p) or (course.get_surface(t.x, t.y) == Surface.Type.TREES
				and z < _top(course, t) + trees):
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


## E3-S34: labels the parts of `hazard`'s non-hazard tiles (Parts). Its cost goes with the
## runs, not the tiles: about a run a row on open land.
static func route_parts(course: CourseData, hazard: PackedByteArray) -> Parts:
	var p := Parts.new()
	var w := course.width
	p.width = w
	p.row_first.resize(course.height + 1)
	var parent := PackedInt32Array()
	var prev_first := 0
	for y: int in course.height:
		var first := p.x0.size()
		p.row_first[y] = first
		var base := y * w
		var end := base + w
		var x := base
		while x < end:
			var s0 := hazard.find(0, x)
			if s0 < 0 or s0 >= end:
				break
			var e0 := hazard.find(1, s0)
			if e0 < 0 or e0 > end:
				e0 = end
			p.x0.append(s0 - base)
			p.x1.append(e0 - base)
			parent.append(parent.size())
			x = e0
		# Join this row's runs to the runs of the row above that share a column with them.
		var i := prev_first
		var j := first
		var last := p.x0.size()
		while i < first and j < last:
			if p.x0[i] < p.x1[j] and p.x0[j] < p.x1[i]:
				# Roots, halving the paths on the way (inline: a packed array passed to a
				# function is a copy once written).
				var a := i
				while parent[a] != a:
					parent[a] = parent[parent[a]]
					a = parent[a]
				var b := j
				while parent[b] != b:
					parent[b] = parent[parent[b]]
					b = parent[b]
				if a != b:
					parent[maxi(a, b)] = mini(a, b)
			if p.x1[i] <= p.x1[j]:
				i += 1
			else:
				j += 1
		prev_first = first
	p.row_first[course.height] = p.x0.size()
	# Every run's parent is an earlier run, so one pass in order labels each with its root.
	p.part.resize(parent.size())
	for r: int in parent.size():
		var q: int = parent[r]
		p.part[r] = r if q == r else p.part[q]
	return p


## True when a safe route joins `from` and `to` on the parts `parts` (route_parts): both are
## non-hazard tiles of one part. The same answer as the breadth-first search (_route).
static func joined(course: CourseData, parts: Parts, from: Vector2i, to: Vector2i) -> bool:
	if not course.in_bounds(from.x, from.y) or not course.in_bounds(to.x, to.y):
		return false
	var a := parts.part_of(from.x, from.y)
	return a >= 0 and a == parts.part_of(to.x, to.y)


## The breadth-first search that route_parts replaced in measure (E3-S34); kept for the
## static safe_route and as the tests' reference.
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


## The top of `tile` in yards (its whole height; off the map, 0): where its trees stand for
## the ball (Ball._blocks) and so for the sight line.
func _top(course: CourseData, tile: Vector2i) -> float:
	return course.get_height(tile.x, tile.y) * yards_per_step


## The drawn ground at `p` (yards) in yards (D50: height_at, a water tile flat at its level).
func _ground(field: HeightField, p: Vector2) -> float:
	return field.drawn_steps(p.x, p.y) * yards_per_step
