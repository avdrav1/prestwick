class_name GuestPlan
extends RefCounted
## How a guest plans one stroke (D41, docs/design.md Guests and reactions, Club and aim), with
## no scene, spread over a tick budget (Guest Ball work).
##
## Off the green: aim at the target and take the shortest legal club (D13) whose flat total on
## fairway (GuestClubTable) times the lie reaches the cup, at power distance / (total × lie),
## at most 100%; when none reaches, the longest legal club at 100%. The target is the cup, or
## on a dogleg (D54, E3-S70) its turn (D47, `turn`) while the turn is ahead of the ball (the
## ball lies `turn_ahead_yd` or more farther from the cup than the turn) and the longest legal
## club reaches it: guests play round the corner, not over it. Each plan is checked with
## the player's marker, a ShotPrediction of a perfect swing (the same Ball step). A plan is
## unsafe when the club is blocked (ClubSet.is_blocked, D20) or the perfect swing ends in
## water or OB (a penalty, D29's unowned land included). When the straight plan is unsafe the
## same club is tried at each of `aim_offsets_deg` from the target, and the safe one resting
## nearest the target is kept; when none is safe the guest clubs down one club and tries again,
## straight first. If nothing is safe down to the shortest legal club, that club is played
## straight.
##
## Shot shape (E20-S2, D75, amends D54): while a full shot aims at the turn, a guest of
## `shape_skill_min` or more (GuestTuning.shapes_for) whose corner turns `shape_turn_min_deg`
## or more also plans the shape that bends with the hole, once the straight plan is chosen:
## with the same club and power, each shape that bends the hole's way (ShotShapes.bending: the
## draw or fade, and from `strong_shape_skill_min` the hook or slice) is aimed to finish each of
## `shape_cut_shares` of its bend inside the turn, and judged by the same perfect-swing marker.
## The shaped plan that rests nearest the cup is played when it is safe and clear of the trees
## (no penalty, not blocked, never scattered), rests on a lie at least as good as the straight
## plan's (LieTable's surface multiplier), and either rests `shape_gain_yd` nearer the cup, on a
## better lie, or the straight plan was not clear (unsafe, or into the trees); else the straight
## plan stands. The shaped stroke is swung with the shape (Swing.shape), so its zone narrows.
##
## On the green: the putter, aimed straight at the cup (nobody reads break in the MVP), at
## the power PuttAim's solve finds with the guest's `guest_putt_max_runs`.
##
## Every Ball tick a prediction or the putt solve steps goes through `advance(max_ticks)`,
## which never steps more than `max_ticks`, pausing inside a prediction when they run out;
## the next call goes on from there, so the plan is the same whatever the budget.

var club: Club
## Planned power, 0 to 1 (never over 100%: overswing comes only from the swing's noise).
var power: float = 1.0
## The aim the stroke is played along, degrees.
var aim_deg: float = 0.0
## `aim_deg` less the straight line to the target, degrees (0, or one of aim_offsets_deg).
var offset_deg: float = 0.0
## True when the stroke aims at the dogleg's turn, not the cup (D54).
var at_turn: bool = false
## E20-S2 (D75): the shot shape the stroke is planned with, null for straight.
var shape: ShotShape
## E20-S2: which way the hole turns at its corner from this ball, -1 left, +1 right, 0 when it
## turns less than shape_turn_min_deg or the guest does not shape (only set while at_turn).
var turn_side: int = 0
## E20-S2: the straight plan's perfect-swing prediction when a shaped one replaced it, else null.
var straight_prediction: ShotPrediction
## Where the plan aims, yards: the cup, or the turn (at_turn).
var target: Vector2 = Vector2.ZERO
## The perfect swing's prediction for the chosen plan (the putt solve's best putt on green).
var prediction: ShotPrediction
## False when no plan was safe and the shortest club is played straight anyway.
var safe: bool = true
var done: bool = false
## Ball ticks stepped so far, and the predictions run to rest (putts included).
var ticks: int = 0
var predictions: int = 0

var _course: CourseData
var _field: HeightField
var _model: ShotModel
var _tuning: GuestTuning
var _at: Vector2
var _cup_tile: Vector2i
var _seed: int
## The straight line to the target (the cup, or the turn), degrees.
var _target_aim: float = 0.0

