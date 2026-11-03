class_name GridHeightEvidence
extends SceneTree
## Evidence for E1-S9 (D4, D5 in docs/DECISIONS.md): two courses and a set of putts and shots
## across them, run through the real Ball. Prints one line per shot. Screenshots of the same
## courses come from tests/fixtures/grid_height_shot.tscn. The E1-S9 sections run with the
## green's E1-S11 slope columns reset to 1.0, so they still show the unscaled green D5 judged;
## the E1-S11 section runs the table as built.
##
##   godot --headless --path . -s res://tests/fixtures/grid_height_evidence.gd

const GREEN_W: int = 16
const GREEN_H: int = 12
const HILL_W: int = 28
const HILL_H: int = 12
const RAMP_W: int = 24
const RAMP_H: int = 12


func _initialize() -> void:
	var params := BallParams.load_default()
	print("== slope between two tile centres one step apart: %.0f%% (%.1f deg)" % [
		100.0 * params.yards_per_step / params.yards_per_tile,
		rad_to_deg(atan(params.yards_per_step / params.yards_per_tile))])
	var built := SurfaceTable.load_default()
	var unscaled: SurfaceTable = built.duplicate(true)
	var g := unscaled.row(Surface.Type.GREEN)
	g.slope_scale = 1.0
	g.rest_decel_scale = 1.0
	g.drag_scale = 1.0
	print("== E1-S9: green unscaled (slope_scale, rest_decel_scale, drag_scale all 1)")
	_putts("green contour, 2.0 yd per step", green_contour(), params, unscaled)
	var gentle := params.duplicate() as BallParams
	gentle.yards_per_step = 0.15
	_putts("green contour, 0.15 yd per step (3% between centres; what-if only)", green_contour(), gentle, unscaled)
	_rest_on_slope(green_contour(), params, unscaled)
	_hill_shots(params)
	var row := built.row(Surface.Type.GREEN)
	print("== E1-S11: green as built (slope_scale %.3f, rest_decel_scale %.3f, decel_ramp_speed %.1f yd/s, drag_scale %.2f)" % [
		row.slope_scale, row.rest_decel_scale, row.decel_ramp_speed, row.drag_scale])
	_putts("green contour, 2.0 yd per step, scaled green", green_contour(), params, built)
	_sidehill_break(green_contour(), params, built)
	_slow_balls(green_contour(), params, built)
	_still_on_steps(green_contour(), params, built)
	_rest_on_slope(green_contour(), params, built)
	print("== E1-S12 (D7): a green holds a slow ball on a gentle felt slope; target: every green ball settles in under 8 s")
	_ramp_balls(params, built)
	for mirrored: bool in [false, true]:
		_settle("green contour" + (" mirrored" if mirrored else ""), green_contour(mirrored),
				params, built,
				[22.5, 25.0, 28.0, 30.0, 32.0, 35.0, 38.0, 40.0, 42.0, 45.0, 48.0, 50.0, 52.0, 55.0],
				[12.5, 27.5, 47.5])
	_settle("green ramp", green_ramp(), params, built,
			[20.0, 22.5, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 57.5, 60.0], [10.0, 30.0, 50.0])
	print("== E2-S4 (D16): a green bank steeper than steep_from %.2f is felt as steep (steep_scale %.2f); target: under 8 s" % [
		row.steep_from, row.steep_scale])
	for per_tile: int in [2, 3]:
		_steep_bank(per_tile, params, built)
	quit(0)


