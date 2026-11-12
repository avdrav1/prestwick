extends GutTest
## E2-S5: the /balance simulator's measuring functions (scripts/balance_sim.gd), called
## without the command line. Each table's rows hit their docs/design.md targets with the
## values in golf/clubs.tres, golf/lies.tres and course/surfaces.tres.

const RUNS: int = 3
const SEED: int = 1

var sim: BalanceSim


func before_each() -> void:
	sim = BalanceSim.new()


func _named(rows: Array[Dictionary], prefix: String) -> Dictionary:
	for r in rows:
		if String(r.name).begins_with(prefix):
			return r
	return {}


func _assert_all_hit(rows: Array[Dictionary], table: String) -> void:
	assert_gt(rows.size(), 0, "%s has rows" % table)
	for r in rows:
		assert_true(r.ok, "%s: %s measured %.3f, target %s" % [table, r.name, r.measured, r.target])


func test_clubs_rows_hit_their_targets() -> void:
	var rows := sim.measure_clubs(RUNS, SEED)
	_assert_all_hit(rows, "clubs")
	var driver := _named(rows, "driver carry")
	assert_between(float(driver.measured), 230.0, 260.0)
	assert_eq(driver.target, BalanceSim.DRIVER_CARRY, "printed next to its target")
	for i in BalanceSim.IRONS.size() - 1:
		var step := _named(rows, "%s to %s step" % [BalanceSim.IRONS[i], BalanceSim.IRONS[i + 1]])
		assert_false(step.is_empty(), "a row per iron step")
	assert_false(_named(rows, "putter legal on green only").is_empty())
	assert_false(_named(rows, "full putt on flat green").is_empty())


func test_a_perfect_drive_stops_short_of_the_shortest_par4_green() -> void:
	# E6-S19, D33: on flat fairway the driver's total stops short of a 30 yd green round a cup
	# at rule 4's shortest par 4.
	var rows := sim.measure_clubs(RUNS, SEED)
	var short := _named(rows, "driver: perfect drive short of the shortest par 4's green")
	assert_false(short.is_empty(), "a row for the drive against the shortest par 4")
	assert_true(short.ok, "measured %.1f yd short" % float(short.measured))
	assert_gt(float(short.measured), 0.0, "stops before the green's front")
	assert_false(_named(rows, "driver: perfect drives on generated land onto that green").is_empty(),
			"and the generated-land share is printed")


func test_drives_on_land_sample_every_lane_off_the_block() -> void:
	var land := sim.drives_on_land(SEED, 1)
	var totals: Array[float] = land.totals
	assert_eq(totals.size(), BalanceSim.LANE_SIDES.size() * BalanceSim.LANE_OFFSETS.size(), "one drive a lane")
	assert_lt(totals[totals.size() / 2], BalanceSim.par4_green_front_yd(), "the median perfect drive on seed 1 stops short of the green")
	assert_gt(totals[0], 200.0, "every drive gets away")


func test_lies_rows_hit_their_targets() -> void:
	var rows := sim.measure_lies(RUNS, SEED)
	_assert_all_hit(rows, "lies")
	assert_eq(rows.size(), 2, "uphill and sidehill")


func test_surfaces_rows_hit_their_targets() -> void:
	var rows := sim.measure_surfaces(RUNS, SEED)
	_assert_all_hit(rows, "surfaces")
	assert_false(_named(rows, "rough distance cost").is_empty())
	assert_false(_named(rows, "bunker sw at 50%").is_empty())
	assert_eq(rows.filter(func(r: Dictionary) -> bool: return String(r.name).begins_with("green:")).size(), 5,
			"the five green targets on GridHeightEvidence")


func test_the_lie_spots_read_what_d18_names() -> void:
	var at := (Vector2(4, BalanceSim.STRIP_H / 2) + Vector2(0.5, 0.5)) * 5.0
	var up := sim.model.lies.measure(HeightField.new(sim.uphill_course(), sim.model.params), at, 0.0)
	assert_almost_eq(up.rise, 2.0, 0.001, "a 2-step uphill lie")
	var side := sim.model.lies.measure(HeightField.new(sim.sidehill_course(), sim.model.params), at, 0.0)
	assert_almost_eq(absf(side.tilt), 1.0, 0.001, "a 1-step sidehill lie")


