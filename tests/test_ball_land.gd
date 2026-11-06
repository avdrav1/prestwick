extends GutTest
## E6-S7: the ball on land the player does not own (D29, D15; docs/design.md Land and Ball,
## Cup and hazards). A tile of an unowned parcel plays as an `oob` tile: a ball that touches
## down on or rolls onto it is OB, one stroke and a drop that skips unowned tiles. A flight
## over unowned land that comes down on owned land plays on. The aim view draws the line
## between owned and unowned land before the shot. A fully owned course (New sandbox, every
## version 1 file) plays exactly as before.
##
## Courses are strips of 16-tile parcels along +x at height 0, 5 yd per tile, 16 tiles deep
## (one parcel row); y 42.5 is the centre of row 8. Parcel p holds x 80p to 80p + 80 yd.

const EPS := 0.001
const ROW_Y := 42.5
const PARCEL_YD := 80.0

var params: BallParams


func before_each() -> void:
	params = BallParams.load_default()


## `parcels` parcels wide, one deep, fairway at height 0, every parcel owned but `unowned`.
func _course(parcels: int, unowned: Array[int] = [], fill: Surface.Type = Surface.Type.FAIRWAY) -> CourseData:
	var c := CourseData.create(parcels * CourseData.PARCEL_TILES, CourseData.PARCEL_TILES, fill, 0)
	for p: int in unowned:
		c.set_parcel_owned(Vector2i(p, 0), false)
	return c


func _fly(course: CourseData, start: Vector3, v: Vector3, seed_value: int = 7) -> Ball:
	var ball := Ball.new(course, seed_value)
	ball.record_path = true
	ball.launch(start, v)
	ball.run_to_rest()
	return ball


func _roll(course: CourseData, start: Vector2, v: Vector2) -> Ball:
	var ball := Ball.new(course, 1)
	ball.record_path = true
	ball.start_roll(start, v)
	ball.run_to_rest()
	return ball


## Launch velocity whose flat carry is `carry` yd at `launch_deg`, along +x.
func _carry(carry: float, launch_deg: float) -> Vector3:
	var speed := sqrt(carry * params.gravity / sin(deg_to_rad(2.0 * launch_deg)))
	return Ball.launch_velocity(speed, launch_deg, 0.0)


func _tile(ball: Ball) -> Vector2i:
	return ball.field.tile_at(ball.position.x, ball.position.y)


# --- unowned land is an oob tile ---

func test_unowned_tiles_play_as_oob_and_owned_tiles_keep_their_surface() -> void:
	var c := _course(3, [1])
	c.set_tile(20, 8, 0, Surface.Type.GREEN)
	var field := HeightField.new(c, params)
	assert_eq(field.surface_at(10.0, ROW_Y), Surface.Type.FAIRWAY, "owned parcel 0")
	assert_eq(field.surface_at(102.5, ROW_Y), Surface.Type.OOB, "a green on unowned land is oob to the ball")
	assert_eq(field.surface_at(PARCEL_YD - EPS, ROW_Y), Surface.Type.FAIRWAY, "the last owned yard")
	assert_eq(field.surface_at(PARCEL_YD, ROW_Y), Surface.Type.OOB, "the land line at x 80")
	assert_eq(field.surface_at(2.0 * PARCEL_YD, ROW_Y), Surface.Type.FAIRWAY, "owned again at x 160")
	var ball := Ball.new(c, 1)
	assert_false(ball.may_rest_on(Vector2i(20, 8)), "no ball rests on unowned land")
	assert_false(ball.may_place_on(Vector2i(20, 8)), "nor is one placed there")
	assert_true(ball.may_place_on(Vector2i(15, 8)))
	assert_eq(ball.hazard_at(Vector2(100.0, ROW_Y)), Ball.Hazard.OB)


func test_unowned_land_keeps_its_real_heights() -> void:
	var c := _course(2, [1])
	for y in c.height:
		c.set_tile(16, y, 3, Surface.Type.ROUGH)
	var field := HeightField.new(c, params)
	assert_almost_eq(field.height_at(82.5, ROW_Y), 3.0 * field.yards_per_step, EPS)
	assert_gt(field.gradient_at(79.0, ROW_Y).x, 0.0, "a rise on unowned land still feeds the slope beside it")


