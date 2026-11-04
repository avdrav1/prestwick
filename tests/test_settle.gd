extends GutTest
## E6-S29: settle times (D16) on the six `/course-file generate <par> hilly [water|dry]` holes
## (course/course_generator.gd). Every full club at 100% and the bar's max_power, struck along
## +x (down the hole) from the hole's lanes: rows 6 tiles either side of the centre line and
## the centre line itself, from the tee to the cup. D16 as D36 reads it (docs/design.md Ball,
## Settle targets): every strike rests under 600 ticks from its first touchdown, and one that
## rests on the green also rests under 480 ticks from reaching it (from the later of touchdown
## and the first tick over a green tile). By default each variant strikes the worst shots the full
## sweep found; `scripts/run_tests.sh --full` (tests/fixtures/sweep.gd) runs the sweep: every
## lane row from -6 to 6 and a start every 2 tiles, each variant in parts at once (E6-S30;
## each variant's test passes `Sweep.part` in, which is how run_tests.sh finds it). No
## class-typed members, and clubs are reached through a ClubSet local, so the exit-leak case
## in scripts/run_tests.sh does not apply.

const GREEN_SETTLE := 480
const OFF_GREEN_SETTLE := 600
## Lane rows across the hole, in tiles off the centre line (the fairway is 2 either side).
const LANE_HALF_WIDTH := 6
## Tiles between sweep starts along a lane.
const SWEEP_STRIDE := 2

## No hilly case is a known limit since D36 (E6-S33). Before it the green target counted from
## the first touchdown, so the par 4 3-wood at 110% from (22, 13), about 7 s down the fairway
## and then 1.8 s on the green (535 ticks), was guarded at 560 as a case beside D31's. Counted
## from reaching the green it takes 106 ticks there, inside 480. Par 5 dry's worst off the
## green (593 against 600) has the least margin: a tuning change that moves fairway rolls on
## hills should re-run `--full` here.

## The worst strikes the sweep found, per variant: [club, power (1.0 or "top"), start x, row].
## "off" rests off the green, "green" on it (the worst from touchdown among balls resting there). Sweep worsts (E6-S34, with the bounce budget): off
## the green 575, 575, 580, 580, 593 and 491 ticks; on it 392, 388, 535, 535, 347 and 347
## (E6-S29, before it: off 575, 575, 580, 580, 637 and 532; on 392, 388, 535, 596, 347 and 347).
const WORST := {
	"par 3 dry": {"off": ["7i", "top", 8, 7], "green": ["7i", 1.0, 12, 17]},
	"par 3 water": {"off": ["7i", "top", 8, 7], "green": ["5i", "top", 8, 13]},
	"par 4 dry": {"off": ["7i", "top", 34, 9], "green": ["3w", "top", 22, 13]},
	"par 4 water": {"off": ["7i", "top", 34, 9], "green": ["3w", "top", 22, 13]},
	"par 5 dry": {"off": ["7i", "top", 48, 9], "green": ["driver", "top", 48, 11]},
	"par 5 water": {"off": ["3w", "top", 36, 13], "green": ["driver", "top", 48, 11]},
}


## {ticks, air, on_green, green_ticks} for `club_id` at `power` from tile (x, row) of `c`,
## aimed down the hole: ticks from the first touchdown to rest, of them `air` in flight
## (bounces); `green_ticks` from reaching the green (the later of touchdown and the first tick
## over a green tile) to rest, or -1 if the ball rests off the green.
func _strike(c: CourseData, club_id: String, power: float, x: int, row: int) -> Dictionary:
	var model := ShotModel.new()
	var ball := Ball.new(c, 1)
	ball.set_cup(c.holes[0].cup)
	var at := Vector2((x + 0.5) * 5.0, (row + 0.5) * 5.0)
	# Through a ClubSet local: model.clubs.club(...) in one call is the exit-leak case in
	# scripts/run_tests.sh.
	var clubs: ClubSet = model.clubs
	model.full(ball.field, clubs.club(club_id), power, at, 0.0).apply(ball)
	while not ball.has_landed and not ball.is_at_rest():
		ball.step()
	var landed := ball.steps
	var reached := -1
	if _over_green(ball):
		reached = landed
	var air := 0
	while ball.state == Ball.State.FLYING or ball.state == Ball.State.ROLLING:
		ball.step()
		if ball.state == Ball.State.FLYING:
			air += 1
		if reached < 0 and _over_green(ball):
			reached = ball.steps
	var on_green := _over_green(ball)
	return {"ticks": ball.steps - landed, "air": air, "on_green": on_green,
			"green_ticks": ball.steps - reached if on_green else -1}


