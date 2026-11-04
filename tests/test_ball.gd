extends GutTest
## E1-S6: the ball is a custom 3D step at 60 Hz over the height map (D1).
## Units are yards: x and y on the ground from the map's corner, z up.

const EPS := 0.001
## docs/design.md Ball, Settle targets (E2-S1, D16), in ticks: a ball that rests on green,
## and one that rests on fairway, tee, rough or cart path (also a putt that runs off).
const GREEN_SETTLE := 480
const OFF_GREEN_SETTLE := 600
## The slowest putt that must climb a steep green tier (test_putts_climb_a_steep_green_tier):
## below the putter's top speed (18 yd/s since E2-S5) and about main's 14 yd/s from 7.5 yd.
const PUTT_CLIMB_MAX := 15.0


func _flat(surface: Surface.Type = Surface.Type.FAIRWAY, size: int = 40, h: int = 0) -> CourseData:
	return CourseData.create(size, size, surface, h)


func _run(course: CourseData, start: Vector3, velocity: Vector3, seed_value: int = 7,
		surfaces: SurfaceTable = null) -> Ball:
	var ball := Ball.new(course, seed_value, null, surfaces)
	ball.record_path = true
	ball.launch(start, velocity)
	ball.run_to_rest()
	return ball


# --- resources ---

func test_tunables_come_from_resources() -> void:
	var params := BallParams.load_default()
	assert_not_null(params, "golf/ball_params.tres loads")
	assert_gt(params.gravity, 0.0)
	assert_eq(params.yards_per_tile, 5.0, "grid is 5 yards per tile")
	assert_gt(params.yards_per_step, 0.0)
	var table := SurfaceTable.load_default()
	assert_not_null(table, "course/surfaces.tres loads")
	assert_eq(table.validate(), PackedStringArray(), "a row for every surface, in enum order")
	assert_eq(table.row(Surface.Type.BUNKER).roll, 0.0, "bunker roll 0 per design.md")
	assert_eq(table.row(Surface.Type.GREEN).roll, 1.4, "green roll 1.4 per design.md")
	assert_eq(table.row(Surface.Type.CART_PATH).roll, 1.6, "cart path roll 1.6 per design.md")


func test_steps_at_60_hz() -> void:
	assert_eq(Ball.TICK_HZ, 60)
	var ball := Ball.new(_flat(), 1)
	var p0 := Vector3(50, 50, 0)
	var v0 := Vector3(30, 0, 20)
	ball.launch(p0, v0)
	ball.step()
	var dt := 1.0 / 60.0
	var g := ball.params.gravity
	var expected := p0 + v0 * dt + Vector3(0, 0, -0.5 * g * dt * dt)
	assert_almost_eq(ball.position, expected, Vector3.ONE * 1e-5, "one tick of a parabola")
	assert_eq(ball.steps, 1)


# --- height map ---

func test_height_interpolated_between_tiles() -> void:
	var course := _flat(Surface.Type.FAIRWAY, 4)
	for y in 4:
		course.set_tile(1, y, 2, Surface.Type.FAIRWAY)
		course.set_tile(2, y, 2, Surface.Type.FAIRWAY)
	var params := BallParams.load_default()
	var field := HeightField.new(course, params)
	var s := params.yards_per_step
	assert_almost_eq(field.height_at(2.5, 7.5), 0.0, EPS, "tile 0 centre")
	assert_almost_eq(field.height_at(7.5, 7.5), 2.0 * s, EPS, "tile 1 centre")
	assert_almost_eq(field.height_at(5.0, 7.5), 1.0 * s, EPS, "halfway between centres")
	assert_almost_eq(field.height_at(3.75, 7.5), 0.5 * s, EPS, "a quarter of the way")
	assert_almost_eq(field.height_at(10.0, 7.5), 2.0 * s, EPS, "between two equal tiles")
	assert_almost_eq(field.height_at(-3.0, 7.5), 0.0, EPS, "off the edge holds the edge height")
	# Continuous: no step at tile borders, unlike the raw tile grid.
	assert_almost_eq(field.height_at(4.999, 7.5), field.height_at(5.001, 7.5), 0.01)
	# Gradient: rises 2 steps over one tile between the centres, flat along y.
	var grad := field.gradient_at(5.0, 7.5)
	assert_almost_eq(grad.x, 2.0 * s / params.yards_per_tile, EPS)
	assert_almost_eq(grad.y, 0.0, EPS)
	assert_almost_eq(field.normal_at(2.0, 2.0), Vector3(0, 0, 1), Vector3.ONE * EPS, "flat normal is up")


# --- flight ---

func test_gravity_flight_matches_parabola_on_flat() -> void:
	var ball := _run(_flat(), Vector3(10, 100, 0), Vector3(30, 0, 20))
	var g := ball.params.gravity
	var t := 2.0 * 20.0 / g
	assert_true(ball.has_landed)
	assert_almost_eq(ball.landing_position.x, 10.0 + 30.0 * t, 0.01, "carry matches the analytic parabola")
	assert_almost_eq(ball.landing_position.y, 100.0, EPS)
	assert_almost_eq(ball.landing_position.z, 0.0, EPS)
	var apex := 0.0
	for p in ball.path:
		apex = maxf(apex, p.z)
	assert_almost_eq(apex, 20.0 * 20.0 / (2.0 * g), 0.05, "apex height")


func test_one_bounce_then_roll_to_rest() -> void:
	var ball := _run(_flat(), Vector3(10, 100, 0), Vector3(30, 0, 20))
	assert_eq(ball.state, Ball.State.AT_REST)
	assert_eq(ball.bounces, 1, "exactly one bounce")
	assert_gt(ball.position.x, ball.landing_position.x, "the ball moves on after landing")
	assert_almost_eq(ball.position.z, 0.0, EPS, "rests on the ground")
	assert_lt(ball.steps, ball.params.max_steps, "came to rest on its own")


func test_bounce_and_roll_by_surface() -> void:
	var start := Vector3(10, 100, 0)
	var v := Vector3(30, 0, 15)
	var travel := {}
	for s: Surface.Type in [Surface.Type.ROUGH, Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.CART_PATH]:
		var ball := _run(_flat(s), start, v)
		travel[s] = ball.position.x - ball.landing_position.x
	assert_lt(travel[Surface.Type.ROUGH], travel[Surface.Type.FAIRWAY], "rough stops sooner than fairway")
	assert_lt(travel[Surface.Type.FAIRWAY], travel[Surface.Type.GREEN], "green runs further than fairway")
	assert_lt(travel[Surface.Type.GREEN], travel[Surface.Type.CART_PATH], "cart path runs furthest")
	var bunker := _run(_flat(Surface.Type.BUNKER), start, v)
	assert_eq(bunker.bounces, 0, "bunker takes no bounce")
	assert_eq(bunker.position, bunker.landing_position, "bunker stops the ball where it lands")


func test_friction_is_read_from_the_resource() -> void:
	var start := Vector2(10, 100)
	var normal := Ball.new(_flat(), 7)
	normal.start_roll(start, Vector2(10, 0))
	normal.run_to_rest()
	var slick: SurfaceTable = SurfaceTable.load_default().duplicate(true)
	slick.row(Surface.Type.FAIRWAY).roll *= 2.0
	var fast := Ball.new(_flat(), 7, null, slick)
	fast.start_roll(start, Vector2(10, 0))
	fast.run_to_rest()
	var d_normal := normal.position.x - start.x
	var d_fast := fast.position.x - start.x
	# Deceleration (a + k v) / roll stops a ball from v0 in (v0 - (a / k) ln(1 + k v0 / a)) / k
	# at roll 1; doubling roll doubles the distance.
	var a := normal.params.roll_decel
	var k := normal.params.roll_drag * normal.surfaces.row(Surface.Type.FAIRWAY).drag_scale
	var expected := (10.0 - (a / k) * log(1.0 + k * 10.0 / a)) / k
	assert_almost_eq(d_normal, expected, 0.3, "distance from the table's friction")
	assert_almost_eq(d_fast / d_normal, 2.0, 0.1, "double roll factor rolls twice as far")
	assert_eq(SurfaceTable.load_default().row(Surface.Type.FAIRWAY).roll, 1.0, "the shared table is untouched")


# --- slopes ---

## Heights rise one step per tile along +x, to 7: an even slope from x = 2.5 to 37.5 yards.
func _ramp() -> CourseData:
	var course := _flat(Surface.Type.FAIRWAY, 40)
	for y in 40:
		for x in 40:
			course.set_tile(x, y, mini(x, 7), Surface.Type.FAIRWAY)
	return course


func test_roll_downhill_further_than_uphill() -> void:
	var course := _ramp()
	var start := Vector2(20, 100)
	var up := Ball.new(course, 3)
	up.record_path = true
	up.start_roll(start, Vector2(10, 0))
	up.run_to_rest()
	var down := Ball.new(course, 3)
	down.start_roll(start, Vector2(-10, 0))
	down.run_to_rest()
	var up_dist := 0.0
	for p in up.path:
		up_dist = maxf(up_dist, p.x - start.x)
	var down_dist := start.x - down.position.x
	assert_gt(up_dist, 0.0, "the uphill ball climbs before it stops")
	assert_gt(down_dist, up_dist + 2.0, "the slope carries the ball further downhill")
	assert_almost_eq(down.position.z, HeightField.new(course, down.params).height_at(down.position.x, down.position.y),
			EPS, "a rolling ball stays on the ground")


func test_roll_across_a_slope_drifts_downhill() -> void:
	var course := _ramp()
	var ball := Ball.new(course, 3)
	ball.start_roll(Vector2(20, 60), Vector2(0, 15))
	ball.run_to_rest()
	assert_gt(ball.position.y, 65.0, "rolled forward")
	assert_lt(ball.position.x, 19.0, "and broke down the slope")


## The ramp from _ramp(), on green.
func _green_ramp() -> CourseData:
	var course := _ramp()
	for y in 40:
		for x in 40:
			course.set_tile(x, y, course.get_height(x, y), Surface.Type.GREEN)
	return course


## Felt pull on a slope rising `steps` height steps per tile, on the surface of `row`.
func _step_pull(params: BallParams, row: SurfaceRow, steps: float) -> float:
	var terrain := Vector2(steps * params.yards_per_step / params.yards_per_tile, 0.0)
	var grad := Ball.felt_gradient(terrain, row).x
	return params.gravity * grad / (1.0 + grad * grad)


## Constant friction that holds a still ball on the surface of `row`.
func _hold(params: BallParams, row: SurfaceRow) -> float:
	return params.roll_decel * row.rest_decel_scale / row.roll


