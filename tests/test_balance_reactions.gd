extends GutTest
## E3-S8: /balance reactions (scripts/reaction_field.gd, ReactionField.measure). A field
## of guests drawn as the day draws them plays one hole through GuestBrain, day after day, and
## its reactions are read against docs/design.md Balance targets, reactions: a fair par 4
## gets 60 to 75% praise and under 15% complaints, and a blind one clearly worse. The fixture
## holes are tests/fixtures/reaction_holes.gd. The full field of 50 (and the nine-hole day)
## is the sim's run (`--table reactions --runs 50`); here a smaller field checks the rows.
## E3-S48: every field, nine-hole day and edges job the tests read is run once, in before_all,
## WORKERS at a time in their own Godots (ReactionField.run_jobs), as the sim runs them, and
## each test reads its results (`_result`); the figures are the same as one at a time.

const SEED: int = 1
## Guests in the field here; the target's field is FIELD_TARGET.
const SMALL: int = 12
## E3-S48: before_all's jobs run this many at once.
const WORKERS: int = 8
## The edges tests' guests a job.
const EDGE_FIELD: int = 12
const PUTT_FIELD: int = 16

var sim: ReactionField
## {ReactionField.job_key: result} of before_all's batch.
var batch: Dictionary = {}


func before_all() -> void:
	sim = ReactionField.new()
	var jobs: Array[Dictionary] = []
	jobs.append_array(_rows_jobs())
	for course_name: String in ["fair", "blind"]:
		jobs.append(_fifty(course_name))
	jobs.append_array(ScoringEdges.new(sim.model).jobs(1, SEED))
	jobs.append_array(_skill_10_jobs())
	jobs.append_array(_putt_jobs())
	for skill: int in [10, 1]:
		jobs.append(_chips(skill))
	var results := sim.run_jobs(jobs, WORKERS)
	for i: int in jobs.size():
		batch[ReactionField.job_key(jobs[i])] = results[i]


func _result(job: Dictionary) -> Dictionary:
	return batch[ReactionField.job_key(job)]


## The jobs of the rows test's measure: a field of SMALL, one nine-hole day, no edges.
func _rows_jobs() -> Array[Dictionary]:
	return sim.jobs_for(SMALL, SEED, 1, 1, false, SMALL)


func _fifty(course_name: String) -> Dictionary:
	var n := ReactionField.FIELD_TARGET
	return {"kind": "field", "course": course_name, "n": n, "seed": SEED, "cuts": [n]}


func _skill_10_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hole_name: String in ScoringEdges.SPIKE_HOLES:
		out.append({"kind": "edge_hole", "hole": hole_name, "skill": 10, "n": EDGE_FIELD, "seed": SEED})
	return out


func _putts(green_name: String, skill: int) -> Dictionary:
	return {"kind": "edge_putts", "green": green_name, "skill": skill, "n": PUTT_FIELD, "seed": SEED}


func _putt_jobs() -> Array[Dictionary]:
	return [_putts("flat green", ScoringEdges.NOISE_FREE), _putts("sloped green", ScoringEdges.NOISE_FREE),
			_putts("tier green", ScoringEdges.NOISE_FREE), _putts("sloped green", 1)]


func _chips(skill: int) -> Dictionary:
	return {"kind": "edge_chips", "skill": skill, "n": EDGE_FIELD, "seed": SEED}


func _named(rows: Array[Dictionary], prefix: String) -> Dictionary:
	for r in rows:
		if String(r.name).begins_with(prefix):
			return r
	return {}


func test_the_fixture_holes_are_open_and_their_statics_are_as_named() -> void:
	var checks := HoleChecks.new()
	var fair := ReactionHoles.fair_par4()
	assert_eq(fair.holes.size(), 1)
	assert_true(fair.holes[0].open, "the fair par 4 passes every rule")
	assert_eq(fair.holes[0].par, 4)
	var s := checks.statics(fair, fair.holes[0])
	assert_true(s.fair(), "seen from the tee")
	assert_true(s.interesting(), "a hazard on the line and a way round")
	var blind := ReactionHoles.blind_par4()
	assert_true(blind.holes[0].open)
	var b := checks.statics(blind, blind.holes[0])
	assert_true(b.blind, "the ridge hides the landing zone")
	assert_true(b.interesting(), "and only fair changes")
	var dog := ReactionHoles.dogleg_par4()
	assert_true(dog.holes[0].open, "rule 4 makes the dogleg a par 4 by its straight line")
	assert_true(checks.statics(dog, dog.holes[0]).interesting(), "the pond in the corner is on the line")
	var corridor := ReactionHoles.corridor_par4(SEED)
	assert_not_null(corridor, "the corridor par 4 opens on land seed %d" % SEED)
	if corridor != null:
		var owned := 0
		for q: int in corridor.parcels_high:
			for p: int in corridor.parcels_wide:
				if corridor.is_parcel_owned(Vector2i(p, q)):
					owned += 1
		assert_eq(owned, corridor.parcels_wide, "one parcel row owned: an 80 yd corridor")


