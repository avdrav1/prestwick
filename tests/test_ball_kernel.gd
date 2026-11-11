extends GutTest
## E7-S4: the ball's tick spelled out (Ball.run) and HeightField's reads on the packed tiles
## give the same answers, bit for bit, as the code they replaced, kept as test oracles
## (tests/fixtures/reference_ball.gd, reference_field.gd): every tick's position, velocity and
## state, and every read, on the playtest nine (fairways, rough, greens with tiers, bunkers,
## water, trees) and on small maps where the reads clamp at the edge or sit on a tile centre.

const SHOTS_PER_TEE := 14
const PUTTS_PER_GREEN := 12


func _nine() -> CourseData:
	return CourseSave.load_file(PlaytestNine.PATH)


## Small maps where the reads clamp or sit on a tile centre: one tile, one row, two by two, and
## a 7 x 5 map of mixed heights and surfaces with its second parcel column unowned.
func _small_maps() -> Array[CourseData]:
	var out: Array[CourseData] = []
	out.append(CourseData.create(1, 1, Surface.Type.FAIRWAY, 3))
	var row := CourseData.create(6, 1, Surface.Type.GREEN, 0)
	for i in 6:
		row.set_tile(i, 0, i % 3, Surface.Type.GREEN)
	out.append(row)
	var two := CourseData.create(2, 2, Surface.Type.ROUGH, 0)
	two.set_tile(1, 0, 4, Surface.Type.ROUGH)
	two.set_tile(1, 1, 7, Surface.Type.TREES)
	out.append(two)
	var mixed := CourseData.create(20, 5, Surface.Type.FAIRWAY, 2)
	var kinds := [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.ROUGH, Surface.Type.TREES,
			Surface.Type.WATER, Surface.Type.BUNKER]
	for j in 5:
		for i in 20:
			mixed.set_tile(i, j, (i * 3 + j * 5) % 8, kinds[(i + 2 * j) % kinds.size()])
	mixed.set_parcel_owned(Vector2i(1, 0), false)
	out.append(mixed)
	return out