func test_slope_pull_beats_rest_friction() -> void:
	# A design guard: off the green, the one-step pull must beat the constant friction that
	# holds a still ball on every rolling surface, or balls never start down a slope. The
	# green holds a ball on a gentle slope by design (D7, next test). Trees have roll 0 since
	# E2-S6: no ball rolls on them, it stops at their edge (D15).
	var params := BallParams.load_default()
	var table := SurfaceTable.load_default()
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.TEE, Surface.Type.CART_PATH]:
		var row := table.row(s)
		assert_gt(_step_pull(params, row, 1.0), _hold(params, row),
				"a one-step slope moves a still ball on %s" % Surface.NAMES[s])


func test_green_holds_a_ball_on_a_gentle_slope_only() -> void:
	# E1-S12 (D7): a green holds a slow ball on a gentle felt slope, as a real green holds a
	# ball on about 3%. One step per tile is felt as 3% and holds; two steps per tile (6%)
	# must still move a still ball, so steeper greens roll down and short putts roll back.
	var params := BallParams.load_default()
	var green := SurfaceTable.load_default().row(Surface.Type.GREEN)
	assert_gt(_hold(params, green), _step_pull(params, green, 1.0),
			"a one-step green slope holds a still ball")
	assert_lt(_hold(params, green), _step_pull(params, green, 2.0),
			"a two-steps-per-tile green slope does not")


## A green rising `per_tile` steps per tile along +x from height 0 at tile `from`, up to 7.
func _steep_green(per_tile: int, from: int) -> CourseData:
	var course := _flat(Surface.Type.GREEN, 40)
	for y in 40:
		for x in 40:
			course.set_tile(x, y, clampi((x - from) * per_tile, 0, 7), Surface.Type.GREEN)
	return course


func test_ball_at_rest_on_a_gentle_green_slope_stays() -> void:
	# E1-S12 (D7): the E1-S6 test's original x 20 start on the one-step-per-tile green ramp
	# (felt as 3%). The green holds the ball where it is set, at once.
	var ball := Ball.new(_green_ramp(), 3)
	ball.start_roll(Vector2(20, 100), Vector2.ZERO)
	ball.run_to_rest()
	assert_almost_eq(ball.position.x, 20.0, EPS, "a green holds a ball on a 3% felt slope")
	assert_lte(ball.steps, 1, "and rests on the first tick")


func test_ball_at_rest_on_a_green_slope_rolls_down() -> void:
	# The same x 20 start on a green rising two steps per tile (felt as 6%; heights 0, 2, 4,
	# 6, 7 from tile 2, so the 6% band runs x 12.5 to 27.5): the ball runs down to the foot.
	var ball := Ball.new(_steep_green(2, 2), 3)
	ball.start_roll(Vector2(20, 100), Vector2.ZERO)
	ball.run_to_rest()
	assert_lt(ball.position.x, 13.0, "a ball set down on a steeper green slope runs down it")
	# E2-S4: it used to trickle for about 42 s; a green now feels a bank this steep as steep.
	assert_lt(ball.steps, GREEN_SETTLE, "within the green settle target (%d ticks)" % ball.steps)


func test_ball_rolling_downhill_on_green_speeds_up() -> void:
	# Green feels slope_scale of the slope (E1-S11), so a one-step ramp is a 3% break whose
	# pull only keeps a slow ball trickling. A three-steps-per-tile green (120%, felt as 9%)
	# pulls hard enough to speed a 0.5 yd/s ball up. Heights 0, 3, 6, 7 from x = 10.
	var ball := Ball.new(_steep_green(3, 10), 3)
	ball.start_roll(Vector2(62, 100), Vector2(-0.5, 0))
	for i in 30:
		ball.step()
	assert_eq(ball.state, Ball.State.ROLLING)
	assert_gt(Vector2(ball.velocity.x, ball.velocity.y).length(), 0.5, "gathers speed going down")


func test_uphill_putt_that_stops_short_rolls_back() -> void:
	# E1-S12 (D7): a one-step-per-tile green now holds a ball that stops on it (see the
	# contour test below), so this putt runs up a two-steps-per-tile green (felt as 6%,
	# foot at x 12.5), which does not hold it.
	var course := _steep_green(2, 2)
	var start := Vector2(10, 100)
	var ball := Ball.new(course, 3)
	ball.record_path = true
	# E2-S4: 7 yd/s, not 5, since the steep bank now takes a 5 yd/s putt only 0.7 yd up it.
	ball.start_roll(start, Vector2(7, 0))
	ball.run_to_rest()
	var furthest := start.x
	for p in ball.path:
		furthest = maxf(furthest, p.x)
	assert_gt(furthest, 13.5, "went up the slope")
	assert_lt(furthest, 27.5, "but not over the top")
	assert_lt(ball.position.x, 13.0, "and came back down to the foot")
	assert_lt(ball.steps, GREEN_SETTLE, "within the green settle target (%d ticks)" % ball.steps)


## A 5x5 plot at height 1 with a one-tile pit at height 0 in the middle, tile (2, 2), whose
## centre is (12.5, 12.5) yd. The slope pull jumps across the pit's centre.
func _pit(surface: Surface.Type) -> CourseData:
	var course := _flat(surface, 5, 1)
	course.set_tile(2, 2, 0, surface)
	return course


func test_still_ball_in_a_one_tile_pit_rests_near_the_centre() -> void:
	# E1-S13: it used to rock across the centre until the 60 s cap. "Just off" is within
	# 0.04 yd. Since E1-S12 (D7) the green holds a still ball on the pit's walls, which it
	# feels as 3%, so on green the ball rests where it is set.
	var centre := Vector2(12.5, 12.5)
	for s: Surface.Type in [Surface.Type.GREEN, Surface.Type.FAIRWAY]:
		for off: Vector2 in [Vector2(0.04, 0.0), Vector2(-0.03, 0.02), Vector2(0.0, -0.04)]:
			var ball := Ball.new(_pit(s), 1)
			ball.start_roll(centre + off, Vector2.ZERO)
			ball.run_to_rest()
			var label := "%s, set %s off the centre" % [Surface.NAMES[s], off]
			assert_lte(ball.steps, Ball.TICK_HZ, "%s: rests within 1 s (%d ticks)" % [label, ball.steps])
			assert_lt(Vector2(ball.position.x, ball.position.y).distance_to(centre), 0.1,
					"%s: rests near the centre" % label)


## A 7x8 plot with a one-tile gully down column 3 (floor line x = 17.5 yd): the floor rises
## one step per tile from height 0 at row 0 to 4 at row 4, then is flat; the walls either
## side stand `wall` steps above it. The floor is lowest, and flat along y, for y <= 2.5 yd.
func _gully(surface: Surface.Type, wall: int) -> CourseData:
	var course := CourseData.create(7, 8, surface, 0)
	for j in 8:
		var floor_h: int = mini(j, 4)
		for i in 7:
			course.set_tile(i, j, floor_h if i == 3 else floor_h + wall, surface)
	return course


func test_still_ball_in_a_sloping_gully_does_not_rest_mid_slope() -> void:
	# E1-S13 review: the gradient flips across the gully's floor line, but the floor itself
	# still slopes, pulling 3.7 yd/s² along it (more than rough's 2.5 hold). Only the cross
	# axis is at a low point, so the ball must go on down, not rest where it crosses the line.
	for s: Surface.Type in [Surface.Type.ROUGH, Surface.Type.FAIRWAY]:
		for wall in [2, 3]:
			for start: Vector2 in [Vector2(17.2, 18.0), Vector2(16.5, 18.0), Vector2(17.45, 18.0),
					Vector2(17.5, 18.0)]:
				var ball := Ball.new(_gully(s, wall), 1)
				ball.start_roll(start, Vector2.ZERO)
				ball.run_to_rest()
				var label := "%s, walls %d up, set at %s" % [Surface.NAMES[s], wall, start]
				assert_lt(ball.position.y, start.y - 5.0,
						"%s: more than a tile down the gully (y %.2f)" % [label, ball.position.y])
				if ball.steps < ball.params.max_steps:
					assert_lte(ball.position.y, 3.0,
							"%s: rested on its own only at the flat bottom (y %.2f)" % [label, ball.position.y])
				assert_almost_eq(ball.position.x, 17.5, 0.1, "%s: on the floor line" % label)
	# Fairway rolls all the way down.
	var down := Ball.new(_gully(Surface.Type.FAIRWAY, 2), 1)
	down.start_roll(Vector2(17.2, 18.0), Vector2.ZERO)
	down.run_to_rest()
	assert_lt(down.steps, down.params.max_steps, "fairway: came to rest on its own")
	assert_lte(down.position.y, 3.0, "fairway: at the flat bottom")


func test_flying_ball_meets_hillside_and_lands_there() -> void:
	# Flat at height 0 for tiles x < 10, a 7-step hill from x = 10. The hillside runs
	# between the tile centres at 47.5 and 52.5 yards.
	var course := _flat(Surface.Type.FAIRWAY, 30)
	for y in 30:
		for x in range(10, 30):
			course.set_tile(x, y, 7, Surface.Type.FAIRWAY)
	var start := Vector3(5, 75, 0)
	var v := Vector3(40, 0, 10)
	var open_ground := _run(_flat(Surface.Type.FAIRWAY, 30), start, v)
	assert_gt(open_ground.landing_position.x, 60.0, "without the hill it would carry past it")
	var ball := _run(course, start, v)
	var field := HeightField.new(course, ball.params)
	var hit := ball.landing_position
	assert_between(hit.x, 47.5, 52.5, "lands on the hillside")
	assert_gt(hit.z, 0.5, "part way up the hill, not at its foot")
	assert_almost_eq(hit.z, field.height_at(hit.x, hit.y), EPS, "on the ground, not inside it")
	var below := 0
	for p in ball.path:
		if p.z < field.height_at(p.x, p.y) - EPS:
			below += 1
	assert_eq(below, 0, "never passes through the terrain")


# --- green contours (E1-S11, D5): a one-step green contour putts as a break ---

## Ground point in yards for a fractional tile coordinate as GridHeightEvidence uses it
## (integer = tile centre).
func _yd(tile: Vector2) -> Vector2:
	return (tile + Vector2(0.5, 0.5)) * 5.0


func _putt(course: CourseData, from_tile: Vector2, v: Vector2) -> Ball:
	var ball := Ball.new(course, 1)
	ball.record_path = true
	ball.start_roll(_yd(from_tile), v)
	ball.run_to_rest()
	return ball


