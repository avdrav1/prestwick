extends GutTest
## E4-S1: data/economy.json holds the chosen economy (D56 build costs, D58 income and rating)
## and EconomyTuning reads it; data/land.json's price_scale moves land with it (D57). The
## readers only: E4-S2, S4, S5 and S6 charge, pay and rate.


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(EconomyTuning.PATH))


func test_the_shipped_file_reads_with_no_errors() -> void:
	var t := EconomyTuning.load_default()
	assert_eq(t.errors, [] as Array[String])


func test_the_tile_table_is_t4_times_the_money_scale_in_whole_dollars() -> void:
	var t := EconomyTuning.load_default()
	# T4 before scaling (D56): fairway 5, rough 2, green 25, tee 15, bunker 20, water 30,
	# trees 10, cart path 8, oob 2, $10 a step; times 0.61, rounded.
	var t4 := {Surface.Type.FAIRWAY: 5, Surface.Type.ROUGH: 2, Surface.Type.GREEN: 25,
			Surface.Type.TEE: 15, Surface.Type.BUNKER: 20, Surface.Type.WATER: 30,
			Surface.Type.TREES: 10, Surface.Type.CART_PATH: 8, Surface.Type.OOB: 2}
	for s: int in t4:
		assert_eq(t.price_of(s), roundi(t4[s] * 0.61), Surface.NAMES[s])
	assert_eq(t.height_step_price, roundi(10 * 0.61))
	assert_eq(t.price_of(Surface.Type.OOB), t.price_of(Surface.Type.ROUGH), "oob costs rough's price")
	assert_eq([t.tee_marker_price, t.cup_price], [0, 0], "tee markers and cups are free")


func test_land_moves_with_the_same_money_scale() -> void:
	var lp := LandPrices.load_default()
	assert_almost_eq(lp.price_scale, 0.61, 1e-9)
	# The discounts are what clearing costs before the scale: a tree to rough, a pond tile to
	# rough and one step up.
	assert_eq(lp.tree_tile_price, -2)
	assert_eq(lp.water_tile_price, -(2 + 10))
	assert_eq(lp.land_budget, 5000, "the one starting balance (D57)")


func test_arrivals_are_eight_plus_four_a_star_capped_at_24() -> void:
	var t := EconomyTuning.load_default()
	assert_eq(t.arrivals(1.0, 0.0), 12)
	assert_eq(t.arrivals(3.0, 0.0), 20)
	assert_eq(t.arrivals(4.0, 0.0), 24)
	assert_eq(t.arrivals(5.0, 0.0), 24, "28 capped")
	assert_eq(t.arrivals(5.0, 0.8), 24, "the cap holds whatever the fee: 28 x 0.89 = 25")


func test_the_fee_curve_is_flat_to_70_percent_then_falls_to_two_thirds() -> void:
	var t := EconomyTuning.load_default()
	assert_eq(t.fee_arrivals_share(0.0), 1.0)
	assert_eq(t.fee_arrivals_share(0.7), 1.0)
	assert_almost_eq(t.fee_arrivals_share(0.85), 0.8333, 0.001)
	assert_almost_eq(t.fee_arrivals_share(1.0), 2.0 / 3.0, 0.001)
	assert_eq(t.arrivals(3.0, 1.0), 13, "20 at the ceiling is cut by a third")
	assert_eq(t.arrivals(3.0, 0.8), 18)
	assert_eq(t.fee_ceiling(3.0), 75.0, "$25 a star a round")


func test_rating_points_are_5_3_1() -> void:
	var t := EconomyTuning.load_default()
	assert_eq(Array(t.rating_points), [5.0, 3.0, 1.0])
	assert_eq(GuestTuning.load_default().rating_window, 50, "over the last 50 reactions")


func test_a_bad_value_is_named() -> void:
	var cases: Array = [
		["height_step_price", -1],
		["arrivals_max", 0],
		["fee_full_arrivals_share", 1.0],
		["ceiling_arrivals_share", 1.5],
		["fee_ceiling_per_star", 2.5],
	]
	for c: Array in cases:
		var d := _shipped()
		d[c[0]] = c[1]
		var errors := EconomyTuning.from_dict(d).errors
		assert_eq(errors.size(), 1, "%s = %s: %s" % [c[0], c[1], errors])
		assert_string_contains(" ".join(errors), c[0])
	var d := _shipped()
	(d["tile_price"] as Dictionary).erase("green")
	assert_string_contains(" ".join(EconomyTuning.from_dict(d).errors), "green")
	d = _shipped()
	d["rating_points"]["neutral"] = 6
	assert_string_contains(" ".join(EconomyTuning.from_dict(d).errors), "rating_points")