## E2-S4: an all-green plot rising `per_tile` steps per tile along +x from height 0 at tile
## 2 (x 12.5 yd, the foot) to 7. Still balls up the bank and short uphill putts from x 10.
func _steep_bank(per_tile: int, params: BallParams, table: SurfaceTable) -> void:
	var c := CourseData.create(40, 40, Surface.Type.GREEN, 0)
	for y: int in 40:
		for x: int in 40:
			c.set_tile(x, y, clampi((x - 2) * per_tile, 0, 7), Surface.Type.GREEN)
	var top := 12.5 + 5.0 * ceili(7.0 / per_tile)
	var worst := 0
	var at := 0.0
	var rest := 0.0
	var x := 12.5
	while x <= top:
		var ball := Ball.new(c, 1, params, table)
		ball.start_roll(Vector2(x, 100.0), Vector2.ZERO)
		ball.run_to_rest()
		if ball.steps > worst:
			worst = ball.steps
			at = x
			rest = ball.position.x
		x += 0.5
	print("== green bank, %d steps per tile (foot x 12.5, top x %.1f): longest still ball %.1f s, set at x %.1f, rests x %.2f" % [
		per_tile, top, worst / 60.0, at, rest])
	for speed: float in [4.0, 5.0, 6.0, 7.0]:
		var ball := Ball.new(c, 1, params, table)
		ball.record_path = true
		ball.start_roll(Vector2(10.0, 100.0), Vector2(speed, 0.0))
		ball.run_to_rest()
		var furthest := 0.0
		for p in ball.path:
			furthest = maxf(furthest, p.x)
		print("   uphill %3.1f yd/s from x 10: furthest x %.2f, rests x %.2f in %.1f s" % [
			speed, furthest, ball.position.x, ball.steps / 60.0])


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


## E1-S12: an all-green plot rising one step per tile along +x from 0 to 7: flat at 0 for
## tiles x 0 to 4, then heights 1 to 7 at tiles 5 to 11, flat at 7 after. The slope runs
## from x 22.5 to 57.5 yd, felt on green as an even 3%.
static func green_ramp() -> CourseData:
	var c := CourseData.create(RAMP_W, RAMP_H, Surface.Type.GREEN, 0)
	for y: int in RAMP_H:
		for x: int in RAMP_W:
			c.set_tile(x, y, clampi(x - 4, 0, 7), Surface.Type.GREEN)
	c.set_info("E1-S12 green ramp", "tests", "")
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


func _putts(label: String, course: CourseData, params: BallParams, table: SurfaceTable) -> void:
	print("== putts: %s" % label)
	print("   tiers: x 4-5 h0, 6-7 h1, 8-9 h2, 10-11 h3; tile 5 yd; green x 4..11")
	# Uphill from the front tier centre (tile 4.5, 5.5) along +x, and downhill from the back.
	for speed: float in [3.0, 5.0, 7.0, 9.0, 11.0]:
		_putt(course, params, table, "uphill  ", Vector2(4.5, 5.5), Vector2(speed, 0.0))
	for speed: float in [1.0, 3.0, 5.0]:
		_putt(course, params, table, "downhill", Vector2(10.5, 5.5), Vector2(-speed, 0.0))
	# Sidehill: along +y across the slope band between tier 0 and tier 1 (tile x 5.5).
	for speed: float in [3.0, 5.0]:
		_putt(course, params, table, "sidehill", Vector2(5.5, 2.5), Vector2(0.0, speed))
	# Reference: the same speeds on a flat green.
	var flat := CourseData.create(GREEN_W, GREEN_H, Surface.Type.GREEN, 0)
	for speed: float in [3.0, 5.0, 7.0, 9.0, 11.0]:
		_putt(flat, params, table, "flat    ", Vector2(1.5, 5.5), Vector2(speed, 0.0))


func _putt(course: CourseData, params: BallParams, table: SurfaceTable, kind: String,
		from_tile: Vector2, v: Vector2) -> void:
	var ball := Ball.new(course, 1, params, table)
	ball.start_roll(_yd(from_tile), v)
	var ticks := ball.run_to_rest()
	var end := ball.position
	var travel := Vector2(end.x, end.y) - _yd(from_tile)
	print("   %s %4.1f yd/s from tile %s -> rest tile (%.2f, %.2f) on %s, moved (%.1f, %.1f) yd in %.1f s" % [
		kind, v.length(), from_tile, end.x / 5.0 - 0.5, end.y / 5.0 - 0.5,
		Surface.name_of(ball.field.surface_at(end.x, end.y)), travel.x, travel.y, ticks / 60.0])


