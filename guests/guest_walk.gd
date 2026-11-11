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
## walk. No other pathfinding: a guest walks over any tile, water, trees and unowned land
## included (E3-S1, unowned land is out of bounds for the ball, not a wall), only slower.
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

	## Searches kept.
	func size() -> int:
		return searches.size()

	## Drops everything if `course` is another course, or a tile of it turned to or from cart
	## path, since it was filled.
	func follow(course: CourseData) -> void:
		var k := key(course)
		if k != revision:
			searches.clear()
			grid = PackedByteArray()
			revision = k

	## What the path search reads of `course`, as one key: the course and its cart path writes.
	static func key(course: CourseData) -> String:
		return "%d:%d" % [course.get_instance_id(), course.surface_revision(Surface.Type.CART_PATH)]


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
## E9-S2: the yards of the walk on cart path tiles (the Walk check asks whether it followed a
## path: GuestTuning.walk_path_share of its length), and the straight walk's time were no cart
## path laid (its path tiles walked at the base speed): whether a path made the walk quick.
var path_yd: float = 0.0
var bare_s: float = 0.0
## Simulated seconds walked so far.
var elapsed: float = 0.0
## E9-S1: the walk cut where it crosses a tile edge (time_pieces): each piece's end, yards, and
## the walk's time at that end, so a guest's position is by time.
var _ends: PackedVector2Array = PackedVector2Array()
var _times: PackedFloat64Array = PackedFloat64Array()


## The walk from `from` to `to` (yards) on `course`. `cache` shares the cart path search (and
## the path grid it reads) between walks while the course's cart path stands unchanged
## (Cache.follow). E9-S1: the path's route is taken only when quicker than the straight walk.
static func route(course: CourseData, from: Vector2, to: Vector2, tuning: GuestTuning,
		yards_per_tile: float = 5.0, cache: Cache = null) -> GuestWalk:
	var w := GuestWalk.new()
	w.points = PackedVector2Array([from, to])
	var on := PackedFloat64Array([0.0, 0.0])
	w.straight_s = time_pieces(course, w.points, tuning, yards_per_tile, w._ends, w._times, on)
	w.duration = w.straight_s
	w.path_yd = on[0]
	w.bare_s = w.straight_s - on[1] + on[0] / tuning.walk_yd_per_s
	var path := _path_route(course, from, to, tuning, yards_per_tile, w.straight_s, cache)
	if path.size() > 2:
		var ends := PackedVector2Array()
		var times := PackedFloat64Array()
		var path_on := PackedFloat64Array([0.0, 0.0])
		var t := time_pieces(course, path, tuning, yards_per_tile, ends, times, path_on)
		if t < w.straight_s:
			w.points = path
			w.on_path = true
			w.duration = t
			w._ends = ends
			w._times = times
			w.path_yd = path_on[0]
	w.length = _polyline_length(w.points)
	return w


## E9-S1 (D65): the time, simulated seconds, to walk the polyline `poly` (yards) on `course`:
## each piece between tile edges at its tile's walking speed (GuestTuning.walk_speed), and
## `walk_climb_s_per_step` for each step up from one tile to the next. Appends each piece's end
## to `ends` and the time there to `times` (a piece shorter than a thousandth of a yard, where
## the line grazes a tile's corner, is left out, so its tile neither slows nor lifts the walk).
## Off the map a tile walks as rough at the last height. E9-S2: `path_yd`, when given, gets the
## yards walked on cart path tiles added to its first value and, when it has a second, their
## time (climbs left out) to that.
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
	return course.in_bounds(t.x, t.y) and course.get_surface(t.x, t.y) == Surface.Type.CART_PATH
