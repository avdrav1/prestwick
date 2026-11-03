class_name HeightField
extends RefCounted
## Reads a CourseData as continuous ground in yards, for the ball, its shadow and guests.
## Height is interpolated bilinearly between tile centres, so a one-step rise between two
## tiles becomes a slope from one centre to the next. Past the map edge the edge height holds.
## x and y are yards from the map corner (tile (i, j) covers [5i, 5i + 5)); heights are yards.

var course: CourseData
var yards_per_tile: float
var yards_per_step: float


func _init(p_course: CourseData, params: BallParams) -> void:
	course = p_course
	yards_per_tile = params.yards_per_tile
	yards_per_step = params.yards_per_step


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


## Surface under (x, y). Off the map is Surface.Type.OOB.
func surface_at(x: float, y: float) -> Surface.Type:
	var t := tile_at(x, y)
	return course.get_surface(t.x, t.y)


## Ground height in yards at (x, y).
func height_at(x: float, y: float) -> float:
	var ax := _axis(x, course.width)
	var ay := _axis(y, course.height)
	var h00 := course.get_height(int(ax.x), int(ay.x))
	var h10 := course.get_height(int(ax.y), int(ay.x))
	var h01 := course.get_height(int(ax.x), int(ay.y))
	var h11 := course.get_height(int(ax.y), int(ay.y))
	var top := lerpf(h00, h10, ax.z)
	var bottom := lerpf(h01, h11, ax.z)
	return lerpf(top, bottom, ay.z) * yards_per_step


## Slope (dh/dx, dh/dy) in yards per yard at (x, y). Zero across the clamped map edge.
## The bilinear slope along an axis jumps at each tile centre on that axis; exactly on a
## centre it is the mean of the slopes on both sides (E2-S4), so a ball set there feels
## no one-sided pull (a pit's floor line is level, not the wall beyond it).
func gradient_at(x: float, y: float) -> Vector2:
	var ax := _axis(x, course.width)
	var ay := _axis(y, course.height)
	var dfx := _centred_slope(x, course.width, ax, ay, true)
	var dfy := _centred_slope(y, course.height, ay, ax, false)
	return Vector2(dfx, dfy) * (yards_per_step / yards_per_tile)


## Unit ground normal at (x, y), z up.
func normal_at(x: float, y: float) -> Vector3:
	return normal_for(gradient_at(x, y))


## Unit normal of ground with slope `g` (dh/dx, dh/dy), z up.
static func normal_for(g: Vector2) -> Vector3:
	return Vector3(-g.x, -g.y, 1.0).normalized()


## Height difference in steps per tile along one axis at `v` (yards on that axis), across
## the other axis's blend `cross`. `a` is _axis(v). On an exact tile centre, the mean of the
## segments either side (a side past the map edge is level).
func _centred_slope(v: float, count: int, a: Vector4, cross: Vector4, along_x: bool) -> float:
	var u := v / yards_per_tile - 0.5
	if count < 2 or u < 0.0 or u > count - 1 or u != floorf(u):
		return _segment_slope(int(a.x), int(a.y), cross, along_x) * a.w
	var i := int(u)
	var left := _segment_slope(i - 1, i, cross, along_x) if i > 0 else 0.0
	var right := _segment_slope(i, i + 1, cross, along_x) if i < count - 1 else 0.0
	return 0.5 * (left + right)


## Steps from tile `i0` to tile `i1` along one axis, blended across the other by `cross`.
func _segment_slope(i0: int, i1: int, cross: Vector4, along_x: bool) -> float:
	var c0 := int(cross.x)
	var c1 := int(cross.y)
	if along_x:
		return lerpf(course.get_height(i1, c0) - course.get_height(i0, c0),
				course.get_height(i1, c1) - course.get_height(i0, c1), cross.z)
	return lerpf(course.get_height(c0, i1) - course.get_height(c0, i0),
			course.get_height(c1, i1) - course.get_height(c1, i0), cross.z)


## For one axis: (low tile, high tile, blend 0..1, 1 inside the map or 0 where clamped).
func _axis(v: float, count: int) -> Vector4:
	var u := v / yards_per_tile - 0.5
	if u <= 0.0 or count < 2:
		return Vector4(0, 0, 0, 0)
	if u >= count - 1:
		return Vector4(count - 1, count - 1, 0, 0)
	var i0 := floori(u)
	return Vector4(i0, i0 + 1, u - i0, 1.0)
