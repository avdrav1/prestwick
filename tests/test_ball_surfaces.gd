extends GutTest
## E2-S6: every surface, the cup and the hazards (D15; docs/design.md Ball, Cup and hazards).
## Courses are strips along +x at height 0, 5 yd per tile; y 27.5 is the centre of row 5.

const EPS := 0.001
const ROW_Y := 27.5

var params: BallParams
var table: SurfaceTable


func before_each() -> void:
	params = BallParams.load_default()
	table = SurfaceTable.load_default()


func _course(fill: Surface.Type = Surface.Type.FAIRWAY, width: int = 40, height: int = 11) -> CourseData:
	return CourseData.create(width, height, fill, 0)


## Paints tiles x0 to x1 (both included) of every row with `surface`.
func _band(course: CourseData, x0: int, x1: int, surface: Surface.Type) -> void:
	for y in course.height:
		for x in range(x0, x1 + 1):
			course.set_tile(x, y, course.get_height(x, y), surface)


func _fly(course: CourseData, start: Vector3, v: Vector3, seed_value: int = 7,
		cup: Vector2i = Ball.NO_CUP) -> Ball:
	var ball := Ball.new(course, seed_value)
	ball.record_path = true
	ball.set_cup(cup)
	ball.launch(start, v)
	ball.run_to_rest()
	return ball


func _roll(course: CourseData, start: Vector2, v: Vector2, cup: Vector2i = Ball.NO_CUP) -> Ball:
	var ball := Ball.new(course, 1)
	ball.record_path = true
	ball.set_cup(cup)
	ball.start_roll(start, v)
	ball.run_to_rest()
	return ball


## Launch velocity whose flat carry is `carry` yd at `launch_deg`, along +x.
func _carry(carry: float, launch_deg: float) -> Vector3:
	var speed := sqrt(carry * params.gravity / sin(deg_to_rad(2.0 * launch_deg)))
	return Ball.launch_velocity(speed, launch_deg, 0.0)


func _tile(ball: Ball) -> Vector2i:
	return ball.field.tile_at(ball.position.x, ball.position.y)


func _assert_rests_on_open_ground(ball: Ball, label: String) -> void:
	assert_eq(ball.state, Ball.State.AT_REST, label + ": at rest")
	assert_true(ball.may_rest_on(_tile(ball)), label + ": rests on %s at %s, not water, OB or trees"
			% [Surface.name_of(ball.field.surface_at(ball.position.x, ball.position.y)), _tile(ball)])


# --- the table ---

func test_trees_row_no_longer_copies_rough() -> void:
	var trees := table.row(Surface.Type.TREES)
	var rough := table.row(Surface.Type.ROUGH)
	assert_eq(trees.roll, 0.0, "a ball never rolls on trees: it stops at their edge")
	assert_eq(trees.bounce, 0.0)
	assert_eq(trees.bounce_friction, 1.0)
	assert_eq(trees.scatter_deg, 0.0, "tree scatter is the flight rule, not a bounce turn")
	assert_eq(trees.block_height, 10.0, "trees block a flight below 10 yd")
	assert_ne(trees.roll, rough.roll)
	for s in Surface.COUNT:
		if s != Surface.Type.TREES:
			assert_eq(table.row(s).block_height, 0.0, "only trees block a flight (%s)" % Surface.name_of(s))


func test_cup_and_scatter_tunables_come_from_the_resource() -> void:
	assert_eq(params.cup_radius, 0.3, "E3-S51: 0.25 before")
	assert_eq(params.cup_capture_speed, 2.0)
	assert_eq(params.cup_clear_drop_yd, 2.4)
	assert_eq(params.tree_scatter_min_yd, 5.0, "1 tile")
	assert_eq(params.tree_scatter_max_yd, 10.0, "2 tiles")
	assert_eq(params.tree_scatter_cone_deg, 90.0)
	assert_eq(params.tree_scatter_draws, 8)


# --- one case per surface ---

func test_fairway_tee_rough_green_bounce_once_and_rest_on_their_ground() -> void:
	var start := Vector3(10, ROW_Y, 0)
	var v := Vector3(30, 0, 15)
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.TEE, Surface.Type.ROUGH, Surface.Type.GREEN]:
		var ball := _fly(_course(s), start, v)
		assert_eq(ball.bounces, 1, "%s: one bounce" % Surface.name_of(s))
		assert_gt(ball.position.x, ball.landing_position.x, "%s: rolls on" % Surface.name_of(s))
		assert_eq(ball.penalty_strokes, 0, Surface.name_of(s))
		assert_false(ball.scattered, Surface.name_of(s))
		_assert_rests_on_open_ground(ball, Surface.name_of(s))


