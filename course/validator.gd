class_name CourseValidator
extends RefCounted
## The six hole rules (docs/design.md Hole validation rules, D11, D30). The only implementation:
## the game (E2-S3) and /course-file validate (course/course_file.gd) both call it.
## A reader only: it never writes the course.
##
##   1. Exactly one tee and one cup.
##   2. Cup sits on a green tile.
##   3. A path of non-water, non-OB tiles connects tee to cup (4 neighbours, heights ignored).
##      A tile on an unowned parcel counts as OB (D30, E6-S4). A bridge crosses its water
##      (E14-S1, D69).
##   4. Yardage matches par (par 3 < 320, par 5 > 470), on the rounded line of play (D47): the
##      straight tee-to-cup line, or for a dogleg tee -> turn_point -> cup.
##   5. No tee inside another hole's landing zone (a disc on the line of play of each hole of
##      zone_from_yd or more, whatever its par: D35, E6-S37; a dogleg's at its turn, D51).
##   6. Tee and cup on owned land (D30, E6-S4). The footprint need not be owned.
##   7. On foot (E14-S3, D69): the tee, the cup and every dry tile of the footprint a ball could
##      rest on (owned, not OB, not the clubhouse) can be walked to from the clubhouse door (from
##      the tee with no clubhouse): through tiles that are dry or bridged, 8 neighbours, no
##      diagonal past water, heights ignored, any land, owned or not (the walks guests take,
##      guests/guest_walk.gd). The reason names the place: "no way to walk to the 9th green:
##      add a bridge". Measured once per course water and bridges (Walk) and per hole while they
##      and the hole's line stand, so an edit that moves no water costs nothing here.
##
## Each failing rule is one Issue: the rule, the tile at fault and a one-line reason.
## Hints (E3-S39, hint_slots) are Issues with rule HINT: advice shown in Build that never
## closes a hole or stops it opening (pillar 1); check_hole never returns them.
## Distances are between tile centres at YARDS_PER_TILE. Numbers come from ValidatorTuning.

## Grid constant (CLAUDE.md Grid, D4), the same as BallParams.yards_per_tile (a test checks).
const YARDS_PER_TILE: float = 5.0
const RULE_COUNT: int = 7
## The `rule` of a hint (hint_slots): not a rule at all.
const HINT: int = 0


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

## E14-S3: rule 7's walking graph for the course's water and bridges as last read (Walk.key),
## and the last few graphs by their walkable tiles (WALK_KEPT), so an undo that puts the water
## back as it was finds its graph labelled already.
var _walk_graph: Walk = null
var _walk_kept: Array[Walk] = []
## Rule 7's graphs kept for an undo (the latest and the ones before it).
const WALK_KEPT: int = 4
## _disc_offsets' cache: the radius it was built for and its offsets.
var _disc_r: float = -1.0
var _disc_cache: Array[Vector2i] = []
## The yardage the latest check_hole's rule 4 measured, for check_slots' `yards`.
var _rule4_yards: int = 0


