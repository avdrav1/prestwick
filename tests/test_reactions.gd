extends GutTest
## E3-S6: the four checks (fair, interesting, pace, challenge) per hole, as E3-S1 defined them
## (docs/design.md Guests and reactions, D39 to D43): a pass and a fail for each, the tastes,
## the verdict (pass 4 praise, fail 2 complaint naming the hole), the blind tee shot and the
## risk-reward par 5, the static checks kept per hole until the hole or its terrain changes,
## and a guest day giving one reaction per finished hole.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const NineHolesHazards := preload("res://tests/fixtures/nine_holes_hazards.gd")

var tuning: GuestTuning
var checks: HoleChecks


func before_all() -> void:
	tuning = GuestTuning.load_default()


func before_each() -> void:
	checks = HoleChecks.new(tuning)


# --- fixtures ---

## A flat New sandbox strip at height 1 (drawn top 2 yd), rough.
func _strip(w: int, h: int) -> CourseData:
	return CourseData.create(w, h, Surface.Type.ROUGH, 1)


## A column of tiles at `x`, rows `y0` to `y1`, set to `surface` at `height`.
func _column(c: CourseData, x: int, y0: int, y1: int, surface: Surface.Type, height: int) -> void:
	for y in range(y0, y1 + 1):
		c.set_tile(x, y, height, surface)


func _rect(c: CourseData, r: Rect2i, surface: Surface.Type, height: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			c.set_tile(x, y, height, surface)


func _hole(c: CourseData, number: int, par: int, tee: Vector2i, cup: Vector2i) -> HoleData:
	c.set_tile(tee.x, tee.y, c.get_height(tee.x, tee.y), Surface.Type.TEE)
	c.set_tile(cup.x, cup.y, c.get_height(cup.x, cup.y), Surface.Type.GREEN)
	var h := HoleData.new(number, par, tee, cup)
	c.set_holes([h])
	return h


func _guest(skill: int, patience: int, taste: Guest.Taste) -> Guest:
	var g := Guest.new()
	g.skill = skill
	g.patience = patience
	g.taste = taste
	return g


## `walk_s`: the walk to the tee, simulated seconds (E9-S1; -1 for none), at the base speed's
## yards.
func _record(number: int, par: int, score: int, wait_s: int = 0, walk_s: float = -1.0) -> Guest.HoleRecord:
	var r := Guest.HoleRecord.new()
	r.number = number
	r.par = par
	r.score = score
	r.wait_s = wait_s
	r.walk_s = walk_s
	r.walk_yd = walk_s * tuning.walk_yd_per_s if walk_s >= 0.0 else -1.0
	return r


## Statics with every static check passing (or as given).
func _statics(fair: bool = true, interesting: bool = true) -> HoleChecks.Statics:
	var s := HoleChecks.Statics.new()
	s.blind = not fair
	s.hazard_on_line = true
	s.safe_route = interesting
	return s


# --- fair (D43) ---

func test_fair_passes_on_a_level_hole() -> void:
	var c := _strip(40, 12)
	var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 6))
	var s := checks.measure(c, h)
	assert_false(s.target_is_zone, "a 140 yd hole aims at the cup")
	assert_false(s.blind, "nothing between eye and flag")
	assert_true(s.fair())


func test_fair_fails_behind_a_crest() -> void:
	var c := _strip(40, 12)
	var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 6))
	_column(c, 16, 0, 11, Surface.Type.ROUGH, 3)  # two steps up, mid-hole
	var s := checks.measure(c, h)
	assert_true(s.blind, "a two-step crest hides the 2 yd mark")
	assert_eq(s.blind_at.x, 16, "the crest is where the line meets ground")
	assert_false(s.fair())


func test_one_step_rise_toward_a_raised_green_still_shows_the_flag() -> void:
	# The green and the ground before it one step up: the mark stands 2 yd above it.
	var c := _strip(40, 12)
	_rect(c, Rect2i(26, 0, 14, 12), Surface.Type.ROUGH, 2)
	var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 6))
	assert_false(checks.measure(c, h).blind)


