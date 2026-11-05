extends GutTest
## E3-S3: guests swing the player's bar and shot model with skill as noise (D40), pick a club
## and an aim with the player's marker (D41), play a hole out with no scene, and spend Ball
## work only through a tick budget (Guest Ball work). docs/design.md Guests and reactions.

## Guests a skill a hole in the scoring test (seeds 7, 107, ...).
const FIELD: int = 16

var tuning: GuestTuning
var model: ShotModel


func before_all() -> void:
	tuning = GuestTuning.load_default()
	model = ShotModel.new()


# --- tuning ---

func test_tuning_reads_data_guests_json() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GuestTuning.PATH))
	assert_eq(tuning.full_sigma_best, float(raw.full_sigma_best))
	assert_eq(tuning.full_sigma_worst, float(raw.full_sigma_worst))
	assert_eq(tuning.putt_aim_sigma_worst, float(raw.putt_aim_sigma_worst))
	assert_eq(tuning.guest_ticks_per_s, int(raw.guest_ticks_per_s))
	assert_eq(tuning.guest_putt_max_runs, int(raw.guest_putt_max_runs))
	assert_eq(tuning.guest_min_power, float(raw.guest_min_power))
	assert_eq(tuning.aim_offsets_deg.size(), (raw.aim_offsets_deg as Array).size())
	var errors: Array[String] = []
	GuestTuning.from_dict({}, errors)
	assert_gt(errors.size(), 10, "an empty file names every missing number")


## E3-S13: the shipped file holds every range.
func test_the_shipped_file_passes_its_range_checks() -> void:
	var errors: Array[String] = []
	GuestTuning.from_dict(_shipped(), errors)
	assert_eq(errors, [] as Array[String], "data/guests.json loads with no errors")


## E3-S13: each min/max or best/worst pair swapped is an error that names both keys.
func test_a_swapped_range_names_that_range() -> void:
	var pairs := [
		["full_sigma_best", "full_sigma_worst"],
		["putt_aim_sigma_best", "putt_aim_sigma_worst"],
		["putt_power_sigma_best", "putt_power_sigma_worst"],
		["group_size_min", "group_size_max"],
		["skill_min", "skill_max"],
		["patience_min", "patience_max"],
	]
	for pair: Array in pairs:
		var d := _shipped()
		var a: Variant = d[pair[0]]
		d[pair[0]] = d[pair[1]]
		d[pair[1]] = a
		var errors := _errors(d)
		assert_eq(errors.size(), 1, "%s and %s swapped: one error (%s)" % [pair[0], pair[1], errors])
		assert_true(_named(errors, pair[0]) and _named(errors, pair[1]),
				"the error names %s and %s: %s" % [pair[0], pair[1], errors])


## E3-S13: weights and per-second rates must be above 0; guest_min_power inside 0 to 1.
func test_a_weight_or_rate_at_zero_and_min_power_outside_0_to_1_are_named() -> void:
	for key: String in ["walk_yd_per_s", "guest_ticks_per_s", "sim_ticks_per_s",
			"flight_draw_speed", "doubled_check_weight"]:
		for bad: Variant in [0, -1]:
			var d := _shipped()
			d[key] = bad
			if key == "guest_ticks_per_s":
				d["sim_ticks_per_s"] = 4800
			var errors := _errors(d)
			assert_true(_named(errors, key), "%s = %s is named: %s" % [key, bad, errors])
	for name: String in Guest.TASTE_NAMES:
		for bad: Variant in [0, -1, "one"]:
			var d := _shipped()
			(d.taste_weights as Dictionary)[name] = bad
			var errors := _errors(d)
			assert_eq(errors.size(), 1, "taste_weights.%s = %s: %s" % [name, bad, errors])
			assert_true(_named(errors, "taste_weights.%s" % name), str(errors))
		var gone := _shipped()
		(gone.taste_weights as Dictionary).erase(name)
		assert_true(_named(_errors(gone), "taste_weights.%s" % name), "a missing weight is named")
	for bad: float in [0.0, -0.1, 1.5]:
		var d := _shipped()
		d["guest_min_power"] = bad
		var errors := _errors(d)
		assert_eq(errors.size(), 1, "guest_min_power = %s: %s" % [bad, errors])
		assert_true(_named(errors, "guest_min_power"), str(errors))
	var full := _shipped()
	full["guest_min_power"] = 1.0
	assert_eq(_errors(full).size(), 0, "guest_min_power 1 (full power) is inside the range")


