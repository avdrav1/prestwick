class_name GuestWalk
extends RefCounted
## One walk of a guest (E3-S4, docs/design.md Guests and reactions, Walking): a polyline in
## yards from where it stands to where it is going, walked by time (E9-S1, D65): the base
## `walk_yd_per_s` times each surface's `walk_surface_speed` (a cart path quickest; trees,
## bunkers and water slower), plus `walk_climb_s_per_step` for each height step climbed from
## one tile to the next, summed tile by tile along the line (time_pieces).
##
## A straight line, unless a cart path makes the walk quicker: a cart path tile within
## `cart_path_reach_yd` of the start and one within that of the end, joined through cart path
## tiles (8-connected, so a diagonal painted line holds), and the whole route (start, the
## path's tile centres, end) quicker than the straight walk. Then the guest walks the path.
## Before E9-S1 every surface was walked at one speed and the path was taken when at most
## `cart_path_max_detour` 1.5 times the straight line's yards, so it only ever lengthened a
## walk. A guest walks over any tile but open water, trees and unowned land included (E3-S1,
## unowned land is out of bounds for the ball, not a wall), only slower.
##
## E14-S2 (D69): guests never wade. A footbridge (CourseData.is_bridge) walks at cart path's
## speed and is a path tile for the path search. Of the straight walk and the path walk, the
## quicker that crosses no open water (water with no bridge) is taken; when both would wade,
## `_dry_route` searches the tiles for the quickest dry route (A*, 8 neighbours in a fixed order,
## no diagonal past water, each step timed as time_pieces times it, ties by the order reached)
## and straightens it where a straight line is dry and no slower. A searched walk follows a path
## (`on_path`) when it walks any cart path or bridge. A walk to a point no dry route reaches
## ends at the reachable tile nearest it (`goal` keeps the point asked for). The validator's
## rule 7 keeps every open hole's tee, cup and footprint reachable from the clubhouse door.
##
## Reads CourseData only. The route is fixed when the walk starts; a path painted mid-walk is
## used from the next walk.

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## Cart path searches kept for one course while its cart path tiles stand unchanged (E3-S15).
## A walk passed a Cache reads the course's path key first (its CourseData.surface_revision of
## CART_PATH, E3-S74: before, CourseData.revision, so any tile or parcel write dropped every
## search and the path grid, about 0.9 ms to read again) and drops what it holds when a tile
## turned to or from cart path since: the search reads nothing else, so a kept route is always
## the one a fresh search would find. GuestBrain holds one for the whole day.
class Cache:
	extends RefCounted
	## The path key (Cache.key) the searches and the grid stand for.
	var revision: String = ""
	## {Vector4i(start tile, end tile): [tiles between, empty for none; steps searched]}.
	var searches: Dictionary = {}
	## path_grid of that course (empty until a search needs it).
	var grid := PackedByteArray()
	## E12-S1 (D68): {Vector4(from, to) yards: the Reason a walk between them takes no path}.
	## Reads only the cart path tiles, as the search does.
	var reasons: Dictionary = {}
	## E14-S2: {Vector4(from, to) yards: the searched dry route's points}, while every tile and
	## bridge stands (follow_dry).
	var dry: Dictionary = {}
	var dry_revision: String = ""
	## E14-S2: the dry search's reading of the course (DryGrid), null until a search needs it.
	var dry_grid: DryGrid = null

	## Searches kept.
	func size() -> int:
		return searches.size()

	## E14-S2: drops the dry routes if `course` is another course, or any tile or bridge of it
	## was written, since they were searched.
	func follow_dry(course: CourseData) -> void:
		var k := "%d:%d:%d" % [course.get_instance_id(), course.revision, course.bridge_revision]
		if k != dry_revision:
			dry.clear()
			dry_grid = null
			dry_revision = k

	## Drops everything if `course` is another course, or a tile of it turned to or from cart
	## path, since it was filled.
	func follow(course: CourseData) -> void:
		var k := key(course)
		if k != revision:
			searches.clear()
			reasons.clear()
			grid = PackedByteArray()
			revision = k

	## What the path search reads of `course`, as one key: the course and its cart path writes.
	static func key(course: CourseData) -> String:
		return "%d:%d:%d" % [course.get_instance_id(), course.surface_revision(Surface.Type.CART_PATH),
				course.bridge_revision]


## E12-S1 (D68): why a walk follows no cart path, as the Build overlay (scenes/walk_overlay.gd)
## and the walk complaint (GuestReaction) both say it (`why` finds it, `text` words it).
class Reason:
	extends RefCounted
	## NO_PATH: no cart path on the course. NOT_NEAR: no path tile within reach of either end.
	## SHORT: a path within reach of one end stops `gap_yd` short of reach of the other.
	## SLOWER: a path joins both ends, but walking across is quicker.
	enum Kind { NO_PATH, NOT_NEAR, SHORT, SLOWER }
	var kind: Kind = Kind.NO_PATH
	## SHORT: how many yards nearer the path must come to be within reach, rounded up.
	var gap_yd: int = 0
	## NOT_NEAR and SHORT: the end the path does not reach is the walk's start (else its end).
	var at_start: bool = true
	## SHORT: the path tile nearest the end it misses (where the Build overlay draws the gap
	## from); (-1, -1) otherwise. Not saved.
	var near_tile := Vector2i(-1, -1)

	## The reason in a guest's words, `start` and `end` naming the walk's ends ("the 4th green",
	## "the 5th tee"): "path stops 32 yd short of the 5th tee".
	func text(start: String, end: String) -> String:
		match kind:
			Kind.NOT_NEAR:
				return "no path within reach of %s" % (start if at_start else end)
			Kind.SHORT:
				return "path stops %d yd short of %s" % [gap_yd, start if at_start else end]
			Kind.SLOWER:
				return "path is slower than walking across"
		return "no cart path"

	## For a save: [kind, gap_yd, at_start].
	func to_save() -> Array:
		return [int(kind), gap_yd, at_start]

	## The Reason `a` (to_save) holds; null when it is not one.
	static func from_save(a: Variant) -> Reason:
		if typeof(a) != TYPE_ARRAY or (a as Array).size() != 3:
			return null
		var k := int(a[0])
		if k < 0 or k >= Kind.size():
			return null
		var r := Reason.new()
		r.kind = k as Kind
		r.gap_yd = int(a[1])
		r.at_start = bool(a[2])
		return r