func test_bunker_stops_a_flight_and_a_rolling_ball() -> void:
	var c := _course()
	_band(c, 20, 24, Surface.Type.BUNKER)
	var flight := _fly(c, Vector3(10, ROW_Y, 0), _carry(100.0, 30.0))
	assert_eq(flight.bounces, 0, "no bounce out of sand")
	assert_eq(flight.position, flight.landing_position, "stops where it lands")
	assert_eq(c.get_surface(_tile(flight).x, _tile(flight).y), Surface.Type.BUNKER)
	var rolled := _roll(c, Vector2(80, ROW_Y), Vector2(20, 0))
	assert_eq(_tile(rolled), Vector2i(20, 5), "a rolling ball stops on the first bunker tick")
	assert_lt(rolled.position.x, 100.0 + 20.0 / 60.0 + EPS)
	assert_eq(rolled.penalty_strokes, 0, "a bunker is not a hazard that drops")


func test_cart_path_bounces_hard_and_rolls_at_1_6() -> void:
	assert_eq(table.row(Surface.Type.CART_PATH).roll, 1.6)
	assert_eq(table.row(Surface.Type.CART_PATH).bounce, 0.5)
	var start := Vector3(10, ROW_Y, 0)
	var v := Vector3(30, 0, 15)
	var apex := {}
	var run := {}
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.CART_PATH]:
		var ball := _fly(_course(s, 80), start, v)
		var top := 0.0
		var landed := false
		for p in ball.path:
			if absf(p.x - ball.landing_position.x) < EPS:
				landed = true
			if landed:
				top = maxf(top, p.z)
		apex[s] = top
		run[s] = ball.position.x - ball.landing_position.x
	assert_gt(apex[Surface.Type.CART_PATH], 2.0 * apex[Surface.Type.FAIRWAY],
			"the bounce off cart path is far higher: %.2f against %.2f yd" % [apex[Surface.Type.CART_PATH], apex[Surface.Type.FAIRWAY]])
	assert_gt(run[Surface.Type.CART_PATH], run[Surface.Type.FAIRWAY], "and it runs further")


# --- water ---

func test_water_flight_drops_before_the_entry_point_with_one_stroke() -> void:
	var c := _course()
	_band(c, 20, 24, Surface.Type.WATER)
	var ball := _fly(c, Vector3(10, ROW_Y, 0), _carry(100.0, 30.0))
	assert_almost_eq(ball.landing_position.x, 110.0, 0.05, "lands in the water")
	assert_eq(ball.penalty_strokes, 1)
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_almost_eq(ball.entry_point.x, 100.0, 0.01, "the track crossed into the water at x 100")
	assert_almost_eq(ball.entry_point.y, ROW_Y, EPS)
	assert_almost_eq(ball.hazard_position.x, 110.0, 0.05, "it stopped where it landed")
	assert_eq(ball.drop_point, Vector3(97.5, ROW_Y, 0.0), "the centre of tile 19, before the entry")
	assert_eq(ball.position, ball.drop_point, "the ball is placed at the drop")
	assert_eq(ball.state, Ball.State.AT_REST)
	assert_eq(ball.path[ball.path.size() - 1], ball.hazard_position, "the drawn path ends in the water")


func test_water_roll_drops_on_the_tile_it_rolled_in_from() -> void:
	var c := _course()
	_band(c, 20, 24, Surface.Type.WATER)
	var ball := _roll(c, Vector2(80, 26), Vector2(20, 0))
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_eq(ball.penalty_strokes, 1)
	assert_almost_eq(ball.entry_point.x, 100.0, 0.01)
	assert_eq(ball.drop_point, Vector3(97.5, ROW_Y, 0.0), "row 5's tile 19, at its centre")


func test_a_drop_on_a_slope_is_never_stepped_again() -> void:
	var c := _course()
	for y in c.height:
		c.set_tile(18, y, 2, Surface.Type.FAIRWAY)
	_band(c, 20, 24, Surface.Type.WATER)
	var ball := _fly(c, Vector3(10, ROW_Y, 4.0), _carry(100.0, 30.0))
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_ne(ball.field.gradient_at(ball.position.x, ball.position.y), Vector2.ZERO, "the drop tile slopes")
	var at := ball.position
	for i in 120:
		ball.step()
	assert_eq(ball.position, at, "placed at rest: it cannot roll back in")
	assert_eq(ball.state, Ball.State.AT_REST)


func test_drop_walks_back_past_water_oob_and_trees() -> void:
	# Trees on 18, water on 19, oob from 20: a lob over them all lands OB. The tile before the
	# OB entry is water, then trees, so the drop is tile 17's centre.
	var c := _course()
	_band(c, 18, 18, Surface.Type.TREES)
	_band(c, 19, 19, Surface.Type.WATER)
	_band(c, 20, 24, Surface.Type.OOB)
	var ball := _fly(c, Vector3(10, ROW_Y, 0), _carry(100.0, 80.0))
	assert_false(ball.scattered, "a steep lob clears the trees")
	assert_eq(ball.hazard, Ball.Hazard.OB)
	assert_almost_eq(ball.entry_point.x, 100.0, 0.01)
	assert_eq(ball.drop_point, Vector3(87.5, ROW_Y, 0.0))


