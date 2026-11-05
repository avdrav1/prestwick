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
## (PACE_PAR5_HOLE) and the dogleg each within PACE_SPREAD of the fair par 4's. Its other par 5
## (hole 8) is a recorded row, no target (E3-S22 review): it fails pace on waits at its own tee.
## Read on PACE_FIELD hole records of the fair par 4 and the dogleg and PACE_DAYS nine-hole
## days (days 1 to 10, as D46 measured them), whatever `--runs` is: a field of 50 is three
## mornings, too few for a share of waits a few seconds long (E3-S22).
const PACE_SPREAD: float = 0.10
const PACE_FIRST_TEE_HOLE: int = 1
const PACE_PAR5_HOLE: int = 3
const PACE_FIELD: int = 150
const PACE_DAYS: int = 10
## The days a field may take before play_field stops (a hole nobody finishes).
const FIELD_MAX_DAYS: int = 60
## The nine-hole day: tests/fixtures/nine_holes.gd on this land, the first NINE_DAYS days.
const NINE_LAND_SEED: int = 7
const NINE_DAYS: int = 5
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const EPS := 0.001

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
## land of `rng_seed` and the New sandbox dogleg, recorded. Then the nine-hole fixture
## (tests/fixtures/nine_holes.gd) plays the first `nine_days` days of a New sandbox course
## (GuestSim.day_seed(0, d)), each against "every hole reached". Last, E3-S24's scoring at
## the edges (scripts/scoring_edges.gd): skill 10 on the spike holes, putting on sloped
## greens and chips, `runs` guests each, unless `edges` is false (tests read them alone).
## E3-S22: before the edges, pace across hole shapes (the first tee, the nine-hole fixture's
## first par 5 and the dogleg, each within PACE_SPREAD of the fair par 4's pace fails) and the
## crossing holes' field (ReactionHoles.crossing_holes), held for a group on the other hole.
func measure(runs: int, rng_seed: int, nine_days: int = NINE_DAYS, edges: bool = true,
		pace_field: int = PACE_FIELD, pace_days: int = PACE_DAYS) -> Array[Dictionary]:
	var n := maxi(runs, 1)
	var rows: Array[Dictionary] = []
	var fair := tally(play_field(ReactionHoles.fair_par4(), n, rng_seed))
	rows.append(_row("fair par 4: praise (share of the field)", fair.praise, FAIR_PRAISE,
			"%d guests; %s" % [n, fair.note]))
	rows.append(_row("fair par 4: complaints (share)", fair.complaints, FAIR_COMPLAINTS,
			"fails: %s" % fair.fails))
	var blind := tally(play_field(ReactionHoles.blind_par4(), n, rng_seed))
	rows.append(_row("blind par 4: praise (share)", blind.praise,
			Vector2(0.0, float(fair.praise) * BLIND_PRAISE_SHARE),
			"the same hole behind a one-step ridge; %s" % blind.note))
	rows.append(_row("blind par 4: complaints (share)", blind.complaints,
			Vector2(float(fair.complaints) + FAIR_TO_BLIND_COMPLAINTS, INF), "fails: %s" % blind.fails))
	var corridor_course := ReactionHoles.corridor_par4(rng_seed)
	if corridor_course == null:
		rows.append(_row("corridor par 4: opens on land seed %d" % rng_seed, 0.0, Vector2(1.0, 1.0)))
	else:
		var corridor := tally(play_field(corridor_course, n, rng_seed))
		rows.append(_row("corridor par 4: tee shots OB (share)", corridor.tee_ob, Vector2(-INF, INF),
				"land seed %d, one parcel (80 yd) wide; OB %.2f a guest a hole; %s" % [rng_seed,
					corridor.ob_per_hole, corridor.note]))
		rows.append(_row("corridor par 4: praise (share)", corridor.praise, Vector2(-INF, INF),
				"complaints %.2f; fails: %s" % [corridor.complaints, corridor.fails]))
	var dog := tally(play_field(ReactionHoles.dogleg_par4(), n, rng_seed))
	rows.append(_row("dogleg par 4: strokes over the expected score (mean)", dog.over, Vector2(-INF, INF),
			"333 yd straight, 470 yd round the corner; by skill %s; praise %.2f, complaints %.2f; fails: %s" % [
				dog.over_by_skill, dog.praise, dog.complaints, dog.fails]))
	var nine := nine_hole_days(maxi(nine_days, 1))
	rows.append(_row("nine holes, New sandbox: days reaching every hole", nine.reached, Vector2(1.0, 1.0),
			nine.note))
	rows.append(_row("nine holes, New sandbox: days every hole was finished", nine.finished,
			Vector2(-INF, INF), "by at least one guest"))
	# E3-S22: pace across hole shapes, each against the fair par 4's pace fails, on bigger
	# samples than the field (PACE_FIELD, PACE_DAYS).
	var spread := Vector2(-PACE_SPREAD, PACE_SPREAD)
	var pf := maxi(pace_field, 1)
	var fair_pace := fair if pf == n else tally(play_field(ReactionHoles.fair_par4(), pf, rng_seed))
	var dog_pace := dog if pf == n else tally(play_field(ReactionHoles.dogleg_par4(), pf, rng_seed))
	var pace_nine := nine if maxi(pace_days, 1) == maxi(nine_days, 1) else nine_hole_days(maxi(pace_days, 1))
	var pace_by_hole: Dictionary = pace_nine.pace_by_hole
	var base: float = fair_pace.pace
	rows.append(_row("pace fails: fair par 4 (share)", base, Vector2(-INF, INF),
			"%d hole records; praise %.2f; waits a hole mean %.1f s, of which on the tee %.1f" % [
				pf, fair_pace.praise, fair_pace.wait_mean, fair_pace.tee_wait_mean]))
	rows.append(_row("pace fails: first tee (nine holes, hole %d) less the fair par 4's" % PACE_FIRST_TEE_HOLE,
			float(pace_by_hole.get(PACE_FIRST_TEE_HOLE, 0.0)) - base, spread,
			"%.2f against %.2f; nine-hole days 1 to %d" % [
				float(pace_by_hole.get(PACE_FIRST_TEE_HOLE, 0.0)), base, maxi(pace_days, 1)]))
	rows.append(_row("pace fails: par 5 (nine holes, hole %d) less the fair par 4's" % PACE_PAR5_HOLE,
			float(pace_by_hole.get(PACE_PAR5_HOLE, 0.0)) - base, spread,
			"%.2f against %.2f; %s" % [float(pace_by_hole.get(PACE_PAR5_HOLE, 0.0)), base,
				pace_nine.note.get_slice("; ", pace_nine.note.get_slice_count("; ") - 1)]))
	# E3-S22 review: recorded, no target. The target's par 5 is hole 3 (the E3 review's "33%
	# on the par 5"); the fixture's other par 5 and every nine-hole hole past the spread print
	# here with where their waits were, so the target does not read as covering them.
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
		rows.append(_row("pace fails: other par 5 (nine holes, hole %d) less the fair par 4's, recorded" % worst_par5,
				float(pace_by_hole[worst_par5]) - base, Vector2(-INF, INF),
				"%.2f against %.2f; past the %d-point spread: %s" % [
					float(pace_by_hole[worst_par5]), base, roundi(PACE_SPREAD * 100.0),
					"none" if over.is_empty() else "; ".join(over)]))
	rows.append(_row("pace fails: dogleg par 4 less the fair par 4's", dog_pace.pace - base, spread,
			"%.2f against %.2f; %d hole records; waits a hole mean %.1f s" % [dog_pace.pace, base, pf,
				dog_pace.wait_mean]))
	var crossing := tally(play_field(ReactionHoles.crossing_holes(), n, rng_seed))
	rows.append(_row("crossing holes: records held for a group on the other hole (share)",
			crossing.cross_held, Vector2(-INF, INF),
			"a par 3's green on a par 4's line 250 yd out; held %.1f s a record on average; pace fails %.2f; %s" % [
				crossing.cross_wait_mean, crossing.pace, crossing.note]))
	if edges:
		rows.append_array(ScoringEdges.new(model).measure(n, rng_seed))
	return rows


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
	var fails := [0, 0, 0, 0]
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


