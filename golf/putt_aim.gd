class_name PuttAim
extends RefCounted
## The putter's aim marker (D21, docs/design.md Swing, Aim marker): the putt, along the aim
## with accuracy at the centre, at the power whose roll comes to rest nearest the cup. Each
## try is a ShotPrediction, the same Ball step as the live putt (E1-S7), so a putt struck at
## `power` rests on the marker. The bar's locked power still decides the real putt; this only
## says which roll the marker and dots show. No scene, so guests (E3) can read it too.
##
## The solve is a safeguarded secant on the signed reach along the aim: how far past the
## cup's projection onto the aim the roll got before it stopped or turned back, negative when
## short. E6-S12: the reach, not the rest, because on a bank of about two steps per tile a
## harder uphill putt rolls back further, so the rest is not monotonic in power but the
## reach still is. It stops at a holed putt, at a reach inside `putt_aim_tolerance_yd` that
## rested there, or after `putt_aim_max_runs` predictions. A roll that turns back level with
## the cup without dropping is aimed again to turn a cup's radius past it, so it drops on its
## way back. When the secant pins at the bar's edge, finds a slope that is not positive,
## brackets a jump in the reach, or turns back at the cup again, it scans
## `putt_aim_scan_powers` powers spread over the bar, bisects for the roll-back edge where
## the scan shows one (E6-S12 review), and narrows a golden-section search on the distance
## to the cup around the nearest, down to `putt_aim_refine_power`. Of every putt it ran it keeps the one resting nearest the cup
## (a holed putt rests on it), a dry rest before a drop. A warm start (the last solve's
## power, while the ball stays put) usually ends it in two or three runs while the player
## sweeps the aim. E3-S51 (D49): once a putt holes, dry putts (no cup) centre its pace so the
## roll would run SwingTuning.putt_aim_past_yd past the cup, kept if that pace drops too.
##
## Spread over frames (E6-S12): `begin` sets the solve up and `advance` steps it by a budget
## of Ball ticks or time (SwingControl spends `putt_aim_frame_ticks` or `putt_aim_frame_usec`
## a frame), pausing inside a putt's roll when the budget runs out, so no frame pays for a
## whole solve. `prediction` is the best putt so far (a first answer, then refined) and
## `done` says the solve has ended.
## `solve` runs it all at once (tests, guests), with the same result as any budget.

## The power picked, 0 to 1 (the bar's share; the putter maps it along its curve, Club.putt_speed_at).
var power: float = 1.0
## The putt at `power`: what the marker and dots show. Null until the first putt rests.
var prediction: ShotPrediction
## The launch at `power`.
var shot: ShotLaunch
## How far the rest lies from the cup's centre, yards (0 when holed).
var miss_yd: float = INF
## Predictions run to find it (the solve's cost: each is one putt run to rest).
var runs: int = 0
## Ball ticks stepped so far, over every prediction.
var ticks: int = 0
## True once the solve has ended: `prediction` is final.
var done: bool = false
## The power of the first putt it ran (the warm start, or the flat-roll guess).
var start_power: float = 1.0
## True once the solve fell back to the coarse scan (a pin or a non-positive secant).
var scanned: bool = false

enum _Phase { FIRST, SECANT, SCAN, EDGE, GOLDEN, CENTRE, VERIFY }

const _GOLDEN := 0.381966
## How often `advance` reads the clock under a time cap, in Ball ticks.
const _TIME_CHECK_TICKS := 8

var _course: CourseData
var _field: HeightField
var _model: ShotModel
var _tuning: SwingTuning
var _at: Vector2
var _aim_deg: float
var _cup_tile: Vector2i
var _seed: int
var _cup: Vector2
var _line: Vector2
var _length: float
var _slope_guess: float

## The putt being run: its ball (stepped by `advance`), launch and power.
var _ball: Ball
var _ball_shot: ShotLaunch
var _ball_power: float
## How far the last putt rolled back along the aim from its furthest reach, yards.
var _back: float = 0.0
## Where the roll should turn, yards past the cup's projection: 0, or a cup's radius once a
## roll turned back level with the cup without dropping.
var _target: float = 0.0

