class_name GridHeightEvidence
extends SceneTree
## Evidence for E1-S9 (D4, D5 in docs/DECISIONS.md): two courses and a set of putts and shots
## across them, run through the real Ball. Prints one line per shot. Screenshots of the same
## courses come from tests/fixtures/grid_height_shot.tscn.
##
##   godot --headless --path . -s res://tests/fixtures/grid_height_evidence.gd

const GREEN_W: int = 16
const GREEN_H: int = 12
const HILL_W: int = 28
const HILL_H: int = 12


func _initialize() -> void:
	var params := BallParams.load_default()
	print("== slope between two tile centres one step apart: %.0f%% (%.1f deg)" % [
		100.0 * params.yards_per_step / params.yards_per_tile,
		rad_to_deg(atan(params.yards_per_step / params.yards_per_tile))])
	_putts("green contour, 2.0 yd per step (as built)", green_contour(), params)
	var gentle := params.duplicate() as BallParams
	gentle.yards_per_step = 0.15
	_putts("green contour, 0.15 yd per step (3% between centres; what-if only)", green_contour(), gentle)
	_rest_on_slope(green_contour(), params)
	_hill_shots(params)
	quit(0)


## Fairway in front (x 0 to 3) at height 0, then an 8x8 green (x 4 to 11, y 2 to 9) in four
## tiers two tiles deep at heights 0, 1, 2, 3: a 3-step contour. Rough around it follows the
## same tiers, then a flat back at 3. `mirrored` flips the tiers (3, 2, 1, 0 along +x, fairway
## at 3), so the risers face the camera instead of away from it.
static func green_contour(mirrored: bool = false) -> CourseData:
	var c := CourseData.create(GREEN_W, GREEN_H, Surface.Type.ROUGH, 0)
	for y: int in GREEN_H:
		for x: int in GREEN_W:
			var h: int = clampi((x - 4) / 2, 0, 3) if x >= 4 else 0
			if mirrored:
				h = 3 - h
			var s := Surface.Type.ROUGH
			if x <= 3 and y >= 3 and y <= 8:
				s = Surface.Type.FAIRWAY
			if x >= 4 and x <= 11 and y >= 2 and y <= 9:
				s = Surface.Type.GREEN
			c.set_tile(x, y, h, s)
	c.set_info("E1-S9 green contour", "tests", "")
	return c


## A fairway hillside climbing 0 to 7. Rows y 0 to 5 rise one step every two tiles
## (x 6 to 19); rows y 6 to 11 rise one step every tile (x 10 to 16). Flat top at 7.
## `mirrored` flips it along x, so it rises towards the camera and its risers show.
static func hillside(mirrored: bool = false) -> CourseData:
	var c := CourseData.create(HILL_W, HILL_H, Surface.Type.FAIRWAY, 0)
	for y: int in HILL_H:
		for x: int in HILL_W:
			var h: int
			if y <= 5:
				h = clampi((x - 4) / 2, 0, 7)
			else:
				h = clampi(x - 9, 0, 7)
			var s := Surface.Type.ROUGH if y == 0 or y == HILL_H - 1 or y == 5 or y == 6 \
					else Surface.Type.FAIRWAY
			c.set_tile(HILL_W - 1 - x if mirrored else x, y, h, s)
	c.set_info("E1-S9 hillside", "tests", "")
	return c


static func _yd(tile: Vector2) -> Vector2:
	return (tile + Vector2(0.5, 0.5)) * 5.0


