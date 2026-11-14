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
	# trees 10, cart path 8, oob 2, $10 a step; times the money scale 0.70 (D73; 0.78 at D67, 0.63 at
	# E4-S8), rounded.
	var t4 := {Surface.Type.FAIRWAY: 5, Surface.Type.ROUGH: 2, Surface.Type.GREEN: 25,
			Surface.Type.TEE: 15, Surface.Type.BUNKER: 20, Surface.Type.WATER: 30,
			Surface.Type.TREES: 10, Surface.Type.CART_PATH: 8, Surface.Type.OOB: 2}
	for s: int in t4:
		assert_eq(t.price_of(s), roundi(t4[s] * 0.70), Surface.NAMES[s])
	assert_eq(t.height_step_price, roundi(10 * 0.70))
	assert_eq(t.price_of(Surface.Type.OOB), t.price_of(Surface.Type.ROUGH), "oob costs rough's price")
	assert_eq([t.tee_marker_price, t.cup_price], [0, 0], "tee markers and cups are free")


func test_land_moves_with_the_same_money_scale() -> void:
	var lp := LandPrices.load_default()
	assert_almost_eq(lp.price_scale, 0.70, 1e-9, "D73 (0.78 at D67)")
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


# --- E18-S4 (D73): the back nine's pacing ---

func test_a_bridge_tile_is_t4s_40_times_the_money_scale() -> void:
	assert_eq(EconomyTuning.load_default().bridge_tile_price, roundi(40 * 0.70), "D69 at D73's scale")


func test_an_eighteen_still_pays_one_and_three_quarter_fees() -> void:
	var t := EconomyTuning.load_default()
	assert_almost_eq(t.eighteen_fee_multiple, 1.75, 1e-9, "D72, kept by D73")
	assert_eq(t.round_fee(t.start_fee, 18), 105)


func test_the_sims_eighteen_is_the_frugal_nine_twice() -> void:
	var plan := EconomySim.plan18()
	assert_eq(plan.size(), 18)
	assert_eq(plan.slice(0, 9), EconomySim.PLAN)
	assert_eq(plan.slice(9), EconomySim.PLAN, "holes 10 to 18 repeat the nine")


## A run of 18 free holes: one every 2 days, so the ninth opens on day 17 and the eighteenth on
## day 35; from the morning after, half the guests (rounded) play eighteen at 1.75 times the fee.
func test_the_sims_eighteen_hole_day_pays_nines_and_eighteens() -> void:
	var sim := EconomySim.new()
	var e := sim.chosen_income()
	var plan: Array[Dictionary] = []
	for i in 18:
		plan.append({"build": 0, "land": 0})
	var pts: Array = Array(sim.economy.rating_points)
	var start: Array = [3.0, sim.rating_window]
	var r35 := sim.run(e, plan, EconomySim.MID_MIX, pts, start, 35)
	var r36 := sim.run(e, plan, EconomySim.MID_MIX, pts, start, 36)
	assert_eq([r36.nine_day, r36.eighteen_day], [17, 35])
	# 3 stars, $60: 18 guests, 9 nines at $60 and 9 eighteens at $105, less 18 holes' upkeep.
	assert_eq(int(r36.money) - int(r35.money), 9 * 60 + 9 * 105 - 18 * 5)
	assert_string_contains(String(r36.log[35]), "(9 eighteens)")
	var nine := sim.run(e, plan.slice(0, 9), EconomySim.MID_MIX, pts, start)
	assert_eq([nine.nine_day, nine.eighteen_day], [17, -1], "a nine's run never opens an eighteen")


## The shipped economy against docs/design.md Balance targets, economy (`/balance economy`'s
## "chosen 18" rows): a 3-star course opens its nine in 25 to 35 days and all eighteen in 50
## to 70, on a New course's 192 x 192 land, never negative.
func test_the_shipped_economy_paces_the_nine_and_the_eighteen() -> void:
	var sim := EconomySim.new()
	var fx := sim.fixtures()
	var parcel := sim.median_parcel(10, sim.chosen_land, LandTuning.load_default())
	assert_eq(parcel, 700, "D73: the median parcel on 192 x 192, as on 128 x 128")
	var plan := sim.plan_costs(fx, sim.chosen_table(), parcel, 1.0, EconomySim.plan18())
	var pts: Array = Array(sim.economy.rating_points)
	var start: Array = [float(sim.economy.rating_points[1]), sim.rating_window]
	var r := sim.run(sim.chosen_income(), plan, EconomySim.MID_MIX, pts, start, EconomySim.RUN18_DAYS)
	assert_between(int(r.nine_day), 25, 35, "the nine")
	assert_between(int(r.eighteen_day), 50, 70, "all eighteen")
	assert_gte(int(r.min_money), 0, "never negative")