func test_drop_falls_back_to_the_stroke_start() -> void:
	# Struck from an oob tile over oob into water: no tile on the track may hold a ball.
	var c := _course()
	_band(c, 0, 19, Surface.Type.OOB)
	_band(c, 20, 24, Surface.Type.WATER)
	var start := Vector3(12.5, ROW_Y, 0)
	var ball := _fly(c, start, _carry(100.0, 30.0))
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_eq(ball.drop_point, start)


func test_the_fallback_drop_is_never_within_the_cup_radius() -> void:
	# E2-S13: struck from beside the cup's centre (inside cup_radius) over water. The cup's tile
	# is the only open tile on the track and takes no placed ball, so the drop falls back; the
	# stroke's start would leave a free tap-in, so it is the nearest tile centre that may take a
	# ball instead (one fairway tile, off the track).
	var c := _course(Surface.Type.WATER)
	var cup := Vector2i(10, 5)
	c.set_tile(cup.x, cup.y, 0, Surface.Type.GREEN)
	c.set_tile(10, 1, 0, Surface.Type.FAIRWAY)
	var start := Vector3(52.5 + params.cup_radius * 0.5, ROW_Y, 0)
	var ball := _fly(c, start, _carry(40.0, 30.0), 7, cup)
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_false(ball.holed)
	assert_eq(ball.drop_point, Vector3(52.5, 7.5, 0.0), "the nearest tile centre that takes a ball")
	_assert_fallback_clear_of_cup(c, ball, cup)


func test_the_fallback_drop_with_nowhere_to_place_a_ball_stays_clear_of_the_cup() -> void:
	# The cup's tile is the only open tile on the whole map: the drop stays on it, but
	# cup_clear_drop_yd from the cup's centre, on the side the stroke started.
	var c := _course(Surface.Type.WATER)
	var cup := Vector2i(10, 5)
	c.set_tile(cup.x, cup.y, 0, Surface.Type.GREEN)
	var start := Vector3(52.5 - params.cup_radius * 0.5, ROW_Y, 0)
	var ball := _fly(c, start, _carry(40.0, 30.0), 7, cup)
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_lt(params.cup_clear_drop_yd, 2.5, "inside the cup's tile")
	assert_gt(params.cup_clear_drop_yd, params.cup_radius)
	assert_almost_eq(ball.drop_point, Vector3(52.5 - params.cup_clear_drop_yd, ROW_Y, 0.0),
			Vector3(EPS, EPS, EPS))
	assert_eq(_tile(ball), cup, "on the only tile a ball may rest on")
	_assert_fallback_clear_of_cup(c, ball, cup)


func test_a_fallback_drop_from_a_start_clear_of_the_cup_is_still_the_start() -> void:
	var c := _course(Surface.Type.WATER)
	var cup := Vector2i(10, 5)
	c.set_tile(cup.x, cup.y, 0, Surface.Type.GREEN)
	c.set_tile(10, 1, 0, Surface.Type.FAIRWAY)
	var start := Vector3(51.0, ROW_Y, 0)
	var ball := _fly(c, start, _carry(40.0, 30.0), 7, cup)
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_eq(ball.drop_point, start, "a start clear of the cup is the drop of last resort (D15)")


func _assert_fallback_clear_of_cup(c: CourseData, ball: Ball, cup: Vector2i) -> void:
	var drop := Vector2(ball.drop_point.x, ball.drop_point.y)
	assert_gt(drop.distance_to(ball.cup_center()), params.cup_radius, "clear of the cup")
	assert_true(ball.may_rest_on(_tile(ball)), "on ground that may hold a ball")
	for speed: float in [0.0, 0.1, 0.3]:
		var to_cup := (ball.cup_center() - drop).normalized()
		var tap := _roll(c, drop, to_cup * speed, cup)
		assert_false(tap.holed, "a %.1f yd/s tap toward the cup from the drop is not holed" % speed)


# --- out of bounds ---

func test_oob_tile_costs_a_stroke_and_drops_at_entry() -> void:
	var c := _course()
	_band(c, 20, 24, Surface.Type.OOB)
	var ball := _fly(c, Vector3(10, ROW_Y, 0), _carry(100.0, 30.0))
	assert_eq(ball.hazard, Ball.Hazard.OB)
	assert_eq(ball.penalty_strokes, 1)
	assert_almost_eq(ball.entry_point.x, 100.0, 0.01)
	assert_eq(ball.drop_point, Vector3(97.5, ROW_Y, 0.0))
	var rolled := _roll(c, Vector2(80, ROW_Y), Vector2(20, 0))
	assert_eq(rolled.hazard, Ball.Hazard.OB, "rolling onto oob")
	assert_eq(rolled.drop_point, Vector3(97.5, ROW_Y, 0.0))