## The route's corners, yards: the start first, the end last.
var points: PackedVector2Array = PackedVector2Array()
## The route's length, yards.
var length: float = 0.0
## True when the route follows a cart path.
var on_path: bool = false
## E9-S1: the walk's time, simulated seconds, and what the straight walk would have taken
## (the same unless it follows a path).
var duration: float = 0.0
var straight_s: float = 0.0
## E9-S2: the yards of the walk on cart path tiles (the Walk check asked for half its length
## until E12-S1, D68; now `on_path` alone), and the straight walk's time were no cart
## path laid (its path tiles walked at the base speed): whether a path made the walk quick.
var path_yd: float = 0.0
var bare_s: float = 0.0
## Simulated seconds walked so far.
var elapsed: float = 0.0
## E9-S1: the walk cut where it crosses a tile edge (time_pieces): each piece's end, yards, and
## the walk's time at that end, so a guest's position is by time.
var _ends: PackedVector2Array = PackedVector2Array()
var _times: PackedFloat64Array = PackedFloat64Array()
## E14-S2: the point the walk was asked to reach, yards: its end, unless no dry route reaches it
## (then the walk ends at the reachable tile nearest it).
var goal: Vector2 = Vector2.ZERO
## E14-S2: true when the route was searched (both D65 walks would have waded).
var searched: bool = false


## The walk from `from` to `to` (yards) on `course`. `cache` shares the cart path search (and
## the path grid it reads) between walks while the course's cart path stands unchanged
## (Cache.follow). E9-S1: the path's route is taken only when quicker than the straight walk.
static func route(course: CourseData, from: Vector2, to: Vector2, tuning: GuestTuning,
		yards_per_tile: float = 5.0, cache: Cache = null) -> GuestWalk:
	var w := GuestWalk.new()
	w.goal = to
	w.points = PackedVector2Array([from, to])
	var on := PackedFloat64Array([0.0, 0.0, 0.0])
	w.straight_s = time_pieces(course, w.points, tuning, yards_per_tile, w._ends, w._times, on)
	w.duration = w.straight_s
	w.path_yd = on[0]
	w.bare_s = w.straight_s - on[1] + on[0] / tuning.walk_yd_per_s
	var dry: bool = on[2] == 0.0
	var path := _path_route(course, from, to, tuning, yards_per_tile, w.straight_s, cache)
	if path.size() > 2:
		var ends := PackedVector2Array()
		var times := PackedFloat64Array()
		var path_on := PackedFloat64Array([0.0, 0.0, 0.0])
		var t := time_pieces(course, path, tuning, yards_per_tile, ends, times, path_on)
		# E14-S2: the path walk when it is dry and quicker, or dry where the straight one wades.
		if path_on[2] == 0.0 and (t < w.straight_s or not dry):
			w.points = path
			w.on_path = true
			w.duration = t
			w._ends = ends
			w._times = times
			w.path_yd = path_on[0]
			dry = true
	if not dry:
		_take_dry_route(w, course, from, to, tuning, yards_per_tile, cache)
	w.length = _polyline_length(w.points)
	return w


## E14-S2: gives `w` the quickest dry route from `from` to `to` (_dry_route), its time and its
## path yards; it follows a path when it walks any cart path or bridge.
static func _take_dry_route(w: GuestWalk, course: CourseData, from: Vector2, to: Vector2,
		tuning: GuestTuning, ypt: float, cache: Cache) -> void:
	var pts := PackedVector2Array()
	var key := Vector4(from.x, from.y, to.x, to.y)
	if cache != null:
		cache.follow_dry(course)
		if cache.dry.has(key):
			pts = cache.dry[key]
	if pts.is_empty():
		var grid: DryGrid
		if cache != null:
			if cache.dry_grid == null:
				cache.dry_grid = DryGrid.new(course, tuning)
			grid = cache.dry_grid
		else:
			grid = DryGrid.new(course, tuning)
		pts = _dry_route(course, from, to, tuning, ypt, grid)
		if cache != null:
			cache.dry[key] = pts
	var ends := PackedVector2Array()
	var times := PackedFloat64Array()
	var on := PackedFloat64Array([0.0, 0.0, 0.0])
	var t := time_pieces(course, pts, tuning, ypt, ends, times, on)
	w.points = pts
	w.searched = true
	w.duration = t
	w._ends = ends
	w._times = times
	w.path_yd = on[0]
	w.on_path = on[0] > 0.0
	w.bare_s = t - on[1] + on[0] / tuning.walk_yd_per_s


