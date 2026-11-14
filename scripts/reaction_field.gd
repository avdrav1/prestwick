class_name ReactionField
extends RefCounted
## E3-S8: the /balance reactions measurements (scripts/balance_sim.gd's measure_reactions,
## scripts/sim.gd --table reactions; docs/design.md Balance targets, reactions). A field of
## guests drawn as the day draws them plays a fixture hole (tests/fixtures/reaction_holes.gd)
## through GuestBrain day after day, as Play runs it, and its reactions are counted. Rows are
## BalanceSim's: {name, measured, target, ok, note}. Its own script, not part of BalanceSim,
## so tests/test_balance_reactions.gd can call it without the exit leak BalanceSim's bag
## member brings (scripts/run_tests.sh header).

## docs/design.md Balance targets, reactions (E3-S8): a fair par 4 played by a field of
## FIELD_TARGET guests gets FAIR_PRAISE praise and complaints under FAIR_COMPLAINTS' top; the
## same hole blind gets at most BLIND_PRAISE_SHARE of its praise and at least
## FAIR_TO_BLIND_COMPLAINTS more complaints (clearly worse).
const FIELD_TARGET: int = 50
const FAIR_PRAISE := Vector2(0.60, 0.75)
const FAIR_COMPLAINTS := Vector2(0.0, 0.149)
const BLIND_PRAISE_SHARE: float = 0.5
const FAIR_TO_BLIND_COMPLAINTS: float = 0.15
## E3-S22: pace fails on the first tee (the nine-hole fixture's hole 1), its first par 5
## (PACE_PAR5_HOLE) each within PACE_SPREAD of the fair par 4's, the dogleg within
## DOGLEG_PACE_SPREAD (D61). Its other par 5
## (hole 8) was a recorded row (E3-S22 review: it failed pace on waits at its own tee); since
## E3-S37 (`next_tee_queue_max`) it has the same target.
## Read on PACE_FIELD hole records of the fair par 4 and the dogleg and PACE_DAYS nine-hole
## days (days 1 to 10, as D46 measured them), whatever `--runs` is: a field of 50 is three
## mornings, too few for a share of waits a few seconds long (E3-S22).
const PACE_SPREAD: float = 0.10
## D61 (E5-S12): the dogleg's pace fails within 15 points of the fair par 4's (10 before). The
## 10 was measured when groups vanished at hole-out and held nobody; since guests walk off
## greens (D60's clubhouse) a long dogleg approach really is held longer. Both holes are
## one-hole fields whose groups walk home to the clubhouse beside the tee, like with like.
const DOGLEG_PACE_SPREAD: float = 0.15
const PACE_FIRST_TEE_HOLE: int = 1
const PACE_PAR5_HOLE: int = 3
const PACE_FIELD: int = 150
const PACE_DAYS: int = 10
## The days a field may take before play_field stops (a hole nobody finishes).
const FIELD_MAX_DAYS: int = 60
## The nine-hole day: the nine-hole fixtures on this land, the first NINE_DAYS days. E3-S48:
## the days reaching every hole are read on nine_holes_hazards (REACH_FIXTURE: the same holes
## with a bunker on each line and hole 1's crest cut, so they can be praised, E3-S23); pace
## across hole shapes stays on the bare nine (PACE_FIXTURE), which E3-S22, E3-S54 and E3-S37
## tuned its targets on.
const NINE_LAND_SEED: int = 7
const NINE_DAYS: int = 5
const REACH_FIXTURE: String = "hazards"
const PACE_FIXTURE: String = "bare"
const NINE_FILES := {"bare": "nine_holes.gd", "hazards": "nine_holes_hazards.gd"}
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const NineHolesHazards := preload("res://tests/fixtures/nine_holes_hazards.gd")
## E9-S2 (D65): the walk check. On the bare nine (PACE_FIXTURE, its PACE_DAYS days), a fair
## layout whose walks between holes run 5 to 86 yd, at most WALK_FAIL_MAX of the hole records
## fail the walk (each is a complaint naming the walk, walk_check_weight). On the far next tee
## (tests/fixtures/guest_course.gd far_next_tee, a 277 yd walk from hole 1's green to hole 2's
## tee), a cart path along the walk leaves at most WALK_PATH_SHARE_MAX of the walk fails it
## draws without one.
const WALK_FAIL_MAX: float = 0.10
const WALK_PATH_SHARE_MAX: float = 0.5
const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
## E3-S48: the script a parallel job runs in (run_jobs), and how often run_jobs looks for the
## jobs it started to finish.
const JOB_SCRIPT: String = "res://scripts/reaction_job.gd"
const JOB_POLL_MS: int = 20
const EPS := 0.001
## E13-S5: the example courses (FamousCourses.files(), in res://courses/), each played
## EXAMPLE_DAYS days (day seeds 1 on, as scripts/guest_day.gd plays them) at EXAMPLE_ARRIVALS
## guests a day (the most a day draws, data/economy.json arrivals_max; a 4.5-star course draws
## it). Each prints one row: the reaction mix, its rating and the latest finish. Reported, not
## targets (the user, 2026-11-13).
const EXAMPLE_DAYS: int = 5
const EXAMPLE_ARRIVALS: int = 24
## E18-S3 (D72): the eighteen-hole field: tests/fixtures/eighteen_holes.gd (two copies of the
## nine's layout with nine_holes_hazards' bunkers on 192 x 192, the clubhouse between the 1st and
## 10th tees), its first EIGHTEEN_DAYS days as a New sandbox course plays them, at
## EXAMPLE_ARRIVALS guests a day with data/guests.json's mix of nines and eighteens. Targets:
## every group that tees off finishes its round before dusk on every day, and at most
## WALK_FAIL_MAX of its hole records fail the walk (the walk out from the clubhouse at the turn
## included); the mix, the reactions, their rating and pace are reported.
const EIGHTEEN_DAYS: int = 5
const EighteenHoles := preload("res://tests/fixtures/eighteen_holes.gd")

