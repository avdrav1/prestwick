extends GutTest
## E1-S6: the ball is a custom 3D step at 60 Hz over the height map (D1).
## Units are yards: x and y on the ground from the map's corner, z up.

const EPS := 0.001


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
	var k := normal.params.roll_drag
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
	var grad := row.slope_scale * steps * params.yards_per_step / params.yards_per_tile
	return params.gravity * grad / (1.0 + grad * grad)


## Constant friction that holds a still ball on the surface of `row`.
func _hold(params: BallParams, row: SurfaceRow) -> float:
	return params.roll_decel * row.rest_decel_scale / row.roll


func test_slope_pull_beats_rest_friction() -> void:
	# A design guard: off the green, the one-step pull must beat the constant friction that
	# holds a still ball on every rolling surface, or balls never start down a slope. The
	# green holds a ball on a gentle slope by design (D7, next test).
	var params := BallParams.load_default()
	var table := SurfaceTable.load_default()
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.TEE,
			Surface.Type.TREES, Surface.Type.CART_PATH]:
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
	# Known limit (docs/design.md Ball): it trickles, about 42 s; the 8 s target covers
	# one-step green slopes only.
	assert_lt(ball.steps, ball.params.max_steps, "and came to rest on its own")


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
	ball.start_roll(start, Vector2(5, 0))
	ball.run_to_rest()
	var furthest := start.x
	for p in ball.path:
		furthest = maxf(furthest, p.x)
	assert_gt(furthest, 13.5, "went up the slope")
	assert_lt(furthest, 27.5, "but not over the top")
	assert_lt(ball.position.x, 13.0, "and came back down to the foot")
	assert_lt(ball.steps, ball.params.max_steps, "on its own (about 14 s; see the test above)")


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

## Longest settle over still balls and putts of 1 to 15 yd/s along the four axes and the four
## diagonals from every start (yards) in `xs` x `ys`. The 8 s target is for balls that come
## to rest on green ("steps"); a putt that runs off the green and on down the rough's slope
## is rough physics, reported apart ("off_steps", docs/design.md Ball known limit).
func _settle_worst(course: CourseData, xs: Array, ys: Array) -> Dictionary:
	var worst := {"steps": 0, "what": "", "off_steps": 0, "off_what": "", "capped": 0}
	var cases: Array[Vector2] = [Vector2.ZERO]
	for speed in range(1, 16):
		for i in 8:
			cases.append(Vector2.RIGHT.rotated(i * PI / 4.0) * speed)
	for x: float in xs:
		for y: float in ys:
			var p := Vector2(x, y)
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
	# down the rough's tier slope for up to about 9.6 s (rough physics, a known limit), so
	# only balls that rest on green are held to 8 s; the rest must still settle on their own.
	for mirrored: bool in [false, true]:
		var w := _settle_worst(GridHeightEvidence.green_contour(mirrored),
				[22.5, 25.0, 28.0, 30.0, 32.0, 35.0, 38.0, 40.0, 42.0, 45.0, 48.0, 50.0, 52.0, 55.0],
				[12.5, 27.5, 47.5])
		assert_eq(w["capped"], 0, "no ball reaches max_steps")
		assert_lt(w["steps"], Ball.TICK_HZ * 8, "mirrored %s: longest settle on green %.1f s, %s (off green %.1f s, %s)" % [
				mirrored, w["steps"] / 60.0, w["what"], w["off_steps"] / 60.0, w["off_what"]])


func test_green_settle_time_on_a_one_step_per_tile_ramp() -> void:
	# GridHeightEvidence.green_ramp(): all green, rising one step per tile from 0 to 7.
	var w := _settle_worst(GridHeightEvidence.green_ramp(),
			[20.0, 22.5, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 57.5, 60.0], [10.0, 30.0, 50.0])
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