func test_green_slope_columns_come_from_the_table() -> void:
	var table := SurfaceTable.load_default()
	var green := table.row(Surface.Type.GREEN)
	assert_between(green.slope_scale, 0.05, 0.1, "a green step feels like a 3% break, not 40%")
	assert_lt(green.rest_decel_scale, 1.0, "a still ball on green is held more lightly")
	for i: int in Surface.COUNT:
		if i == Surface.Type.GREEN:
			continue
		var row := table.row(i)
		assert_eq(row.slope_scale, 1.0, "%s feels the full slope" % row.name)
		assert_eq(row.rest_decel_scale, 1.0, "%s keeps its constant friction" % row.name)
		assert_eq(row.steep_scale, 0.0, "%s has no steep-bank term" % row.name)
	# E2-S4: the steep term starts above every one-step contour, corners included (0.4 x
	# sqrt 2 per axis is still 0.4), and below two steps per tile (0.8).
	assert_gt(green.steep_scale, 0.0, "a green feels a steep bank as steep")
	assert_between(green.steep_from, 0.4, 0.8, "from between one and two steps per tile")


func test_flat_green_4_yds_putt_runs_about_3_7_yd() -> void:
	var ball := _putt(CourseData.create(16, 12, Surface.Type.GREEN, 0), Vector2(1.5, 5.5), Vector2(4, 0))
	assert_almost_eq(ball.position.x - _yd(Vector2(1.5, 5.5)).x, 3.7, 0.2, "docs/design.md Ball")


func test_contour_uphill_9_yds_ends_near_its_flat_distance() -> void:
	var from := Vector2(4.5, 5.5)
	var flat := _putt(CourseData.create(16, 12, Surface.Type.GREEN, 0), from, Vector2(9, 0))
	var up := _putt(GridHeightEvidence.green_contour(), from, Vector2(9, 0))
	var flat_d := flat.position.x - _yd(from).x
	var up_d := up.position.x - _yd(from).x
	assert_gt(up_d, 0.0, "goes up the green")
	assert_lt(up_d, flat_d, "the contour costs some distance")
	assert_almost_eq(up_d, flat_d, 1.5, "but only a little: %.2f yd against %.2f flat" % [up_d, flat_d])
	assert_eq(up.field.surface_at(up.position.x, up.position.y), Surface.Type.GREEN)


func test_contour_sidehill_3_yds_breaks_a_little() -> void:
	# Along +y through the middle of the slope band between tier 0 and tier 1 (x 27.5 to
	# 32.5 yd), which falls towards -x. E1-S12 (D7): the break is the sideways offset where
	# the ball comes to rest. The green holds it there: no slide after the putt dies.
	var from := _yd(Vector2(5.5, 2.5))
	var ball := _putt(GridHeightEvidence.green_contour(), Vector2(5.5, 2.5), Vector2(0, 3))
	var brk := from.x - ball.position.x
	assert_gt(ball.position.y - from.y, 2.0, "it rolled forward")
	assert_between(brk, 0.1, 1.0, "a 3 yd/s sidehill putt rests %.2f yd below its line" % brk)
	assert_gt(ball.position.x, 27.5, "held on the step, not slid down to the lower shelf")
	assert_lt(ball.steps, Ball.TICK_HZ * 8, "within the 8 s settle target")


func test_contour_still_ball_on_a_step_is_held() -> void:
	# E1-S12 (D7) replaces the E1-S11 clause "a still ball set down on a step rolls to the
	# shelf below": a one-step green contour is felt as 3%, and a green holds a ball on that.
	var course := GridHeightEvidence.green_contour()
	# Points across each of the three green step bands (x 27.5-32.5, 37.5-42.5, 47.5-52.5).
	for band: int in 3:
		var lower := 27.5 + 10.0 * band
		for into: float in [0.5, 2.5, 4.5]:
			var ball := Ball.new(course, 1)
			ball.start_roll(Vector2(lower + into, 27.5), Vector2.ZERO)
			ball.run_to_rest()
			assert_lte(ball.steps, 1, "set down %.1f yd up step %d, rests at once" % [into, band + 1])
			assert_almost_eq(ball.position.x, lower + into, EPS, "where it was set")


func test_contour_uphill_putt_that_stops_short_on_a_step_stays_there() -> void:
	# E1-S12 (D7): it used to roll back to the front tier in 12 to 35 s. Now the green holds
	# it on the step's 3% felt slope at the point where it runs out of pace.
	var from := Vector2(4.5, 5.5)
	var ball := _putt(GridHeightEvidence.green_contour(), from, Vector2(6, 0))
	var furthest := 0.0
	for p in ball.path:
		furthest = maxf(furthest, p.x)
	assert_between(ball.position.x, 27.5, 32.5, "it stops on the step's slope")
	assert_almost_eq(ball.position.x, furthest, EPS, "and stays there")
	assert_lt(ball.steps, Ball.TICK_HZ * 8, "within the 8 s settle target")


# --- settle time (E1-S12, D7): docs/design.md Ball, the longest green settle is under 8 s ---

## Every start (yards) of `xs` x `ys`.
func _grid(xs: Array, ys: Array) -> Array[Vector2]:
	var starts: Array[Vector2] = []
	for x: float in xs:
		for y: float in ys:
			starts.append(Vector2(x, y))
	return starts


## Longest settle over still balls and putts of 1 to 15 yd/s along the four axes and the four
## diagonals from every start (yards) in `starts`. The 8 s target is for balls that come
## to rest on green ("steps"); a putt that runs off the green and on down the rough's slope
## is held to the off-green target, reported apart ("off_steps", D16).
func _settle_worst(course: CourseData, starts: Array) -> Dictionary:
	var worst := {"steps": 0, "what": "", "off_steps": 0, "off_what": "", "capped": 0}
	var cases: Array[Vector2] = [Vector2.ZERO]
	for speed in range(1, 16):
		for i in 8:
			cases.append(Vector2.RIGHT.rotated(i * PI / 4.0) * speed)
	for p: Vector2 in starts:
		for v: Vector2 in cases:
			var ball := Ball.new(course, 1)
			ball.start_roll(p, v)
			ball.run_to_rest()
			if ball.steps >= ball.params.max_steps:
				worst["capped"] += 1
			var on_green := ball.field.surface_at(ball.position.x, ball.position.y) \
					== Surface.Type.GREEN
			var key := "steps" if on_green else "off_steps"
			if ball.steps > worst[key]:
				worst[key] = ball.steps
				worst["what" if on_green else "off_what"] = "from %s at %s" % [p, v]
	return worst


func test_green_settle_time_on_the_contour() -> void:
	# From the front tier, every step band and every tier of the green, on three lines, on the
	# contour and its mirror. A diagonal putt that runs off the green's y = 50 edge rolls on
	# down the rough's tier slope, so only balls that rest on green are held to 8 s; the rest
	# are held to the off-green 10 s (D16).
	# E2-S16: by default only the starts that set the worst settles on the full grid (on
	# green 329 ticks from x 52, 321 from 55 and 50; off green 362 from (52, 27.5) and 359 to
	# 360 near the y = 10 and y = 50 edges), mirrored at x 80 - x on the mirror, and two
	# starts back across the tiers. The contour is the same along y away from its edges.
	# Sweep.full() (scripts/run_tests.sh --full) runs every start.
	var dense := _grid([22.5, 25.0, 28.0, 30.0, 32.0, 35.0, 38.0, 40.0, 42.0, 45.0, 48.0, 50.0, 52.0, 55.0],
			[12.5, 27.5, 47.5])
	var quick: Array[Vector2] = [Vector2(52.0, 27.5), Vector2(55.0, 12.5), Vector2(50.0, 47.5),
			Vector2(35.0, 27.5), Vector2(22.5, 27.5)]
	for mirrored: bool in [false, true]:
		var starts: Array[Vector2] = dense
		if not Sweep.full():
			starts = []
			for p: Vector2 in quick:
				starts.append(Vector2(80.0 - p.x, p.y) if mirrored else p)
		var w := _settle_worst(GridHeightEvidence.green_contour(mirrored), Sweep.part(starts))
		assert_eq(w["capped"], 0, "no ball reaches max_steps")
		assert_lt(w["steps"], GREEN_SETTLE, "mirrored %s: longest settle on green %.1f s, %s (off green %.1f s, %s)" % [
				mirrored, w["steps"] / 60.0, w["what"], w["off_steps"] / 60.0, w["off_what"]])
		assert_lt(w["off_steps"], OFF_GREEN_SETTLE, "mirrored %s: longest settle off green %.1f s, %s" % [
				mirrored, w["off_steps"] / 60.0, w["off_what"]])


func test_green_settle_time_on_a_one_step_per_tile_ramp() -> void:
	# GridHeightEvidence.green_ramp(): all green, rising one step per tile from 0 to 7.
	# E2-S16: by default the starts of the worst settles on the full grid (337 ticks from x 50
	# to 57.5, 336 from 60, 329 from 45) and a spread down the ramp, which is the same along
	# y. Sweep.full() runs every start.
	var starts: Array[Vector2] = _grid([20.0, 22.5, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 57.5, 60.0],
			[10.0, 30.0, 50.0])
	if not Sweep.full():
		starts = [Vector2(57.5, 30.0), Vector2(60.0, 10.0), Vector2(45.0, 50.0), Vector2(30.0, 30.0),
				Vector2(20.0, 10.0)]
	var w := _settle_worst(GridHeightEvidence.green_ramp(), starts)
	assert_eq(w["capped"], 0, "no ball reaches max_steps")
	assert_lt(w["steps"], Ball.TICK_HZ * 8, "longest settle %.1f s, %s" % [w["steps"] / 60.0, w["what"]])


func test_still_ball_on_a_several_tile_green_ramp_settles_at_once() -> void:
	# E1-S12's still ball on a several-tile one-step-per-tile green ramp, under D7: it used
	# to creep about 10 yd down before the 60 s cap; now the green holds it where it is set.
	var course := GridHeightEvidence.green_ramp()
	for x: float in [25.0, 35.0, 45.0, 55.0]:
		var ball := Ball.new(course, 1)
		ball.start_roll(Vector2(x, 30.0), Vector2.ZERO)
		ball.run_to_rest()
		assert_lt(ball.steps, ball.params.max_steps, "came to rest on its own")
		assert_lte(ball.steps, 1, "at once, on the slope at x %.1f" % x)
		assert_almost_eq(ball.position.x, x, EPS, "where it was set")