func test_off_the_map_is_ob_and_drops_on_the_edge_tile() -> void:
	var c := _course()
	var ball := _roll(c, Vector2(185, ROW_Y), Vector2(30, 0))
	assert_eq(ball.hazard, Ball.Hazard.OB)
	assert_eq(ball.penalty_strokes, 1)
	assert_almost_eq(ball.entry_point.x, 200.0, 0.01, "the map ends at x 200")
	assert_eq(ball.drop_point, Vector3(197.5, ROW_Y, 0.0), "tile 39, the last on the map")
	var flight := _fly(c, Vector3(150, ROW_Y, 0), _carry(100.0, 30.0))
	assert_eq(flight.hazard, Ball.Hazard.OB, "a flight off the map")
	assert_eq(flight.drop_point, Vector3(197.5, ROW_Y, 0.0))
	var side := _roll(c, Vector2(100, 50), Vector2(0, 30))
	assert_eq(side.hazard, Ball.Hazard.OB, "off the side")
	assert_eq(side.drop_point, Vector3(102.5, 52.5, 0.0))


# --- trees ---

func test_rolling_into_trees_stops_at_their_edge() -> void:
	var c := _course()
	_band(c, 20, 24, Surface.Type.TREES)
	var ball := _roll(c, Vector2(80, ROW_Y), Vector2(20, 0))
	assert_eq(_tile(ball), Vector2i(19, 5), "rests outside the trees")
	assert_gt(ball.position.x, 100.0 - 20.0 / 60.0 - EPS, "where it was the tick before")
	assert_lt(ball.position.x, 100.0)
	assert_eq(ball.penalty_strokes, 0)
	assert_false(ball.scattered)


func test_a_low_flight_is_blocked_and_scattered_back_1_to_2_tiles() -> void:
	var c := _course()
	_band(c, 20, 24, Surface.Type.TREES)
	var start := Vector3(10, ROW_Y, 0)
	var ball := _fly(c, start, _carry(160.0, 12.0))
	assert_true(ball.scattered)
	var from := ball.scatter_from
	assert_eq(c.get_surface(ball.field.tile_at(from.x, from.y).x, 5), Surface.Type.TREES)
	assert_almost_eq(from.x, 100.0, 1.5, "blocked as it entered the trees")
	assert_lt(from.z, ball.field.height_at(from.x, from.y) + 10.0, "below the block height")
	var moved := Vector2(ball.position.x, ball.position.y) - Vector2(from.x, from.y)
	assert_between(moved.length(), 5.0 - EPS, 10.0 + EPS, "1 to 2 tiles")
	assert_lt(moved.x, EPS, "back toward the start, within 90 degrees of the reversed heading")
	assert_eq(ball.landing_position, ball.position, "it came down at the target and stayed")
	assert_eq(ball.penalty_strokes, 0)
	_assert_rests_on_open_ground(ball, "scatter")


func test_a_flight_above_the_block_height_clears_trees() -> void:
	var c := _course()
	_band(c, 12, 13, Surface.Type.TREES)
	var ball := _fly(c, Vector3(10, ROW_Y, 0), _carry(140.0, 40.0))
	assert_false(ball.scattered, "about 40 yd up over the trees")
	assert_almost_eq(ball.landing_position.x, 150.0, 0.1)


func test_block_height_counts_from_the_tree_tiles_top_not_the_bilinear_ground() -> void:
	# A 7-step tee pillar ringed by trees at height 0, as in courses/heights_20x20.json. A ball
	# leaving the pillar 14 yd up is above the drawn trees (0 + 10 yd), although the bilinear
	# ground under it leans up toward the pillar.
	var c := _course(Surface.Type.ROUGH, 30, 11)
	for y in range(4, 7):
		for x in range(14, 17):
			c.set_tile(x, y, 0, Surface.Type.TREES)
	c.set_tile(15, 5, 7, Surface.Type.TEE)
	var ball := _fly(c, Vector3(77.5, ROW_Y, 14.0), Ball.launch_velocity(20.0, 30.0, 180.0))
	assert_false(ball.scattered, "it clears the trees round the pillar")
	assert_lt(ball.landing_position.x, 70.0, "and lands past them")
	var low := _fly(c, Vector3(77.5, ROW_Y, 14.0), Ball.launch_velocity(20.0, -60.0, 180.0))
	assert_true(low.scattered, "a ball driven down into them is blocked")
	_assert_rests_on_open_ground(low, "down into the trees")


func test_block_height_is_read_from_the_trees_row() -> void:
	var c := _course()
	_band(c, 20, 36, Surface.Type.TREES)
	var low := table.duplicate(true) as SurfaceTable
	low.row(Surface.Type.TREES).block_height = 1.0
	var start := Vector3(10, ROW_Y, 0)
	var v := _carry(160.0, 12.0)
	var blocked := Ball.new(c, 7)
	blocked.launch(start, v)
	blocked.run_to_rest()
	var lower := Ball.new(c, 7, null, low)
	lower.launch(start, v)
	lower.run_to_rest()
	assert_true(blocked.scattered)
	assert_true(lower.scattered, "it still meets the trees lower down")
	assert_gt(lower.scatter_from.x, blocked.scatter_from.x + 5.0, "a 1 yd block lets it fly deeper in")