func test_a_field_plays_the_hole_through_the_guest_day() -> void:
	var c := ReactionHoles.fair_par4()
	var field := sim.play_field(c, SMALL, SEED)
	assert_eq(field.size(), SMALL, "the first %d hole records" % SMALL)
	var ids := {}
	for e: Dictionary in field:
		var g: Guest = e.guest
		var r: Guest.HoleRecord = e.record
		assert_eq(r.number, 1)
		assert_not_null(r.reaction, "every record has its reaction")
		ids[Vector2i(e.day, g.id)] = true
	assert_eq(ids.size(), SMALL, "one record a guest")
	var again := sim.play_field(ReactionHoles.fair_par4(), SMALL, SEED)
	for i in SMALL:
		var a: Guest.HoleRecord = field[i].record
		var b: Guest.HoleRecord = again[i].record
		assert_eq([a.score, a.wait_s, a.reaction.kind], [b.score, b.wait_s, b.reaction.kind],
				"the same seed gives the same field")


func test_reaction_rows_print_next_to_their_targets() -> void:
	var jobs := _rows_jobs()
	var results: Array[Dictionary] = []
	for job: Dictionary in jobs:
		results.append(_result(job))
	var rows := sim.rows_from(SMALL, SEED, 1, 1, false, SMALL, jobs, results)
	for prefix: String in ["fair par 4: praise", "fair par 4: complaints",
			"blind par 4: praise", "blind par 4: complaints",
			"corridor par 4", "dogleg par 4", "nine holes", "pace fails: fair par 4",
			"crossing holes"]:
		assert_false(_named(rows, prefix).is_empty(), "a row for %s" % prefix)
	# E3-S22: pace on the first tee, the par 5 and the dogleg, each against the fair par 4's.
	for prefix: String in ["pace fails: first tee", "pace fails: par 5", "pace fails: dogleg"]:
		var r := _named(rows, prefix)
		assert_false(r.is_empty(), "a row for %s" % prefix)
		assert_eq(r.target, Vector2(-ReactionField.PACE_SPREAD, ReactionField.PACE_SPREAD),
				"%s: within 10 points of the fair par 4" % prefix)
	# E3-S22 review: the fixture's other par 5 (hole 8) was recorded; E3-S37 gives it the
	# same 10 points (next_tee_queue_max spaces the groups bunched after par 3 hole 7).
	var other := _named(rows, "pace fails: other par 5")
	assert_false(other.is_empty(), "a row for the other par 5")
	assert_eq(other.target, Vector2(-ReactionField.PACE_SPREAD, ReactionField.PACE_SPREAD),
			"the other par 5: within 10 points of the fair par 4")
	var praise := _named(rows, "fair par 4: praise")
	assert_eq(praise.target, ReactionField.FAIR_PRAISE, "praise is read against 60 to 75%")
	var blind := _named(rows, "blind par 4: praise")
	assert_lte(float(blind.measured), float(praise.measured) * 0.5 + 1e-6,
			"a blind hole clearly scores worse")
	var nine := _named(rows, "nine holes, New sandbox: days reaching every hole")
	assert_true(nine.ok, "the nine-hole day reaches every hole: %s" % nine.note)
	# E3-S48: the nine-hole field plays the holes that can be praised; pace stays on the bare nine.
	assert_string_starts_with(String(nine.note), "nine_holes_hazards.gd:")
	var finished := _named(rows, "nine holes, New sandbox: days every hole was finished")
	assert_string_contains(String(finished.note), "praise")
	assert_string_contains(String(_named(rows, "pace fails: par 5").note), "pace fails by hole")


func test_the_fair_par_4_hits_its_target_with_a_field_of_50() -> void:
	var n := ReactionField.FIELD_TARGET
	var tally: Dictionary = _result(_fifty("fair"))[str(n)]
	var blind: Dictionary = _result(_fifty("blind"))[str(n)]
	assert_between(float(tally.praise), ReactionField.FAIR_PRAISE.x, ReactionField.FAIR_PRAISE.y,
			"praise share of %d guests" % ReactionField.FIELD_TARGET)
	assert_lt(float(tally.complaints), ReactionField.FAIR_COMPLAINTS.y + 1e-6, "complaints under 15%")
	assert_eq(float(blind.praise), 0.0, "nobody praises a blind hole")
	assert_gt(float(blind.complaints), float(tally.complaints) + 0.25, "and many more complain")


## E3-S48: jobs run in their own Godots give the very results they give run here, so the
## parallel sim prints the same figures: two of before_all's jobs (a field cut at two sizes,
## a breaking putt's share) run again here.
func test_jobs_run_in_parallel_give_the_same_results_as_run_here() -> void:
	var jobs: Array[Dictionary] = []
	for job: Dictionary in _rows_jobs():
		if String(job.kind) == "field" and String(job.course) == "corridor":
			jobs.append(job)
	jobs.append(_putts("sloped green", 1))
	assert_eq(jobs.size(), 2)
	var here := sim.run_jobs(jobs, 1)
	var apart: Array[Dictionary] = []
	for job: Dictionary in jobs:
		apart.append(_result(job))
	for i: int in jobs.size():
		# JSON keeps numbers as floats: compare both as JSON gives them back.
		var mine: Variant = JSON.parse_string(JSON.stringify(here[i], "", true, true))
		assert_eq(JSON.stringify(apart[i], "", true, true), JSON.stringify(mine, "", true, true),
				"job %s" % ReactionField.job_key(jobs[i]))


