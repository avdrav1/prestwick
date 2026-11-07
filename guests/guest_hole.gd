class_name GuestHole
extends RefCounted
## One guest playing one hole (E3-S3, D40, D41; docs/design.md Guests and reactions), with no
## scene: the same shot model, bar and Ball as the player, with skill as click noise.
##
## A stroke goes PLANNING (GuestPlan: club-pick predictions or the putt solve) -> READY (the
## plan is made; E3-S4 decides when the guest reaches its ball and swings) -> FLYING (its own
## Ball, stepped to rest) -> PLANNING the next stroke, until the hole is FINISHED: holed, or
## picked up at the player's stroke limit (D12, HoleScore). The ball obeys D29 like the
## player's: a rest on unowned land is OB, dropped with a penalty stroke by the Ball.
##
## The swing (D40): `Swing.set_result(planned power + power error, accuracy error)`, each error
## Gaussian in bar units with the sigma GuestTuning gives the guest's skill, so a shank is an
## accuracy outside the zone (30 degrees, half power) exactly as for the player.
##
## Ball work (E3-S1): every tick stepped (predictions, the putt solve, the guest's own ball)
## goes through `advance(max_ticks)`, which never steps more than `max_ticks` in one call; the
## work goes on next call from where it stopped. Every random number comes from `rng_seed`,
## so the same seed plays the same hole whatever the budget. `rng_seed` is per guest per hole
## (`hole_seed`): one guest's holes built from one seed would replay the same click noise and
## the same Ball seeds on every hole.
##
## Holes are edited by copy (CourseBuilder: `_place`, close and renumber call `set_holes`), so
## the `hole` a guest was given goes stale when the builder moves its tee or cup, changes its
## par, closes, removes or renumbers it. `hole_still_stands` reports that; E3-S4 checks it
## before each plan and strike and ends the guest's hole when it is false (GuestHole itself
## never stops on its own).
##
## Cost outside the budget: the first plan of a run measures GuestClubTable (about 80 to 110
## ms headless, once per bag); E3-S4 warms it (`GuestClubTable.warm`) before guests tick.
## `play_out` runs whole simulated seconds in one call: for tests and headless runs only. In
## Play, E3-S4 slices each second's budget over that second's frames with `advance`.
##
## Off-screen shortcut: a ball nobody watches runs to rest in as few calls as the budget
## allows, skipping the drawn flight and jumping to where it rests; `flight_ticks` steps it a
## few ticks a call instead. The Ball is the same in both, so the result is the same for the
## same seed (tests/test_guest_shot.gd). The view (E3-S5, scenes/guest_view.gd) never steps a
## guest's ball: the sim runs every ball the same way whether it is watched or not, and the
## view replays the stroke's recorded path (`stroke_path`) when the guest is on screen, so
## what the camera looks at never changes the day.

enum State { PLANNING, READY, FLYING, FINISHED }

var course: CourseData
var hole: HoleData
var skill: int
var tuning: GuestTuning
var model: ShotModel
var field: HeightField
var score: HoleScore
var state: State = State.PLANNING
## Where the ball lies (or flies), yards.
var ball_at: Vector3 = Vector3.ZERO
## The plan for the next stroke (null while the ball flies).
var plan: GuestPlan
## The ball in flight (null at rest).
var ball: Ball
## The path of the last stroke that came to rest (Ball.path: one point a tick, ending where
## it stopped, or where it went into a hazard), for the view's replay (E3-S5).
var last_path: PackedVector3Array = PackedVector3Array()
## One entry per stroke struck (StrokeRecord).
var strokes: Array[StrokeRecord] = []
## Ball ticks stepped: in all, on plans, on the guest's own balls.
var ticks: int = 0
var plan_ticks: int = 0
var ball_ticks: int = 0
## The most ticks any one `advance` call stepped, and (play_out) any one simulated second.
var max_call_ticks: int = 0
var max_second_ticks: int = 0
## The hole's slot in `course.holes` when the guest started it, -1 when unknown (GuestBrain
## sets it; E3-S17 review: the feed files the reaction under it, and drops it when Build
## edits that slot while the guest plays it).
var slot: int = -1

var _rng := RandomNumberGenerator.new()
var _seed: int
## The hole as it stood when the guest started it (hole_still_stands).
var _number: int
var _par: int
var _tee: Vector2i
var _cup: Vector2i
var _swing_tuning: SwingTuning
var _putt_tuning: SwingTuning