## E9-S1 (D65): the time, simulated seconds, to walk the polyline `poly` (yards) on `course`:
## each piece between tile edges at its tile's walking speed (GuestTuning.walk_speed), and
## `walk_climb_s_per_step` for each step up from one tile to the next. Appends each piece's end
## to `ends` and the time there to `times` (a piece shorter than a thousandth of a yard, where
## the line grazes a tile's corner, is left out, so its tile neither slows nor lifts the walk).
## Off the map a tile walks as rough at the last height. E9-S2: `path_yd`, when given, gets the
## yards walked on cart path tiles added to its first value and, when it has a second, their
## time (climbs left out) to that. E14-S2: a bridge walks as cart path (and counts as one); a
## third value gets the yards walked on open water (water with no bridge), 0 for a dry walk.
static func time_pieces(course: CourseData, poly: PackedVector2Array, tuning: GuestTuning,
		ypt: float, ends: PackedVector2Array, times: PackedFloat64Array,
		path_yd: PackedFloat64Array = PackedFloat64Array()) -> float:
	var total := 0.0
	var prev_h := -1
	var cuts := PackedFloat64Array()
	for i: int in range(1, poly.size()):
		var a := poly[i - 1]
		var b := poly[i]
		var d := b - a
		var seg := d.length()
		if seg <= 0.0:
			continue
		cuts.clear()
		cuts.append(0.0)
		cuts.append(1.0)
		_edge_cuts(a.x / ypt, b.x / ypt, cuts)
		_edge_cuts(a.y / ypt, b.y / ypt, cuts)
		cuts.sort()
		for k: int in range(1, cuts.size()):
			var piece := (cuts[k] - cuts[k - 1]) * seg
			if piece < 1e-3:
				continue
			var mid := a + d * ((cuts[k] + cuts[k - 1]) * 0.5)
			var tx := floori(mid.x / ypt)
			var ty := floori(mid.y / ypt)
			var surface := Surface.Type.ROUGH
			var h := prev_h
			if course.in_bounds(tx, ty):
				surface = course.get_surface(tx, ty)
				h = course.get_height(tx, ty)
				if surface == Surface.Type.WATER:
					if course.is_bridge(tx, ty):
						surface = Surface.Type.CART_PATH  # E14-S2: a bridge walks as path
					elif path_yd.size() > 2:
						path_yd[2] += piece
			total += piece / tuning.walk_speed(surface)
			if surface == Surface.Type.CART_PATH and not path_yd.is_empty():
				path_yd[0] += piece
				if path_yd.size() > 1:
					path_yd[1] += piece / tuning.walk_speed(surface)
			if prev_h >= 0 and h > prev_h:
				total += (h - prev_h) * tuning.walk_climb_s_per_step
			prev_h = h
			ends.append(a + d * cuts[k])
			times.append(total)
	return total


## The shares along a line from `u0` to `u1` (one axis, in tiles) where it crosses a tile edge.
static func _edge_cuts(u0: float, u1: float, cuts: PackedFloat64Array) -> void:
	if u1 == u0:
		return
	var lo := mini(floori(u0), floori(u1)) + 1
	var hi := maxi(floori(u0), floori(u1))
	for k: int in range(lo, hi + 1):
		var c := (k - u0) / (u1 - u0)
		if c > 0.0 and c < 1.0:
			cuts.append(c)


func is_done() -> bool:
	return elapsed >= duration


## Where the guest stands now, yards.
func position() -> Vector2:
	return point_at_time(elapsed)


## E9-S2: the share of the walk's yards on cart path tiles (0 for a walk of no length).
func path_share() -> float:
	return path_yd / length if length > 0.0 else 0.0


## E9-S1: walks `seconds` further (never past the end). Returns where the guest stands.
func advance(seconds: float) -> Vector2:
	elapsed = minf(elapsed + maxf(seconds, 0.0), duration)
	return position()


## E9-S1: the point the walk reaches `t` seconds after it set off.
func point_at_time(t: float) -> Vector2:
	if _ends.is_empty() or t >= duration:
		return points[-1]
	if t <= 0.0:
		return points[0]
	var i := _times.bsearch(t)
	if i >= _ends.size():
		return points[-1]
	var t0 := 0.0 if i == 0 else _times[i - 1]
	var p0 := points[0] if i == 0 else _ends[i - 1]
	var span := _times[i] - t0
	return p0.lerp(_ends[i], (t - t0) / span) if span > 0.0 else _ends[i]


## The end of the walk, yards.
func end() -> Vector2:
	return points[-1]


static func _polyline_length(p: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, p.size()):
		total += p[i - 1].distance_to(p[i])
	return total