# --- E3-S24: scoring at the edges (scripts/scoring_edges.gd) ---

func test_the_edge_rows_print_and_only_the_spike_mean_has_a_target() -> void:
	var edges := ScoringEdges.new(sim.model)
	var results: Array[Dictionary] = []
	for job: Dictionary in edges.jobs(1, SEED):
		results.append(_result(job))
	var rows := edges.rows_from(1, SEED, results)
	var prefixes: Array[String] = []
	for hole_name: String in ScoringEdges.spike_holes():
		prefixes.append("skill 10 on %s:" % hole_name)
	prefixes.append_array(["skill 10 on the spike holes", "sloped green: three-putt",
			"tier green: three-putt", "flat green: three-putt", "chips, flat green"])
	for prefix: String in prefixes:
		assert_false(_named(rows, prefix).is_empty(), "a row for %s" % prefix)
	assert_eq(rows.size(), prefixes.size(), "one row each")
	var mean := _named(rows, "skill 10 on the spike holes")
	assert_eq(mean.target, Vector2(-ScoringEdges.SKILL_10_WITHIN, ScoringEdges.SKILL_10_WITHIN),
			"skill 10 is read against par, within 0.25")
	for r: Dictionary in rows:
		if r != mean:
			assert_eq(r.target, Vector2(-INF, INF), "%s is recorded" % r.name)
	assert_string_contains(String(_named(rows, "sloped green").note), "skill 1:")
	assert_string_contains(String(_named(rows, "chips").note), "guest_min_power")


func test_the_short_game_greens_are_shaped_as_named() -> void:
	var c := ShortGameHoles.CUP
	var h := ShortGameHoles.GREEN_HALF
	var sloped := ShortGameHoles.sloped_green()
	for x in range(c.x - h, c.x + h + 1):
		assert_eq(sloped.get_surface(x, c.y), Surface.Type.GREEN)
		assert_eq(sloped.get_height(x, c.y), x - (c.x - h), "one step a tile along +x")
	var tier := ShortGameHoles.tier_green()
	assert_eq(tier.get_height(c.x - 1, c.y), 0)
	assert_eq(tier.get_height(c.x, c.y), 1, "the cup on the upper tier")
	assert_eq(ShortGameHoles.flat_green().get_height(c.x + h, c.y), 0)
	assert_eq(sloped.get_surface(c.x - h - 1, c.y), Surface.Type.FAIRWAY, "fairway round the green")
	var starts := ShortGameHoles.putt_starts()
	assert_eq(starts.size(), 16, "eight directions at two distances")
	for s: Vector2i in starts:
		assert_eq(sloped.get_surface(s.x, s.y), Surface.Type.GREEN, "%s is a putt" % s)
	assert_eq(sloped.get_surface(ShortGameHoles.chip_start(1).x, c.y), Surface.Type.FAIRWAY)


func test_a_noise_free_guest_one_putts_a_flat_green_and_never_three_putts_a_sloped_one() -> void:
	var flat := _result(_putts("flat green", ScoringEdges.NOISE_FREE))
	assert_eq(float(flat.one), 1.0, "with no noise every straight putt drops")
	for green_name: String in ["sloped green", "tier green"]:
		var p := _result(_putts(green_name, ScoringEdges.NOISE_FREE))
		assert_eq(float(p.three), 0.0, "no three-putts with no noise")
		assert_gt(float(p.two), 0.0, "aimed at the cup, some breaking putts miss (D41)")
	var noisy := _result(_putts("sloped green", 1))
	assert_gt(float(noisy.three), float(flat.three), "skill 1 three-putts the sloped green")


func test_chips_hole_out_and_skill_10_gets_down_in_fewer() -> void:
	var best := _result(_chips(10))
	var worst := _result(_chips(1))
	gut.p("chips: skill 10 %.2f, skill 1 %.2f" % [best.mean, worst.mean])
	assert_between(float(best.mean), 2.0, 3.5, "skill 10 about up and down")
	assert_gt(float(worst.mean), float(best.mean), "skill 1 takes more")


func test_skill_10_averages_near_par_over_the_spike_holes() -> void:
	# The sim reads the target at 50 guests a hole; a field of 12 is looser.
	var jobs := _skill_10_jobs()
	var sum := 0.0
	for job: Dictionary in jobs:
		var m := _result(job)
		gut.p("skill 10 on %s: %+.2f" % [job.hole, m.over])
		sum += float(m.over)
	assert_almost_eq(sum / jobs.size(), 0.0, ScoringEdges.SKILL_10_WITHIN + 0.15,
			"skill 10 averages about par (D40)")