func test_trees_on_the_line_block_the_view_and_trees_beside_it_do_not() -> void:
	var c := _strip(40, 12)
	var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 6))
	_column(c, 16, 0, 2, Surface.Type.TREES, 1)
	assert_false(checks.measure(c, h).blind, "trees off the line")
	_column(c, 16, 5, 7, Surface.Type.TREES, 1)
	assert_true(checks.measure(c, h).blind, "10 yd trees on a level line")


func test_a_long_hole_aims_at_its_landing_zone() -> void:
	# 340 yd: the target is the zone centre, 240 yd out (tile 50). A ridge between the zone
	# and the cup hides the flag but not the zone; the same ridge before the zone is blind.
	var c := _strip(75, 12)
	var h := _hole(c, 1, 4, Vector2i(2, 6), Vector2i(70, 6))
	_column(c, 60, 0, 11, Surface.Type.ROUGH, 4)
	var s := checks.measure(c, h)
	assert_true(s.target_is_zone)
	assert_almost_eq(s.target.x, 50.5 * 5.0, 0.6, "the zone centre, 240 yd from the tee")
	assert_false(s.blind, "the landing area can be seen")
	_column(c, 60, 0, 11, Surface.Type.ROUGH, 1)
	_column(c, 30, 0, 11, Surface.Type.ROUGH, 4)
	assert_true(checks.measure(c, h).blind, "a ridge before the zone hides it")


## E4-S9 (D55): a dogleg's sight line runs to its turn, where guests aim their tee shots (D54),
## not to the straight line's zone inside the bend. The reaction dogleg with trees in place of
## its pond: the straight zone is behind them, the turn is in plain sight.
func test_a_dogleg_aims_its_sight_line_at_the_turn() -> void:
	var c := ReactionHoles.dogleg_par4()
	var h: HoleData = c.holes[0]
	_rect(c, ReactionHoles.DOG_POND, Surface.Type.TREES, ReactionHoles.GROUND)
	var turn: Variant = CourseValidator.new().turn_point(c, h)
	assert_not_null(turn, "the hole turns")
	var s := checks.measure(c, h)
	assert_true(s.target_is_zone, "the landing area, not the flag")
	assert_eq(s.turn, turn)
	assert_almost_eq(s.target.distance_to(((turn as Vector2) + Vector2(0.5, 0.5)) * 5.0), 0.0, 0.01,
			"the target is the turn's centre")
	assert_false(s.blind, "the turn is seen down the first leg; the trees inside the bend do not count")
	_column(c, 30, 3, 9, Surface.Type.TREES, ReactionHoles.GROUND)
	assert_true(checks.measure(c, h).blind, "trees across the first leg hide the turn")


## D55: a fairway edit measures a hole's statics again only when it moves the turn.
func test_a_fairway_edit_measures_again_only_when_it_moves_the_turn() -> void:
	var c := ReactionHoles.dogleg_par4()
	var h: HoleData = c.holes[0]
	_rect(c, ReactionHoles.DOG_POND, Surface.Type.TREES, ReactionHoles.GROUND)
	var first := checks.statics(c, h)
	assert_false(first.blind)
	assert_eq(checks.measured, 1)
	c.set_tile(68, 58, ReactionHoles.GROUND, Surface.Type.FAIRWAY)
	assert_same(checks.statics(c, h), first, "fairway far from the corner keeps the turn and the statics")
	assert_eq(checks.measured, 1)
	# The corner painted out: the turn moves down the second leg and is measured again.
	_rect(c, Rect2i(40, 3, 19, 7), Surface.Type.ROUGH, ReactionHoles.GROUND)
	var moved := checks.statics(c, h)
	assert_eq(checks.measured, 2, "a moved turn measures again")
	assert_ne(moved.turn, first.turn)
	assert_eq(moved.turn, CourseValidator.new().turn_point(c, h))


## D55: the line is judged against the drawn ground (HeightField.drawn_steps, D50), not tile
## tops. A five-step tower beside the line's tiles never stands on one, so on terraces it hid
## nothing; the smooth ground rising toward it from the next tile does hide the flag.
func test_the_sight_line_reads_the_drawn_ground() -> void:
	var c := _strip(40, 12)
	var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 7))
	assert_false(checks.measure(c, h).blind, "level ground")
	c.set_tile(15, 7, 6, Surface.Type.ROUGH)
	var s := checks.measure(c, h)
	assert_true(s.blind, "the slope up to the tower crosses the line")
	assert_eq(s.blind_at.y, 6, "where the line meets it, on the row beside the tower")


