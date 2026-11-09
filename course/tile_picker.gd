class_name TilePicker
extends RefCounted
## Screen-to-tile picking on the drawn ground: which tile the player sees under the cursor.
## A reader only. Uses the one projection in course/iso.gd.
##
## The ground is drawn as a smooth surface (E3-S58, D50), and the pick reads exactly what is
## drawn: each tile's own ground (TerrainMesh.ground_in: the mesh's triangles over the bilinear
## ground, water flat at its level) and the vertical faces where two tiles' ground does not meet
## (a water bank, the map's two front edges). A screen point is a ray: rising one step moves a
## point's tile coordinates by (+0.5, +0.5) at the same screen point, and the camera sees from
## +x +y, so the ray's highest point is nearest the camera. The pick walks the ray down from
## above the highest ground, from one mesh grid line to the next (tile edges among them): the
## ray runs along the grid squares' diagonals, so between two lines it stays over one flat
## triangle and meets it at most once, exactly. It takes the first point at or under the ground
## of the tile it is over: the frontmost drawn ground there. Coming over a tile's edge already
## under its ground is a hit on that tile's face (a water bank, the map's side) or edge. A tile
## partly hidden behind a nearer hill is picked only where its ground still shows.

## Returned when no tile of the course is under the point.
const NONE: Vector2i = Vector2i(-1, -1)
## How much nearer the camera (in i + j, which along a ray is height) a drawn point must be to
## hide another (hidden).
const HIDE_EPS: float = 0.02

## TerrainTuning's default, read once (E3-S74: `load` on every cast cost about 0.08 ms, a
## third of an issue box's placing), as TerrainMesh keeps its subdiv.
static var _tuning: TerrainTuning = null


## The tile drawn frontmost at `screen` (CourseView local space), or NONE. `heights` overrides
## the course height of the tiles it holds (tile -> height), to pick against ground as it was.
static func pick(course: CourseData, screen: Vector2, heights: Dictionary = {}) -> Vector2i:
	var hit: Array = cast(course, screen, heights)
	return NONE if hit.is_empty() else hit[0]


## The ground point drawn frontmost at `screen`: tile x, tile y (integer = tile centre) and
## height in steps, or null off the map. On a face it is the point on that face.
static func ground_point(course: CourseData, screen: Vector2, heights: Dictionary = {}) -> Variant:
	var hit: Array = cast(course, screen, heights)
	return null if hit.is_empty() else hit[1]


## Whether the ground point `p` (tile x, tile y, steps) is hidden: something drawn nearer the
## camera (a hill in front) covers its screen point. Issue markers' leader feet and the land
## line use it (E3-S59).
static func hidden(course: CourseData, p: Vector3) -> bool:
	var hit: Array = cast(course, Iso.point_to_screen(p), {}, p.z + HIDE_EPS)
	return not hit.is_empty()


## [tile, ground point] drawn frontmost at `screen`, or [] off the map. With `floor`, the ray is
## walked only down to that height (so [] when nothing above it is drawn there).
static func cast(course: CourseData, screen: Vector2, heights: Dictionary = {}, floor: float = -INF) -> Array:
	var t0: Vector2 = Iso.screen_to_tile(screen, 0.0)
	var hi_edge := Vector2(course.width - 0.5, course.height - 0.5)
	if _tuning == null:
		_tuning = TerrainTuning.load_default()
	var tuning := _tuning
	var base: float = maxf(minf(0.0, tuning.base_steps), floor)
	var n: int = tuning.subdiv
	var top: float = CourseData.MAX_HEIGHT + 0.5
	# Every height where the ray crosses a grid line of the mesh (tile edges among them), highest
	# first: between two, the ray stays over one triangle of one tile.
	var zs := PackedFloat64Array([top, base])
	for axis: int in 2:
		# Grid line j lies at j / n - 0.5 tiles; the ray is over it at ze = 2 (that - t0).
		var size: int = course.width if axis == 0 else course.height
		var j0: int = maxi(0, ceili((t0[axis] + base * 0.5 + 0.5) * n))
		var j1: int = mini(size * n, floori((t0[axis] + top * 0.5 + 0.5) * n))
		for j: int in range(j0, j1 + 1):
			var ze: float = 2.0 * (float(j) / n - 0.5 - t0[axis])
			if ze > base and ze < top:
				zs.append(ze)
	zs.sort()
	zs.reverse()
	for k: int in zs.size() - 1:
		var hi: float = zs[k]
		var lo: float = zs[k + 1]
		if hi - lo <= 0.0:
			continue
		var mid: float = 0.5 * (hi + lo)
		var tm: Vector2 = t0 + Vector2(mid, mid) * 0.5
		if tm.x < -0.5 or tm.y < -0.5:
			return []  # behind the map's back edges: lower only goes further back
		if tm.x > hi_edge.x or tm.y > hi_edge.y:
			continue  # in front of the map
		var cell := Vector2i(floori(tm.x + 0.5), floori(tm.y + 0.5))
		var th: Vector2 = t0 + Vector2(hi, hi) * 0.5
		var above: float = TerrainMesh.ground_in(course, cell, th, heights, n) - hi
		if above >= 0.0:
			# Under the ground where the ray came over this tile's edge: its face or its edge.
			return [cell, Vector3(th.x, th.y, hi)]
		var tl: Vector2 = t0 + Vector2(lo, lo) * 0.5
		var below: float = TerrainMesh.ground_in(course, cell, tl, heights, n) - lo
		if below >= 0.0:
			var z: float = hi + (lo - hi) * above / (above - below)
			var tz: Vector2 = t0 + Vector2(z, z) * 0.5
			return [cell, Vector3(tz.x, tz.y, z)]
	return []