func test_same_seed_same_numbers() -> void:
	var a := sim.measure_clubs(RUNS, SEED)
	var b := BalanceSim.new().measure_clubs(RUNS, SEED)
	for i in a.size():
		assert_eq(a[i].measured, b[i].measured, a[i].name)


func test_a_missed_target_is_reported() -> void:
	var lies: LieTable = LieTable.load_default().duplicate()
	lies.uphill_k = 0.0
	var off := BalanceSim.new(ShotModel.new(null, lies))
	var missed := BalanceSim.misses(off.measure_lies(RUNS, SEED))
	assert_eq(missed.size(), 1, "with k at 0 the uphill target misses")
	var lines := BalanceSim.format(off.measure_lies(RUNS, SEED))
	assert_string_contains(lines[0], "MISS")


# --- land (E6-S8) ---

func test_land_rows_hit_their_targets() -> void:
	var rows := sim.measure_land(RUNS, SEED)
	_assert_all_hit(rows, "land")
	var both := _named(rows, "land: seeds with room for a par 3 and a par 4")
	assert_false(both.is_empty(), "a row for the par 3 and par 4")
	assert_eq(float(both.measured), 1.0, "on every seed")
	var nine := _named(rows, "land: seeds with room for nine holes")
	assert_false(nine.is_empty(), "a row for nine holes")
	assert_eq(float(nine.measured), 0.0, "on no seed")
	assert_false(_named(rows, "land: parcels at the price clamp").is_empty())
	# D67: the 4 x 4 block alone holds the par 3 and the par 4, and no par 5.
	assert_eq(float(_named(rows, "land: starting block alone, seeds with room for a par 3 and a par 4").measured),
			1.0, "with no purchase")
	assert_eq(float(_named(rows, "land: starting block alone, seeds with room for a par 5").measured),
			0.0, "a par 5 is the first purchase's reason")


func test_land_budget_buys_land_cheapest_first() -> void:
	var c := CourseBuilder.new_course(SEED)
	var budget: int = c.land_budget
	var buy := BalanceSim.spend_budget(CourseBuilder.new(c))
	assert_gt(buy.bought.size(), 0, "the budget buys at least one parcel")
	var spent := 0
	for price: int in buy.prices:
		spent += price
	assert_eq(spent + int(buy.left), budget, "the budget is spent on parcels only")
	assert_lt(int(buy.left), int(buy.cheapest_left), "stops when the cheapest buyable parcel costs more than is left")


func test_land_hole_room_reads_the_design_footprint() -> void:
	# docs/design.md Land, hand calculation: a (L + 60) x 60 sq yd capsule per hole.
	assert_almost_eq(BalanceSim.footprint_parcels(160.0), 2.06, 0.01, "a 160 yd par 3")
	assert_almost_eq(BalanceSim.footprint_parcels(380.0), 4.13, 0.01, "a 380 yd par 4")
	var nine := 0.0
	for yd: float in BalanceSim.NINE_HOLES_YD:
		nine += BalanceSim.footprint_parcels(yd)
	assert_almost_eq(nine, 33.56, 0.01, "nine holes need about 34 parcels")


func test_land_span_of_the_starting_block_is_445_yd() -> void:
	var c := CourseBuilder.new_course(SEED)
	assert_almost_eq(BalanceSim.owned_span_yd(c), 445.5, 0.1, "corner to corner of the 4 x 4 block (D67)")
	assert_eq(BalanceSim.owned_parcels(c), 16)


func test_a_missed_land_target_is_reported() -> void:
	# D67: the block holds the par 4 whatever the budget, so the miss to read is nine holes: a
	# budget that buys the map leaves room for them.
	sim.land.land_budget = 1000000
	var missed := BalanceSim.misses(sim.measure_land(RUNS, SEED))
	assert_eq(missed.size(), 1, "a budget that buys the map fits nine holes")
	assert_string_contains(String(missed[0].name), "nine holes")