func test_scatter_never_rests_on_trees_water_or_oob() -> void:
	# Behind the trees a checker of water, oob and fairway, so many draws are rejected.
	var c := _course(Surface.Type.FAIRWAY, 40, 21)
	_band(c, 20, 24, Surface.Type.TREES)
	for y in c.height:
		for x in range(14, 20):
			var s: Surface.Type = [Surface.Type.WATER, Surface.Type.OOB, Surface.Type.FAIRWAY][(x + 2 * y) % 3]
			c.set_tile(x, y, 0, s)
	var bad := 0
	var scattered := 0
	for i in 200:
		var heading := -20.0 + 40.0 * float(i % 20) / 19.0
		var v := Ball.launch_velocity(60.0, 8.0, heading)
		var ball := Ball.new(c, i)
		ball.launch(Vector3(30, 52.5, 0), v)
		ball.run_to_rest()
		if ball.scattered:
			scattered += 1
		if not ball.may_rest_on(_tile(ball)) or ball.state != Ball.State.AT_REST:
			bad += 1
	assert_eq(scattered, 200, "every one of these low shots meets the trees")
	assert_eq(bad, 0, "no ball rests on trees, water or oob")


func test_scatter_falls_back_to_the_nearest_open_tile_centre() -> void:
	# Water short of the trees and trees everywhere past x 50, but one fairway tile two rings
	# out: every draw lands on water or trees, so the ball goes to that tile's centre.
	var c := _course(Surface.Type.WATER, 40, 11)
	_band(c, 10, 39, Surface.Type.TREES)
	c.set_tile(1, 5, 0, Surface.Type.FAIRWAY)
	c.set_tile(12, 6, 0, Surface.Type.FAIRWAY)
	var ball := _fly(c, Vector3(7.5, ROW_Y, 0), Ball.launch_velocity(70.0, 8.0, 0.0))
	assert_true(ball.scattered)
	assert_eq(ball.field.tile_at(ball.scatter_from.x, ball.scatter_from.y), Vector2i(10, 5))
	assert_eq(Vector2(ball.position.x, ball.position.y), Vector2(62.5, 32.5), "tile (12, 6)")
	assert_eq(ball.penalty_strokes, 0)


## E6-S13: water everywhere but the cup's tile (10, 5), a green, and trees from tile 14 on, so
## the cup's tile is the only tile on the map a ball may rest on.
func _cup_island_before_trees() -> CourseData:
	var c := _course(Surface.Type.WATER)
	c.set_tile(10, 5, 0, Surface.Type.GREEN)
	_band(c, 14, 39, Surface.Type.TREES)
	return c


## A ball placed at rest at `at` by a last-resort fallback: on ground that may hold it, clear of
## the cup, and no tap toward the cup from there is holed.
func _assert_placed_clear_of_cup(c: CourseData, ball: Ball, cup: Vector2i, label: String) -> void:
	var at := Vector2(ball.position.x, ball.position.y)
	assert_false(ball.holed, label + ": not holed")
	assert_eq(ball.penalty_strokes, 0, label + ": no penalty")
	assert_eq(ball.state, Ball.State.AT_REST, label + ": at rest")
	assert_gt(at.distance_to(ball.cup_center()), params.cup_radius, label + ": clear of the cup")
	assert_true(ball.may_rest_on(_tile(ball)), label + ": on ground that may hold a ball")
	for speed: float in [0.0, 0.1, 0.3]:
		var to_cup := (ball.cup_center() - at).normalized()
		var tap := _roll(c, at, to_cup * speed, cup)
		assert_false(tap.holed, label + ": a %.1f yd/s tap toward the cup is not holed" % speed)


func test_a_scatter_with_no_other_open_tile_stays_clear_of_the_cup() -> void:
	# Struck from beside the cup's centre (inside cup_radius) low into the trees. Every draw
	# comes down on water (5 to 10 yd back from x 70 is tiles 12 and 13), and no tile but the
	# cup's may take a placed ball, so the scatter falls to the last resort: the start would
	# leave a free tap-in, so cup_clear_drop_yd from the cup toward the start, on its tile.
	var c := _cup_island_before_trees()
	var cup := Vector2i(10, 5)
	var start := Vector3(52.5 + params.cup_radius * 0.5, ROW_Y, 0)
	for s: int in 10:
		var ball := _fly(c, start, Ball.launch_velocity(40.0, 8.0, 0.0), s, cup)
		var label := "seed %d" % s
		assert_true(ball.scattered, label + ": the low flight meets the trees")
		assert_eq(ball.field.tile_at(ball.scatter_from.x, ball.scatter_from.y), Vector2i(14, 5))
		assert_almost_eq(Vector2(ball.position.x, ball.position.y),
				Vector2(52.5 + params.cup_clear_drop_yd, ROW_Y), Vector2(EPS, EPS),
				label + ": cup_clear_drop_yd from the cup, toward the start")
		assert_eq(_tile(ball), cup, label + ": on the only tile a ball may rest on")
		_assert_placed_clear_of_cup(c, ball, cup, label)


