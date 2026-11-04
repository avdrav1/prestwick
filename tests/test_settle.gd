extends GutTest
## E6-S29: settle times (D16) on the six `/course-file generate <par> hilly [water|dry]` holes
## (course/course_generator.gd). Every full club at 100% and the bar's max_power, struck along
## +x (down the hole) from the hole's lanes: rows 6 tiles either side of the centre line and
## the centre line itself, from the tee to the cup. A settle is the ticks from the first
## touchdown to rest (D16, docs/design.md Ball, Settle targets): under 480 for a ball that
## rests on green, under 600 elsewhere. By default each variant strikes the worst shots the full
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

## Known limits (E6-S29), guarded as D31's cases are, a little above the sweep's measured worst
## ([off-green guard, green guard] ticks; the D16 target where a case has none). In each the
## time on the ground after touchdown meets D16 and the overrun is in the air: the ball comes
## down on a one-step rise and bounces for up to about 4 s (par 4 water, par 5 dry), or runs a
## long way down the fairway and only then onto the green (par 4 dry). See
## test_the_guarded_cases_meet_d16_on_the_ground.
const GUARDS := {
	"par 4 dry": [OFF_GREEN_SETTLE, 560],
	"par 4 water": [OFF_GREEN_SETTLE, 620],
	"par 5 dry": [660, GREEN_SETTLE],
}

## The worst strikes the sweep found, per variant: [club, power (1.0 or "top"), start x, row].
## "off" rests off the green, "green" on it. Sweep worsts (E6-S29): off the green 575, 575,
## 580, 580, 637 and 532 ticks; on it 392, 388, 535, 596, 347 and 347.
const WORST := {
	"par 3 dry": {"off": ["7i", "top", 8, 7], "green": ["7i", 1.0, 12, 17]},
	"par 3 water": {"off": ["7i", "top", 8, 7], "green": ["5i", "top", 8, 13]},
	"par 4 dry": {"off": ["7i", "top", 34, 9], "green": ["3w", "top", 22, 13]},
	"par 4 water": {"off": ["7i", "top", 34, 9], "green": ["3w", "top", 14, 13]},
	"par 5 dry": {"off": ["driver", 1.0, 20, 10], "green": ["driver", "top", 48, 11]},
	"par 5 water": {"off": ["driver", "top", 20, 14], "green": ["driver", "top", 48, 11]},
}


## {ticks, air, on_green} for `club_id` at `power` from tile (x, row) of `c`, aimed down the
## hole: ticks from the first touchdown to rest, of them `air` in flight (bounces).
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
	var air := 0
	while ball.state == Ball.State.FLYING or ball.state == Ball.State.ROLLING:
		ball.step()
		if ball.state == Ball.State.FLYING:
			air += 1
	return {"ticks": ball.steps - landed, "air": air,
			"on_green": ball.field.surface_at(ball.position.x, ball.position.y) == Surface.Type.GREEN}


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
	var limits: Array = GUARDS.get(key, [OFF_GREEN_SETTLE, GREEN_SETTLE])
	var worst := {true: [0, ""], false: [0, ""]}
	var mine: Array = parted.call(strikes)
	for st: Array in mine:
		var r := _strike(c, st[0], st[1], st[2], st[3])
		if r.ticks > worst[r.on_green][0]:
			worst[r.on_green] = [r.ticks, "%s at %.0f%% from (%d, %d)" % [st[0], st[1] * 100.0, st[2], st[3]]]
	assert_lt(worst[false][0], limits[0], "%s: longest settle off the green %d ticks (%s)" % [
			key, worst[false][0], worst[false][1]])
	assert_lt(worst[true][0], limits[1], "%s: longest settle on the green %d ticks (%s)" % [
			key, worst[true][0], worst[true][1]])
	gut.p("%s: off the green %d ticks (%s), on it %d (%s), %d of %d strikes" % [key, worst[false][0],
			worst[false][1], worst[true][0], worst[true][1], mine.size(), strikes.size()])


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


func test_the_guarded_cases_meet_d16_on_the_ground() -> void:
	# Each GUARDS case's worst strike: its ticks on the ground after touchdown (the settle less
	# its time in the air) meet D16, so what it is over by is the bounce.
	var top: float = SwingTuning.load_default().max_power
	for key: String in GUARDS:
		var parts := key.split(" ")
		var c := CourseGenerator.generate(int(parts[1]), true, parts[2] == "water")
		for kind: String in ["off", "green"]:
			var w: Array = WORST[key][kind]
			var r := _strike(c, w[0], top if w[1] is String else float(w[1]), w[2], w[3])
			var target := GREEN_SETTLE if r.on_green else OFF_GREEN_SETTLE
			assert_lt(r.ticks - r.air, target, "%s %s: %d ticks, %d in the air" % [key, kind, r.ticks, r.air])
