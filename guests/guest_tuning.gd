class_name GuestTuning
extends RefCounted
## Every guest tunable (E3-S1, D38 to D43), read from res://data/guests.json. docs/design.md
## Guests and reactions has a line for each. Read-only: /balance reactions (E3-S8) tunes the
## file. E3-S3 reads the swing, aim and Ball work numbers, E3-S4 the day, arrivals, draws, walking
## and stroke time; E3-S6 the checks' numbers (GuestReaction, HoleChecks).

const PATH: String = "res://data/guests.json"

var day_s: float = 0.0
var arrivals_per_day: int = 0
var group_size_min: int = 0
var group_size_max: int = 0
## D46: the groups arrive over the first `arrival_window_s` seconds of the day (seconds, not a
## share of `day_s`, so a longer day keeps the morning rush the pace check was tuned on).
var arrival_window_s: float = 0.0
## E18-S2: the holes of the round D46 sized `day_s` for (9): GuestBrain.late_round_s gives each
## open hole `day_s` less `arrival_window_s` over this, so a late group's need is the same on a
## nine and on the front nine of an eighteen (it read BuilderTuning.max_holes before, 9 then).
var day_round_holes: int = 0
## E18-S3 (D72): rounds of nine or eighteen. On a course with all eighteen holes open (Out 1 to
## 9 and In 10 to 18), a day runs `eighteen_day_s` seconds with its groups arriving over the first
## `eighteen_arrival_window_s` (GuestBrain.day_s and arrival_window_s; any other course keeps
## `day_s` and `arrival_window_s`, so a nine plays as before), and each group plays eighteen
## with the share `eighteen_share` (drawn per group from the day's seed, GuestSpawner), else
## nine. A nine-hole group starts on the back nine when at least `back_nine_queue` groups are
## heading for or standing on the front's first tee and fewer on the back's (0: always the
## front, unless it has no open hole). An eighteen-hole group turns at the clubhouse: from the
## 9th green it walks to the door, stops `turn_stop_s` seconds (a halfway stop), and walks out
## to the 10th tee as from the clubhouse.
var eighteen_share: float = 0.0
var back_nine_queue: int = 0
var turn_stop_s: float = 0.0
var eighteen_day_s: float = 0.0
var eighteen_arrival_window_s: float = 0.0

## E9-S1 (D65): the base walking speed, yards a simulated second, over fairway, rough, green,
## tee and painted out of bounds; `walk_surface_speed` times it on each surface (by
## Surface.Type, read from {surface name: factor}; a cart path is the fastest), and
## `walk_climb_s_per_step` seconds more for each height step climbed from one tile to the next
## (downhill is free). GuestWalk sums a walk's time tile by tile.
var walk_yd_per_s: float = 0.0
var walk_surface_speed: PackedFloat64Array = PackedFloat64Array()
var walk_climb_s_per_step: float = 0.0
## E3-S4: a walk may follow a cart path with a tile within cart_path_reach_yd of both ends
## (E12-S1, D68: 40 yd; E9-S3: 25, 15 before, which no path round a 30 yd green reached).
## E9-S1 (D65): it does when that route is quicker than the straight walk (E3-S4's
## cart_path_max_detour, a cap on its length, is retired).
var cart_path_reach_yd: float = 0.0
var stroke_s: float = 0.0
## E3-S8 review, E3-S22: a guest holds its stroke while a guest, or an unfinished ball, of a
## group ahead on its hole or of a group on another hole lies nearer its cup and within this
## of its ball, or inside the landing area round the stroke's planned rest: a disc of the
## larger of this and `play_clear_share` of the stroke's planned distance
## (GuestBrain.hold_for). E3-S22 folded E3-S8's `tee_clear_yd` (250 yd) into it.
var play_clear_yd: float = 0.0
var play_clear_share: float = 0.0
## E3-S22: a guest out on another hole (it has struck there), or its unfinished ball, holds
## a stroke when nearer the stroke's cup than its ball and within this of the ball or of the
## planned rest (GuestBrain.hold_for, CROSSING); and the seconds in a row a stroke waits on
## such groups alone before it plays on, so two groups on crossing holes never wait on each
## other for ever.
var cross_clear_yd: float = 0.0
var cross_hold_max_s: int = 0
## E3-S37: a group steps onto a tee only while fewer than this many groups are heading for,
## or standing at, the next open hole's tee (GuestBrain.next_tee_free); 0 turns it off. So
## groups that bunch after a quick hole (a par 3 before a par 5) wait a little on its tee, not
## a long while on the slow hole's, and the wait is shared between the two.
var next_tee_queue_max: int = 0
## E3-S8: ready golf. True: the guest away among those standing at their balls plays, so a
## partner still walking to a ball farther out does not hold the group up.
var ready_golf: bool = false
## E3-S4 review: the most simulated seconds GuestBrain.advance_real steps in one frame; a
## longer frame's extra time is let go (the day runs late, never differently).
var max_steps_per_frame: int = 0
var flight_draw_speed: float = 0.0
## E3-S20: the share of `stroke_s` after the strike at which the club meets the ball: the
## golfer art's impact frame (4 of the 6 swing frames, GolferArt.swing_impact_frame). The view
## starts the flight's replay there, and the guest walks once the replay has drawn the ball
## to rest (GuestBrain.ball_shown_s).
var swing_impact_share: float = 0.0
## E3-S20: the share of `stroke_s` before the takeaway (the address, swing frame 0 of 6). A
## guest whose walk ends within `address_s` of a second may strike in that second: the view
## draws its last steps in the address. Later, it strikes the second after, so the figure
## walks all the way first.
var swing_address_share: float = 0.0

