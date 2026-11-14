extends GutTest
## E2-S2: the hole rules of docs/design.md (Hole validation rules, D11), the one validator
## the game and /course-file share. Every failing rule names a tile and a reason. Rule 6 and
## rule 3's unowned land are E6-S4's (D30).

const EXAMPLE_PATH := "res://courses/example_par3.json"
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")

var _v: CourseValidator


func before_each() -> void:
	_v = CourseValidator.new()


## A flat rough course with a one-tile green under each hole's cup.
func _course(w: int, h: int, holes: Array) -> CourseData:
	var c := CourseData.create(w, h, Surface.Type.ROUGH, 0)
	for hole: HoleData in holes:
		if c.in_bounds(hole.cup.x, hole.cup.y):
			c.set_tile(hole.cup.x, hole.cup.y, 0, Surface.Type.GREEN)
	c.set_holes(holes)
	return c


func _rules(issues: Array[CourseValidator.Issue]) -> Array[int]:
	var out: Array[int] = []
	for i: CourseValidator.Issue in issues:
		out.append(i.rule)
	return out


func _issue(issues: Array[CourseValidator.Issue], rule: int) -> CourseValidator.Issue:
	for i: CourseValidator.Issue in issues:
		if i.rule == rule:
			return i
	return null


func _assert_one_line(issue: CourseValidator.Issue) -> void:
	assert_false(issue.reason.is_empty(), "rule %d has a reason" % issue.rule)
	assert_false(issue.reason.contains("\n"), "rule %d reason is one line" % issue.rule)


func test_the_shipped_tuning_keeps_every_par_4_inside_the_zone_threshold() -> void:
	var t := ValidatorTuning.load_default()
	assert_eq(t.order_issue(), "", "course/validator_tuning.tres: %s" % t.order_issue())
	assert_lte(t.zone_from_yd, t.par4_min_yd)


func test_a_zone_threshold_above_the_shortest_par_4_is_caught() -> void:
	var t := ValidatorTuning.load_default().duplicate() as ValidatorTuning
	t.zone_from_yd = t.par4_min_yd
	assert_eq(t.order_issue(), "", "equal is allowed")
	t.zone_from_yd = t.par4_min_yd + 1
	var issue := t.order_issue()
	assert_string_contains(issue, "zone_from_yd")
	assert_string_contains(issue, "par4_min_yd")


func test_tuning_holds_the_d11_numbers() -> void:
	var t := ValidatorTuning.load_default()
	assert_not_null(t)
	assert_eq(t.landing_distance_yd, 240.0)
	assert_eq(t.cup_clearance_yd, 60.0)
	assert_eq(t.zone_radius_yd, 30.0)
	assert_eq(t.zone_from_yd, 300, "a zone on every hole of 300 yd or more, whatever its par (D35, E6-S37)")
	assert_eq(t.footprint_half_width_yd, 30.0)
	assert_eq(t.par4_min_yd, 320, "past a perfect drive's 297 yd on flat fairway (D33, E6-S19)")
	assert_eq(t.par5_min_yd, 471)


func test_yards_per_tile_matches_the_ball() -> void:
	assert_eq(CourseValidator.YARDS_PER_TILE, BallParams.load_default().yards_per_tile)


# --- rule 1: exactly one tee and one cup ---

func test_rule1_passes_one_hole_with_a_tee_and_a_cup() -> void:
	var c := _course(40, 10, [HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))])
	assert_eq(_v.check_hole(c, c.holes[0]), [] as Array[CourseValidator.Issue])


func test_rule1_fails_when_tee_and_cup_share_a_tile() -> void:
	var c := _course(10, 10, [HoleData.new(1, 3, Vector2i(4, 4), Vector2i(4, 4))])
	var issue := _issue(_v.check_hole(c, c.holes[0]), 1)
	assert_not_null(issue)
	assert_eq(issue.tile, Vector2i(4, 4))
	_assert_one_line(issue)


func test_rule1_fails_when_the_cup_is_not_placed() -> void:
	var c := _course(10, 10, [HoleData.new(1, 3, Vector2i(4, 4), HoleData.UNPLACED)])
	var issues := _v.check_hole(c, c.holes[0])
	assert_eq(_rules(issues), [1] as Array[int], "only rule 1: the rest cannot be measured")
	assert_eq(issues[0].tile, Vector2i(4, 4), "points at the tee that is there")
	_assert_one_line(issues[0])


func test_rule1_fails_when_the_tee_is_not_placed() -> void:
	var c := _course(10, 10, [HoleData.new(1, 3, HoleData.UNPLACED, Vector2i(6, 6))])
	var issues := _v.check_hole(c, c.holes[0])
	assert_eq(_rules(issues), [1] as Array[int])
	assert_eq(issues[0].tile, Vector2i(6, 6), "points at the cup that is there")


func test_rule1_fails_both_holes_sharing_a_number() -> void:
	# Two holes numbered 1 are one hole with two tees and two cups.
	var a := HoleData.new(1, 3, Vector2i(2, 2), Vector2i(30, 2))
	var b := HoleData.new(1, 3, Vector2i(2, 8), Vector2i(30, 8))
	var c := _course(40, 12, [a, b])
	var ia := _issue(_v.check_hole(c, c.holes[0]), 1)
	var ib := _issue(_v.check_hole(c, c.holes[1]), 1)
	assert_not_null(ia)
	assert_not_null(ib)
	# E3-S41: each stands on its own tee and names the other as the map labels it.
	assert_eq(ia.tile, Vector2i(2, 2), "hole A's issue is on its own tee")
	assert_eq(ib.tile, Vector2i(2, 8), "hole B's on its own")
	assert_eq(ia.reason, "shares number 1 with hole 1b")
	assert_eq(ib.reason, "shares number 1 with hole 1a")
	_assert_one_line(ia)


func test_check_slots_keeps_each_duplicates_own_issues() -> void:
	# E3-S11: one array per entry of course.holes, so the hole list can show each duplicate's.
	var a := HoleData.new(1, 3, Vector2i(2, 2), Vector2i(30, 2))
	var b := HoleData.new(1, 3, Vector2i(2, 8), Vector2i(30, 8))
	var other := HoleData.new(2, 3, Vector2i(2, 11), Vector2i(20, 11))
	var c := _course(40, 12, [a, b, other])
	var slots: Array = _v.check_slots(c)
	assert_eq(slots.size(), 3)
	assert_eq((_issue(slots[0], 1) as CourseValidator.Issue).tile, Vector2i(2, 2), "slot 0 on its own tee")
	assert_eq((_issue(slots[1], 1) as CourseValidator.Issue).tile, Vector2i(2, 8), "slot 1 on its own tee")
	assert_eq((_issue(slots[0], 1) as CourseValidator.Issue).reason, "shares number 1 with hole 1b")
	assert_eq(slots[2], [] as Array[CourseValidator.Issue], "hole 2 passes")
	var by_number: Dictionary = _v.check_course(c)
	assert_eq(_rules(by_number[1]), [1, 1] as Array[int], "check_course still merges a shared number")
	assert_eq(by_number[2], [] as Array[CourseValidator.Issue])


func test_rule1_passes_a_hole_that_is_not_the_courses_own_copy() -> void:
	# set_holes stores copies; a caller may validate the HoleData it still holds.
	var h := HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))
	var c := _course(40, 10, [h])
	assert_false(is_same(h, c.holes[0]), "the course holds a copy")
	assert_eq(_v.check_hole(c, h), [] as Array[CourseValidator.Issue], "not its own second tee")


func test_rule1_held_copy_still_sees_a_real_duplicate_number() -> void:
	var a := HoleData.new(1, 3, Vector2i(2, 2), Vector2i(30, 2))
	var b := HoleData.new(1, 3, Vector2i(2, 8), Vector2i(30, 8))
	var c := _course(40, 12, [a, b])
	var ia := _issue(_v.check_hole(c, a), 1)
	assert_not_null(ia)
	assert_eq(ia.tile, Vector2i(2, 2), "on its own tee (E3-S41)")
	assert_eq(ia.reason, "shares number 1 with hole 1b")

# --- rule 2: cup on a green ---

func test_rule2_passes_cup_on_green() -> void:
	var c := _course(40, 10, [HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))])
	assert_null(_issue(_v.check_hole(c, c.holes[0]), 2))


func test_rule2_fails_cup_on_fairway() -> void:
	var c := _course(40, 10, [HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))])
	c.set_tile(32, 5, 0, Surface.Type.FAIRWAY)
	var issue := _issue(_v.check_hole(c, c.holes[0]), 2)
	assert_not_null(issue)
	assert_eq(issue.tile, Vector2i(32, 5))
	assert_string_contains(issue.reason, "fairway")
	_assert_one_line(issue)


# --- rule 3: a path of non-water, non-OB tiles ---

func test_rule3_passes_round_the_end_of_a_lake() -> void:
	var c := _course(40, 12, [HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))])
	for y: int in range(0, 11):  # row 11 stays dry
		for x: int in range(15, 18):
			c.set_tile(x, y, 0, Surface.Type.WATER)
	assert_null(_issue(_v.check_hole(c, c.holes[0]), 3))


func test_rule3_crosses_trees_and_ignores_heights() -> void:
	var c := _course(40, 10, [HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))])
	for y: int in c.height:
		c.set_tile(10, y, 0, Surface.Type.TREES)
		c.set_tile(20, y, 7, Surface.Type.ROUGH)
		c.set_tile(21, y, 0, Surface.Type.CART_PATH)
		c.set_tile(22, y, 0, Surface.Type.BUNKER)
	assert_null(_issue(_v.check_hole(c, c.holes[0]), 3))