func test_a_flight_that_touches_down_on_unowned_land_is_ob_and_drops_at_the_line() -> void:
	var c := _course(3, [1])
	var ball := _fly(c, Vector3(10, ROW_Y, 0), _carry(90.0, 30.0))
	assert_eq(ball.hazard, Ball.Hazard.OB)
	assert_eq(ball.penalty_strokes, 1)
	assert_almost_eq(ball.landing_position.x, 100.0, 0.5, "it came down 20 yd past the line")
	assert_almost_eq(ball.hazard_position.x, ball.landing_position.x, EPS, "stopped where it touched down")
	assert_almost_eq(ball.entry_point.x, PARCEL_YD, 0.01, "the track crossed the line at x 80")
	assert_eq(ball.drop_point, Vector3(77.5, ROW_Y, 0.0), "the owned tile before the line")
	assert_eq(ball.state, Ball.State.AT_REST)


func test_a_ball_that_rolls_onto_unowned_land_is_ob_even_if_it_would_roll_back() -> void:
	# The unowned parcel is flat for a tile, then rises 7 steps: on owned land the ball runs
	# onto it, up the rise and rolls back. As an oob tile, the first tick on it stops the
	# ball (D29), so it is OB even though it would have rolled back.
	var owned := _course(2)
	var c := _course(2, [1])
	for course: CourseData in [owned, c]:
		for y in course.height:
			for x in range(17, 24):
				course.set_tile(x, y, x - 16, Surface.Type.FAIRWAY)
	var back := _roll(owned, Vector2(70, ROW_Y), Vector2(25, 0))
	var furthest := 0.0
	for p in back.path:
		furthest = maxf(furthest, p.x)
	assert_eq(back.hazard, Ball.Hazard.NONE, "owned: no penalty")
	assert_gt(furthest, PARCEL_YD + 5.0, "owned: it ran onto parcel 1")
	assert_lt(back.position.x, furthest - 1.0, "owned: and rolled back")
	var ball := _roll(c, Vector2(70, ROW_Y), Vector2(25, 0))
	assert_eq(ball.hazard, Ball.Hazard.OB)
	assert_eq(ball.penalty_strokes, 1)
	assert_almost_eq(ball.entry_point.x, PARCEL_YD, 0.01)
	assert_lt(ball.hazard_position.x - PARCEL_YD, 25.0 / 60.0 + EPS, "stopped on its first tick past the line")
	assert_eq(ball.drop_point, Vector3(77.5, ROW_Y, 0.0))


func test_a_flight_over_unowned_land_that_comes_down_on_owned_land_plays_on() -> void:
	var c := _course(4, [1])
	var ball := _fly(c, Vector3(40, ROW_Y, 0), _carry(140.0, 30.0))
	assert_eq(ball.hazard, Ball.Hazard.NONE)
	assert_eq(ball.penalty_strokes, 0)
	assert_gt(ball.landing_position.x, 2.0 * PARCEL_YD, "came down on parcel 2")
	assert_true(c.is_owned(_tile(ball).x, _tile(ball).y), "rests on owned land")
	var owned := _fly(_course(4), Vector3(40, ROW_Y, 0), _carry(140.0, 30.0))
	assert_eq(ball.position, owned.position, "the same shot as over owned land")


func test_the_drop_walks_back_past_unowned_tiles() -> void:
	# Parcel 1 is not owned and parcel 2 has water from x 160: a long shot carries the unowned
	# land and lands in the water. The tile before the water's entry is unowned, so the walk
	# goes on back over parcel 1 to the last owned tile, 15.
	var c := _course(3, [1])
	for y in c.height:
		for x in range(32, 40):
			c.set_tile(x, y, 0, Surface.Type.WATER)
	var ball := _fly(c, Vector3(10, ROW_Y, 0), _carry(170.0, 30.0))
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_almost_eq(ball.entry_point.x, 2.0 * PARCEL_YD, 0.01)
	assert_eq(ball.drop_point, Vector3(77.5, ROW_Y, 0.0), "tile 15, the last owned tile on the track")


func test_a_tree_scatter_never_lands_on_unowned_land() -> void:
	# Trees fill parcel 0 but its last column (tile 15); parcel 1 is open fairway, not owned.
	# A low shot back into the trees is blocked and scattered back toward +x, 5 to 10 yd: on
	# to tile 15 or over the line. Unowned land is rejected as oob is, so it rests on tile 15.
	var c := _course(2, [1], Surface.Type.TREES)
	for y in c.height:
		for x in range(15, 32):
			c.set_tile(x, y, 0, Surface.Type.FAIRWAY)
	for seed_value in 20:
		var ball := _fly(c, Vector3(77.5, ROW_Y, 0), Ball.launch_velocity(20.0, 5.0, 180.0), seed_value)
		assert_true(ball.scattered, "seed %d: blocked by the trees" % seed_value)
		assert_eq(ball.hazard, Ball.Hazard.NONE, "seed %d: no penalty" % seed_value)
		assert_eq(ball.state, Ball.State.AT_REST)
		assert_eq(_tile(ball).x, 15, "seed %d: on the owned column, at %s" % [seed_value, ball.position])


