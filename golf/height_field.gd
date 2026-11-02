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
func gradient_at(x: float, y: float) -> Vector2:
	var ax := _axis(x, course.width)
	var ay := _axis(y, course.height)
	var h00 := course.get_height(int(ax.x), int(ay.x))
	var h10 := course.get_height(int(ax.y), int(ay.x))
	var h01 := course.get_height(int(ax.x), int(ay.y))
	var h11 := course.get_height(int(ax.y), int(ay.y))
	var dfx := lerpf(h10 - h00, h11 - h01, ay.z) * ax.w
	var dfy := lerpf(h01 - h00, h11 - h10, ax.z) * ay.w
	return Vector2(dfx, dfy) * (yards_per_step / yards_per_tile)


## Unit ground normal at (x, y), z up.
func normal_at(x: float, y: float) -> Vector3:
	var g := gradient_at(x, y)
	return Vector3(-g.x, -g.y, 1.0).normalized()


## For one axis: (low tile, high tile, blend 0..1, 1 inside the map or 0 where clamped).
func _axis(v: float, count: int) -> Vector4:
	var u := v / yards_per_tile - 0.5
	if u <= 0.0 or count < 2:
		return Vector4(0, 0, 0, 0)
	if u >= count - 1:
		return Vector4(count - 1, count - 1, 0, 0)
	var i0 := floori(u)
	return Vector4(i0, i0 + 1, u - i0, 1.0)
