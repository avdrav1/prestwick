extends GutTest
## E2-S5: the 12 clubs in golf/clubs.tres, their legality per lie and per stroke (D13), and
## the shot model's carry, power and roll factor (D14).

const IDS: PackedStringArray = ["driver", "3w", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "pw", "sw", "putter"]
const EPS := 0.01

var clubs: ClubSet


func before_each() -> void:
	clubs = ClubSet.load_default()


func _ids(list: Array[Club]) -> PackedStringArray:
	var out := PackedStringArray()
	for c in list:
		out.append(c.id)
	return out


# --- the table ---

func test_the_table_loads_with_all_12_clubs() -> void:
	assert_not_null(clubs, "golf/clubs.tres loads")
	assert_eq(clubs.validate(), PackedStringArray(), "12 clubs, one driver, one sand wedge, one putter")
	assert_eq(_ids(clubs.clubs), IDS, "longest first, as docs/design.md Swing lists them")
	for c in clubs.clubs:
		if c.is_putter():
			continue
		assert_gt(c.carry_yd, 0.0, "%s has a carry" % c.id)
		assert_between(c.launch_deg, 5.0, 60.0, "%s has a launch angle" % c.id)
		assert_between(c.roll_factor, 0.1, 1.0, "%s has a roll factor" % c.id)


func test_carries_fall_and_launch_angles_rise_through_the_bag() -> void:
	var prev: Club = null
	for c in clubs.clubs:
		if c.is_putter():
			continue
		if prev != null:
			assert_lt(c.carry_yd, prev.carry_yd, "%s carries less than %s" % [c.id, prev.id])
			assert_gt(c.launch_deg, prev.launch_deg, "%s launches higher than %s" % [c.id, prev.id])
			assert_lte(c.roll_factor, prev.roll_factor, "%s rolls no more than %s" % [c.id, prev.id])
		prev = c


func test_sand_wedge_keeps_the_bunker_target_reachable() -> void:
	# docs/design.md hand calculation step 2: the SW must carry 80 yd or more.
	assert_gte(clubs.club("sw").carry_yd, 80.0)


func test_putter_has_a_speed_range_and_a_full_putt_limit() -> void:
	var p := clubs.putter()
	assert_eq(p.id, "putter")
	assert_gt(p.putt_min_speed, 0.0)
	assert_gt(p.putt_max_speed, p.putt_min_speed)
	assert_gt(clubs.full_putt_max_yd, 0.0)


func test_validate_catches_a_missing_putter() -> void:
	var bag: ClubSet = clubs.duplicate(true)
	bag.clubs.pop_back()
	var errors := bag.validate()
	assert_gt(errors.size(), 0)


# --- legality (D13), per lie and per stroke ---

func test_green_allows_the_putter_only() -> void:
	for first: bool in [true, false]:
		assert_eq(_ids(clubs.legal(Surface.Type.GREEN, first)), PackedStringArray(["putter"]),
				"first stroke %s" % first)


func test_bunker_allows_the_sand_wedge_only() -> void:
	for first: bool in [true, false]:
		assert_eq(_ids(clubs.legal(Surface.Type.BUNKER, first)), PackedStringArray(["sw"]),
				"first stroke %s" % first)


func test_the_putter_is_legal_on_green_and_nowhere_else() -> void:
	var putter := clubs.putter()
	for s in Surface.COUNT:
		for first: bool in [true, false]:
			assert_eq(ClubSet.is_legal(putter, s as Surface.Type, first), s == Surface.Type.GREEN,
					"%s, first stroke %s" % [Surface.name_of(s), first])


func test_driver_on_the_first_stroke_from_the_tee_marker_whatever_the_surface() -> void:
	var driver := clubs.club("driver")
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.TEE, Surface.Type.CART_PATH]:
		assert_true(ClubSet.is_legal(driver, s, true), "first stroke from a marker on %s" % Surface.name_of(s))


func test_driver_later_only_from_a_tee_tile() -> void:
	var driver := clubs.club("driver")
	assert_true(ClubSet.is_legal(driver, Surface.Type.TEE, false), "a ball resting on a tee tile")
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.CART_PATH, Surface.Type.TREES]:
		assert_false(ClubSet.is_legal(driver, s, false), "not a later stroke from %s" % Surface.name_of(s))


func test_a_tee_marker_on_green_takes_the_putter() -> void:
	# D13's order: green is checked first, so the first stroke there is a putt.
	assert_false(ClubSet.is_legal(clubs.club("driver"), Surface.Type.GREEN, true))