func test_rule3_fails_a_water_wall_and_names_a_blocking_tile() -> void:
	var c := _course(40, 10, [HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))])
	for y: int in c.height:
		c.set_tile(16, y, 0, Surface.Type.WATER)
	var issue := _issue(_v.check_hole(c, c.holes[0]), 3)
	assert_not_null(issue)
	assert_eq(issue.tile, Vector2i(16, 5), "the water on the tee-to-cup line")
	assert_string_contains(issue.reason, "water")
	_assert_one_line(issue)


func test_rule3_fails_an_oob_wall() -> void:
	var c := _course(40, 10, [HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))])
	for y: int in c.height:
		c.set_tile(25, y, 0, Surface.Type.OOB)
	var issue := _issue(_v.check_hole(c, c.holes[0]), 3)
	assert_not_null(issue)
	assert_eq(issue.tile, Vector2i(25, 5))
	assert_string_contains(issue.reason, "oob")


func test_rule3_uses_four_neighbours_not_diagonals() -> void:
	# Water along x + y == 9: the dry tiles either side touch only at corners.
	var c := _course(10, 10, [HoleData.new(1, 3, Vector2i(0, 0), Vector2i(9, 9))])
	for x: int in 10:
		c.set_tile(x, 9 - x, 0, Surface.Type.WATER)
	var issue := _issue(_v.check_hole(c, c.holes[0]), 3)
	assert_not_null(issue, "a diagonal gap is no path")
	assert_eq(c.get_surface(issue.tile.x, issue.tile.y), Surface.Type.WATER)



func test_rule3_shared_reach_matches_a_fresh_one() -> void:
	# check_course shares one Reach; a second hole in a walled-off pocket still fails.
	var a := HoleData.new(1, 3, Vector2i(2, 2), Vector2i(30, 2))
	var b := HoleData.new(2, 3, Vector2i(2, 8), Vector2i(30, 8))
	var c := _course(40, 12, [a, b])
	for x: int in c.width:
		c.set_tile(x, 5, 0, Surface.Type.WATER)
	for y: int in range(6, 12):
		c.set_tile(20, y, 0, Surface.Type.WATER)
	var all := _v.check_course(c)
	assert_null(_issue(all[1], 3), "hole 1 is open across the top")
	assert_not_null(_issue(all[2], 3), "hole 2's cup is behind the wall")
	assert_not_null(_issue(_v.check_hole(c, c.holes[1]), 3), "same answer alone")

func test_rule3_fails_a_tee_on_water() -> void:
	var c := _course(40, 10, [HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))])
	c.set_tile(2, 5, 0, Surface.Type.WATER)
	var issue := _issue(_v.check_hole(c, c.holes[0]), 3)
	assert_not_null(issue)
	assert_eq(issue.tile, Vector2i(2, 5), "the tee tile is part of the path")


# --- rule 4: yardage matches par ---

func _par_check(d: Vector2i, par: int) -> CourseValidator.Issue:
	var tee := Vector2i(2, 2)
	var c := _course(100, 50, [HoleData.new(1, par, tee, tee + d)])
	return _issue(_v.check_hole(c, c.holes[0]), 4)


func test_rule4_yardage_is_rounded_straight_line() -> void:
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(64, 0)), 320)
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(58, 27)), 320, "319.88 rounds up")
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(61, 19)), 319, "319.45 rounds down")
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(30, 40)), 250)
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(94, 0)), 470)
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(94, 4)), 470, "470.43")
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(94, 5)), 471, "470.66")


func test_rule4_par_for_yardage_at_the_boundaries() -> void:
	assert_eq(_v.par_for_yardage(319), 3)
	assert_eq(_v.par_for_yardage(320), 4)
	assert_eq(_v.par_for_yardage(470), 4)
	assert_eq(_v.par_for_yardage(471), 5)


func test_rule4_at_exactly_320_yd() -> void:
	# D33 (E6-S19): the shortest par 4 is 320 yd, so a perfect drive (297 yd on flat fairway)
	# stops short of a 30 yd green round its cup.
	for d: Vector2i in [Vector2i(64, 0), Vector2i(58, 27)]:
		assert_null(_par_check(d, 4), "%s is a par 4" % d)
		var issue := _par_check(d, 3)
		assert_not_null(issue, "%s is not a par 3" % d)
		if issue:
			assert_eq(issue.tile, Vector2i(2, 2) + d, "points at the cup")
			assert_string_contains(issue.reason, "320")
			_assert_one_line(issue)
	assert_null(_par_check(Vector2i(61, 19), 3), "319 yd is a par 3")
	assert_not_null(_par_check(Vector2i(61, 19), 4), "319 yd is not a par 4")
	assert_null(_par_check(Vector2i(30, 40), 3), "250 yd, a par 4 before D33, is a par 3")
	assert_not_null(_par_check(Vector2i(30, 40), 4), "and no longer a par 4")


func test_rule4_at_exactly_470_yd() -> void:
	for d: Vector2i in [Vector2i(94, 0), Vector2i(94, 4)]:
		assert_null(_par_check(d, 4), "%s is a par 4" % d)
		assert_not_null(_par_check(d, 5), "%s is not a par 5" % d)
	assert_null(_par_check(Vector2i(94, 5), 5), "471 yd is a par 5")
	var issue := _par_check(Vector2i(94, 5), 4)
	assert_not_null(issue, "471 yd is not a par 4")
	if issue:
		assert_string_contains(issue.reason, "471")


func test_rule4_fails_a_par_outside_3_to_5() -> void:
	assert_not_null(_par_check(Vector2i(30, 0), 2))
	assert_not_null(_par_check(Vector2i(94, 5), 6))


# --- rule 5: no tee inside another hole's landing zone ---

## Hole 1, a 400 yd par 4 from (5, 20) to (85, 20): its zone centre is 240 yd (48 tiles)
## out, at (53, 20), radius 30 yd (6 tiles). Hole 2 is a par 3 teeing off at `tee2`.
func _two_holes(tee2: Vector2i) -> CourseData:
	var a := HoleData.new(1, 4, Vector2i(5, 20), Vector2i(85, 20))
	var b := HoleData.new(2, 3, tee2, tee2 + Vector2i(0, 30))
	return _course(100, 60, [a, b])


func test_landing_zone_centre_and_radius() -> void:
	var c := _two_holes(Vector2i(53, 24))
	var zone: Variant = _v.landing_zone(c.holes[0])
	assert_not_null(zone)
	assert_almost_eq((zone as Vector2).x, 53.0, 0.001)
	assert_almost_eq((zone as Vector2).y, 20.0, 0.001)
	assert_null(_v.landing_zone(c.holes[1]), "a 150 yd par 3 has no zone (under zone_from_yd)")


func test_rule5_fails_both_holes_for_a_tee_in_the_zone() -> void:
	var c := _two_holes(Vector2i(53, 24))  # 20 yd from the centre
	var all := _v.check_course(c)
	var ia := _issue(all[1], 5)
	var ib := _issue(all[2], 5)
	assert_not_null(ia, "the hole whose zone holds the tee fails")
	assert_not_null(ib, "the hole whose tee is in the zone fails")
	assert_eq(ia.tile, Vector2i(53, 24), "A reports B's tee")
	assert_eq(ib.tile, Vector2i(53, 24), "B reports its own tee")
	_assert_one_line(ia)
	_assert_one_line(ib)
	assert_eq(_rules(all[1]), [5] as Array[int], "nothing else wrong with A")
	assert_eq(_rules(all[2]), [5] as Array[int], "nothing else wrong with B")


func test_rule5_zone_edge_is_inside() -> void:
	var c := _two_holes(Vector2i(53, 26))  # exactly 30 yd
	assert_not_null(_issue(_v.check_course(c)[2], 5))


func test_rule5_passes_a_tee_outside_the_zone() -> void:
	var c := _two_holes(Vector2i(53, 27))  # 35 yd
	var all := _v.check_course(c)
	assert_eq(all[1], [] as Array[CourseValidator.Issue])
	assert_eq(all[2], [] as Array[CourseValidator.Issue])


func test_rule5_par3_next_tee_beside_the_green_passes() -> void:
	# docs/design.md: a 150 yd par 3 from (10, 10) to (40, 10), next tee at (44, 13).
	var a := HoleData.new(1, 3, Vector2i(10, 10), Vector2i(40, 10))
	var b := HoleData.new(2, 3, Vector2i(44, 13), Vector2i(44, 43))
	var c := _course(60, 50, [a, b])
	var all := _v.check_course(c)
	assert_eq(all[1], [] as Array[CourseValidator.Issue])
	assert_eq(all[2], [] as Array[CourseValidator.Issue])


func test_rule5_short_par4_next_tee_beside_the_green_passes() -> void:
	# The shortest par 4 (320 yd since D33) with another tee 25 yd beside its cup: the zone
	# centre is 240 yd out, since 320 - 60 is past the landing distance.
	var a := HoleData.new(1, 4, Vector2i(10, 10), Vector2i(74, 10))
	var b := HoleData.new(2, 3, Vector2i(74, 15), Vector2i(74, 45))
	var c := _course(90, 50, [a, b])
	assert_eq(CourseValidator.yardage(a.tee, a.cup), 320)
	var zone: Vector2 = _v.landing_zone(c.holes[0])
	assert_almost_eq(zone.x, 58.0, 0.001, "240 yd out")
	var all := _v.check_course(c)
	assert_eq(all[1], [] as Array[CourseValidator.Issue])
	assert_eq(all[2], [] as Array[CourseValidator.Issue])


