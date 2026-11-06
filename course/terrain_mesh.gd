class_name TerrainMesh
extends RefCounted
## The ground as the course view draws it (E3-S58, D50): a triangle mesh over the bilinear
## surface the ball rolls on (HeightField.height_at, in tile and step units here), textured
## from the flat surface sheets and lit by its slope. A reader only: it never writes the course.
##
## Heights stay whole steps in CourseData; only the drawing is smooth. A one-step rise is a
## slope from one tile centre to the next, across the two half tiles either side of their edge,
## and no risers are drawn.
##
## Geometry, per tile (tile coords: integer = tile centre, as course/iso.gd; heights in steps):
## - A sloped tile (land whose 3 x 3 block of heights, clamped at the map edge, is not all one
##   height) is a subdiv x subdiv grid (TerrainTuning.subdiv, even), its vertices at
##   ground_at, so they lie on the tile's edges and on its centre lines, where the bilinear
##   ground creases. Two triangles a grid square.
## - A flat tile is one fan round its centre, at its height: its four corners, plus the
##   subdiv - 1 points along each edge it shares with a sloped tile, so the two meet without a
##   crack (no T-junctions).
## - Water lies flat at its level (its tile's height) as a fan the same way. Where a water
##   tile meets ground at another height along an edge, a bank face (side_color) closes the
##   gap; only faces that look toward the camera (+x, +y) are drawn.
## - The map's two edges toward the camera (x = width - 1, y = height - 1) get a side face
##   down to TerrainTuning.base_steps.
##
## Texture: every point of a tile maps affinely onto its surface frame's diamond (pulled in by
## UV_INSET_PX so the transparent corner pixels are never sampled), so the flat sheets texture
## the slope with no new art. Unowned tiles are drawn a second time with the land sheet's hatch
## and parcel lines (CourseView.land_frame).
##
## Colour, per vertex: the E6-S18 height shade (a land surface's grey for its height, now
## interpolated between whole steps) times the slope light, capped at the frame's headroom
## (no coloured pixel clips), times BuilderTuning.unowned_tint off owned land. The light is
## shade = 1 + light_strength * (n.x, n.y) . L, held to [light_min, light_max], n the ground's
## unit normal from its slope (the same gradient HeightField.gradient_at gives, so at a
## crease the mean of both sides) and L the unit light_dir across the ground: flat ground is 1
## and draws as before, a slope turned toward the light lighter and one turned from it darker
## by the same amount. The light comes from behind the hills (-x -y), so a slope facing away
## from the camera, which the projection squeezes, reads by value as clearly as one facing it
## (D5 finding 3).
##
## Draw order (painter's, exact for a height field seen from +x +y): a ray to the camera only
## ever moves to larger i + j, so the ground is drawn depth row by depth row (i + j), back to
## front. Each row is cut into Chunks of TerrainTuning.chunk_tiles tiles, each a Node2D that
## Y-sorts at Iso.depth_key of its row, under every object in that row (Iso.object_sort_key is
## the row's key + 1.5 or more) and before the next row. So a hill in front hides what stands
## behind it.

## Pixels the texture diamond is pulled in by, along its edge normal, so nearest sampling never
## lands on a transparent corner pixel of a frame (art/specs/surfaces.md: the diamond is
## pixel-centre rasterised). Art-spec geometry, not a tunable.
const UV_INSET_PX: float = 1.0
## A water bank or side face lower than this, steps, is not drawn.
const FACE_MIN: float = 0.001

var course: CourseData
var tuning: TerrainTuning
var art: TileArt
## Draw the sheets' Play textures (TileSheet.texture_for, E3-S55).
var play: bool = false
var unowned_tint: Color = Color.WHITE
## Grey height shade per surface frame and whole height (CourseView.top_shades).
var shades: Array[PackedFloat32Array] = []
## The largest shade each surface frame takes before a coloured pixel clips (at least 1).
var caps: PackedFloat32Array = PackedFloat32Array()
## Steps per tile, as yards of rise per yard of run (BallParams yards_per_step / yards_per_tile),
## so the light sees the slope the ball feels.
var rise_per_step: float = 0.4

var _light: Vector2 = Vector2(-1.0, 0.0)
var _uv_scale: float = 1.0
var _inv_tex: Vector2 = Vector2.ONE
var _inv_land: Vector2 = Vector2.ONE
## The course as the build reads it (sync): size, every tile's height, water flag and sloped flag.
var _w: int = 0
var _h: int = 0
var _hs := PackedByteArray()
var _wat := PackedByteArray()
var _slo := PackedByteArray()