## Putts.
var _putt: PuttAim
## Full clubs: the clubs to try, from the club by distance down to the shortest legal one,
## each with its power.
var _clubs: Array[Club] = []
var _powers: PackedFloat32Array = PackedFloat32Array()
var _ci: int = 0
## -1 the straight plan, else the index in aim_offsets_deg being tried.
var _oi: int = -1
var _ball: Ball
var _shot: ShotLaunch
var _best: ShotPrediction
var _best_offset: float = 0.0
var _best_d: float = INF
var _straight: ShotPrediction
## E20-S2: the cup in yards; the shapes to try and the indices being tried (shape, cut share);
## the chosen straight plan's distance to the cup, lie multiplier and whether it was clear; the
## best shaped plan so far.
var _cup: Vector2 = Vector2.ZERO
var _shape_tries: Array[ShotShape] = []
var _shaping: bool = false
var _si: int = 0
var _ki: int = 0
var _straight_d: float = INF
var _straight_lie: float = 0.0
## -1 while the candidate's perfect swing is tried, else the index in shape_miss_checks.
var _mi: int = -1
## The candidate's perfect-swing prediction while its misses are tried.
var _candidate: ShotPrediction
var _candidate_d: float = INF
var _straight_clear: bool = true
var _shape_best: ShotPrediction
var _shape_best_d: float = INF
var _shape_best_aim: float = 0.0
var _shape_best_shape: ShotShape
var _shaped_aim: float = 0.0


## Sets up the plan for a stroke from `at` (yards) on `course` toward `cup_tile`; nothing is
## stepped until `advance`. `driver_stroke` is the hole's first stroke, from its tee marker
## (D13). `putt_tuning` is the swing tuning the putt solve uses (GuestTuning.guest_swing_tuning).
## `turn` is the hole's dogleg turn in yards (D47, CourseValidator.turn_point), null on a
## straight hole. `skill` is the guest's (E20-S2: it may plan a shot shape on the dogleg); below
## 0 the plan never shapes.
static func begin(course: CourseData, field: HeightField, model: ShotModel, tuning: GuestTuning,
		putt_tuning: SwingTuning, at: Vector2, cup_tile: Vector2i, driver_stroke: bool,
		rng_seed: int, turn: Variant = null, skill: int = -1) -> GuestPlan:
	var p := GuestPlan.new()
	p._course = course
	p._field = field
	p._model = model
	p._tuning = tuning
	p._at = at
	p._cup_tile = cup_tile
	p._seed = rng_seed
	var cup := field.tile_center(cup_tile)
	p._cup = cup
	p._target_aim = rad_to_deg((cup - at).angle())
	p.aim_deg = p._target_aim
	var lie_surface := field.surface_at(at.x, at.y)
	var legal := model.clubs.legal(lie_surface, driver_stroke)
	if legal.size() == 1 and legal[0].is_putter():
		p.club = legal[0]
		p._putt = PuttAim.begin(course, field, model, putt_tuning, at, p._target_aim, cup_tile, rng_seed)
		return p
	var totals := GuestClubTable.totals(model)
	p.target = cup
	if turn != null:
		var bend: Vector2 = turn
		if at.distance_to(cup) - bend.distance_to(cup) >= tuning.turn_ahead_yd:
			var bend_aim := rad_to_deg((bend - at).angle())
			var reach := float(totals.get(legal[0].id, 0.0)) \
					* model.lies.measure(field, at, bend_aim).carry_multiplier()
			if reach >= at.distance_to(bend):
				p.target = bend
				p.at_turn = true
				p._target_aim = bend_aim
				p.aim_deg = bend_aim
				if skill >= 0 and tuning.shapes_for(skill):
					p._plan_shapes(bend - at, cup - bend, skill)
	var mult := model.lies.measure(field, at, p._target_aim).carry_multiplier()
	var d := at.distance_to(p.target)
	var start := 0
	for i in range(legal.size() - 1, -1, -1):
		if float(totals.get(legal[i].id, 0.0)) * mult >= d:
			start = i
			break
	for i in range(start, legal.size()):
		var reach := float(totals.get(legal[i].id, 0.0)) * mult
		p._clubs.append(legal[i])
		p._powers.append(clampf(d / reach, 0.0, 1.0) if reach > 0.0 else 1.0)
	p.club = p._clubs[0]
	p.power = p._powers[0]
	return p