var skill_min: int = 1
var skill_max: int = 10
## D40: Gaussian click error, in bar units (Swing.set_result), at skill_max (best) and
## skill_min (worst), linear between.
var full_sigma_best: float = 0.0
var full_sigma_worst: float = 0.0
var putt_aim_sigma_best: float = 0.0
var putt_aim_sigma_worst: float = 0.0
var putt_power_sigma_best: float = 0.0
var putt_power_sigma_worst: float = 0.0
## D40: the least power a guest's full-club swing locks, noise included, so a short chip
## always moves the ball (a planned chip of a few % plus a Gaussian error would often clamp
## to 0 in Swing.set_result and whiff). Putts have no floor.
var guest_min_power: float = 0.0
## D40: strokes over par a skill_min guest expects a hole.
var over_par_worst: float = 0.0

## D41: aims tried either side of the cup, degrees, in order, when the straight plan is unsafe.
var aim_offsets_deg: PackedFloat32Array = PackedFloat32Array()
## D54 (E3-S70): on a dogleg a full shot aims at the turn (D47) while the ball lies at least
## this many yards farther from the cup than the turn does (the corner is still ahead) and the
## longest legal club reaches it; else at the cup.
var turn_ahead_yd: float = 0.0

## Guest Ball work: Ball ticks a guest may spend per simulated second, and the whole sim.
var guest_ticks_per_s: int = 0
var sim_ticks_per_s: int = 0
## E3-S14: the most Ball ticks GuestBrain.advance_real serves in one frame, all guests together
## (the frame's share of its second's need is smaller; a step whose second's work is not yet
## served waits for later frames: the day runs late, never differently).
var frame_ticks_max: int = 0
## E3-S35: the Ball ticks advance_real serves per real second, spread by the frame's length: a
## frame of `delta` seconds serves at most `frame_ticks_per_real_s` x `delta` (200 at 60 fps,
## 400 at 30), never more than `frame_ticks_max`. So the day's real time no longer depends on
## the frame rate: at 30 fps a frame has twice a 60 fps frame's budget, as it has twice its time.
var frame_ticks_per_real_s: int = 0
## E3-S14: the guest work one 3x frame at 60 fps may take, ms: a target that
## scripts/nine_holes_perf.gd measures against. The sim never reads a clock.
var frame_guest_ms_max: float = 0.0
## E3-S34: what one putt-solve tick counts against `frame_ticks_max` (1 for every other
## tick): a putt solve's tick costs about 1.5 times a club-pick prediction's or a ball's
## (34 us against 22, headless), so a frame of putt solves stays inside frame_guest_ms_max. Only
## the frame budget reads it; a second's ticks (guest_ticks_per_s, sim_ticks_per_s) count
## every tick as 1, so the day is the same.
var putt_tick_weight: float = 1.0
## E4-S3: skip to morning runs the rest of the day over frames (GuestBrain.advance_skip), so
## the HUD stays live while it runs. E7-S4: a skip frame runs whole seconds, each served at
## once on several threads, until `skip_frame_ms` of real time has gone (at least one second a
## frame), and at most `skip_steps_per_frame` of them (was `skip_frame_ticks` 1,000 Ball ticks
## and 60 seconds a frame: a busy day on PlaytestNine took 11 to 15 s).
var skip_frame_ms: float = 0.0
var skip_steps_per_frame: int = 0
## PuttAim's putt_aim_max_runs for guests (the player keeps golf/swing_tuning.tres's).
var guest_putt_max_runs: int = 0