func test_a_scatter_with_no_other_open_tile_from_a_start_clear_of_the_cup_is_the_start() -> void:
	var c := _cup_island_before_trees()
	var cup := Vector2i(10, 5)
	var start := Vector3(51.0, ROW_Y, 0)
	var ball := _fly(c, start, Ball.launch_velocity(40.0, 8.0, 0.0), 3, cup)
	assert_true(ball.scattered)
	assert_eq(ball.position, start, "a start clear of the cup is the place of last resort (D15)")
	_assert_placed_clear_of_cup(c, ball, cup, "start")


func test_a_scatter_draw_never_comes_down_on_the_cup() -> void:
	# The cup sits where the draws come down (tile 12, 5 to 10 yd back from the trees at x 70)
	# and its radius is widened to 2 yd so many draws fall inside it: a still ball there would
	# be holed on its next tick, so those draws are drawn again.
	var c := _course()
	_band(c, 14, 39, Surface.Type.TREES)
	var cup := Vector2i(12, 5)
	var wide := params.duplicate() as BallParams
	wide.cup_radius = 2.0
	var on_cup_tile := 0
	for s: int in 200:
		var ball := Ball.new(c, s, wide)
		ball.set_cup(cup)
		ball.launch(Vector3(52.5, ROW_Y, 0), Ball.launch_velocity(40.0, 8.0, 0.0))
		ball.run_to_rest()
		assert_true(ball.scattered, "seed %d: the low flight meets the trees" % s)
		var at := Vector2(ball.position.x, ball.position.y)
		if _tile(ball) == cup:
			on_cup_tile += 1
		if ball.holed or at.distance_to(ball.cup_center()) <= wide.cup_radius:
			fail_test("seed %d: the scatter came down %.2f yd from the cup" % [s,
					at.distance_to(ball.cup_center())])
			return
	assert_gt(on_cup_tile, 10, "the draws do reach the cup's tile")


func test_a_ball_stopped_on_trees_with_no_other_open_tile_stays_clear_of_the_cup() -> void:
	# The trees rest: with block_height 0 a flight comes down on the trees (roll 0) and is moved
	# to the nearest tile centre the game may place a ball on. The cup's tile is the only tile a
	# ball may rest on and takes no placed ball, so it is the last resort, as for a drop.
	var c := _course(Surface.Type.TREES)
	var cup := Vector2i(10, 5)
	c.set_tile(cup.x, cup.y, 0, Surface.Type.GREEN)
	var open := table.duplicate(true) as SurfaceTable
	open.row(Surface.Type.TREES).block_height = 0.0
	for start: Vector3 in [Vector3(52.5 - params.cup_radius * 0.5, ROW_Y, 0), Vector3(51.0, ROW_Y, 0)]:
		var ball := Ball.new(c, 7, null, open)
		ball.set_cup(cup)
		ball.launch(start, _carry(40.0, 30.0))
		ball.run_to_rest()
		var label := "from x %.3f" % start.x
		assert_false(ball.scattered, label + ": nothing blocks it")
		assert_eq(ball.field.tile_at(ball.landing_position.x, ball.landing_position.y),
				Vector2i(18, 5), label + ": it comes down on the trees")
		var at := Vector2(ball.position.x, ball.position.y)
		if Vector2(start.x, start.y).distance_to(ball.cup_center()) <= params.cup_radius:
			assert_almost_eq(at, Vector2(52.5 - params.cup_clear_drop_yd, ROW_Y), Vector2(EPS, EPS),
					label + ": cup_clear_drop_yd from the cup, toward the start")
		else:
			assert_eq(at, Vector2(start.x, start.y), label + ": the start, clear of the cup")
		_assert_placed_clear_of_cup(c, ball, cup, label)


func test_scatter_is_deterministic_by_seed() -> void:
	var c := _course()
	_band(c, 20, 24, Surface.Type.TREES)
	var v := _carry(160.0, 12.0)
	var first := _fly(c, Vector3(10, ROW_Y, 0), v, 11)
	for i in 20:
		var again := _fly(c, Vector3(10, ROW_Y, 0), v, 11)
		assert_eq(again.position, first.position, "same seed, same target")
	var targets := {}
	for s in 10:
		targets[_fly(c, Vector3(10, ROW_Y, 0), v, s).position] = true
	assert_gt(targets.size(), 5, "the seed drives the draw")
	var predicted := ShotPrediction.run(c, 11, Vector3(10, ROW_Y, 0), v)
	assert_true(predicted.scattered)
	assert_eq(predicted.rest, first.position, "the prediction matches the flight")


