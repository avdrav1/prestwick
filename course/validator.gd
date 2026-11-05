class_name CourseValidator
extends RefCounted
## The six hole rules (docs/design.md Hole validation rules, D11, D30). The only implementation:
## the game (E2-S3) and /course-file validate (course/course_file.gd) both call it.
## A reader only: it never writes the course.
##
##   1. Exactly one tee and one cup.
##   2. Cup sits on a green tile.
##   3. A path of non-water, non-OB tiles connects tee to cup (4 neighbours, heights ignored).
##      A tile on an unowned parcel counts as OB (D30, E6-S4).
##   4. Tee-to-cup yardage matches par (rounded straight line, par 3 < 320, par 5 > 470).
##   5. No tee inside another hole's landing zone (a disc on the line of each hole of
##      zone_from_yd or more, whatever its par: D35, E6-S37).
##   6. Tee and cup on owned land (D30, E6-S4). The footprint need not be owned.
##
## Each failing rule is one Issue: the rule, the tile at fault and a one-line reason.
## Distances are between tile centres at YARDS_PER_TILE. Numbers come from ValidatorTuning.

## Grid constant (CLAUDE.md Grid, D4), the same as BallParams.yards_per_tile (a test checks).
const YARDS_PER_TILE: float = 5.0
const RULE_COUNT: int = 6


## One failing rule of one hole.
class Issue:
	extends RefCounted
	## Rule number, 1 to RULE_COUNT.
	var rule: int
	## The tile to highlight.
	var tile: Vector2i
	## One line, no newline.
	var reason: String

	func _init(p_rule: int, p_tile: Vector2i, p_reason: String) -> void:
		rule = p_rule
		tile = p_tile
		reason = p_reason

	func _to_string() -> String:
		return "rule %d at %s: %s" % [rule, tile, reason]


var tuning: ValidatorTuning