func test_the_prediction_sees_the_land_line() -> void:
	var c := _course(3, [1])
	var p := ShotPrediction.run(c, 7, Vector3(10, ROW_Y, 0), _carry(90.0, 30.0))
	assert_eq(p.hazard, Ball.Hazard.OB, "the aim marker shows the OB outcome before the shot")
	assert_eq(p.penalty_strokes, 1)
	assert_eq(p.rest, Vector3(77.5, ROW_Y, 0.0))


# --- sandbox play is unchanged ---

func test_a_fully_owned_course_plays_every_tile_as_its_surface() -> void:
	var c := CourseBuilder.new_sandbox()
	var field := HeightField.new(c, params)
	for y in range(0, c.height, 7):
		for x in range(0, c.width, 7):
			assert_eq(field.surface_at(x * 5.0 + 2.5, y * 5.0 + 2.5), c.get_surface(x, y))
	assert_eq(field.surface_at(-1.0, 2.5), Surface.Type.OOB, "off the map is still OB")


func test_a_shot_that_stays_on_owned_land_is_unchanged_tick_for_tick() -> void:
	var owned := _course(3)
	var c := _course(3, [2])
	var a := _fly(owned, Vector3(10, ROW_Y, 0), _carry(90.0, 30.0))
	var b := _fly(c, Vector3(10, ROW_Y, 0), _carry(90.0, 30.0))
	assert_lt(a.position.x, 2.0 * PARCEL_YD, "it never reaches parcel 2")
	assert_eq(b.path, a.path)
	assert_eq(b.steps, a.steps)
	assert_eq(b.hazard, Ball.Hazard.NONE)


# --- the land line (LandBoundary, drawn by AimView) ---

func test_a_fully_owned_course_has_no_land_line() -> void:
	assert_eq(LandBoundary.segments(CourseBuilder.new_sandbox()).size(), 0)
	assert_eq(LandBoundary.segments(_course(3)).size(), 0)


func test_the_land_line_runs_along_each_owned_edge_that_meets_unowned_land() -> void:
	# Parcel 1 unowned between owned 0 and 2: one 16-tile edge at x 16 and one at x 32
	# (tile coordinates x 15.5 and 31.5 in Iso space); the map's own edges are not drawn.
	var c := _course(3, [1])
	var s := LandBoundary.segments(c)
	assert_eq(s.size(), 2 * 2 * 2 * CourseData.PARCEL_TILES, "32 tile edges, two halves each, two points a half")
	var xs: Dictionary = {}
	for k in range(0, s.size(), 2):
		assert_eq(s[k].x, s[k + 1].x, "each edge runs along y")
		assert_almost_eq(absf(s[k + 1].y - s[k].y), 0.5, EPS, "half a tile long (E3-S59: the ground bends at the middle)")
		xs[s[k].x] = true
	assert_eq(xs.keys().size(), 2)
	assert_true(xs.has(15.5) and xs.has(31.5), "at the two land lines: %s" % [xs.keys()])


func test_the_land_line_lies_on_the_ground() -> void:
	# E3-S59 (D50): on the drawn ground at every point, and on the higher side at a water bank.
	var c := _course(2, [1])
	c.set_tile(15, 3, 2, Surface.Type.FAIRWAY)
	c.set_tile(16, 5, 4, Surface.Type.FAIRWAY)
	c.set_tile(16, 8, 3, Surface.Type.WATER)
	var s := LandBoundary.segments(c)
	var raised := 0
	for k in range(0, s.size(), 2):
		var row := floori((s[k].y + s[k + 1].y) * 0.5 + 0.5)
		for p: Vector3 in [s[k], s[k + 1]]:
			var at := Vector2(p.x, p.y)
			var want := maxf(TerrainMesh.ground_in(c, Vector2i(15, row), at), TerrainMesh.ground_in(c, Vector2i(16, row), at))
			assert_almost_eq(p.z, want, EPS, "at %s" % p)
			if p.z > 0.0:
				raised += 1
	assert_gt(raised, 6, "it climbs the slopes of the raised tiles")
	var mid := Vector3.ZERO
	for p: Vector3 in s:
		if is_equal_approx(p.y, 5.0):
			mid = p
	assert_almost_eq(mid.z, 2.0, EPS, "half way up the step at the middle of the raised tile's edge")