## E20-S2: the shapes to try when the corner turns enough: those bending the hole's way, the
## gentlest only below strong_shape_skill_min.
func _plan_shapes(leg_in: Vector2, leg_out: Vector2, skill: int) -> void:
	var turn_deg := rad_to_deg(leg_in.angle_to(leg_out))
	if absf(turn_deg) < _tuning.shape_turn_min_deg or _tuning.shape_cut_shares.is_empty():
		return
	turn_side = 1 if turn_deg > 0.0 else -1
	for s: ShotShape in _model.shapes.bending(turn_side):
		if _shape_tries.is_empty() or _tuning.shapes_for(skill, true):
			_shape_tries.append(s)


func is_putt() -> bool:
	return _putt != null


## Steps the plan by at most `max_ticks` Ball ticks (below 0: to its end). Returns the ticks
## it stepped.
func advance(max_ticks: int) -> int:
	var used := 0
	while not done and (max_ticks < 0 or used < max_ticks):
		if _putt != null:
			var before := _putt.runs
			used += _putt.advance(max_ticks - used if max_ticks >= 0 else -1)
			predictions += _putt.runs - before
			if _putt.done:
				power = _putt.power
				prediction = _putt.prediction
				done = true
			continue
		if _ball == null:
			if _shaping:
				_pass_hopeless()
				if done:
					break
			_launch()
		used += _ball.run(max_ticks - used if max_ticks >= 0 else -1)
		if not _ball.is_at_rest():
			break
		var p := ShotPrediction.of_ball(_ball, _shot.start)
		_ball = null
		predictions += 1
		_judge(p)
	ticks += used
	return used


func _launch() -> void:
	if _shaping:
		var s := _shape_tries[_si]
		_shaped_aim = _shape_aim(s, _tuning.shape_cut_shares[_ki])
		var aim := _shaped_aim
		var pw := power
		if _mi >= 0:
			# A miss of the candidate: short, or turned to the inside of the corner.
			var miss: Vector2 = _tuning.shape_miss_checks[_mi]
			pw = power * miss.x
			aim += turn_side * miss.y
		_shot = _model.full(_field, club, pw, _at, aim, 0.0, true, s)
		_ball = ShotPrediction.launched(_course, _seed, _shot, _model.params, null, _cup_tile)
		return
	var aim := _target_aim + (_tuning.aim_offsets_deg[_oi] if _oi >= 0 else 0.0)
	# A perfect swing at the planned power (Swing.launch with accuracy at the centre).
	_shot = _model.full(_field, _clubs[_ci], _powers[_ci], _at, aim)
	_ball = ShotPrediction.launched(_course, _seed, _shot, _model.params, null, _cup_tile)


## E20-S2: the aim that finishes shape `s` (at the planned club and power) `cut` of its bend
## inside the line to the turn: a shaped ball lands `1 - start_share` of its bend to the bend's
## side of its aim (ShotShapes.flight), and the bend shrinks with the power as the carry does.
func _shape_aim(s: ShotShape, cut: float) -> float:
	var bend := ShotShapes.bend_of(club, s) * power
	var d := maxf(_at.distance_to(target), 1.0)
	var inside := (cut - (1.0 - _model.shapes.start_share)) * bend
	return _target_aim + turn_side * rad_to_deg(atan2(inside, d))


## E20-S2: skips, with no Ball work, each shaped candidate whose perfect swing or any of its
## misses would land off the fairway and green (each landing found from the flight's own numbers:
## along the aim at the target carry, `1 - start_share` of the bend at that power to the bend's
## side), so a corner no shape can use costs a guest no predictions. Ends the plan when none is
## left.
func _pass_hopeless() -> void:
	while not done and _mi < 0:
		var s := _shape_tries[_si]
		var aim := _shape_aim(s, _tuning.shape_cut_shares[_ki])
		var ok := _lands_clear(s, aim, power)
		for m: Vector2 in _tuning.shape_miss_checks:
			ok = ok and _lands_clear(s, aim + turn_side * m.y, power * m.x)
		if ok:
			return
		_next_candidate()