var _phase: _Phase = _Phase.FIRST
var _p0: float
var _m0: float
var _p1: float
var _lo: float = NAN
var _hi: float = NAN
var _m_lo: float
var _m_hi: float
## Every putt run: (power, signed reach, distance to the cup with a drop counted far, how
## far it rolled back from its reach).
var _samples: Array[Vector4] = []
var _scan: PackedFloat32Array = PackedFloat32Array()
## The golden-section bracket [_ga, _gb] around its best power _gx (distance _gf).
var _ga: float
var _gb: float
var _gx: float
var _gf: float
## The roll-back edge's bracket: a putt at `_ea` stops without rolling back, one at `_eb` rolls
## back.
var _ea: float = NAN
var _eb: float = NAN
## The centring secant's last dry putt (E3-S51): its power and how far its reach missed
## putt_aim_past_yd past the cup (NAN before the first).
var _cp: float = NAN
var _cm: float = NAN


## Solves the putt from `at` (yards) along `aim_deg` toward `cup_tile` on `course`, with the
## stroke's seed `rng_seed`, all at once. `warm_power` (0 to 1) is a first guess, or below 0
## for none.
static func solve(course: CourseData, field: HeightField, model: ShotModel, tuning: SwingTuning,
		at: Vector2, aim_deg: float, cup_tile: Vector2i, rng_seed: int,
		warm_power: float = -1.0) -> PuttAim:
	var a := begin(course, field, model, tuning, at, aim_deg, cup_tile, rng_seed, warm_power)
	a.advance(-1)
	return a


## The same solve, set up but not yet run: `advance` runs it.
static func begin(course: CourseData, field: HeightField, model: ShotModel, tuning: SwingTuning,
		at: Vector2, aim_deg: float, cup_tile: Vector2i, rng_seed: int,
		warm_power: float = -1.0) -> PuttAim:
	var a := PuttAim.new()
	a._course = course
	a._field = field
	a._model = model
	a._tuning = tuning
	a._at = at
	a._aim_deg = aim_deg
	a._cup_tile = cup_tile
	a._seed = rng_seed
	a._cup = field.tile_center(cup_tile)
	# The miss is measured along the aim, against the cup's projection onto it: a straight
	# roll along the aim rests nearest the cup there, and a cup square to the aim or behind
	# it solves to 0% (E2-S20 review: along the ball-to-cup line, an aim turned off the cup
	# chased a roll of L / cos(angle) and ran yards long).
	a._line = Vector2.RIGHT.rotated(deg_to_rad(aim_deg))
	a._length = maxf((a._cup - at).dot(a._line), 0.0)
	# Yards of roll per unit of power, for the first step: a full putt's flat roll.
	a._slope_guess = model.clubs.full_putt_max_yd
	# The flat-roll guess in speed, then onto the bar along the putter's curve (D49).
	var putter := model.clubs.putter()
	var guess := putter.putt_power_for(lerpf(putter.putt_min_speed, putter.putt_max_speed,
			clampf(a._length / a._slope_guess, 0.0, 1.0)))
	var p0 := warm_power if warm_power >= 0.0 else guess
	a.start_power = clampf(p0, 0.0, 1.0)
	a._launch(a.start_power)
	return a