## from, the cart path's tile centres from the one nearest `from` to the one nearest `to`,
## then to; empty when no path serves both ends within the time bound.
##
## E3-S15, E9-S1: the search is bounded by `limit_s`, the straight walk's time. Every step
## between path tile centres is at least `ypt` yards walked on cart path (at its speed, climbs
## only adding), and the two legs (from to the first tile, the last tile to `to`) take at least
## their yards at the fastest walking speed, so a route of more steps than the time left allows
## would be slower than the straight walk and refused. So the search never goes deeper than
## that many steps, and never enters a tile from which `b` is further than the steps left
## (8-neighbour distance). It finds exactly the route the unbounded search finds whenever that
## route is taken, and none only when that route would have been refused: a disconnected end
## costs the tiles inside the bound, not its whole component.
static func _path_route(course: CourseData, from: Vector2, to: Vector2, tuning: GuestTuning,
		ypt: float, limit_s: float, cache: Cache = null) -> PackedVector2Array:
	var a := _nearest_path_tile(course, from, tuning.cart_path_reach_yd, ypt)
	if a.x < 0:
		return PackedVector2Array()
	var b := _nearest_path_tile(course, to, tuning.cart_path_reach_yd, ypt)
	if b.x < 0 or a == b:
		return PackedVector2Array()
	var legs := from.distance_to(_center(a, ypt)) + _center(b, ypt).distance_to(to)
	var path_speed := tuning.walk_speed(Surface.Type.CART_PATH)
	var hops := max_hops((limit_s - legs / tuning.walk_top_yd_per_s()) * path_speed, ypt)
	if hops < 1:
		return PackedVector2Array()
	var tiles := cached_search(course, a, b, hops, cache)
	if tiles.is_empty():
		return PackedVector2Array()
	var out := PackedVector2Array([from])
	for t: Vector2i in tiles:
		out.append(_center(t, ypt))
	out.append(to)
	return out


## The most steps a route of at most `yards` between its first and last path tile can take
## (each step at least `ypt`). Rounded up a hair, so float error never cuts a route.
static func max_hops(yards: float, ypt: float) -> int:
	return floori(yards / ypt + 1e-6)


## _search from `a` to `b` within `hops` steps, through `cache` when one is given: a route
## found is kept for any bound (a bound shorter than it refuses it by its length), and "none"
## only for bounds no deeper than the search that found none.
static func cached_search(course: CourseData, a: Vector2i, b: Vector2i, hops: int,
		cache: Cache = null) -> Array[Vector2i]:
	if cache == null:
		return _search(course, a, b, hops)
	cache.follow(course)
	var key := Vector4i(a.x, a.y, b.x, b.y)
	if cache.searches.has(key):
		var hit: Array = cache.searches[key]
		var found: Array[Vector2i] = hit[0]
		if not found.is_empty() or int(hit[1]) >= hops:
			return found
	if cache.grid.is_empty():
		cache.grid = path_grid(course)
	var tiles := _search(course, a, b, hops, cache.grid)
	cache.searches[key] = [tiles, hops]
	return tiles


## 1 per cart path tile, row-major over the map with a border of one 0 tile all round
## ((width + 2) x (height + 2)), so the search reads its neighbours with no bounds test.
static func path_grid(course: CourseData) -> PackedByteArray:
	var w := course.width + 2
	var grid := PackedByteArray()
	grid.resize(w * (course.height + 2))
	var surfaces := course.surface_grid()
	var path := Surface.Type.CART_PATH
	for y: int in course.height:
		var row := (y + 1) * w + 1
		var src := y * course.width
		for x: int in course.width:
			if surfaces[src + x] == path:
				grid[row + x] = 1
	# E14-S2 (D69): a bridge is a path tile.
	for b: Vector2i in course.bridge_cells():
		grid[(b.y + 1) * w + b.x + 1] = 1
	return grid


## The cart path tiles from `a` to `b`, both included, at most `hops` steps apart (below 0: no
## bound); empty when no path joins them within it. `grid` is path_grid(course), read afresh
## when not given.
static func _search(course: CourseData, a: Vector2i, b: Vector2i, hops: int = -1,
		grid: PackedByteArray = PackedByteArray()) -> Array[Vector2i]:
	# Breadth-first over cart path tiles, neighbours in a fixed order (the same route every run).
	# A tile is entered only if b is still in reach from it in the steps left: that never drops
	# a tile of the route found nor any tile that could be its parent, so the search finds the
	# same route as an unbounded one whenever that route has `hops` steps or fewer.
	# E3-S15: tiles by index into the bordered grid, in packed arrays (a Dictionary entry and a
	# CourseData read per tile cost about 4 us a tile on a dense lattice).
	if grid.is_empty():
		grid = path_grid(course)
	var w := course.width + 2
	var n_tiles := grid.size()
	var start := (a.y + 1) * w + a.x + 1
	var goal := (b.y + 1) * w + b.x + 1
	var offsets := PackedInt32Array()
	for d: Vector2i in NEIGHBOURS:
		offsets.append(d.y * w + d.x)
	var came := PackedInt32Array()  # parent index + 1; 0: not reached
	came.resize(n_tiles)
	var depth := PackedInt32Array()
	depth.resize(n_tiles)
	var queue := PackedInt32Array()
	queue.resize(n_tiles)
	came[start] = start + 1
	queue[0] = start
	var tail := 1
	var head := 0
	var bound := hops >= 0
	var bx: int = b.x + 1
	var by: int = b.y + 1
	while head < tail:
		var c: int = queue[head]
		head += 1
		if c == goal:
			break
		var dn: int = depth[c] + 1
		for off: int in offsets:
			var n: int = c + off
			if grid[n] == 0 or came[n] != 0:
				continue
			if bound and dn + maxi(absi(bx - n % w), absi(by - n / w)) > hops:
				continue
			came[n] = c + 1
			depth[n] = dn
			queue[tail] = n
			tail += 1
	if came[goal] == 0:
		return [] as Array[Vector2i]
	var tiles: Array[Vector2i] = [b]
	var i := goal
	while i != start:
		i = came[i] - 1
		tiles.append(Vector2i(i % w - 1, i / w - 1))
	tiles.reverse()
	return tiles