func test_rule5_cup_clearance_moves_the_zone_on_a_short_par4() -> void:
	# With a shortest par 4 under landing distance + clearance (250 yd, before D33), the zone
	# sits 60 yd short of the cup: a 260 yd par 4's centre is 200 yd out, and a tee 25 yd
	# beside its cup passes. zone_from_yd comes down with it, or a 260 yd hole has no zone.
	var t: ValidatorTuning = ValidatorTuning.load_default().duplicate()
	t.par4_min_yd = 250
	t.zone_from_yd = 250
	var v := CourseValidator.new(t)
	var a := HoleData.new(1, 4, Vector2i(10, 10), Vector2i(62, 10))
	var b := HoleData.new(2, 3, Vector2i(62, 15), Vector2i(62, 45))
	var c := _course(80, 50, [a, b])
	assert_eq(CourseValidator.yardage(a.tee, a.cup), 260)
	var zone: Vector2 = v.landing_zone(c.holes[0])
	assert_almost_eq(zone.x, 50.0, 0.001, "200 yd out")
	var all := v.check_course(c)
	assert_eq(all[1], [] as Array[CourseValidator.Issue])
	assert_eq(all[2], [] as Array[CourseValidator.Issue])


func test_rule5_fails_for_a_placed_tee_whose_cup_is_not_placed() -> void:
	# E2-S3 places a tee before its cup: the tee alone already sits in hole 1's zone.
	var a := HoleData.new(1, 4, Vector2i(5, 20), Vector2i(85, 20))
	var b := HoleData.new(2, 3, Vector2i(53, 24), HoleData.UNPLACED)
	var c := _course(100, 60, [a, b])
	var ia := _issue(_v.check_hole(c, c.holes[0]), 5)
	assert_not_null(ia, "hole 1 fails as soon as the tee is down")
	assert_eq(ia.tile, Vector2i(53, 24))
	_assert_one_line(ia)
	assert_eq(_rules(_v.check_hole(c, c.holes[1])), [1] as Array[int], "hole 2 only lacks its cup")


func test_rule5_a_cupless_hole_has_no_zone_to_stand_in() -> void:
	# Hole 2 has a cup but no tee: it has no zone, and its cup is not a tee.
	var a := HoleData.new(1, 4, Vector2i(5, 20), Vector2i(85, 20))
	var b := HoleData.new(2, 4, HoleData.UNPLACED, Vector2i(53, 24))
	var c := _course(100, 60, [a, b])
	assert_eq(_v.check_hole(c, c.holes[0]), [] as Array[CourseValidator.Issue])

# --- rule 6: tee and cup on owned land (D30) ---

## A 64 x 32 course of 4 x 2 parcels owning only parcels (1, 0) and (2, 0), tiles 16 to 47 of
## the top row, with hole 1 a 100 yd par 3 from `tee` to `cup`.
func _owned_strip(tee: Vector2i, cup: Vector2i) -> CourseData:
	var c := _course(64, 32, [HoleData.new(1, 3, tee, cup)])
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), q == 0 and (p == 1 or p == 2))
	c.set_land_budget(5000)
	return c


func test_rule_count_is_seven() -> void:
	assert_eq(CourseValidator.RULE_COUNT, 7, "E14-S3: rule 7, on foot")


func test_rule6_passes_tee_and_cup_on_owned_land() -> void:
	var c := _owned_strip(Vector2i(20, 8), Vector2i(40, 8))
	assert_eq(_v.check_hole(c, c.holes[0]), [] as Array[CourseValidator.Issue])


func test_rule6_passes_in_a_sandbox() -> void:
	var c := _course(64, 32, [HoleData.new(1, 3, Vector2i(2, 20), Vector2i(22, 20))])
	assert_null(_issue(_v.check_hole(c, c.holes[0]), 6), "every parcel owned")


func test_rule6_passes_when_only_the_footprint_is_unowned() -> void:
	# Tee and cup one tile inside the owned strip: the footprint runs 30 yd past both ends and
	# 30 yd south of the line onto unowned land (D30 allows it).
	var c := _owned_strip(Vector2i(16, 14), Vector2i(36, 14))
	assert_eq(_v.check_hole(c, c.holes[0]), [] as Array[CourseValidator.Issue])


func test_rule6_fails_a_tee_on_unowned_land() -> void:
	var c := _owned_strip(Vector2i(10, 8), Vector2i(30, 8))
	var issue := _issue(_v.check_hole(c, c.holes[0]), 6)
	assert_not_null(issue)
	assert_eq(issue.tile, Vector2i(10, 8), "the tee is highlighted")
	assert_string_contains(issue.reason, "tee")
	_assert_one_line(issue)


func test_rule6_fails_a_cup_on_unowned_land() -> void:
	var c := _owned_strip(Vector2i(30, 8), Vector2i(50, 8))
	var issues := _v.check_hole(c, c.holes[0])
	var issue := _issue(issues, 6)
	assert_not_null(issue)
	assert_eq(issue.tile, Vector2i(50, 8), "the cup is highlighted")
	assert_string_contains(issue.reason, "cup")
	_assert_one_line(issue)


func test_rule6_reports_both_tee_and_cup_when_both_are_unowned() -> void:
	var c := _owned_strip(Vector2i(4, 20), Vector2i(24, 20))
	var tiles: Array[Vector2i] = []
	for i: CourseValidator.Issue in _v.check_hole(c, c.holes[0]):
		if i.rule == 6:
			tiles.append(i.tile)
	assert_eq(tiles, [Vector2i(4, 20), Vector2i(24, 20)] as Array[Vector2i])


func test_rule6_is_not_measured_for_an_unplaced_hole() -> void:
	var c := _owned_strip(Vector2i(4, 20), HoleData.UNPLACED)
	assert_eq(_rules(_v.check_hole(c, c.holes[0])), [1] as Array[int])


# --- rule 3 counts unowned land as OB (D30) ---

func test_rule3_fails_a_path_cut_by_unowned_land() -> void:
	# Tee on parcel (1, 0), cup on parcel (3, 0); parcel (2, 0) between them is not owned, nor
	# is the row below, so no owned path joins them.
	var c := _course(64, 32, [HoleData.new(1, 3, Vector2i(20, 8), Vector2i(52, 8))])
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), q == 0 and (p == 1 or p == 3))
	var issue := _issue(_v.check_hole(c, c.holes[0]), 3)
	assert_not_null(issue)
	assert_eq(issue.tile, Vector2i(32, 8), "the first unowned tile on the line")
	assert_string_contains(issue.reason, "unowned")
	_assert_one_line(issue)
	assert_null(_issue(_v.check_hole(c, c.holes[0]), 6), "tee and cup are owned")


func test_rule3_goes_round_unowned_land_through_owned_land() -> void:
	# The same, but the row below is owned all along: the path detours through it.
	var c := _course(64, 32, [HoleData.new(1, 3, Vector2i(20, 8), Vector2i(52, 8))])
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), q == 1 or p == 1 or p == 3)
	assert_null(_issue(_v.check_hole(c, c.holes[0]), 3))


# --- the course as a whole, and the example ---

func test_check_course_keys_every_hole_by_number() -> void:
	var c := _two_holes(Vector2i(53, 27))
	var all := _v.check_course(c)
	assert_eq(all.keys(), [1, 2])


func test_generated_par3_passes_every_rule() -> void:
	var c := CourseGenerator.generate(3, false, false)
	assert_not_null(c)
	assert_eq(c.holes.size(), 1)
	assert_eq(c.holes[0].par, 3)
	assert_eq(_v.check_hole(c, c.holes[0]), [] as Array[CourseValidator.Issue])


func test_example_par3_file_is_the_generated_par3() -> void:
	var errors: Array[String] = []
	var loaded := CourseSave.load_file(EXAMPLE_PATH, errors)
	assert_not_null(loaded, "loads: %s" % [errors])
	if loaded == null:
		return
	assert_eq(loaded.content_hash(), CourseGenerator.generate(3, false, false).content_hash(),
			"regenerate with: godot --headless --path . -s res://course/course_file.gd -- generate 3 flat dry --out=courses/example_par3.json")
	assert_eq(_v.check_course(loaded), {1: [] as Array[CourseValidator.Issue]})


func test_generated_par4_and_par5_with_water_pass() -> void:
	for par: int in [4, 5]:
		for water: bool in [false, true]:
			var c := CourseGenerator.generate(par, false, water)
			assert_eq(_v.check_course(c), {1: [] as Array[CourseValidator.Issue]}, "par %d water %s" % [par, water])
			var waters: int = 0
			for y: int in c.height:
				for x: int in c.width:
					if c.get_surface(x, y) == Surface.Type.WATER:
						waters += 1
			assert_eq(waters > 0, water, "par %d water %s" % [par, water])


# --- the headless entry point /course-file uses ---

func test_cli_validate_example_passes() -> void:
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["validate", EXAMPLE_PATH]), out), 0, "\n".join(out))
	assert_eq(out.filter(func(l: String) -> bool: return l.contains("rule")).size(), CourseValidator.RULE_COUNT,
			"one line per rule")
	assert_false("\n".join(out).contains("FAIL"))