func test_green_touchdown_normal_tilt_is_scaled() -> void:
	# Dropped straight down onto the middle of a step band, the bounce kicks downhill by the
	# tilt of the ground normal. On green that tilt is scaled down with the pull.
	var table: SurfaceTable = SurfaceTable.load_default().duplicate(true)
	for r: SurfaceRow in table.rows:
		r.scatter_deg = 0.0
	var kick := {}
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.GREEN]:
		var course := GridHeightEvidence.green_contour()
		for y: int in course.height:
			for x: int in course.width:
				course.set_tile(x, y, course.get_height(x, y), s)
		var ball := Ball.new(course, 1, null, table)
		ball.launch(Vector3(30, 27.5, 6), Vector3(0, 0, -8))
		while ball.bounces == 0 and not ball.is_at_rest():
			ball.step()
		kick[s] = -ball.velocity.x
	assert_gt(kick[Surface.Type.FAIRWAY], 1.0, "fairway kicks the bounce downhill")
	assert_gt(kick[Surface.Type.GREEN], 0.0, "green tilts the same way")
	assert_lt(kick[Surface.Type.GREEN], kick[Surface.Type.FAIRWAY] * 0.15, "by far less")


# --- settle every ball the builder can make (E2-S4, D16) ---
# Each case asserts its ticks against GREEN_SETTLE or OFF_GREEN_SETTLE, counted from the
# first touchdown, the set-down or the putt start (docs/design.md Ball, Settle targets).

## A ball set down at `at` with velocity `v`, run to rest. `record` keeps its path, for the
## tests that read `ball.path` (E6-S14: the sweeps do not, so they skip the allocations).
func _set_down(course: CourseData, at: Vector2, v: Vector2 = Vector2.ZERO, record: bool = false) -> Ball:
	var ball := Ball.new(course, 1)
	ball.record_path = record
	ball.start_roll(at, v)
	ball.run_to_rest()
	return ball


## Ticks from the first touchdown to rest, for a flight from `start` at `v`.
func _ground_ticks(ball: Ball, start: Vector3, v: Vector3) -> int:
	ball.launch(start, v)
	while not ball.has_landed:
		ball.step()
	var landed := ball.steps
	ball.run_to_rest()
	return ball.steps - landed


func test_gradient_at_an_exact_tile_centre_averages_both_sides() -> void:
	var params := BallParams.load_default()
	var field := HeightField.new(_pit(Surface.Type.FAIRWAY), params)
	var step := params.yards_per_step / params.yards_per_tile
	for x: float in [11.0, 12.5, 13.5, 14.0]:
		assert_eq(field.gradient_at(x, 12.5).y, 0.0, "no pull along y on the pit's floor line at x %.1f" % x)
	assert_almost_eq(field.gradient_at(12.5, 12.4).y, -step, EPS, "just before the line: the wall")
	assert_almost_eq(field.gradient_at(12.5, 12.6).y, step, EPS, "just after: the other wall")
	# One step up on one side, level on the other: the mean.
	var ramp := HeightField.new(_ramp(), params)
	assert_almost_eq(ramp.gradient_at(37.5, 20.0).x, 0.5 * step, EPS, "the top of the ramp, tile 7's centre")
	assert_almost_eq(ramp.gradient_at(20.0, 22.5).x, step, EPS, "mid-slope, on a y centre line")


func test_still_ball_on_a_pit_floor_line_rolls_straight_to_the_centre() -> void:
	# E2-S4 (old E2-S10): on y = 12.5 the one-sided gradient pulled a ball along y. Now it
	# runs along x only and rests at the centre.
	for dx: float in [1.0, 1.5, 2.0, -1.0, -2.0]:
		var ball := _set_down(_pit(Surface.Type.FAIRWAY), Vector2(12.5 + dx, 12.5), Vector2.ZERO, true)
		var off := 0.0
		for p in ball.path:
			off = maxf(off, absf(p.y - 12.5))
		assert_eq(off, 0.0, "set %.1f yd out: no move along y" % dx)
		assert_almost_eq(ball.position.x, 12.5, 0.1, "set %.1f yd out: rests at the centre" % dx)


func test_pit_balls_settle_under_the_targets() -> void:
	var centre := Vector2(12.5, 12.5)
	for s: Surface.Type in [Surface.Type.GREEN, Surface.Type.FAIRWAY]:
		var target := GREEN_SETTLE if s == Surface.Type.GREEN else OFF_GREEN_SETTLE
		for r: float in [0.0, 1.0, 1.5, 2.0]:
			for a: int in 16:
				var at := centre + Vector2.RIGHT.rotated(a * PI / 8.0) * r
				var ball := _set_down(_pit(s), at)
				assert_lt(ball.steps, target, "%s pit, set at %s: %d ticks" % [Surface.NAMES[s], at, ball.steps])
				if s == Surface.Type.FAIRWAY:
					assert_lt(Vector2(ball.position.x, ball.position.y).distance_to(centre), 0.1,
							"fairway pit, set at %s: rests at the centre" % at)


func test_gully_floor_balls_reach_the_bottom_under_the_target() -> void:
	# E2-S4 (old E2-S11): a still ball in a rough gully crept 6 to 10 yd until the cap. The
	# floor line rises one step per tile; the walls stand 1 to 3 steps above it.
	for s: Surface.Type in [Surface.Type.ROUGH, Surface.Type.FAIRWAY]:
		for wall: int in [1, 2, 3]:
			for dx: float in [-2.0, -1.5, -1.0, 0.0, 1.0, 1.5, 2.0]:
				for y: float in [12.0, 18.0, 22.0]:
					var ball := _set_down(_gully(s, wall), Vector2(17.5 + dx, y))
					var label := "%s gully, walls %d up, set at (%.1f, %.1f)" % [
							Surface.NAMES[s], wall, 17.5 + dx, y]
					assert_lt(ball.steps, OFF_GREEN_SETTLE, "%s: %d ticks" % [label, ball.steps])
					assert_lte(ball.position.y, 3.0, "%s: at the flat bottom (y %.2f)" % [label, ball.position.y])
					assert_almost_eq(ball.position.x, 17.5, 0.1, "%s: on the floor line" % label)


func test_green_gully_balls_settle_under_the_green_target() -> void:
	# E2-S4 (old E2-S13): balls in a green gully reached the cap at about y 8.2. The floor's
	# one step per tile holds a ball (D7); the steeper walls roll it onto the floor.
	for wall: int in [1, 2, 3]:
		for dx: float in [-2.0, -1.5, -1.0, 0.0, 1.0, 1.5, 2.0]:
			for y: float in [12.0, 18.0, 22.0]:
				var ball := _set_down(_gully(Surface.Type.GREEN, wall), Vector2(17.5 + dx, y))
				assert_lt(ball.steps, GREEN_SETTLE, "green gully, walls %d up, set at (%.1f, %.1f): %d ticks" % [
						wall, 17.5 + dx, y, ball.steps])


func test_still_balls_on_steep_greens_settle_under_the_green_target() -> void:
	# E2-S4 (old E2-S15): on two steps per tile a still ball took about 42 s or reached the
	# cap mid-slope; on three, about 15 s. Every 0.5 yd from the bank's foot to its top.
	for cfg: Vector2i in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 10)]:
		var course := _steep_green(cfg.x, cfg.y)
		var foot := cfg.y * 5.0 + 2.5
		var top := foot + 5.0 * ceili(7.0 / cfg.x)
		var x := foot
		while x <= top:
			var ball := _set_down(course, Vector2(x, 100.0))
			var label := "%d steps per tile, set at x %.1f" % [cfg.x, x]
			assert_lt(ball.steps, GREEN_SETTLE, "%s: %d ticks" % [label, ball.steps])
			x += 0.5


func test_roll_backs_on_steep_greens_settle_under_the_green_target() -> void:
	# E2-S4 (old E2-S18): short uphill putts that rolled back took 8 to 28 s.
	for cfg: Vector2i in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 10)]:
		var course := _steep_green(cfg.x, cfg.y)
		var foot := cfg.y * 5.0 + 2.5
		for speed: float in [4.0, 5.0, 6.0, 7.0]:
			var ball := _set_down(course, Vector2(foot - 2.5, 100.0), Vector2(speed, 0.0), true)
			var furthest := 0.0
			for p in ball.path:
				furthest = maxf(furthest, p.x)
			var label := "%d steps per tile, %.0f yd/s" % [cfg.x, speed]
			assert_gt(furthest, foot, "%s: went up the bank" % label)
			assert_lt(ball.position.x, foot, "%s: and rolled back off it" % label)
			assert_lt(ball.steps, GREEN_SETTLE, "%s: %d ticks" % [label, ball.steps])


func test_off_green_diagonal_putt_settles_under_the_off_green_target() -> void:
	# E2-S1 pinned it (9.6 s, D16): it leaves the contour's y = 50 edge and runs down the
	# rough's tier slope.
	var ball := _set_down(GridHeightEvidence.green_contour(), Vector2(58.1, 34.4), Vector2(-10.6, 10.6))
	assert_eq(ball.field.surface_at(ball.position.x, ball.position.y), Surface.Type.ROUGH, "ran off the green")
	assert_lt(ball.steps, OFF_GREEN_SETTLE, "%d ticks" % ball.steps)


## A V valley along y: a one-tile floor at height 0 down column 10 (floor line x 52.5 yd),
## walls rising one step per tile on both sides up to `depth`, then flat.
func _valley(surface: Surface.Type, depth: int) -> CourseData:
	var course := CourseData.create(21, 12, surface, 0)
	for y: int in 12:
		for x: int in 21:
			course.set_tile(x, y, mini(absi(x - 10), depth), surface)
	return course


