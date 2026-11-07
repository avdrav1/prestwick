extends GuestReaction
## E3-S44: a complaint whose pace reason holds ". " itself, so a test can check the lead is
## kept as built and never split out of the line. A purist, slow, blind and too hard: fair
## leads (doubled), pace and challenge follow; or with `pace_leads` a casual guest whose pace
## alone fails twice over (its reason leads).


static func make(hole: int, pace_leads: bool) -> GuestReaction:
	var r: GuestReaction = (load("res://tests/fixtures/dotted_reaction.gd") as GDScript).new()
	r.hole_number = hole
	r.kind = Kind.COMPLAINT
	r.score = 9
	r.par = 4
	r.expected = 4.0
	r.wait_s = 40
	r.wait_limit_s = 10.0
	r.statics = HoleChecks.Statics.new()
	r.statics.hazard_on_line = true
	r.statics.safe_route = true
	var passed: Array[bool] = [pace_leads, true, false, false]
	r.passed = passed
	if not pace_leads:
		r.taste = Guest.Taste.PURIST
		r.weights[Check.FAIR] = 2
	else:
		r.taste = Guest.Taste.CASUAL
	for c: int in Check.size():
		if not r.passed[c]:
			r.fail_weight += r.weights[c]
	r.text = r._line()
	return r


func _reason(c: int) -> String:
	if c == Check.PACE:
		return "slow. Very slow, waited %d s" % wait_s
	return super(c)