func _init(p_tuning: ValidatorTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else ValidatorTuning.load_default()


## Rule 3's passable graph for one course, read once and shared by every hole checked
## against it. connected(a, b) first searches from `a` toward `b`, nearest-to-`b` first (a
## bucket queue on the 4-neighbour distance to `b`), and stops when it reaches `b`, so a hole
## with a clear line costs a few hundred tiles, not a flood of the map (E3-S12). A search that
## sees SEARCH_SLACK times the distance plus SEARCH_BASE tiles without reaching `b` gives up,
## and `a`'s component is flooded and labelled as before; later questions about a labelled
## component, or a pair a search already joined, are answered from what was found.
## E3-S12: the builder keeps one between edits and hands it the tiles each edit wrote
## (update); what it found is kept unless an edit changed whether a tile can be crossed.
class Reach:
	extends RefCounted
	## The search's tile budget: SEARCH_SLACK x the 4-neighbour distance + SEARCH_BASE. Not a
	## tunable: it changes only how fast rule 3 answers, never what.
	const SEARCH_SLACK: int = 4
	const SEARCH_BASE: int = 256
	var _w: int
	var _h: int
	## 1 where a tile can be crossed (not water, not OB, on an owned parcel), 0 otherwise.
	var _passable := PackedByteArray()
	## Component id per tile, 0 = its component not searched out yet.
	var _label := PackedInt32Array()
	var _next_label: int = 1
	## Pairs a search joined (ia * size + ib -> true), kept with the labels.
	var _joined: Dictionary = {}
	## Search scratch, sized once: the search a tile was last seen in, the next tile in its
	## bucket, every tile seen in the current search in order, and each bucket's first tile.
	var _seen := PackedInt32Array()
	var _next := PackedInt32Array()
	var _visited := PackedInt32Array()
	var _head := PackedInt32Array()
	var _stamp: int = 0

	func _init(course: CourseData) -> void:
		_w = course.width
		_h = course.height
		var grid: PackedByteArray = course.surface_grid()
		_passable.resize(grid.size())
		for i in grid.size():
			var s: int = grid[i]
			_passable[i] = 0 if s == Surface.Type.WATER or s == Surface.Type.OOB else 1
		# E14-S1 (D69): a bridge crosses its water.
		for b: Vector2i in course.bridge_cells():
			_passable[b.y * _w + b.x] = 1
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
		_seen.resize(grid.size())
		_next.resize(grid.size())
		_visited.resize(grid.size())
		_head.resize(_w + _h)

	## Rereads `cells` of `course` (the tiles an edit wrote). True, dropping every label, when
	## any of them changed whether it can be crossed.
	func update(course: CourseData, cells: Array[Vector2i]) -> bool:
		var changed: bool = false
		for c: Vector2i in cells:
			var i: int = _index(c)
			if i < 0:
				continue
			var p: int = 1 if CourseValidator._crossable(course, c) else 0
			if p != _passable[i]:
				_passable[i] = p
				changed = true
		if changed:
			_label.fill(0)
			_next_label = 1
			_joined.clear()
		return changed

	## A 4-neighbour path of crossable tiles joins `a` and `b` (heights ignored).
	func connected(a: Vector2i, b: Vector2i) -> bool:
		var ia: int = _index(a)
		var ib: int = _index(b)
		if ia < 0 or ib < 0 or _passable[ia] == 0 or _passable[ib] == 0:
			return false
		if ia == ib:
			return true
		# A labelled component is complete: two tiles share it or they are apart.
		if _label[ia] != 0 or _label[ib] != 0:
			return _label[ia] == _label[ib]
		var key: int = ia * _passable.size() + ib
		if _joined.has(key):
			return true
		if _search(ia, ib):
			_joined[key] = true
			return true
		_flood(ia)
		return _label[ia] == _label[ib]

	func _index(t: Vector2i) -> int:
		if t.x < 0 or t.y < 0 or t.x >= _w or t.y >= _h:
			return -1
		return t.y * _w + t.x

	## Best-first from `start` toward `goal`: true on reaching it; false when its component
	## runs out or the tile budget does (nothing is labelled either way).
	func _search(start: int, goal: int) -> bool:
		_stamp += 1
		var st: int = _stamp
		var w: int = _w
		var last: int = _w * _h - 1
		var gx: int = goal % w
		var gy: int = goal / w
		_head.fill(-1)
		var seen: int = 0
		var lo: int = absi(start % w - gx) + absi(start / w - gy)
		var budget: int = SEARCH_SLACK * lo + SEARCH_BASE
		_seen[start] = st
		_visited[0] = start
		seen = 1
		_next[start] = -1
		_head[lo] = start
		var top: int = _head.size()
		while true:
			while lo < top and _head[lo] == -1:
				lo += 1
			if lo >= top:
				break
			var i: int = _head[lo]
			_head[lo] = _next[i]
			var x: int = i % w
			var y: int = i / w
			for n: int in 4:
				var j: int
				var d: int
				if n == 0:
					if x == 0:
						continue
					j = i - 1
					d = absi(x - 1 - gx) + absi(y - gy)
				elif n == 1:
					if x == w - 1:
						continue
					j = i + 1
					d = absi(x + 1 - gx) + absi(y - gy)
				elif n == 2:
					if i < w:
						continue
					j = i - w
					d = absi(x - gx) + absi(y - 1 - gy)
				else:
					if i + w > last:
						continue
					j = i + w
					d = absi(x - gx) + absi(y + 1 - gy)
				if _passable[j] == 0 or _seen[j] == st:
					continue
				if j == goal:
					return true
				if seen >= budget:
					return false
				_seen[j] = st
				_visited[seen] = j
				seen += 1
				_next[j] = _head[d]
				_head[d] = j
				if d < lo:
					lo = d
		return false

	func _flood(start: int) -> void:
		var id: int = _next_label
		_next_label += 1
		var w: int = _w
		var last: int = _w * _h - 1
		var queue := _visited
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
## two holes sharing a number each keep their own, rule 1 on its own tee naming the other. The passable
## graph is read once for all holes, or `reach` is used when given (the builder's, kept
## between edits, E3-S12): it must describe `course` as it is now. When `yards` is given it is
## filled with each slot's hole_yardage as rule 4 measured it (0 when not placed), so a caller
## showing it need not measure a dogleg again (E3-S25 review).
## When `turns` is given it is filled with each slot's turn_point (null when straight or not
## placed), so a caller can keep each hole's line of play as checked (E3-S45).
## `known_turns`, when it holds one entry per slot, is each slot's turn_point on `course` as it
## is now, measured by the caller (CourseBuilder keeps them between edits, E3-S61), so the turns
## are not measured again.
func check_slots(course: CourseData, reach: Reach = null, yards: Array[int] = [],
		turns: Array = [], known_turns: Array = []) -> Array:
	var out: Array = []
	yards.clear()
	turns.clear()
	if reach == null:
		reach = Reach.new(course)
	turns.assign(known_turns if known_turns.size() == course.holes.size() else _all_turns(course))
	for i: int in course.holes.size():
		out.append(_check(course, course.holes[i], i, reach, turns))
		yards.append(_rule4_yards)
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


## E14-S3 (D69): rule 7's graph. A tile is walkable when it is on the map and is not water or
## carries a bridge; tiles join through their 8 neighbours, a diagonal only where both tiles
## beside it are walkable (as GuestWalk's search steps). Components are labelled when asked for,
## a flood from the tile asked about. One per course's water and bridges (key).
class Walk:
	extends RefCounted
	var key: String = ""
	var _w: int
	var _h: int
	var _ok := PackedByteArray()
	var _label := PackedInt32Array()
	var _next: int = 1
	var _strays := PackedInt32Array()
	var _strays_home: int = -1
	## Each hole's rule 7 issue on this graph (CourseValidator._rule7), null when it passes.
	var issues: Dictionary = {}

	## The graph of `course`, its walkable tiles `ok` (walkable_tiles).
	func _init(course: CourseData, ok: PackedByteArray) -> void:
		key = Walk.key_of(course)
		_w = course.width
		_h = course.height
		_ok = ok
		_label.resize(ok.size())

	## 1 on each walkable tile of `course`, row by row.
	static func walkable_tiles(course: CourseData) -> PackedByteArray:
		var tiles: PackedByteArray = course.packed_tiles()
		var ok := PackedByteArray()
		ok.resize(tiles.size())
		var water: int = Surface.Type.WATER
		for i: int in tiles.size():
			if (tiles[i] & 0x0F) != water:
				ok[i] = 1
		for b: Vector2i in course.bridge_cells():
			ok[b.y * course.width + b.x] = 1
		return ok

	## True when this graph's walkable tiles are `ok`.
	func same(ok: PackedByteArray) -> bool:
		return _ok == ok

	## What the graph reads of `course`: the course, its water and its bridges.
	static func key_of(course: CourseData) -> String:
		return "%d:%d:%d" % [course.get_instance_id(), course.surface_revision(Surface.Type.WATER),
				course.bridge_revision]

	func walkable(t: Vector2i) -> bool:
		return t.x >= 0 and t.y >= 0 and t.x < _w and t.y < _h and _ok[t.y * _w + t.x] != 0

	## The component of `t`, 0 when it is not walkable.
	func label(t: Vector2i) -> int:
		if not walkable(t):
			return 0
		var i: int = t.y * _w + t.x
		if _label[i] == 0:
			_flood(i)
		return _label[i]

	## E14-S3: the walkable tiles not in component `home`, by index (row order): the islands, read
	## once per graph and home (one pass over the map), so a hole's footprint is checked against
	## them alone, and a course with none checks nothing.
	func strays(home: int) -> PackedInt32Array:
		if home == _strays_home:
			return _strays
		_strays_home = home
		_strays = PackedInt32Array()
		for i: int in _ok.size():
			if _ok[i] != 0 and _label[i] != home:
				_strays.append(i)
		return _strays

	## Row width.
	func width() -> int:
		return _w

	## Labels the component holding `start` by spans: each run of a row is filled at once and
	## the rows above and below it are searched for runs to fill next. Diagonals step only past
	## two walkable tiles, so a diagonal tile is reached through either of them anyway, and 8
	## neighbours label as 4 do.
	func _flood(start: int) -> void:
		var id: int = _next
		_next += 1
		var w: int = _w
		var stack := PackedInt32Array([start])
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			if _label[i] != 0:
				continue
			@warning_ignore("integer_division")
			var y: int = i / w
			var row: int = y * w
			var l: int = i
			while l > row and _ok[l - 1] != 0 and _label[l - 1] == 0:
				l -= 1
			var r: int = i
			while r < row + w - 1 and _ok[r + 1] != 0 and _label[r + 1] == 0:
				r += 1
			for k: int in range(l, r + 1):
				_label[k] = id
			for off: int in [-w, w]:
				if (off < 0 and y == 0) or (off > 0 and y == _h - 1):
					continue
				var run: bool = false
				for k: int in range(l + off, r + off + 1):
					if _ok[k] != 0 and _label[k] == 0:
						if not run:
							stack.append(k)
							run = true
					else:
						run = false


## The failing rules of `hole`, in rule order; empty when all six pass. When its tee or cup
## is not placed, only rule 1 is reported: the others cannot be measured yet.
## `hole` is matched to its entry in `course.holes` (rules 1 and 5 compare it with the
## others): by identity, else the first entry with the same content, since set_holes stores
## copies. A hole with no entry is checked as if it were added to the course.
## `reach` lets callers checking several holes on an unchanged course share rule 3's flood.
func check_hole(course: CourseData, hole: HoleData, reach: Reach = null) -> Array[Issue]:
	var own: int = _own_index(course, hole)
	return _check(course, hole, own, reach if reach != null else Reach.new(course), _all_turns(course))


## check_hole for `hole` at index `own` of course.holes (-1: not in it), with `turns` each
## entry's turn_point, read once per check (rule 5 reads every other hole's zone).
func _check(course: CourseData, hole: HoleData, own: int, reach: Reach, turns: Array) -> Array[Issue]:
	var issues: Array[Issue] = []
	_rule4_yards = 0
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
	var turn: Variant = turns[own] if own >= 0 else turn_point(course, hole)
	_rule1(course, hole, own, issues)
	_rule2(course, hole, issues)
	_rule3(course, hole, reach, issues)
	_rule4(hole, turn, issues)
	_rule5(course, hole, own, turn, turns, issues)
	_rule6(course, hole, issues)
	_rule7(course, hole, turn, issues)
	return issues


## turn_point of every entry of course.holes, in order (null when straight or not placed).
func _all_turns(course: CourseData) -> Array:
	var out: Array = []
	for h: HoleData in course.holes:
		out.append(turn_point(course, h))
	return out


## The straight tee-to-cup line between tile centres, rounded to the nearest yard. Rule 5's
## zone threshold reads it; rule 4 and the card read hole_yardage, which is this number on
## every hole but a dogleg (D47).
static func yardage(tee: Vector2i, cup: Vector2i) -> int:
	return roundi(Vector2(cup - tee).length() * YARDS_PER_TILE)


## Rule 4's yardage (D47, E3-S25): the line of play, rounded to the nearest yard. A straight
## hole's is yardage(tee, cup); a dogleg's runs tee -> turn_point -> cup. The card, the hole
## list and /course-file show this number, and par is checked on it. 0 when not placed.
func hole_yardage(course: CourseData, hole: HoleData) -> int:
	if not _placed(course, hole.tee) or not _placed(course, hole.cup):
		return 0
	return _play_yards(hole, turn_point(course, hole))


## E8-S5: hole_yardage for a placed `hole` whose turn_point is `turn` (null for a straight one),
## so a reader that already measured the turn (the Build ruler) does not measure it twice.
static func play_yards(hole: HoleData, turn: Variant) -> int:
	return _play_yards(hole, turn)


## The rounded line of play of a placed `hole` whose turn_point is `turn`.
static func _play_yards(hole: HoleData, turn: Variant) -> int:
	if turn == null:
		return yardage(hole.tee, hole.cup)
	var b: Vector2 = turn
	return roundi((b.distance_to(Vector2(hole.tee)) + b.distance_to(Vector2(hole.cup))) * YARDS_PER_TILE)


## The line of play's points in tile coordinates (D47, D51): [tee, cup] on a straight hole,
## [tee, turn, cup] on a dogleg, empty when its tee or cup is not placed. The footprint and
## rule 5's zone follow it. `reads`, a Dictionary when given, gets turn_point's tiles read.
func line_of_play(course: CourseData, hole: HoleData, reads: Variant = null) -> PackedVector2Array:
	if not _placed(course, hole.tee) or not _placed(course, hole.cup):
		return PackedVector2Array()
	return line_of_play_through(hole, turn_point(course, hole, reads))


## line_of_play for a placed `hole` whose turn_point is `turn` (check_slots' `turns`).
static func line_of_play_through(hole: HoleData, turn: Variant) -> PackedVector2Array:
	if turn == null:
		return PackedVector2Array([Vector2(hole.tee), Vector2(hole.cup)])
	return PackedVector2Array([Vector2(hole.tee), turn as Vector2, Vector2(hole.cup)])


## Where a dogleg's line of play turns (D47, E3-S25), in tile coordinates, or null for a hole
## played on the straight line. A hole shorter on the straight line than a tee shot's landing
## distance (landing_distance_yd, 240 yd) is played at its cup and never turns. A longer one
## has rule 4's disc: zone_radius_yd round the point min(landing_distance_yd, yardage -
## cup_clearance_yd) from the tee on the straight line (rule 5's zone on a hole of
## zone_from_yd or more, but rule 4 does not need that threshold: E3-S25 review). It is
## straight while any fairway tile's centre lies inside that disc. Otherwise its tee shot is
## played to its own fairway: of the fairway tiles whose centres are the disc's distance from
## the tee, to half a tile, and ahead of the tee (toward the cup's side of it), the runs of
## neighbouring tiles (8 neighbours) whose fairway runs on, 8 neighbours through fairway, to
## within turn_cup_reach_yd of the cup. Of those the run nearest the disc's centre is where
## tee shots come down, and the turn is the mean of its tile centres. Another hole's fairway,
## or fairway behind the tee, never turns a hole; with no such run the hole stays straight.
## A reader only: what the course holds now, nothing stored, so painting the corner moves the
## turn and the yardage with it.
## E3-S61: `reads`, a Dictionary when given, gets every tile whose surface the answer read
## ({tile: true}: the disc, the ring, every tile the fairway walks looked at), so a fairway
## write anywhere else cannot change the turn (CourseBuilder keeps a hole's line until one lands
## on one of them). Nothing is added when the answer read no tile (too short to turn).
func turn_point(course: CourseData, hole: HoleData, reads: Variant = null) -> Variant:
	if not _placed(course, hole.tee) or not _placed(course, hole.cup):
		return null
	var line := Vector2(hole.cup - hole.tee)
	var yards: int = yardage(hole.tee, hole.cup)
	if line == Vector2.ZERO or yards < tuning.landing_distance_yd:
		return null
	var out_tiles: float = maxf(minf(tuning.landing_distance_yd, yards - tuning.cup_clearance_yd), 0.0) \
			/ YARDS_PER_TILE
	var tee := Vector2(hole.tee)
	var z: Vector2 = tee + line.normalized() * out_tiles
	var disc_r: float = tuning.zone_radius_yd / YARDS_PER_TILE
	if reads != null:
		var zi := Vector2i(roundi(z.x), roundi(z.y))
		for d: Vector2i in _disc_offsets(disc_r):
			(reads as Dictionary)[zi + d] = true
	if _fairway_in_disc(course, z, disc_r):
		return null
	var left := {}
	for t: Vector2i in _fairway_ring(course, hole.tee, out_tiles, reads):
		if Vector2(t - hole.tee).dot(line) > 0.0:
			left[t] = true
	# Split the ring into runs (8-neighbour components), each with its nearest tile to z.
	var runs: Array = []
	while not left.is_empty():
		var first: Vector2i = left.keys()[0]
		left.erase(first)
		var run: Array[Vector2i] = [first]
		var i: int = 0
		var near2: float = INF
		while i < run.size():
			var at: Vector2i = run[i]
			i += 1
			near2 = minf(near2, Vector2(at).distance_squared_to(z))
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var n := at + Vector2i(dx, dy)
					if left.has(n):
						left.erase(n)
						run.append(n)
		runs.append([near2, run])
	runs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var reach: float = tuning.turn_cup_reach_yd / YARDS_PER_TILE
	for entry: Array in runs:
		var run: Array[Vector2i] = entry[1]
		if not _fairway_runs_to(course, run, hole.cup, reach, reads):
			continue
		var sum := Vector2.ZERO
		for t: Vector2i in run:
			sum += Vector2(t)
		return sum / run.size()
	return null


## The par a rounded yardage calls for under rule 4.
func par_for_yardage(yards: int) -> int:
	if yards >= tuning.par5_min_yd:
		return 5
	if yards >= tuning.par4_min_yd:
		return 4
	return 3


## True when `cell` is under `hole` (D11 footprint): its centre is within
## footprint_half_width_yd of the line of play (D51, E3-S45: tee to cup, or tee to turn to cup
## on a dogleg). A hole whose tee or cup is not placed has no footprint. Measures the turn on
## every call: a caller testing many cells reads line_of_play once and asks near_line.
func in_footprint(course: CourseData, hole: HoleData, cell: Vector2i) -> bool:
	return near_line(line_of_play(course, hole), cell)


## True when `cell`'s centre is within footprint_half_width_yd of the polyline `line`
## (line_of_play's points). False for an empty line.
func near_line(line: PackedVector2Array, cell: Vector2i) -> bool:
	var p := Vector2(cell)
	for i: int in range(1, line.size()):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, line[i - 1], line[i])
		if _yards_between(p, closest) <= tuning.footprint_half_width_yd:
			return true
	return false