## Points over and past `c`: a seeded scatter, every tile centre line and edge, and the map's
## edges and corners.
static func _points(c: CourseData, scatter: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var w := c.width * 5.0
	var h := c.height * 5.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 74
	for k in scatter:
		out.append(Vector2(rng.randf_range(-12.0, w + 12.0), rng.randf_range(-12.0, h + 12.0)))
	var step_i := maxi(c.width / 12, 1)
	var step_j := maxi(c.height / 12, 1)
	for j in range(0, c.height, step_j):
		for i in range(0, c.width, step_i):
			var y := rng.randf_range(0.0, h)
			var x := rng.randf_range(0.0, w)
			out.append(Vector2((i + 0.5) * 5.0, y))
			out.append(Vector2(x, (j + 0.5) * 5.0))
			out.append(Vector2((i + 0.5) * 5.0, (j + 0.5) * 5.0))
			out.append(Vector2(i * 5.0, j * 5.0))
	for p: Vector2 in [Vector2.ZERO, Vector2(2.5, 2.5), Vector2(w, h), Vector2(w - 2.5, h - 2.5),
			Vector2(-1.0, h * 0.5), Vector2(w + 1.0, h * 0.5), Vector2(w * 0.5, -0.3),
			Vector2(w * 0.5, h + 0.3), Vector2(2.5, h - 2.5), Vector2(w - 2.5, 2.5)]:
		out.append(p)
	return out


func test_height_field_reads_as_before() -> void:
	var courses := _small_maps()
	courses.append(_nine())
	var params := BallParams.load_default()
	var checked := 0
	for c: CourseData in courses:
		var now := HeightField.new(c, params)
		var was := ReferenceField.new(c, params)
		var bad := 0
		for p: Vector2 in _points(c, 3000):
			if now.height_at(p.x, p.y) != was.height_at(p.x, p.y) \
					or now.gradient_at(p.x, p.y) != was.gradient_at(p.x, p.y) \
					or now.surface_at(p.x, p.y) != was.surface_at(p.x, p.y) \
					or now.painted_surface_at(p.x, p.y) != was.painted_surface_at(p.x, p.y):
				bad += 1
				if bad <= 3:
					fail_test("%dx%d at %s: height %s / %s, slope %s / %s" % [c.width, c.height, p,
							now.height_at(p.x, p.y), was.height_at(p.x, p.y), now.gradient_at(p.x, p.y),
							was.gradient_at(p.x, p.y)])
			checked += 1
		assert_eq(bad, 0, "%d x %d: every read as before" % [c.width, c.height])
	assert_gt(checked, 5000)


func test_ball_reads_match_height_field() -> void:
	var courses := _small_maps()
	courses.append(_nine())
	for c: CourseData in courses:
		var field := HeightField.new(c, BallParams.load_default())
		var ball := Ball.new(c, 1)
		ball.start_roll(Vector2(2.5, 2.5), Vector2.ZERO)
		ball._take_terrain()
		var bad := 0
		for p: Vector2 in _points(c, 2000):
			var t := ball._terrain(p.x, p.y)
			if ball._ground(p.x, p.y) != field.height_at(p.x, p.y) \
					or Vector3(0.0, 0.0, field.height_at(p.x, p.y)).z != t.z \
					or ball._slope(p.x, p.y) != field.gradient_at(p.x, p.y):
				bad += 1
		assert_eq(bad, 0, "%d x %d: the tick's own reads are HeightField's" % [c.width, c.height])


## A Ball and a ReferenceBall launched alike, stepped side by side to rest: the Ball by
## Ball.run in chunks of `chunk` ticks (a guest's budget cuts a run anywhere), the reference a
## step at a time. Returns "" when every tick matched, else the first difference.
static func _side_by_side(c: CourseData, seed_value: int, start: Vector3, velocity: Vector3,
		putt: bool, cup: Vector2i, roll_factor: float, chunk: int, record: bool) -> String:
	var ball := Ball.new(c, seed_value)
	var ref := ReferenceBall.new(c, seed_value)
	for b: Variant in [ball, ref]:
		b.record_path = record
		b.roll_factor = roll_factor
		b.set_cup(cup)
		if putt:
			b.start_roll(Vector2(start.x, start.y), Vector2(velocity.x, velocity.y))
		else:
			b.launch(start, velocity)
	var tick := 0
	while not ref.is_at_rest():
		var k := 0
		while k < chunk and not ref.is_at_rest():
			ref.step()
			k += 1
		var n := ball.run(chunk)
		tick += k
		if n != k:
			return "tick %d: run stepped %d, the reference %d" % [tick, n, k]
		if ball.position != ref.position or ball.velocity != ref.velocity \
				or int(ball.state) != int(ref.state):
			return "tick %d: %s %s %d against %s %s %d" % [tick, ball.position, ball.velocity,
					ball.state, ref.position, ref.velocity, ref.state]
	if not ball.is_at_rest():
		return "tick %d: the ball still moves" % tick
	if ball.steps != ref.steps or ball.holed != ref.holed \
			or ball.penalty_strokes != ref.penalty_strokes or int(ball.hazard) != int(ref.hazard) \
			or ball.entry_point != ref.entry_point or ball.drop_point != ref.drop_point \
			or ball.hazard_position != ref.hazard_position \
			or ball.landing_position != ref.landing_position or ball.scattered != ref.scattered \
			or ball.scatter_from != ref.scatter_from or ball.stop_point != ref.stop_point \
			or ball.stop_velocity != ref.stop_velocity or ball.bounces != ref.bounces \
			or ball.path != ref.path:
		return "at rest: the outcome differs (holed %s/%s, penalty %d/%d, drop %s/%s)" % [
				ball.holed, ref.holed, ball.penalty_strokes, ref.penalty_strokes, ball.drop_point,
				ref.drop_point]
	return ""


func test_flights_and_rolls_tick_for_tick_on_the_nine() -> void:
	var c := _nine()
	var field := HeightField.new(c, BallParams.load_default())
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var shots := 0
	var hazards := 0
	var scattered := 0
	for h: HoleData in c.holes:
		var tee := field.tile_center(h.tee)
		var cup := field.tile_center(h.cup)
		var line := rad_to_deg((cup - tee).angle())
		for k in SHOTS_PER_TEE:
			# Drives, irons and wild ones: into trees, water and over the white stakes too.
			var start := Vector3(tee.x, tee.y, field.height_at(tee.x, tee.y))
			var v := Ball.launch_velocity(rng.randf_range(20.0, 75.0), rng.randf_range(8.0, 40.0),
					line + rng.randf_range(-70.0, 70.0))
			var why := _side_by_side(c, rng.randi(), start, v, false, h.cup,
					rng.randf_range(0.6, 1.2), rng.randi_range(1, 9), k % 3 != 0)
			assert_eq(why, "", "hole %d shot %d" % [h.number, k])
			shots += 1
		for k in PUTTS_PER_GREEN:
			# Putts and chips round the cup, some past it and off the green.
			var at := cup + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.5, 25.0)
			var to := (cup - at).normalized().rotated(deg_to_rad(rng.randf_range(-25.0, 25.0)))
			var why := _side_by_side(c, rng.randi(), Vector3(at.x, at.y, 0.0),
					Vector3(to.x, to.y, 0.0) * rng.randf_range(0.5, 18.0), true, h.cup, 1.0,
					rng.randi_range(1, 9), k % 2 == 0)
			assert_eq(why, "", "hole %d putt %d" % [h.number, k])
			shots += 1
	# What shots like these meet, by the reference: hazards and trees are covered.
	for k in 400:
		var h: HoleData = c.holes[k % c.holes.size()]
		var tee := field.tile_center(h.tee)
		var ref := ReferenceBall.new(c, k)
		ref.set_cup(h.cup)
		ref.launch(Vector3(tee.x, tee.y, field.height_at(tee.x, tee.y)), Ball.launch_velocity(
				20.0 + k % 55, 8.0 + k % 30, k * 37.0))
		ref.run_to_rest()
		hazards += 1 if ref.penalty_strokes > 0 else 0
		scattered += 1 if ref.scattered else 0
	assert_gt(shots, 200)
	assert_gt(hazards, 0, "some of these shots find water or OB")
	assert_gt(scattered, 0, "and some trees")


