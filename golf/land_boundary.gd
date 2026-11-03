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
## issue-marker rule, E2-S17).

## Step along the view line, in tile units of (i + j), when testing whether an edge is covered.
const COVER_STEP: float = 0.125


## The land line as pairs of Iso points (x, y in tiles, integer = tile centre; z in height
## steps): points 2k and 2k + 1 are the ends of one tile edge, at the higher top of the two
## tiles either side, so the line sits on the lip of any step between them. Iso.point_to_screen
## takes each point. Order: parcels row-major, then east, south, west, north, then along the edge.
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
		var h := float(maxi(course.get_height(x, y), course.get_height(x + dir, y)))
		out.append(Vector3(ex, y - 0.5, h))
		out.append(Vector3(ex, y + 0.5, h))


## The edges between owned row `y` and row `y + dir`, columns x0 to x1 - 1.
static func _edge_along_x(course: CourseData, out: PackedVector3Array, y: int, dir: int,
		x0: int, x1: int) -> void:
	var ey := y + 0.5 * dir
	for x in range(x0, x1):
		var h := float(maxi(course.get_height(x, y), course.get_height(x, y + dir)))
		out.append(Vector3(x - 0.5, ey, h))
		out.append(Vector3(x + 0.5, ey, h))


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


## True when a tile nearer the camera stands high enough to hide the middle of the edge
## `a`-`b` (two points of segments): its column, from height 0 to its top, crosses the line
## of sight from the camera to that point. Along that line, the point at depth t (i + j) is
## at height z = t - (i + j of the edge) + the edge's height, so it walks t forward from the
## edge until z passes CourseData.MAX_HEIGHT.
static func covered(course: CourseData, a: Vector3, b: Vector3) -> bool:
	var m := (a + b) * 0.5
	var d := m.x - m.y
	var t0 := m.x + m.y
	var z := m.z + COVER_STEP
	while z <= CourseData.MAX_HEIGHT:
		var t := t0 + z - m.z
		var tile := Vector2i(floori((t + d) * 0.5 + 0.5), floori((t - d) * 0.5 + 0.5))
		if course.in_bounds(tile.x, tile.y) and course.get_height(tile.x, tile.y) >= z:
			return true
		z += COVER_STEP
	return false