func test_still_balls_across_v_valleys_settle_under_the_target() -> void:
	# E2-S4: from up to 18.7 s (rough, 4 steps deep). Every 0.25 yd from rim to rim.
	# E6-S10: 5 to 7 deep too (up to 13.5 s before: downhill_friction_scale and floor_keep).
	# E2-S16: by default the left half only (the valley is symmetric, and so are its settles),
	# every 0.25 yd within 1.5 yd of the rim, where the worst settle starts (on the rim or
	# 0.25 yd in, on the full grid), then every yard down to the floor. Sweep.full() runs
	# every 0.25 yd from rim to rim. E6-S10: 5 to 7 deep by default every 2 yd past the rim
	# (their worst starts within 0.75 yd of it), and tee (fairway's twin) only in full.
	var surfaces: Array = Sweep.pick([Surface.Type.ROUGH, Surface.Type.FAIRWAY, Surface.Type.CART_PATH],
			[Surface.Type.ROUGH, Surface.Type.FAIRWAY, Surface.Type.TEE, Surface.Type.CART_PATH])
	for s: Surface.Type in surfaces:
		for depth: int in [2, 3, 4, 5, 6, 7]:
			var course := _valley(s, depth)
			var worst := 0
			var rim := 52.5 - depth * 5.0
			var xs: Array[float] = []
			for i: int in range(0, depth * 40 + 1):
				var at := rim + i * 0.25
				var quick := at <= 52.5 + EPS and (i <= 6 or i % (4 if depth <= 4 else 8) == 0)
				if quick or Sweep.full():
					xs.append(at)
			for x: float in Sweep.part(xs):
				var ball := _set_down(course, Vector2(x, 30.0))
				worst = maxi(worst, ball.steps)
				var label := "%s, %d deep, set at x %.2f" % [Surface.NAMES[s], depth, x]
				if absf(absf(x - 52.5) - depth * 5.0) < EPS and ball.steps <= 1:
					# On the rim's centre line the slope is the mean of the wall and the flat
					# top, half a step per tile, which rough's still-ball friction holds.
					assert_eq(s, Surface.Type.ROUGH, "%s: only rough holds a ball on the rim" % label)
				else:
					assert_almost_eq(ball.position.x, 52.5, 0.25, "%s: rests on the floor" % label)
			assert_lt(worst, OFF_GREEN_SETTLE, "%s valley %d steps deep: longest %d ticks" % [
					Surface.NAMES[s], depth, worst])


func test_drives_onto_flat_ground_settle_under_the_target() -> void:
	# A 100% driver (75 yd/s at 14 degrees) onto each rolling surface off the green, and a
	# 110% one (78.7 yd/s) onto cart path, the slowest.
	var drives := [
		[Surface.Type.FAIRWAY, 75.0], [Surface.Type.TEE, 75.0], [Surface.Type.ROUGH, 75.0],
		[Surface.Type.CART_PATH, 75.0], [Surface.Type.CART_PATH, 78.7]]
	for d: Array in drives:
		var s: Surface.Type = d[0]
		var ball := Ball.new(CourseData.create(120, 8, s, 0), 1)
		var ticks := _ground_ticks(ball, Vector3(10, 20, 0), Ball.launch_velocity(d[1], 14.0, 0.0))
		assert_lt(ticks, OFF_GREEN_SETTLE, "%s at %.1f yd/s: %d ticks on the ground" % [Surface.NAMES[s], d[1], ticks])


func test_drive_down_a_stepped_cart_path_settles_under_the_target() -> void:
	# A 100% and a 110% driver from the height-7 top carry to where the path steps down, one
	# step every 1 to 4 tiles from tile 52 to height 0 (10.2 s on the ground before E2-S4 at
	# every 4; E2-S4 review: 10.2 to 10.4 s at every 1 to 3 and at 110%).
	for every: int in [1, 2, 3, 4]:
		var course := CourseData.create(160, 8, Surface.Type.CART_PATH, 7)
		for y: int in 8:
			for x: int in 160:
				course.set_tile(x, y, clampi(7 - (x - 52) / every, 0, 7) if x >= 52 else 7, Surface.Type.CART_PATH)
		for speed: float in [75.0, 78.7]:
			var ball := Ball.new(course, 1)
			var ticks := _ground_ticks(ball, Vector3(10, 20, 14), Ball.launch_velocity(speed, 14.0, 0.0))
			var label := "every %d tiles, %.1f yd/s" % [every, speed]
			assert_gt(ball.landing_position.x, 250.0, "%s: carries to the steps" % label)
			assert_gt(ball.position.x, (52.0 + 7.0 * every) * 5.0, "%s: runs past the foot of the steps" % label)
			assert_lt(ticks, OFF_GREEN_SETTLE, "%s: %d ticks on the ground" % [label, ticks])


## A plateau at height 7 that steps down to 0 along +x from tile 52 (x 262.5 yd, the top), one
## step every `every` tiles, then flat: the long slope off the green (E2-S4 review, E6-S10).
func _stepped(surface: Surface.Type, every: int) -> CourseData:
	var course := CourseData.create(160, 8, surface, 7)
	for y: int in 8:
		for x: int in 160:
			course.set_tile(x, y, clampi(7 - (x - 52) / every, 0, 7) if x >= 52 else 7, surface)
	return course


const STEPPED_TOP := 262.5


func test_balls_down_a_long_one_step_slope_settle_under_the_target() -> void:
	# E6-S10: from up to 15.4 s (fairway, 923 ticks), rough 14.8 s, at the low terminal speed
	# where a one-step pull met the drag (3.6 yd/s). Balls set still or at up to 12 yd/s from
	# 22.5 yd above the top to the foot, down a slope stepping one step per tile (and every
	# 2 tiles). The worst arrive at the top nearly still (fairway and rough from x 254 at
	# 10 yd/s, 9.6 s). By default the run-in above the top every 2 yd at 8 to 12 yd/s and still
	# balls every 5 yd down the slope; Sweep.full() every 0.5 yd at 0 to 12 yd/s, and tee.
	# Cart path is docs/design.md Ball, Known limit (its own flat roll-out is too long).
	var surfaces: Array = Sweep.pick([Surface.Type.FAIRWAY, Surface.Type.ROUGH],
			[Surface.Type.FAIRWAY, Surface.Type.TEE, Surface.Type.ROUGH])
	for s: Surface.Type in surfaces:
		for every: int in [1, 2]:
			var course := _stepped(s, every)
			var foot := STEPPED_TOP + 35.0 * every
			var starts: Array[Vector2] = []
			if Sweep.full():
				var x := STEPPED_TOP - 22.5
				while x <= foot + EPS:
					for sp: int in 13:
						starts.append(Vector2(x, sp))
					x += 0.5
			else:
				for i: int in 13:
					for sp: float in [8.0, 10.0, 12.0]:
						starts.append(Vector2(STEPPED_TOP - 24.0 + 2.0 * i, sp))
				var x := STEPPED_TOP
				while x <= foot:
					starts.append(Vector2(x, 0.0))
					x += 5.0
			var worst := 0
			var at := Vector2.ZERO
			for st: Vector2 in Sweep.part(starts):
				var ball := Ball.new(course, 1)
				ball.start_roll(Vector2(st.x, 20.0), Vector2(st.y, 0.0))
				ball.run_to_rest()
				if ball.steps > worst:
					worst = ball.steps
					at = st
			assert_lt(worst, OFF_GREEN_SETTLE, "%s stepping every %d: longest %d ticks (x %.1f at %.0f yd/s)" % [
					Surface.NAMES[s], every, worst, at.x, at.y])


func test_fast_downhill_putts_over_a_steep_green_bank_stay_within_their_known_limit() -> void:
	# E6-S9, accepted beside the 8 s target (D31): the putt slows on the one-step slope at the
	# top of the bank, then runs from nearly still down the bank and out across the flat. The
	# worst starts of a sweep (x 1 to 60 every 0.5 yd, 6 to 18 yd/s straight down), measured
	# 2026-11-04: 715 ticks on two steps per tile, 659 on three, 558 on seven. This guards them.
	for c: Array in [[2, 48.5, 14.0, 750], [3, 43.5, 14.0, 690], [7, 45.0, 18.0, 590]]:
		var ball := Ball.new(_steep_green(c[0], 2), 1)
		ball.start_roll(Vector2(c[1], 100.0), Vector2(-c[2], 0.0))
		ball.run_to_rest()
		assert_lt(ball.steps, c[3], "%d steps per tile from x %.1f at %.0f yd/s: %d ticks" % [
				c[0], c[1], c[2], ball.steps])


func test_balls_down_a_long_cart_path_slope_stay_within_their_known_limit() -> void:
	# E6-S10, accepted beside the 10 s target (D31): cart path's own flat roll-out is too long
	# for a one-step slope. Worst starts of a sweep (every 1 yd from 22.5 yd above the top to
	# the foot, 0 to 12 yd/s), measured 2026-11-04: 845 ticks stepping every tile, 719 every 2.
	for c: Array in [[1, 244.0, 12.0, 880], [2, 272.0, 12.0, 750]]:
		var ball := Ball.new(_stepped(Surface.Type.CART_PATH, c[0]), 1)
		ball.start_roll(Vector2(c[1], 20.0), Vector2(c[2], 0.0))
		ball.run_to_rest()
		assert_lt(ball.steps, c[3], "stepping every %d from x %.1f at %.0f yd/s: %d ticks" % [
				c[0], c[1], c[2], ball.steps])


func test_clubs_down_a_long_slope_settle_under_the_target() -> void:
	# E6-S10: every full club through the shot model, at 100% and max_power, struck so it
	# comes down above or on the slope of _stepped(): rough stepping every 1, 2 and 4 tiles
	# (up to 572 ticks, the 110% driver), fairway every 2 and 4 (584, the 110% 3-wood). Fairway
	# every tile and cart path are docs/design.md Ball, Known limit. By default the worst
	# strikes; Sweep.full() every yard from 60 yd short of the club's carry to 10 yd past.
	var model := ShotModel.new()
	var top := SwingTuning.load_default().max_power
	var cases: Array = [[Surface.Type.ROUGH, 1], [Surface.Type.ROUGH, 2], [Surface.Type.ROUGH, 4],
			[Surface.Type.FAIRWAY, 2], [Surface.Type.FAIRWAY, 4]]
	# The worst strike found by the full sweep for each case: club, power, start x.
	var worst_strikes := {
		"rough 1": ["driver", top, -33.0], "rough 2": ["driver", top, -12.0],
		"rough 4": ["driver", top, -18.0], "fairway 2": ["3w", top, 0.0],
		"fairway 4": ["driver", top, 3.0]}
	for cfg: Array in cases:
		var s: Surface.Type = cfg[0]
		var every: int = cfg[1]
		var course := _stepped(s, every)
		var key := "%s %d" % [Surface.NAMES[s], every]
		var strikes: Array = []
		if Sweep.full():
			for c in model.clubs.clubs:
				if c.is_putter():
					continue
				for power: float in [1.0, top]:
					var x := STEPPED_TOP - c.carry_yd * power - 60.0
					while x <= STEPPED_TOP - c.carry_yd * power + 10.0:
						strikes.append([c.id, power, x])
						x += 1.0
		else:
			strikes.append(worst_strikes[key])
		var worst := 0
		var label := ""
		for st: Array in Sweep.part(strikes):
			var ball := Ball.new(course, 1)
			model.full(ball.field, model.clubs.club(st[0]), st[1], Vector2(st[2], 20.0), 0.0).apply(ball)
			while not ball.has_landed:
				ball.step()
			var landed := ball.steps
			ball.run_to_rest()
			if ball.steps - landed > worst:
				worst = ball.steps - landed
				label = "%s at %.0f%% from x %.0f" % [st[0], st[1] * 100.0, st[2]]
		assert_lt(worst, OFF_GREEN_SETTLE, "%s: longest %d ticks on the ground (%s)" % [key, worst, label])