## One drawn piece of a depth row: its tiles' ground, land hatch and faces, in the Chunk's space
## (CourseView space less (0, key)).
class Chunk:
	extends Node2D
	var row: int = 0
	var index: int = 0
	var texture: Texture2D
	var land_texture: Texture2D
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var land_pts := PackedVector2Array()
	var land_cols := PackedColorArray()
	var land_uvs := PackedVector2Array()
	var land_idx := PackedInt32Array()
	var face_pts := PackedVector2Array()
	var face_cols := PackedColorArray()
	var face_idx := PackedInt32Array()
	## What each of its tiles last emitted (TerrainMesh.emit_tile), so an edit emits only the
	## tiles it touched and joins the rest as they were.
	var parts: Dictionary = {}

	func clear() -> void:
		for a: Variant in [pts, cols, uvs, idx, land_pts, land_cols, land_uvs, land_idx, face_pts, face_cols, face_idx]:
			a.clear()

	func _draw() -> void:
		var ci := get_canvas_item()
		if not idx.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, cols, uvs,
					PackedInt32Array(), PackedFloat32Array(), texture.get_rid())
		if not land_idx.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci, land_idx, land_pts, land_cols, land_uvs,
					PackedInt32Array(), PackedFloat32Array(), land_texture.get_rid())
		if not face_idx.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci, face_idx, face_pts, face_cols)