# --- the cup ---

func _cup_ball(course: CourseData, cup: Vector2i) -> Ball:
	var ball := Ball.new(course, 1)
	ball.set_cup(cup)
	return ball


func test_capture_at_inside_and_outside_its_radius_and_speed() -> void:
	var ball := _cup_ball(_course(Surface.Type.GREEN), Vector2i(10, 5))
	var c := ball.cup_center()
	assert_eq(c, Vector2(52.5, ROW_Y), "the cup sits at its tile centre")
	var r := params.cup_radius
	var fast := params.cup_capture_speed
	assert_true(ball.captures(c, 0.0), "dead centre")
	assert_true(ball.captures(c + Vector2(r * 0.5, 0), 1.0), "inside")
	assert_true(ball.captures(c + Vector2(0, r), 1.0), "at the radius")
	assert_false(ball.captures(c + Vector2(0, r + 0.01), 0.0), "just outside the radius")
	assert_true(ball.captures(c, fast), "at the capture speed")
	assert_false(ball.captures(c, fast + 0.01), "just over it")
	var none := Ball.new(_course(Surface.Type.GREEN), 1)
	assert_false(none.captures(c, 0.0), "no cup, no capture")


func test_a_ball_set_still_at_the_radius_is_holed_and_just_outside_is_not() -> void:
	var cup := Vector2i(10, 5)
	var r := params.cup_radius
	var at := _roll(_course(Surface.Type.GREEN), Vector2(52.5 + r, ROW_Y), Vector2.ZERO, cup)
	assert_true(at.holed, "rolls to rest at the radius: captured")
	assert_eq(Vector2(at.position.x, at.position.y), Vector2(52.5, ROW_Y), "rests at the cup's centre")
	var out := _roll(_course(Surface.Type.GREEN), Vector2(52.52 + r, ROW_Y), Vector2.ZERO, cup)
	assert_false(out.holed)


## The starting speed along +x of a roll from `from_x` that comes to rest at `rest_x`
## with no cup, by bisection.
func _speed_to_rest_at(course: CourseData, from_x: float, rest_x: float) -> float:
	var lo := 0.0
	var hi := 30.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		var ball := _roll(course, Vector2(from_x, ROW_Y), Vector2(mid, 0))
		if ball.position.x < rest_x:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Ground speed of a cupless roll at `from_x` with speed `v` as it first passes `at_x`.
func _speed_passing(course: CourseData, from_x: float, v: float, at_x: float) -> float:
	var ball := Ball.new(course, 1)
	ball.start_roll(Vector2(from_x, ROW_Y), Vector2(v, 0))
	while not ball.is_at_rest() and ball.position.x < at_x:
		ball.step()
	return Vector2(ball.velocity.x, ball.velocity.y).length()


func test_a_putt_dying_at_the_cup_drops_and_a_fast_one_rolls_over() -> void:
	var cup := Vector2i(10, 5)
	var green := _course(Surface.Type.GREEN)
	# Would stop 1 yd past the cup: slow over it.
	var v := _speed_to_rest_at(green, 42.5, 53.5)
	assert_lt(_speed_passing(green, 42.5, v, 52.5 - params.cup_radius), params.cup_capture_speed)
	var gentle := _roll(green, Vector2(42.5, ROW_Y), Vector2(v, 0), cup)
	assert_true(gentle.holed, "a %.2f yd/s putt from 10 yd is slow at the cup" % v)
	assert_eq(Vector2(gentle.position.x, gentle.position.y), Vector2(52.5, ROW_Y))
	assert_lt(gentle.steps, 480)
	# Would stop 5 yd past: over the capture speed across the whole cup.
	var hard := _speed_to_rest_at(green, 42.5, 57.5)
	assert_gt(_speed_passing(green, 42.5, hard, 52.5 + params.cup_radius), params.cup_capture_speed)
	var fast := _roll(green, Vector2(42.5, ROW_Y), Vector2(hard, 0), cup)
	assert_false(fast.holed, "a %.2f yd/s putt rolls over the cup" % hard)
	assert_almost_eq(fast.position.x, 57.5, 0.01, "and on as if there were none")
	var wide := _roll(green, Vector2(42.5, ROW_Y + params.cup_radius + 0.02), Vector2(v, 0), cup)
	assert_false(wide.holed, "just wider than the radius misses")
	var edge := _roll(green, Vector2(42.5, ROW_Y + params.cup_radius - 0.02), Vector2(v, 0), cup)
	assert_true(edge.holed, "just inside the radius drops")


func test_a_putt_that_stops_short_inside_the_radius_is_holed() -> void:
	var green := _course(Surface.Type.GREEN)
	var v := _speed_to_rest_at(green, 42.5, 52.5 - params.cup_radius * 0.5)
	var free := _roll(green, Vector2(42.5, ROW_Y), Vector2(v, 0))
	assert_between(free.position.x, 52.5 - params.cup_radius, 52.5,
			"with no cup it stops short, inside the radius: x %.3f" % free.position.x)
	var ball := _roll(green, Vector2(42.5, ROW_Y), Vector2(v, 0), Vector2i(10, 5))
	assert_true(ball.holed, "it rolls to rest inside the radius: captured")