func _init(p_tuning: ValidatorTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else ValidatorTuning.load_default()


## Rule 3's passable graph for one course, read once and shared by every hole checked
## against it: each tile's connected component, labelled lazily, one flood per component.
class Reach:
	extends RefCounted
	var _w: int
	var _h: int
	## 1 where a tile can be crossed (not water, not OB, on an owned parcel), 0 otherwise.
	var _passable := PackedByteArray()
	## Component id per tile, 0 = not flooded yet.
	var _label := PackedInt32Array()
	var _next_label: int = 1

	func _init(course: CourseData) -> void:
		_w = course.width
		_h = course.height
		var grid: PackedByteArray = course.surface_grid()
		_passable.resize(grid.size())
		for i in grid.size():
			var s: int = grid[i]
			_passable[i] = 0 if s == Surface.Type.WATER or s == Surface.Type.OOB else 1
		# Unowned land is OB for the path (D30): clear each unowned parcel's tiles.
		for q: int in course.parcels_high:
			for p: int in course.parcels_wide:
				if course.is_parcel_owned(Vector2i(p, q)):
					continue
				var r: Rect2i = course.parcel_rect(Vector2i(p, q))
				for y: int in range(r.position.y, r.end.y):
					for x: int in range(r.position.x, r.end.x):
						_passable[y * _w + x] = 0
		_label.resize(grid.size())

	## A 4-neighbour path of crossable tiles joins `a` and `b` (heights ignored).
	func connected(a: Vector2i, b: Vector2i) -> bool:
		var ia: int = _index(a)
		var ib: int = _index(b)
		if ia < 0 or ib < 0 or _passable[ia] == 0 or _passable[ib] == 0:
			return false
		if _label[ia] == 0:
			_flood(ia)
		return _label[ia] == _label[ib]

	func _index(t: Vector2i) -> int:
		if t.x < 0 or t.y < 0 or t.x >= _w or t.y >= _h:
			return -1
		return t.y * _w + t.x

	func _flood(start: int) -> void:
		var id: int = _next_label
		_next_label += 1
		var w: int = _w
		var last: int = _w * _h - 1
		var queue := PackedInt32Array()
		queue.resize(_w * _h)
		queue[0] = start
		_label[start] = id
		var head: int = 0
		var tail: int = 1
		while head < tail:
			var i: int = queue[head]
			head += 1
			var x: int = i % w
			if x > 0 and _passable[i - 1] == 1 and _label[i - 1] == 0:
				_label[i - 1] = id
				queue[tail] = i - 1
				tail += 1
			if x < w - 1 and _passable[i + 1] == 1 and _label[i + 1] == 0:
				_label[i + 1] = id
				queue[tail] = i + 1
				tail += 1
			if i >= w and _passable[i - w] == 1 and _label[i - w] == 0:
				_label[i - w] = id
				queue[tail] = i - w
				tail += 1
			if i + w <= last and _passable[i + w] == 1 and _label[i + w] == 0:
				_label[i + w] = id
				queue[tail] = i + w
				tail += 1


## Every hole's failing rules, keyed by hole number (empty array when it passes).
## Holes sharing a number share a key. The passable graph is read once for all holes.
func check_course(course: CourseData) -> Dictionary:
	return by_number(course, check_slots(course))


## Every hole's failing rules, one array per entry of `course.holes`, in its order (E3-S11):
## two holes sharing a number each keep their own, rule 1 naming the other's tee. The passable
## graph is read once for all holes.
func check_slots(course: CourseData) -> Array:
	var out: Array = []
	var reach := Reach.new(course)
	for hole: HoleData in course.holes:
		out.append(check_hole(course, hole, reach))
	return out


## check_slots' result `slots` for `course`, keyed by hole number as check_course gives it:
## holes sharing a number share a key, their issues in course order.
static func by_number(course: CourseData, slots: Array) -> Dictionary:
	var out := {}
	for i: int in course.holes.size():
		var number: int = course.holes[i].number
		var issues: Array[Issue] = []
		issues.assign(slots[i])
		if out.has(number):
			var existing: Array[Issue] = out[number]
			existing.append_array(issues)
		else:
			out[number] = issues
	return out


## The failing rules of `hole`, in rule order; empty when all six pass. When its tee or cup
## is not placed, only rule 1 is reported: the others cannot be measured yet.
## `hole` is matched to its entry in `course.holes` (rules 1 and 5 compare it with the
## others): by identity, else the first entry with the same content, since set_holes stores
## copies. A hole with no entry is checked as if it were added to the course.
## `reach` lets callers checking several holes on an unchanged course share rule 3's flood.
func check_hole(course: CourseData, hole: HoleData, reach: Reach = null) -> Array[Issue]:
	var issues: Array[Issue] = []
	var has_tee: bool = _placed(course, hole.tee)
	var has_cup: bool = _placed(course, hole.cup)
	if not has_tee or not has_cup:
		if has_tee:
			issues.append(Issue.new(1, hole.tee, "hole %d has a tee but no cup" % hole.number))
		elif has_cup:
			issues.append(Issue.new(1, hole.cup, "hole %d has a cup but no tee" % hole.number))
		else:
			issues.append(Issue.new(1, HoleData.UNPLACED, "hole %d has no tee and no cup" % hole.number))
		return issues
	var own: int = _own_index(course, hole)
	_rule1(course, hole, own, issues)
	_rule2(course, hole, issues)
	_rule3(course, hole, reach if reach != null else Reach.new(course), issues)
	_rule4(hole, issues)
	_rule5(course, hole, own, issues)
	_rule6(course, hole, issues)
	return issues


## Rule 4's yardage: the straight line between tile centres, rounded to the nearest yard.
## The card shows this number and par is checked on it.
static func yardage(tee: Vector2i, cup: Vector2i) -> int:
	return roundi(Vector2(cup - tee).length() * YARDS_PER_TILE)


## The par a rounded yardage calls for under rule 4.
func par_for_yardage(yards: int) -> int:
	if yards >= tuning.par5_min_yd:
		return 5
	if yards >= tuning.par4_min_yd:
		return 4
	return 3


## True when `cell` is under `hole` (D11 footprint): its centre is within
## footprint_half_width_yd of the tee-to-cup segment. A hole whose tee or cup is not placed
## has no footprint.
func in_footprint(course: CourseData, hole: HoleData, cell: Vector2i) -> bool:
	if not _placed(course, hole.tee) or not _placed(course, hole.cup):
		return false
	var p := Vector2(cell)
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, Vector2(hole.tee), Vector2(hole.cup))
	return _yards_between(p, closest) <= tuning.footprint_half_width_yd


