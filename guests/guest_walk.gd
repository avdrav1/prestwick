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

## The route's corners, yards: the start first, the end last.
var points: PackedVector2Array = PackedVector2Array()
## The route's length, yards.
var length: float = 0.0
## True when the route follows a cart path.
var on_path: bool = false
## Yards walked so far.
var walked: float = 0.0


## The walk from `from` to `to` (yards) on `course`. `cache` ({Vector4i(start tile, end
## tile): the path tiles between, empty for none}) shares the cart path search between walks
## while the course stands unchanged; the caller drops it when the course may have changed.
static func route(course: CourseData, from: Vector2, to: Vector2, tuning: GuestTuning,
		yards_per_tile: float = 5.0, cache: Variant = null) -> GuestWalk:
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
## then to; empty when no path serves both ends.
static func _path_route(course: CourseData, from: Vector2, to: Vector2, tuning: GuestTuning,
		ypt: float, cache: Variant = null) -> PackedVector2Array:
	var a := _nearest_path_tile(course, from, tuning.cart_path_reach_yd, ypt)
	if a.x < 0:
		return PackedVector2Array()
	var b := _nearest_path_tile(course, to, tuning.cart_path_reach_yd, ypt)
	if b.x < 0 or a == b:
		return PackedVector2Array()
	var key := Vector4i(a.x, a.y, b.x, b.y)
	var tiles: Array[Vector2i] = []
	if cache is Dictionary and (cache as Dictionary).has(key):
		tiles = (cache as Dictionary)[key]
	else:
		tiles = _search(course, a, b)
		if cache is Dictionary:
			(cache as Dictionary)[key] = tiles
	if tiles.is_empty():
		return PackedVector2Array()
	var out := PackedVector2Array([from])
	for t: Vector2i in tiles:
		out.append((Vector2(t) + Vector2(0.5, 0.5)) * ypt)
	out.append(to)
	return out


## The cart path tiles from `a` to `b`, both included; empty when no path joins them.
static func _search(course: CourseData, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	# Breadth-first over cart path tiles, neighbours in a fixed order (the same route every run).
	var came := {a: a}
	var queue: Array[Vector2i] = [a]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == b:
			break
		for d: Vector2i in NEIGHBOURS:
			var n := c + d
			if came.has(n) or not _is_path(course, n):
				continue
			came[n] = c
			queue.append(n)
	if not came.has(b):
		return [] as Array[Vector2i]
	var tiles: Array[Vector2i] = [b]
	while tiles[-1] != a:
		tiles.append(came[tiles[-1]])
	tiles.reverse()
	return tiles


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