func test_cli_validate_reports_a_failing_rule_with_its_tile() -> void:
	var c := _course(40, 10, [HoleData.new(1, 4, Vector2i(2, 5), Vector2i(32, 5))])
	var path := "user://test_validator_fail.json"
	assert_eq(CourseSave.save_file(c, path), OK)
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["validate", path]), out), 1)
	var text := "\n".join(out)
	assert_string_contains(text, "rule 4 FAIL at (32, 5)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_cli_generate_writes_a_passing_file() -> void:
	var path := "user://test_validator_gen.json"
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["generate", "3", "flat", "dry", "--out=" + path]), out), 0,
			"\n".join(out))
	var loaded := CourseSave.load_file(path)
	assert_not_null(loaded)
	if loaded:
		assert_eq(loaded.content_hash(), CourseGenerator.generate(3, false, false).content_hash())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_cli_rejects_bad_arguments() -> void:
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["generate", "6"]), out), 2)
	assert_eq(CourseFileTool.run(PackedStringArray(["validate", "res://courses/nope.json"]), out), 2)
	assert_eq(CourseFileTool.run(PackedStringArray([]), out), 2)


# --- speed: E2-S3 reruns the validator after every build edit ---

## Nine holes on a new D10 sandbox (128x128 rough, height 2), each cup ringed by water so
## no hole connects: the worst case for rule 3's flood.
func _walled_sandbox() -> CourseData:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	var holes: Array = []
	for n: int in 9:
		var y: int = 6 + n * 13
		var tee := Vector2i(4, y)
		var cup := Vector2i(4 + 30, y)
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				c.set_tile(cup.x + dx, cup.y + dy, 2, Surface.Type.WATER)
		c.set_tile(cup.x, cup.y, 2, Surface.Type.GREEN)
		holes.append(HoleData.new(n + 1, 3, tee, cup))
	c.set_holes(holes)
	return c


func test_check_course_on_a_walled_128_plot_is_fast() -> void:
	if BestTime.later(self):
		return
	var c := _walled_sandbox()
	var all := _v.check_course(c)
	var ms: float = BestTime.ms(func() -> void: _v.check_course(c))
	for n: int in range(1, 10):
		assert_not_null(_issue(all[n], 3), "hole %d is walled off" % n)
	gut.p("check_course, 9 walled holes on 128x128: %.1f ms (fastest of %d)" % [ms, BestTime.RUNS])
	assert_lt(ms, 100.0, "one edit's rerun of nine holes stays under 100 ms (debug build)" + BestTime.load_note())


func test_check_hole_on_a_128_plot_is_fast() -> void:
	if BestTime.later(self):
		return
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	c.set_tile(100, 64, 2, Surface.Type.GREEN)
	c.set_holes([HoleData.new(1, 5, Vector2i(4, 64), Vector2i(100, 64))])
	var issues := _v.check_hole(c, c.holes[0])
	var ms: float = BestTime.ms(func() -> void: _v.check_hole(c, c.holes[0]))
	assert_eq(issues, [] as Array[CourseValidator.Issue])
	gut.p("check_hole, one par 5 on 128x128: %.1f ms (fastest of %d)" % [ms, BestTime.RUNS])
	assert_lt(ms, 30.0, "one hole's check stays under 30 ms (debug build)" + BestTime.load_note())


# --- rule 3's graph kept between edits (E3-S12) ---

## Every slot's issues as strings, for comparing two checks.
func _strings(slots: Array) -> Array:
	var out: Array = []
	for issues: Array in slots:
		out.append(issues.map(func(i: CourseValidator.Issue) -> String: return str(i)))
	return out


## The builder's cached check matches a fresh validator on the same course.
func _assert_matches_fresh(b: CourseBuilder, what: String) -> void:
	var fresh: Array = CourseValidator.new().check_slots(b.course)
	var cached: Array = []
	for slot: int in b.course.holes.size():
		cached.append(b.issues_at(slot))
	assert_eq(_strings(cached), _strings(fresh), what)


func test_reach_update_relabels_only_when_a_crossing_changes() -> void:
	var c := CourseData.create(20, 10, Surface.Type.ROUGH, 0)
	var r := CourseValidator.Reach.new(c)
	assert_true(r.connected(Vector2i(0, 5), Vector2i(19, 5)))
	c.set_tile(10, 5, 0, Surface.Type.FAIRWAY)
	assert_false(r.update(c, [Vector2i(10, 5)] as Array[Vector2i]), "rough to fairway changes no crossing")
	for y: int in 10:
		c.set_tile(10, y, 0, Surface.Type.WATER)
	var wall: Array[Vector2i] = []
	for y: int in 10:
		wall.append(Vector2i(10, y))
	assert_true(r.update(c, wall), "a water wall changes crossings")
	assert_false(r.connected(Vector2i(0, 5), Vector2i(19, 5)), "the wall cuts the path")
	c.set_tile(10, 3, 0, Surface.Type.BUNKER)
	assert_true(r.update(c, [Vector2i(10, 3)] as Array[Vector2i]))
	assert_true(r.connected(Vector2i(0, 5), Vector2i(19, 5)), "a gap in the wall joins them again")


func test_a_cached_check_gives_the_same_issues_as_a_fresh_one_after_edits() -> void:
	var c := LandGenerator.generate(7)
	var b := CourseBuilder.new(c)
	b.level_water = false  # D66: water as a plain paint here, not a flood
	var NineHoles: GDScript = load("res://tests/fixtures/nine_holes.gd")
	NineHoles.build(b)
	_assert_matches_fresh(b, "nine holes built")
	var h1: HoleData = b.hole(1)
	var mid := Vector2i(60, h1.tee.y)
	# A click edit that changes no crossing: the graph is kept.
	b.paint(Vector2i(64, 100), Surface.Type.FAIRWAY, 1)
	_assert_matches_fresh(b, "after a fairway click")
	# A water wall the height of the map across hole 1's line, as one stroke: rule 3 fails.
	b.begin_stroke()
	for y: int in c.height:
		b.paint(Vector2i(mid.x, y), Surface.Type.WATER, 1)
	b.end_stroke()
	assert_not_null(_issue(b.issues_for(1), 3), "the wall cuts hole 1")
	_assert_matches_fresh(b, "after a water wall")
	# A gap of rough: rule 3 passes again.
	b.paint(Vector2i(mid.x, 100), Surface.Type.ROUGH, 1)
	assert_null(_issue(b.issues_for(1), 3), "the gap joins hole 1 again")
	_assert_matches_fresh(b, "after a gap in the wall")
	b.paint(Vector2i(mid.x, 100), Surface.Type.OOB, 1)
	_assert_matches_fresh(b, "after OB closing the gap")
	# Undo opens the gap, then takes the wall away.
	b.undo()
	_assert_matches_fresh(b, "after undoing the OB")
	b.undo()
	b.undo()
	assert_null(_issue(b.issues_for(1), 3), "the wall is undone")
	_assert_matches_fresh(b, "after undoing the wall")
	# The breaking drag: rough through every cup in one stroke, then its undo.
	b.begin_stroke()
	for spec: Array in NineHoles.HOLES:
		b.paint(spec[3], Surface.Type.ROUGH, 1)
	b.end_stroke()
	_assert_matches_fresh(b, "after rough on every cup")
	b.undo()
	_assert_matches_fresh(b, "after undoing it")
	# Raising and lowering ground changes no crossing.
	b.raise(mid, 3)
	b.lower(mid + Vector2i(0, 2), 5)
	_assert_matches_fresh(b, "after raise and lower")
	# A write the builder did not make (a test fixture's set_tile) is caught too.
	for y: int in c.height:
		c.set_tile(h1.cup.x - 3, y, c.get_height(h1.cup.x - 3, y), Surface.Type.WATER)
	b.paint(Vector2i(64, 100), Surface.Type.ROUGH, 1)
	assert_not_null(_issue(b.issues_for(1), 3), "the outside wall cuts hole 1")
	_assert_matches_fresh(b, "after an outside write")


func test_a_cached_check_follows_land_bought_and_undone() -> void:
	var c := CourseBuilder.new_course(7)
	var b := CourseBuilder.new(c)
	# A hole in the starting block (tiles 48 to 79), tee and cup owned.
	b.paint(Vector2i(50, 60), Surface.Type.TEE, 1)
	b.paint(Vector2i(75, 60), Surface.Type.GREEN, 1)
	b.place_tee(1, Vector2i(50, 60), 3)
	b.place_cup(1, Vector2i(75, 60))
	_assert_matches_fresh(b, "a hole on a New course")
	var bought: bool = b.buy_parcel(Vector2i(5, 3))
	_assert_matches_fresh(b, "after buying a parcel (%s)" % bought)
	b.undo()
	_assert_matches_fresh(b, "after undoing the purchase")


func test_reach_finds_a_long_way_round_past_its_search_budget() -> void:
	# A water wall at x = 15 with one gap at the far edge: the way round is about 140 tiles for
	# a 10-tile distance, past the search's budget, so the flood answers.
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 0)
	for y: int in 127:
		c.set_tile(15, y, 0, Surface.Type.WATER)
	var r := CourseValidator.Reach.new(c)
	assert_true(r.connected(Vector2i(10, 64), Vector2i(20, 64)), "round by the gap at y 127")
	assert_true(r.connected(Vector2i(20, 64), Vector2i(10, 64)), "and back, from the labels")
	c.set_tile(15, 127, 0, Surface.Type.OOB)
	assert_true(r.update(c, [Vector2i(15, 127)] as Array[Vector2i]))
	assert_false(r.connected(Vector2i(10, 64), Vector2i(20, 64)), "the gap closed")
	assert_true(r.connected(Vector2i(10, 64), Vector2i(10, 0)), "same side")
	assert_false(r.connected(Vector2i(10, 64), Vector2i(15, 64)), "onto the water")
	assert_true(r.connected(Vector2i(3, 3), Vector2i(3, 3)), "a tile reaches itself")


