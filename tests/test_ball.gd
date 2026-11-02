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


func test_slope_pull_beats_rest_friction() -> void:
	# A design guard: the steepest pull, scaled by the surface's slope_scale, must beat the
	# constant friction that holds a still ball on every rolling surface, or balls never
	# start down a slope.
	var params := BallParams.load_default()
	var table := SurfaceTable.load_default()
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.GREEN,
			Surface.Type.TEE, Surface.Type.TREES, Surface.Type.CART_PATH]:
		var row := table.row(s)
		var grad := row.slope_scale * params.yards_per_step / params.yards_per_tile
		var pull := params.gravity * grad / (1.0 + grad * grad)
		var hold := params.roll_decel * row.rest_decel_scale / row.roll
		assert_gt(pull, hold, "a one-step slope moves a still ball on %s" % Surface.NAMES[s])


func test_ball_at_rest_on_a_green_slope_rolls_down() -> void:
	# The green feels a one-step ramp as 3% (E1-S11), so a still ball trickles down it at
	# about 0.17 yd/s: set it down 3 yd above the mark rather than 10.
	var course := _green_ramp()
	var ball := Ball.new(course, 3)
	ball.start_roll(Vector2(13, 100), Vector2.ZERO)
	ball.run_to_rest()
	assert_lt(ball.position.x, 10.0, "a ball set down on the slope runs down it")


func test_ball_rolling_downhill_on_green_speeds_up() -> void:
	# Green feels slope_scale of the slope (E1-S11), so a one-step ramp is a 3% break whose
	# pull only keeps a slow ball trickling. A three-steps-per-tile green (120%, felt as 9%)
	# pulls hard enough to speed a 0.5 yd/s ball up. Heights 0, 3, 6, 7 from x = 10.
	var course := _flat(Surface.Type.GREEN, 40)
	for y in 40:
		for x in 40:
			course.set_tile(x, y, clampi((x - 10) * 3, 0, 7), Surface.Type.GREEN)
	var ball := Ball.new(course, 3)
	ball.start_roll(Vector2(62, 100), Vector2(-0.5, 0))
	for i in 30:
		ball.step()
	assert_eq(ball.state, Ball.State.ROLLING)
	assert_gt(Vector2(ball.velocity.x, ball.velocity.y).length(), 0.5, "gathers speed going down")


func test_uphill_putt_that_stops_short_rolls_back() -> void:
	var course := _green_ramp()
	var start := Vector2(10, 100)
	var ball := Ball.new(course, 3)
	ball.record_path = true
	ball.start_roll(start, Vector2(6, 0))
	ball.run_to_rest()
	var furthest := start.x
	for p in ball.path:
		furthest = maxf(furthest, p.x)
	assert_gt(furthest, start.x + 1.0, "went up the hill")
	assert_lt(furthest, 37.5, "but not over the top")
	assert_lt(ball.position.x, start.x, "and came back down past where it started")


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
	# 32.5 yd), which falls towards -x. The break is the sideways offset when the putt runs
	# out of pace (forward speed under rest speed): what a cup at the putt's length sees.
	# After that the ball trickles on down to the lower shelf, as any still ball does there.
	var from := _yd(Vector2(5.5, 2.5))
	var ball := Ball.new(GridHeightEvidence.green_contour(), 1)
	ball.start_roll(from, Vector2(0, 3))
	var brk := -1.0
	while not ball.is_at_rest():
		ball.step()
		if brk < 0.0 and ball.velocity.y < ball.params.rest_speed:
			brk = from.x - ball.position.x
			assert_gt(ball.position.y - from.y, 2.0, "it rolled forward first")
	assert_between(brk, 0.1, 1.0, "a 3 yd/s sidehill putt breaks %.2f yd downhill" % brk)
	assert_lt(ball.position.x, 27.5 + EPS, "then settles on the lower shelf")


func test_contour_still_ball_on_a_step_rolls_to_the_lower_shelf() -> void:
	var course := GridHeightEvidence.green_contour()
	# Points across each of the three green step bands (x 27.5-32.5, 37.5-42.5, 47.5-52.5).
	for band: int in 3:
		var lower := 27.5 + 10.0 * band
		for into: float in [0.5, 2.5, 4.5]:
			var ball := Ball.new(course, 1)
			ball.start_roll(Vector2(lower + into, 27.5), Vector2.ZERO)
			ball.run_to_rest()
			assert_lt(ball.steps, ball.params.max_steps, "came to rest on its own")
			assert_between(ball.position.x, lower - 5.0, lower + EPS,
					"set down %.1f yd up step %d, rests on the shelf below" % [into, band + 1])
			assert_almost_eq(ball.field.gradient_at(ball.position.x, ball.position.y).length(), 0.0, EPS,
					"on flat ground")


func test_contour_uphill_putt_that_stops_short_on_a_step_rolls_back() -> void:
	var from := Vector2(4.5, 5.5)
	var ball := _putt(GridHeightEvidence.green_contour(), from, Vector2(6, 0))
	var furthest := 0.0
	for p in ball.path:
		furthest = maxf(furthest, p.x)
	assert_between(furthest, 27.5, 32.5, "it stops on the step's slope")
	assert_lt(ball.position.x, 27.5 + EPS, "and rolls back to the front tier")
	assert_gt(ball.position.x, _yd(from).x, "ahead of where it started")


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