static func _center(t: Vector2i, ypt: float) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * ypt


## The cart path tile whose centre is nearest `at` within `reach` yards; (-1, -1) if none.
## Ties go to the first in row order.
static func _nearest_path_tile(course: CourseData, at: Vector2, reach: float,
		ypt: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var r := ceili(reach / ypt) + 1
	var c := Vector2i(floori(at.x / ypt), floori(at.y / ypt))
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var t := Vector2i(x, y)
			if not _is_path(course, t):
				continue
			var d := ((Vector2(t) + Vector2(0.5, 0.5)) * ypt).distance_to(at)
			if d <= reach and d < best_d:
				best_d = d
				best = t
	return best


static func _is_path(course: CourseData, t: Vector2i) -> bool:
	if not course.in_bounds(t.x, t.y):
		return false
	var s := course.get_surface(t.x, t.y)
	return s == Surface.Type.CART_PATH or (s == Surface.Type.WATER and course.is_bridge(t.x, t.y))


# --- E12-S1 (D68): why a walk takes no path, what a path edit reaches, a round's walks ---

## Why the walk from `from` to `to` (yards) on `course` follows no cart path (Reason): no path on
## the course; none within `cart_path_reach_yd` of either end; a path within reach of one end that
## comes no nearer the other than reach plus `gap_yd`; or one joining both ends but slower than
## walking across. Ask it of a walk that took no path (route's `on_path` false): it reads only
## the cart path tiles (path_grid), never the route's time, so `cache` keeps it as it keeps the
## search. The Build overlay and the walk complaint both call it.
static func why(course: CourseData, from: Vector2, to: Vector2, tuning: GuestTuning,
		ypt: float = 5.0, cache: Cache = null) -> Reason:
	var key := Vector4(from.x, from.y, to.x, to.y)
	var grid: PackedByteArray
	if cache != null:
		cache.follow(course)
		if cache.reasons.has(key):
			return cache.reasons[key]
		if cache.grid.is_empty():
			cache.grid = path_grid(course)
		grid = cache.grid
	else:
		grid = path_grid(course)
	var r := _why(course, grid, from, to, tuning.cart_path_reach_yd, ypt)
	if cache != null:
		cache.reasons[key] = r
	return r


static func _why(course: CourseData, grid: PackedByteArray, from: Vector2, to: Vector2,
		reach: float, ypt: float) -> Reason:
	var r := Reason.new()
	if grid.find(1) < 0:
		return r
	var a := _nearest_path_tile(course, from, reach, ypt)
	var b := _nearest_path_tile(course, to, reach, ypt)
	if a.x < 0 and b.x < 0:
		r.kind = Reason.Kind.NOT_NEAR
		r.at_start = true
		return r
	# The path piece within reach of one end: does it hold the other end's tile, and how near
	# does it come to the other end?
	var from_start := a.x >= 0
	var origin := a if from_start else b
	var goal := b if from_start else a
	var near := _piece_nearest(course, grid, origin, to if from_start else from, goal, ypt)
	if origin == goal or near.y > 0.0:
		r.kind = Reason.Kind.SLOWER
		return r
	r.kind = Reason.Kind.SHORT
	r.at_start = not from_start
	r.gap_yd = maxi(1, ceili(near.x - reach - 1e-6))
	r.near_tile = Vector2i(int(near.z), int(near.w))
	return r


## Over the path piece (8-connected cart path tiles) holding `origin`: x, the nearest a tile
## centre of it comes to `point`, yards; y, 1 when `goal` is on it, else 0; z and w, that
## nearest tile (the first in the search's order on a tie).
static func _piece_nearest(course: CourseData, grid: PackedByteArray, origin: Vector2i,
		point: Vector2, goal: Vector2i, ypt: float) -> Vector4:
	var w := course.width + 2
	var best := INF
	var best_t := origin
	var found := 0.0
	var goal_i := (goal.y + 1) * w + goal.x + 1 if goal.x >= 0 else -1
	for i: int in _piece(grid, w, [(origin.y + 1) * w + origin.x + 1]):
		if i == goal_i:
			found = 1.0
		var t := Vector2i(i % w - 1, i / w - 1)
		var d := _center(t, ypt).distance_to(point)
		if d < best:
			best = d
			best_t = t
	return Vector4(best, found, best_t.x, best_t.y)


## The bordered-grid indices (path_grid, rows `w` wide) of every cart path tile 8-connected to
## one of `seeds`, the seeds included.
static func _piece(grid: PackedByteArray, w: int, seeds: Array) -> PackedInt32Array:
	var offsets := PackedInt32Array()
	for d: Vector2i in NEIGHBOURS:
		offsets.append(d.y * w + d.x)
	var mark := PackedByteArray()
	mark.resize(grid.size())
	var queue := PackedInt32Array()
	for s: int in seeds:
		if grid[s] != 0 and mark[s] == 0:
			mark[s] = 1
			queue.append(s)
	var head := 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		for off: int in offsets:
			var n: int = c + off
			if grid[n] != 0 and mark[n] == 0:
				mark[n] = 1
				queue.append(n)
	return queue


## E12-S1 (D68): true when a change to or from cart path on one of `cells` can change the walk
## from `from` to `to` (yards): the cell lies within `cart_path_reach_yd` of either end, or it or
## one of its 8 neighbours is on a path piece (as the course is now) with a tile within reach of
## either end: path laid on, or taken off, a piece the walk could use (ReactionFeed.walks_edited).
static func path_edit_reaches(course: CourseData, from: Vector2, to: Vector2,
		cells: Array[Vector2i], tuning: GuestTuning, ypt: float = 5.0,
		grid: PackedByteArray = PackedByteArray()) -> bool:
	var reach := tuning.cart_path_reach_yd
	for cell: Vector2i in cells:
		var c := _center(cell, ypt)
		if c.distance_to(from) <= reach or c.distance_to(to) <= reach:
			return true
	if grid.is_empty():
		grid = path_grid(course)
	var w := course.width + 2
	var seeds: Array = []
	var r := ceili(reach / ypt) + 1
	for end: Vector2 in [from, to]:
		var at := Vector2i(floori(end.x / ypt), floori(end.y / ypt))
		for y in range(at.y - r, at.y + r + 1):
			for x in range(at.x - r, at.x + r + 1):
				var t := Vector2i(x, y)
				if _is_path(course, t) and _center(t, ypt).distance_to(end) <= reach:
					seeds.append((y + 1) * w + x + 1)
	if seeds.is_empty():
		return false
	var mark := {}
	for i: int in _piece(grid, w, seeds):
		mark[i] = true
	for cell: Vector2i in cells:
		var i := (cell.y + 1) * w + cell.x + 1
		if mark.has(i):
			return true
		for d: Vector2i in NEIGHBOURS:
			if mark.has(i + d.y * w + d.x):
				return true
	return false


## E12-S1 (D68): the walks of a round the Walk check judges, as GuestBrain walks them: the
## clubhouse door to the first open hole's tee (with a clubhouse), then each open hole's cup to
## the next open hole's tee, holes by number (the first hole with a number stands for it, as
## GuestBrain.hole_numbered reads it). Each: {from, to (yards, tile centres), from_hole (0 for
## the clubhouse), to_hole, to_slot (its slot in CourseData.holes)}.
static func round_walks(course: CourseData, ypt: float = 5.0) -> Array[Dictionary]:
	var first := {}
	for i: int in course.holes.size():
		var h: HoleData = course.holes[i]
		if not first.has(h.number):
			first[h.number] = i
	var numbers: Array = first.keys()
	numbers.sort()
	var out: Array[Dictionary] = []
	var has_prev := course.has_clubhouse()
	var prev := _center(course.clubhouse_door(), ypt) if has_prev else Vector2.ZERO
	var prev_number := 0
	for n: int in numbers:
		var slot: int = first[n]
		var h: HoleData = course.holes[slot]
		if not h.open:
			continue
		if has_prev:
			out.append({"from": prev, "to": _center(h.tee, ypt), "from_hole": prev_number,
					"to_hole": n, "to_slot": slot})
		prev = _center(h.cup, ypt)
		prev_number = n
		has_prev = true
	return out


# --- E14-S2 (D69): the quickest dry route ---

## The dry search's heuristic is the straight yards at the base walking speed divided by this
## (a weighted A*): measured on 200 searched walks across the playtest nine (E14-S2), 1.3 halves
## the search (median 2.0 to 1.0 ms, worst 8.4 to 5.8) for walks 0.45% slower in all. Not a
## tunable: it changes how fast a route is found, and its routes only within that.
const DRY_GUIDE_WEIGHT: float = 1.3
## How far ahead (route points) the straightening looks for a dry shortcut.
const STRAIGHTEN_LOOK: int = 16
## A segment that passes this close (tiles) to an open water tile counts as touching it.
const WET_MARGIN: float = 0.02
const _ROOT2: float = 1.4142135623730951


## True when tile (x, y) can be walked: on the map, and not water unless bridged.
static func walkable(course: CourseData, x: int, y: int) -> bool:
	if not course.in_bounds(x, y):
		return false
	return course.get_surface(x, y) != Surface.Type.WATER or course.is_bridge(x, y)


## E14-S2: what the dry search reads of a course, read once while its tiles and bridges stand
## (Cache.dry_grid): each tile's seconds a yard (0 for open water and off the map, a bridge at
## cart path's) and height, in a grid bordered by one blocked tile all round, so the search reads
## a neighbour with no bounds test; and the heuristic's speed.
class DryGrid:
	extends RefCounted
	## Bordered row width (course width + 2).
	var stride: int = 0
	var pace := PackedFloat64Array()
	var height := PackedByteArray()
	## The speed the search's heuristic assumes, yards a second (the base over DRY_GUIDE_WEIGHT).
	var guide_speed: float = 0.0

	func _init(course: CourseData, tuning: GuestTuning) -> void:
		stride = course.width + 2
		var n: int = stride * (course.height + 2)
		pace.resize(n)
		height.resize(n)
		var by_surface := PackedFloat64Array()
		by_surface.resize(16)
		for s: int in Surface.COUNT:
			by_surface[s] = 1.0 / tuning.walk_speed(s)
		by_surface[Surface.Type.WATER] = 0.0
		var tiles: PackedByteArray = course.packed_tiles()
		var w: int = course.width
		for y: int in course.height:
			var row: int = (y + 1) * stride + 1
			var src: int = y * w
			for x: int in w:
				var t: int = tiles[src + x]
				pace[row + x] = by_surface[t & 0x0F]
				height[row + x] = t >> 4
		var path_pace: float = 1.0 / tuning.walk_speed(Surface.Type.CART_PATH)
		for b: Vector2i in course.bridge_cells():
			pace[(b.y + 1) * stride + b.x + 1] = path_pace
		guide_speed = tuning.walk_yd_per_s / DRY_GUIDE_WEIGHT


## The quickest dry route from `from` to `to` (yards) as points: `from`, the centre of its tile,
## the centres of the tiles between, the centre of the end tile, `to`, then straightened. A*
## over the tiles (`grid`, DryGrid): 8 neighbours in NEIGHBOURS' order, a diagonal step only where
## both tiles beside it are walkable, each step half its yards at each tile's speed (a bridge at
## path's) plus the climb onto the higher tile, as time_pieces times a walk; the heuristic is the
## straight yards at the base walking speed over DRY_GUIDE_WEIGHT, so the route is within a hair
## of the quickest (the search stays a few hundred tiles, not the map); ties go to the tile
## reached first, so the route is the same every run. When `to`'s tile cannot be reached the route ends at the centre of the reachable
## tile nearest `to` (ties: the first closed). A start on open water (none in play) walks off it.
static func _dry_route(course: CourseData, from: Vector2, to: Vector2, tuning: GuestTuning,
		ypt: float, grid: DryGrid) -> PackedVector2Array:
	var w: int = course.width
	var hgt: int = course.height
	var sw: int = grid.stride
	var a := Vector2i(clampi(floori(from.x / ypt), 0, w - 1), clampi(floori(from.y / ypt), 0, hgt - 1))
	var b := Vector2i(clampi(floori(to.x / ypt), 0, w - 1), clampi(floori(to.y / ypt), 0, hgt - 1))
	var pace: PackedFloat64Array = grid.pace
	var heights: PackedByteArray = grid.height
	var climb: float = tuning.walk_climb_s_per_step
	var h_scale: float = ypt / grid.guide_speed
	var diag: float = ypt * _ROOT2
	var n_tiles: int = pace.size()
	var g := PackedFloat64Array()
	g.resize(n_tiles)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n_tiles)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n_tiles)
	var hf := PackedFloat64Array()
	var hs := PackedInt32Array()
	var ht := PackedInt32Array()
	var seq: int = 0
	var start: int = (a.y + 1) * sw + a.x + 1
	var goal: int = (b.y + 1) * sw + b.x + 1
	var bx: int = b.x + 1
	var by: int = b.y + 1
	g[start] = 0.0
	_push(hf, hs, ht, Vector2(a).distance_to(Vector2(b)) * h_scale, seq, start)
	seq += 1
	var best: int = start
	var best_d: int = 1 << 30
	var reached: bool = false
	var offs := PackedInt32Array()
	for d: Vector2i in NEIGHBOURS:
		offs.append(d.y * sw + d.x)
	var start_pace: float = pace[start] if pace[start] > 0.0 else 1.0 / tuning.walk_yd_per_s
	while not hf.is_empty():
		var c: int = _pop(hf, hs, ht)
		if closed[c] != 0:
			continue
		closed[c] = 1
		@warning_ignore("integer_division")
		var cy: int = c / sw
		var cx: int = c - cy * sw
		var dd: int = (cx - bx) * (cx - bx) + (cy - by) * (cy - by)
		if dd < best_d:
			best_d = dd
			best = c
		if c == goal:
			reached = true
			break
		var cpace: float = pace[c] if c != start else start_pace
		var ch: int = heights[c]
		var gc: float = g[c]
		for k: int in 8:
			var n: int = c + offs[k]
			var npace: float = pace[n]
			if npace == 0.0 or closed[n] != 0:
				continue
			var step: float = ypt
			if k >= 4:
				# A diagonal only past two walkable tiles: NEIGHBOURS[k] = (dx, dy).
				var dx: int = NEIGHBOURS[k].x
				if pace[c + dx] == 0.0 or pace[n - dx] == 0.0:
					continue
				step = diag
			var cost: float = 0.5 * step * (cpace + npace)
			var nh: int = heights[n]
			if nh > ch:
				cost += (nh - ch) * climb
			var gn: float = gc + cost
			if gn < g[n]:
				g[n] = gn
				came[n] = c
				@warning_ignore("integer_division")
				var ny: int = n / sw
				var nx: int = n - ny * sw
				_push(hf, hs, ht, gn + sqrt(float((nx - bx) * (nx - bx) + (ny - by) * (ny - by))) * h_scale, seq, n)
				seq += 1
	var end: int = goal if reached else best
	var chain := PackedInt32Array()
	var i: int = end
	while i != -1:
		chain.append(i)
		if i == start:
			break
		i = came[i]
	chain.reverse()
	var pts := PackedVector2Array([from])
	for t: int in chain:
		@warning_ignore("integer_division")
		var ty: int = t / sw
		pts.append((Vector2(t - ty * sw - 1, ty - 1) + Vector2(0.5, 0.5)) * ypt)
	if reached:
		pts.append(to)
	# The time to each point: the legs inside the end tiles timed as a walk, the tiles between by
	# the search's own sums.
	var cum := PackedFloat64Array([0.0])
	var ends := PackedVector2Array()
	var times := PackedFloat64Array()
	var lead: float = time_pieces(course, PackedVector2Array([pts[0], pts[1]]), tuning, ypt, ends, times)
	for t: int in chain:
		cum.append(lead + g[t])
	if reached:
		ends.clear()
		times.clear()
		cum.append(cum[-1] + time_pieces(course, PackedVector2Array([pts[-2], pts[-1]]), tuning, ypt,
				ends, times))
	return _straighten(course, pts, tuning, ypt, grid, cum)