## Drops a still ball at many points on the contour green and records where any comes to rest
## on ground steeper than 1%.
func _rest_on_slope(course: CourseData, params: BallParams, table: SurfaceTable) -> void:
	var field := HeightField.new(course, params)
	var rests_on_slope := 0
	var drops := 0
	var max_grad := 0.0
	for xi: int in range(40, 121, 5):
		for yi: int in [30, 55]:
			var p := Vector2(xi / 10.0, yi / 10.0)
			var ball := Ball.new(course, 1, params, table)
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


## Sidehill putts along +y through the middle of the tier 0 to 1 slope band. Prints the
## sideways offset when the forward speed drops under rest speed (the putt's full length) and
## where the ball rests. Since E1-S12 (D7) the break is read at rest.
func _sidehill_break(course: CourseData, params: BallParams, table: SurfaceTable) -> void:
	print("== sidehill break (from tile (5.5, 2.5), mid-band, along +y); D7 reads the break at rest")
	for speed: float in [2.0, 3.0, 4.0, 5.0]:
		var from := _yd(Vector2(5.5, 2.5))
		var ball := Ball.new(course, 1, params, table)
		ball.start_roll(from, Vector2(0.0, speed))
		var at := Vector2.ZERO
		var t := 0
		while not ball.is_at_rest():
			ball.step()
			if t == 0 and ball.velocity.y < params.rest_speed:
				t = ball.steps
				at = Vector2(ball.position.x, ball.position.y) - from
		var end := Vector2(ball.position.x, ball.position.y) - from
		print("   %3.1f yd/s: out of pace %.2f yd on, %.2f yd down at %.1f s; rests %.2f yd down (the break), %.2f yd on, at %.1f s" % [
			speed, at.y, -at.x, t / 60.0, -end.x, end.y, ball.steps / 60.0])


## Slow balls on a step: short uphill putts that stop on the slope, and slow balls rolled down.
func _slow_balls(course: CourseData, params: BallParams, table: SurfaceTable) -> void:
	print("== slow balls on the tier 0 to 1 step (slope band x 27.5 to 32.5 yd, y 27.5)")
	var flat := CourseData.create(GREEN_W, GREEN_H, Surface.Type.GREEN, 0)
	_putt(flat, params, table, "flat    ", Vector2(1.5, 5.5), Vector2(4.0, 0.0))
	for speed: float in [4.0, 5.0, 6.0, 7.0]:
		var ball := Ball.new(course, 1, params, table)
		ball.record_path = true
		ball.start_roll(Vector2(22.5, 27.5), Vector2(speed, 0.0))
		ball.run_to_rest()
		var top := 0.0
		for p in ball.path:
			top = maxf(top, p.x)
		print("   uphill   %3.1f yd/s from x 22.5: furthest x %.2f, rests x %.2f (%s) in %.1f s" % [
			speed, top, ball.position.x, "rolled back" if ball.position.x < top - 0.05 else "stayed",
			ball.steps / 60.0])
	for speed: float in [0.2, 0.5, 1.0]:
		var ball := Ball.new(course, 1, params, table)
		ball.start_roll(Vector2(32.0, 27.5), Vector2(-speed, 0.0))
		ball.run_to_rest()
		print("   downhill %3.1f yd/s from x 32.0: rests x %.2f in %.1f s" % [
			speed, ball.position.x, ball.steps / 60.0])