func _init(p_tuning: TerrainTuning = null, p_art: TileArt = null, builder: BuilderTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else TerrainTuning.load_default()
	art = p_art if p_art != null else TileArt.load_default()
	var b: BuilderTuning = builder if builder != null else BuilderTuning.load_default()
	unowned_tint = b.unowned_tint
	shades = CourseView.top_shades(art.surfaces, b.height_shade, b.height_shaded)
	caps.resize(art.surfaces.frame_count())
	for i: int in caps.size():
		caps[i] = maxf(1.0, CourseView.frame_headroom(art.surfaces, i))
	var params := BallParams.load_default()
	rise_per_step = params.yards_per_step / params.yards_per_tile
	_light = tuning.light_dir.normalized()
	# The diamond's edge lies 32 * 16 / |(32, 16)| px from its centre.
	var edge_px: float = Iso.HALF_W * Iso.HALF_H / Vector2(Iso.HALF_W, Iso.HALF_H).length()
	_uv_scale = 1.0 - UV_INSET_PX / edge_px
	_inv_tex = Vector2.ONE / Vector2(art.surfaces.texture.get_size())
	_inv_land = Vector2.ONE / Vector2(art.land.texture.get_size())


## The surface sheet drawn now: labelled in Build, label-free in Play (E3-S55).
func surface_texture() -> Texture2D:
	return art.surfaces.texture_for(play)


func land_texture() -> Texture2D:
	return art.land.texture_for(play)


# --- the ground ---------------------------------------------------------------------------

## Height in steps of tile (x, y), clamped onto the map (past the edge the edge holds, as
## HeightField does), or as `heights` overrides it (tile -> height).
static func tile_height(c: CourseData, x: int, y: int, heights: Dictionary = {}) -> int:
	var cell := Vector2i(clampi(x, 0, c.width - 1), clampi(y, 0, c.height - 1))
	if not heights.is_empty() and heights.has(cell):
		return heights[cell]
	return c.get_height(cell.x, cell.y)


## The bilinear ground at tile point `t` (integer = tile centre), in steps:
## HeightField.height_at / yards_per_step at the same point.
static func bilinear(c: CourseData, t: Vector2, heights: Dictionary = {}) -> float:
	var fx: float = clampf(t.x, 0.0, c.width - 1)
	var fy: float = clampf(t.y, 0.0, c.height - 1)
	var x0: int = floori(fx)
	var y0: int = floori(fy)
	var ax: float = fx - x0
	var ay: float = fy - y0
	var x1: int = mini(x0 + 1, c.width - 1)
	var y1: int = mini(y0 + 1, c.height - 1)
	var top: float = lerpf(tile_height(c, x0, y0, heights), tile_height(c, x1, y0, heights), ax)
	var bottom: float = lerpf(tile_height(c, x0, y1, heights), tile_height(c, x1, y1, heights), ax)
	return lerpf(top, bottom, ay)


## The ground exactly as the mesh draws it at tile point `t`, in steps:
## water flat at its level (its tile's height), a flat tile at its height, a sloped tile on its
## grid's triangles, whose corners are the bilinear ground (`subdiv` 0 reads TerrainTuning's).
## Off the map, the edge tile's.
static func ground_at(c: CourseData, t: Vector2, heights: Dictionary = {}, subdiv: int = 0) -> float:
	var cell := Vector2i(clampi(floori(t.x + 0.5), 0, c.width - 1), clampi(floori(t.y + 0.5), 0, c.height - 1))
	return ground_in(c, cell, t, heights, subdiv)


## Tile `cell`'s own drawn ground at `t` (held inside the tile), in steps: ground_at, but on a
## tile edge it is this tile's side, so at a water bank the two tiles differ (TilePicker).
static func ground_in(c: CourseData, cell: Vector2i, t: Vector2, heights: Dictionary = {}, subdiv: int = 0) -> float:
	var h: int = tile_height(c, cell.x, cell.y, heights)
	if c.get_surface(cell.x, cell.y) == Surface.Type.WATER:
		return h
	var flat: bool = true
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if tile_height(c, cell.x + dx, cell.y + dy, heights) != h:
				flat = false
	if flat:
		return h
	var n: int = subdiv if subdiv > 0 else TerrainTuning.load_default().subdiv
	# The grid square holding t (clamped into the tile), and its corner heights.
	var u: float = clampf(t.x - cell.x + 0.5, 0.0, 1.0) * n
	var v: float = clampf(t.y - cell.y + 0.5, 0.0, 1.0) * n
	var a: int = mini(floori(u), n - 1)
	var b: int = mini(floori(v), n - 1)
	var fx: float = u - a
	var fy: float = v - b
	var x0: float = cell.x - 0.5 + float(a) / n
	var y0: float = cell.y - 0.5 + float(b) / n
	var s: float = 1.0 / n
	var h00: float = bilinear(c, Vector2(x0, y0), heights)
	var h11: float = bilinear(c, Vector2(x0 + s, y0 + s), heights)
	# The square's diagonal runs from its (0, 0) corner to its (1, 1) corner (tile_geometry).
	if fx >= fy:
		var h10: float = bilinear(c, Vector2(x0 + s, y0), heights)
		return h00 + fx * (h10 - h00) + fy * (h11 - h10)
	var h01: float = bilinear(c, Vector2(x0, y0 + s), heights)
	return h00 + fy * (h01 - h00) + fx * (h11 - h01)


## The bilinear ground's slope at `t`, steps per tile along x and y. On a tile centre line,
## where the slope along the line's normal jumps, the mean of both sides; zero across the
## clamped map edge (HeightField.gradient_at's rule).
static func slope_at(c: CourseData, t: Vector2) -> Vector2:
	return Vector2(_axis_slope(c, t.x, t.y, true), _axis_slope(c, t.y, t.x, false))


static func _axis_slope(c: CourseData, v: float, w: float, along_x: bool) -> float:
	var count: int = c.width if along_x else c.height
	var other: int = c.height if along_x else c.width
	if count < 2 or v < 0.0 or v > count - 1:
		return 0.0
	var fw: float = clampf(w, 0.0, other - 1)
	var w0: int = floori(fw)
	var w1: int = mini(w0 + 1, other - 1)
	var aw: float = fw - w0
	var i0: int = floori(v)
	if v == float(i0):
		var left: float = _segment(c, i0 - 1, w0, w1, aw, along_x) if i0 > 0 else 0.0
		var right: float = _segment(c, i0, w0, w1, aw, along_x) if i0 < count - 1 else 0.0
		return 0.5 * (left + right)
	return _segment(c, i0, w0, w1, aw, along_x)


## Steps from tile i to i + 1 along one axis, blended across the other (w0, w1, aw).
static func _segment(c: CourseData, i: int, w0: int, w1: int, aw: float, along_x: bool) -> float:
	if along_x:
		return lerpf(c.get_height(i + 1, w0) - c.get_height(i, w0), c.get_height(i + 1, w1) - c.get_height(i, w1), aw)
	return lerpf(c.get_height(w0, i + 1) - c.get_height(w0, i), c.get_height(w1, i + 1) - c.get_height(w1, i), aw)


## Whether `cell` is drawn as a subdivided grid: land (not water) whose 3 x 3 block of heights,
## clamped at the map edge, is not all one height. Off the map, never. Reads the cache (sync).
func sloped(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= _w or cell.y >= _h:
		return false
	return _slo[cell.y * _w + cell.x] != 0


## Reads the course into the caches the build uses: every tile's height, whether it is water and
## whether it is sloped. `cells` (tiles whose height or surface changed) refreshes only round
## them; empty reads the whole course. Call before building after the course changed.
func sync(cells: Array[Vector2i] = []) -> void:
	if course == null:
		return
	if cells.is_empty() or _hs.size() != course.width * course.height:
		_w = course.width
		_h = course.height
		_hs.resize(_w * _h)
		_wat.resize(_w * _h)
		_slo.resize(_w * _h)
		for y: int in _h:
			for x: int in _w:
				_read(x, y)
		for y: int in _h:
			for x: int in _w:
				_slo[y * _w + x] = _slope_flag(x, y)
		return
	var near := {}
	for cell: Vector2i in cells:
		if course.in_bounds(cell.x, cell.y):
			_read(cell.x, cell.y)
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					near[cell + Vector2i(dx, dy)] = true
	for c: Vector2i in near:
		if c.x >= 0 and c.y >= 0 and c.x < _w and c.y < _h:
			_slo[c.y * _w + c.x] = _slope_flag(c.x, c.y)


func _read(x: int, y: int) -> void:
	_hs[y * _w + x] = course.get_height(x, y)
	_wat[y * _w + x] = 1 if course.get_surface(x, y) == Surface.Type.WATER else 0


## Cached height of tile (x, y) clamped onto the map.
func _hc(x: int, y: int) -> int:
	return _hs[clampi(y, 0, _h - 1) * _w + clampi(x, 0, _w - 1)]


func _slope_flag(x: int, y: int) -> int:
	if _wat[y * _w + x] != 0:
		return 0
	var h: int = _hs[y * _w + x]
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if _hc(x + dx, y + dy) != h:
				return 1
	return 0


# --- lighting -------------------------------------------------------------------------------

## The slope light for ground of slope `g` (steps per tile along x, y): 1 on flat ground.
func light_for(g: Vector2) -> float:
	var n := Vector3(-g.x * rise_per_step, -g.y * rise_per_step, 1.0).normalized()
	return light_of(n)


## The light on a surface whose unit normal is `n` (z up): the ground's rule, so a vertical
## face takes it too.
func light_of(n: Vector3) -> float:
	return clampf(1.0 + tuning.light_strength * Vector2(n.x, n.y).dot(_light), tuning.light_min, tuning.light_max)


## The vertex colour of surface frame `frame` at `h` steps with slope `g`, owned or not.
func shade(frame: int, h: float, g: Vector2, owned: bool) -> Color:
	var row: PackedFloat32Array = shades[frame]
	var k: int = clampi(floori(h), 0, row.size() - 1)
	var hs: float = lerpf(row[k], row[mini(k + 1, row.size() - 1)], clampf(h - k, 0.0, 1.0))
	var v: float = minf(hs * light_for(g), caps[frame])
	var col := Color(v, v, v)
	return col * unowned_tint if not owned else col


# --- geometry -------------------------------------------------------------------------------

## The ground of one tile: [points (tile x, tile y, steps), triangles (index triples), slopes
## (steps per tile at each point)]. Reads the cache (sync).
func tile_geometry(cell: Vector2i) -> Array:
	var pts := PackedVector3Array()
	var tris := PackedInt32Array()
	var slopes := PackedVector2Array()
	var n: int = tuning.subdiv
	if sloped(cell):
		_grid_setup(n)
		# The 3 x 3 heights round the tile, clamped at the map edge: all the tile's ground reads.
		var hh := PackedFloat32Array()
		hh.resize(9)
		for dy: int in 3:
			for dx: int in 3:
				hh[dy * 3 + dx] = _hc(cell.x + dx - 1, cell.y + dy - 1)
		var m: int = n + 1
		pts.resize(m * m)
		slopes.resize(m * m)
		for b: int in m:
			var ya: int = _pair[b]
			var fy: float = _frac[b]
			for a: int in m:
				var xa: int = _pair[a]
				var fx: float = _frac[a]
				var r0: int = ya * 3
				var r1: int = r0 + 3
				var top: float = lerpf(hh[r0 + xa], hh[r0 + xa + 1], fx)
				var bot: float = lerpf(hh[r1 + xa], hh[r1 + xa + 1], fx)
				var gx: float
				var gy: float
				if _centre[a]:
					gx = 0.5 * lerpf(hh[r0 + 2] - hh[r0], hh[r1 + 2] - hh[r1], fy)
				else:
					gx = lerpf(hh[r0 + xa + 1] - hh[r0 + xa], hh[r1 + xa + 1] - hh[r1 + xa], fy)
				if _centre[b]:
					gy = 0.5 * lerpf(hh[6 + xa] - hh[xa], hh[6 + xa + 1] - hh[xa + 1], fx)
				else:
					gy = bot - top
				var k: int = b * m + a
				pts[k] = Vector3(cell.x + _off[a], cell.y + _off[b], lerpf(top, bot, fy))
				slopes[k] = Vector2(gx, gy)
		return [pts, _grid_tris, slopes]
	# A fan round the centre, flat at the tile's height (water at its level).
	var h: float = _hc(cell.x, cell.y)
	pts.append(Vector3(cell.x, cell.y, h))
	var c := Vector2(cell)
	for e: int in 4:
		var a0: Vector2 = c + FAN_CORNERS[e]
		pts.append(Vector3(a0.x, a0.y, h))
		if sloped(cell + FAN_SIDES[e]):
			var a1: Vector2 = c + FAN_CORNERS[(e + 1) % 4]
			for k: int in range(1, n):
				var p: Vector2 = a0.lerp(a1, float(k) / n)
				pts.append(Vector3(p.x, p.y, h))
	var ring: int = pts.size() - 1
	for k: int in ring:
		tris.append_array([0, 1 + k, 1 + (k + 1) % ring])
	slopes.resize(pts.size())
	return [pts, tris, slopes]


## The fan's corners in order round the tile, and the neighbour across the edge each starts.
const FAN_CORNERS: Array[Vector2] = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
const FAN_SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## The grid of a sloped tile, the same for every tile at one subdiv: per grid line, its offset
## from the centre, the pair of 3 x 3 columns (or rows) it blends (0: -1 and 0, 1: 0 and +1),
## the blend, whether it is the centre line; and the triangles.
var _grid_n: int = 0
var _off := PackedFloat32Array()
var _pair := PackedInt32Array()
var _frac := PackedFloat32Array()
var _centre: Array[bool] = []
var _grid_tris := PackedInt32Array()


func _grid_setup(n: int) -> void:
	if _grid_n == n:
		return
	_grid_n = n
	_off.clear()
	_pair.clear()
	_frac.clear()
	_centre.clear()
	_grid_tris.clear()
	for a: int in n + 1:
		var u: float = -0.5 + float(a) / n
		_off.append(u)
		_pair.append(0 if u < 0.0 else 1)
		_frac.append(u + 1.0 if u < 0.0 else u)
		_centre.append(u == 0.0)
	for b: int in n:
		for a: int in n:
			var p00: int = b * (n + 1) + a
			var p01: int = p00 + n + 1
			_grid_tris.append_array([p00, p00 + 1, p01 + 1, p00, p01 + 1, p01])


## The points along `cell`'s edge toward `side` (+x or +y), from one corner to the other, as
## its own ground draws them: every grid point when it or the tile beyond is sloped, else the
## two corners.
func _edge_points(cell: Vector2i, side: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a0: Vector2 = Vector2(cell) + (Vector2(0.5, -0.5) if side.x == 1 else Vector2(-0.5, 0.5))
	var a1: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
	var n: int = tuning.subdiv
	var count: int = n if sloped(cell) or sloped(cell + side) else 1
	for k: int in count + 1:
		out.append(a0.lerp(a1, float(k) / count))
	return out


## Height in steps of `cell`'s own ground at `t` on its edge: water at its level, land bilinear.
func _own_height(cell: Vector2i, t: Vector2) -> float:
	if _wat[cell.y * _w + cell.x] != 0:
		return _hs[cell.y * _w + cell.x]
	return bilinear(course, t)


## The faces `cell` shows toward the camera: [top polyline, bottom polyline, unit normal] per
## face. A water bank where the ground on its +x or +y edge stands lower beyond it, and the side
## of the map on its last row or column.
func tile_faces(cell: Vector2i) -> Array:
	var out: Array = []
	var water: bool = _wat[cell.y * _w + cell.x] != 0
	for side: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var next: Vector2i = cell + side
		var off_map: bool = next.x >= _w or next.y >= _h
		if not off_map and not water and _wat[next.y * _w + next.x] == 0:
			continue
		var line := _edge_points(cell, side)
		var top := PackedVector3Array()
		var bottom := PackedVector3Array()
		var drop: float = 0.0
		for t: Vector2 in line:
			var hi: float = _own_height(cell, t)
			var lo: float = tuning.base_steps if off_map else _own_height(next, t)
			drop = maxf(drop, hi - lo)
			top.append(Vector3(t.x, t.y, hi))
			bottom.append(Vector3(t.x, t.y, minf(lo, hi)))
		if drop > FACE_MIN:
			out.append([top, bottom, Vector3(side.x, side.y, 0.0)])
	return out


# --- chunks ---------------------------------------------------------------------------------

## The chunk holding `cell`: (depth row, index along the row by x).
func chunk_key(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x + cell.y, cell.x / tuning.chunk_tiles)


## The tiles of chunk `key`, back of the row first.
func chunk_cells(key: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo: int = maxi(key.y * tuning.chunk_tiles, maxi(0, key.x - course.height + 1))
	var hi: int = mini((key.y + 1) * tuning.chunk_tiles - 1, mini(course.width - 1, key.x))
	for x: int in range(lo, hi + 1):
		out.append(Vector2i(x, key.x - x))
	return out


## Every chunk key of the course, back to front.
func all_chunk_keys() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: int in course.width + course.height - 1:
		var lo: int = maxi(0, row - course.height + 1)
		var hi: int = mini(course.width - 1, row)
		for k: int in range(lo / tuning.chunk_tiles, hi / tuning.chunk_tiles + 1):
			out.append(Vector2i(row, k))
	return out


## A new chunk node for `key`, built.
func make_chunk(key: Vector2i) -> Chunk:
	var ch := Chunk.new()
	ch.name = "Ground%d_%d" % [key.x, key.y]
	ch.row = key.x
	ch.index = key.y
	ch.position = Vector2(0.0, Iso.depth_key(Vector2i(key.x, 0)))
	build_chunk(ch)
	return ch


## Fills `ch` from the cache (sync first) and redraws it. With `only` (tile -> true), only those
## of its tiles are emitted again; the others keep what they last emitted (Chunk.parts).
func build_chunk(ch: Chunk, only: Dictionary = {}) -> void:
	ch.texture = surface_texture()
	ch.land_texture = land_texture()
	var cells: Array[Vector2i] = chunk_cells(Vector2i(ch.row, ch.index))
	for cell: Vector2i in cells:
		if only.is_empty() or only.has(cell) or not ch.parts.has(cell):
			ch.parts[cell] = emit_tile(cell, ch.position.y)
	ch.clear()
	for cell: Vector2i in cells:
		var part: Array = ch.parts[cell]
		var base: int = ch.pts.size()
		ch.pts.append_array(part[0])
		ch.uvs.append_array(part[1])
		ch.cols.append_array(part[2])
		for t: int in part[3] as PackedInt32Array:
			ch.idx.append(base + t)
		var land_uvs: PackedVector2Array = part[4]
		if not land_uvs.is_empty():
			var lbase: int = ch.land_pts.size()
			ch.land_pts.append_array(part[0])
			ch.land_uvs.append_array(land_uvs)
			for t: int in part[3] as PackedInt32Array:
				ch.land_idx.append(lbase + t)
		var face_pts: PackedVector2Array = part[5]
		if not face_pts.is_empty():
			var fbase: int = ch.face_pts.size()
			ch.face_pts.append_array(face_pts)
			ch.face_cols.append_array(part[6])
			for t: int in part[7] as PackedInt32Array:
				ch.face_idx.append(fbase + t)
	ch.land_cols.resize(ch.land_pts.size())
	ch.land_cols.fill(Color.WHITE)
	ch.queue_redraw()


## What `cell` draws, in the space of a chunk whose sort key is `key_y`: [points, uvs, colours,
## triangles, land hatch uvs (empty on owned land), face points, face colours, face triangles].
func emit_tile(cell: Vector2i, key_y: float) -> Array:
	var sheet: TileSheet = art.surfaces
	var strength: float = tuning.light_strength
	var lmin: float = tuning.light_min
	var lmax: float = tuning.light_max
	var r: float = rise_per_step
	var geo: Array = tile_geometry(cell)
	var pts: PackedVector3Array = geo[0]
	var slopes: PackedVector2Array = geo[2]
	var frame: int = course.get_surface(cell.x, cell.y)
	var land: int = CourseView.land_frame(course, cell.x, cell.y)
	var owned: bool = land < 0
	var row: PackedFloat32Array = shades[frame]
	var cap: float = caps[frame]
	var tint: Color = Color.WHITE if owned else unowned_tint
	# Screen and texture points relative to the tile's centre at height 0: Iso and _uv written
	# out here, since this runs for every point of the map.
	var centre: Vector2 = Iso.tile_to_screen(Vector2(cell), 0.0) - Vector2(0.0, key_y)
	var origin: Vector2 = Vector2(sheet.region(frame).position) + Vector2(sheet.anchor)
	var count: int = pts.size()
	var screen := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	screen.resize(count)
	uvs.resize(count)
	cols.resize(count)
	for i: int in count:
		var p: Vector3 = pts[i]
		var dx: float = p.x - cell.x
		var dy: float = p.y - cell.y
		var lx: float = dx * _uv_scale
		var ly: float = dy * _uv_scale
		screen[i] = centre + Vector2((dx - dy) * Iso.HALF_W, (dx + dy) * Iso.HALF_H - p.z * Iso.STEP_PX)
		uvs[i] = (origin + Vector2((lx - ly) * Iso.HALF_W, (lx + ly) * Iso.HALF_H)) * _inv_tex
		var k: int = clampi(floori(p.z), 0, CourseData.MAX_HEIGHT)
		var hs: float = lerpf(row[k], row[mini(k + 1, CourseData.MAX_HEIGHT)], p.z - k)
		var g: Vector2 = slopes[i]
		var light: float = 1.0
		if g != Vector2.ZERO:
			var nx: float = -g.x * r
			var ny: float = -g.y * r
			light = clampf(1.0 + strength * (nx * _light.x + ny * _light.y) / sqrt(nx * nx + ny * ny + 1.0), lmin, lmax)
		var v: float = minf(hs * light, cap)
		cols[i] = Color(v * tint.r, v * tint.g, v * tint.b)
	var land_uvs := PackedVector2Array()
	if not owned:
		var land_sheet: TileSheet = art.land
		var lorigin: Vector2 = Vector2(land_sheet.region(land).position) + Vector2(land_sheet.anchor)
		land_uvs.resize(count)
		for i: int in count:
			var lx: float = (pts[i].x - cell.x) * _uv_scale
			var ly: float = (pts[i].y - cell.y) * _uv_scale
			land_uvs[i] = (lorigin + Vector2((lx - ly) * Iso.HALF_W, (lx + ly) * Iso.HALF_H)) * _inv_land
	var face_pts := PackedVector2Array()
	var face_cols := PackedColorArray()
	var face_idx := PackedInt32Array()
	if _wat[cell.y * _w + cell.x] != 0 or cell.x == _w - 1 or cell.y == _h - 1 \
			or _wat[cell.y * _w + mini(cell.x + 1, _w - 1)] != 0 or _wat[mini(cell.y + 1, _h - 1) * _w + cell.x] != 0:
		var off := Vector2(0.0, key_y)
		for face: Array in tile_faces(cell):
			var top: PackedVector3Array = face[0]
			var bottom: PackedVector3Array = face[1]
			var col: Color = tuning.side_color * light_of(face[2]) * tint
			col.a = 1.0
			var fbase: int = face_pts.size()
			for i: int in top.size():
				face_pts.append(Iso.tile_to_screen(Vector2(top[i].x, top[i].y), top[i].z) - off)
				face_pts.append(Iso.tile_to_screen(Vector2(bottom[i].x, bottom[i].y), bottom[i].z) - off)
				face_cols.append(col)
				face_cols.append(col)
			for i: int in top.size() - 1:
				var a: int = fbase + 2 * i
				face_idx.append_array([a, a + 2, a + 3, a, a + 3, a + 1])
	return [screen, uvs, cols, geo[1], land_uvs, face_pts, face_cols, face_idx]