## What one struck stroke was and did.
class StrokeRecord:
	var club_id: String = ""
	var planned_power: float = 0.0
	var aim_deg: float = 0.0
	## The plan's aim less the straight line to the cup (0, or one of aim_offsets_deg).
	var offset_deg: float = 0.0
	var safe_plan: bool = true
	## The swing's locked power and accuracy, noise included (Swing.set_result).
	var power: float = 0.0
	var accuracy: float = 0.0
	var shank: bool = false
	var start: Vector3 = Vector3.ZERO
	var rest: Vector3 = Vector3.ZERO
	var penalty_strokes: int = 0
	var hazard: Ball.Hazard = Ball.Hazard.NONE
	## Where the ball stopped in a hazard, before the drop.
	var hazard_position: Vector3 = Vector3.ZERO
	var holed: bool = false
	## Ticks its plan and its own ball took.
	var plan_ticks: int = 0
	var ball_ticks: int = 0


## A guest of `skill` (GuestTuning skill_min to skill_max) on `hole` of `course`, its ball
## on the tee marker's centre. `rng_seed` draws its noise and seeds each stroke's Ball: pass
## `hole_seed(guest seed, hole number)`, never one seed for all of a guest's holes.
func _init(p_course: CourseData, p_hole: HoleData, p_skill: int, rng_seed: int,
		p_tuning: GuestTuning = null, p_model: ShotModel = null,
		p_swing_tuning: SwingTuning = null) -> void:
	course = p_course
	hole = p_hole
	tuning = p_tuning if p_tuning != null else GuestTuning.load_default()
	skill = clampi(p_skill, tuning.skill_min, tuning.skill_max)
	model = p_model if p_model != null else ShotModel.new()
	_swing_tuning = p_swing_tuning if p_swing_tuning != null else SwingTuning.load_default()
	_putt_tuning = tuning.guest_swing_tuning(_swing_tuning)
	field = HeightField.new(course, model.params)
	score = HoleScore.new(hole.par)
	_seed = rng_seed
	_rng.seed = rng_seed
	_number = hole.number
	_par = hole.par
	_tee = hole.tee
	_cup = hole.cup
	var tee := field.tile_center(hole.tee)
	ball_at = Vector3(tee.x, tee.y, field.height_at(tee.x, tee.y))
	_begin_plan()


## The seed of one guest's play of hole `hole_number` (1 to 9): distinct for every guest seed
## and hole, so two holes of one guest never share click noise or Ball seeds.
static func hole_seed(guest_seed: int, hole_number: int) -> int:
	return guest_seed * 16 + hole_number


func is_finished() -> bool:
	return state == State.FINISHED


## True while the course still holds this guest's hole as it started it: the same number,
## open, with the same tee, cup and par. False once the builder has moved, re-parred, closed,
## removed or renumbered it (holes are edited by copy, so `hole` itself never changes).
func hole_still_stands() -> bool:
	for h: HoleData in course.holes:
		if h.number == _number:
			return h.open and h.tee == _tee and h.cup == _cup and h.par == _par
	return false


## E3-S49: Build edited the terrain before this guest struck: its ball goes back on the tee
## marker at the tee's height now and the first stroke is planned afresh (HeightField and the
## plan's predictions read the live CourseData, so the new plan sees the new terrain). Only
## before the first stroke (a struck hole judges the old terrain and is dropped instead).
func replan() -> void:
	assert(strokes.is_empty() and state != State.FLYING, "replan only before the first stroke")
	var tee := field.tile_center(hole.tee)
	ball_at = Vector3(tee.x, tee.y, field.height_at(tee.x, tee.y))
	_begin_plan()


## Spends up to `max_ticks` Ball ticks (below 0: no limit) on whatever work there is: the plan
## of the next stroke, or the ball in flight. `flight_ticks` (below 0: no limit) caps the
## ticks the ball in flight gets this call, for a view drawing it (on screen); off screen it
## is left at -1 and the ball jumps to its rest. Does nothing while READY (waiting for
## `strike`) or FINISHED. Returns the ticks it stepped, never more than `max_ticks`.
func advance(max_ticks: int, flight_ticks: int = -1) -> int:
	var used := 0
	while max_ticks < 0 or used < max_ticks:
		var left := max_ticks - used if max_ticks >= 0 else -1
		if state == State.PLANNING:
			var n := plan.advance(left)
			used += n
			plan_ticks += n
			if plan.done:
				state = State.READY
			else:
				break
		elif state == State.FLYING:
			var cap := left
			if flight_ticks >= 0:
				cap = flight_ticks if cap < 0 else mini(cap, flight_ticks)
			var n := 0
			while not ball.is_at_rest() and (cap < 0 or n < cap):
				ball.step()
				n += 1
			used += n
			ball_ticks += n
			strokes[-1].ball_ticks += n
			ball_at = ball.position if ball.penalty_strokes == 0 else ball.hazard_position
			if ball.is_at_rest():
				_ball_rested()
			else:
				break
			if flight_ticks >= 0:
				break  # a drawn flight ends its call at the rest, as a frame would
		else:
			break
	ticks += used
	max_call_ticks = maxi(max_call_ticks, used)
	return used