func test_downhill_share_is_the_pull_along_the_ball_over_the_constant_friction() -> void:
	var full := 1.5
	var down := Vector2(3.7, 0.0)
	assert_eq(Ball.downhill_share(Vector2.ZERO, Vector2(5, 0), full), 0.0, "flat ground: none")
	assert_eq(Ball.downhill_share(down, Vector2(-5, 0), full), 0.0, "uphill: none")
	assert_almost_eq(Ball.downhill_share(down, Vector2(0, 5), full), 0.0, EPS, "straight across: none")
	assert_eq(Ball.downhill_share(down, Vector2(5, 0), full), 1.0, "a one-step downhill: in full")
	assert_almost_eq(Ball.downhill_share(Vector2(0.75, 0), Vector2(5, 0), full), 0.5, EPS,
			"a pull of half the constant friction: half")
	assert_eq(Ball.downhill_share(down, Vector2.ZERO, full), 0.0, "a still ball: none")


func test_downhill_friction_leaves_flat_rolls_and_climbs_alone() -> void:
	# E6-S10: downhill_friction_scale only works where the slope pulls the ball on.
	var plain: SurfaceTable = SurfaceTable.load_default().duplicate(true)
	for i in plain.rows.size():
		plain.rows[i] = plain.rows[i].duplicate()
		plain.rows[i].downhill_friction_scale = 1.0
	assert_lt(SurfaceTable.load_default().row(Surface.Type.FAIRWAY).downhill_friction_scale, 1.0,
			"fairway eases its friction downhill")
	var flat := Ball.new(_flat(), 1)
	flat.start_roll(Vector2(10, 100), Vector2(12, 0))
	flat.run_to_rest()
	var flat_plain := Ball.new(_flat(), 1, null, plain)
	flat_plain.start_roll(Vector2(10, 100), Vector2(12, 0))
	flat_plain.run_to_rest()
	assert_eq(flat.position, flat_plain.position, "flat ground: the same roll")
	assert_eq(flat.steps, flat_plain.steps, "and the same ticks")
	# Uphill on _ramp() until it stops: the same climb.
	var climbs: Array[float] = []
	for table: SurfaceTable in [SurfaceTable.load_default(), plain]:
		var up := Ball.new(_ramp(), 1, null, table)
		up.start_roll(Vector2(10, 100), Vector2(10, 0))
		while up.velocity.x > 0.0:
			up.step()
		climbs.append(up.position.x)
	assert_eq(climbs[0], climbs[1], "the climb: the same")
	# Downhill from the top of _ramp(), still: it reaches the foot sooner.
	var ticks: Array[int] = []
	for table: SurfaceTable in [SurfaceTable.load_default(), plain]:
		var down := Ball.new(_ramp(), 1, null, table)
		down.start_roll(Vector2(37.0, 100), Vector2.ZERO)
		while down.position.x > 5.0 and not down.is_at_rest():
			down.step()
		ticks.append(down.steps)
	assert_lt(ticks[0], ticks[1] * 0.8, "downhill: well before (%d against %d ticks)" % [ticks[0], ticks[1]])


func test_a_valley_floor_takes_floor_keep_of_the_speed() -> void:
	# E6-S10: across a low point only; a flat foot and a lip are as before.
	var v := Vector2(5.0, 0.0)
	var rigid := Ball.meet_ground(v, Vector2(-0.4, 0), Vector2(0.4, 0))
	var thud := Ball.meet_ground(v, Vector2(-0.4, 0), Vector2(0.4, 0), 0.4)
	assert_almost_eq(thud.x, rigid.x * 0.4, EPS, "a V floor: floor_keep of the rigid share")
	assert_eq(Ball.meet_ground(v, Vector2.ZERO, Vector2(0.4, 0), 0.4),
			Ball.meet_ground(v, Vector2.ZERO, Vector2(0.4, 0)), "the foot of a bank: unchanged")
	assert_eq(Ball.meet_ground(v, Vector2(-0.4, 0), Vector2.ZERO, 0.4), v, "onto a flat foot: unchanged")
	assert_eq(Ball.meet_ground(v, Vector2.ZERO, Vector2(-0.4, 0), 0.4), v, "over a lip: unchanged")
	var table := SurfaceTable.load_default()
	assert_eq(table.row(Surface.Type.GREEN).floor_keep, 1.0, "the green keeps the rigid share")
	assert_eq(table.row(Surface.Type.GREEN).downhill_friction_scale, 1.0, "and its friction downhill")
	# E6-S10 review: the thud fades with speed, so floor_keep is for slow crossings.
	assert_eq(Ball.floor_thud(0.0, 0.4, 20.0), 0.4, "a still ball: floor_keep")
	assert_almost_eq(Ball.floor_thud(10.0, 0.4, 20.0), 0.7, EPS, "half floor_keep_speed: halfway")
	assert_eq(Ball.floor_thud(25.0, 0.4, 20.0), 1.0, "past floor_keep_speed: all of it")
	assert_eq(Ball.floor_thud(25.0, 0.4, 0.0), 0.4, "floor_keep_speed 0: floor_keep at every speed")
	var fast := Ball.meet_ground(Vector2(25.0, 0.0), Vector2(-0.4, 0), Vector2(0.4, 0), 0.4, 20.0)
	assert_almost_eq(fast, Ball.meet_ground(Vector2(25.0, 0.0), Vector2(-0.4, 0), Vector2(0.4, 0)),
			Vector2.ONE * 1e-5, "a fast crossing: the rigid share alone")


func test_a_fast_roll_crosses_a_one_step_dip_as_before_floor_keep() -> void:
	# E6-S10 review: with floor_keep at every speed, one tile dug a step into fairway or rough
	# caught a 25 to 40 yd/s roll at its floor (15.0 yd, against 23.8 to 41.0 without it).
	# With floor_keep_speed the fast rolls run on as they did with floor_keep 1.0.
	var plain: SurfaceTable = SurfaceTable.load_default().duplicate(true)
	for i in plain.rows.size():
		plain.rows[i] = plain.rows[i].duplicate()
		plain.rows[i].floor_keep = 1.0
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.CART_PATH]:
		var course := CourseData.create(60, 8, s, 2)
		for y: int in 8:
			course.set_tile(5, y, 1, s)
		for speed: float in [30.0, 35.0, 40.0, 50.0, 60.0]:
			var runs: Array[float] = []
			for table: SurfaceTable in [SurfaceTable.load_default(), plain]:
				var ball := Ball.new(course, 1, null, table)
				ball.start_roll(Vector2(12.5, 20.0), Vector2(speed, 0.0))
				ball.run_to_rest()
				runs.append(ball.position.x - 12.5)
			var label := "%s at %.0f yd/s" % [Surface.NAMES[s], speed]
			assert_gt(runs[0], 20.0, "%s: past the dip (%.1f yd)" % [label, runs[0]])
			assert_almost_eq(runs[0], runs[1], 1.0, "%s: about as far as without floor_keep" % label)


func test_fairway_does_not_outroll_green_on_flat_ground() -> void:
	# E6-S10: fairway drag_scale 1.2 shortens fairway rolls; it must not pass the green's.
	for speed: float in [4.0, 10.0, 20.0, 30.0]:
		var fair := Ball.new(_flat(Surface.Type.FAIRWAY, 60), 1)
		fair.start_roll(Vector2(10, 100), Vector2(speed, 0))
		fair.run_to_rest()
		var green := Ball.new(_flat(Surface.Type.GREEN, 60), 1)
		green.start_roll(Vector2(10, 100), Vector2(speed, 0))
		green.run_to_rest()
		assert_lt(fair.position.x, green.position.x, "%.0f yd/s: fairway %.2f yd, green %.2f yd" % [
				speed, fair.position.x - 10.0, green.position.x - 10.0])


func test_every_club_settles_under_the_target_on_flat_ground() -> void:
	# E2-S11: the E2-S4 drives above are a raw 75 yd/s ball with no club. Every full club
	# through the shot model (E2-S5: its launch and roll_factor), at 100% and at the bar's
	# max_power, onto flat fairway, tee, rough and cart path (the 110% driver onto cart path,
	# 8.9 s, is the slowest). Down a long slope see test_clubs_down_a_long_slope_settle_under_the_target.
	var model := ShotModel.new()
	var top := SwingTuning.load_default().max_power
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.TEE, Surface.Type.ROUGH, Surface.Type.CART_PATH]:
		var course := CourseData.create(120, 8, s, 0)
		for c in model.clubs.clubs:
			if c.is_putter():
				continue
			for power: float in [1.0, top]:
				var ball := Ball.new(course, 1)
				model.full(ball.field, c, power, Vector2(10, 20), 0.0).apply(ball)
				while not ball.has_landed:
					ball.step()
				var landed := ball.steps
				ball.run_to_rest()
				assert_lt(ball.steps - landed, OFF_GREEN_SETTLE, "flat %s, %s at %.0f%%: %d ticks on the ground" % [
						Surface.NAMES[s], c.id, power * 100.0, ball.steps - landed])


## Every surface a ball rolls on, the green included.
const ROLLING: Array[Surface.Type] = [Surface.Type.FAIRWAY, Surface.Type.TEE, Surface.Type.ROUGH,
		Surface.Type.CART_PATH, Surface.Type.GREEN]


func _deep_pit(surface: Surface.Type, depth: int) -> CourseData:
	var course := _flat(surface, 5, depth)
	course.set_tile(2, 2, 0, surface)
	return course


