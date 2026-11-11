class_name HeightField
extends RefCounted
## Reads a CourseData as continuous ground in yards, for the ball, its shadow and guests. The
## course view draws the same ground (E3-S58, D50), so ground_screen puts a thing on it.
## Land the player does not own reads as `oob` (surface_at, D29).
## Height is interpolated bilinearly between tile centres, so a one-step rise between two
## tiles becomes a slope from one centre to the next. Past the map edge the edge height holds.
## x and y are yards from the map corner (tile (i, j) covers [5i, 5i + 5)); heights are yards.

var course: CourseData
var yards_per_tile: float
var yards_per_step: float

## E7-S4: the course's packed tiles and owned flags (CourseData.packed_tiles, packed_owned) as
## of its `revision` `_rev`, read straight by height_at, gradient_at and the surface reads: a
## Ball tick makes dozens of them, and before they cost a GDScript call per tile read
## (CourseData.get_height, is_owned, get_surface) and per axis. Every read first checks the
## revision, so a write by the builder is seen at the next read, as before. The answers are
## the same bit for bit: the same lerps in the same order, each axis's blend rounded to a
## 32-bit float as _axis's Vector4 rounds it.
var _rev: int = -1
var _tiles: PackedByteArray
var _owned: PackedByteArray
var _w: int = 0
var _h: int = 0
## Parcels along a row (CourseData.parcels_wide), for the owned flags' index.
var _pw: int = 0


func _init(p_course: CourseData, params: BallParams) -> void:
	course = p_course
	yards_per_tile = params.yards_per_tile
	yards_per_step = params.yards_per_step


## Takes the course's packed arrays again (it was written since they were taken).
@warning_ignore("integer_division")
func _sync() -> void:
	_rev = course.revision
	_tiles = course.packed_tiles()
	_owned = course.packed_owned()
	_w = course.width
	_h = course.height
	_pw = (_w + CourseData.PARCEL_TILES - 1) / CourseData.PARCEL_TILES


## Tile holding the ground point (x, y) in yards.
func tile_at(x: float, y: float) -> Vector2i:
	return Vector2i(floori(x / yards_per_tile), floori(y / yards_per_tile))


## Centre of a tile, in yards.
func tile_center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * yards_per_tile


## A point in yards as Iso coordinates: x, y in tiles (integer = tile centre, as course/iso.gd
## expects) and z in height steps. Iso.point_to_screen takes the result.
func iso_point(p: Vector3) -> Vector3:
	return Vector3(p.x / yards_per_tile - 0.5, p.y / yards_per_tile - 0.5, p.z / yards_per_step)


## Drawn height, in steps, of the ground at (x, y) (E3-S59, D50): the height the course view
## draws there, which is height_at, except on a water tile, which lies flat at its level (its
## tile's height). Past the map edge the edge holds, as it does for height_at.
func drawn_steps(x: float, y: float) -> float:
	var cell := tile_at(x, y)
	cell = Vector2i(clampi(cell.x, 0, course.width - 1), clampi(cell.y, 0, course.height - 1))
	if course.get_surface(cell.x, cell.y) == Surface.Type.WATER:
		return course.get_height(cell.x, cell.y)
	return height_at(x, y) / yards_per_step


## Screen point (CourseView space) of the ground point `p` drawn on the ground under it, at
## drawn_steps (D50, replacing D17's tile top): the ball and its shadow on the ground, the aim
## marker, the struck ball's landing cross, golfers and their balls all use this one rule, so
## they sit on the ground the course view draws, and on each other.
func ground_screen(p: Vector3) -> Vector2:
	var iso := iso_point(p)
	return Iso.tile_to_screen(Vector2(iso.x, iso.y), drawn_steps(p.x, p.y))


## Surface the ball plays under (x, y). Off the map is Surface.Type.OOB, and so is every tile
## of a parcel the player does not own (D29, E6-S7): unowned land plays as an `oob` tile,
## whatever is painted on it, though its heights still shape the ground (height_at). On a
## fully owned course (New sandbox, every version 1 file) it is the tile's own surface.
func surface_at(x: float, y: float) -> Surface.Type:
	return _surface(floori(x / yards_per_tile), floori(y / yards_per_tile))


## Surface the ball plays on `tile`, as surface_at.
func surface_of(tile: Vector2i) -> Surface.Type:
	return _surface(tile.x, tile.y)


## CourseData.is_owned and get_surface on the packed arrays (E7-S4).
@warning_ignore("integer_division")
func _surface(tx: int, ty: int) -> Surface.Type:
	if course.revision != _rev:
		_sync()
	if tx < 0 or ty < 0 or tx >= _w or ty >= _h:
		return Surface.Type.OOB
	if _owned[(ty / CourseData.PARCEL_TILES) * _pw + tx / CourseData.PARCEL_TILES] == 0:
		return Surface.Type.OOB
	return (_tiles[ty * _w + tx] & 0x0F) as Surface.Type


## Surface painted under (x, y), owned or not (off the map is Surface.Type.OOB). Only the
## in-flight tree block reads it (Ball._blocks, E6-S7 review): trees standing on unowned land
## still stop a flight, as trees past the white stakes do, and are drawn there, so the shot
## reads as it plays. Touchdown, roll, rest and the drop read surface_at.
func painted_surface_at(x: float, y: float) -> Surface.Type:
	if course.revision != _rev:
		_sync()
	var tx := floori(x / yards_per_tile)
	var ty := floori(y / yards_per_tile)
	if tx < 0 or ty < 0 or tx >= _w or ty >= _h:
		return Surface.Type.OOB
	return (_tiles[ty * _w + tx] & 0x0F) as Surface.Type