## E3-S13 review: the day's clock keys are checked too, so a bad day_s edit (D46) fails loudly.
func test_the_day_clock_keys_out_of_range_are_named() -> void:
	var cases: Array = [["day_s", 0], ["day_s", -1], ["stroke_s", 0], ["stroke_s", -1],
			["arrival_window", -0.1], ["arrival_window", 1.5], ["arrivals_per_day", -2]]
	for c: Array in cases:
		var d := _shipped()
		d[c[0]] = c[1]
		var errors := _errors(d)
		assert_eq(errors.size(), 1, "%s = %s: %s" % [c[0], c[1], errors])
		assert_true(_named(errors, c[0]), str(errors))
	for ok: Array in [["arrival_window", 0.0], ["arrival_window", 1.0], ["arrivals_per_day", 0]]:
		var d := _shipped()
		d[ok[0]] = ok[1]
		assert_eq(_errors(d).size(), 0, "%s = %s is inside the range" % [ok[0], ok[1]])


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GuestTuning.PATH))


func _errors(d: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	GuestTuning.from_dict(d, errors)
	return errors


func _named(errors: Array[String], key: String) -> bool:
	for e: String in errors:
		if e.contains(key):
			return true
	return false


func test_sigma_is_linear_in_skill_and_expected_score_runs_par_to_par_plus_2() -> void:
	assert_almost_eq(tuning.full_sigma(10), tuning.full_sigma_best, 1e-9)
	assert_almost_eq(tuning.full_sigma(1), tuning.full_sigma_worst, 1e-9)
	var mid := lerpf(tuning.full_sigma_best, tuning.full_sigma_worst, 5.0 / 9.0)
	assert_almost_eq(tuning.full_sigma(5), mid, 1e-9, "linear between")
	assert_almost_eq(tuning.putt_aim_sigma(10), tuning.putt_aim_sigma_best, 1e-9)
	assert_almost_eq(tuning.putt_power_sigma(1), tuning.putt_power_sigma_worst, 1e-9)
	assert_almost_eq(tuning.expected_score(4, 10), 4.0, 1e-9, "skill 10 expects par")
	assert_almost_eq(tuning.expected_score(4, 1), 6.0, 1e-9, "skill 1 expects par + 2")
	var t := tuning.guest_swing_tuning(SwingTuning.load_default())
	assert_eq(t.putt_aim_max_runs, tuning.guest_putt_max_runs)
	assert_eq(SwingTuning.load_default().putt_aim_max_runs, 16, "the player's solve is untouched")


func test_club_table_is_the_clubs_tables_flat_totals() -> void:
	var want := {"driver": 282, "3w": 261, "3i": 223, "4i": 208, "5i": 193, "6i": 178,
		"7i": 164, "8i": 150, "9i": 136, "pw": 123, "sw": 110}
	var got := GuestClubTable.totals(model)
	for id: String in want:
		assert_almost_eq(float(got[id]), float(want[id]), 1.5, "%s flat total (docs/design.md Clubs)" % id)
	assert_false(got.has("putter"))
	GuestClubTable.warm(model)
	assert_true(GuestClubTable.is_warm(ShotModel.new()),
			"a fresh ShotModel of the same files is not measured again")
	var custom := ShotModel.new(model.clubs.duplicate(true) as ClubSet)
	assert_false(GuestClubTable.is_warm(custom), "a bag built in code is its own table")


# --- club and aim (D41) ---

func test_plan_takes_the_shortest_legal_club_that_reaches() -> void:
	var course := CourseSave.load_file("res://courses/example_par3.json")
	var hole: HoleData = course.holes[0]
	var field := HeightField.new(course, model.params)
	var at := field.tile_center(hole.tee)
	var p := _plan(course, at, hole.cup, true)
	var totals := GuestClubTable.totals(model)
	var d := at.distance_to(field.tile_center(hole.cup))
	var aim := rad_to_deg((field.tile_center(hole.cup) - at).angle())
	var mult := model.lies.measure(field, at, aim).carry_multiplier()
	assert_true(p.done and p.safe)
	assert_true(ClubSet.is_legal(p.club, field.surface_at(at.x, at.y), true))
	assert_gte(float(totals[p.club.id]) * mult, d, "%s reaches the cup" % p.club.id)
	var legal := model.clubs.legal(field.surface_at(at.x, at.y), true)
	var i := legal.find(p.club)
	assert_lt(float(totals[legal[i + 1].id]) * mult, d, "the next club down does not")
	assert_almost_eq(p.power, d / (float(totals[p.club.id]) * mult), 1e-5)
	assert_eq(p.offset_deg, 0.0, "straight at the cup")
	assert_almost_eq(p.aim_deg, aim, 1e-6)
	assert_eq(p.predictions, 1, "the straight plan was safe")


func test_out_of_reach_takes_the_longest_legal_club_at_full_power() -> void:
	var strip := BalanceStrips.from(Surface.Type.FAIRWAY)
	var field := HeightField.new(strip, model.params)
	var at := field.tile_center(BalanceStrips.tee_tile())
	var cup := BalanceStrips.tee_tile() + Vector2i(90, 0)
	var off_tee := _plan(strip, at, cup, false)
	assert_eq(off_tee.club.id, "3w", "no driver off fairway after the first stroke (D13)")
	assert_eq(off_tee.power, 1.0)
	var first := _plan(strip, at, cup, true)
	assert_eq(first.club.id, "driver", "the driver from the tee marker")
	assert_eq(first.power, 1.0)


func test_plan_skips_a_blocked_club_and_clubs_down() -> void:
	# The ball at the foot of a one-step riser (tests/test_clubs.gd): straight at it the driver
	# to 5i meet the face, the 6i to SW fly. 195 yd wants the 4i, blocked straight and at every
	# aim, so the plan clubs down to the 5i: blocked straight, but at 16 degrees it crosses the
	# face at a slant and flies. Every aim of a club is tried and the safe one nearest the cup
	# kept.
	var strip := BalanceStrips.uphill(1)
	var field := HeightField.new(strip, model.params)
	var at := field.tile_center(BalanceStrips.tee_tile())
	var cup := BalanceStrips.tee_tile() + Vector2i(39, 0)
	var p := _plan(strip, at, cup, false)
	assert_eq(p.club.id, "5i", "one club down from the blocked 4i")
	assert_true(p.safe)
	assert_eq(absf(p.offset_deg), 16.0, "the wide aim is the one that flies")
	assert_false(p.prediction.stopped_climbing, "its perfect swing flies")
	var shot := model.full(field, p.club, p.power, at, p.aim_deg)
	assert_false(model.clubs.is_blocked(shot, p.prediction))
	var aims := 1 + tuning.aim_offsets_deg.size()
	assert_eq(p.predictions, 2 * aims, "the 4i and the 5i at every aim")
	var four := model.clubs.club("4i")
	for off: float in [0.0, 8.0, -8.0, 16.0, -16.0]:
		var s := model.full(field, four, 1.0, at, off)
		var r := ShotPrediction.run_launch(strip, 1, s, model.params)
		assert_true(model.clubs.is_blocked(s, r), "4i at %+.0f deg is blocked (D20)" % off)
	var five := model.full(field, p.club, 1.0, at, 0.0)
	assert_true(model.clubs.is_blocked(five, ShotPrediction.run_launch(strip, 1, five, model.params)),
			"5i straight is blocked")


func test_plan_aims_off_the_cup_round_water() -> void:
	var strip := BalanceStrips.from(Surface.Type.FAIRWAY)
	var t := BalanceStrips.tee_tile()
	for x in range(t.x + 26, t.x + 35):
		for y in range(t.y - 1, t.y + 2):
			strip.set_tile(x, y, 0, Surface.Type.WATER)
	var field := HeightField.new(strip, model.params)
	var at := field.tile_center(t)
	var p := _plan(strip, at, t + Vector2i(36, 0), false)
	assert_true(p.safe)
	assert_true(absf(p.offset_deg) == absf(tuning.aim_offsets_deg[0]),
			"the straight plan lands in the pond, the first aims either side clear it (%s)" % p.offset_deg)
	assert_eq(p.prediction.penalty_strokes, 0)
	assert_eq(p.club.id, "5i", "the same club as the straight plan")


func test_plan_counts_unowned_land_as_ob() -> void:
	# D29: a perfect swing resting on land the player does not own is OB, so the plan turns
	# off it. The parcel the 3w lands in is unowned; the wider aims land on owned parcels.
	var c := CourseData.create(64, 48, Surface.Type.FAIRWAY, 0)
	c.set_parcel_owned(Vector2i(2, 1), false)
	var field := HeightField.new(c, model.params)
	var at := field.tile_center(Vector2i(4, 24))
	var cup := Vector2i(52, 24)
	var p := _plan(c, at, cup, false)
	assert_true(p.safe)
	assert_ne(p.offset_deg, 0.0, "the straight plan ends on unowned land")
	assert_eq(p.prediction.penalty_strokes, 0)
	var rest := field.tile_at(p.prediction.rest.x, p.prediction.rest.y)
	assert_true(c.is_owned(rest.x, rest.y), "it rests on owned land")
	var straight := model.full(field, p.club, p.power, at, p.aim_deg - p.offset_deg)
	var r := ShotPrediction.run_launch(c, 1, straight, model.params, null, cup)
	assert_eq(r.hazard, Ball.Hazard.OB, "straight would be OB on unowned land")


func test_putts_aim_straight_at_the_cup_and_miss_by_the_break() -> void:
	# A green tilted across the line: nobody reads break in the MVP (D41), so even the solve's
	# perfect putt along the line to the cup misses by the break.
	var c := CourseData.create(30, 12, Surface.Type.GREEN, 0)
	for y in 12:
		for x in 30:
			c.set_tile(x, y, y / 3, Surface.Type.GREEN)
	var field := HeightField.new(c, model.params)
	var at := field.tile_center(Vector2i(6, 6))
	var cup := Vector2i(14, 6)
	var p := _plan(c, at, cup, false)
	assert_true(p.is_putt())
	assert_true(p.club.is_putter())
	assert_almost_eq(p.aim_deg, 0.0, 1e-6, "straight at the cup")
	assert_false(p.prediction.holed, "the break takes it off the line")
	var miss := absf(p.prediction.rest.y - field.tile_center(cup).y)
	assert_gt(miss, model.params.cup_radius, "it misses to the low side by the break")
	assert_lte(p.predictions, tuning.guest_putt_max_runs, "the guest's own run cap")


# --- budget ---

func test_no_putt_solve_runs_past_its_budget_in_one_call() -> void:
	# The steep bank (E6-S12): a 16-run solve there is about 5,000 ticks at once.
	var c := CourseData.create(30, 12, Surface.Type.GREEN, 0)
	for y in 12:
		for x in 30:
			c.set_tile(x, y, clampi((x - 10) * 2, 0, 7), Surface.Type.GREEN)
	var field := HeightField.new(c, model.params)
	var budget := 50
	for bx: float in [20.0, 42.5, 60.0]:
		var p := _begin(c, Vector2(bx, 31.0), Vector2i(13, 6), false)
		var calls := 0
		while not p.done:
			var used := p.advance(budget)
			calls += 1
			assert_lte(used, budget, "one call steps at most its budget")
			if calls > 10000:
				break
		assert_true(p.done)
		assert_gt(calls, 1, "a solve from %.1f yd spans calls" % bx)
		assert_lte(p.predictions, tuning.guest_putt_max_runs)
		var whole := _plan(c, Vector2(bx, 31.0), Vector2i(13, 6), false)
		assert_eq(p.power, whole.power, "the same putt whatever the budget")
		assert_eq(p.ticks, whole.ticks)
		assert_true(field.surface_at(bx, 31.0) == Surface.Type.GREEN)


func test_a_hole_plays_the_same_whatever_the_budget() -> void:
	var course := CourseGenerator.generate(4, true, false)
	var hole: HoleData = course.holes[0]
	var a := GuestHole.new(course, hole, 5, 31, tuning, model)
	a.play_out(tuning.guest_ticks_per_s)
	var b := GuestHole.new(course, hole, 5, 31, tuning, model)
	b.play_out(37)
	assert_lte(a.max_second_ticks, tuning.guest_ticks_per_s, "a second spends at most its budget")
	assert_lte(b.max_second_ticks, 37)
	assert_lte(b.max_call_ticks, 37)
	_assert_same_round(a, b, "480 and 37 ticks a second")
	assert_eq(a.ticks, b.ticks, "the same work, spread wider")
	assert_eq(a.ticks, a.plan_ticks + a.ball_ticks, "every tick is a plan's or the ball's")
	var again := GuestHole.new(course, hole, 5, 31, tuning, model)
	again.play_out()
	_assert_same_round(a, again, "the same seed")


# --- playing a hole ---

func test_a_guest_plays_out_a_hole_with_no_scene() -> void:
	var course := CourseSave.load_file("res://courses/example_par3.json")
	var hole: HoleData = course.holes[0]
	var g := GuestHole.new(course, hole, 5, 7, tuning, model)
	assert_eq(g.state, GuestHole.State.PLANNING, "planning from the tee")
	var seconds := g.play_out()
	assert_true(g.is_finished())
	assert_gt(seconds, 0)
	assert_true(g.score.holed or g.score.picked_up)
	assert_eq(g.strokes.size(), g.score.strokes)
	assert_lte(g.score.total(), g.score.limit(), "the player's stroke limit (D12)")
	var first := g.strokes[0]
	assert_true(ClubSet.is_legal(model.clubs.club(first.club_id), Surface.Type.TEE, true))
	for r in g.strokes:
		assert_gt(r.ball_ticks, 0, "its own ball ran")
	if g.score.holed:
		assert_true(g.strokes[-1].holed)


func test_skill_10_scores_near_par_and_skill_1_clearly_worse() -> void:
	var holes := {
		"example_par3": CourseSave.load_file("res://courses/example_par3.json"),
		"generated hilly par 4": CourseGenerator.generate(4, true, false),
	}
	for hole_name: String in holes:
		var course: CourseData = holes[hole_name]
		var hole: HoleData = course.holes[0]
		var best := _mean_score(course, hole, 10)
		var worst := _mean_score(course, hole, 1)
		gut.p("%s par %d: skill 10 mean %.2f (%+.2f), skill 1 mean %.2f (%+.2f), %d guests each" % [
			hole_name, hole.par, best, best - hole.par, worst, worst - hole.par, FIELD])
		assert_almost_eq(best, float(hole.par), 0.6, "%s: skill 10 near par" % hole_name)
		assert_gt(worst - best, 1.0, "%s: skill 1 clearly worse" % hole_name)
		assert_gt(worst, float(hole.par) + 0.75, "%s: skill 1 well over par" % hole_name)


func test_the_off_screen_shortcut_gives_the_same_result_as_the_full_flight() -> void:
	var course := CourseGenerator.generate(4, true, true)
	var hole: HoleData = course.holes[0]
	for rng_seed: int in [3, 11]:
		var off := GuestHole.new(course, hole, 2, rng_seed, tuning, model)
		off.play_out()
		var on := GuestHole.new(course, hole, 2, rng_seed, tuning, model)
		# On screen: the ball steps one tick a call and each drawn position is kept.
		var drawn: Array[Vector3] = []
		while not on.is_finished():
			on.advance(tuning.guest_ticks_per_s, 1)
			if on.state == GuestHole.State.FLYING:
				drawn.append(on.ball_at)
			elif on.state == GuestHole.State.READY:
				on.strike()
		_assert_same_round(off, on, "seed %d off screen and drawn" % rng_seed)
		assert_gt(drawn.size(), 100, "the drawn flight is shown tick by tick")
		assert_eq(on.ball_ticks, off.ball_ticks, "the same ball ticks either way")
		var timed := GuestHole.new(course, hole, 2, rng_seed, tuning, model)
		var seconds := timed.play_out(0, 1)
		_assert_same_round(off, timed, "seed %d drawn under the budget" % rng_seed)
		assert_eq(seconds, GuestHole.new(course, hole, 2, rng_seed, tuning, model).play_out(),
				"the same simulated seconds drawn or not")


func test_a_guests_ball_obeys_d29_on_unowned_land() -> void:
	# A one-parcel corridor par 4 (D30): the parcel row either side is not owned. Low-skill
	# guests shank into it; every such ball is dropped OB with a penalty and rests on owned land.
	var c := CourseData.create(80, 48, Surface.Type.FAIRWAY, 0)
	for px in 5:
		c.set_parcel_owned(Vector2i(px, 0), false)
		c.set_parcel_owned(Vector2i(px, 2), false)
	var hole := HoleData.new(1, 4, Vector2i(4, 24), Vector2i(72, 24), true)
	c.set_holes([hole])
	var field := HeightField.new(c, model.params)
	var ob := 0
	for rng_seed in range(1, 13):
		var g := GuestHole.new(c, hole, 1, rng_seed, tuning, model)
		g.play_out()
		assert_true(g.is_finished())
		for r in g.strokes:
			var rest := field.tile_at(r.rest.x, r.rest.y)
			assert_true(c.is_owned(rest.x, rest.y), "seed %d: every rest is on owned land" % rng_seed)
			if r.hazard == Ball.Hazard.OB:
				ob += 1
				assert_eq(r.penalty_strokes, 1, "OB costs a stroke")
				var hz := field.tile_at(r.hazard_position.x, r.hazard_position.y)
				assert_false(c.is_owned(hz.x, hz.y), "it stopped on unowned land")
	assert_gt(ob, 0, "some skill 1 guest went OB onto unowned land")


func test_short_chips_always_move_the_ball() -> void:
	# A chip of 5 or 10 yd plans a few % of the sand wedge; the click error must never lock 0%.
	var c := CourseData.create(60, 20, Surface.Type.FAIRWAY, 0)
	for x in range(20, 40):
		for y in range(4, 16):
			c.set_tile(x, y, 0, Surface.Type.GREEN)
	var field := HeightField.new(c, model.params)
	for back: int in [1, 2]:
		var hole := HoleData.new(1, 3, Vector2i(20 - back, 10), Vector2i(20, 10), true)
		c.set_holes([hole])
		for skill: int in [10, 1]:
			var chips := 0
			for g in 24:
				var gh := GuestHole.new(c, hole, skill, 100 * g + 7, tuning, model)
				gh.play_out()
				for r in gh.strokes:
					if field.surface_at(r.start.x, r.start.y) == Surface.Type.GREEN:
						continue
					chips += 1
					assert_gte(r.power, tuning.guest_min_power, "the floor holds")
					var moved := Vector2(r.rest.x, r.rest.y).distance_to(Vector2(r.start.x, r.start.y))
					assert_gt(moved, 0.5, "%d yd chip, skill %d: the ball moved" % [5 * back, skill])
			assert_gt(chips, 20, "chips were played")


func test_two_holes_of_one_guest_do_not_share_noise() -> void:
	var seen := {}
	for guest_seed in range(1, 40):
		for n in range(1, 10):
			var s := GuestHole.hole_seed(guest_seed, n)
			assert_false(seen.has(s), "seed %d hole %d is its own" % [guest_seed, n])
			seen[s] = true
	var course := CourseSave.load_file("res://courses/example_par3.json")
	var hole: HoleData = course.holes[0]
	var a := GuestHole.new(course, hole, 1, GuestHole.hole_seed(7, 1), tuning, model)
	var b := GuestHole.new(course, hole, 1, GuestHole.hole_seed(7, 2), tuning, model)
	for g: GuestHole in [a, b]:
		g.advance(-1)
		g.strike()
	assert_ne(a.strokes[0].power, b.strokes[0].power, "a different power error off the tee")
	assert_ne(a.strokes[0].accuracy, b.strokes[0].accuracy, "a different accuracy error")
	assert_ne(a.stroke_seed(1), b.stroke_seed(1), "different Ball seeds")


func test_a_guest_sees_when_its_hole_is_edited() -> void:
	var course := CourseSave.load_file("res://courses/example_par3.json")
	var builder := CourseBuilder.new(course)
	var g := GuestHole.new(course, course.holes[0], 5, 7, tuning, model)
	assert_true(g.hole_still_stands(), "an untouched hole stands")
	var cup := course.holes[0].cup
	assert_true(builder.place_cup(1, cup + Vector2i(0, 3)), "the builder moves the cup")
	assert_false(g.hole_still_stands(), "a moved cup is not the guest's hole")
	assert_eq(g.hole.cup, cup, "the guest's copy never changes by itself")
	assert_true(builder.undo())
	assert_true(g.hole_still_stands(), "undone, the hole is as the guest started it")
	assert_true(builder.close_hole(1))
	assert_false(g.hole_still_stands(), "a closed hole")
	assert_true(builder.undo())
	assert_true(builder.set_par(1, 4))
	assert_false(g.hole_still_stands(), "a new par")
	assert_true(builder.undo())
	assert_true(builder.renumber_hole(1, 2))
	assert_false(g.hole_still_stands(), "renumbered: no hole 1")


# --- helpers ---

func _begin(course: CourseData, at: Vector2, cup: Vector2i, driver: bool) -> GuestPlan:
	var field := HeightField.new(course, model.params)
	return GuestPlan.begin(course, field, model, tuning,
			tuning.guest_swing_tuning(SwingTuning.load_default()), at, cup, driver, 1)


func _plan(course: CourseData, at: Vector2, cup: Vector2i, driver: bool) -> GuestPlan:
	var p := _begin(course, at, cup, driver)
	p.advance(-1)
	return p


func _mean_score(course: CourseData, hole: HoleData, skill: int) -> float:
	var sum := 0
	for g in FIELD:
		var gh := GuestHole.new(course, hole, skill, 100 * g + 7, tuning, model)
		gh.play_out()
		assert_lte(gh.max_second_ticks, tuning.guest_ticks_per_s)
		sum += gh.score.total()
	return float(sum) / FIELD


func _assert_same_round(a: GuestHole, b: GuestHole, why: String) -> void:
	assert_eq(a.score.total(), b.score.total(), "%s: same score" % why)
	assert_eq(a.strokes.size(), b.strokes.size(), "%s: same strokes" % why)
	for i in mini(a.strokes.size(), b.strokes.size()):
		var x := a.strokes[i]
		var y := b.strokes[i]
		assert_eq(x.club_id, y.club_id, "%s: stroke %d club" % [why, i + 1])
		assert_eq(x.power, y.power, "%s: stroke %d power" % [why, i + 1])
		assert_eq(x.accuracy, y.accuracy, "%s: stroke %d accuracy" % [why, i + 1])
		assert_eq(x.rest, y.rest, "%s: stroke %d rest" % [why, i + 1])
		assert_eq(x.penalty_strokes, y.penalty_strokes, "%s: stroke %d penalty" % [why, i + 1])