func test_deep_pits_settle_under_the_targets() -> void:
	# E2-S4 review: one-tile pits 2 to 7 steps deep reached the 60 s cap (fairway and tee from
	# 5 deep, cart path from 3, green from 4, rough from 6). Starts 0.5 to 2.4 yd out, 16
	# ways round. The green's rim, further out, is the next test.
	# E2-S16: by default depths 2, 4 and 7 (7 is the worst on every surface, rough 204 ticks)
	# and radii 0.5, 1.925 and 2.4 (every worst start is 1.925 or 2.4 out). Sweep.full() runs
	# every depth from 2 to 7 and every radius.
	var centre := Vector2(12.5, 12.5)
	for s: Surface.Type in ROLLING:
		var target := GREEN_SETTLE if s == Surface.Type.GREEN else OFF_GREEN_SETTLE
		for depth: int in Sweep.pick([2, 4, 7], [2, 3, 4, 5, 6, 7]):
			var course := _deep_pit(s, depth)
			var worst := 0
			for r: float in Sweep.pick([0.5, 1.925, 2.4], [0.5, 0.975, 1.45, 1.925, 2.4]):
				for a: int in 16:
					var ball := _set_down(course, centre + Vector2.RIGHT.rotated(a * PI / 8.0) * r)
					worst = maxi(worst, ball.steps)
					assert_lt(Vector2(ball.position.x, ball.position.y).distance_to(centre), 0.5,
							"%s pit %d deep, r %.2f: rests at the bottom" % [Surface.NAMES[s], depth, r])
			assert_lt(worst, target, "%s pit %d deep: longest %d ticks" % [Surface.NAMES[s], depth, worst])


func test_green_pit_balls_settle_from_anywhere_on_the_plot() -> void:
	# E2-S11: on the rim of a two-step green pit, where the walls blend at its corners, the
	# felt pull was just over the D7 hold and a still ball crept at the rest speed: 20.7 s
	# from (10.2, 10.2), 19.4 s from (9.5, 10.75), and 15.2 s on a three-step pit. Since green
	# steep_from 0.4 and steep_scale 3.0 (20 since E6-S11), past a one-step contour a slope is
	# felt well over the hold. Every 0.25 yd over one quarter of the 5x5 plot (the pit is symmetric).
	var centre := Vector2(12.5, 12.5)
	for depth: int in [2, 3]:
		var course := _deep_pit(Surface.Type.GREEN, depth)
		var worst := 0
		var what := Vector2.ZERO
		for i in range(1, 51):
			for j in range(1, 51):
				# E2-S16: by default every 0.5 yd, and every 0.25 yd from 7.25 to 10.5 yd on both
				# axes, the rim's corner, where the worst settles start (E6-S11: 201 ticks from
				# (7.75, 10.25) on 2 deep, 162 from (7.75, 9.25) on 3; 273 and 286 before). Sweep.full() runs every 0.25 yd.
				var corner := i >= 29 and i <= 42 and j >= 29 and j <= 42
				if not (Sweep.full() or corner or (i % 2 == 0 and j % 2 == 0)):
					continue
				var at := Vector2(i, j) * 0.25
				var ball := _set_down(course, at)
				if ball.steps > worst:
					worst = ball.steps
					what = at
				if Vector2(ball.position.x, ball.position.y).distance_to(centre) >= 0.5:
					assert_true(ball.steps <= 1, "green pit %d deep, set at %s: held where set, or rolls to the bottom" % [depth, at])
		assert_lt(worst, GREEN_SETTLE, "green pit %d deep: longest %d ticks, from %s" % [depth, worst, what])


func test_a_green_slope_past_a_contour_is_felt_well_over_the_hold() -> void:
	# E2-S11: a contour's slope (0.4 per axis, one step per tile, corners included) is felt as
	# a break and held (D7). Just past it the felt slope must already pull a still ball
	# clearly harder than the hold, or the ball creeps at the rest speed for many seconds.
	var params := BallParams.load_default()
	var green := SurfaceTable.load_default().row(Surface.Type.GREEN)
	assert_almost_eq(green.steep_from, 0.4, 1e-6, "the steep part starts where a one-step contour ends")
	var hold := _hold(params, green)
	var felt := Ball.felt_gradient(Vector2(0.5, 0.0), green).x
	var pull := params.gravity * felt / (1.0 + felt * felt)
	assert_gt(pull, 3.0 * hold, "a quarter step past a contour pulls %.2f against the %.2f hold" % [pull, hold])


## E6-S11: 40 greens of 6x6 tiles, every tile a random height from 0 to `hmax`, drawn in
## order from one generator seeded 5 (the E2-S11 review's set).
func _random_greens(hmax: int) -> Array[CourseData]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var greens: Array[CourseData] = []
	for g in 40:
		var course := CourseData.create(6, 6, Surface.Type.GREEN, 0)
		for y in 6:
			for x in 6:
				course.set_tile(x, y, rng.randi_range(0, hmax), Surface.Type.GREEN)
		greens.append(course)
	return greens


## Still balls on `greens` as [green index, start]: `quick`, and with --full also every
## `stride` yards on both axes (at x.5, y.5).
func _random_green_cases(greens: Array[CourseData], quick: Array, stride: int = 1) -> Array:
	var cases: Array = quick.duplicate()
	if Sweep.full():
		for g in greens.size():
			for i in range(0, 30, stride):
				for j in range(0, 30, stride):
					cases.append([g, Vector2(i + 0.5, j + 0.5)])
	return cases


## Longest settle of the still balls `cases` ([green index, start]) on `greens`.
func _random_green_worst(greens: Array[CourseData], cases: Array) -> Dictionary:
	var worst := {"steps": 0, "what": "", "capped": 0}
	for c: Array in cases:
		var ball := _set_down(greens[c[0]], c[1])
		if ball.steps >= ball.params.max_steps:
			worst["capped"] += 1
		if ball.steps > worst["steps"]:
			worst["steps"] = ball.steps
			worst["what"] = "green %d from %s" % [c[0], c[1]]
	return worst


func test_random_greens_up_to_two_steps_settle_under_the_green_target() -> void:
	# E6-S11: with E2-S11's steep_scale 3.0, 7 of the 36000 still balls on random greens of
	# heights 0 to 2 took 480 ticks or more (8.6 s); just past a contour a ball crept at a low
	# terminal speed for seconds. Since steep_scale 20 none does (446 ticks, green 15 from
	# (14.5, 18.5)). By default the twelve worst starts of the full set; --full runs them all.
	var quick := [[15, Vector2(14.5, 18.5)], [12, Vector2(15.5, 10.5)], [12, Vector2(19.5, 10.5)],
			[15, Vector2(20.5, 18.5)], [22, Vector2(11.5, 9.5)], [15, Vector2(21.5, 18.5)],
			[22, Vector2(11.5, 8.5)], [6, Vector2(4.5, 26.5)], [14, Vector2(19.5, 21.5)],
			[12, Vector2(26.5, 24.5)], [16, Vector2(3.5, 10.5)], [22, Vector2(10.5, 10.5)]]
	var greens := _random_greens(2)
	var w := _random_green_worst(greens, Sweep.part(_random_green_cases(greens, quick)))
	assert_eq(w["capped"], 0, "no ball reaches max_steps")
	assert_lt(w["steps"], GREEN_SETTLE, "heights 0 to 2: longest %d ticks, %s" % [w["steps"], w["what"]])


func test_random_steep_greens_stay_within_their_known_limit() -> void:
	# E6-S11, not met: random greens of heights 0 to 4 and 0 to 7 still settle over 8 s from
	# a few starts (docs/design.md Ball, Known limit). The ball runs down a bank, slows almost
	# to rest on gentle ground, then meets another bank. This guards the measured worst (501
	# and 589 ticks, from 666 and 662 with steep_scale 3.0) against a regression. By default
	# the worst starts of the full set; --full adds every other yard on both axes (a quarter
	# of the 36000 per height, to keep --full near its old runtime; the worst starts above
	# come from the every-yard sweep).
	var cases := {
		4: {"bound": 520, "quick": [[0, Vector2(14.5, 10.5)], [2, Vector2(21.5, 9.5)],
				[4, Vector2(15.5, 21.5)], [35, Vector2(9.5, 27.5)]]},
		7: {"bound": 610, "quick": [[17, Vector2(8.5, 4.5)], [32, Vector2(26.5, 10.5)],
				[17, Vector2(9.5, 19.5)], [29, Vector2(16.5, 4.5)], [22, Vector2(21.5, 8.5)]]},
	}
	for hmax: int in cases:
		var greens := _random_greens(hmax)
		var w := _random_green_worst(greens, Sweep.part(_random_green_cases(greens, cases[hmax]["quick"], 2)))
		assert_eq(w["capped"], 0, "heights 0 to %d: no ball reaches max_steps" % hmax)
		assert_lt(w["steps"], cases[hmax]["bound"], "heights 0 to %d: longest %d ticks, %s" % [
				hmax, w["steps"], w["what"]])


func test_a_diagonal_two_and_one_step_green_ramp_settles_under_the_green_target() -> void:
	# E2-S11 review: a 6x6 green with heights 2i + j (capped at 7) took up to 9.7 s (583
	# ticks) for still balls; since steep_scale 20, 264 ticks from (17.25, 12.25). Every yard
	# and every 0.25 yd round the worst start; --full every 0.25 yd.
	var course := CourseData.create(6, 6, Surface.Type.GREEN, 0)
	for y in 6:
		for x in 6:
			course.set_tile(x, y, clampi(2 * x + y, 0, 7), Surface.Type.GREEN)
	var worst := 0
	var what := Vector2.ZERO
	for i in range(1, 120):
		for j in range(1, 120):
			var near := i >= 64 and i <= 72 and j >= 44 and j <= 52
			if not (Sweep.full() or near or (i % 4 == 0 and j % 4 == 0)):
				continue
			var ball := _set_down(course, Vector2(i, j) * 0.25)
			if ball.steps > worst:
				worst = ball.steps
				what = Vector2(i, j) * 0.25
	assert_lt(worst, GREEN_SETTLE, "longest %d ticks, from %s" % [worst, what])


func test_mixed_green_banks_stay_within_their_known_limit() -> void:
	# E6-S11, not met: a green bank whose tiles alternate two- and one-step rises, ten flat
	# tiles below it. A ball that runs down a two-step rise and only just crosses the one-step
	# band below it, then runs down the next rise and out across the flat, takes over 8 s
	# (docs/design.md Ball, Known limit): 534 and 548 ticks, from x 66.0 and 71.0. This guards
	# them against a regression. Still balls every 0.25 yd along y 22.5 over the bank (x 50 to
	# 85); --full from x 0.25.
	for heights: Array in [[0, 2, 3, 5, 6, 7, 7], [0, 1, 3, 4, 6, 7, 7]]:
		var course := CourseData.create(10 + heights.size(), 10, Surface.Type.GREEN, 0)
		for y in 10:
			for i in heights.size():
				course.set_tile(10 + i, y, heights[i], Surface.Type.GREEN)
		var worst := 0
		var what := 0.0
		var x := 0.25 if Sweep.full() else 50.0
		while x < course.width * 5.0:
			var ball := _set_down(course, Vector2(x, 22.5))
			assert_lt(ball.steps, ball.params.max_steps, "%s from x %.2f: comes to rest" % [heights, x])
			if ball.steps > worst:
				worst = ball.steps
				what = x
			x += 0.25
		assert_lt(worst, 560, "%s: longest %d ticks, from x %.2f" % [heights, worst, what])