## Ground height in yards at (x, y).
## E7-S4: `_axis` and CourseData.get_height spelled out on the packed tiles (_sync); the
## indices are clamped onto the map, so no read is off it.
func height_at(x: float, y: float) -> float:
	if course.revision != _rev:
		_sync()
	if _w == 0 or _h == 0:
		return 0.0
	# _axis, x then y: the low and high tile and the blend, rounded to 32 bits as Vector4 holds it.
	var ux := x / yards_per_tile - 0.5
	var x0 := 0
	var x1 := 0
	var bx := 0.0
	if ux <= 0.0 or _w < 2:
		pass
	elif ux >= _w - 1:
		x0 = _w - 1
		x1 = x0
	else:
		x0 = floori(ux)
		x1 = x0 + 1
		bx = Vector2(ux - x0, 0.0).x
	var uy := y / yards_per_tile - 0.5
	var r0 := 0
	var r1 := 0
	var by := 0.0
	if uy <= 0.0 or _h < 2:
		pass
	elif uy >= _h - 1:
		r0 = (_h - 1) * _w
		r1 = r0
	else:
		var y0 := floori(uy)
		r0 = y0 * _w
		r1 = r0 + _w
		by = Vector2(uy - y0, 0.0).x
	var top := lerpf(_tiles[r0 + x0] >> 4, _tiles[r0 + x1] >> 4, bx)
	var bottom := lerpf(_tiles[r1 + x0] >> 4, _tiles[r1 + x1] >> 4, bx)
	return lerpf(top, bottom, by) * yards_per_step


## Slope (dh/dx, dh/dy) in yards per yard at (x, y). Zero across the clamped map edge.
## The bilinear slope along an axis jumps at each tile centre on that axis; exactly on a
## centre it is the mean of the slopes on both sides (E2-S4), so a ball set there feels
## no one-sided pull (a pit's floor line is level, not the wall beyond it).
## E7-S4: `_axis`, `_centred_slope` and `_segment_slope` spelled out on the packed tiles
## (_sync), the same lerps in the same order.
func gradient_at(x: float, y: float) -> Vector2:
	if course.revision != _rev:
		_sync()
	if _w == 0 or _h == 0:
		return Vector2.ZERO
	var ux := x / yards_per_tile - 0.5
	var x0 := 0
	var x1 := 0
	var bx := 0.0
	var wx := 0.0
	if ux <= 0.0 or _w < 2:
		pass
	elif ux >= _w - 1:
		x0 = _w - 1
		x1 = x0
	else:
		x0 = floori(ux)
		x1 = x0 + 1
		bx = Vector2(ux - x0, 0.0).x
		wx = 1.0
	var uy := y / yards_per_tile - 0.5
	var y0 := 0
	var y1 := 0
	var by := 0.0
	var wy := 0.0
	if uy <= 0.0 or _h < 2:
		pass
	elif uy >= _h - 1:
		y0 = _h - 1
		y1 = y0
	else:
		y0 = floori(uy)
		y1 = y0 + 1
		by = Vector2(uy - y0, 0.0).x
		wy = 1.0
	var t := _tiles
	var w := _w
	var r0 := y0 * w
	var r1 := y1 * w
	var dfx := 0.0
	if _w < 2 or ux < 0.0 or ux > _w - 1 or ux != floorf(ux):
		dfx = lerpf((t[r0 + x1] >> 4) - (t[r0 + x0] >> 4), (t[r1 + x1] >> 4) - (t[r1 + x0] >> 4),
				by) * wx
	else:
		var i := int(ux)
		var left := lerpf((t[r0 + i] >> 4) - (t[r0 + i - 1] >> 4),
				(t[r1 + i] >> 4) - (t[r1 + i - 1] >> 4), by) if i > 0 else 0.0
		var right := lerpf((t[r0 + i + 1] >> 4) - (t[r0 + i] >> 4),
				(t[r1 + i + 1] >> 4) - (t[r1 + i] >> 4), by) if i < _w - 1 else 0.0
		dfx = 0.5 * (left + right)
	var dfy := 0.0
	if _h < 2 or uy < 0.0 or uy > _h - 1 or uy != floorf(uy):
		dfy = lerpf((t[r1 + x0] >> 4) - (t[r0 + x0] >> 4), (t[r1 + x1] >> 4) - (t[r0 + x1] >> 4),
				bx) * wy
	else:
		var j := int(uy)
		var rj := j * w
		var up := lerpf((t[rj + x0] >> 4) - (t[rj - w + x0] >> 4),
				(t[rj + x1] >> 4) - (t[rj - w + x1] >> 4), bx) if j > 0 else 0.0
		var down := lerpf((t[rj + w + x0] >> 4) - (t[rj + x0] >> 4),
				(t[rj + w + x1] >> 4) - (t[rj + x1] >> 4), bx) if j < _h - 1 else 0.0
		dfy = 0.5 * (up + down)
	return Vector2(dfx, dfy) * (yards_per_step / yards_per_tile)


## Unit ground normal at (x, y), z up.
func normal_at(x: float, y: float) -> Vector3:
	return normal_for(gradient_at(x, y))


## Unit normal of ground with slope `g` (dh/dx, dh/dy), z up.
static func normal_for(g: Vector2) -> Vector3:
	return Vector3(-g.x, -g.y, 1.0).normalized()