## Steps the solve by up to `max_ticks` Ball ticks (below 0: to its end), pausing inside a
## putt's roll when they run out, or once `max_usec` microseconds have passed (below 0: no
## time cap; E6-S12 review: a tick costs more on a busy machine, so a frame caps both).
## `until_answer` stops once the first putt has rested (a turned aim waits for it). Returns
## the ticks it stepped.
func advance(max_ticks: int, max_usec: int = -1, until_answer: bool = false) -> int:
	var used := 0
	var deadline := Time.get_ticks_usec() + max_usec if max_usec >= 0 else -1
	var out_of_time := false
	while not done and not out_of_time and (max_ticks < 0 or used < max_ticks) \
			and not (until_answer and prediction != null):
		while not _ball.is_at_rest() and (max_ticks < 0 or used < max_ticks):
			_ball.step()
			used += 1
			if deadline >= 0 and used % _TIME_CHECK_TICKS == 0 \
					and Time.get_ticks_usec() >= deadline:
				out_of_time = true
				break
		if not _ball.is_at_rest():
			break
		var next := _next(_finish_run())
		if is_nan(next):
			done = true
			_ball = null
		else:
			_launch(next)
		if deadline >= 0 and Time.get_ticks_usec() >= deadline:
			out_of_time = true
	ticks += used
	return used


## The aim this solve is for, degrees.
func get_aim_deg() -> float:
	return _aim_deg


## The putt struck at `p_power` with accuracy at the centre (the bar's own mapping).
static func launch_at(model: ShotModel, tuning: SwingTuning, field: HeightField, at: Vector2,
		aim_deg: float, p_power: float) -> ShotLaunch:
	var s := Swing.new(tuning)
	s.set_result(p_power, 0.0)
	return s.launch(model, field, model.clubs.putter(), at, aim_deg)


func _launch(p: float) -> void:
	_ball_power = p
	_ball_shot = launch_at(_model, _tuning, _field, _at, _aim_deg, p)
	# The centring runs (E3-S51) are dry: no cup, so the roll's reach shows the pace.
	_ball = ShotPrediction.launched(_course, _seed, _ball_shot, null, null,
			Ball.NO_CUP if _phase == _Phase.CENTRE else _cup_tile)


## Reads the putt just run to rest, keeps it if it rests nearest the cup so far, returns its
## signed reach along the aim: how far past the cup's projection the roll got before it
## stopped or turned back (0 when holed). Sets `_back`, how far it then rolled back.
func _finish_run() -> float:
	var pred := ShotPrediction.of_ball(_ball, _ball_shot.start)
	runs += 1
	if _phase == _Phase.CENTRE:
		return _reach(pred) - _length - _tuning.putt_aim_past_yd
	if _phase == _Phase.VERIFY:
		if pred.holed:
			power = _ball_power
			prediction = pred
			shot = _ball_shot
			miss_yd = 0.0
		return 0.0
	var rest := Vector2(pred.rest.x, pred.rest.y)
	var d := 0.0 if pred.holed else rest.distance_to(_cup)
	var better := prediction == null \
			or (pred.penalty_strokes < prediction.penalty_strokes) \
			or (pred.penalty_strokes == prediction.penalty_strokes and d < miss_yd)
	if better:
		power = _ball_power
		prediction = pred
		shot = _ball_shot
		miss_yd = d
	var m := 0.0
	_back = 0.0
	if not pred.holed:
		var along := (rest - _at).dot(_line)
		var reach := _reach(pred)
		m = reach - _length - _target
		_back = reach - along
	# A drop ranks behind every dry rest, as `better` ranks it.
	_samples.append(Vector4(_ball_power, m, d + 1000.0 * pred.penalty_strokes, _back))
	return m


## How far along the aim from the start the roll of `pred` got, yards.
func _reach(pred: ShotPrediction) -> float:
	var reach := (Vector2(pred.rest.x, pred.rest.y) - _at).dot(_line)
	for q in pred.path:
		reach = maxf(reach, (Vector2(q.x, q.y) - _at).dot(_line))
	return reach