## `pts` with corners taken out where the straight line between two kept points is dry
## (_segment_dry) and walks no slower than the points between (time_pieces), looking at most
## STRAIGHTEN_LOOK points ahead, farthest first.
## `cum`, when given, is the time to each point along `pts`; else it is measured (time_pieces).
## From each kept point the farthest dry line within the look is found (the look's end, else by
## halving), then the farthest point up to it whose line is no slower is kept.
static func _straighten(course: CourseData, pts: PackedVector2Array, tuning: GuestTuning,
		ypt: float, grid: DryGrid = null, cum: PackedFloat64Array = PackedFloat64Array()) -> PackedVector2Array:
	if pts.size() <= 2:
		return pts
	var ends := PackedVector2Array()
	var times := PackedFloat64Array()
	if cum.size() != pts.size():
		cum = PackedFloat64Array([0.0])
		for k: int in range(1, pts.size()):
			ends.clear()
			times.clear()
			cum.append(cum[k - 1] + time_pieces(course, PackedVector2Array([pts[k - 1], pts[k]]), tuning,
					ypt, ends, times))
	var out := PackedVector2Array([pts[0]])
	var i: int = 0
	var last: int = pts.size() - 1
	while i < last:
		# The farthest dry line within the look: the look's end, else halved down to one.
		var far: int = mini(last, i + STRAIGHTEN_LOOK)
		if not _segment_dry(course, pts[i], pts[far], ypt, grid):
			var lo: int = i + 1
			while far - lo > 1:
				@warning_ignore("integer_division")
				var mid: int = (lo + far) / 2
				if _segment_dry(course, pts[i], pts[mid], ypt, grid):
					lo = mid
				else:
					far = mid
			far = lo
		var next: int = i + 1
		for j: int in range(far, i + 1, -1):
			ends.clear()
			times.clear()
			var t: float = time_pieces(course, PackedVector2Array([pts[i], pts[j]]), tuning, ypt, ends, times)
			if t <= cum[j] - cum[i] + 1e-9:
				next = j
				break
		out.append(pts[next])
		i = next
	return out