var model: Variant


## `p_model` is the ShotModel guests play with (a new one when null).
func _init(p_model: Variant = null) -> void:
	model = p_model if p_model != null else ShotModel.new()


static func _row(row_name: String, measured: float, target: Vector2, note: String = "") -> Dictionary:
	return {"name": row_name, "measured": measured, "target": target,
			"ok": measured >= target.x - EPS and measured <= target.y + EPS, "note": note}


## A field of `runs` guests (at least 1), drawn as the day draws them (GuestSpawner), plays
## each fixture hole (tests/fixtures/reaction_holes.gd) through GuestBrain as Play runs it
## (play_field): the fair par 4 against its praise and complaint targets; the same hole blind,
## clearly worse (at most BLIND_PRAISE_SHARE of the fair hole's praise and at least
## FAIR_TO_BLIND_COMPLAINTS more complaints); the one-parcel corridor par 4 on the generated
## land of `rng_seed` and the New sandbox dogleg, recorded. Then the nine-hole field
## (E3-S48: tests/fixtures/nine_holes_hazards.gd, REACH_FIXTURE, whose holes can be praised)
## plays the first `nine_days` days of a New sandbox course (GuestSim.day_seed(0, d)), each
## against "every hole reached". Last, E3-S24's scoring at the edges
## (scripts/scoring_edges.gd): skill 10 on the spike holes, putting on sloped greens and
## chips, `runs` guests each, unless `edges` is false (tests read them alone).
## E3-S22: before the edges, pace across hole shapes (the first tee, the nine-hole fixture's
## par 5s and the dogleg, each within PACE_SPREAD (the dogleg DOGLEG_PACE_SPREAD, D61) of the fair par 4's pace fails, on the bare
## nine, PACE_FIXTURE) and the crossing holes' field (ReactionHoles.crossing_holes), held for a
## group on the other hole.
## E3-S48: the work is a list of jobs (jobs_for, run_job), each a plain call with a JSON
## result, run one after another (`workers` 1) or up to `workers` at once in their own
## headless Godots (run_jobs, scripts/reaction_job.gd); the rows are the same either way. A
## field is played once at its largest size and its first records tallied for the smaller
## (the first `n` records of a field are the field of `n`), and each nine-hole day once.
## E13-S5: before the edges, a row per example course (example_row; its first `example_days`
## days at EXAMPLE_ARRIVALS guests), reported, with no target.
## E18-S3: after the example courses, the eighteen-hole field's rows (eighteen_rows; its first
## `eighteen_days` days).
func measure(runs: int, rng_seed: int, nine_days: int = NINE_DAYS, edges: bool = true,
		pace_field: int = PACE_FIELD, pace_days: int = PACE_DAYS, workers: int = 1,
		example_days: int = EXAMPLE_DAYS, eighteen_days: int = EIGHTEEN_DAYS) -> Array[Dictionary]:
	var n := maxi(runs, 1)
	var pf := maxi(pace_field, 1)
	var nd := maxi(nine_days, 1)
	var pd := maxi(pace_days, 1)
	var jobs := jobs_for(n, rng_seed, nd, pd, edges, pf, example_days, eighteen_days)
	return rows_from(n, rng_seed, nd, pd, edges, pf, jobs, run_jobs(jobs, workers), example_days,
			eighteen_days)


