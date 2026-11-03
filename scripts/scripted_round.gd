class_name ScriptedRound
extends RefCounted
## A scripted player for the /playtest smoke (scripts/playtest.gd, E2 stage) and
## tests/test_round_flow.gd (E2-S8): it plans each stroke on a SwingControl and clicks the
## real three-click swing. Not a guest (E3-S3 gives guests their own swing with skill as
## noise): it reads the future through ShotPrediction, so it is only for checks.
##
## A plan aims at the cup and holds the bar for a whole number of 1/60 s ticks up to the power
## click and the same number back down to the accuracy click, so the accuracy is the centre.
## Its prediction mirrors that swing exactly (same tuning, bar speed, seed and cup), so the
## live ball follows it tick for tick.

## Full-club powers tried, in ticks of the bar (72 is 100% at bar speed 1.0).
const FULL_TICKS: Array[int] = [72, 64, 56, 48, 40, 32, 24]


class Plan:
	var club: Club
	var aim_deg: float = 0.0
	## Bar ticks up to the power click, and back down to the accuracy click.
	var ticks: int = 0
	var prediction: ShotPrediction


## The stroke to play next from where `sc`'s ball rests: aimed at the cup, the legal club
## and power whose predicted rest is nearest the cup (a holed putt first, a drop never).
## With `putts_hole_only` a full club's stroke that would hole is passed over, so the player
## holes out only with the putter (E2-S13: a test that must not hang on a perfect chip-in).
static func plan(sc: SwingControl, putts_hole_only: bool = false) -> Plan:
	var best: Plan = null
	var best_d := INF
	var cup := sc.cup_tile()
	var target := sc.field.tile_center(cup) if cup != Ball.NO_CUP else sc.ball_at
	var aim := fposmod(rad_to_deg((target - sc.ball_at).angle()), 360.0)
	for c: Club in sc.legal:
		var options: Array[int] = []
		if c.is_putter():
			options.assign(range(1, ticks_for(sc, 1.0) + 1))
		else:
			for t: int in FULL_TICKS:
				options.append(t)
		for t: int in options:
			var p := Plan.new()
			p.club = c
			p.aim_deg = aim
			p.ticks = t
			p.prediction = predict(sc, c, aim, t)
			if p.prediction.holed:
				if putts_hole_only and not c.is_putter():
					continue
				return p
			if p.prediction.penalty_strokes > 0:
				continue
			var d := Vector2(p.prediction.rest.x, p.prediction.rest.y).distance_to(target)
			if d < best_d:
				best_d = d
				best = p
	return best


## Bar ticks to reach `power` at the control's bar speed.
static func ticks_for(sc: SwingControl, power: float) -> int:
	return roundi(power / (sc.swing.rate() * Ball.DT))


## What the swing `ticks` up and down with `club`, aimed `aim_deg`, will do: the same Swing
## the control runs, ticked the same way.
static func predict(sc: SwingControl, club: Club, aim_deg: float, ticks: int) -> ShotPrediction:
	var s := Swing.new(sc.tuning)
	s.bar_speed = sc.swing.bar_speed
	s.click()
	for i in ticks:
		s.tick(Ball.DT)
	s.click()
	for i in ticks:
		s.tick(Ball.DT)
	s.click()
	var shot := s.launch(sc.model, sc.field, club, sc.ball_at, aim_deg)
	return ShotPrediction.run_launch(sc.course, sc.next_seed(), shot, null, null, sc.cup_tile())


## Plays `p` on `sc`: picks the club, sets the aim, and clicks the swing three times with the
## bar advanced in 1/60 s ticks between them. The ball is then in flight in ShotView.
static func swing(sc: SwingControl, p: Plan) -> void:
	sc.select_club(p.club)
	sc.aim_deg = p.aim_deg
	sc.press()
	for i in p.ticks:
		sc.advance(Ball.DT)
	sc.press()
	for i in p.ticks:
		sc.advance(Ball.DT)
	sc.press()