## Still balls set down across each green step's slope band.
func _still_on_steps(course: CourseData, params: BallParams, table: SurfaceTable) -> void:
	print("== still balls set down on each green step's slope (y 27.5)")
	var field := HeightField.new(course, params)
	for band: int in 3:
		var lower := 27.5 + 10.0 * band
		var line := "   step %d (x %.1f to %.1f):" % [band + 1, lower, lower + 5.0]
		for into: float in [0.5, 2.5, 4.5]:
			var ball := Ball.new(course, 1, params, table)
			ball.start_roll(Vector2(lower + into, 27.5), Vector2.ZERO)
			ball.run_to_rest()
			var flat := field.gradient_at(ball.position.x, ball.position.y).length() < 0.001
			line += " from x %.1f -> x %.2f (%s, %.1f s);" % [lower + into, ball.position.x,
					"flat shelf" if flat else "on slope", ball.steps / 60.0]
		print(line)


## E1-S12: the longest settle over still balls and putts of 1 to 15 yd/s along the four axes
## and the four diagonals, from starts across the green (yards). The same grids as
## tests/test_ball.gd. The 8 s target is for balls that rest on green; a ball that runs off
## the green is reported apart (rough physics, docs/design.md Ball known limit).
func _settle(label: String, course: CourseData, params: BallParams, table: SurfaceTable,
		xs: Array, ys: Array) -> void:
	var worst := {true: 0, false: 0}
	var what := {true: "none", false: "none"}
	var count := {true: 0, false: 0}
	var capped := 0
	var runs := 0
	var still_worst := 0
	for x: float in xs:
		for y: float in ys:
			for speed: int in range(0, 16):
				for i: int in 8:
					if speed == 0 and i > 0:
						continue
					var v := Vector2.RIGHT.rotated(i * PI / 4.0) * speed
					var ball := Ball.new(course, 1, params, table)
					ball.start_roll(Vector2(x, y), v)
					ball.run_to_rest()
					runs += 1
					if ball.steps >= params.max_steps:
						capped += 1
					if speed == 0:
						still_worst = maxi(still_worst, ball.steps)
					var s := ball.field.surface_at(ball.position.x, ball.position.y)
					var on_green := s == Surface.Type.GREEN
					count[on_green] += 1
					if ball.steps > worst[on_green]:
						worst[on_green] = ball.steps
						what[on_green] = "from (%.1f, %.1f) at (%.1f, %.1f), rests (%.2f, %.2f) on %s" % [
								x, y, v.x, v.y, ball.position.x, ball.position.y, Surface.name_of(s)]
	print("== settle time, %s: %d runs, longest still ball %.1f s, at the cap %d" % [
		label, runs, still_worst / 60.0, capped])
	print("   resting on green (%d): longest %.1f s (%s)" % [count[true], worst[true] / 60.0, what[true]])
	print("   ran off green (%d): longest %.1f s (%s)" % [count[false], worst[false] / 60.0, what[false]])


## E1-S12: still balls and slow balls on the one-step-per-tile green ramp.
func _ramp_balls(params: BallParams, table: SurfaceTable) -> void:
	print("== green ramp, one step per tile 0 to 7 (slope x 22.5 to 57.5 yd, y 30)")
	var course := green_ramp()
	var line := "   still:"
	for x: float in [25.0, 35.0, 45.0, 55.0]:
		var ball := Ball.new(course, 1, params, table)
		ball.start_roll(Vector2(x, 30.0), Vector2.ZERO)
		ball.run_to_rest()
		line += " x %.1f -> x %.2f (%.1f s);" % [x, ball.position.x, ball.steps / 60.0]
	print(line)
	for speed: float in [3.0, 6.0, 9.0, 12.0, 15.0]:
		for dir: float in [1.0, -1.0]:
			var from := Vector2(40.0, 30.0)
			var ball := Ball.new(course, 1, params, table)
			ball.start_roll(from, Vector2(speed * dir, 0.0))
			ball.run_to_rest()
			print("   %s %4.1f yd/s from x 40: rests x %.2f in %.1f s" % [
				"uphill  " if dir > 0.0 else "downhill", speed, ball.position.x, ball.steps / 60.0])