## measure's rows from the `results` of its `jobs` (jobs_for with the same arguments; a test
## may run them in one batch with others).
func rows_from(n: int, rng_seed: int, nd: int, pd: int, edges: bool, pf: int,
		jobs: Array[Dictionary], results: Array[Dictionary], example_days: int = 0,
		eighteen_days: int = 0) -> Array[Dictionary]:
	var by := {}
	for i: int in jobs.size():
		by[job_key(jobs[i])] = results[i]
	var rows: Array[Dictionary] = []
	var fair := _tally_of(by, "fair", n)
	rows.append(_row("fair par 4: praise (share of the field)", fair.praise, FAIR_PRAISE,
			"%d guests; %s" % [n, fair.note]))
	rows.append(_row("fair par 4: complaints (share)", fair.complaints, FAIR_COMPLAINTS,
			"fails: %s" % fair.fails))
	var blind := _tally_of(by, "blind", n)
	rows.append(_row("blind par 4: praise (share)", blind.praise,
			Vector2(0.0, float(fair.praise) * BLIND_PRAISE_SHARE),
			"the same hole behind a one-step ridge; %s" % blind.note))
	rows.append(_row("blind par 4: complaints (share)", blind.complaints,
			Vector2(float(fair.complaints) + FAIR_TO_BLIND_COMPLAINTS, INF), "fails: %s" % blind.fails))
	var corridor := _tally_of(by, "corridor", n)
	if corridor.is_empty():
		rows.append(_row("corridor par 4: opens on land seed %d" % rng_seed, 0.0, Vector2(1.0, 1.0)))
	else:
		rows.append(_row("corridor par 4: tee shots OB (share)", corridor.tee_ob, Vector2(-INF, INF),
				"land seed %d, one parcel (80 yd) wide; OB %.2f a guest a hole; %s" % [rng_seed,
					corridor.ob_per_hole, corridor.note]))
		rows.append(_row("corridor par 4: praise (share)", corridor.praise, Vector2(-INF, INF),
				"complaints %.2f; fails: %s" % [corridor.complaints, corridor.fails]))
	var dog := _tally_of(by, "dogleg", n)
	rows.append(_row("dogleg par 4: strokes over the expected score (mean)", dog.over, Vector2(-INF, INF),
			"333 yd straight, 470 yd round the corner; by skill %s; praise %.2f, complaints %.2f; fails: %s" % [
				dog.over_by_skill, dog.praise, dog.complaints, dog.fails]))
	var nine := combine_days(_days_of(by, REACH_FIXTURE, nd), REACH_FIXTURE)
	rows.append(_row("nine holes, New sandbox: days reaching every hole", nine.reached,
			Vector2(1.0, 1.0), nine.note))
	rows.append(_row("nine holes, New sandbox: days every hole was finished", nine.finished, Vector2(-INF, INF), "by at least one guest; praise %.2f of %d records" % [
				nine.praise, nine.records]))
	# E3-S22: pace across hole shapes, each against the fair par 4's pace fails, on bigger
	# samples than the field (PACE_FIELD, PACE_DAYS).
	var spread := Vector2(-PACE_SPREAD, PACE_SPREAD)
	var fair_pace := _tally_of(by, "fair", pf)
	var dog_pace := _tally_of(by, "dogleg", pf)
	var pace_nine := combine_days(_days_of(by, PACE_FIXTURE, pd), PACE_FIXTURE)
	var pace_by_hole: Dictionary = pace_nine.pace_by_hole
	var base: float = fair_pace.pace
	rows.append(_row("pace fails: fair par 4 (share)", base, Vector2(-INF, INF),
			"%d hole records; praise %.2f; waits a hole mean %.1f s, of which on the tee %.1f" % [
				pf, fair_pace.praise, fair_pace.wait_mean, fair_pace.tee_wait_mean]))
	rows.append(_row("pace fails: first tee (nine holes, hole %d) less the fair par 4's" % PACE_FIRST_TEE_HOLE,
			float(pace_by_hole.get(PACE_FIRST_TEE_HOLE, 0.0)) - base, spread,
			"%.2f against %.2f; nine-hole days 1 to %d" % [
				float(pace_by_hole.get(PACE_FIRST_TEE_HOLE, 0.0)), base, pd]))
	rows.append(_row("pace fails: par 5 (nine holes, hole %d) less the fair par 4's" % PACE_PAR5_HOLE,
			float(pace_by_hole.get(PACE_PAR5_HOLE, 0.0)) - base, spread,
			"%.2f against %.2f; %s" % [float(pace_by_hole.get(PACE_PAR5_HOLE, 0.0)), base,
				pace_nine.note.get_slice("; ", pace_nine.note.get_slice_count("; ") - 1)]))
	# E3-S22 review: the fixture's other par 5 (hole 8), recorded until E3-S37 gave it the
	# spread too; every nine-hole hole past the spread prints here with where its waits were.
	var worst_par5 := -1
	var over := PackedStringArray()
	for num: int in pace_by_hole:
		var p := float(pace_by_hole[num])
		if int(pace_nine.par_by_hole.get(num, 0)) == 5 and num != PACE_PAR5_HOLE and (
				worst_par5 < 0 or p > float(pace_by_hole[worst_par5])):
			worst_par5 = num
		if p - base > PACE_SPREAD + EPS:
			over.append("hole %d (par %d) %.2f, waits a record on the tee %.1f s, crossing %.1f s" % [
					num, int(pace_nine.par_by_hole.get(num, 0)), p,
					float(pace_nine.tee_wait_by_hole.get(num, 0.0)),
					float(pace_nine.cross_wait_by_hole.get(num, 0.0))])
	if worst_par5 >= 0:
		rows.append(_row("pace fails: other par 5 (nine holes, hole %d) less the fair par 4's" % worst_par5,
				float(pace_by_hole[worst_par5]) - base, spread,
				"%.2f against %.2f; past the %d-point spread: %s" % [
					float(pace_by_hole[worst_par5]), base, roundi(PACE_SPREAD * 100.0),
					"none" if over.is_empty() else "; ".join(over)]))
	rows.append(_row("pace fails: dogleg par 4 less the fair par 4's", dog_pace.pace - base,
			Vector2(-DOGLEG_PACE_SPREAD, DOGLEG_PACE_SPREAD),
			"%.2f against %.2f; %d hole records; waits a hole mean %.1f s" % [dog_pace.pace, base, pf,
				dog_pace.wait_mean]))
	# E9-S2: the walk check on a fair layout, and what a cart path does for a far next tee.
	rows.append(_row("walk fails: nine holes (share of records)", pace_nine.walk,
			Vector2(0.0, WALK_FAIL_MAX), "each a complaint naming the walk; by hole: %s; fair par 4 %.2f, dogleg %.2f" % [
				pace_nine.walk_by_hole_text, fair_pace.walk, dog_pace.walk]))
	var far := _tally_of(by, "far_tee", n)
	var far_path := _tally_of(by, "far_tee_path", n)
	rows.append(_row("far next tee: walk fails with a cart path (share of those without)",
			far_path.walk / maxf(far.walk, EPS), Vector2(0.0, WALK_PATH_SHARE_MAX),
			"%.2f of %d records with the path, %.2f without (hole 2 of 2, 277 yd from hole 1's green); complaints %.2f against %.2f" % [
				far_path.walk, n, far.walk, far_path.complaints, far.complaints]))
	var crossing := _tally_of(by, "crossing", n)
	rows.append(_row("crossing holes: records held for a group on the other hole (share)",
			crossing.cross_held, Vector2(-INF, INF),
			"a par 3's green on a par 4's line 250 yd out; held %.1f s a record on average; pace fails %.2f; %s" % [
				crossing.cross_wait_mean, crossing.pace, crossing.note]))
	# E13-S5: a row per example course, reported (no target).
	if example_days > 0:
		for file: String in FamousCourses.files():
			var days: Array[Dictionary] = []
			for d: int in range(1, example_days + 1):
				days.append(by[job_key(example_job(file, d))])
			rows.append(example_row(file, days))
	# E18-S3 (D72): the eighteen-hole field.
	if eighteen_days > 0:
		var days18: Array[Dictionary] = []
		for d: int in range(1, eighteen_days + 1):
			days18.append(by[job_key(eighteen_job(d))])
		rows.append_array(eighteen_rows(days18, pace_nine))
	if edges:
		var edge_results: Array[Dictionary] = []
		for i: int in jobs.size():
			if String(jobs[i].kind).begins_with("edge_"):
				edge_results.append(results[i])
		rows.append_array(ScoringEdges.new(model).rows_from(n, rng_seed, edge_results))
	return rows


