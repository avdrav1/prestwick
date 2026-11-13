class_name FixtureBridges
extends RefCounted
## E14-S3 (D69): lays the example courses' footbridges. A bridge is cart path painted on water
## (CourseBuilder.paint builds one there and leaves the tile water); these paint only the water
## tiles of a 4-connected walk along a polyline of tile points, so the banks keep their surface
## (no cart path on a fairway) and every bridge tile meets the next through an edge, which a
## guest can walk (a diagonal step past open water is never walked).


## The tiles of a 4-connected walk from tile `a` to tile `b`, both included: each step along x
## or y, whichever keeps nearer the straight line (as CourseValidator walks rule 3's line).
static func line_tiles(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var line := Vector2(b - a)
	var p: Vector2i = a
	while p != b:
		var sx: int = signi(b.x - p.x)
		var sy: int = signi(b.y - p.y)
		if sx == 0:
			p.y += sy
		elif sy == 0:
			p.x += sx
		else:
			var px := Vector2(p + Vector2i(sx, 0) - a)
			var py := Vector2(p + Vector2i(0, sy) - a)
			p = p + (Vector2i(sx, 0) if absf(line.cross(px)) <= absf(line.cross(py)) else Vector2i(0, sy))
		out.append(p)
	return out


## Paints cart path on every water tile of the 4-connected walk along `poly` (tile points,
## rounded), as one stroke: a bridge on each. Returns the bridge tiles laid.
static func lay(b: CourseBuilder, poly: Array) -> int:
	var c: CourseData = b.course
	var before: int = c.bridge_cells().size()
	b.begin_stroke()
	for i: int in range(1, poly.size()):
		var from := Vector2i((poly[i - 1] as Vector2).round())
		var to := Vector2i((poly[i] as Vector2).round())
		for t: Vector2i in line_tiles(from, to):
			if c.in_bounds(t.x, t.y) and c.get_surface(t.x, t.y) == Surface.Type.WATER:
				b.paint(t, Surface.Type.CART_PATH, 1)
	b.end_stroke()
	return c.bridge_cells().size() - before