# --- E18-S5: the frame budget at eighteen holes (D71) ---

## The kept graph answers as a fresh one on every pair of `pairs`.
func _assert_reach_as_fresh(r: CourseValidator.Reach, c: CourseData, pairs: Array, why: String) -> void:
	var fresh := CourseValidator.Reach.new(c)
	for pair: Array in pairs:
		assert_eq(r.connected(pair[0], pair[1]), fresh.connected(pair[0], pair[1]),
				"%s: %s to %s" % [why, pair[0], pair[1]])


func test_surface_indices_finds_every_tile_of_a_surface_in_order() -> void:
	var c := LandGenerator.generate(7)
	var tiles: PackedByteArray = c.packed_tiles()
	for s: int in [Surface.Type.WATER, Surface.Type.OOB, Surface.Type.TREES, Surface.Type.ROUGH]:
		var want := PackedInt32Array()
		for i: int in tiles.size():
			if (tiles[i] & 0x0F) == s:
				want.append(i)
		assert_eq(CourseValidator.surface_indices(tiles, s), want, Surface.name_of(s))


func test_walkable_tiles_and_the_reach_read_the_map_as_tile_by_tile() -> void:
	var c := LandGenerator.generate(7)
	c.set_tile(3, 4, 0, Surface.Type.OOB)
	var water := CourseValidator.surface_indices(c.packed_tiles(), Surface.Type.WATER)
	var wet := Vector2i(water[0] % c.width, water[0] / c.width)
	c.set_bridge(wet, true)
	var ok := CourseValidator.Walk.walkable_tiles(c)
	var r := CourseValidator.Reach.new(c)
	var bad_walk: int = 0
	var bad_reach: int = 0
	for y: int in c.height:
		for x: int in c.width:
			var s: Surface.Type = c.get_surface(x, y)
			var walk: int = 1 if s != Surface.Type.WATER or c.is_bridge(x, y) else 0
			if ok[y * c.width + x] != walk:
				bad_walk += 1
			if r._passable[y * c.width + x] != (1 if CourseValidator._crossable(c, Vector2i(x, y)) else 0):
				bad_reach += 1
	assert_eq(bad_walk, 0, "every tile walkable as rule 7 reads it")
	assert_eq(bad_reach, 0, "every tile crossable as rule 3 reads it")


## E18-S5: an update that only opens crossings keeps the pairs joined; one that closes any drops
## them; an update back to crossings seen before takes up what was found on them. Every answer
## is a fresh graph's.
func test_reach_keeps_what_it_found_for_crossings_it_has_seen() -> void:
	var c := CourseData.create(40, 20, Surface.Type.ROUGH, 0)
	for y: int in 20:
		c.set_tile(20, y, 0, Surface.Type.WATER)
	var pairs: Array = [[Vector2i(2, 2), Vector2i(10, 15)], [Vector2i(2, 2), Vector2i(30, 5)],
			[Vector2i(30, 5), Vector2i(38, 18)], [Vector2i(5, 10), Vector2i(35, 10)]]
	var r := CourseValidator.Reach.new(c)
	_assert_reach_as_fresh(r, c, pairs, "the wall")
	assert_true(r._joined.size() > 0, "same-side pairs joined by a search")
	var joined: int = r._joined.size()
	# A gap: crossings only open, so the joined pairs stand.
	c.set_tile(20, 10, 0, Surface.Type.ROUGH)
	assert_true(r.update(c, [Vector2i(20, 10)] as Array[Vector2i]))
	assert_eq(r._joined.size(), joined, "opening a crossing keeps the joined pairs")
	_assert_reach_as_fresh(r, c, pairs, "the gap")
	var after_gap: Dictionary = r._joined.duplicate()
	# Closed again (the undo): the wall's own labels and pairs come back.
	c.set_tile(20, 10, 0, Surface.Type.WATER)
	assert_true(r.update(c, [Vector2i(20, 10)] as Array[Vector2i]))
	assert_eq(r._joined.size(), joined, "the wall's pairs, as they were")
	_assert_reach_as_fresh(r, c, pairs, "the wall again")
	# And open once more (a redo): the gap's.
	c.set_tile(20, 10, 0, Surface.Type.ROUGH)
	assert_true(r.update(c, [Vector2i(20, 10)] as Array[Vector2i]))
	assert_eq(r._joined, after_gap, "the gap's pairs, as they were")
	_assert_reach_as_fresh(r, c, pairs, "the gap again")
	# A new closing (OB on the gap): nothing kept fits, so everything goes.
	c.set_tile(20, 10, 0, Surface.Type.OOB)
	c.set_tile(5, 5, 0, Surface.Type.OOB)
	assert_true(r.update(c, [Vector2i(20, 10), Vector2i(5, 5)] as Array[Vector2i]))
	assert_eq(r._joined.size(), 0, "a closed crossing drops the pairs")
	_assert_reach_as_fresh(r, c, pairs, "OB")


## E18-S5 (D71): on 192 x 192 with eighteen holes, the drag that breaks every hole and its undo
## give the issues a fresh validator gives, and the rerun costs a few ms, not the 4 to 5 ms that
## put the release and undo frames past 16.7 ms.
func test_eighteen_holes_breaking_drag_and_undo_check_as_fresh() -> void:
	var land := LandTuning.load_d26()
	land.map_size = Vector2i(192, 192)
	var bt := BuilderTuning.load_default().duplicate() as BuilderTuning
	bt.plot_size = Vector2i(192, 192)
	bt.max_holes = 18
	var c := LandGenerator.generate(7, land)
	var b := CourseBuilder.new(c, bt)
	var NineHoles: GDScript = load("res://tests/fixtures/nine_holes.gd")
	NineHoles.build(b)
	for spec: Array in NineHoles.HOLES:
		var n: int = spec[0] + 9
		var tee: Vector2i = spec[2] + Vector2i(64, 100)
		var cup: Vector2i = spec[3] + Vector2i(64, 100)
		b.begin_stroke()
		for cell: Vector2i in BuildTool.grid_line(tee, cup):
			b.paint(cell, Surface.Type.FAIRWAY, 3)
		b.end_stroke()
		b.paint(tee, Surface.Type.TEE, 3)
		b.paint(cup, Surface.Type.GREEN, 5)
		b.place_tee(n, tee, spec[1])
		b.place_cup(n, cup)
		b.set_par(n, spec[1])
	assert_eq(c.holes.size(), 18)
	_assert_matches_fresh(b, "eighteen built")
	var cups: Array[Vector2i] = []
	for h: HoleData in c.holes:
		cups.append(h.cup)
	cups.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return x.y < y.y or (x.y == y.y and x.x < y.x))
	var spent: Array[float] = []
	for k: int in 3:
		b.begin_stroke()
		for i: int in range(1, cups.size()):
			for cell: Vector2i in BuildTool.grid_line(cups[i - 1], cups[i]):
				b.paint(cell, Surface.Type.ROUGH, 1)
		var t0 := Time.get_ticks_usec()
		b.end_stroke()
		spent.append((Time.get_ticks_usec() - t0) / 1000.0)
		_assert_matches_fresh(b, "the breaking drag %d" % k)
		t0 = Time.get_ticks_usec()
		b.undo()
		spent.append((Time.get_ticks_usec() - t0) / 1000.0)
		_assert_matches_fresh(b, "its undo %d" % k)
	gut.p("E18-S5: eighteen holes, breaking drag's check and undo (ms): %s" % [spent])


# --- rule 4 on doglegs: the line of play (D47, E3-S25) ---

## A rough 100 x 70 course: a 5-wide fairway from `tee` to `corner` and from `corner` to `cup`,
## a 5 x 5 green round the cup, hole 1 at `par`. Painted through the builder, as Build does.
func _dogleg(tee: Vector2i, corner: Vector2i, cup: Vector2i, par: int) -> CourseData:
	var c := CourseData.create(100, 70, Surface.Type.ROUGH, 1)
	var b := CourseBuilder.new(c)
	for leg: Array in [[tee, corner], [corner, cup]]:
		b.begin_stroke()
		for cell: Vector2i in BuildTool.grid_line(leg[0], leg[1]):
			b.paint(cell, Surface.Type.FAIRWAY, 5)
		b.end_stroke()
	b.paint(cup, Surface.Type.GREEN, 5)
	b.place_tee(1, tee, par)
	b.place_cup(1, cup)
	b.set_par(1, par)
	return c


func test_a_straight_hole_with_fairway_in_its_zone_keeps_its_straight_yardage() -> void:
	var c := ReactionHoles.fair_par4()
	var h: HoleData = c.holes[0]
	assert_null(_v.turn_point(c, h), "the fairway runs through the landing zone")
	assert_eq(_v.hole_yardage(c, h), CourseValidator.yardage(h.tee, h.cup))
	assert_eq(_v.hole_yardage(c, h), 380)


