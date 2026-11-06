class_name LandBoundary
extends RefCounted
## The land line (D29, E6-S7): every tile edge between an owned tile and an unowned one on
## the map, where a ball crossing onto the unowned side is OB. AimView draws it in Play so
## the player reads it before the shot (pillar 2). A reader only: it never writes CourseData.
##
## The edges lie along parcel edges (D26), so it walks each owned parcel's four sides
## against its edge neighbours, not every tile: at most 64 parcels x 4 sides x 16 tiles on
## the 128 x 128 map. The map's own edge is not a land line (off the map is OB anyway, and
## a fully owned course, New sandbox, has no line at all). A parcel touching only at a
## corner shares no edge.
##
## For drawing (E6-S7 review): unowned_side says which side of an edge is out of bounds, so
## the line can mark it, and covered says whether terrain in front of an edge hides it, so a
## line behind a hill draws faded and does not read as running over the hill's top (the
## issue-marker rule, E2-S17). Since E3-S59 (D50) the line lies on the drawn ground
## (TerrainMesh.ground_in) and covered reads the drawn ground (TilePicker.hidden).


## The land line as pairs of Iso points (x, y in tiles, integer = tile centre; z in height
## steps): points 2k and 2k + 1 are the ends of one half of a tile edge (corner to middle, middle
## to corner: the drawn ground bends where the edge crosses the tiles' centre line), each on the
## drawn ground, the higher of the two tiles' sides where they differ (a water bank), so the
## line lies on the ground and on the lip of a bank. Iso.point_to_screen takes each point.
## Order: parcels row-major, then east, south, west, north, then along the edge.
static func segments(course: CourseData) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q: int in course.parcels_high:
		for p: int in course.parcels_wide:
			var parcel := Vector2i(p, q)
			if not course.is_parcel_owned(parcel):
				continue
			var r := course.parcel_rect(parcel)
			if _unowned(course, parcel + Vector2i(1, 0)):
				_edge_along_y(course, out, r.end.x - 1, 1, r.position.y, r.end.y)
			if _unowned(course, parcel + Vector2i(0, 1)):
				_edge_along_x(course, out, r.end.y - 1, 1, r.position.x, r.end.x)
			if _unowned(course, parcel + Vector2i(-1, 0)):
				_edge_along_y(course, out, r.position.x, -1, r.position.y, r.end.y)
			if _unowned(course, parcel + Vector2i(0, -1)):
				_edge_along_x(course, out, r.position.y, -1, r.position.x, r.end.x)
	return out


## A parcel on the map that is not owned.
static func _unowned(course: CourseData, p: Vector2i) -> bool:
	return course.parcel_in_bounds(p) and not course.is_parcel_owned(p)


## The edges between owned column `x` and column `x + dir`, rows y0 to y1 - 1.
static func _edge_along_y(course: CourseData, out: PackedVector3Array, x: int, dir: int,
		y0: int, y1: int) -> void:
	var ex := x + 0.5 * dir
	for y in range(y0, y1):
		for half: float in [-0.5, 0.0]:
			out.append(_on_edge(course, Vector2i(x, y), Vector2i(x + dir, y), Vector2(ex, y + half)))
			out.append(_on_edge(course, Vector2i(x, y), Vector2i(x + dir, y), Vector2(ex, y + half + 0.5)))


## The edges between owned row `y` and row `y + dir`, columns x0 to x1 - 1.
static func _edge_along_x(course: CourseData, out: PackedVector3Array, y: int, dir: int,
		x0: int, x1: int) -> void:
	var ey := y + 0.5 * dir
	for x in range(x0, x1):
		for half: float in [-0.5, 0.0]:
			out.append(_on_edge(course, Vector2i(x, y), Vector2i(x, y + dir), Vector2(x + half, ey)))
			out.append(_on_edge(course, Vector2i(x, y), Vector2i(x, y + dir), Vector2(x + half + 0.5, ey)))


## The point `t` on the edge between tiles `a` and `b`, on the higher of their drawn grounds.
static func _on_edge(course: CourseData, a: Vector2i, b: Vector2i, t: Vector2) -> Vector3:
	var h := TerrainMesh.ground_in(course, a, t)
	if course.in_bounds(b.x, b.y):
		h = maxf(h, TerrainMesh.ground_in(course, b, t))
	return Vector3(t.x, t.y, h)


## Unit direction, in tiles (x, y), from the middle of the edge `a`-`b` (two points of
## segments) toward its unowned side.
static func unowned_side(course: CourseData, a: Vector3, b: Vector3) -> Vector2:
	var along := Vector2(b.x - a.x, b.y - a.y).normalized()
	var n := Vector2(along.y, -along.x)
	var m := Vector2(a.x + b.x, a.y + b.y) * 0.5
	var probe := m + n * 0.5
	if course.is_owned(roundi(probe.x), roundi(probe.y)):
		return -n
	return n


## True when ground nearer the camera hides the middle of the segment `a`-`b` (two points of
## segments): the drawn ground in front covers its screen point (TilePicker.hidden).
static func covered(course: CourseData, a: Vector3, b: Vector3) -> bool:
	return TilePicker.hidden(course, (a + b) * 0.5)