## E3-S48: measure's jobs, the longest first (the nine-hole days and the 150-record fields),
## so a parallel run is not left waiting on one long job at the end: each field once at its
## largest size, cut at the sizes measure reads; each nine-hole day of each fixture once; the
## edges' jobs (ScoringEdges.jobs).
func jobs_for(n: int, rng_seed: int, nine_days: int, pace_days: int, edges: bool,
		pf: int, example_days: int = 0, eighteen_days: int = 0) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	# E18-S3: the eighteen-hole days, longer still.
	for d: int in range(1, eighteen_days + 1):
		jobs.append(eighteen_job(d))
	# E13-S5: the example courses' days first, the longest jobs of all.
	for file: String in FamousCourses.files():
		for d: int in range(1, example_days + 1):
			jobs.append(example_job(file, d))
	var days := {}
	for d: int in range(1, pace_days + 1):
		days[[PACE_FIXTURE, d]] = true
	for d: int in range(1, nine_days + 1):
		days[[REACH_FIXTURE, d]] = true
	for k: Array in days:
		jobs.append({"kind": "nine_day", "fixture": k[0], "day": k[1]})
	for course_name: String in ["dogleg", "fair"]:
		jobs.append({"kind": "field", "course": course_name, "n": maxi(n, pf), "seed": rng_seed,
				"cuts": [n, pf]})
	for course_name: String in ["blind", "corridor", "crossing", "far_tee", "far_tee_path"]:
		jobs.append({"kind": "field", "course": course_name, "n": n, "seed": rng_seed, "cuts": [n]})
	if edges:
		jobs.append_array(ScoringEdges.new(model).jobs(n, rng_seed))
	return jobs


## The first `n` hole records a field gives on `course`, a course of one open hole: the days
## of seeds `rng_seed`, `rng_seed` + 1, ... (GuestSpawner's arrivals, so groups queue on the
## tee as they do in Play), each run to dusk through GuestBrain. [{day, guest, record}], in
## the order the records were given. Stops after FIELD_MAX_DAYS days.
func play_field(course: CourseData, n: int, rng_seed: int) -> Array[Dictionary]:
	var tuning := GuestTuning.load_default()
	var out: Array[Dictionary] = []
	var d := 0
	while out.size() < n and d < FIELD_MAX_DAYS:
		var day_seed := rng_seed + d
		var brain := GuestBrain.new(course, day_seed, tuning, model)
		var given: Array[Dictionary] = []
		brain.hole_finished.connect(func(g: Guest, r: Guest.HoleRecord) -> void:
			given.append({"day": day_seed, "guest": g, "record": r}))
		brain.run_day()
		for e: Dictionary in given:
			if out.size() < n:
				out.append(e)
		d += 1
	return out


## A field's reactions summed: shares of praise, neutral and complaints, each check's fail
## share, the mean strokes over the expected score (D40), overall and by skill, and OB.
static func tally(field: Array[Dictionary]) -> Dictionary:
	var tuning := GuestTuning.load_default()
	var n := maxi(field.size(), 1)
	var kinds := [0, 0, 0]
	var fails := []
	fails.resize(GuestReaction.Check.size())
	fails.fill(0)
	var over := 0.0
	var tee_ob := 0
	var ob := 0
	var waits: Array[int] = []
	var by_skill := {}
	var wait_sum := 0
	var tee_wait_sum := 0
	var cross_wait_sum := 0
	var cross_held := 0
	for e: Dictionary in field:
		var g: Guest = e.guest
		var r: Guest.HoleRecord = e.record
		kinds[r.reaction.kind] += 1
		for c: int in GuestReaction.Check.size():
			if not r.reaction.passed[c]:
				fails[c] += 1
		var o := r.score - tuning.expected_score(r.par, g.skill)
		over += o
		var band := "1-3" if g.skill <= 3 else ("4-7" if g.skill <= 7 else "8-10")
		var acc: Array = by_skill.get(band, [0.0, 0])
		by_skill[band] = [float(acc[0]) + o, int(acc[1]) + 1]
		waits.append(r.wait_s)
		wait_sum += r.wait_s
		tee_wait_sum += r.tee_wait_s
		cross_wait_sum += r.cross_wait_s
		if r.cross_wait_s > 0:
			cross_held += 1
		for i: int in r.play.strokes.size():
			if r.play.strokes[i].hazard == Ball.Hazard.OB:
				ob += 1
				if i == 0:
					tee_ob += 1
	waits.sort()
	var fail_text := PackedStringArray()
	for c: int in GuestReaction.Check.size():
		fail_text.append("%s %.2f" % [GuestReaction.CHECK_NAMES[c], fails[c] / float(n)])
	var skill_text := PackedStringArray()
	for band: String in ["1-3", "4-7", "8-10"]:
		if by_skill.has(band):
			var acc: Array = by_skill[band]
			skill_text.append("%s %+.2f" % [band, float(acc[0]) / int(acc[1])])
	var p90 := 0
	var worst := 0
	if not waits.is_empty():
		p90 = waits[mini(int(waits.size() * 0.9), waits.size() - 1)]
		worst = waits[-1]
	return {
		"praise": kinds[GuestReaction.Kind.PRAISE] / float(n),
		"neutral": kinds[GuestReaction.Kind.NEUTRAL] / float(n),
		"complaints": kinds[GuestReaction.Kind.COMPLAINT] / float(n),
		"fails": ", ".join(fail_text),
		"pace": fails[GuestReaction.Check.PACE] / float(n),
		"walk": fails[GuestReaction.Check.WALK] / float(n),
		"wait_mean": wait_sum / float(n),
		"tee_wait_mean": tee_wait_sum / float(n),
		"cross_wait_mean": cross_wait_sum / float(n),
		"cross_held": cross_held / float(n),
		"over": over / n,
		"over_by_skill": " ".join(skill_text),
		"tee_ob": tee_ob / float(n),
		"ob_per_hole": ob / float(n),
		"note": "neutral %.2f; wait a hole p90 %d s, worst %d; %+.2f strokes over expected" % [
			kinds[GuestReaction.Kind.NEUTRAL] / float(n), p90, worst, over / n],
	}