func test_a_hole_with_no_fairway_keeps_its_straight_yardage() -> void:
	var c := _course(100, 50, [HoleData.new(1, 4, Vector2i(2, 2), Vector2i(96, 2))])
	assert_null(_v.turn_point(c, c.holes[0]), "nothing to bend toward")
	assert_eq(_v.hole_yardage(c, c.holes[0]), 470)
	assert_null(_issue(_v.check_hole(c, c.holes[0]), 4), "every rule-4 boundary case keeps its yardage")


func test_a_bunker_on_the_zone_centre_keeps_a_straight_hole_straight() -> void:
	var c := ReactionHoles.fair_par4()
	var h: HoleData = c.holes[0]
	var z: Vector2 = _v.landing_zone(h)
	var at := Vector2i(roundi(z.x), roundi(z.y))
	for y: int in range(at.y - 2, at.y + 3):
		for x: int in range(at.x - 1, at.x + 2):
			c.set_tile(x, y, c.get_height(x, y), Surface.Type.BUNKER)
	assert_null(_v.turn_point(c, h), "fairway round the bunker is still inside the 30 yd disc")
	assert_eq(_v.hole_yardage(c, h), 380)


func test_the_reaction_dogleg_is_measured_round_its_corner() -> void:
	# ReactionHoles.dogleg_par4: tee (6, 6), fairway east to (56, 6), then south to the cup
	# (56, 50), round a pond. 333 yd straight; the straight zone centre (240 yd out) is in the
	# pond, 60 yd or more from any fairway. The fairway tiles 240 yd (48 tiles) from the tee,
	# to half a tile, are (54, 4) to (54, 12): the end of the east leg and the inside edge of
	# the south leg. Their centre (54, 8) is the turn: 5 x sqrt(48² + 2²) = 240.21 yd out,
	# then 5 x sqrt(2² + 42²) = 210.24 yd to the cup, 450.45 in all.
	var c := ReactionHoles.dogleg_par4()
	var h: HoleData = c.holes[0]
	assert_eq(CourseValidator.yardage(h.tee, h.cup), 333, "the straight line")
	var turn: Variant = _v.turn_point(c, h)
	assert_not_null(turn, "the zone holds no fairway: a dogleg")
	if turn != null:
		assert_almost_eq((turn as Vector2).x, 54.0, 0.001)
		assert_almost_eq((turn as Vector2).y, 8.0, 0.001)
	assert_eq(_v.hole_yardage(c, h), 450, "round the corner")
	assert_null(_issue(_v.check_hole(c, h), 4), "450 yd is still a par 4")
	assert_true(h.open, "the reaction field's dogleg still opens")
	var five := HoleData.new(1, 5, h.tee, h.cup)
	var issue := _issue(_v.check_hole(c, five), 4)
	assert_not_null(issue, "and not a par 5")
	if issue:
		assert_string_contains(issue.reason, "450 yd round the dogleg is a par 4, not par 5")
		_assert_one_line(issue)


func test_a_long_dogleg_is_a_par_5_though_its_straight_line_is_a_par_4() -> void:
	# East 270 yd to (60, 6), south 270 yd to (60, 60): 381.8 yd straight, a par 4. The
	# fairway 48 tiles out is (54, 4) to (54, 8), the east leg only (the south leg is 52 tiles
	# or more away); its centre (54, 6) is 240 yd out, and 5 x sqrt(6² + 54²) = 271.66 yd from
	# the cup: 511.66, rounded 512, a par 5.
	var c := _dogleg(Vector2i(6, 6), Vector2i(60, 6), Vector2i(60, 60), 5)
	var h: HoleData = c.holes[0]
	assert_eq(CourseValidator.yardage(h.tee, h.cup), 382)
	assert_eq(_v.turn_point(c, h), Vector2(54, 6))
	assert_eq(_v.hole_yardage(c, h), 512)
	assert_null(_issue(_v.check_hole(c, h), 4), "a par 5 round its corner")
	var four := HoleData.new(1, 4, h.tee, h.cup)
	var issue := _issue(_v.check_hole(c, four), 4)
	assert_not_null(issue, "not the par 4 its straight line gives")
	if issue:
		assert_eq(issue.tile, h.cup, "the cup is at fault, as before")
		assert_string_contains(issue.reason, "512 yd round the dogleg is a par 5, not par 4")


func test_painting_the_corner_rough_straightens_the_line_again() -> void:
	# D11's cost of a line of play: the yardage follows the fairway. With the east leg's end
	# painted over, no fairway is 240 yd out and the hole is measured straight.
	var c := _dogleg(Vector2i(6, 6), Vector2i(60, 6), Vector2i(60, 60), 5)
	for y: int in range(0, 15):
		for x: int in range(50, 58):
			if c.get_surface(x, y) == Surface.Type.FAIRWAY:
				c.set_tile(x, y, c.get_height(x, y), Surface.Type.ROUGH)
	assert_null(_v.turn_point(c, c.holes[0]))
	assert_eq(_v.hole_yardage(c, c.holes[0]), 382)


func test_a_hole_shorter_than_a_tee_shot_has_no_turn() -> void:
	# Under landing_distance_yd (240) on the straight line the cup is in reach of a tee shot:
	# no disc, no turn, whatever the fairway does.
	var c := _dogleg(Vector2i(6, 6), Vector2i(30, 6), Vector2i(30, 30), 3)
	var h: HoleData = c.holes[0]
	assert_lt(CourseValidator.yardage(h.tee, h.cup), 240)
	assert_null(_v.turn_point(c, h))
	assert_eq(_v.hole_yardage(c, h), CourseValidator.yardage(h.tee, h.cup))


func test_a_sharp_dogleg_under_300_yd_straight_is_measured_round_its_corner() -> void:
	# E3-S25 review: east 210 yd to (48, 6), south 210 yd to the cup (48, 48). 297 yd straight
	# (no rule 5 zone), 420 along the fairway. Rule 4's disc is min(240, 297 - 60) = 237 yd out,
	# on the diagonal, 40 yd or more from either leg: a dogleg. The fairway 47.4 tiles out,
	# ahead of the tee, is the south leg near (48, 28): about 237 + 100 = 337 yd, a par 4.
	var c := _dogleg(Vector2i(6, 6), Vector2i(48, 6), Vector2i(48, 48), 4)
	var h: HoleData = c.holes[0]
	assert_eq(CourseValidator.yardage(h.tee, h.cup), 297)
	assert_null(_v.landing_zone(h), "under zone_from_yd on the straight line")
	var turn: Variant = _v.turn_point(c, h)
	assert_not_null(turn, "but rule 4 still finds its corner")
	if turn != null:
		assert_almost_eq((turn as Vector2).x, 48.0, 0.25)
		assert_almost_eq((turn as Vector2).y, 28.0, 0.5)
	var yards: int = _v.hole_yardage(c, h)
	assert_between(yards, 330, 345)
	assert_null(_issue(_v.check_hole(c, h), 4), "%d yd round the corner is a par 4" % yards)
	var three := HoleData.new(1, 3, h.tee, h.cup)
	assert_not_null(_issue(_v.check_hole(c, three), 4), "and not the par 3 its straight line gives")


## A rough 150 x 100 course with a 5-wide fairway strip from `a` to `b` (another hole's) and
## hole 1 from `tee` to `cup` at `par`, with a green round its cup and no fairway of its own.
func _beside(a: Vector2i, b: Vector2i, tee: Vector2i, cup: Vector2i, par: int) -> CourseData:
	var c := CourseData.create(150, 100, Surface.Type.ROUGH, 1)
	var bld := CourseBuilder.new(c)
	bld.begin_stroke()
	for cell: Vector2i in BuildTool.grid_line(a, b):
		bld.paint(cell, Surface.Type.FAIRWAY, 5)
	bld.end_stroke()
	bld.paint(cup, Surface.Type.GREEN, 5)
	bld.place_tee(1, tee, par)
	bld.place_cup(1, cup)
	bld.set_par(1, par)
	return c


func test_another_holes_fairway_beside_the_tee_never_turns_a_hole() -> void:
	# E3-S25 review: hole 1 has no fairway; a fairway runs east 200 yd to its north, crossing
	# the 240 yd ring at about (31, 10). It leads to someone else's green, not to this cup.
	var c := _beside(Vector2i(5, 10), Vector2i(95, 10), Vector2i(5, 50), Vector2i(85, 50), 4)
	var h: HoleData = c.holes[0]
	assert_null(_v.turn_point(c, h), "the neighbour's fairway is not this hole's line")
	assert_eq(_v.hole_yardage(c, h), 400)
	assert_null(_issue(_v.check_hole(c, h), 4))


func test_another_holes_fairway_ahead_and_to_the_side_never_turns_a_hole() -> void:
	# A strip 48 tiles east of the tee, north of it: ahead of the tee but not this hole's.
	var c := _beside(Vector2i(108, 5), Vector2i(108, 14), Vector2i(60, 10), Vector2i(60, 90), 4)
	assert_null(_v.turn_point(c, c.holes[0]))
	assert_eq(_v.hole_yardage(c, c.holes[0]), 400)


func test_fairway_behind_the_tee_never_turns_a_hole() -> void:
	# A strip north-south 48 tiles behind the tee: even if it ran to this cup's side, it lies
	# behind the tee. Here it is someone else's, and behind.
	var c := _beside(Vector2i(12, 5), Vector2i(12, 95), Vector2i(60, 30), Vector2i(136, 30), 4)
	assert_null(_v.turn_point(c, c.holes[0]))
	assert_eq(_v.hole_yardage(c, c.holes[0]), 380)


