extends GutTest
## E2-S5: lie multipliers (golf/lies.tres) and the uphill and sidehill numbers, read and
## applied as docs/design.md Swing, Shot model (D14) says.

const EPS := 0.001

var lies: LieTable
var params: BallParams


func before_each() -> void:
	lies = LieTable.load_default()
	params = BallParams.load_default()


func _field(c: CourseData) -> HeightField:
	return HeightField.new(c, params)


func _centre(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * params.yards_per_tile


# --- the multipliers ---

func test_the_table_loads_and_validates() -> void:
	assert_not_null(lies, "golf/lies.tres loads")
	assert_eq(lies.validate(), PackedStringArray())


func test_surface_multipliers_follow_the_distance_column() -> void:
	assert_eq(lies.multiplier_for(Surface.Type.FAIRWAY), 1.0)
	assert_eq(lies.multiplier_for(Surface.Type.TEE), 1.0)
	assert_between(lies.multiplier_for(Surface.Type.ROUGH), 0.8, 0.9, "rough 0.8 to 0.9")
	assert_eq(lies.multiplier_for(Surface.Type.BUNKER), 0.5)


func test_rough_is_one_fixed_value_never_rolled() -> void:
	# D14: the same lie always gives the same marker, whatever the seed.
	var model := ShotModel.new()
	var c := CourseData.create(60, 20, Surface.Type.ROUGH, 0)
	var field := _field(c)
	var club := model.clubs.club("7i")
	var a := model.full(field, club, 1.0, _centre(Vector2i(2, 10)), 0.0)
	var landings: Array[float] = []
	var seeds: Array[int] = [1, 2, 99]
	for s in seeds:
		var p := ShotPrediction.run_launch(c, s, a)
		landings.append(p.landing.x)
	assert_almost_eq(landings[0], landings[1], EPS)
	assert_almost_eq(landings[0], landings[2], EPS)
	assert_almost_eq(a.target_carry, club.carry_yd * lies.multiplier_for(Surface.Type.ROUGH), EPS)


func test_bunker_halves_the_carry() -> void:
	var model := ShotModel.new()
	var c := CourseData.create(30, 20, Surface.Type.BUNKER, 0)
	var sw := model.clubs.club("sw")
	var shot := model.full(_field(c), sw, 0.5, _centre(Vector2i(2, 10)), 0.0)
	assert_almost_eq(shot.target_carry, sw.carry_yd * 0.25, EPS, "SW at 50% in a bunker")
	var p := ShotPrediction.run_launch(c, 1, shot)
	assert_between(p.landing.x - shot.start.x, 20.0, 40.0, "the bunker target")


# --- rise (uphill) ---

## Flat at 0 up to tile column `edge`, then `steps` up.
func _riser(edge: int, steps: int) -> CourseData:
	var c := CourseData.create(30, 10, Surface.Type.FAIRWAY, 0)
	for y in 10:
		for x in range(edge + 1, 30):
			c.set_tile(x, y, steps, Surface.Type.FAIRWAY)
	return c


func test_rise_reads_steps_from_the_ground_ahead() -> void:
	var c := _riser(5, 2)
	var at := _centre(Vector2i(5, 5))
	var lie := lies.measure(_field(c), at, 0.0)
	assert_almost_eq(lie.rise, 2.0, EPS, "at the tile centre where a 2-step riser begins")
	assert_almost_eq(lie.uphill_multiplier, 1.0 - 2.0 * lies.uphill_k, EPS)
	var short := lies.measure(_field(c), at - Vector2(2.0, 0.0), 0.0)
	assert_almost_eq(short.rise, 2.0 * 3.0 / 5.0, EPS, "2 x (5 - d) / 5 at d = 2 yd short")
	var back := lies.measure(_field(c), at - Vector2(5.0, 0.0), 0.0)
	assert_almost_eq(back.rise, 0.0, EPS, "0 from 5 yd back")


func test_ground_behind_never_counts_and_downhill_does_nothing() -> void:
	var c := _riser(5, 2)
	# On the plateau's edge, aimed away from the riser: flat ahead.
	var top := lies.measure(_field(c), _centre(Vector2i(6, 5)), 0.0)
	assert_almost_eq(top.rise, 0.0, EPS)
	# Aimed back down the riser: rise -2, which does nothing.
	var down := lies.measure(_field(c), _centre(Vector2i(6, 5)), 180.0)
	assert_almost_eq(down.rise, -2.0, EPS)
	assert_eq(down.uphill_multiplier, 1.0)


func test_uphill_shortens_carry_by_k_per_step() -> void:
	var model := ShotModel.new()
	var c := _riser(5, 1)
	var club := model.clubs.club("7i")
	var shot := model.full(_field(c), club, 1.0, _centre(Vector2i(5, 5)), 0.0)
	assert_almost_eq(shot.target_carry, club.carry_yd * (1.0 - lies.uphill_k), EPS)
	var none := model.full(_field(c), club, 1.0, _centre(Vector2i(5, 5)), 0.0, 0.0, false)
	assert_almost_eq(none.target_carry, club.carry_yd, EPS, "the lie rule off")


func test_uphill_k_meets_the_hand_calculation() -> void:
	# docs/design.md step 6: 10 to 12 yd at rise 2 with a 146 yd 7-iron, 0.034 to 0.041.
	var carry := ShotModel.new().clubs.club("7i").carry_yd
	var lost := carry * 2.0 * lies.uphill_k
	assert_between(lost, 10.0, 12.0, "a 2-step uphill lie loses %.1f yd" % lost)


# --- tilt (sidehill) ---

## Flat at 0 up to tile row `edge`, then `steps` up on +y.
func _band(edge: int, steps: int) -> CourseData:
	var c := CourseData.create(30, 20, Surface.Type.FAIRWAY, 0)
	for y in range(edge + 1, 20):
		for x in 30:
			c.set_tile(x, y, steps, Surface.Type.FAIRWAY)
	return c


func test_tilt_reads_across_a_centred_window_and_names_the_higher_side() -> void:
	var c := _band(10, 1)
	var at := _centre(Vector2i(5, 10))
	# Aimed along +x the higher ground (+y) is on the player's right on screen: tilt -1.
	var along := lies.measure(_field(c), at, 0.0)
	assert_almost_eq(along.tilt, -1.0, EPS)
	# Aimed along -x it is on the left: tilt +1.
	var back := lies.measure(_field(c), at, 180.0)
	assert_almost_eq(back.tilt, 1.0, EPS)
	# Aimed straight up the band, no tilt.
	assert_almost_eq(lies.measure(_field(c), at, 90.0).tilt, 0.0, EPS)


func test_a_ball_on_flat_ground_beside_a_bank_reads_a_tilt() -> void:
	# D14: ground on both sides counts.
	var c := _band(10, 1)
	var lie := lies.measure(_field(c), _centre(Vector2i(5, 10)) - Vector2(0.0, 2.0), 0.0)
	assert_almost_eq(lie.tilt, -0.6, EPS, "3 yd of the 5 yd window reach the band")


func test_tilt_turns_the_heading_toward_the_lower_side() -> void:
	var model := ShotModel.new()
	var c := _band(10, 1)
	var at := _centre(Vector2i(5, 10))
	var shot := model.full(_field(c), model.clubs.club("7i"), 1.0, at, 0.0)
	assert_almost_eq(shot.heading_deg, -lies.sidehill_deg, EPS, "turned toward -y, the lower side")
	assert_lt(shot.velocity.y, 0.0, "it flies toward the low ground")
	var back := model.full(_field(c), model.clubs.club("7i"), 1.0, at, 180.0)
	assert_almost_eq(back.heading_deg, 180.0 + lies.sidehill_deg, EPS)
	assert_lt(back.velocity.y, 0.0, "the low ground is still -y")


func test_sidehill_deg_meets_the_hand_calculation() -> void:
	# docs/design.md step 6: 5 to 10 yd at 146 yd, 1.96 to 3.92 degrees per step.
	var carry := ShotModel.new().clubs.club("7i").carry_yd
	var curve := carry * sin(deg_to_rad(lies.sidehill_deg))
	assert_between(curve, 5.0, 10.0, "a 1-step sidehill lie curves %.1f yd" % curve)


func test_the_putter_ignores_rise_and_tilt() -> void:
	var model := ShotModel.new()
	var c := _band(10, 1)
	var shot := model.putt(_field(c), model.clubs.putter(), 4.0, _centre(Vector2i(5, 10)), 0.0)
	assert_almost_eq(shot.heading_deg, 0.0, EPS)
	assert_almost_eq(shot.lie.tilt, 0.0, EPS)