## The nine-hole fixture's first `days` days as a New sandbox course plays them: {reached,
## finished: the share of days on which every hole was teed off, and finished by someone;
## note}.
func nine_hole_days(days: int) -> Dictionary:
	var tuning := GuestTuning.load_default()
	var course := NineHoles.land(NINE_LAND_SEED)
	var opened := NineHoles.build(CourseBuilder.new(course))
	var reached := 0
	var finished := 0
	var parts := PackedStringArray()
	# {hole number: [records, pace fails]} over every day (E3-S8 review: par 3s and short
	# holes hold the group behind longest).
	var pace := {}
	for d: int in range(1, days + 1):
		var brain := GuestBrain.new(course, GuestSim.day_seed(0, d), tuning, model)
		brain.run_day()
		var done := {}
		var records := 0
		var nine := 0
		for g: Guest in brain.guests:
			records += g.records.size()
			if g.records.size() == opened.size():
				nine += 1
			for r: Guest.HoleRecord in g.records:
				done[r.number] = true
				var acc: Array = pace.get(r.number, [0, 0, 0, 0])
				pace[r.number] = [int(acc[0]) + 1,
						int(acc[1]) + (0 if r.reaction.passed[GuestReaction.Check.PACE] else 1),
						int(acc[2]) + r.tee_wait_s, int(acc[3]) + r.cross_wait_s]
		if brain.teed_off.size() == opened.size():
			reached += 1
		if done.size() == opened.size():
			finished += 1
		parts.append("day %d: %d teed off, %d finished, %d guests played all %d, %d records" % [
				d, brain.teed_off.size(), done.size(), nine, opened.size(), records])
	var by_hole := PackedStringArray()
	var pace_by_hole := {}
	# E3-S22 review: each hole's par and its counted waits a record on the tee and held for a
	# group on another hole, so a hole past the spread says where its waits were.
	var par_by_hole := {}
	var tee_wait_by_hole := {}
	var cross_wait_by_hole := {}
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
	parts.append("pace fails by hole: " + ", ".join(by_hole))
	return {"reached": reached / float(days), "finished": finished / float(days),
		"pace_by_hole": pace_by_hole, "par_by_hole": par_by_hole,
		"tee_wait_by_hole": tee_wait_by_hole, "cross_wait_by_hole": cross_wait_by_hole,
		"note": "; ".join(parts)}
