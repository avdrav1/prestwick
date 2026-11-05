class_name GuestWalk
extends RefCounted
## One walk of a guest (E3-S4, docs/design.md Guests and reactions, Walking): a polyline in
## yards from where it stands to where it is going, walked `walk_yd_per_s` a simulated second.
##
## A straight line, unless a cart path serves the walk: a cart path tile within
## `cart_path_reach_yd` of the start and one within that of the end, joined through cart path
## tiles (8-connected, so a diagonal painted line holds), with the whole route (start, the
## path's tile centres, end) at most `cart_path_max_detour` times the straight line. Then the
## guest walks the path. No other pathfinding: a guest walks over any tile, water, trees and
## unowned land included (E3-S1, unowned land is out of bounds for the ball, not a wall).
##
## Reads CourseData only. The route is fixed when the walk starts; a path painted mid-walk is
## used from the next walk.

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## Cart path searches kept for one course while its tiles stand unchanged (E3-S15). A walk
## passed a Cache reads CourseData.revision first and drops what it holds when the course was
## written since (any tile or parcel write), so a kept route is always the one a fresh search
## would find. GuestBrain holds one for the whole day.
class Cache:
	extends RefCounted
	## CourseData.revision the searches and the grid stand for.
	var revision: int = -1
	## {Vector4i(start tile, end tile): [tiles between, empty for none; steps searched]}.
	var searches: Dictionary = {}
	## path_grid of that course (empty until a search needs it).
	var grid := PackedByteArray()

	## Searches kept.
	func size() -> int:
		return searches.size()

	## Drops everything if `course` was written since it was filled.
	func follow(course: CourseData) -> void:
		if course.revision != revision:
			searches.clear()
			grid = PackedByteArray()
			revision = course.revision


## The route's corners, yards: the start first, the end last.
var points: PackedVector2Array = PackedVector2Array()
## The route's length, yards.
var length: float = 0.0
## True when the route follows a cart path.
var on_path: bool = false
## Yards walked so far.
var walked: float = 0.0


## The walk from `from` to `to` (yards) on `course`. `cache` shares the cart path search (and
## the path grid it reads) between walks while the course stands unchanged (Cache.follow).
static func route(course: CourseData, from: Vector2, to: Vector2, tuning: GuestTuning,
		yards_per_tile: float = 5.0, cache: Cache = null) -> GuestWalk:
	var w := GuestWalk.new()
	var straight := from.distance_to(to)
	var path := _path_route(course, from, to, tuning, yards_per_tile, cache)
	if path.size() > 2 and _polyline_length(path) <= straight * tuning.cart_path_max_detour:
		w.points = path
		w.on_path = true
	else:
		w.points = PackedVector2Array([from, to])
	w.length = _polyline_length(w.points)
	return w


func is_done() -> bool:
	return walked >= length


## Where the guest stands now, yards.
func position() -> Vector2:
	return point_at(walked)


## Walks `yards` further (never past the end). Returns where the guest stands.
func move(yards: float) -> Vector2:
	walked = minf(walked + maxf(yards, 0.0), length)
	return position()


## The point `d` yards along the route.
func point_at(d: float) -> Vector2:
	var left := clampf(d, 0.0, length)
	for i in range(1, points.size()):
		var seg := points[i - 1].distance_to(points[i])
		if left <= seg:
			return points[i - 1].lerp(points[i], left / seg) if seg > 0.0 else points[i]
		left -= seg
	return points[-1]


## The end of the walk, yards.
func end() -> Vector2:
	return points[-1]


static func _polyline_length(p: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, p.size()):
		total += p[i - 1].distance_to(p[i])
	return total


## from, the cart path's tile centres from the one nearest `from` to the one nearest `to`,
## then to; empty when no path serves both ends within the detour bound.
##
## E3-S15: the search is bounded by the detour. Every step between tile centres is at least
## `ypt` yards, so a route of h steps is at least the two legs (from to the first tile, the last
## tile to `to`) plus h * ypt; past `cart_path_max_detour` times the straight line it would be
## refused. So the search never goes deeper than that many steps, and never enters a tile from
## which `b` is further than the steps left (8-neighbour distance). It finds exactly the route
## the unbounded search finds whenever that route is taken, and none only when that route
## would have been refused: a disconnected end costs the tiles inside the bound, not its whole
## component.
static func _path_route(course: CourseData, from: Vector2, to: Vector2, tuning: GuestTuning,
		ypt: float, cache: Cache = null) -> PackedVector2Array:
	var a := _nearest_path_tile(course, from, tuning.cart_path_reach_yd, ypt)
	if a.x < 0:
		return PackedVector2Array()
	var b := _nearest_path_tile(course, to, tuning.cart_path_reach_yd, ypt)
	if b.x < 0 or a == b:
		return PackedVector2Array()
	var legs := from.distance_to(_center(a, ypt)) + _center(b, ypt).distance_to(to)
	var hops := max_hops(from.distance_to(to) * tuning.cart_path_max_detour - legs, ypt)
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