## Every in-map tile under `hole` (in_footprint), row-major. Empty when it is not placed.
func footprint(course: CourseData, hole: HoleData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _placed(course, hole.tee) or not _placed(course, hole.cup):
		return out
	var pad: int = ceili(tuning.footprint_half_width_yd / YARDS_PER_TILE)
	var lo := Vector2i(maxi(mini(hole.tee.x, hole.cup.x) - pad, 0), maxi(mini(hole.tee.y, hole.cup.y) - pad, 0))
	var hi := Vector2i(mini(maxi(hole.tee.x, hole.cup.x) + pad, course.width - 1),
			mini(maxi(hole.tee.y, hole.cup.y) + pad, course.height - 1))
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			if in_footprint(course, hole, Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


## Rule 5's landing zone centre, in tile coordinates, or null for a hole shorter than
## `zone_from_yd` on the rounded yardage (which has none), whatever its par (D35, E6-S37).
func landing_zone(hole: HoleData) -> Variant:
	var line := Vector2(hole.cup - hole.tee)
	if line == Vector2.ZERO:
		return null
	var yards: int = yardage(hole.tee, hole.cup)
	if yards < tuning.zone_from_yd:
		return null
	var out_yd: float = maxf(minf(tuning.landing_distance_yd, yards - tuning.cup_clearance_yd), 0.0)
	return Vector2(hole.tee) + line.normalized() * (out_yd / YARDS_PER_TILE)


# --- rules ---

func _rule1(course: CourseData, hole: HoleData, own: int, issues: Array[Issue]) -> void:
	if hole.tee == hole.cup:
		issues.append(Issue.new(1, hole.tee, "tee and cup are on the same tile"))
		return
	for i in course.holes.size():
		var other: HoleData = course.holes[i]
		if i != own and other.number == hole.number:
			issues.append(Issue.new(1, other.tee,
					"hole %d has a second tee and cup, tee at %s" % [hole.number, _fmt(other.tee)]))
			return


func _rule2(course: CourseData, hole: HoleData, issues: Array[Issue]) -> void:
	var s: Surface.Type = course.get_surface(hole.cup.x, hole.cup.y)
	if s != Surface.Type.GREEN:
		issues.append(Issue.new(2, hole.cup, "cup is on %s, not green" % Surface.name_of(s)))


func _rule3(course: CourseData, hole: HoleData, reach: Reach, issues: Array[Issue]) -> void:
	if reach.connected(hole.tee, hole.cup):
		return
	var at: Vector2i = _first_blocked_on_line(course, hole.tee, hole.cup)
	var what: String = Surface.name_of(course.get_surface(at.x, at.y)) if course.is_owned(at.x, at.y) \
			else "unowned land"
	issues.append(Issue.new(3, at, "no path from tee to cup without water, oob or unowned land: %s at %s"
			% [what, _fmt(at)]))


func _rule4(hole: HoleData, issues: Array[Issue]) -> void:
	var yards: int = yardage(hole.tee, hole.cup)
	var want: int = par_for_yardage(yards)
	if hole.par == want:
		return
	var bands := "par 3 up to %d, par 4 %d to %d, par 5 %d and up" % [
			tuning.par4_min_yd - 1, tuning.par4_min_yd, tuning.par5_min_yd - 1, tuning.par5_min_yd]
	issues.append(Issue.new(4, hole.cup, "%d yd is a par %d, not par %d (%s)" % [yards, want, hole.par, bands]))


func _rule5(course: CourseData, hole: HoleData, own: int, issues: Array[Issue]) -> void:
	var own_zone: Variant = landing_zone(hole)
	for i in course.holes.size():
		var other: HoleData = course.holes[i]
		if i == own or not _placed(course, other.tee):
			continue
		# Another hole's tee in this hole's zone: needs only that tee placed.
		if own_zone != null:
			var d: float = _yards_between(own_zone as Vector2, Vector2(other.tee))
			if d <= tuning.zone_radius_yd:
				issues.append(Issue.new(5, other.tee, "hole %d's tee is in this hole's landing zone, %d yd from its centre"
						% [other.number, roundi(d)]))
				return
		# This hole's tee in another hole's zone: that zone is built from its cup.
		if not _placed(course, other.cup):
			continue
		var zone: Variant = landing_zone(other)
		if zone != null:
			var d: float = _yards_between(zone as Vector2, Vector2(hole.tee))
			if d <= tuning.zone_radius_yd:
				issues.append(Issue.new(5, hole.tee, "tee is in hole %d's landing zone, %d yd from its centre"
						% [other.number, roundi(d)]))
				return


## One issue for the tee and one for the cup, each on its tile, when it stands on a parcel
## the player does not own. A course that owns every parcel (New sandbox) always passes.
func _rule6(course: CourseData, hole: HoleData, issues: Array[Issue]) -> void:
	if not course.is_owned(hole.tee.x, hole.tee.y):
		issues.append(Issue.new(6, hole.tee, "tee is on land you do not own, at %s" % _fmt(hole.tee)))
	if not course.is_owned(hole.cup.x, hole.cup.y):
		issues.append(Issue.new(6, hole.cup, "cup is on land you do not own, at %s" % _fmt(hole.cup)))


# --- helpers ---

## The index of `hole` in `course.holes`: identity first, then the first entry with the same
## content (a caller holding the HoleData it passed to set_holes). -1 when there is none.
static func _own_index(course: CourseData, hole: HoleData) -> int:
	var by_identity: int = course.holes.find(hole)
	if by_identity >= 0:
		return by_identity
	var want: Dictionary = hole.to_dict()
	for i in course.holes.size():
		if course.holes[i].to_dict() == want:
			return i
	return -1


static func _placed(course: CourseData, tile: Vector2i) -> bool:
	return course.in_bounds(tile.x, tile.y)


static func _crossable(course: CourseData, tile: Vector2i) -> bool:
	if not course.is_owned(tile.x, tile.y):
		return false
	var s: Surface.Type = course.get_surface(tile.x, tile.y)
	return s != Surface.Type.WATER and s != Surface.Type.OOB


## The first water, OB or unowned tile on a 4-connected walk along the tee-to-cup line. A walk with
## none would itself be a path, so when rule 3 fails there is always one.
static func _first_blocked_on_line(course: CourseData, from: Vector2i, to: Vector2i) -> Vector2i:
	var line := Vector2(to - from)
	var p: Vector2i = from
	while true:
		if not _crossable(course, p):
			return p
		if p == to:
			break
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
	return to


static func _yards_between(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b) * YARDS_PER_TILE


static func _fmt(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]
