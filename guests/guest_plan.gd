class_name GuestPlan
extends RefCounted
## How a guest plans one stroke (D41, docs/design.md Guests and reactions, Club and aim), with
## no scene, spread over a tick budget (Guest Ball work).
##
## Off the green: aim at the cup and take the shortest legal club (D13) whose flat total on
## fairway (GuestClubTable) times the lie reaches the cup, at power distance / (total × lie),
## at most 100%; when none reaches, the longest legal club at 100%. Each plan is checked with
## the player's marker, a ShotPrediction of a perfect swing (the same Ball step). A plan is
## unsafe when the club is blocked (ClubSet.is_blocked, D20) or the perfect swing ends in
## water or OB (a penalty, D29's unowned land included). When the straight plan is unsafe the
## same club is tried at each of `aim_offsets_deg` from the cup, and the safe one resting
## nearest the cup is kept; when none is safe the guest clubs down one club and tries again,
## straight first. If nothing is safe down to the shortest legal club, that club is played
## straight.
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
## `aim_deg` less the straight line to the cup, degrees (0, or one of aim_offsets_deg).
var offset_deg: float = 0.0
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
var _cup_aim: float = 0.0

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


## Sets up the plan for a stroke from `at` (yards) on `course` toward `cup_tile`; nothing is
## stepped until `advance`. `driver_stroke` is the hole's first stroke, from its tee marker
## (D13). `putt_tuning` is the swing tuning the putt solve uses (GuestTuning.guest_swing_tuning).
static func begin(course: CourseData, field: HeightField, model: ShotModel, tuning: GuestTuning,
		putt_tuning: SwingTuning, at: Vector2, cup_tile: Vector2i, driver_stroke: bool,
		rng_seed: int) -> GuestPlan:
	var p := GuestPlan.new()
	p._course = course
	p._field = field
	p._model = model
	p._tuning = tuning
	p._at = at
	p._cup_tile = cup_tile
	p._seed = rng_seed
	var cup := field.tile_center(cup_tile)
	p._cup_aim = rad_to_deg((cup - at).angle())
	p.aim_deg = p._cup_aim
	var lie_surface := field.surface_at(at.x, at.y)
	var legal := model.clubs.legal(lie_surface, driver_stroke)
	if legal.size() == 1 and legal[0].is_putter():
		p.club = legal[0]
		p._putt = PuttAim.begin(course, field, model, putt_tuning, at, p._cup_aim, cup_tile, rng_seed)
		return p
	var totals := GuestClubTable.totals(model)
	var mult := model.lies.measure(field, at, p._cup_aim).carry_multiplier()
	var d := at.distance_to(cup)
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
			_launch()
		while not _ball.is_at_rest() and (max_ticks < 0 or used < max_ticks):
			_ball.step()
			used += 1
		if not _ball.is_at_rest():
			break
		var p := ShotPrediction.of_ball(_ball, _shot.start)
		_ball = null
		predictions += 1
		_judge(p)
	ticks += used
	return used


func _launch() -> void:
	var aim := _cup_aim + (_tuning.aim_offsets_deg[_oi] if _oi >= 0 else 0.0)
	# A perfect swing at the planned power (Swing.launch with accuracy at the centre).
	_shot = _model.full(_field, _clubs[_ci], _powers[_ci], _at, aim)
	_ball = ShotPrediction.launched(_course, _seed, _shot, _model.params, null, _cup_tile)


func _judge(p: ShotPrediction) -> void:
	var ok := not _model.clubs.is_blocked(_shot, p) and p.penalty_strokes == 0
	if _oi < 0:
		_straight = p
		if ok:
			_choose(_ci, 0.0, p, true)
			return
	elif ok:
		var rest := Vector2(p.rest.x, p.rest.y)
		var dist := 0.0 if p.holed else rest.distance_to(_field.tile_center(_cup_tile))
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
	aim_deg = _cup_aim + offset
	prediction = p
	safe = is_safe
	done = true