func test_a_ball_reads_a_write_at_its_next_run() -> void:
	var c := _nine()
	var h: HoleData = c.holes[0]
	var field := HeightField.new(c, BallParams.load_default())
	var cup := field.tile_center(h.cup)
	var at := cup + Vector2(9.0, 4.0)
	var ball := Ball.new(c, 5)
	var ref := ReferenceBall.new(c, 5)
	for b: Variant in [ball, ref]:
		b.set_cup(h.cup)
		b.start_roll(at, (cup - at).normalized() * 9.0)
	for i in 12:
		ref.step()
	ball.run(12)
	assert_eq(ball.position, ref.position)
	# Raise the ground just ahead of the ball, as the builder would between two frames.
	var next := field.tile_at(ball.position.x + ball.velocity.x * 0.5,
			ball.position.y + ball.velocity.y * 0.5)
	c.set_tile(next.x, next.y, mini(c.get_height(next.x, next.y) + 2, CourseData.MAX_HEIGHT),
			c.get_surface(next.x, next.y))
	while not ref.is_at_rest():
		ref.step()
	ball.run_to_rest()
	assert_eq(ball.position, ref.position, "the ball felt the new ground as the reference did")
	assert_eq(ball.steps, ref.steps)


func test_run_steps_as_step_does() -> void:
	var c := _nine()
	var h: HoleData = c.holes[2]
	var field := HeightField.new(c, BallParams.load_default())
	var tee := field.tile_center(h.tee)
	var a := Ball.new(c, 9)
	var b := Ball.new(c, 9)
	for ball: Ball in [a, b]:
		ball.record_path = true
		ball.launch(Vector3(tee.x, tee.y, 0.0), Ball.launch_velocity(55.0, 16.0, 30.0))
	assert_eq(a.run(0), 0, "a run of no ticks steps none")
	var n := a.run(25)
	assert_eq(n, 25)
	for i in 25:
		b.step()
	assert_eq(a.position, b.position)
	var rest := a.run_to_rest()
	var m := 0
	while not b.is_at_rest():
		b.step()
		m += 1
	assert_eq(rest, m, "run_to_rest counts its ticks")
	assert_eq(a.path, b.path)
	assert_eq(a.run(10), 0, "a ball at rest does not move")
	assert_eq(Ball.new(c, 1).run(5), 0, "nor one not launched")