# --- interesting ---

func test_interesting_fails_with_nothing_on_the_line() -> void:
	var c := _strip(40, 12)
	var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 6))
	_column(c, 16, 0, 2, Surface.Type.BUNKER, 1)  # a bunker off the line
	var s := checks.measure(c, h)
	assert_false(s.hazard_on_line)
	assert_false(s.interesting())


func test_interesting_passes_with_a_hazard_on_the_line_and_a_way_round() -> void:
	for surface: Surface.Type in [Surface.Type.WATER, Surface.Type.BUNKER, Surface.Type.TREES]:
		var c := _strip(40, 12)
		var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 6))
		_rect(c, Rect2i(14, 4, 4, 5), surface, 1)
		var s := checks.measure(c, h)
		assert_true(s.hazard_on_line, Surface.name_of(surface))
		assert_true(s.safe_route, "round the %s" % Surface.name_of(surface))
		assert_true(s.interesting())


func test_interesting_fails_with_no_way_round() -> void:
	# A wall of trees across the whole map: rule 3 passes (trees can be crossed), but every
	# route crosses the hazard.
	var c := _strip(40, 12)
	var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 6))
	_column(c, 16, 0, 11, Surface.Type.TREES, 1)
	var s := checks.measure(c, h)
	assert_true(s.hazard_on_line)
	assert_false(s.safe_route)
	assert_false(s.interesting())


func test_unowned_land_on_the_line_is_a_hazard() -> void:
	var c := _strip(48, 40)
	c.set_parcel_owned(Vector2i(1, 0), false)  # tiles x 16 to 31, y 0 to 15
	var h := _hole(c, 1, 4, Vector2i(2, 6), Vector2i(45, 6))
	var s := checks.measure(c, h)
	assert_true(s.hazard_on_line, "the line crosses the unowned parcel")
	assert_true(s.safe_route, "round it through the owned parcel south")


func test_the_line_walk_is_rule_3s() -> void:
	var walk := HoleChecks.line_walk(Vector2i(2, 3), Vector2i(9, 7))
	assert_eq(walk[0], Vector2i(2, 3))
	assert_eq(walk[-1], Vector2i(9, 7))
	assert_eq(walk.size(), 7 + 4 + 1, "4-connected: one tile per step")
	for i in range(1, walk.size()):
		assert_eq(absi(walk[i].x - walk[i - 1].x) + absi(walk[i].y - walk[i - 1].y), 1)


# --- pace ---

func test_pace_passes_within_the_wait_limit_and_fails_over_it() -> void:
	for patience: int in [1, 5, 10]:
		var limit := tuning.wait_base_s + tuning.wait_per_patience_s * patience
		assert_true(GuestReaction.pace_passes(_record(1, 4, 4, int(limit)), patience, tuning),
				"patience %d waits %d s" % [patience, limit])
		assert_false(GuestReaction.pace_passes(_record(1, 4, 4, int(limit) + 1), patience, tuning))


func test_pace_fails_on_a_long_walk_from_the_last_green() -> void:
	# E9-S1 (D65): the walk is judged by its time, not its yards.
	var patience := 3
	var limit := tuning.walk_base_s + tuning.walk_per_patience_s * patience
	assert_true(GuestReaction.pace_passes(_record(2, 4, 4, 0, limit), patience, tuning))
	assert_false(GuestReaction.pace_passes(_record(2, 4, 4, 0, limit + 0.1), patience, tuning))
	assert_true(GuestReaction.pace_passes(_record(1, 4, 4, 0, -1.0), patience, tuning),
			"a first hole has no walk")


# --- challenge (D40) ---

func test_challenge_passes_within_two_of_the_expected_score() -> void:
	var within := int(tuning.challenge_within)
	# Skill 10 expects par; skill 1 expects par + 2.
	for skill: int in [tuning.skill_max, tuning.skill_min]:
		var expected := roundi(tuning.expected_score(4, skill))
		for score: int in [expected - within, expected, expected + within]:
			assert_true(GuestReaction.challenge_passes(_record(1, 4, score), skill,
					Guest.Taste.PURIST, tuning), "skill %d scores %d" % [skill, score])
		for score: int in [expected - within - 1, expected + within + 1]:
			assert_false(GuestReaction.challenge_passes(_record(1, 4, score), skill,
					Guest.Taste.PURIST, tuning), "skill %d scores %d" % [skill, score])


