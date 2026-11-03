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
##
## Short-game noise (E6-S13, data/scripted_player.json): a perfect click every time holed the
## 80 to 110 yd chip from a drop far too often. So a full-club stroke from within
## short_game_max_yd of the cup clicks the accuracy `accuracy_offset` ticks off the centre,
## drawn from -accuracy_noise_ticks to +accuracy_noise_ticks by a generator seeded with the
## stroke and the ball's place. The club and power are still chosen on a centred swing (what
## the player means to play); the plan's prediction is the noisy swing it will play, so it
## may be a drop (the centred plan's "a drop never" covers only the swing meant). With
## `putts_hole_only` a noisy swing that would hole is not played: the plan falls back to the
## centred click, which `_plan_centred` already kept from holing.

## Full-club powers tried, in ticks of the bar (72 is 100% at bar speed 1.0).
const FULL_TICKS: Array[int] = [72, 64, 56, 48, 40, 32, 24]
const NOISE_PATH: String = "res://data/scripted_player.json"


## The scripted player's short-game noise, from data/scripted_player.json.
class ShortGameNoise:
	## A full-club stroke from at most this far from the cup, yards, gets the noise.
	var short_game_max_yd: float = 0.0
	## The accuracy click lands up to this many bar ticks either side of the centre.
	var accuracy_noise_ticks: int = 0

	## The noise in data/scripted_player.json.
	static func load_default() -> ShortGameNoise:
		var n := ShortGameNoise.new()
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(NOISE_PATH))
		assert(typeof(parsed) == TYPE_DICTIONARY, "%s must be a JSON object" % NOISE_PATH)
		if typeof(parsed) != TYPE_DICTIONARY:
			return n
		var data: Dictionary = parsed
		n.short_game_max_yd = float(data.get("short_game_max_yd", 0.0))
		n.accuracy_noise_ticks = maxi(int(data.get("accuracy_noise_ticks", 0)), 0)
		return n

	## No noise: every click at the centre.
	static func none() -> ShortGameNoise:
		return ShortGameNoise.new()


class Plan:
	var club: Club
	var aim_deg: float = 0.0
	## Bar ticks up to the power click, and back down to the accuracy click.
	var ticks: int = 0
	## Extra bar ticks after the way back down before the accuracy click: positive is late
	## (a hook), negative early (a slice). 0 is the centre.
	var accuracy_offset: int = 0
	var prediction: ShotPrediction


## The stroke to play next from where `sc`'s ball rests: aimed at the cup, the legal club
## and power whose predicted rest is nearest the cup (a holed putt first, a drop never on the
## centred swing; short-game noise may still play one, see above). With `putts_hole_only` a
## full club's stroke that would hole is passed over, noisy or not, so the player holes out
## only with the putter (E2-S13: a test that must not hang on a perfect chip-in).
## `noise` defaults to data/scripted_player.json's; ShortGameNoise.none() clicks every swing perfectly.
static func plan(sc: SwingControl, putts_hole_only: bool = false, noise: ShortGameNoise = null) -> Plan:
	if noise == null:
		noise = ShortGameNoise.load_default()
	var best := _plan_centred(sc, putts_hole_only)
	if best == null or best.club.is_putter() or noise.accuracy_noise_ticks <= 0:
		return best
	var cup := sc.cup_tile()
	if cup == Ball.NO_CUP \
			or sc.ball_at.distance_to(sc.field.tile_center(cup)) > noise.short_game_max_yd:
		return best
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sc.next_seed(), sc.ball_at.x, sc.ball_at.y])
	best.accuracy_offset = rng.randi_range(-noise.accuracy_noise_ticks, noise.accuracy_noise_ticks)
	if best.accuracy_offset != 0:
		var centred := best.prediction
		best.prediction = predict(sc, best.club, best.aim_deg, best.ticks, best.accuracy_offset)
		if putts_hole_only and best.prediction.holed:
			best.accuracy_offset = 0
			best.prediction = centred
	return best


## The plan a perfect click every time would play.
static func _plan_centred(sc: SwingControl, putts_hole_only: bool) -> Plan:
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


## What the swing `ticks` up and `ticks` + `accuracy_offset` back down with `club`, aimed
## `aim_deg`, will do: the same Swing the control runs, ticked the same way.
static func predict(sc: SwingControl, club: Club, aim_deg: float, ticks: int,
		accuracy_offset: int = 0) -> ShotPrediction:
	var s := Swing.new(sc.tuning)
	s.bar_speed = sc.swing.bar_speed
	s.click()
	for i in ticks:
		s.tick(Ball.DT)
	s.click()
	for i in ticks + accuracy_offset:
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
	for i in p.ticks + p.accuracy_offset:
		sc.advance(Ball.DT)
	sc.press()