var patience_min: int = 1
var patience_max: int = 10
var wait_base_s: float = 0.0
var wait_per_patience_s: float = 0.0
## E9-S1 (D65): the walk to a tee (from the previous cup, or the clubhouse door) is long
## when it takes over walk_base_s + walk_per_patience_s x patience simulated seconds (was
## walk_base_yd 60 + walk_per_patience_yd 10 yards, the same at the base speed).
var walk_base_s: float = 0.0
var walk_per_patience_s: float = 0.0

var challenge_within: float = 0.0
var casual_challenge_within: float = 0.0
var taste_weights: Dictionary = {}
var doubled_check_weight: int = 0

## E9-S2 (D65): the Walk check weighs walk_check_weight when it fails (2: a long walk alone
## makes a complaint). E12-S1 (D68): a walk follows a cart path when GuestWalk.route takes one;
## walk_path_share (0.5 of its yards on path tiles, E9-S2) is retired.
var walk_check_weight: int = 0

var praise_passes: int = 0
var complaint_fails: int = 0
var rating_window: int = 0

var eye_height_yd: float = 0.0
var mark_height_yd: float = 0.0
var sight_step_yd: float = 0.0

static var _default: GuestTuning


## The numbers in data/guests.json, read once per run. Fails an assert, and pushes an error
## for each problem (so a release build says so too), when the file is missing, a number is
## missing or of the wrong kind, or a range does not hold (E3-S13, _check_ranges).
static func load_default() -> GuestTuning:
	if _default == null:
		_default = from_file(PATH)
	return _default