## True when the segment from `a` to `b` (yards) touches no open water tile, passes no closer
## than WET_MARGIN to one, and stays on the map.
static func _segment_dry(course: CourseData, a: Vector2, b: Vector2, ypt: float,
		grid: DryGrid = null) -> bool:
	var p := a / ypt
	var q := b / ypt
	var m: float = WET_MARGIN
	var x0: int = floori(minf(p.x, q.x) - m)
	var x1: int = floori(maxf(p.x, q.x) + m)
	var dx: float = q.x - p.x
	for x: int in range(x0, x1 + 1):
		# The part of the segment over column x (widened by the margin), and its y span.
		var t0: float = 0.0
		var t1: float = 1.0
		if absf(dx) > 1e-12:
			var ta: float = (float(x) - m - p.x) / dx
			var tb: float = (float(x + 1) + m - p.x) / dx
			t0 = maxf(0.0, minf(ta, tb))
			t1 = minf(1.0, maxf(ta, tb))
			if t0 > t1:
				continue
		var ya: float = p.y + (q.y - p.y) * t0
		var yb: float = p.y + (q.y - p.y) * t1
		for y: int in range(floori(minf(ya, yb) - m), floori(maxf(ya, yb) + m) + 1):
			if grid != null:
				if x < 0 or y < 0 or x >= course.width or y >= course.height \
						or grid.pace[(y + 1) * grid.stride + x + 1] == 0.0:
					return false
			elif not walkable(course, x, y):
				return false
	return true