## Swings the planned stroke (state READY): the bar with this guest's click noise, then its
## own Ball, launched and not yet stepped (FLYING).
func strike() -> void:
	assert(state == State.READY, "strike needs a finished plan")
	var r := StrokeRecord.new()
	r.club_id = plan.club.id
	r.planned_power = plan.power
	r.aim_deg = plan.aim_deg
	r.offset_deg = plan.offset_deg
	r.safe_plan = plan.safe
	r.plan_ticks = plan.ticks
	r.start = ball_at
	var swing := Swing.new(_swing_tuning)
	if plan.is_putt():
		var p_err := _rng.randfn(0.0, tuning.putt_power_sigma(skill))
		var a_err := _rng.randfn(0.0, tuning.putt_aim_sigma(skill))
		swing.set_result(plan.power + p_err, a_err)
	else:
		var sigma := tuning.full_sigma(skill)
		var p_err := _rng.randfn(0.0, sigma)
		var a_err := _rng.randfn(0.0, sigma)
		# A short chip's few % plus the error would often lock 0% and whiff: floor it.
		swing.set_result(maxf(plan.power + p_err, tuning.guest_min_power), a_err)
	r.power = swing.power
	r.accuracy = swing.accuracy
	r.shank = swing.is_shank()
	var shot := swing.launch(model, field, plan.club, Vector2(ball_at.x, ball_at.y), plan.aim_deg)
	ball = Ball.new(course, stroke_seed(strokes.size() + 1), model.params)
	ball.record_path = true
	ball.set_cup(hole.cup)
	shot.apply(ball)
	strokes.append(r)
	plan = null
	state = State.FLYING


## The Ball seed of stroke `n` (1 for the first), from the guest's seed: the plan's
## predictions use the same seed as the stroke they plan, as the player's marker does.
func stroke_seed(n: int) -> int:
	return _seed * 1000 + n


## Plays the hole out with no scene: each simulated second gets `ticks_per_s` Ball ticks
## (below 0 or omitted: GuestTuning.guest_ticks_per_s), and a plan that is READY is struck at
## once (E3-S4 adds walking and turns). Returns the simulated seconds it took.
func play_out(ticks_per_s: int = 0, flight_ticks: int = -1) -> int:
	assert(flight_ticks != 0, "a drawn flight steps at least one tick a call")
	var budget := ticks_per_s if ticks_per_s > 0 else tuning.guest_ticks_per_s
	var seconds := 0
	while not is_finished():
		seconds += 1
		var used := 0
		while used < budget and not is_finished():
			var n := advance(budget - used, flight_ticks)
			used += n
			if state == State.READY:
				strike()
			elif n == 0:
				break
		max_second_ticks = maxi(max_second_ticks, used)
	return seconds


## The recorded path of the latest stroke so far: the ball in flight's (growing) path, or the
## path of the last one at rest. Empty before the first stroke.
func stroke_path() -> PackedVector3Array:
	return ball.path if ball != null else last_path


func _ball_rested() -> void:
	var r := strokes[-1]
	last_path = ball.path
	r.rest = ball.position
	r.penalty_strokes = ball.penalty_strokes
	r.hazard = ball.hazard
	r.hazard_position = ball.hazard_position
	r.holed = ball.holed
	ball_at = ball.position
	score.record_stroke(ball.penalty_strokes, ball.holed)
	ball = null
	if score.is_finished():
		state = State.FINISHED
		return
	_begin_plan()


func _begin_plan() -> void:
	plan = GuestPlan.begin(course, field, model, tuning, _putt_tuning,
			Vector2(ball_at.x, ball_at.y), hole.cup, strokes.is_empty(),
			stroke_seed(strokes.size() + 1))
	state = State.PLANNING