func _putts(label: String, course: CourseData, params: BallParams) -> void:
	print("== putts: %s" % label)
	print("   tiers: x 4-5 h0, 6-7 h1, 8-9 h2, 10-11 h3; tile 5 yd; green x 4..11")
	# Uphill from the front tier centre (tile 4.5, 5.5) along +x, and downhill from the back.
	for speed: float in [3.0, 5.0, 7.0, 9.0, 11.0]:
		_putt(course, params, "uphill  ", Vector2(4.5, 5.5), Vector2(speed, 0.0))
	for speed: float in [1.0, 3.0, 5.0]:
		_putt(course, params, "downhill", Vector2(10.5, 5.5), Vector2(-speed, 0.0))
	# Sidehill: along +y across the slope band between tier 0 and tier 1 (tile x 5.5).
	for speed: float in [3.0, 5.0]:
		_putt(course, params, "sidehill", Vector2(5.5, 2.5), Vector2(0.0, speed))
	# Reference: the same speeds on a flat green.
	var flat := CourseData.create(GREEN_W, GREEN_H, Surface.Type.GREEN, 0)
	for speed: float in [3.0, 5.0, 7.0, 9.0, 11.0]:
		_putt(flat, params, "flat    ", Vector2(1.5, 5.5), Vector2(speed, 0.0))


func _putt(course: CourseData, params: BallParams, kind: String, from_tile: Vector2,
		v: Vector2) -> void:
	var ball := Ball.new(course, 1, params)
	ball.start_roll(_yd(from_tile), v)
	var ticks := ball.run_to_rest()
	var end := ball.position
	var travel := Vector2(end.x, end.y) - _yd(from_tile)
	print("   %s %4.1f yd/s from tile %s -> rest tile (%.2f, %.2f) on %s, moved (%.1f, %.1f) yd in %.1f s" % [
		kind, v.length(), from_tile, end.x / 5.0 - 0.5, end.y / 5.0 - 0.5,
		Surface.name_of(ball.field.surface_at(end.x, end.y)), travel.x, travel.y, ticks / 60.0])


## Drops a still ball at many points on the contour green and records where any comes to rest
## on ground steeper than 1%.
func _rest_on_slope(course: CourseData, params: BallParams) -> void:
	var field := HeightField.new(course, params)
	var rests_on_slope := 0
	var drops := 0
	var max_grad := 0.0
	for xi: int in range(40, 121, 5):
		for yi: int in [30, 55]:
			var p := Vector2(xi / 10.0, yi / 10.0)
			var ball := Ball.new(course, 1, params)
			ball.start_roll(_yd(p), Vector2.ZERO)
			ball.run_to_rest()
			var g := field.gradient_at(ball.position.x, ball.position.y).length()
			drops += 1
			if g > 0.01:
				rests_on_slope += 1
				max_grad = maxf(max_grad, g)
	print("== still balls dropped on the green: %d, at rest on a slope > 1%%: %d (max %.0f%%)" % [
		drops, rests_on_slope, max_grad * 100.0])


func _hill_shots(params: BallParams) -> void:
	print("== hillside shots (25 yd/s, 30 deg; flat carry for reference)")
	var flat := CourseData.create(HILL_W, HILL_H, Surface.Type.FAIRWAY, 0)
	var c := hillside()
	var v_up := Ball.launch_velocity(25.0, 30.0, 0.0)
	var v_down := Ball.launch_velocity(25.0, 30.0, 180.0)
	for row: Dictionary in [
			{"label": "flat     ", "course": flat, "from": Vector2(1, 3), "v": v_up},
			{"label": "up 1/2   ", "course": c, "from": Vector2(1, 3), "v": v_up},
			{"label": "up 1/1   ", "course": c, "from": Vector2(4, 8), "v": v_up},
			{"label": "down 1/2 ", "course": c, "from": Vector2(25, 3), "v": v_down},
			{"label": "down 1/1 ", "course": c, "from": Vector2(25, 8), "v": v_down}]:
		var course: CourseData = row["course"]
		var f := HeightField.new(course, params)
		var start2 := _yd(row["from"])
		var start := Vector3(start2.x, start2.y, f.height_at(start2.x, start2.y))
		var p := ShotPrediction.run(course, 1, start, row["v"], params)
		var land_g := f.gradient_at(p.landing.x, p.landing.y)
		print("   %s from %s: lands tile %s (z %.1f steps, ground slope %.0f%%), rests tile %s (z %.1f steps), carry %.1f yd" % [
			row["label"], row["from"], p.landing_tile, p.landing.z / params.yards_per_step,
			land_g.length() * 100.0, p.rest_tile, p.rest.z / params.yards_per_step,
			Vector2(p.landing.x - start.x, p.landing.y - start.y).length()])