func test_the_land_line_follows_a_corner_and_both_axes() -> void:
	# 2 x 2 parcels, only (0, 0) owned: its east and south edges, 16 tiles each.
	var c := CourseData.create(32, 32, Surface.Type.ROUGH, 0)
	c.set_parcel_owned(Vector2i(1, 0), false)
	c.set_parcel_owned(Vector2i(0, 1), false)
	c.set_parcel_owned(Vector2i(1, 1), false)
	var s := LandBoundary.segments(c)
	assert_eq(s.size(), 2 * 2 * 2 * CourseData.PARCEL_TILES)
	var along_y := 0
	var along_x := 0
	for k in range(0, s.size(), 2):
		if s[k].x == s[k + 1].x:
			assert_eq(s[k].x, 15.5)
			along_y += 1
		else:
			assert_eq(s[k].y, 15.5)
			along_x += 1
	assert_eq(along_y, 32)
	assert_eq(along_x, 32, "a diagonal neighbour alone draws nothing")


func test_the_aim_view_draws_the_land_line_with_the_aim() -> void:
	var c := _course(3, [1])
	var field := HeightField.new(c, params)
	var view := AimView.new()
	add_child_autofree(view)
	var start := Vector3(10, ROW_Y, 0)
	var p := ShotPrediction.run(c, 7, start, _carry(90.0, 30.0))
	view.show_prediction(field, p, false, start)
	assert_true(view.visible)
	var s := LandBoundary.segments(c)
	assert_eq(view.land_line.size(), s.size(), "every land-line edge, in screen space")
	assert_eq(view.land_line[0], Iso.point_to_screen(s[0]))
	view.clear()
	assert_eq(view.land_line.size(), 0)
	var sandbox := _course(3)
	view.show_prediction(HeightField.new(sandbox, params),
			ShotPrediction.run(sandbox, 7, start, _carry(90.0, 30.0)), false, start)
	assert_eq(view.land_line.size(), 0, "a fully owned course shows no line")


# --- E6-S7 review: trees on unowned land, the OB marker, the line's side and cover ---

## A putt's prediction, as ShotPrediction.run_launch builds it for the putter.
func _putt(course: CourseData, start: Vector2, v: Vector2) -> ShotPrediction:
	var ball := Ball.new(course, 1)
	ball.record_path = true
	ball.start_roll(start, v)
	return ShotPrediction._from(ball, Vector3(start.x, start.y, 0.0))


func test_trees_on_unowned_land_still_block_a_low_flight() -> void:
	# Parcel 1 is unowned and painted trees. A low flight over it that would come down on
	# owned parcel 2 is stopped by those trees, as trees past the stakes stop a ball, and
	# scattered back onto owned land; with the trees painted away it flies over and plays on.
	var open := _course(4, [1])
	var wooded := _course(4, [1])
	for y in wooded.height:
		for x in range(16, 32):
			wooded.set_tile(x, y, 0, Surface.Type.TREES)
	var v := _carry(110.0, 5.0)
	var a := _fly(open, Vector3(60, ROW_Y, 0), v)
	assert_false(a.scattered)
	assert_gt(a.landing_position.x, 2.0 * PARCEL_YD, "comes down on owned parcel 2")
	var b := _fly(wooded, Vector3(60, ROW_Y, 0), v)
	assert_true(b.scattered, "the unowned trees block it")
	assert_lt(b.scatter_from.x, PARCEL_YD + 5.0, "at the first tree tile")
	assert_eq(b.hazard, Ball.Hazard.NONE)
	assert_lt(b.position.x, PARCEL_YD, "scattered back onto owned land")


func test_a_climbing_shot_into_unowned_trees_is_blocked() -> void:
	# D20: a shot from beside an unowned tree stand still climbing as it reaches them.
	var c := _course(3, [1])
	for y in c.height:
		for x in range(16, 32):
			c.set_tile(x, y, 0, Surface.Type.TREES)
	var p := ShotPrediction.run(c, 7, Vector3(77.5, ROW_Y, 0), _carry(150.0, 30.0))
	assert_true(p.scattered)
	assert_true(p.stopped_climbing, "ClubSet.is_blocked reads this")


func test_the_aim_marker_shows_the_ob_cue_for_a_putt_over_the_line() -> void:
	var c := CourseData.create(32, 16, Surface.Type.GREEN, 0)
	c.set_parcel_owned(Vector2i(1, 0), false)
	var p := _putt(c, Vector2(60, ROW_Y), Vector2(14, 0))
	assert_eq(p.hazard, Ball.Hazard.OB)
	assert_almost_eq(p.hazard_position.x, PARCEL_YD, 0.5, "stopped as it crossed the line")
	var field := HeightField.new(c, params)
	var view := AimView.new()
	add_child_autofree(view)
	view.show_prediction(field, p, true, Vector3(60, ROW_Y, 0))
	assert_eq(view.hazard_cue, Ball.Hazard.OB)
	assert_false(view.show_ring, "the cue, not the rest ring at the drop")
	assert_eq(view.marker_point, p.hazard_position, "where the dots end")
	assert_eq(view.hazard_screen, field.ground_screen(p.hazard_position))