static func _push(hf: PackedFloat64Array, hs: PackedInt32Array, ht: PackedInt32Array, f: float,
		sq: int, t: int) -> void:
	hf.append(f)
	hs.append(sq)
	ht.append(t)
	var i: int = hf.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var parent: int = (i - 1) / 2
		if hf[parent] < f or (hf[parent] == f and hs[parent] < sq):
			break
		hf[i] = hf[parent]
		hs[i] = hs[parent]
		ht[i] = ht[parent]
		i = parent
	hf[i] = f
	hs[i] = sq
	ht[i] = t


static func _pop(hf: PackedFloat64Array, hs: PackedInt32Array, ht: PackedInt32Array) -> int:
	var top: int = ht[0]
	var last: int = hf.size() - 1
	var f: float = hf[last]
	var sq: int = hs[last]
	var t: int = ht[last]
	hf.resize(last)
	hs.resize(last)
	ht.resize(last)
	if last == 0:
		return top
	var i: int = 0
	while true:
		var l: int = 2 * i + 1
		if l >= last:
			break
		var c: int = l
		var r: int = l + 1
		if r < last and (hf[r] < hf[l] or (hf[r] == hf[l] and hs[r] < hs[l])):
			c = r
		if f < hf[c] or (f == hf[c] and sq < hs[c]):
			break
		hf[i] = hf[c]
		hs[i] = hs[c]
		ht[i] = ht[c]
		i = c
	hf[i] = f
	hs[i] = sq
	ht[i] = t
	return top