func test_a_casual_guest_takes_a_wider_band() -> void:
	var wide := int(tuning.casual_challenge_within)
	assert_gt(tuning.casual_challenge_within, tuning.challenge_within)
	var r := _record(1, 4, 4 + wide)
	assert_true(GuestReaction.challenge_passes(r, 10, Guest.Taste.CASUAL, tuning))
	assert_false(GuestReaction.challenge_passes(r, 10, Guest.Taste.ADVENTURER, tuning))
	assert_false(GuestReaction.challenge_passes(_record(1, 4, 5 + wide), 10, Guest.Taste.CASUAL, tuning))


# --- the verdict (D39) and tastes (D42) ---

func test_four_passes_give_praise_naming_the_hole() -> void:
	var r := GuestReaction.judge(_guest(10, 5, Guest.Taste.CASUAL), _record(6, 4, 4), _statics(), tuning)
	assert_eq(r.kind, GuestReaction.Kind.PRAISE)
	assert_eq(r.failed().size(), 0)
	assert_eq(r.hole_number, 6)
	assert_string_starts_with(r.text, "Hole 6:")


func test_one_fail_is_neutral_and_two_a_complaint() -> void:
	var guest := _guest(10, 5, Guest.Taste.CASUAL)
	var slow := _record(4, 4, 4, 60)
	var r1 := GuestReaction.judge(guest, slow, _statics(), tuning)
	assert_eq(r1.kind, GuestReaction.Kind.NEUTRAL, "one fail")
	assert_eq(r1.failed(), PackedStringArray(["pace"]))
	var slow_hard := _record(4, 4, 9, 60)
	var r2 := GuestReaction.judge(guest, slow_hard, _statics(), tuning)
	assert_eq(r2.kind, GuestReaction.Kind.COMPLAINT, "two fails")
	assert_eq(r2.fail_weight, 2)
	assert_string_starts_with(r2.text, "Hole 4:")
	assert_string_contains(r2.text, "slow")
	assert_string_contains(r2.text, "too hard")


func test_a_purist_complains_about_blind_alone_and_others_do_not() -> void:
	var blind := _statics(false, true)
	var rec := _record(3, 3, 3)
	var purist := GuestReaction.judge(_guest(10, 5, Guest.Taste.PURIST), rec, blind, tuning)
	assert_eq(purist.kind, GuestReaction.Kind.COMPLAINT, "fair counts double")
	assert_eq(purist.fail_weight, tuning.doubled_check_weight)
	assert_string_contains(purist.text, "I hate blind shots")
	for taste: Guest.Taste in [Guest.Taste.ADVENTURER, Guest.Taste.CASUAL]:
		var r := GuestReaction.judge(_guest(10, 5, taste), rec, blind, tuning)
		assert_eq(r.kind, GuestReaction.Kind.NEUTRAL, Guest.TASTE_NAMES[taste])


func test_an_adventurer_complains_about_a_dull_hole_alone() -> void:
	var dull := _statics(true, false)
	var rec := _record(2, 4, 4)
	var r := GuestReaction.judge(_guest(10, 5, Guest.Taste.ADVENTURER), rec, dull, tuning)
	assert_eq(r.kind, GuestReaction.Kind.COMPLAINT, "interesting counts double")
	assert_eq(GuestReaction.judge(_guest(10, 5, Guest.Taste.PURIST), rec, dull, tuning).kind,
			GuestReaction.Kind.NEUTRAL)


