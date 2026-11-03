extends GutTest
## E2-S2: the five hole rules of docs/design.md (Hole validation rules, D11), the one
## validator the game and /course-file share. Every failing rule names a tile and a reason.

const EXAMPLE_PATH := "res://courses/example_par3.json"

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


func test_tuning_holds_the_d11_numbers() -> void:
	var t := ValidatorTuning.load_default()
	assert_not_null(t)
	assert_eq(t.landing_distance_yd, 240.0)
	assert_eq(t.cup_clearance_yd, 60.0)
	assert_eq(t.zone_radius_yd, 30.0)
	assert_eq(t.footprint_half_width_yd, 30.0)
	assert_eq(t.par4_min_yd, 250)
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
	assert_eq(ia.tile, Vector2i(2, 8), "hole A points at the other tee")
	assert_eq(ib.tile, Vector2i(2, 2), "hole B points at the other tee")
	_assert_one_line(ia)



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
	assert_eq(ia.tile, Vector2i(2, 8), "points at the other hole's tee, not its own")

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
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(50, 0)), 250)
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(30, 40)), 250)
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(47, 17)), 250, "249.90 rounds up")
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(49, 9)), 249, "249.10 rounds down")
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(94, 0)), 470)
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(94, 4)), 470, "470.43")
	assert_eq(CourseValidator.yardage(Vector2i(0, 0), Vector2i(94, 5)), 471, "470.66")


func test_rule4_par_for_yardage_at_the_boundaries() -> void:
	assert_eq(_v.par_for_yardage(249), 3)
	assert_eq(_v.par_for_yardage(250), 4)
	assert_eq(_v.par_for_yardage(470), 4)
	assert_eq(_v.par_for_yardage(471), 5)


func test_rule4_at_exactly_250_yd() -> void:
	for d: Vector2i in [Vector2i(50, 0), Vector2i(30, 40), Vector2i(47, 17)]:
		assert_null(_par_check(d, 4), "%s is a par 4" % d)
		var issue := _par_check(d, 3)
		assert_not_null(issue, "%s is not a par 3" % d)
		if issue:
			assert_eq(issue.tile, Vector2i(2, 2) + d, "points at the cup")
			assert_string_contains(issue.reason, "250")
			_assert_one_line(issue)
	assert_null(_par_check(Vector2i(49, 9), 3), "249 yd is a par 3")
	assert_not_null(_par_check(Vector2i(49, 9), 4), "249 yd is not a par 4")


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
	assert_null(_v.landing_zone(c.holes[1]), "a par 3 has no zone")


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
	# A 260 yd par 4 (zone centre 200 yd out) with another tee 25 yd beside its cup.
	var a := HoleData.new(1, 4, Vector2i(10, 10), Vector2i(62, 10))
	var b := HoleData.new(2, 3, Vector2i(62, 15), Vector2i(62, 45))
	var c := _course(80, 50, [a, b])
	assert_eq(CourseValidator.yardage(a.tee, a.cup), 260)
	var zone: Vector2 = _v.landing_zone(c.holes[0])
	assert_almost_eq(zone.x, 50.0, 0.001, "200 yd out")
	var all := _v.check_course(c)
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

# --- the course as a whole, and the example ---

func test_check_course_keys_every_hole_by_number() -> void:
	var c := _two_holes(Vector2i(53, 27))
	var all := _v.check_course(c)
	assert_eq(all.keys(), [1, 2])


func test_generated_par3_passes_all_five_rules() -> void:
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
	assert_eq(out.filter(func(l: String) -> bool: return l.contains("rule")).size(), 5, "one line per rule")
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
	var c := _walled_sandbox()
	var start := Time.get_ticks_usec()
	var all := _v.check_course(c)
	var ms: float = (Time.get_ticks_usec() - start) / 1000.0
	for n: int in range(1, 10):
		assert_not_null(_issue(all[n], 3), "hole %d is walled off" % n)
	gut.p("check_course, 9 walled holes on 128x128: %.1f ms" % ms)
	assert_lt(ms, 100.0, "one edit's rerun of nine holes stays under 100 ms (debug build)")


func test_check_hole_on_a_128_plot_is_fast() -> void:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	c.set_tile(100, 64, 2, Surface.Type.GREEN)
	c.set_holes([HoleData.new(1, 5, Vector2i(4, 64), Vector2i(100, 64))])
	var start := Time.get_ticks_usec()
	var issues := _v.check_hole(c, c.holes[0])
	var ms: float = (Time.get_ticks_usec() - start) / 1000.0
	assert_eq(issues, [] as Array[CourseValidator.Issue])
	gut.p("check_hole, one par 5 on 128x128: %.1f ms" % ms)
	assert_lt(ms, 30.0, "one hole's check stays under 30 ms (debug build)")
