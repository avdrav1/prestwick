class_name PuttingSim
extends RefCounted
## E3-S51: /balance putting (scripts/sim.gd --table putting; docs/design.md Balance targets,
## putting). A human-like putter holes out from DISTANCES yards on a flat green and on a
## one-step contour (tests/fixtures/short_game_holes.gd: the flat green, and the sloped green
## rising one step a tile, D7's 3% felt slope), from DIRECTIONS starts round the cup.
##
## The putter reads the putt as the player does: the aim marker's pace (PuttAim, D21) and the
## break the dots show, by turning the aim by the angle the marker rests off the cup, up to
## READ_TRIES solves, keeping the solve nearest the cup. It then clicks with a Gaussian error
## in bar units (Swing.set_result), the click error of a skill-7 guest's putt (D40,
## GuestTuning.putt_power_sigma and putt_aim_sigma), so the target asks the putter's numbers
## to be fair to an ordinary hand, not a perfect one.
##
## Rows are BalanceSim's: {name, measured, target, ok, note}.

## Putt lengths, ball to cup centre, yards.
const DISTANCES: Array[float] = [1.0, 3.0, 8.0]
## docs/design.md Balance targets, putting: the share holed with the first putt, by length.
const MADE := {1.0: Vector2(0.90, 1.0), 3.0: Vector2(0.55, 0.75), 8.0: Vector2(0.15, 0.35)}
## Three putts or more from this length, at most THREE_PUTT_MAX.
const THREE_PUTT_YD: float = 8.0
const THREE_PUTT_MAX := Vector2(0.0, 0.20)
## The skill whose D40 putt sigmas are the human-like click error.
const HUMAN_SKILL: int = 7
## Starts round the cup, evenly spread from east (on the contour: uphill, then round).
const DIRECTIONS: int = 8
## Aim reads (PuttAim solves) a putt takes at most to allow for the break.
const READ_TRIES: int = 4
## A hole out gives up after this many putts (it counts as that many).
const MAX_PUTTS: int = 10
const SEED_STEP: int = 100
const EPS := 0.001

var model: ShotModel
var swing_tuning: SwingTuning
var power_sigma: float
var aim_sigma: float


## `p_model` the ShotModel to putt with (null: the defaults); the click error is a skill-7
## guest's from `guests` (null: data/guests.json), or `p_power_sigma` and `p_aim_sigma` when
## given (0 or more).
func _init(p_model: ShotModel = null, guests: GuestTuning = null, p_swing: SwingTuning = null,
		p_power_sigma: float = -1.0, p_aim_sigma: float = -1.0) -> void:
	model = p_model if p_model != null else ShotModel.new()
	swing_tuning = p_swing if p_swing != null else SwingTuning.load_default()
	var g := guests if guests != null else GuestTuning.load_default()
	power_sigma = p_power_sigma if p_power_sigma >= 0.0 else g.putt_power_sigma(HUMAN_SKILL)
	aim_sigma = p_aim_sigma if p_aim_sigma >= 0.0 else g.putt_aim_sigma(HUMAN_SKILL)


static func greens() -> Dictionary:
	return {"flat green": ShortGameHoles.flat_green(), "one-step contour": ShortGameHoles.sloped_green()}


static func _row(row_name: String, measured: float, target: Vector2, note: String = "") -> Dictionary:
	return {"name": row_name, "measured": measured, "target": target,
			"ok": measured >= target.x - EPS and measured <= target.y + EPS, "note": note}