## The feed line leads with the reason that matters (the taste's doubled check, else the
## first failed one) and keeps the rest short, so four fails stay one readable line.
func test_a_four_fail_line_leads_with_the_taste_and_stays_short() -> void:
	var s := _statics(false, false)
	s.hazard_on_line = false
	s.target_is_zone = true
	var rec := _record(1, 4, 9, 47)
	var purist := GuestReaction.judge(_guest(10, 1, Guest.Taste.PURIST), rec, s, tuning)
	assert_eq(purist.failed().size(), 4)
	assert_eq(purist.lead_check(), GuestReaction.Check.FAIR)
	assert_eq(purist.text, "Hole 1: blind from the tee, could not see the landing area. "
			+ "I hate blind shots. Also dull, slow (47 s wait) and too hard (9 on a par 4).")
	assert_lt(purist.text.length(), 140)
	var adv := GuestReaction.judge(_guest(10, 1, Guest.Taste.ADVENTURER), rec, s, tuning)
	assert_eq(adv.lead_check(), GuestReaction.Check.INTERESTING)
	assert_string_starts_with(adv.text, "Hole 1: nothing in the way, nothing to think about. "
			+ "I want risk and reward. Also blind, slow")
	assert_lt(adv.text.length(), 140)
	assert_eq(adv.text.count("risk and reward"), 1)
	var casual := GuestReaction.judge(_guest(10, 1, Guest.Taste.CASUAL), rec, s, tuning)
	assert_eq(casual.lead_check(), GuestReaction.Check.FAIR, "no taste: the first failed check")
	assert_false(casual.text.contains("I hate"), "no taste line without a doubled check")
	assert_lt(casual.text.length(), 140)


func test_a_neutral_line_names_its_one_fail() -> void:
	var r := GuestReaction.judge(_guest(10, 5, Guest.Taste.CASUAL), _record(4, 4, 4, 60), _statics(), tuning)
	assert_eq(r.text, "Hole 4: fine, but slow, waited 60 s.")


func test_a_casual_guest_shrugs_off_one_more_stroke() -> void:
	var rec := _record(5, 4, 4 + int(tuning.casual_challenge_within))
	assert_eq(GuestReaction.judge(_guest(10, 5, Guest.Taste.CASUAL), rec, _statics(), tuning).kind,
			GuestReaction.Kind.PRAISE)
	assert_eq(GuestReaction.judge(_guest(10, 5, Guest.Taste.PURIST), rec, _statics(), tuning).kind,
			GuestReaction.Kind.NEUTRAL)


# --- the design doc's two holes ---

## The blind tee shot: a par 3 over a two-step crest, with a bunker on the line and a way
## round it (so only fair fails). Purists complain, naming the hole and the blind shot.
func test_the_blind_tee_shot() -> void:
	var c := _strip(40, 12)
	var h := _hole(c, 7, 3, Vector2i(2, 6), Vector2i(30, 6))
	_column(c, 14, 0, 11, Surface.Type.ROUGH, 3)
	c.set_tile(22, 6, 1, Surface.Type.BUNKER)
	var s := checks.statics(c, h)
	assert_true(s.blind)
	assert_true(s.interesting())
	var rec := _record(7, 3, 3)
	var purist := GuestReaction.judge(_guest(10, 8, Guest.Taste.PURIST), rec, s, tuning)
	assert_eq(purist.kind, GuestReaction.Kind.COMPLAINT)
	assert_string_starts_with(purist.text, "Hole 7:")
	assert_string_contains(purist.text, "blind")
	assert_eq(GuestReaction.judge(_guest(10, 8, Guest.Taste.CASUAL), rec, s, tuning).kind,
			GuestReaction.Kind.NEUTRAL)
	# Level the crest and the same guest praises it.
	_column(c, 14, 0, 11, Surface.Type.ROUGH, 1)
	var level := checks.statics(c, h)
	assert_false(level.blind)
	assert_eq(GuestReaction.judge(_guest(10, 8, Guest.Taste.PURIST), rec, level, tuning).kind,
			GuestReaction.Kind.PRAISE)