func test_the_aim_marker_keeps_the_landing_ring_for_a_roll_over_the_line() -> void:
	var c := _course(3, [1])
	var start := Vector3(10, ROW_Y, 0)
	var view := AimView.new()
	add_child_autofree(view)
	var field := HeightField.new(c, params)
	# Lands on the line's far side: the cue takes the ring's place.
	var in_ob := ShotPrediction.run(c, 7, start, _carry(90.0, 30.0))
	view.show_prediction(field, in_ob, false, start)
	assert_eq(view.hazard_cue, Ball.Hazard.OB)
	assert_false(view.show_ring)
	# A clean shot on owned land: no cue.
	var clean := ShotPrediction.run(c, 7, start, _carry(40.0, 30.0))
	view.show_prediction(field, clean, false, start)
	assert_eq(view.hazard_cue, Ball.Hazard.NONE)
	assert_true(view.show_ring)
	# A low runner that lands owned and rolls over: ring at the landing and the cue.
	var runner := ShotPrediction.run(c, 7, start, _carry(55.0, 8.0))
	assert_eq(runner.hazard, Ball.Hazard.OB, "rolls over the line")
	assert_lt(runner.landing.x, PARCEL_YD, "lands on owned land")
	view.show_prediction(field, runner, false, start)
	assert_eq(view.hazard_cue, Ball.Hazard.OB)
	assert_true(view.show_ring)


func test_the_land_line_ticks_point_into_unowned_land() -> void:
	var c := _course(3, [1])
	var s := LandBoundary.segments(c)
	for k in range(0, s.size(), 2):
		var side := LandBoundary.unowned_side(c, s[k], s[k + 1])
		var want := Vector2(1, 0) if s[k].x == 15.5 else Vector2(-1, 0)
		assert_almost_eq(side.x, want.x, EPS, "edge at x %s" % s[k].x)
		assert_almost_eq(side.y, want.y, EPS)
	var view := AimView.new()
	add_child_autofree(view)
	var start := Vector3(10, ROW_Y, 0)
	view.show_prediction(HeightField.new(c, params),
			ShotPrediction.run(c, 7, start, _carry(40.0, 30.0)), false, start)
	assert_eq(view.land_ticks.size(), view.land_line.size(), "one tick per edge")
	assert_eq(view.land_hidden.size(), s.size() / 2)


func test_a_hill_in_front_hides_the_land_line_behind_it() -> void:
	# 2 x 2 parcels, (0, 1) and (1, 1) unowned: the line runs along x at y 15.5, height 0.
	# A height-7 hill on unowned tiles x 4 to 11, rows 18 to 22, in front of the line (nearer
	# the camera) covers the edges behind it; edges clear of it stay drawn.
	var c := CourseData.create(32, 32, Surface.Type.ROUGH, 0)
	c.set_parcel_owned(Vector2i(0, 1), false)
	c.set_parcel_owned(Vector2i(1, 1), false)
	var flat := LandBoundary.segments(c)
	for k in range(0, flat.size(), 2):
		assert_false(LandBoundary.covered(c, flat[k], flat[k + 1]), "flat land hides nothing")
	for y in range(18, 23):
		for x in range(4, 12):
			c.set_tile(x, y, 7, Surface.Type.ROUGH)
	var s := LandBoundary.segments(c)
	var hidden := {}
	for k in range(0, s.size(), 2):
		hidden[int(s[k].x + 0.5)] = LandBoundary.covered(c, s[k], s[k + 1])
	assert_true(hidden[8], "the edge straight behind the hill")
	assert_false(hidden[28], "an edge far to the side")
	# A hill behind the line (on owned land, further from the camera) hides nothing.
	var behind := CourseData.create(32, 32, Surface.Type.ROUGH, 0)
	behind.set_parcel_owned(Vector2i(0, 1), false)
	behind.set_parcel_owned(Vector2i(1, 1), false)
	for y in range(8, 13):
		for x in range(4, 12):
			behind.set_tile(x, y, 7, Surface.Type.ROUGH)
	var sb := LandBoundary.segments(behind)
	for k in range(0, sb.size(), 2):
		assert_false(LandBoundary.covered(behind, sb[k], sb[k + 1]))