## Every row: about `runs` hole-outs (at least one a start) from each length on each green,
## seeds from `rng_seed`.
func measure(runs: int, rng_seed: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var g := greens()
	for green_name: String in g:
		var course: CourseData = g[green_name]
		for d: float in DISTANCES:
			var r := hole_outs(course, d, runs, rng_seed)
			var note := "1 putt %.2f, 2 %.2f, 3+ %.2f, mean %.2f; noise-free plan holes %d of %d; sigma power %.3f aim %.3f" % [
					r.one, r.two, r.three, r.mean, r.plans_holed, DIRECTIONS, power_sigma, aim_sigma]
			rows.append(_row("%s: made from %d yd" % [green_name, int(d)], r.one, MADE[d], note))
			if is_equal_approx(d, THREE_PUTT_YD):
				rows.append(_row("%s: three-putts from %d yd" % [green_name, int(d)], r.three,
						THREE_PUTT_MAX, note))
	return rows


## About `n` hole-outs from `dist_yd` on `course`, spread over the DIRECTIONS starts:
## {one, two, three (3 or more) shares, mean putts, plans_holed: starts whose noise-free
## first putt holes}.
func hole_outs(course: CourseData, dist_yd: float, n: int, rng_seed: int) -> Dictionary:
	var field := HeightField.new(course, model.params)
	var cup_tile := ShortGameHoles.CUP
	var cup := field.tile_center(cup_tile)
	var each := maxi(1, ceili(float(n) / DIRECTIONS))
	var counts := [0, 0, 0]
	var total := 0
	var played := 0
	var plans_holed := 0
	for j in DIRECTIONS:
		var at := cup + Vector2.RIGHT.rotated(TAU * j / DIRECTIONS) * dist_yd
		var first := plan(course, field, at, cup_tile, rng_seed)
		if first.holed:
			plans_holed += 1
		for i in each:
			var rng := RandomNumberGenerator.new()
			rng.seed = rng_seed + SEED_STEP * (i * DIRECTIONS + j)
			var k := hole_out(course, field, at, cup_tile, first, rng)
			counts[clampi(k, 1, 3) - 1] += 1
			total += k
			played += 1
	return {"one": counts[0] / float(played), "two": counts[1] / float(played),
		"three": counts[2] / float(played), "mean": total / float(played), "plans_holed": plans_holed}


## Putts to hole out from `at`, the first struck from `first` (its plan), then each planned
## afresh from where the last rested.
func hole_out(course: CourseData, field: HeightField, at: Vector2, cup_tile: Vector2i,
		first: Dictionary, rng: RandomNumberGenerator) -> int:
	var here := at
	var p := first
	for k in range(1, MAX_PUTTS + 1):
		if k > 1:
			p = plan(course, field, here, cup_tile, int(rng.seed) + k)
		var ball := strike(course, field, here, cup_tile, p, rng, int(rng.seed) + k)
		if ball.holed:
			return k
		here = Vector2(ball.position.x, ball.position.y)
	return MAX_PUTTS


## The putt the player sets up from `at`: {power, aim_deg, holed (the noise-free putt drops)}.
func plan(course: CourseData, field: HeightField, at: Vector2, cup_tile: Vector2i,
		rng_seed: int) -> Dictionary:
	var cup := field.tile_center(cup_tile)
	var aim := rad_to_deg((cup - at).angle())
	var best: PuttAim = null
	var best_aim := aim
	var warm := -1.0
	for t in READ_TRIES:
		var a := PuttAim.solve(course, field, model, swing_tuning, at, aim, cup_tile, rng_seed, warm)
		if best == null or a.miss_yd < best.miss_yd:
			best = a
			best_aim = aim
		if a.prediction == null or a.prediction.holed:
			break
		var rest := Vector2(a.prediction.rest.x, a.prediction.rest.y)
		if rest.distance_to(at) < EPS:
			break
		aim += rad_to_deg(wrapf((cup - at).angle() - (rest - at).angle(), -PI, PI))
		warm = a.power
	return {"power": best.power, "aim_deg": best_aim,
		"holed": best.prediction != null and best.prediction.holed}


## The putt struck from `at` with the plan `p` and the click error drawn from `rng`.
func strike(course: CourseData, field: HeightField, at: Vector2, cup_tile: Vector2i,
		p: Dictionary, rng: RandomNumberGenerator, ball_seed: int) -> Ball:
	var s := Swing.new(swing_tuning)
	s.set_result(float(p.power) + rng.randfn(0.0, power_sigma), rng.randfn(0.0, aim_sigma))
	var shot := s.launch(model, field, model.clubs.putter(), at, float(p.aim_deg))
	var ball := Ball.new(course, ball_seed, model.params)
	ball.set_cup(cup_tile)
	shot.apply(ball)
	ball.run_to_rest()
	return ball