func test_fairway_and_rough_allow_every_club_but_putter_and_driver_later() -> void:
	var expected := PackedStringArray(["3w", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "pw", "sw"])
	for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.ROUGH]:
		assert_eq(_ids(clubs.legal(s, false)), expected, Surface.name_of(s))
		var first := _ids(clubs.legal(s, true))
		assert_eq(first[0], "driver", "first stroke adds the driver on %s" % Surface.name_of(s))
		assert_eq(first.size(), 11)


func test_sand_wedge_is_legal_everywhere_but_green() -> void:
	var sw := clubs.club("sw")
	for s in Surface.COUNT:
		assert_eq(ClubSet.is_legal(sw, s as Surface.Type, false), s != Surface.Type.GREEN, Surface.name_of(s))


# --- the shot model (D14) ---

func _flat(surface: Surface.Type = Surface.Type.FAIRWAY) -> CourseData:
	return CourseData.create(120, 20, surface, 0)


func _carry(course: CourseData, shot: ShotLaunch) -> float:
	var p := ShotPrediction.run_launch(course, 1, shot)
	return Vector2(p.landing.x, p.landing.y).distance_to(Vector2(shot.start.x, shot.start.y))


func test_every_full_club_carries_its_carry_on_flat_ground() -> void:
	var model := ShotModel.new()
	var course := _flat()
	var field := HeightField.new(course, model.params)
	for c in clubs.clubs:
		if c.is_putter():
			continue
		var shot := model.full(field, c, 1.0, Vector2(12.5, 52.5), 0.0)
		assert_almost_eq(_carry(course, shot), c.carry_yd, 0.05, "%s carry" % c.id)


func test_power_is_a_share_of_carry_not_of_speed() -> void:
	var model := ShotModel.new()
	var course := _flat()
	var field := HeightField.new(course, model.params)
	var c := clubs.club("7i")
	for power: float in [0.25, 0.5, 1.1]:
		var shot := model.full(field, c, power, Vector2(12.5, 52.5), 0.0)
		assert_almost_eq(shot.target_carry, c.carry_yd * power, EPS)
		assert_almost_eq(_carry(course, shot), c.carry_yd * power, 0.05, "%d%% carries %d%%" % [power * 100, power * 100])


func test_accuracy_offset_turns_the_heading_and_the_ball_flies_straight() -> void:
	var model := ShotModel.new()
	var course := _flat()
	var field := HeightField.new(course, model.params)
	var c := clubs.club("7i")
	var at := Vector2(12.5, 52.5)
	var shot := model.full(field, c, 1.0, at, 0.0, 4.0)
	assert_almost_eq(shot.heading_deg, 4.0, EPS)
	var p := ShotPrediction.run_launch(course, 1, shot)
	var land := Vector2(p.landing.x, p.landing.y) - at
	assert_almost_eq(rad_to_deg(land.angle()), 4.0, 0.01, "lands on the launch heading")


func test_roll_factor_scales_the_roll_and_never_the_carry() -> void:
	var course := _flat()
	var v := Ball.launch_velocity(40.0, 30.0, 0.0)
	var start := Vector3(12.5, 52.5, 0.0)
	var full := ShotPrediction.run(course, 3, start, v)
	var half := ShotPrediction.run(course, 3, start, v, null, null, 0.5)
	assert_almost_eq(half.landing.x, full.landing.x, 0.0001, "same carry")
	assert_lt(half.rest.x - half.landing.x, full.rest.x - full.landing.x, "rolls less")
	assert_gt(half.rest.x, half.landing.x, "but still rolls")


func test_roll_factor_applies_after_the_first_touchdown_bounce_friction() -> void:
	# A bunker lie: roll 0 stops the ball dead whatever the factor.
	var course := _flat(Surface.Type.BUNKER)
	var v := Ball.launch_velocity(30.0, 40.0, 0.0)
	var a := ShotPrediction.run(course, 1, Vector3(12.5, 52.5, 0), v, null, null, 0.3)
	assert_almost_eq(a.rest.x, a.landing.x, 0.0001)


func test_full_putt_on_a_flat_green_stays_under_the_limit() -> void:
	var model := ShotModel.new()
	var course := _flat(Surface.Type.GREEN)
	var field := HeightField.new(course, model.params)
	var at := Vector2(12.5, 52.5)
	var p := clubs.putter()
	var shot := model.putt(field, p, p.putt_max_speed, at, 0.0)
	assert_true(shot.is_putt())
	var r := ShotPrediction.run_launch(course, 1, shot)
	var d := r.rest.x - at.x
	assert_lte(d, clubs.full_putt_max_yd, "a full putt rolls %.1f yd, at most N" % d)
	assert_gt(d, clubs.full_putt_max_yd * 0.75, "and close enough to N that N means something")