static func from_file(path: String) -> GuestTuning:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(typeof(parsed) == TYPE_DICTIONARY, "%s must be a JSON object" % path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return GuestTuning.new()
	var errors: Array[String] = []
	var t := from_dict(parsed, errors)
	for e: String in errors:
		push_error("%s: %s" % [path, e])
	assert(errors.is_empty(), "%s: %s" % [path, errors])
	return t


static func from_dict(d: Dictionary, errors: Array[String]) -> GuestTuning:
	var t := GuestTuning.new()
	t.day_s = _float(d, "day_s", errors)
	t.arrivals_per_day = CourseData.read_int(d, "arrivals_per_day", errors)
	t.group_size_min = CourseData.read_int(d, "group_size_min", errors)
	t.group_size_max = CourseData.read_int(d, "group_size_max", errors)
	t.arrival_window_s = _float(d, "arrival_window_s", errors)
	t.day_round_holes = CourseData.read_int(d, "day_round_holes", errors)
	t.eighteen_share = _float(d, "eighteen_share", errors)
	t.back_nine_queue = CourseData.read_int(d, "back_nine_queue", errors)
	t.turn_stop_s = _float(d, "turn_stop_s", errors)
	t.eighteen_day_s = _float(d, "eighteen_day_s", errors)
	t.eighteen_arrival_window_s = _float(d, "eighteen_arrival_window_s", errors)
	t.walk_yd_per_s = _float(d, "walk_yd_per_s", errors)
	t.walk_surface_speed.resize(Surface.COUNT)
	var speeds: Variant = d.get("walk_surface_speed")
	if typeof(speeds) == TYPE_DICTIONARY:
		for s: int in Surface.COUNT:
			var v: Variant = (speeds as Dictionary).get(Surface.NAMES[s])
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				t.walk_surface_speed[s] = float(v)
			else:
				errors.append("walk_surface_speed.%s is missing or not a number" % Surface.NAMES[s])
	else:
		errors.append("walk_surface_speed must be an object of surface names")
	t.walk_climb_s_per_step = _float(d, "walk_climb_s_per_step", errors)
	t.cart_path_reach_yd = _float(d, "cart_path_reach_yd", errors)
	t.stroke_s = _float(d, "stroke_s", errors)
	t.play_clear_yd = _float(d, "play_clear_yd", errors)
	t.play_clear_share = _float(d, "play_clear_share", errors)
	t.cross_clear_yd = _float(d, "cross_clear_yd", errors)
	t.cross_hold_max_s = CourseData.read_int(d, "cross_hold_max_s", errors)
	t.next_tee_queue_max = CourseData.read_int(d, "next_tee_queue_max", errors)
	var ready: Variant = d.get("ready_golf")
	if typeof(ready) == TYPE_BOOL:
		t.ready_golf = ready
	else:
		errors.append("ready_golf is missing or not true or false")
	t.max_steps_per_frame = CourseData.read_int(d, "max_steps_per_frame", errors)
	t.flight_draw_speed = _float(d, "flight_draw_speed", errors)
	t.swing_impact_share = _float(d, "swing_impact_share", errors)
	t.swing_address_share = _float(d, "swing_address_share", errors)
	t.skill_min = CourseData.read_int(d, "skill_min", errors)
	t.skill_max = CourseData.read_int(d, "skill_max", errors)
	t.full_sigma_best = _float(d, "full_sigma_best", errors)
	t.full_sigma_worst = _float(d, "full_sigma_worst", errors)
	t.putt_aim_sigma_best = _float(d, "putt_aim_sigma_best", errors)
	t.putt_aim_sigma_worst = _float(d, "putt_aim_sigma_worst", errors)
	t.putt_power_sigma_best = _float(d, "putt_power_sigma_best", errors)
	t.putt_power_sigma_worst = _float(d, "putt_power_sigma_worst", errors)
	t.guest_min_power = _float(d, "guest_min_power", errors)
	t.over_par_worst = _float(d, "over_par_worst", errors)
	t.turn_ahead_yd = _float(d, "turn_ahead_yd", errors)
	var offsets: Variant = d.get("aim_offsets_deg")
	if typeof(offsets) == TYPE_ARRAY:
		for v: Variant in offsets:
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				t.aim_offsets_deg.append(float(v))
			else:
				errors.append("aim_offsets_deg must hold numbers")
	else:
		errors.append("aim_offsets_deg must be a list of degrees")
	t.guest_ticks_per_s = CourseData.read_int(d, "guest_ticks_per_s", errors)
	t.sim_ticks_per_s = CourseData.read_int(d, "sim_ticks_per_s", errors)
	t.frame_ticks_max = CourseData.read_int(d, "frame_ticks_max", errors)
	t.frame_ticks_per_real_s = CourseData.read_int(d, "frame_ticks_per_real_s", errors)
	t.frame_guest_ms_max = _float(d, "frame_guest_ms_max", errors)
	t.guest_putt_max_runs = CourseData.read_int(d, "guest_putt_max_runs", errors)
	t.putt_tick_weight = _float(d, "putt_tick_weight", errors)
	t.skip_frame_ms = _float(d, "skip_frame_ms", errors)
	t.skip_steps_per_frame = CourseData.read_int(d, "skip_steps_per_frame", errors)
	t.patience_min = CourseData.read_int(d, "patience_min", errors)
	t.patience_max = CourseData.read_int(d, "patience_max", errors)
	t.wait_base_s = _float(d, "wait_base_s", errors)
	t.wait_per_patience_s = _float(d, "wait_per_patience_s", errors)
	t.walk_base_s = _float(d, "walk_base_s", errors)
	t.walk_per_patience_s = _float(d, "walk_per_patience_s", errors)
	t.challenge_within = _float(d, "challenge_within", errors)
	t.casual_challenge_within = _float(d, "casual_challenge_within", errors)
	var weights: Variant = d.get("taste_weights")
	if typeof(weights) == TYPE_DICTIONARY:
		t.taste_weights = weights
	else:
		errors.append("taste_weights must be an object")
	t.doubled_check_weight = CourseData.read_int(d, "doubled_check_weight", errors)
	t.walk_check_weight = CourseData.read_int(d, "walk_check_weight", errors)
	t.praise_passes = CourseData.read_int(d, "praise_passes", errors)
	t.complaint_fails = CourseData.read_int(d, "complaint_fails", errors)
	t.rating_window = CourseData.read_int(d, "rating_window", errors)
	t.eye_height_yd = _float(d, "eye_height_yd", errors)
	t.mark_height_yd = _float(d, "mark_height_yd", errors)
	t.sight_step_yd = _float(d, "sight_step_yd", errors)
	_check_ranges(t, d, errors)
	return t


## How far `skill` sits from the best guest: 0 at skill_max, 1 at skill_min (D40).
func skill_share(skill: int) -> float:
	var s := clampi(skill, skill_min, skill_max)
	return float(skill_max - s) / float(skill_max - skill_min)


## D40: a full club's click error (power and accuracy), bar units.
func full_sigma(skill: int) -> float:
	return lerpf(full_sigma_best, full_sigma_worst, skill_share(skill))


func putt_aim_sigma(skill: int) -> float:
	return lerpf(putt_aim_sigma_best, putt_aim_sigma_worst, skill_share(skill))


func putt_power_sigma(skill: int) -> float:
	return lerpf(putt_power_sigma_best, putt_power_sigma_worst, skill_share(skill))


## D40: the score a guest of `skill` expects on a hole of `par`.
func expected_score(par: int, skill: int) -> float:
	return par + over_par_worst * skill_share(skill)


## The swing tuning a guest's putt solve uses: `base` with putt_aim_max_runs set to
## guest_putt_max_runs (a copy; `base` is not changed).
func guest_swing_tuning(base: SwingTuning) -> SwingTuning:
	var t := base.duplicate() as SwingTuning
	t.putt_aim_max_runs = guest_putt_max_runs
	return t


## E3-S13: the ranges the numbers must hold, one error each, naming the keys, so a bad edit to
## data/guests.json fails loudly instead of playing oddly. Each best sigma at most its worst,
## each min at most its max (skill strictly below: skill_share divides by the span), weights
## and per-second rates above 0, guest_min_power above 0 and at most 1; the day's clock
## (day_s and stroke_s above 0, arrival_window_s 0 to day_s so no group arrives after dusk,
## arrivals_per_day 0 or more); and the older checks (E3-S3 to E3-S8) the engine leans on.
## E3-S36: the pace limits, challenge bands, expected score, sight line and rating window too;
## every message names its keys and the bad value (docs/design.md lists each bound).
static func _check_ranges(t: GuestTuning, d: Dictionary, errors: Array[String]) -> void:
	_at_most(errors, "full_sigma_best", t.full_sigma_best, "full_sigma_worst", t.full_sigma_worst)
	_at_most(errors, "putt_aim_sigma_best", t.putt_aim_sigma_best,
			"putt_aim_sigma_worst", t.putt_aim_sigma_worst)
	_at_most(errors, "putt_power_sigma_best", t.putt_power_sigma_best,
			"putt_power_sigma_worst", t.putt_power_sigma_worst)
	_at_least(errors, "group_size_min", t.group_size_min, 1)
	_at_least(errors, "day_round_holes", t.day_round_holes, 1)
	_at_most(errors, "group_size_min", t.group_size_min, "group_size_max", t.group_size_max)
	if t.skill_max <= t.skill_min:
		errors.append("skill_min (%s) must be below skill_max (%s)" % [t.skill_min, t.skill_max])
	_at_most(errors, "patience_min", t.patience_min, "patience_max", t.patience_max)
	if t.guest_min_power <= 0.0 or t.guest_min_power > 1.0:
		errors.append("guest_min_power (%s) must be above 0 and at most 1" % t.guest_min_power)
	_positive(errors, "day_s", t.day_s)
	_positive(errors, "stroke_s", t.stroke_s)
	if t.arrival_window_s < 0.0 or (t.day_s > 0.0 and t.arrival_window_s > t.day_s):
		errors.append("arrival_window_s (%s) must be 0 to day_s (%s)" % [t.arrival_window_s, t.day_s])
	# E18-S3 (D72): the eighteen-hole day and its rounds.
	_positive(errors, "eighteen_day_s", t.eighteen_day_s)
	if t.eighteen_arrival_window_s < 0.0 or (t.eighteen_day_s > 0.0
			and t.eighteen_arrival_window_s > t.eighteen_day_s):
		errors.append("eighteen_arrival_window_s (%s) must be 0 to eighteen_day_s (%s)" % [
				t.eighteen_arrival_window_s, t.eighteen_day_s])
	if t.eighteen_share < 0.0 or t.eighteen_share > 1.0:
		errors.append("eighteen_share (%s) must be 0 to 1" % t.eighteen_share)
	_at_least(errors, "back_nine_queue", t.back_nine_queue, 0)
	_at_least(errors, "turn_stop_s", t.turn_stop_s, 0.0)
	if t.arrivals_per_day < 0:
		errors.append("arrivals_per_day (%s) must be 0 or more" % t.arrivals_per_day)
	_positive(errors, "walk_yd_per_s", t.walk_yd_per_s)
	for s: int in mini(t.walk_surface_speed.size(), Surface.COUNT):
		_positive(errors, "walk_surface_speed.%s" % Surface.NAMES[s], t.walk_surface_speed[s])
	_at_least(errors, "walk_climb_s_per_step", t.walk_climb_s_per_step, 0.0)
	_positive(errors, "guest_ticks_per_s", t.guest_ticks_per_s)
	_positive(errors, "sim_ticks_per_s", t.sim_ticks_per_s)
	_positive(errors, "flight_draw_speed", t.flight_draw_speed)
	if t.swing_impact_share < 0.0 or t.swing_impact_share >= 1.0:
		errors.append("swing_impact_share (%s) must be 0 or more and below 1" % t.swing_impact_share)
	if t.swing_address_share < 0.0 or t.swing_address_share > t.swing_impact_share:
		errors.append("swing_address_share (%s) must be 0 to swing_impact_share (%s)"
				% [t.swing_address_share, t.swing_impact_share])
	_positive(errors, "doubled_check_weight", t.doubled_check_weight)
	var weights: Variant = d.get("taste_weights")
	if typeof(weights) == TYPE_DICTIONARY:
		for name: String in Guest.TASTE_NAMES:
			var w: Variant = (weights as Dictionary).get(name)
			if typeof(w) != TYPE_FLOAT and typeof(w) != TYPE_INT:
				errors.append("taste_weights.%s is missing or not a number" % name)
			else:
				_positive(errors, "taste_weights.%s" % name, float(w))
	if t.sim_ticks_per_s < t.guest_ticks_per_s:
		errors.append("sim_ticks_per_s (%s) must be at least guest_ticks_per_s (%s)"
				% [t.sim_ticks_per_s, t.guest_ticks_per_s])
	_at_least(errors, "play_clear_yd", t.play_clear_yd, 0.0)
	_at_least(errors, "play_clear_share", t.play_clear_share, 0.0)
	_at_least(errors, "cross_clear_yd", t.cross_clear_yd, 0.0)
	_at_least(errors, "cross_hold_max_s", t.cross_hold_max_s, 1)
	_at_least(errors, "next_tee_queue_max", t.next_tee_queue_max, 0, " (0 turns it off)")
	_at_least(errors, "max_steps_per_frame", t.max_steps_per_frame, 1)
	_at_least(errors, "frame_ticks_max", t.frame_ticks_max, 1)
	_at_least(errors, "frame_ticks_per_real_s", t.frame_ticks_per_real_s, 1)
	_positive(errors, "frame_guest_ms_max", t.frame_guest_ms_max)
	_at_least(errors, "putt_tick_weight", t.putt_tick_weight, 1.0, " (a putt tick costs no less than another)")
	# E4-S3, E7-S4: a skip frame runs at least one second, so a skip always ends.
	_positive(errors, "skip_frame_ms", t.skip_frame_ms)
	_at_least(errors, "skip_steps_per_frame", t.skip_steps_per_frame, 1)
	if t.praise_passes < 1 or t.praise_passes > GuestReaction.Check.size():
		errors.append("praise_passes (%s) must be 1 to %d (the checks)" % [t.praise_passes,
				GuestReaction.Check.size()])
	_at_least(errors, "walk_check_weight", t.walk_check_weight, 1)
	_at_least(errors, "complaint_fails", t.complaint_fails, 1)
	_positive(errors, "sight_step_yd", t.sight_step_yd)
	_at_least(errors, "guest_putt_max_runs", t.guest_putt_max_runs, 2, " (Swing.validate)")
	# E3-S36: the pace limits (GuestReaction.wait_limit_s, walk_limit_s), the challenge bands
	# and the expected score (D40) take no negatives; a Casual guest's band is the wider (D42);
	# the sight line's eye stands above the tee (D43), its mark at or above the target; the rating
	# averages at least one reaction.
	_at_least(errors, "wait_base_s", t.wait_base_s, 0.0)
	_at_least(errors, "wait_per_patience_s", t.wait_per_patience_s, 0.0)
	_at_least(errors, "walk_base_s", t.walk_base_s, 0.0)
	_at_least(errors, "walk_per_patience_s", t.walk_per_patience_s, 0.0)
	_at_least(errors, "challenge_within", t.challenge_within, 0.0)
	if t.casual_challenge_within < 0.0:
		_at_least(errors, "casual_challenge_within", t.casual_challenge_within, 0.0)
	elif t.challenge_within >= 0.0:
		_at_most(errors, "challenge_within", t.challenge_within,
				"casual_challenge_within", t.casual_challenge_within)
	_at_least(errors, "over_par_worst", t.over_par_worst, 0.0)
	_positive(errors, "eye_height_yd", t.eye_height_yd)
	_at_least(errors, "mark_height_yd", t.mark_height_yd, 0.0)
	_at_least(errors, "rating_window", t.rating_window, 1)


## E9-S1 (D65): a guest's walking speed on `surface`, yards a simulated second.
func walk_speed(surface: int) -> float:
	return walk_yd_per_s * walk_surface_speed[surface]


## E9-S1: the fastest a guest walks on any surface, yards a simulated second (what GuestView
## lets a figure's sidestep move at, as a walk).
func walk_top_yd_per_s() -> float:
	var top := 0.0
	for f: float in walk_surface_speed:
		top = maxf(top, f)
	return walk_yd_per_s * top


## E3-S20: simulated seconds from a strike to the club meeting the ball.
func impact_s() -> float:
	return swing_impact_share * stroke_s


## E3-S20: simulated seconds from a strike to the takeaway (the swing's address).
func address_s() -> float:
	return swing_address_share * stroke_s


## E3-S20: simulated seconds a flight of `path_ticks` Ball ticks takes to draw (GuestView's
## replay, `flight_draw_speed` times faster than real time).
func flight_shown_s(path_ticks: int) -> float:
	return maxf(float(path_ticks), 0.0) / (Ball.TICK_HZ * flight_draw_speed)


static func _at_most(errors: Array[String], low_key: String, low: Variant, high_key: String,
		high: Variant) -> void:
	if low > high:
		errors.append("%s (%s) must be at most %s (%s)" % [low_key, low, high_key, high])


## E3-S36: `v` (an int key's value stays an int, so the message shows it as the file has it)
## must be `low` or more.
static func _at_least(errors: Array[String], key: String, v: Variant, low: Variant,
		why: String = "") -> void:
	if v < low:
		errors.append("%s (%s) must be at least %s%s" % [key, v, low, why])


static func _positive(errors: Array[String], key: String, v: Variant) -> void:
	if v <= 0.0:
		errors.append("%s (%s) must be above 0" % [key, v])


static func _float(d: Dictionary, key: String, errors: Array[String]) -> float:
	var v: Variant = d.get(key)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	errors.append("%s is missing or not a number" % key)
	return 0.0