func test_a_forced_carry_beside_a_parallel_hole_keeps_its_straight_yardage() -> void:
	# A straight 460 yd par 4: fairway to 150 yd, water across its zone, fairway again to the
	# cup. A parallel hole's fairway 100 yd to the side crosses the 240 yd ring; it does not run
	# to this cup, so the hole stays straight.
	var c := CourseData.create(150, 100, Surface.Type.ROUGH, 1)
	var bld := CourseBuilder.new(c)
	var tee := Vector2i(6, 30)
	var cup := Vector2i(98, 30)
	for leg: Array in [[tee, Vector2i(36, 30)], [Vector2i(66, 30), cup], [Vector2i(6, 50), Vector2i(98, 50)]]:
		bld.begin_stroke()
		for cell: Vector2i in BuildTool.grid_line(leg[0], leg[1]):
			bld.paint(cell, Surface.Type.FAIRWAY, 5)
		bld.end_stroke()
	for y: int in range(20, 41):
		for x: int in range(38, 64):
			c.set_tile(x, y, 1, Surface.Type.WATER)
	bld.paint(cup, Surface.Type.GREEN, 5)
	bld.place_tee(1, tee, 4)
	bld.place_cup(1, cup)
	assert_null(_v.turn_point(c, c.holes[0]), "the parallel fairway is not this hole's")
	assert_eq(_v.hole_yardage(c, c.holes[0]), 460)


func test_painting_a_neighbours_fairway_does_not_close_an_open_hole() -> void:
	# The rerun after every edit: hole 1 (no fairway of its own) stays open while a second
	# hole's fairway is painted across its 240 yd ring.
	var c := _beside(Vector2i(5, 10), Vector2i(6, 10), Vector2i(5, 50), Vector2i(85, 50), 4)
	var bld := CourseBuilder.new(c)
	assert_true(bld.hole(1).open)
	bld.begin_stroke()
	for cell: Vector2i in BuildTool.grid_line(Vector2i(5, 10), Vector2i(95, 10)):
		bld.paint(cell, Surface.Type.FAIRWAY, 5)
	bld.end_stroke()
	assert_true(bld.hole(1).open, "hole 1 still open")
	assert_eq(bld.yardage_at(0), 400, "and still 400 yd on its card")


func test_the_nine_hole_fixture_and_generated_holes_stay_straight() -> void:
	var nine: CourseData = NineHoles.land()
	var opened: Array[int] = NineHoles.build(CourseBuilder.new(nine))
	assert_eq(opened, [1, 2, 3, 4, 5, 6, 7, 8, 9] as Array[int], "all nine still open")
	for h: HoleData in nine.holes:
		assert_null(_v.turn_point(nine, h), "nine_holes hole %d is straight" % h.number)
	for par: int in [3, 4, 5]:
		for water: bool in [false, true]:
			var c := CourseGenerator.generate(par, false, water)
			assert_null(_v.turn_point(c, c.holes[0]), "generated par %d water %s is straight" % [par, water])


# --- rule 5 and the footprint on a dogleg's line of play (D51, E3-S45) ---

func test_a_tee_at_a_doglegs_turn_fails_rule_5() -> void:
	# The 512 yd par 5 dogleg: its turn (54, 6) is 240 yd out on the east leg, where its tee
	# shots come down; the straight line's 240 yd point is (39.9, 39.9), 35 tiles away.
	var c := _dogleg(Vector2i(6, 6), Vector2i(60, 6), Vector2i(60, 60), 5)
	var one: HoleData = c.holes[0]
	assert_eq(_v.play_zone(c, one), Vector2(54, 6), "the zone sits on the turn")
	assert_ne(_v.play_zone(c, one), _v.landing_zone(one), "not on the straight line")
	var two := HoleData.new(2, 3, Vector2i(54, 8), Vector2i(80, 8))
	c.set_tile(80, 8, 1, Surface.Type.GREEN)
	c.set_holes([one, two])
	var issue := _issue(_v.check_hole(c, c.holes[0]), 5)
	assert_not_null(issue, "hole 2's tee at the turn fails hole 1's rule 5")
	if issue:
		assert_eq(issue.tile, Vector2i(54, 8))
		assert_string_contains(issue.reason, "hole 2's tee is in this hole's landing zone, 10 yd from its centre")
	var back := _issue(_v.check_hole(c, c.holes[1]), 5)
	assert_not_null(back, "and hole 2's own check names it, both ways")
	if back:
		assert_string_contains(back.reason, "tee is in hole 1's landing zone")
	var slots: Array = _v.check_slots(c)
	assert_eq(_rules(slots[0]).count(5), 1, "check_slots agrees")
	assert_eq(_rules(slots[1]).count(5), 1)


func test_a_tee_on_a_doglegs_straight_line_is_clear_of_its_zone() -> void:
	# The straight line's zone centre, where D11 put it, is no longer a landing zone.
	var c := _dogleg(Vector2i(6, 6), Vector2i(60, 6), Vector2i(60, 60), 5)
	var one: HoleData = c.holes[0]
	var two := HoleData.new(2, 3, Vector2i(40, 40), Vector2i(40, 66))
	c.set_tile(40, 66, 1, Surface.Type.GREEN)
	c.set_holes([one, two])
	assert_null(_issue(_v.check_hole(c, c.holes[0]), 5), "nobody lands on the straight line")


func test_a_sharp_dogleg_under_300_yd_straight_has_a_zone_on_its_turn() -> void:
	# 297 yd straight, about 337 round: rule 5's threshold reads the line of play, so this
	# par 4 has a zone like every par 4, on its turn.
	var c := _dogleg(Vector2i(6, 6), Vector2i(48, 6), Vector2i(48, 48), 4)
	var h: HoleData = c.holes[0]
	assert_null(_v.landing_zone(h), "under zone_from_yd on the straight line")
	assert_eq(_v.play_zone(c, h), _v.turn_point(c, h), "but over it round the corner")


func test_a_straight_holes_zone_and_footprint_are_unchanged() -> void:
	var c := ReactionHoles.fair_par4()
	var h: HoleData = c.holes[0]
	assert_eq(_v.play_zone(c, h), _v.landing_zone(h), "zone on the straight line")
	assert_eq(_v.line_of_play(c, h), PackedVector2Array([Vector2(h.tee), Vector2(h.cup)]))
	var capsule: Array[Vector2i] = []
	for y: int in c.height:
		for x: int in c.width:
			var p := Vector2(x, y)
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, Vector2(h.tee), Vector2(h.cup))
			if p.distance_to(q) * CourseValidator.YARDS_PER_TILE <= 30.0:
				capsule.append(Vector2i(x, y))
	assert_eq(_v.footprint(c, h), capsule, "the D11 capsule round the straight segment")


func test_a_doglegs_footprint_follows_tee_to_turn_to_cup() -> void:
	var c := _dogleg(Vector2i(6, 6), Vector2i(60, 6), Vector2i(60, 60), 5)
	var h: HoleData = c.holes[0]
	assert_eq(_v.line_of_play(c, h), PackedVector2Array([Vector2(6, 6), Vector2(54, 6), Vector2(60, 60)]))
	assert_true(_v.in_footprint(c, h, Vector2i(56, 12)), "on the second leg, 31 tiles off the straight line")
	assert_true(_v.in_footprint(c, h, Vector2i(30, 6)), "on the first leg")
	assert_false(_v.in_footprint(c, h, Vector2i(33, 33)), "on the straight line, 27 tiles from either leg")
	var tiles: Array[Vector2i] = _v.footprint(c, h)
	assert_true(tiles.has(Vector2i(56, 12)) and tiles.has(Vector2i(60, 66)), "footprint holds the leg and past the cup")
	assert_false(tiles.has(Vector2i(33, 33)))
	for t: Vector2i in tiles:
		if not _v.in_footprint(c, h, t):
			assert_true(false, "footprint tile %s outside in_footprint" % t)
			break


func test_an_edit_at_a_doglegs_corner_closes_it() -> void:
	# A bunker on the inside of the corner: outside the straight capsule (31 tiles off the
	# diagonal), on the second leg. The hole still passes; the footprint closes it while the
	# edit lasts, and it opens itself again when the edit ends (E8-S1, D64).
	var c := _dogleg(Vector2i(6, 6), Vector2i(60, 6), Vector2i(60, 60), 5)
	var b := CourseBuilder.new(c)
	assert_true(b.hole(1).open, "the dogleg opens itself")
	b.begin_stroke()
	b.paint(Vector2i(58, 14), Surface.Type.BUNKER, 1)
	assert_false(b.hole(1).open, "an edit at the corner closes it")
	b.end_stroke()
	assert_true(b.issues_for(1).is_empty(), "though it still passes")
	assert_true(b.hole(1).open, "so it opens again as the edit ends")
	b.begin_stroke()
	b.paint(Vector2i(33, 33), Surface.Type.BUNKER, 1)
	assert_true(b.hole(1).open, "an edit on the straight line, off the line of play, leaves it open")
	b.end_stroke()


# --- the approach hint (E3-S39): never a rule ---