func test_putt_speed_is_clamped_to_the_putter_range() -> void:
	var model := ShotModel.new()
	var field := HeightField.new(_flat(Surface.Type.GREEN), model.params)
	var p := clubs.putter()
	assert_almost_eq(model.putt(field, p, 999.0, Vector2(10, 10), 0.0).ground_velocity.length(), p.putt_max_speed, EPS)
	assert_almost_eq(model.putt(field, p, 0.0, Vector2(10, 10), 0.0).ground_velocity.length(), p.putt_min_speed, EPS)


func test_the_putter_ignores_the_lie() -> void:
	# Rough would cost a full club 15%; a putt starts at the speed asked.
	var model := ShotModel.new()
	var field := HeightField.new(_flat(Surface.Type.ROUGH), model.params)
	var shot := model.putt(field, clubs.putter(), 5.0, Vector2(10, 10), 0.0)
	assert_almost_eq(shot.ground_velocity.length(), 5.0, EPS)
	assert_almost_eq(shot.roll_factor, 1.0, EPS)


# --- a ball at the foot of a riser (D20, docs/design.md Shot model) ---

## Each full club's perfect swing from the riser foot, `back_yd` short of the tile centre
## where a `steps`-step riser begins: {id: [carry, blocked]}.
func _riser_foot(steps: int, back_yd: float) -> Dictionary:
	var model := ShotModel.new()
	var course := BalanceStrips.uphill(steps)
	var field := HeightField.new(course, model.params)
	var at := (Vector2(BalanceStrips.tee_tile()) + Vector2(0.5, 0.5)) * model.params.yards_per_tile
	at.x -= back_yd
	var out := {}
	for c in clubs.clubs:
		if c.is_putter():
			continue
		var shot := model.full(field, c, 1.0, at, 0.0)
		var r := ShotPrediction.run_launch(course, 1, shot, model.params)
		assert_almost_eq(r.carry_yd, r.landing.x - at.x, EPS, "%s: carry is start to first touchdown" % c.id)
		assert_eq(r.stop_point, r.landing, "%s: on a riser the flight stops at its first touchdown" % c.id)
		out[c.id] = [r.carry_yd, clubs.is_blocked(shot, r)]
	return out