## A job's key: its kind and arguments, so measure finds each result by what it asked.
static func job_key(job: Dictionary) -> String:
	return JSON.stringify(job, "", true)


## The result of one job (jobs_for, ScoringEdges.jobs), a Dictionary that JSON keeps: a
## field's tallies at each cut ({"<cut>": tally}; {} for a corridor that does not open), one
## nine-hole day (nine_day), or an edges job's numbers.
func run_job(job: Dictionary) -> Dictionary:
	match String(job.kind):
		"field":
			var course := course_named(String(job.course), int(job.seed))
			if course == null:
				return {}
			var field := play_field(course, int(job.n), int(job.seed))
			var out := {}
			for cut: Variant in job.cuts:
				out[str(int(cut))] = tally(field.slice(0, int(cut)))
			return out
		"nine_day":
			return nine_day(String(job.fixture), int(job.day))
		"example_day":
			return example_day(String(job.file), int(job.day), int(job.arrivals))
		"eighteen_day":
			return eighteen_day(int(job.day), int(job.arrivals))
		_:
			return ScoringEdges.new(model).run_job(job)


## E3-S48: every job's result, in order. `workers` 1 or less runs them here one after another;
## more runs up to that many at once, each in its own headless Godot on this project
## (scripts/reaction_job.gd, which calls run_job and writes the result as JSON with full
## precision, so the rows are the same as a run here). A job whose Godot fails is run here.
func run_jobs(jobs: Array[Dictionary], workers: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.resize(jobs.size())
	if workers <= 1:
		for i: int in jobs.size():
			out[i] = run_job(jobs[i])
		return out
	var dir := "user://reaction_jobs/%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var running := {}
	var next := 0
	while next < jobs.size() or not running.is_empty():
		while running.size() < workers and next < jobs.size():
			var path := ProjectSettings.globalize_path("%s/%d.json" % [dir, next])
			var args := PackedStringArray(["--headless", "--quiet", "--path",
					ProjectSettings.globalize_path("res://"), "-s", JOB_SCRIPT, "--",
					"--job=" + JSON.stringify(jobs[next]), "--out=" + path])
			var pid := OS.create_process(OS.get_executable_path(), args)
			if pid <= 0:
				out[next] = run_job(jobs[next])
			else:
				running[pid] = [next, path]
			next += 1
		OS.delay_msec(JOB_POLL_MS)
		for pid: int in running.keys():
			if OS.is_process_running(pid):
				continue
			var i: int = running[pid][0]
			var path: String = running[pid][1]
			running.erase(pid)
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) \
					if FileAccess.file_exists(path) else null
			if typeof(parsed) == TYPE_DICTIONARY:
				out[i] = parsed
			else:
				push_error("reaction job %d left no result; running it here" % i)
				out[i] = run_job(jobs[i])
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	return out


## A fixture hole's course by name (measure's fields): fair, blind, dogleg, crossing, or the
## corridor par 4 on land seed `rng_seed` (null when it does not open).
static func course_named(course_name: String, rng_seed: int) -> CourseData:
	match course_name:
		"fair":
			return ReactionHoles.fair_par4()
		"blind":
			return ReactionHoles.blind_par4()
		"dogleg":
			return ReactionHoles.dogleg_par4()
		"crossing":
			return ReactionHoles.crossing_holes()
		"corridor":
			return ReactionHoles.corridor_par4(rng_seed)
		"far_tee":
			return GuestCourse.far_next_tee(false)
		"far_tee_path":
			return GuestCourse.far_next_tee(true)
	push_error("no fixture hole named %s" % course_name)
	return null


## The tally of the first `cut` records of the field of `course_name` among measure's results
## ({} for a corridor that did not open).
func _tally_of(by: Dictionary, course_name: String, cut: int) -> Dictionary:
	for key: String in by:
		var job: Dictionary = JSON.parse_string(key)
		if String(job.kind) == "field" and String(job.course) == course_name:
			var r: Dictionary = by[key]
			return r.get(str(cut), {})
	return {}