func test_trench_balls_settle_under_the_targets() -> void:
	# E2-S4 review: a one-tile trench 7 deep (column 4 of a 9x12 plot) held still balls at
	# 0.3 yd/s across its floor until the cap on fairway, tee, cart path and green.
	# E2-S16: by default depths 2, 4 and 7 (7 is the worst on every surface, rough 220
	# ticks). Sweep.full() runs every depth from 2 to 7.
	for s: Surface.Type in ROLLING:
		var target := GREEN_SETTLE if s == Surface.Type.GREEN else OFF_GREEN_SETTLE
		for depth: int in Sweep.pick([2, 4, 7], [2, 3, 4, 5, 6, 7]):
			var course := CourseData.create(9, 12, s, depth)
			for y: int in 12:
				course.set_tile(4, y, 0, s)
			var worst := 0
			var x := 17.5
			while x <= 27.5 + EPS:
				var ball := _set_down(course, Vector2(x, 30.0))
				worst = maxi(worst, ball.steps)
				x += 0.25
			assert_lt(worst, target, "%s trench %d deep: longest %d ticks" % [Surface.NAMES[s], depth, worst])


func test_putts_climb_a_steep_green_tier() -> void:
	# E2-S4 review: the crease took nearly all of a putt's speed at the foot of a steep green
	# riser, so no putt up to 40 yd/s climbed 5 steps, and 3 steps needed 19.6 yd/s from 1 yd
	# short. The putter is the only club on green (D13), so a cup on the upper tier must be
	# reachable. The riser runs from x 27.5 to 32.5; putts from 1 and 7.5 yd short of it.
	for k: int in [1, 2, 3, 5, 7]:
		var course := _flat(Surface.Type.GREEN, 14)
		for y: int in 14:
			for x: int in range(6, 14):
				course.set_tile(x, y, k, Surface.Type.GREEN)
		for from: float in [26.5, 20.0]:
			var climbs := -1.0
			var speed := 1.0
			while speed <= PUTT_CLIMB_MAX and climbs < 0.0:
				var ball := _set_down(course, Vector2(from, 35.0), Vector2(speed, 0.0))
				if ball.position.x > 32.5:
					climbs = speed
				speed += 0.5
			assert_gt(climbs, 0.0, "a %d-step riser from x %.1f: climbed at %.1f yd/s" % [k, from, climbs])


func test_a_ball_over_a_drop_runs_no_shorter_than_on_flat_ground() -> void:
	# E2-S4 review: the crease braked a ball at a lip, so a 20 yd/s ball over a 7-step drop
	# on fairway rested at x 34.0 against 43.9 on flat ground.
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.GREEN]:
		var flat := _set_down(_flat(s, 40, 7), Vector2(20.0, 20.0), Vector2(20.0, 0.0))
		for k: int in range(1, 8):
			var course := _flat(s, 40, 7)
			for y: int in 40:
				for x: int in range(6, 40):
					course.set_tile(x, y, 7 - k, s)
			var ball := _set_down(course, Vector2(20.0, 20.0), Vector2(20.0, 0.0))
			assert_gte(ball.position.x, flat.position.x, "%s, %d steps down: rests at x %.1f, flat %.1f" % [
					Surface.NAMES[s], k, ball.position.x, flat.position.x])


func test_felt_gradient_feels_a_steep_green_bank_as_steep() -> void:
	var green := SurfaceTable.load_default().row(Surface.Type.GREEN)
	var fairway := SurfaceTable.load_default().row(Surface.Type.FAIRWAY)
	var one := Vector2(0.4, 0.0)
	assert_eq(Ball.felt_gradient(one, fairway), one, "fairway feels the terrain")
	assert_almost_eq(Ball.felt_gradient(one, green).x, 0.4 * green.slope_scale, 1e-6, "a contour is a break")
	assert_almost_eq(Ball.felt_gradient(Vector2(0.4, -0.4), green), Vector2(0.4, -0.4) * green.slope_scale,
			Vector2.ONE * 1e-6, "so is a contour corner")
	var two := Ball.felt_gradient(Vector2(0.8, 0.0), green).x
	assert_gt(two, 0.8 * green.slope_scale * 3.0, "two steps per tile is felt far steeper than a break")
	for steps: int in range(2, 8):
		var g := Vector2(0.0, -0.4 * steps)
		var felt := Ball.felt_gradient(g, green)
		assert_lte(felt.length(), g.length() + 1e-6, "%d steps per tile: never steeper than the terrain" % steps)
		assert_lt(felt.y, 0.0, "%d steps per tile: the same way down" % steps)
	var gully := Ball.felt_gradient(Vector2(0.8, 0.4), green)
	assert_almost_eq(gully.y, 0.4 * green.slope_scale, 1e-6, "per axis: a gentle floor between steep walls stays gentle")


func test_meeting_steeper_ground_takes_the_speed_into_it() -> void:
	var v := Vector2(10.0, 0.0)
	assert_eq(Ball.meet_ground(v, Vector2.ZERO, Vector2.ZERO), v, "flat ground: unchanged")
	assert_almost_eq(Ball.meet_ground(v, Vector2(0.4, 0), Vector2(0.4, 0)), v, Vector2.ONE * 1e-5,
			"even slope: unchanged")
	assert_almost_eq(Ball.meet_ground(v, Vector2(-0.4, 0), Vector2.ZERO), v, Vector2.ONE * 1e-5,
			"down onto a flat foot: all the ground speed kept")
	var across := Ball.meet_ground(v, Vector2(-0.4, 0), Vector2(0.4, 0))
	assert_almost_eq(across.x, 10.0 * 0.84 / 1.16, 1e-4, "across a one-step V floor: cos of the crease angle kept")
	assert_lt(Ball.meet_ground(v, Vector2.ZERO, Vector2(0.4, 0)).x, v.x, "onto a steeper uphill: slower")
	var green := SurfaceTable.load_default().row(Surface.Type.GREEN)
	var contour := Ball.meet_ground(v, Ball.felt_gradient(Vector2(-0.4, 0), green),
			Ball.felt_gradient(Vector2(0.4, 0), green))
	assert_gt(contour.x, 9.98, "across a green contour, felt as a break, almost nothing")


func test_a_crease_never_brakes_a_lip_or_turns_the_ball_back() -> void:
	# E2-S4 review: over a lip (a convex crease) the ball braked; past a 90 degree crease (a
	# pit or trench floor, walls steeper than 45 degrees) it was turned back, and swung to
	# and fro at 0.3 yd/s until the 60 s cap.
	var v := Vector2(10.0, 0.0)
	for drop: float in [0.4, 0.8, 2.8]:
		assert_eq(Ball.meet_ground(v, Vector2.ZERO, Vector2(-drop, 0)), v, "over a lip into %.1f: unchanged" % drop)
		assert_eq(Ball.meet_ground(v, Vector2(0.4, 0), Vector2(-drop, 0)), v, "over a crest into %.1f: unchanged" % drop)
	for wall: float in [1.2, 2.0, 2.8]:
		var met := Ball.meet_ground(Vector2(0.3, 0.0), Vector2(-wall, 0), Vector2(wall, 0))
		assert_gte(met.x, 0.0, "across a V floor of %.1f walls: never turned back" % wall)
		assert_lte(met.x, 0.3, "and never faster")
	assert_eq(Ball.meet_ground(v, Vector2(-0.8, 0), Vector2(-0.4, 0)), v, "onto a gentler downhill: no faster")
	var diag := Ball.meet_ground(Vector2(3.0, 4.0), Vector2(-0.8, 0.4), Vector2(0.8, 0.4))
	assert_eq(diag.y, 4.0, "per axis: a crease across x leaves the run along y as it was")


func test_rough_drag_fades_at_low_speed() -> void:
	# E2-S4: below drag_full_speed the drag fades with speed, so a ball rolling down a rough
	# slope is not held to the 1.2 yd/s crawl full drag allowed.
	var rough := SurfaceTable.load_default().row(Surface.Type.ROUGH)
	assert_gt(rough.drag_full_speed, 0.0, "rough fades its drag")
	var course := _ramp()
	for y in 40:
		for x in 40:
			course.set_tile(x, y, course.get_height(x, y), Surface.Type.ROUGH)
	var ball := Ball.new(course, 1)
	ball.start_roll(Vector2(36.0, 100.0), Vector2.ZERO)
	for i in Ball.TICK_HZ * 3:
		ball.step()
	assert_gt(-ball.velocity.x, 2.0, "3 s down a one-step rough slope: %.2f yd/s" % -ball.velocity.x)


# --- determinism ---

func test_same_seed_same_landing_100_of_100() -> void:
	# Rough scatters the bounce, so the seeded generator matters here.
	var course := _ramp()
	for y in 40:
		for x in 40:
			course.set_tile(x, y, course.get_height(x, y), Surface.Type.ROUGH)
	var start := Vector3(12, 80, 0)
	var v := Ball.launch_velocity(45.0, 28.0, 10.0)
	var first := _run(course, start, v, 1234)
	var same := 0
	for i in 100:
		seed(i * 7919)  # Scramble the global generator; the ball must not care.
		randi()
		var ball := _run(course, start, v, 1234)
		if ball.landing_position == first.landing_position and ball.position == first.position \
				and ball.steps == first.steps:
			same += 1
	assert_eq(same, 100, "identical landing and rest position, bit for bit")


func test_seed_drives_the_scatter() -> void:
	var course := _flat(Surface.Type.ROUGH)
	var start := Vector3(10, 100, 0)
	var v := Vector3(30, 0, 15)
	var a := _run(course, start, v, 1)
	var b := _run(course, start, v, 2)
	assert_eq(a.landing_position, b.landing_position, "the carry is not random")
	assert_ne(a.position, b.position, "the bounce scatter comes from the ball's seed")


func test_ball_leaves_the_global_generator_alone() -> void:
	seed(42)
	var expected := randi()
	seed(42)
	_run(_flat(Surface.Type.ROUGH), Vector3(10, 100, 0), Vector3(30, 0, 15), 99)
	assert_eq(randi(), expected, "global RNG untouched")