func _blocked_ids(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in IDS:
		if d.has(id) and d[id][1]:
			out.append(id)
	return out


## D20: the physics is kept (a launch flatter than the face ahead meets it on the first
## tick), and a club whose perfect swing meets the face while still climbing is blocked.
## Every other club flies, so its marker (the first touchdown) is where it lands.
func test_a_club_flatter_than_the_riser_ahead_meets_it_at_once_and_is_blocked() -> void:
	var one := _riser_foot(1, 0.0)
	for id: String in ["driver", "3w", "3i", "4i", "5i"]:
		assert_lt(float(one[id][0]), 2.0, "%s meets a 1-step riser (0.4, 21.8 deg) at once" % id)
		assert_true(one[id][1], "%s is blocked at the foot of a 1-step riser" % id)
	for id: String in ["6i", "7i", "8i", "9i", "pw", "sw"]:
		assert_gt(float(one[id][0]), 90.0, "%s clears a 1-step riser" % id)
		assert_false(one[id][1], "%s is not blocked" % id)
	var back := _riser_foot(1, 1.0)
	for id: String in ["driver", "3w", "3i"]:
		assert_lt(float(back[id][0]), 5.0, "%s still meets it from 1 yd short" % id)
		assert_true(back[id][1], "%s is still blocked from 1 yd short" % id)
	for id: String in ["4i", "5i"]:
		assert_gt(float(back[id][0]), 150.0, "%s clears it from 1 yd short" % id)
		assert_false(back[id][1], "%s is not blocked from 1 yd short" % id)
	var two := _riser_foot(2, 0.0)
	for c in clubs.clubs:
		if not c.is_putter():
			assert_lt(float(two[c.id][0]), 5.0, "%s gets no carry off a 2-step riser (0.8, 38.7 deg)" % c.id)
			assert_true(two[c.id][1], "%s is blocked at the foot of a 2-step riser" % c.id)


## D20 review: the rule is whether the flight meets the face, not a distance, so it holds
## one to three tiles back too (a 5 yd carry cutoff let the driver carry 5 to 14 yd into the
## face unflagged and then run 120 yd). Every club either is blocked or flies over 90 yd.
func test_the_blocked_rule_holds_further_back_from_a_riser() -> void:
	var want := {
		"1:2": ["driver", "3w"],
		"1:3": ["driver"],
		"1:4": [],
		"1:7": [],
		"1:10": [],
		"2:2": ["driver", "3w", "3i", "4i", "5i", "6i", "7i", "8i"],
		"2:3": ["driver", "3w", "3i", "4i", "5i", "6i", "7i"],
		"2:4": ["driver", "3w", "3i", "4i", "5i", "6i"],
		"2:7": ["driver", "3w", "3i"],
		"2:10": ["driver"],
		"2:15": [],
	}
	for key: String in want:
		var parts := key.split(":")
		var steps := int(parts[0])
		var back_yd := float(parts[1])
		var d := _riser_foot(steps, back_yd)
		assert_eq(_blocked_ids(d), PackedStringArray(want[key]),
				"%d-step riser, %d yd back: the clubs that meet the face" % [steps, back_yd])
		for id: String in d:
			if d[id][1]:
				assert_lt(float(d[id][0]), 15.0, "%s, %s: blocked means it meets the face" % [key, id])
			else:
				assert_gt(float(d[id][0]), 90.0, "%s, %s: not blocked means it flies" % [key, id])


## A strip with a band of trees three tiles deep starting `gap` tiles past the tee.
func _trees_ahead(gap: int) -> CourseData:
	var c := BalanceStrips.strip(Surface.Type.FAIRWAY)
	var t := BalanceStrips.tee_tile()
	for y in BalanceStrips.STRIP_H:
		for x in range(t.x + 1 + gap, t.x + 4 + gap):
			c.set_tile(x, y, 0, Surface.Type.TREES)
	return c


func _blocked_by_trees(gap: int, rng_seed: int) -> PackedStringArray:
	var model := ShotModel.new()
	var course := _trees_ahead(gap)
	var field := HeightField.new(course, model.params)
	var at := (Vector2(BalanceStrips.tee_tile()) + Vector2(0.5, 0.5)) * model.params.yards_per_tile
	var out := PackedStringArray()
	for c in clubs.clubs:
		if c.is_putter():
			continue
		var shot := model.full(field, c, 1.0, at, 0.0)
		var r := ShotPrediction.run_launch(course, rng_seed, shot, model.params)
		if clubs.is_blocked(shot, r):
			assert_true(r.scattered, "gap %d, %s, seed %d: the trees stop it" % [gap, c.id, rng_seed])
			assert_gt(r.stop_point.x, at.x, "gap %d, %s, seed %d: stopped ahead of the ball" % [gap, c.id, rng_seed])
			out.append(c.id)
	return out


## D20 review: trees right in front stop every club while it climbs. The rule reads the
## flight before the scatter, so it does not change with the stroke's seed (the scatter
## does), and the blocked marker's point is where the trees stop it, ahead of the ball.
func test_trees_right_in_front_block_every_club_on_every_seed() -> void:
	var every := PackedStringArray(["driver", "3w", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "pw", "sw"])
	for gap: int in [0, 1, 2]:
		for s in range(1, 11):
			assert_eq(_blocked_by_trees(gap, s), every, "trees %d tiles out, seed %d" % [gap, s])
	# Six tiles out the long clubs are still climbing into the trees; the 5i and up clear them.
	for s in range(1, 6):
		assert_eq(_blocked_by_trees(6, s), PackedStringArray(["driver", "3w", "3i", "4i"]),
				"trees 30 yd out, seed %d" % s)
	# Ten tiles out every club is coming down before it reaches them: none is blocked.
	assert_eq(_blocked_by_trees(10, 1), PackedStringArray(), "trees 50 yd out")


func test_no_club_is_blocked_on_flat_ground_and_a_putt_never_is() -> void:
	var model := ShotModel.new()
	var course := BalanceStrips.strip(Surface.Type.FAIRWAY)
	var field := HeightField.new(course, model.params)
	var at := (Vector2(BalanceStrips.tee_tile()) + Vector2(0.5, 0.5)) * model.params.yards_per_tile
	for c in clubs.clubs:
		var shot := model.putt(field, c, c.putt_min_speed, at, 0.0) if c.is_putter() \
				else model.full(field, c, 1.0, at, 0.0)
		var r := ShotPrediction.run_launch(course, 1, shot, model.params)
		assert_false(clubs.is_blocked(shot, r), "%s is not blocked on flat fairway" % c.id)