func _lands_clear(s: ShotShape, aim_deg_: float, pw: float) -> bool:
	var aim := deg_to_rad(aim_deg_)
	var carry := club.carry_yd * pw * _model.lies.measure(_field, _at, aim_deg_).carry_multiplier()
	var side := (1.0 - _model.shapes.start_share) * ShotShapes.bend_of(club, s) * pw
	var land := _at + Vector2.from_angle(aim) * carry \
			+ Vector2.from_angle(aim + PI * 0.5) * (turn_side * side)
	var surface := _field.surface_at(land.x, land.y)
	return surface == Surface.Type.FAIRWAY or surface == Surface.Type.GREEN


## E20-S2: the surface multiplier of the lie a prediction rests on (a penalty's drop counts as
## no lie at all).
func _lie_at(p: ShotPrediction) -> float:
	if p.penalty_strokes > 0:
		return 0.0
	return _model.lies.multiplier_for(_field.surface_at(p.rest.x, p.rest.y))


func _cup_distance(p: ShotPrediction) -> float:
	return 0.0 if p.holed else Vector2(p.rest.x, p.rest.y).distance_to(_cup)


## E20-S2: one shaped prediction judged against the straight plan: a candidate's perfect swing,
## then (when it would be the best so far) each of its misses; the best kept.
func _judge_shaped(p: ShotPrediction) -> void:
	var clear := not _model.clubs.is_blocked(_shot, p) and p.penalty_strokes == 0 and not p.scattered
	var lie := _lie_at(p)
	if _mi < 0:
		var d := _cup_distance(p)
		if clear and lie >= _straight_lie - 1e-6 and d < _shape_best_d and (not _straight_clear
				or lie > _straight_lie + 1e-6 or _straight_d - d >= _tuning.shape_gain_yd):
			_candidate = p
			_candidate_d = d
			if not _tuning.shape_miss_checks.is_empty():
				_mi = 0
				return
			_keep_candidate()
	elif not clear or lie < _straight_lie - 1e-6:
		_mi = -1  # a miss of it is worse off than the straight plan: not this one
	else:
		_mi += 1
		if _mi < _tuning.shape_miss_checks.size():
			return
		_mi = -1
		_keep_candidate()
	_next_candidate()


func _keep_candidate() -> void:
	_shape_best = _candidate
	_shape_best_d = _candidate_d
	_shape_best_aim = _shaped_aim
	_shape_best_shape = _shape_tries[_si]


## The first candidate that passes is played (gentlest shape first, cut shares in their order),
## so a guest spends no more predictions once it has its line.
func _next_candidate() -> void:
	_ki += 1
	if _ki >= _tuning.shape_cut_shares.size():
		_ki = 0
		_si += 1
	if _shape_best == null and _si < _shape_tries.size():
		return
	if _shape_best != null:
		straight_prediction = prediction
		shape = _shape_best_shape
		aim_deg = _shape_best_aim
		offset_deg = aim_deg - _target_aim
		prediction = _shape_best
		safe = true
	done = true


func _judge(p: ShotPrediction) -> void:
	if _shaping:
		_judge_shaped(p)
		return
	var ok := not _model.clubs.is_blocked(_shot, p) and p.penalty_strokes == 0
	if _oi < 0:
		_straight = p
		if ok:
			_choose(_ci, 0.0, p, true)
			return
	elif ok:
		var rest := Vector2(p.rest.x, p.rest.y)
		var dist := 0.0 if p.holed else rest.distance_to(target)
		if dist < _best_d:
			_best = p
			_best_d = dist
			_best_offset = _tuning.aim_offsets_deg[_oi]
	_oi += 1
	if _oi < _tuning.aim_offsets_deg.size():
		return
	if _best != null:
		_choose(_ci, _best_offset, _best, true)
		return
	if _ci + 1 < _clubs.size():
		_ci += 1
		_oi = -1
		return
	_choose(_ci, 0.0, _straight, false)


func _choose(i: int, offset: float, p: ShotPrediction, is_safe: bool) -> void:
	club = _clubs[i]
	power = _powers[i]
	offset_deg = offset
	aim_deg = _target_aim + offset
	prediction = p
	safe = is_safe
	if not _shape_tries.is_empty() and not club.is_putter():
		# E20-S2: try the shapes with this club and power before the plan is done.
		_shaping = true
		_straight_d = _cup_distance(p)
		_straight_lie = _lie_at(p)
		_straight_clear = is_safe and not p.scattered
		return
	done = true