## Every in-map tile under `hole` (in_footprint), row-major. Empty when it is not placed.
func footprint(course: CourseData, hole: HoleData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var line: PackedVector2Array = line_of_play(course, hole)
	if line.is_empty():
		return out
	var pad: float = tuning.footprint_half_width_yd / YARDS_PER_TILE
	var box := Rect2(line[0], Vector2.ZERO)
	for pt: Vector2 in line:
		box = box.expand(pt)
	var lo := Vector2i(maxi(floori(box.position.x - pad), 0), maxi(floori(box.position.y - pad), 0))
	var hi := Vector2i(mini(ceili(box.end.x + pad), course.width - 1), mini(ceili(box.end.y + pad), course.height - 1))
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			if near_line(line, Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


## Rule 5's landing zone centre (D51, E3-S45), in tile coordinates, or null for a hole
## shorter than `zone_from_yd` on its line of play (which has none), whatever its par (D35,
## E6-S37). A straight hole's is landing_zone; a dogleg's is its turn_point, where its tee
## shots come down. Null when its tee or cup is not placed.
func play_zone(course: CourseData, hole: HoleData) -> Variant:
	if not _placed(course, hole.tee) or not _placed(course, hole.cup):
		return null
	return _zone(hole, turn_point(course, hole))


## play_zone for a placed `hole` whose turn_point is `turn`.
func _zone(hole: HoleData, turn: Variant) -> Variant:
	if turn == null:
		return landing_zone(hole)
	if _play_yards(hole, turn) < tuning.zone_from_yd:
		return null
	return turn


## The landing zone on the straight tee-to-cup line, in tile coordinates, or null for a hole
## shorter than `zone_from_yd` on the rounded straight yardage, whatever its par (D35,
## E6-S37). Rule 5 reads play_zone, which is this on every hole but a dogleg (D51); guests'
## sight check (D43) and rule 4's disc keep the straight line.
func landing_zone(hole: HoleData) -> Variant:
	var line := Vector2(hole.cup - hole.tee)
	if line == Vector2.ZERO:
		return null
	var yards: int = yardage(hole.tee, hole.cup)
	if yards < tuning.zone_from_yd:
		return null
	var out_yd: float = maxf(minf(tuning.landing_distance_yd, yards - tuning.cup_clearance_yd), 0.0)
	return Vector2(hole.tee) + line.normalized() * (out_yd / YARDS_PER_TILE)


## Each slot's hints (E3-S39), one array per entry of course.holes, in its order: a tee within
## approach_hint_yd of another hole's cup stands where that hole's approach shots come down,
## so guests waiting on it are in the way of a topped or long approach. Both holes get one,
## each on the tee's tile, as rule 5 reports a pair. A hole with its tee or cup not placed has
## none and gives none. Never a failing rule: a hole with hints opens.
func hint_slots(course: CourseData) -> Array:
	var out: Array = []
	var n: int = course.holes.size()
	for i: int in n:
		out.append([] as Array[Issue])
	var reach: float = tuning.approach_hint_yd
	for i: int in n:
		var h: HoleData = course.holes[i]
		if not _placed(course, h.tee) or not _placed(course, h.cup):
			continue
		for j: int in n:
			var o: HoleData = course.holes[j]
			if j == i or not _placed(course, o.tee) or not _placed(course, o.cup):
				continue
			var d: float = _yards_between(Vector2(h.cup), Vector2(o.tee))
			if d > reach:
				continue
			(out[i] as Array[Issue]).append(Issue.new(HINT, o.tee,
					"hole %s's tee is %d yd from this cup, where approach shots land: guests waiting there may be hit"
					% [course.hole_label(j), roundi(d)]))
			(out[j] as Array[Issue]).append(Issue.new(HINT, o.tee,
					"tee is %d yd from hole %s's cup, where its approach shots land: guests waiting here may be hit"
					% [roundi(d), course.hole_label(i)]))
	return out


# --- rules ---

func _rule1(course: CourseData, hole: HoleData, own: int, issues: Array[Issue]) -> void:
	if hole.tee == hole.cup:
		issues.append(Issue.new(1, hole.tee, "tee and cup are on the same tile"))
		return
	for i in course.holes.size():
		var other: HoleData = course.holes[i]
		if i != own and other.number == hole.number:
			# E3-S41: on the hole's own tee, naming its twin as the map and the list label it.
			issues.append(Issue.new(1, hole.tee, "shares number %d with hole %s" % [
					hole.number, course.hole_label(i)]))
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


func _rule4(hole: HoleData, turn: Variant, issues: Array[Issue]) -> void:
	var yards: int = _play_yards(hole, turn)
	_rule4_yards = yards
	var want: int = par_for_yardage(yards)
	if hole.par == want:
		return
	var bands := "par 3 up to %d, par 4 %d to %d, par 5 %d and up" % [
			tuning.par4_min_yd - 1, tuning.par4_min_yd, tuning.par5_min_yd - 1, tuning.par5_min_yd]
	var played: String = " round the dogleg" if yards != yardage(hole.tee, hole.cup) else ""
	issues.append(Issue.new(4, hole.cup, "%d yd%s is a par %d, not par %d (%s)" % [
			yards, played, want, hole.par, bands]))


func _rule5(course: CourseData, hole: HoleData, own: int, turn: Variant, turns: Array,
		issues: Array[Issue]) -> void:
	var own_zone: Variant = _zone(hole, turn)
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
		var zone: Variant = _zone(other, turns[i])
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


## E14-S3 (D69): the tee, the cup and every dry tile of the footprint a ball could rest on can
## be walked to from the clubhouse door, or from the tee with no clubhouse (Walk). One issue, on
## the first place no walk reaches: the tee, else the green (the cup), else the island nearest
## the tee along the footprint's rows. Kept per hole while the water, the bridges, the hole's line
## and the door stand.
func _rule7(course: CourseData, hole: HoleData, turn: Variant, issues: Array[Issue]) -> void:
	var k := Walk.key_of(course)
	if _walk_graph == null or _walk_graph.key != k:
		var ok := Walk.walkable_tiles(course)
		_walk_graph = null
		for g: Walk in _walk_kept:
			if g.same(ok) and g.key.begins_with("%d:" % course.get_instance_id()):
				_walk_graph = g
				_walk_kept.erase(g)
				break
		if _walk_graph == null:
			_walk_graph = Walk.new(course, ok)
		_walk_graph.key = k
		_walk_kept.push_front(_walk_graph)
		if _walk_kept.size() > WALK_KEPT:
			_walk_kept.resize(WALK_KEPT)
	var door: Vector2i = course.clubhouse_door() if course.has_clubhouse() else hole.tee
	var hk := [hole.number, hole.tee, hole.cup, turn, door, course.land_revision,
			course.clubhouse_revision, course.surface_revision(Surface.Type.OOB)]
	var kept_issues: Dictionary = _walk_graph.issues
	if kept_issues.has(hk):
		var kept: Variant = kept_issues[hk]
		if kept != null:
			issues.append(kept)
		return
	var issue: Issue = _walk_issue(course, hole, turn, door)
	kept_issues[hk] = issue
	if issue != null:
		issues.append(issue)


func _walk_issue(course: CourseData, hole: HoleData, turn: Variant, door: Vector2i) -> Issue:
	var home: int = _walk_graph.label(door)
	var name: String = _nth(hole.number)
	if home == 0 or _walk_graph.label(hole.tee) != home:
		return Issue.new(7, hole.tee, "no way to walk to the %s tee: add a bridge" % name)
	if _walk_graph.label(hole.cup) != home:
		return Issue.new(7, hole.cup, "no way to walk to the %s green: add a bridge" % name)
	var line: PackedVector2Array = line_of_play_through(hole, turn)
	var pad: float = tuning.footprint_half_width_yd / YARDS_PER_TILE
	var box := Rect2(line[0], Vector2.ZERO)
	for pt: Vector2 in line:
		box = box.expand(pt)
	var lo := Vector2i(maxi(floori(box.position.x - pad), 0), maxi(floori(box.position.y - pad), 0))
	var hi := Vector2i(mini(ceili(box.end.x + pad), course.width - 1), mini(ceili(box.end.y + pad), course.height - 1))
	var oob: int = Surface.Type.OOB
	var water: int = Surface.Type.WATER
	var w: int = _walk_graph.width()
	for i: int in _walk_graph.strays(home):
		@warning_ignore("integer_division")
		var t := Vector2i(i % w, i / w)
		if t.x < lo.x or t.x > hi.x or t.y < lo.y or t.y > hi.y:
			continue
		var s: int = course.get_surface(t.x, t.y)
		if s == oob or s == water or not course.is_owned(t.x, t.y) or course.is_clubhouse(t.x, t.y) \
				or not near_line(line, t):
			continue
		return Issue.new(7, t, "no way to walk to the island at %s on the %s: add a bridge"
				% [_fmt(t), name])
	return null


## "1st", "2nd", "3rd", "4th" ... for hole `n`.
static func _nth(n: int) -> String:
	var tail: String = "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				tail = "st"
			2:
				tail = "nd"
			3:
				tail = "rd"
	return "%d%s" % [n, tail]


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
	if s == Surface.Type.WATER:
		return course.is_bridge(tile.x, tile.y)  # E14-S1 (D69): a bridge crosses its water
	return s != Surface.Type.OOB


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


## True when any fairway tile's centre is within `r` tiles of `centre`. Reads the disc's
## tiles nearest the centre first, so a straight hole's fairway on its line answers at once.
func _fairway_in_disc(course: CourseData, centre: Vector2, r: float) -> bool:
	var at := Vector2i(roundi(centre.x), roundi(centre.y))
	var r2: float = r * r
	for d: Vector2i in _disc_offsets(r):
		var x: int = at.x + d.x
		var y: int = at.y + d.y
		if x < 0 or y < 0 or x >= course.width or y >= course.height:
			continue
		if course.get_surface(x, y) == Surface.Type.FAIRWAY \
				and Vector2(x, y).distance_squared_to(centre) <= r2:
			return true
	return false


## Tile offsets that can hold a centre within `r` tiles of a point near the origin tile (a
## point at most half a tile from it), nearest first; built once per radius.
func _disc_offsets(r: float) -> Array[Vector2i]:
	if _disc_r == r:
		return _disc_cache
	_disc_r = r
	_disc_cache = []
	var reach: int = ceili(r + 1.0)
	var lim2: float = (r + 0.71) * (r + 0.71)
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			if dx * dx + dy * dy <= lim2:
				_disc_cache.append(Vector2i(dx, dy))
	_disc_cache.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared())
	return _disc_cache


## True when the fairway holding `run` (8 neighbours through fairway) has a tile centre within
## `reach` tiles of `cup`: the run belongs to the fairway that leads to this hole's green. A
## depth-first walk that tries the step toward the cup first, so a fairway that does lead
## there answers after about its length in tiles; one that does not is read whole.
## `reads` (turn_point's), when given, gets every tile the walk looked at.
static func _fairway_runs_to(course: CourseData, run: Array[Vector2i], cup: Vector2i, reach: float,
		reads: Variant = null) -> bool:
	var r2: float = reach * reach
	var goal := Vector2(cup)
	var seen := {}
	var stack: Array[Vector2i] = []
	for t: Vector2i in run:
		seen[t] = true
		stack.append(t)
	var found: bool = false
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		if Vector2(at).distance_squared_to(goal) <= r2:
			found = true
			break
		var toward := at + Vector2i(signi(cup.x - at.x), signi(cup.y - at.y))
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var n := at + Vector2i(dx, dy)
				if n != toward:
					_walk(course, n, seen, stack)
		_walk(course, toward, seen, stack)
	if reads != null:
		(reads as Dictionary).merge(seen)
	return found


static func _walk(course: CourseData, n: Vector2i, seen: Dictionary, stack: Array[Vector2i]) -> void:
	if seen.has(n) or not course.in_bounds(n.x, n.y):
		return
	seen[n] = true
	if course.get_surface(n.x, n.y) == Surface.Type.FAIRWAY:
		stack.append(n)


## The in-map fairway tiles whose centres are `r` tiles from `from`, to half a tile: a
## one-tile ring, read row by row (two short spans a row), not its bounding box.
## `reads`, a Dictionary when given, gets every in-map tile of the ring, fairway or not.
static func _fairway_ring(course: CourseData, from: Vector2i, r: float, reads: Variant = null) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var outer: float = r + 0.5
	var inner: float = maxf(r - 0.5, 0.0)
	var reach: int = floori(outer)
	for dy: int in range(-reach, reach + 1):
		var y: int = from.y + dy
		if y < 0 or y >= course.height:
			continue
		var span: int = floori(sqrt(outer * outer - dy * dy))
		var gap2: float = inner * inner - dy * dy
		var near: int = ceili(sqrt(gap2)) if gap2 > 0.0 else 0
		# Left span, then right span; with no gap they meet at dx = 0, read once.
		for dx: int in range(-span, -near + 1):
			_ring_tile(course, from, Vector2i(dx, dy), inner, outer, out, reads)
		for dx: int in range(maxi(near, 1), span + 1):
			_ring_tile(course, from, Vector2i(dx, dy), inner, outer, out, reads)
	return out


static func _ring_tile(course: CourseData, from: Vector2i, d: Vector2i, inner: float, outer: float,
		out: Array[Vector2i], reads: Variant = null) -> void:
	var x: int = from.x + d.x
	if x < 0 or x >= course.width:
		return
	if reads != null:
		(reads as Dictionary)[Vector2i(x, from.y + d.y)] = true
	if course.get_surface(x, from.y + d.y) != Surface.Type.FAIRWAY:
		return
	var r: float = Vector2(d).length()
	if r >= inner and r <= outer:
		out.append(Vector2i(x, from.y + d.y))


static func _yards_between(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b) * YARDS_PER_TILE


static func _fmt(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]