func test_cup_captures_on_any_surface() -> void:
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.TEE,
			Surface.Type.CART_PATH, Surface.Type.GREEN]:
		var c := _course(s)
		var v := _speed_to_rest_at(c, 45.0, 52.6)
		var ball := _roll(c, Vector2(45.0, ROW_Y), Vector2(v, 0), Vector2i(10, 5))
		assert_true(ball.holed, "a slow roll into the cup on %s" % Surface.name_of(s))


func test_no_capture_at_touchdown() -> void:
	# A flight that touches down in the cup at full speed bounces on: the cup only checks on
	# rolling ticks, and the ball is far too fast for it by then.
	var c := _course(Surface.Type.GREEN)
	var v := _carry(42.5, 45.0)
	var ball := Ball.new(c, 1)
	ball.set_cup(Vector2i(10, 5))
	ball.launch(Vector3(10, ROW_Y, 0), v)
	while not ball.has_landed:
		ball.step()
	assert_almost_eq(ball.landing_position.x, 52.5, 0.05, "touched down in the cup")
	assert_false(ball.holed, "not captured at touchdown")
	ball.run_to_rest()
	assert_false(ball.holed, "it bounced and ran past")
	assert_gt(ball.position.x, 53.0)


func test_a_drop_skips_the_cup_tile() -> void:
	# The tile before the entry is the cup's: the drop walks on to the tile before it, so
	# the ball never sits on the cup's centre.
	var c := _course(Surface.Type.GREEN)
	_band(c, 20, 24, Surface.Type.WATER)
	var ball := _roll(c, Vector2(80, ROW_Y), Vector2(20, 0), Vector2i(19, 5))
	assert_eq(ball.hazard, Ball.Hazard.WATER)
	assert_eq(ball.drop_point, Vector3(92.5, ROW_Y, 0.0), "dropped one tile short of the cup")
	assert_false(ball.holed, "a drop is not a holed putt")
	assert_false(ball.may_place_on(Vector2i(19, 5)), "the cup's tile takes no placed ball")
	assert_true(ball.may_rest_on(Vector2i(19, 5)), "a played ball may still rest there")


func test_a_stroke_from_a_drop_is_never_holed_by_a_tap() -> void:
	# A shot carries over the cup into water beyond it. The track crossed the cup's tile just
	# before the entry, which used to drop the ball on the cup's centre for a free tap-in.
	var c := _course(Surface.Type.GREEN)
	_band(c, 11, 39, Surface.Type.WATER)
	var cup := Vector2i(10, 5)
	var shot := _fly(c, Vector3(12.5, ROW_Y, 0), _carry(46.0, 30.0), 7, cup)
	assert_eq(shot.hazard, Ball.Hazard.WATER, "into the water past the cup")
	assert_eq(shot.penalty_strokes, 1)
	assert_false(shot.holed)
	var drop := Vector2(shot.drop_point.x, shot.drop_point.y)
	assert_ne(shot.field.tile_at(drop.x, drop.y), cup, "not dropped on the cup's tile")
	assert_gt(drop.distance_to(shot.cup_center()), params.cup_radius, "clear of the cup")
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		for speed: float in [0.0, 0.5, 1.0, params.cup_capture_speed]:
			var tap := _roll(c, drop, dir * speed, cup)
			assert_false(tap.holed, "a %.1f yd/s tap %s from the drop is not holed" % [speed, dir])


func test_prediction_reports_holed_and_penalty() -> void:
	var c := _course(Surface.Type.GREEN)
	var putter := ClubSet.load_default().club("putter")
	var model := ShotModel.new()
	var field := HeightField.new(c, params)
	var putt := model.putt(field, putter, _speed_to_rest_at(c, 42.5, 53.5), Vector2(42.5, ROW_Y), 0.0)
	var p := ShotPrediction.run_launch(c, 1, putt, null, null, Vector2i(10, 5))
	assert_true(p.holed)
	assert_eq(p.rest, Vector3(52.5, ROW_Y, 0.0))
	var no_cup := ShotPrediction.run_launch(c, 1, putt)
	assert_false(no_cup.holed, "no cup by default")
	_band(c, 20, 24, Surface.Type.WATER)
	var wet := ShotPrediction.run(c, 1, Vector3(10, ROW_Y, 0), _carry(100.0, 30.0))
	assert_eq(wet.penalty_strokes, 1)
	assert_eq(wet.hazard, Ball.Hazard.WATER)
	assert_eq(wet.rest, Vector3(97.5, ROW_Y, 0.0), "the rest is the drop")
	assert_almost_eq(wet.path[wet.path.size() - 1].x, 110.0, 0.05, "the path ends in the water")