## The next power to run after a putt at `_ball_power` reached `m` past the cup, or NAN to
## stop.
func _next(m: float) -> float:
	if _phase == _Phase.CENTRE:
		return _centre(m)
	if _phase == _Phase.VERIFY:
		return NAN
	var reached := absf(m) <= _tuning.putt_aim_tolerance_yd
	if prediction.holed and _tuning.putt_aim_past_yd > 0.0 \
			and runs + 2 <= _tuning.putt_aim_max_runs:
		# E3-S51 (D49): a holed putt is only the first pace that drops; centre it.
		_phase = _Phase.CENTRE
		return power
	if prediction.holed or (reached and _back <= _tuning.putt_aim_tolerance_yd) \
			or runs >= _tuning.putt_aim_max_runs:
		return NAN
	match _phase:
		_Phase.FIRST, _Phase.SECANT:
			if reached and _target == 0.0:
				# It turned back level with the cup without dropping: aim the turn a cup's
				# radius past it, so the ball drops on its way back, then start the secant
				# again from here.
				_target = _model.params.cup_radius
				_phase = _Phase.FIRST
				_lo = NAN
				m -= _target
			elif reached:
				return _start_scan()
			if _phase == _Phase.SECANT:
				return _secant(m)
			_p0 = _ball_power
			_m0 = m
			var p1 := clampf(_p0 - _m0 / _slope_guess, 0.0, 1.0)
			if is_equal_approx(p1, _p0):
				return _start_scan()  # at the bar's edge: out of reach, or too fast at 0%
			_phase = _Phase.SECANT
			_p1 = p1
			return p1
		_Phase.SCAN:
			return _pop_scan()
		_Phase.EDGE:
			return _edge()
		_Phase.GOLDEN:
			return _golden(_samples[_samples.size() - 1].z)
	return NAN


## One secant step from the putt at `_p1` (miss `m1`): false position (Illinois) once the
## misses change sign, else extrapolation; a pin or a slope that is not positive scans.
func _secant(m1: float) -> float:
	var bracketed := not is_nan(_lo)
	if bracketed:
		if m1 < 0.0:
			_lo = _p1
			_m_lo = m1
			_m_hi *= 0.5
		else:
			_hi = _p1
			_m_hi = m1
			_m_lo *= 0.5
	elif _m0 * m1 < 0.0:
		bracketed = true
		_lo = _p0 if _m0 < 0.0 else _p1
		_hi = _p1 if _m0 < 0.0 else _p0
		_m_lo = minf(_m0, m1)
		_m_hi = maxf(_m0, m1)
	var p2: float
	if bracketed and _hi - _lo < _tuning.putt_aim_refine_power:
		# E6-S12 review: the reach jumps across a bracket this narrow (a putt that just
		# crests a riser runs on far past one that does not), so false position would spend
		# every run left on the jump: scan instead.
		return _start_scan()
	if bracketed:
		p2 = _lo - _m_lo * (_hi - _lo) / (_m_hi - _m_lo)
	else:
		var slope := (m1 - _m0) / (_p1 - _p0)
		if slope <= 0.0:
			return _start_scan()  # a harder putt rested shorter: the miss is not monotonic
		p2 = clampf(_p1 - m1 / slope, 0.0, 1.0)
	if is_equal_approx(p2, _p1):
		if bracketed and _back <= _tuning.putt_aim_tolerance_yd:
			return NAN  # converged
		return _start_scan()  # pinned at the bar's edge, or it turns back at the cup
	_p0 = _p1
	_m0 = m1
	_p1 = p2
	return p2


## One step of the centring secant (E3-S51, D49), after the dry putt at `_ball_power` reached
## `m` yards beyond putt_aim_past_yd past the cup. A holed putt is the first pace the solve
## found that drops, often at the capture window's short edge; this aims the dry roll (no cup)
## to run putt_aim_past_yd past the cup, within putt_aim_past_tolerance_yd, then strikes that
## pace with the cup (VERIFY) and keeps it if it drops too. NAN to stop with the holed putt.
func _centre(m: float) -> float:
	var at_holed := is_nan(_cp)
	if absf(m) <= _tuning.putt_aim_past_tolerance_yd:
		if at_holed:
			return NAN  # the holed pace is already centred
		_phase = _Phase.VERIFY
		return _ball_power
	if runs + 2 > _tuning.putt_aim_max_runs:
		return NAN
	var p2: float
	if at_holed or absf(m - _cm) < 1e-6:
		p2 = _ball_power - m / _slope_guess
	else:
		var slope := (m - _cm) / (_ball_power - _cp)
		p2 = _ball_power - m / slope if slope > 0.0 else _ball_power - m / _slope_guess
	p2 = clampf(p2, 0.0, 1.0)
	if is_equal_approx(p2, _ball_power):
		return NAN
	_cp = _ball_power
	_cm = m
	return p2