func _over_green(ball: Ball) -> bool:
	return ball.field.surface_at(ball.position.x, ball.position.y) == Surface.Type.GREEN


## `parted` picks this run's part of the strikes (Sweep.part).
func _check_variant(par: int, water: bool, parted: Callable) -> void:
	var key := "par %d %s" % [par, "water" if water else "dry"]
	var c := CourseGenerator.generate(par, true, water)
	assert_not_null(c, key)
	if c == null:
		return
	var clubs: ClubSet = ShotModel.new().clubs
	var top: float = SwingTuning.load_default().max_power
	var strikes: Array = []
	if Sweep.full():
		var tee: Vector2i = c.holes[0].tee
		var cup: Vector2i = c.holes[0].cup
		for row: int in range(tee.y - LANE_HALF_WIDTH, tee.y + LANE_HALF_WIDTH + 1):
			for x: int in range(tee.x, cup.x, SWEEP_STRIDE):
				for club: Club in clubs.clubs:
					if club.is_putter():
						continue
					for power: float in [1.0, top]:
						strikes.append([club.id, power, x, row])
	else:
		for kind: String in ["off", "green"]:
			var w: Array = WORST[key][kind]
			strikes.append([w[0], top if w[1] is String else float(w[1]), w[2], w[3]])
	# worst[true] / worst[false]: from touchdown, resting on / off the green; worst["reach"]:
	# from reaching the green, among balls resting on it.
	var worst := {true: [0, ""], false: [0, ""], "reach": [0, ""]}
	var mine: Array = parted.call(strikes)
	for st: Array in mine:
		var r := _strike(c, st[0], st[1], st[2], st[3])
		var what := "%s at %.0f%% from (%d, %d)" % [st[0], st[1] * 100.0, st[2], st[3]]
		if r.ticks > worst[r.on_green][0]:
			worst[r.on_green] = [r.ticks, what]
		if r.green_ticks > worst["reach"][0]:
			worst["reach"] = [r.green_ticks, what]
	assert_lt(worst[false][0], OFF_GREEN_SETTLE, "%s: longest settle off the green %d ticks (%s)" % [
			key, worst[false][0], worst[false][1]])
	assert_lt(worst[true][0], OFF_GREEN_SETTLE, "%s: longest settle from touchdown onto the green %d ticks (%s)" % [
			key, worst[true][0], worst[true][1]])
	assert_lt(worst["reach"][0], GREEN_SETTLE, "%s: longest settle from reaching the green %d ticks (%s)" % [
			key, worst["reach"][0], worst["reach"][1]])
	gut.p("%s: off the green %d ticks (%s), onto it %d (%s), on it from reaching it %d (%s), %d of %d strikes" % [
			key, worst[false][0], worst[false][1], worst[true][0], worst[true][1], worst["reach"][0],
			worst["reach"][1], mine.size(), strikes.size()])


func test_par_3_dry_hilly_settles_inside_d16() -> void:
	_check_variant(3, false, Sweep.part)


func test_par_3_water_hilly_settles_inside_d16() -> void:
	_check_variant(3, true, Sweep.part)


func test_par_4_dry_hilly_settles_inside_d16() -> void:
	_check_variant(4, false, Sweep.part)


func test_par_4_water_hilly_settles_inside_d16() -> void:
	_check_variant(4, true, Sweep.part)


func test_par_5_dry_hilly_settles_inside_d16() -> void:
	_check_variant(5, false, Sweep.part)


func test_par_5_water_hilly_settles_inside_d16() -> void:
	_check_variant(5, true, Sweep.part)



func test_the_long_fairway_roll_onto_the_par_4_green_meets_both_clocks() -> void:
	# The case D36 settled: over 480 from touchdown, inside 600 from it and inside 480 from
	# reaching the green.
	var top: float = SwingTuning.load_default().max_power
	var c := CourseGenerator.generate(4, true, false)
	var r := _strike(c, "3w", top, 22, 13)
	assert_true(r.on_green, "the 3-wood at 110% from (22, 13) rests on the green")
	assert_gt(r.ticks, GREEN_SETTLE, "it is the case the old reading failed: %d ticks from touchdown" % r.ticks)
	assert_lt(r.ticks, OFF_GREEN_SETTLE, "%d ticks from touchdown" % r.ticks)
	assert_lt(r.green_ticks, GREEN_SETTLE, "%d ticks from reaching the green" % r.green_ticks)
