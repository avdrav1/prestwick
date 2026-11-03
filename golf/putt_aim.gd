class_name PuttAim
extends RefCounted
## The putter's aim marker (D21, docs/design.md Swing, Aim marker): the putt, along the aim
## with accuracy at the centre, at the power whose roll comes to rest nearest the cup. Each
## try is a ShotPrediction, the same Ball step as the live putt (E1-S7), so a putt struck at
## `power` rests on the marker. The bar's locked power still decides the real putt; this only
## says which roll the marker and dots show. No scene, so guests (E3) can read it too.
##
## The solve is a safeguarded secant on the signed miss along the aim (how far past the
## cup's projection onto the aim the rest lies, negative when short), which grows with power
## on any green a putt can climb. On a bank steep enough that a harder putt rolls back
## further (about two steps per tile), the miss is not monotonic and the solve can stop a few
## yards off the nearest putt the bar can make (E2-S20 review; a followup). It stops at a holed putt, at a miss inside
## `putt_aim_tolerance_yd`, at the edge of the bar (a cup out of reach, or a downhill putt
## too fast even at 0%), or after `putt_aim_max_runs` predictions. Of every putt it ran it
## keeps the one resting nearest the cup (a holed putt rests on it), a dry rest before a drop.
## A warm start (the last solve's power, while the ball stays put) usually ends it in two or
## three runs while the player sweeps the aim.

## The power picked, 0 to 1 (the bar's share; the putter maps it linearly, Swing.putt_speed).
var power: float = 1.0
## The putt at `power`: what the marker and dots show.
var prediction: ShotPrediction
## The launch at `power`.
var shot: ShotLaunch
## How far the rest lies from the cup's centre, yards (0 when holed).
var miss_yd: float = INF
## Predictions run to find it (the solve's cost: each is one putt run to rest).
var runs: int = 0


## Solves the putt from `at` (yards) along `aim_deg` toward `cup_tile` on `course`, with the
## stroke's seed `rng_seed`. `warm_power` (0 to 1) is a first guess, or below 0 for none.
static func solve(course: CourseData, field: HeightField, model: ShotModel, tuning: SwingTuning,
		at: Vector2, aim_deg: float, cup_tile: Vector2i, rng_seed: int,
		warm_power: float = -1.0) -> PuttAim:
	var a := PuttAim.new()
	var cup := field.tile_center(cup_tile)
	# The miss is measured along the aim, against the cup's projection onto it: a straight
	# roll along the aim rests nearest the cup there, and a cup square to the aim or behind
	# it solves to 0% (E2-S20 review: along the ball-to-cup line, an aim turned off the cup
	# chased a roll of L / cos(angle) and ran yards long).
	var line := Vector2.RIGHT.rotated(deg_to_rad(aim_deg))
	var length := maxf((cup - at).dot(line), 0.0)
	# Yards of roll per unit of power, for the first step: a full putt's flat roll.
	var slope_guess := model.clubs.full_putt_max_yd
	var p0 := warm_power if warm_power >= 0.0 else length / slope_guess
	p0 = clampf(p0, 0.0, 1.0)
	var m0 := a._try(course, field, model, tuning, at, aim_deg, cup_tile, rng_seed, p0, cup, line, length)
	if a._done(m0, tuning):
		return a
	var p1 := clampf(p0 - m0 / slope_guess, 0.0, 1.0)
	if is_equal_approx(p1, p0):
		return a  # at the bar's edge and still short (or still long at 0%)
	var m1 := a._try(course, field, model, tuning, at, aim_deg, cup_tile, rng_seed, p1, cup, line, length)
	# Bracket once the misses change sign (false position, Illinois), else extrapolate.
	var lo := NAN
	var hi := NAN
	var m_lo := 0.0
	var m_hi := 0.0
	while not a._done(m1, tuning) and a.runs < tuning.putt_aim_max_runs:
		if m0 * m1 < 0.0 or not is_nan(lo):
			if is_nan(lo):
				lo = p0 if m0 < 0.0 else p1
				hi = p1 if m0 < 0.0 else p0
				m_lo = minf(m0, m1)
				m_hi = maxf(m0, m1)
			else:
				if m1 < 0.0:
					lo = p1
					m_lo = m1
					m_hi *= 0.5
				else:
					hi = p1
					m_hi = m1
					m_lo *= 0.5
		var p2: float
		if not is_nan(lo):
			p2 = lo - m_lo * (hi - lo) / (m_hi - m_lo)
		else:
			var slope := (m1 - m0) / (p1 - p0)
			if slope <= 0.0:
				slope = slope_guess  # a roll back down a slope: step as on the flat
			p2 = clampf(p1 - m1 / slope, 0.0, 1.0)
		if is_equal_approx(p2, p1):
			break  # pinned at the bar's edge
		p0 = p1
		m0 = m1
		p1 = p2
		m1 = a._try(course, field, model, tuning, at, aim_deg, cup_tile, rng_seed, p1, cup, line, length)
	return a


## The putt struck at `p_power` with accuracy at the centre (the bar's own mapping).
static func launch_at(model: ShotModel, tuning: SwingTuning, field: HeightField, at: Vector2,
		aim_deg: float, p_power: float) -> ShotLaunch:
	var s := Swing.new(tuning)
	s.set_result(p_power, 0.0)
	return s.launch(model, field, model.clubs.putter(), at, aim_deg)


## Runs the putt at `p`, keeps it if it rests nearest the cup so far, returns its signed miss
## along `line` (yards past `length`, the cup's projection onto the aim; 0 when holed).
func _try(course: CourseData, field: HeightField, model: ShotModel, tuning: SwingTuning,
		at: Vector2, aim_deg: float, cup_tile: Vector2i, rng_seed: int, p: float,
		cup: Vector2, line: Vector2, length: float) -> float:
	var s := launch_at(model, tuning, field, at, aim_deg, p)
	var pred := ShotPrediction.run_launch(course, rng_seed, s, null, null, cup_tile)
	runs += 1
	var rest := Vector2(pred.rest.x, pred.rest.y)
	var d := 0.0 if pred.holed else rest.distance_to(cup)
	var better := prediction == null \
			or (pred.penalty_strokes < prediction.penalty_strokes) \
			or (pred.penalty_strokes == prediction.penalty_strokes and d < miss_yd)
	if better:
		power = p
		prediction = pred
		shot = s
		miss_yd = d
	if pred.holed:
		return 0.0
	return (rest - at).dot(line) - length


func _done(m: float, tuning: SwingTuning) -> bool:
	return (prediction != null and prediction.holed) or absf(m) <= tuning.putt_aim_tolerance_yd