## Queues the coarse scan, once per solve: `putt_aim_scan_powers` powers from 0 to 100%,
## skipping any already run.
func _start_scan() -> float:
	if scanned:
		return NAN
	scanned = true
	_phase = _Phase.SCAN
	var n := maxi(_tuning.putt_aim_scan_powers, 2)
	for i in n:
		var p := float(i) / float(n - 1)
		var seen := false
		for s in _samples:
			if absf(s.x - p) < 0.01:
				seen = true
		if not seen:
			_scan.append(p)
	return _pop_scan()


func _pop_scan() -> float:
	if _scan.is_empty():
		return _start_edge()
	var p := _scan[0]
	_scan.remove_at(0)
	return p


## After the scan (E6-S12 review): on a bank the nearest rest can be the hardest putt that
## still stops before it rolls back down, at a jump in the rest the golden search cannot see
## past (a diagonal staircase bank: 3.9 yd at 71%, 7.6 yd at 72%, while the putts around the
## 85% local minimum rest 6.6 yd off). So between the softest pair of neighbouring powers
## where a putt that stopped short without rolling back is followed by one that rolled back,
## bisect for that edge, then refine around whichever putt is nearest.
func _start_edge() -> float:
	var sorted := _sorted_samples()
	_ea = NAN
	for i in sorted.size() - 1:
		var a := sorted[i]
		var b := sorted[i + 1]
		if a.y < 0.0 and a.w <= _tuning.putt_aim_tolerance_yd \
				and b.w > _tuning.putt_aim_tolerance_yd \
				and b.x - a.x >= _tuning.putt_aim_refine_power:
			_ea = a.x
			_eb = b.x
			break
	if is_nan(_ea):
		return _start_refine()
	_phase = _Phase.EDGE
	return (_ea + _eb) * 0.5


## One bisection step toward the roll-back edge, after the probe at `_ball_power`.
func _edge() -> float:
	if _back <= _tuning.putt_aim_tolerance_yd:
		_ea = _ball_power
	else:
		_eb = _ball_power
	if _eb - _ea < _tuning.putt_aim_refine_power:
		return _start_refine()
	return (_ea + _eb) * 0.5


func _sorted_samples() -> Array[Vector4]:
	var sorted := _samples.duplicate()
	sorted.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.x < b.x)
	return sorted


## After the scan and the edge: a golden-section search on the distance to the cup between the
## neighbours of the putt resting nearest it.
func _start_refine() -> float:
	var sorted := _sorted_samples()
	var best := 0
	for i in sorted.size():
		if sorted[i].z < sorted[best].z:
			best = i
	_phase = _Phase.GOLDEN
	_gx = sorted[best].x
	_gf = sorted[best].z
	_ga = sorted[best - 1].x if best > 0 else _gx
	_gb = sorted[best + 1].x if best < sorted.size() - 1 else _gx
	return _golden_probe()


## One golden-section step after the probe at `_ball_power` rested `f` from the cup.
func _golden(f: float) -> float:
	var u := _ball_power
	if f < _gf:
		if u > _gx:
			_ga = _gx
		else:
			_gb = _gx
		_gx = u
		_gf = f
	elif u > _gx:
		_gb = u
	else:
		_ga = u
	return _golden_probe()


func _golden_probe() -> float:
	if _gb - _ga < _tuning.putt_aim_refine_power:
		return NAN
	var u := _gx + _GOLDEN * (_gb - _gx) if _gb - _gx > _gx - _ga \
			else _gx - _GOLDEN * (_gx - _ga)
	if absf(u - _gx) < 1e-4:
		return NAN
	return u