## The risk-reward par 5: 500 yd, a pond across the line short of the green with fairway
## round it. Fair and interesting pass; a guest at its expected score, unhurried, praises it.
## The same hole with the pond filled in is dull: an Adventurer complains.
func test_the_risk_reward_par_5() -> void:
	var c := CourseData.create(110, 30, Surface.Type.FAIRWAY, 1)
	var h := _hole(c, 8, 5, Vector2i(4, 15), Vector2i(104, 15))
	_rect(c, Rect2i(88, 10, 8, 11), Surface.Type.WATER, 1)
	var issues := CourseValidator.new().check_hole(c, h)
	assert_eq(issues.size(), 0, "a legal par 5: %s" % [issues])
	var s := checks.statics(c, h)
	assert_true(s.target_is_zone)
	assert_true(s.fair())
	assert_true(s.hazard_on_line)
	assert_true(s.safe_route)
	for taste: Guest.Taste in [Guest.Taste.PURIST, Guest.Taste.ADVENTURER, Guest.Taste.CASUAL]:
		var g := _guest(7, 5, taste)
		var r := GuestReaction.judge(g, _record(8, 5, roundi(tuning.expected_score(5, 7)), 2, 2.0), s, tuning)
		assert_eq(r.kind, GuestReaction.Kind.PRAISE, Guest.TASTE_NAMES[taste])
	_rect(c, Rect2i(88, 10, 8, 11), Surface.Type.FAIRWAY, 1)
	var dull := checks.statics(c, h)
	assert_false(dull.interesting())
	var adv := GuestReaction.judge(_guest(7, 5, Guest.Taste.ADVENTURER),
			_record(8, 5, 6, 2, 2.0), dull, tuning)
	assert_eq(adv.kind, GuestReaction.Kind.COMPLAINT)
	assert_string_starts_with(adv.text, "Hole 8:")


# --- the nine-hole fixtures (E3-S23) ---

## nine_holes.gd as built: its fairways paint over any pond, so every line is bare (interesting
## fails), and hole 1 is blind behind its crest (D43); the other eight are seen from the tee.
func test_nine_holes_is_bare_with_hole_1_blind() -> void:
	var c: CourseData = NineHoles.land(7)
	var opened: Array[int] = NineHoles.build(CourseBuilder.new(c))
	assert_eq(opened.size(), 9)
	for h: HoleData in c.holes:
		var s := checks.statics(c, h)
		assert_eq(s.fair(), h.number != 1, "hole %d fair" % h.number)
		assert_false(s.hazard_on_line, "hole %d bare" % h.number)
		assert_false(s.interesting(), "hole %d not interesting" % h.number)


## nine_holes_hazards.gd: the same nine holes, all open, each seen from the tee (hole 1's crest
## cut) and interesting: its bunker on the line, the fairway's outer rows round it.
func test_nine_holes_hazards_holes_are_fair_and_interesting() -> void:
	var c: CourseData = NineHolesHazards.land(7)
	var b := CourseBuilder.new(c)
	var opened: Array[int] = NineHolesHazards.build(b)
	assert_eq(opened, [1, 2, 3, 4, 5, 6, 7, 8, 9] as Array[int])
	assert_eq(c.holes.size(), NineHoles.HOLES.size())
	for k: int in NineHoles.HOLES.size():
		var spec: Array = NineHoles.HOLES[k]
		var h: HoleData = b.hole(spec[0])
		assert_eq([h.par, h.tee, h.cup], [spec[1], spec[2], spec[3]], "hole %d as nine_holes'" % h.number)
		var s := checks.statics(c, h)
		assert_true(s.fair(), "hole %d seen from the tee (blind at %s)" % [h.number, s.blind_at])
		assert_true(s.hazard_on_line, "hole %d has a hazard on its line" % h.number)
		assert_true(s.safe_route, "hole %d has a way round" % h.number)
		assert_true(s.interesting(), "hole %d interesting" % h.number)
		for cell: Vector2i in NineHolesHazards.bunker_cells(b.validator, h.number, h.par, h.tee, h.cup):
			assert_eq(c.get_surface(cell.x, cell.y), Surface.Type.BUNKER, "hole %d bunker" % h.number)
			for side: int in [-1, 1]:
				assert_eq(c.get_surface(cell.x, cell.y + side), Surface.Type.FAIRWAY,
						"hole %d fairway round its bunker" % h.number)
	assert_eq(b.issues_for(1).size(), 0, "hole 1 legal with its crest cut")


# --- the static checks' cache ---

func test_statics_are_measured_once_per_hole_until_it_or_the_terrain_changes() -> void:
	var c := _strip(40, 12)
	var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 6))
	var first := checks.statics(c, h)
	assert_eq(checks.measured, 1)
	assert_same(checks.statics(c, h), first, "kept")
	assert_same(checks.statics(c, h.copy()), first, "a copy of the hole is the same hole")
	assert_eq(checks.measured, 1)
	_column(c, 16, 0, 11, Surface.Type.ROUGH, 3)
	var after := checks.statics(c, h)
	assert_eq(checks.measured, 2, "a terrain edit measures again")
	assert_true(after.blind)
	var moved := HoleData.new(1, 3, Vector2i(2, 6), Vector2i(12, 6))
	assert_false(checks.statics(c, moved).blind, "a moved cup is measured afresh")
	assert_eq(checks.measured, 3)
	c.set_parcel_owned(Vector2i(0, 0), false)
	checks.statics(c, moved)
	assert_eq(checks.measured, 4, "a land change measures again")