## Nine-hole days 1 to `days` of `fixture` among measure's results, in order.
func _days_of(by: Dictionary, fixture: String, days: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: int in range(1, days + 1):
		out.append(by[job_key({"kind": "nine_day", "fixture": fixture, "day": d})])
	return out


## The nine-hole fixture of that name ("bare": tests/fixtures/nine_holes.gd, "hazards":
## tests/fixtures/nine_holes_hazards.gd) on NINE_LAND_SEED's land, built: {course, opened}.
static func nine_course(fixture: String) -> Dictionary:
	var script: GDScript = NineHolesHazards if fixture == "hazards" else NineHoles
	var course: CourseData = script.land(NINE_LAND_SEED)
	var opened: Array[int] = script.build(CourseBuilder.new(course))
	return {"course": course, "opened": opened}


## Day `d` of the nine-hole `fixture` as a New sandbox course plays it (GuestSim.day_seed(0,
## d)): {reached, finished: every open hole teed off, and finished by someone; part: the day's
## line; pace: {"<hole>": [records, pace fails, tee wait s, crossing wait s]}; records, praise}.
func nine_day(fixture: String, d: int) -> Dictionary:
	var tuning := GuestTuning.load_default()
	var built := nine_course(fixture)
	var course: CourseData = built.course
	var opened: Array[int] = built.opened
	var brain := GuestBrain.new(course, GuestSim.day_seed(0, d), tuning, model)
	brain.run_day()
	var done := {}
	var records := 0
	var praise := 0
	var nine := 0
	var pace := {}
	var walk := {}
	for g: Guest in brain.guests:
		records += g.records.size()
		if g.records.size() == opened.size():
			nine += 1
		for r: Guest.HoleRecord in g.records:
			done[r.number] = true
			if r.reaction.kind == GuestReaction.Kind.PRAISE:
				praise += 1
			var key := str(r.number)
			var acc: Array = pace.get(key, [0, 0, 0, 0])
			pace[key] = [int(acc[0]) + 1,
					int(acc[1]) + (0 if r.reaction.passed[GuestReaction.Check.PACE] else 1),
					int(acc[2]) + r.tee_wait_s, int(acc[3]) + r.cross_wait_s]
			if not r.reaction.passed[GuestReaction.Check.WALK]:
				walk[key] = int(walk.get(key, 0)) + 1
	return {"reached": brain.teed_off.size() == opened.size(), "finished": done.size() == opened.size(),
		"records": records, "praise": praise, "pace": pace, "walk": walk,
		"part": "day %d: %d teed off, %d finished, %d guests played all %d, %d records" % [
				d, brain.teed_off.size(), done.size(), nine, opened.size(), records]}


## The nine-hole days `days` (nine_day's results, in day order) of `fixture` summed: {reached,
## finished: the share of days on which every hole was teed off, and finished by someone;
## pace_by_hole, par_by_hole, tee_wait_by_hole, cross_wait_by_hole (a record, over every
## day); records, praise (share of the records); note}.
static func combine_days(days: Array[Dictionary], fixture: String) -> Dictionary:
	var built := nine_course(fixture)
	var course: CourseData = built.course
	var opened: Array[int] = built.opened
	var reached := 0
	var finished := 0
	var records := 0
	var praise := 0
	var parts := PackedStringArray()
	# {hole number: [records, pace fails, tee, crossing]} over every day (E3-S8 review: par 3s
	# and short holes hold the group behind longest).
	var pace := {}
	var walk := {}
	var walk_fails := 0
	for day: Dictionary in days:
		reached += 1 if bool(day.reached) else 0
		finished += 1 if bool(day.finished) else 0
		records += int(day.records)
		praise += int(day.praise)
		parts.append(String(day.part))
		for key: String in day.get("walk", {}):
			walk[int(key)] = int(walk.get(int(key), 0)) + int(day.walk[key])
			walk_fails += int(day.walk[key])
		for key: String in day.pace:
			var a: Array = day.pace[key]
			var acc: Array = pace.get(int(key), [0, 0, 0, 0])
			pace[int(key)] = [int(acc[0]) + int(a[0]), int(acc[1]) + int(a[1]),
					int(acc[2]) + int(a[2]), int(acc[3]) + int(a[3])]
	var by_hole := PackedStringArray()
	var pace_by_hole := {}
	# E3-S22 review: each hole's par and its counted waits a record on the tee and held for a
	# group on another hole, so a hole past the spread says where its waits were.
	var par_by_hole := {}
	var tee_wait_by_hole := {}
	var cross_wait_by_hole := {}
	var walk_by_hole := PackedStringArray()
	for h: HoleData in course.holes:
		if not opened.has(h.number):
			continue
		var acc: Array = pace.get(h.number, [0, 0, 0, 0])
		var recs := float(maxi(int(acc[0]), 1))
		pace_by_hole[h.number] = int(acc[1]) / recs
		par_by_hole[h.number] = h.par
		tee_wait_by_hole[h.number] = int(acc[2]) / recs
		cross_wait_by_hole[h.number] = int(acc[3]) / recs
		by_hole.append("%d (par %d) %.2f" % [h.number, h.par, pace_by_hole[h.number]])
		walk_by_hole.append("%d %.2f" % [h.number, int(walk.get(h.number, 0)) / recs])
	parts.append("pace fails by hole: " + ", ".join(by_hole))
	var n := float(maxi(days.size(), 1))
	return {"reached": reached / n, "finished": finished / n,
		"records": records, "praise": praise / float(maxi(records, 1)),
		"pace_by_hole": pace_by_hole, "par_by_hole": par_by_hole,
		"tee_wait_by_hole": tee_wait_by_hole, "cross_wait_by_hole": cross_wait_by_hole,
		"walk": walk_fails / float(maxi(records, 1)), "walk_by_hole_text": ", ".join(walk_by_hole),
		"note": "%s: %s" % [NINE_FILES[fixture], "; ".join(parts)]}


## The nine-hole `fixture`'s first `days` days as a New sandbox course plays them, here
## (nine_day, combine_days).
func nine_hole_days(days: int, fixture: String = PACE_FIXTURE) -> Dictionary:
	var out: Array[Dictionary] = []
	for d: int in range(1, days + 1):
		out.append(nine_day(fixture, d))
	return combine_days(out, fixture)


## E13-S5: the job of day `d` on the example course `file` (FamousCourses.FROM), at
## EXAMPLE_ARRIVALS guests.
static func example_job(file: String, d: int) -> Dictionary:
	return {"kind": "example_day", "file": file, "day": d, "arrivals": EXAMPLE_ARRIVALS}


## E13-S5: day `day_seed` of the example course `file` (FamousCourses.FROM) with
## `arrivals` guests (GuestBrain's p_arrivals; -1 for `tuning`'s arrivals_per_day), run to
## dusk through GuestBrain as scripts/guest_day.gd runs it: {name, kinds: [praise, neutral,
## complaint], fails: a count per GuestReaction.Check, records, groups, nine: the groups that
## teed off and all finished every open hole before dusk, latest: the last guest's leaving
## second, day_s}. {} when the file does not load. `tuning` null reads data/guests.json.
func example_day(file: String, day_seed: int, arrivals: int,
		tuning: GuestTuning = null) -> Dictionary:
	var errors: Array[String] = []
	var course := CourseSave.load_file(FamousCourses.FROM.path_join(file), errors)
	if course == null:
		push_error("example course %s: %s" % [file, "; ".join(errors)])
		return {}
	var t := tuning if tuning != null else GuestTuning.load_default()
	var brain := GuestBrain.new(course, day_seed, t, model, [], null, arrivals)
	while not brain.day_over:
		brain.serve(-1)
		brain.step()
	var kinds := [0, 0, 0]
	var fails := []
	fails.resize(GuestReaction.Check.size())
	fails.fill(0)
	var records := 0
	var latest := 0
	var holes := 0
	for h: HoleData in course.holes:
		if h.open:
			holes += 1
	for g: Guest in brain.guests:
		latest = maxi(latest, g.left_s)
		for r: Guest.HoleRecord in g.records:
			records += 1
			kinds[r.reaction.kind] += 1
			for c: int in GuestReaction.Check.size():
				if not r.reaction.passed[c]:
					fails[c] += 1
	var nine := 0
	for gr: GuestGroup in brain.groups:
		var all := brain.guests.has(gr.guests[0])
		for g: Guest in gr.guests:
			all = all and g.records.size() == holes and not g.left_at_dusk
		if all:
			nine += 1
	return {"name": course.course_name, "kinds": kinds, "fails": fails, "records": records,
		"groups": brain.groups.size(), "nine": nine, "latest": latest, "day_s": brain.day_s}


## E13-S5: an example course's row from its days (example_day's results, in day order):
## measured is the rating of its reaction mix (the mean of EconomyTuning.rating_points over
## every reaction, 1 to 5, as the course rating reads a full window), with no target; the note
## gives the mix, the stars that rating shows, each check's fail share, and the latest finish
## against dusk. `arrivals` names the guests a day in the row's name.
static func example_row(file: String, days: Array[Dictionary],
		arrivals: int = EXAMPLE_ARRIVALS) -> Dictionary:
	var points := EconomyTuning.load_default().rating_points
	var kinds := [0, 0, 0]
	var fails := []
	fails.resize(GuestReaction.Check.size())
	fails.fill(0)
	var records := 0
	var latest := 0
	var full_days := 0
	var latest_by_day := PackedStringArray()
	var course_name := file
	var day_s := 0
	for day: Dictionary in days:
		if day.is_empty():
			continue
		course_name = String(day.name)
		day_s = int(day.day_s)
		records += int(day.records)
		for k: int in kinds.size():
			kinds[k] += int(day.kinds[k])
		for c: int in GuestReaction.Check.size():
			fails[c] += int(day.fails[c])
		latest = maxi(latest, int(day.latest))
		latest_by_day.append(str(int(day.latest)))
		if int(day.nine) == int(day.groups):
			full_days += 1
	var n := float(maxi(records, 1))
	var rating := 0.0
	for k: int in kinds.size():
		rating += points[k] * kinds[k] / n
	var fail_text := PackedStringArray()
	for c: int in GuestReaction.Check.size():
		fail_text.append("%s %.2f" % [GuestReaction.CHECK_NAMES[c], fails[c] / n])
	return _row("example course %s: rating of its reaction mix (%d arrivals; reported)" % [
			course_name, arrivals], rating, Vector2(-INF, INF),
			"praise %.2f, neutral %.2f, complaint %.2f of %d reactions, %.1f stars; fails: %s; every group finished nine on %d of %d days, latest finish %d s of %d (days 1 to %d: %s)" % [
				kinds[0] / n, kinds[1] / n, kinds[2] / n, records, EconomyTuning.stars_of(rating),
				", ".join(fail_text), full_days, days.size(), latest, day_s, days.size(),
				"/".join(latest_by_day)])


## E18-S3 (D72): the job of day `d` of the eighteen-hole field (EighteenHoles), at
## EXAMPLE_ARRIVALS guests.
static func eighteen_job(d: int) -> Dictionary:
	return {"kind": "eighteen_day", "day": d, "arrivals": EXAMPLE_ARRIVALS}


## E18-S3 (D72): day `d` of tests/fixtures/eighteen_holes.gd as a New sandbox course plays it
## (GuestSim.day_seed(0, d)) with `arrivals` guests, run to dusk: {open: the holes open, eighteen:
## an eighteen-hole day, day_s, groups, teed: the groups that teed off, finished: of those, the
## groups whose every guest played its whole round and left before dusk, rounds: {"9": groups,
## "18": groups}, back: the nine-hole groups sent to the back nine, latest: the last guest's
## leaving second, kinds, fails (a count per GuestReaction.Check), records, turn_walks: the
## records of the walk out to the 10th from the clubhouse at the turn, turn_walk_fails}.
func eighteen_day(d: int, arrivals: int = EXAMPLE_ARRIVALS, tuning: GuestTuning = null) -> Dictionary:
	var built: Dictionary = EighteenHoles.course()
	var course: CourseData = built.course
	var t := tuning if tuning != null else GuestTuning.load_default()
	var brain := GuestBrain.new(course, GuestSim.day_seed(0, d), t, model, [], null, arrivals)
	brain.run_day()
	var kinds := [0, 0, 0]
	var fails := []
	fails.resize(GuestReaction.Check.size())
	fails.fill(0)
	var records := 0
	var latest := 0
	var turn_walks := 0
	var turn_walk_fails := 0
	for g: Guest in brain.guests:
		latest = maxi(latest, g.left_s)
		for r: Guest.HoleRecord in g.records:
			records += 1
			kinds[r.reaction.kind] += 1
			for c: int in GuestReaction.Check.size():
				if not r.reaction.passed[c]:
					fails[c] += 1
			if g.round_holes == 18 and r.number == 10:
				turn_walks += 1
				if not r.reaction.passed[GuestReaction.Check.WALK]:
					turn_walk_fails += 1
	var teed := 0
	var finished := 0
	var rounds := {"9": 0, "18": 0}
	var back := 0
	for gr: GuestGroup in brain.groups:
		if not brain.guests.has(gr.guests[0]):
			continue
		teed += 1
		rounds[str(gr.round_holes)] = int(rounds.get(str(gr.round_holes), 0)) + 1
		if gr.round_holes == 9 and gr.round_from > GuestBrain.NINE:
			back += 1
		var all := true
		for g: Guest in gr.guests:
			all = all and g.records.size() == gr.round_holes and not g.left_at_dusk
		if all:
			finished += 1
	return {"open": (built.opened as Array).size(), "eighteen": brain.eighteen_day,
		"day_s": brain.day_s, "groups": brain.groups.size(), "teed": teed, "finished": finished,
		"rounds": rounds, "back": back, "latest": latest, "kinds": kinds, "fails": fails,
		"records": records, "turn_walks": turn_walks, "turn_walk_fails": turn_walk_fails}


## E18-S3 (D72): the eighteen-hole field's rows from its days (eighteen_day's results, in day
## order), with the bare nine's days (`pace_nine`, combine_days) to read its pace against.
static func eighteen_rows(days: Array[Dictionary], pace_nine: Dictionary = {}) -> Array[Dictionary]:
	var points := EconomyTuning.load_default().rating_points
	var kinds := [0, 0, 0]
	var fails := []
	fails.resize(GuestReaction.Check.size())
	fails.fill(0)
	var records := 0
	var full_days := 0
	var latest := 0
	var day_s := 0
	var groups := 0
	var eighteens := 0
	var back := 0
	var turn_walks := 0
	var turn_fails := 0
	var all_open := true
	var per_day := PackedStringArray()
	for day: Dictionary in days:
		all_open = all_open and int(day.open) == 18 and bool(day.eighteen)
		day_s = int(day.day_s)
		records += int(day.records)
		for k: int in kinds.size():
			kinds[k] += int(day.kinds[k])
		for c: int in GuestReaction.Check.size():
			fails[c] += int(day.fails[c])
		latest = maxi(latest, int(day.latest))
		groups += int(day.teed)
		eighteens += int(day.rounds.get("18", 0))
		back += int(day.back)
		turn_walks += int(day.turn_walks)
		turn_fails += int(day.turn_walk_fails)
		if int(day.finished) == int(day.teed) and int(day.teed) == int(day.groups):
			full_days += 1
		per_day.append("%d/%d" % [int(day.rounds.get("18", 0)), int(day.latest)])
	var nd := float(maxi(days.size(), 1))
	var n := float(maxi(records, 1))
	var rating := 0.0
	for k: int in kinds.size():
		rating += points[k] * kinds[k] / n
	var fail_text := PackedStringArray()
	for c: int in GuestReaction.Check.size():
		fail_text.append("%s %.2f" % [GuestReaction.CHECK_NAMES[c], fails[c] / n])
	var rows: Array[Dictionary] = []
	rows.append(_row("eighteen holes (%d arrivals): days every group finished its round before dusk" % EXAMPLE_ARRIVALS,
			full_days / nd if all_open else 0.0, Vector2(1.0, 1.0),
			"%d of %d days%s; latest finish %d s of %d; eighteens and latest finish by day %s" % [
				full_days, days.size(), "" if all_open else ", NOT ALL EIGHTEEN OPEN", latest, day_s,
				" ".join(per_day)]))
	rows.append(_row("eighteen holes: groups playing eighteen (share)", eighteens / float(maxi(groups, 1)),
			Vector2(-INF, INF), "%d of %d groups; %d of the nines sent to the back nine" % [
				eighteens, groups, back]))
	rows.append(_row("eighteen holes: rating of its reaction mix (reported)", rating, Vector2(-INF, INF),
			"praise %.2f, neutral %.2f, complaint %.2f of %d reactions, %.1f stars; fails: %s" % [
				kinds[0] / n, kinds[1] / n, kinds[2] / n, records, EconomyTuning.stars_of(rating),
				", ".join(fail_text)]))
	var nine_pace := -1.0
	if pace_nine.has("pace_by_hole"):
		var sum := 0.0
		for num: int in pace_nine.pace_by_hole:
			sum += float(pace_nine.pace_by_hole[num])
		nine_pace = sum / maxf(float((pace_nine.pace_by_hole as Dictionary).size()), 1.0)
	rows.append(_row("eighteen holes: pace fails (share of records; reported)",
			fails[GuestReaction.Check.PACE] / n, Vector2(-INF, INF),
			"the bare nine's mean over its holes %s" % (("%.2f" % nine_pace) if nine_pace >= 0.0 else "not run")))
	rows.append(_row("eighteen holes: walk fails (share of records)", fails[GuestReaction.Check.WALK] / n,
			Vector2(0.0, WALK_FAIL_MAX), "the turn's walk out from the clubhouse to the 10th: %d of %d eighteens' records fail it" % [
				turn_fails, turn_walks]))
	return rows