func test_a_tee_in_another_holes_approach_gets_a_hint_that_never_closes_it() -> void:
	# nine_holes: hole 2's tee (92, 8) is 50 yd past hole 1's cup (82, 8); hole 3's tee
	# (120, 19) is 56 yd from hole 2's cup (122, 8), past approach_hint_yd.
	var nine: CourseData = NineHoles.land()
	var b := CourseBuilder.new(nine)
	var opened: Array[int] = NineHoles.build(b)
	assert_eq(opened.size(), 9, "every hole still opens: a hint is not a rule")
	var hints: Array = _v.hint_slots(nine)
	assert_eq(hints.size(), 9)
	var one: Array[CourseValidator.Issue] = []
	one.assign(hints[0])
	assert_eq(one.size(), 1, "hole 1's approach holds hole 2's tee")
	if not one.is_empty():
		assert_eq(one[0].rule, CourseValidator.HINT)
		assert_eq(one[0].tile, Vector2i(92, 8))
		assert_string_contains(one[0].reason, "hole 2's tee is 50 yd from this cup")
		_assert_one_line(one[0])
	var two: Array[CourseValidator.Issue] = []
	two.assign(hints[1])
	assert_true(two.any(func(i: CourseValidator.Issue) -> bool:
			return i.tile == Vector2i(92, 8) and i.reason.contains("tee is 50 yd from hole 1's cup")),
			"and hole 2 is told its tee is in hole 1's approach")
	assert_false(two.any(func(i: CourseValidator.Issue) -> bool: return i.tile == Vector2i(120, 19)),
			"hole 3's tee, 56 yd from hole 2's cup, is clear")
	for slot: int in 9:
		assert_eq(b.hints_at(slot).size(), (hints[slot] as Array).size(), "the builder keeps slot %d's" % slot)
		for issue: CourseValidator.Issue in b.issues_at(slot):
			assert_ne(issue.rule, CourseValidator.HINT, "no hint among the rules")
	assert_true(b.hole(1).open and b.hole(2).open, "both stay open")


func test_the_approach_hint_reads_its_tuning() -> void:
	var a := HoleData.new(1, 3, Vector2i(2, 5), Vector2i(32, 5))
	var b := HoleData.new(2, 3, Vector2i(40, 5), Vector2i(70, 5))
	var c := _course(80, 10, [a, b])
	assert_eq((_v.hint_slots(c)[0] as Array).size(), 1, "40 yd: inside 50")
	var t := ValidatorTuning.load_default().duplicate() as ValidatorTuning
	t.approach_hint_yd = 35.0
	assert_eq((CourseValidator.new(t).hint_slots(c)[0] as Array).size(), 0, "outside 35")
	var lone := _course(80, 10, [a, HoleData.new(2, 3, Vector2i(40, 5), HoleData.UNPLACED)])
	assert_eq((_v.hint_slots(lone)[0] as Array).size(), 0, "a hole with no cup gives no hint")


func test_a_dogleg_costs_the_validator_little() -> void:
	if BestTime.later(self):
		return
	var c := _dogleg(Vector2i(6, 6), Vector2i(60, 6), Vector2i(60, 60), 5)
	var straight := ReactionHoles.fair_par4()
	var bent_ms: float = BestTime.ms(func() -> void: _v.hole_yardage(c, c.holes[0]))
	var straight_ms: float = BestTime.ms(func() -> void: _v.hole_yardage(straight, straight.holes[0]))
	gut.p("line of play: dogleg %.3f ms, straight hole %.3f ms (fastest of %d)" % [
			bent_ms, straight_ms, BestTime.RUNS])
	assert_lt(bent_ms, 2.0, "a dogleg's line of play stays under 2 ms (debug build)" + BestTime.load_note())
	assert_lt(straight_ms, 1.0, "a straight hole's zone check stays under 1 ms" + BestTime.load_note())


# --- rule 7, on foot (E14-S3, D69) ---

## A 48 x 40 course of rough at 2, clubhouse in the south-west, with a lake x 20 to 39, y 6 to 25
## and an island green (x 27 to 31, y 13 to 17, the cup at its middle) inside it; hole 1's tee
## south of the lake at (29, 34), par 3.
func _island() -> CourseData:
	var c := CourseData.create(48, 40, Surface.Type.ROUGH, 2)
	for y: int in range(6, 26):
		for x: int in range(20, 40):
			c.set_tile(x, y, 1, Surface.Type.WATER)
	for y: int in range(13, 18):
		for x: int in range(27, 32):
			c.set_tile(x, y, 2, Surface.Type.GREEN)
	c.set_holes([HoleData.new(1, 3, Vector2i(29, 34), Vector2i(29, 15))])
	c.set_clubhouse(Vector2i(6, 34), 0)
	return c


## Paints cart path from (29, 18) to (29, 25), a bridge from the island to the south shore.
func _bridge(b: CourseBuilder) -> void:
	b.begin_stroke()
	for y: int in range(18, 26):
		b.paint(Vector2i(29, y), Surface.Type.CART_PATH, 1)
	b.end_stroke()


func test_rule7_an_island_green_with_no_bridge_fails_with_the_reason() -> void:
	var c := _island()
	var issues := _v.check_hole(c, c.holes[0])
	var i := _issue(issues, 7)
	assert_not_null(i, "rule 7 fails: %s" % [issues])
	assert_eq(i.reason, "no way to walk to the 1st green: add a bridge")
	assert_eq(i.tile, Vector2i(29, 15), "on the cup")
	_assert_one_line(i)


func test_rule7_a_bridge_opens_the_island_hole() -> void:
	var c := _island()
	var b := CourseBuilder.new(c)
	assert_false(b.hole(1).open, "closed: no way to walk to its green")
	assert_has(_rules(b.issues_for(1)), 7)
	var opened: Array = []
	b.holes_opened.connect(func(n: Array[int]) -> void: opened.append_array(n))
	_bridge(b)
	assert_eq(b.issues_for(1), [] as Array[CourseValidator.Issue], "every rule passes")
	assert_true(b.hole(1).open, "the bridge opens it (D64)")
	assert_eq(opened, [1])
	assert_true(b.undo())
	assert_false(b.hole(1).open, "undo takes the bridge and closes it again")
	assert_has(_rules(b.issues_for(1)), 7)


func test_rule7_a_tee_cut_off_from_the_clubhouse_fails() -> void:
	var c := _island()
	# Water right across the map between the clubhouse (west) and the tee: the tee is cut off.
	for y: int in c.height:
		c.set_tile(15, y, 1, Surface.Type.WATER)
	var b := CourseBuilder.new(c)
	_bridge(b)
	var i := _issue(b.issues_for(1), 7)
	assert_not_null(i)
	assert_eq(i.reason, "no way to walk to the 1st tee: add a bridge")
	assert_eq(i.tile, Vector2i(29, 34))
	b.paint(Vector2i(15, 34), Surface.Type.CART_PATH, 1)
	assert_null(_issue(b.issues_for(1), 7), "a bridge over the channel joins them")
	assert_true(b.hole(1).open)


func test_rule7_an_island_in_the_footprint_fails_and_one_outside_it_does_not() -> void:
	var c := _island()
	var b := CourseBuilder.new(c)
	_bridge(b)
	assert_true(b.hole(1).open)
	# A dry islet of rough beside the line inside the lake: a ball could rest there.
	b.paint(Vector2i(25, 21), Surface.Type.ROUGH, 1)
	var i := _issue(b.issues_for(1), 7)
	assert_not_null(i, "an island in the footprint")
	assert_eq(i.reason, "no way to walk to the island at (25, 21) on the 1st: add a bridge")
	assert_false(b.hole(1).open)
	assert_true(b.undo())
	assert_true(b.hole(1).open)
	# Far from the line (footprint 30 yd: 6 tiles), an islet is no ball's.
	b.paint(Vector2i(38, 7), Surface.Type.ROUGH, 1)
	assert_null(_issue(b.issues_for(1), 7), "outside the footprint it does not count")
	assert_true(b.hole(1).open)


func test_rule7_with_no_clubhouse_reads_from_the_tee() -> void:
	var c := _island()
	c.set_clubhouse(CourseData.NO_CLUBHOUSE, 0)
	var i := _issue(_v.check_hole(c, c.holes[0]), 7)
	assert_not_null(i, "the green still cannot be walked to from the tee")
	assert_eq(i.reason, "no way to walk to the 1st green: add a bridge")
	assert_eq(_v.check_hole(_island(), c.holes[0]).size() > 0, true)


func test_rule7_is_measured_once_while_the_water_stands() -> void:
	var c := _island()
	var b := CourseBuilder.new(c)
	_bridge(b)
	var walk: Variant = b.validator.get("_walk_graph")
	b.paint(Vector2i(2, 2), Surface.Type.FAIRWAY, 1)
	assert_same(b.validator.get("_walk_graph"), walk, "a paint that moves no water keeps the graph")
	b.paint(Vector2i(2, 2), Surface.Type.CART_PATH, 1)
	b.paint(Vector2i(25, 21), Surface.Type.CART_PATH, 1)
	assert_not_same(b.validator.get("_walk_graph"), walk, "a bridge built reads the graph again")


func test_rule7_an_undo_finds_the_graph_it_had() -> void:
	var c := _island()
	var b := CourseBuilder.new(c)
	_bridge(b)
	var before: Variant = b.validator.get("_walk_graph")
	b.paint(Vector2i(22, 10), Surface.Type.ROUGH, 3)  # land in the lake: the water changed
	assert_not_same(b.validator.get("_walk_graph"), before)
	assert_true(b.undo())
	assert_same(b.validator.get("_walk_graph"), before, "the water as it was: its graph, labelled")
	assert_true(b.hole(1).open)