## E3-S74: the statics read the heights, the hazard surfaces (trees block the sight line too)
## and owned land, so an edit that changes none of them keeps every hole's statics, and one
## that changes any of them measures them again.
func test_statics_are_kept_through_an_edit_that_changes_no_hazard_height_or_land() -> void:
	var c := _strip(40, 12)
	var h := _hole(c, 1, 3, Vector2i(2, 6), Vector2i(30, 6))
	c.set_tile(22, 6, 1, Surface.Type.BUNKER)
	var first := checks.statics(c, h)
	assert_true(first.interesting())
	assert_eq(checks.measured, 1)
	_column(c, 10, 0, 11, Surface.Type.FAIRWAY, 1)
	assert_same(checks.statics(c, h), first, "fairway painted over rough on the line keeps them")
	c.set_tile(22, 6, 1, Surface.Type.BUNKER)
	c.set_parcel_owned(Vector2i(0, 0), true)
	assert_same(checks.statics(c, h), first, "rewriting a bunker or owned land keeps them")
	_column(c, 10, 0, 11, Surface.Type.CART_PATH, 1)
	assert_same(checks.statics(c, h), first, "cart path over fairway keeps them")
	assert_eq(checks.measured, 1)
	c.set_tile(22, 6, 1, Surface.Type.TREES)
	var trees := checks.statics(c, h)
	assert_eq(checks.measured, 2, "one hazard for another measures again")
	assert_true(trees.hazard_on_line)
	c.set_tile(22, 6, 1, Surface.Type.ROUGH)
	assert_false(checks.statics(c, h).hazard_on_line, "the hazard gone, measured again")
	assert_eq(checks.measured, 3)
	c.set_tile(15, 6, 3, Surface.Type.ROUGH)
	checks.statics(c, h)
	assert_eq(checks.measured, 4, "a height edit measures again")
	c.set_parcel_owned(Vector2i(1, 0), false)
	checks.statics(c, h)
	assert_eq(checks.measured, 5, "a land change measures again")
	assert_not_null(checks.statics(c.copy(), h))
	assert_eq(checks.measured, 6, "another course is measured afresh")


# --- a guest day ---

func test_every_finished_hole_gives_one_reaction_naming_it() -> void:
	var brain := GuestBrain.new(GuestCourse.course(), 3, tuning)
	var heard: Array[GuestReaction] = []
	brain.reacted.connect(func(_g: Guest, r: GuestReaction) -> void: heard.append(r))
	brain.run_day()
	var records := 0
	var kinds := {}
	for g: Guest in brain.guests:
		for r: Guest.HoleRecord in g.records:
			records += 1
			assert_not_null(r.reaction)
			assert_eq(r.reaction.hole_number, r.number)
			assert_eq(r.reaction.guest_id, g.id)
			assert_string_starts_with(r.reaction.text, "Hole %d:" % r.number)
			kinds[r.reaction.kind] = true
	assert_gt(records, 0)
	assert_eq(heard.size(), records, "one reaction per finished hole")
	assert_lte(brain.checks.measured, GuestCourse.HOLES.size(), "statics once per hole")
	# The fixture's holes are flat and bare: nothing on the line, so interesting fails.
	for r: GuestReaction in heard:
		assert_false(r.passed[GuestReaction.Check.INTERESTING])
		assert_true(r.passed[GuestReaction.Check.FAIR])
	var again := GuestBrain.new(GuestCourse.course(), 3, tuning)
	var second: Array[String] = []
	again.reacted.connect(func(_g: Guest, r: GuestReaction) -> void: second.append(r.text))
	again.run_day()
	var first: Array[String] = []
	for r: GuestReaction in heard:
		first.append(r.text)
	assert_eq(second, first, "the same seed gives the same reactions")
