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
var arrival_window: float = 0.0

var walk_yd_per_s: float = 0.0
## E3-S4: a walk follows a cart path when one has a tile within cart_path_reach_yd of both
## ends and the route along it is at most cart_path_max_detour times the straight line.
var cart_path_reach_yd: float = 0.0
var cart_path_max_detour: float = 0.0
var stroke_s: float = 0.0
## E3-S8: a group tees off behind the group ahead on its hole once every ball of that group
## rests at least this far from the tee (GuestBrain.tee_clear).
var tee_clear_yd: float = 0.0
## E3-S8 review: on the hole, a guest of a following group holds its stroke while a guest or
## unfinished ball of a group ahead lies nearer the cup and within the stroke's planned
## distance plus this margin (GuestBrain.play_clear).
var play_clear_yd: float = 0.0
## E3-S8: ready golf. True: the guest away among those standing at their balls plays, so a
## partner still walking to a ball farther out does not hold the group up.
var ready_golf: bool = false
## E3-S4 review: the most simulated seconds GuestBrain.advance_real steps in one frame; a
## longer frame's extra time is let go (the day runs late, never differently).
var max_steps_per_frame: int = 0
var flight_draw_speed: float = 0.0

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

## Guest Ball work: Ball ticks a guest may spend per simulated second, and the whole sim.
var guest_ticks_per_s: int = 0
var sim_ticks_per_s: int = 0
## PuttAim's putt_aim_max_runs for guests (the player keeps golf/swing_tuning.tres's).
var guest_putt_max_runs: int = 0

var patience_min: int = 1
var patience_max: int = 10
var wait_base_s: float = 0.0
var wait_per_patience_s: float = 0.0
var walk_base_yd: float = 0.0
var walk_per_patience_yd: float = 0.0

var challenge_within: float = 0.0
var casual_challenge_within: float = 0.0
var taste_weights: Dictionary = {}
var doubled_check_weight: int = 0

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
	t.arrival_window = _float(d, "arrival_window", errors)
	t.walk_yd_per_s = _float(d, "walk_yd_per_s", errors)
	t.cart_path_reach_yd = _float(d, "cart_path_reach_yd", errors)
	t.cart_path_max_detour = _float(d, "cart_path_max_detour", errors)
	t.stroke_s = _float(d, "stroke_s", errors)
	t.tee_clear_yd = _float(d, "tee_clear_yd", errors)
	t.play_clear_yd = _float(d, "play_clear_yd", errors)
	var ready: Variant = d.get("ready_golf")
	if typeof(ready) == TYPE_BOOL:
		t.ready_golf = ready
	else:
		errors.append("ready_golf is missing or not true or false")
	t.max_steps_per_frame = CourseData.read_int(d, "max_steps_per_frame", errors)
	t.flight_draw_speed = _float(d, "flight_draw_speed", errors)
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
	t.guest_putt_max_runs = CourseData.read_int(d, "guest_putt_max_runs", errors)
	t.patience_min = CourseData.read_int(d, "patience_min", errors)
	t.patience_max = CourseData.read_int(d, "patience_max", errors)
	t.wait_base_s = _float(d, "wait_base_s", errors)
	t.wait_per_patience_s = _float(d, "wait_per_patience_s", errors)
	t.walk_base_yd = _float(d, "walk_base_yd", errors)
	t.walk_per_patience_yd = _float(d, "walk_per_patience_yd", errors)
	t.challenge_within = _float(d, "challenge_within", errors)
	t.casual_challenge_within = _float(d, "casual_challenge_within", errors)
	var weights: Variant = d.get("taste_weights")
	if typeof(weights) == TYPE_DICTIONARY:
		t.taste_weights = weights
	else:
		errors.append("taste_weights must be an object")
	t.doubled_check_weight = CourseData.read_int(d, "doubled_check_weight", errors)
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
## (day_s and stroke_s above 0, arrival_window 0 to 1 so no group arrives after dusk,
## arrivals_per_day 0 or more); and the older checks (E3-S3 to E3-S8) the engine leans on.
static func _check_ranges(t: GuestTuning, d: Dictionary, errors: Array[String]) -> void:
	_at_most(errors, "full_sigma_best", t.full_sigma_best, "full_sigma_worst", t.full_sigma_worst)
	_at_most(errors, "putt_aim_sigma_best", t.putt_aim_sigma_best,
			"putt_aim_sigma_worst", t.putt_aim_sigma_worst)
	_at_most(errors, "putt_power_sigma_best", t.putt_power_sigma_best,
			"putt_power_sigma_worst", t.putt_power_sigma_worst)
	if t.group_size_min < 1:
		errors.append("group_size_min must be at least 1")
	_at_most(errors, "group_size_min", t.group_size_min, "group_size_max", t.group_size_max)
	if t.skill_max <= t.skill_min:
		errors.append("skill_min (%s) must be below skill_max (%s)" % [t.skill_min, t.skill_max])
	_at_most(errors, "patience_min", t.patience_min, "patience_max", t.patience_max)
	if t.guest_min_power <= 0.0 or t.guest_min_power > 1.0:
		errors.append("guest_min_power (%s) must be above 0 and at most 1" % t.guest_min_power)
	_positive(errors, "day_s", t.day_s)
	_positive(errors, "stroke_s", t.stroke_s)
	if t.arrival_window < 0.0 or t.arrival_window > 1.0:
		errors.append("arrival_window (%s) must be 0 to 1 (a share of day_s)" % t.arrival_window)
	if t.arrivals_per_day < 0:
		errors.append("arrivals_per_day (%s) must be 0 or more" % t.arrivals_per_day)
	_positive(errors, "walk_yd_per_s", t.walk_yd_per_s)
	_positive(errors, "guest_ticks_per_s", t.guest_ticks_per_s)
	_positive(errors, "sim_ticks_per_s", t.sim_ticks_per_s)
	_positive(errors, "flight_draw_speed", t.flight_draw_speed)
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
		errors.append("sim_ticks_per_s must be at least guest_ticks_per_s")
	if t.tee_clear_yd <= 0.0:
		errors.append("tee_clear_yd must be above 0")
	if t.play_clear_yd < 0.0:
		errors.append("play_clear_yd must be 0 or more")
	if t.cart_path_max_detour < 1.0:
		errors.append("cart_path_max_detour must be at least 1 (the straight line)")
	if t.max_steps_per_frame < 1:
		errors.append("max_steps_per_frame must be at least 1")
	if t.praise_passes < 1 or t.praise_passes > 4:
		errors.append("praise_passes must be 1 to 4 (the four checks)")
	if t.complaint_fails < 1:
		errors.append("complaint_fails must be at least 1")
	if t.sight_step_yd <= 0.0:
		errors.append("sight_step_yd must be above 0")
	if t.guest_putt_max_runs < 2:
		errors.append("guest_putt_max_runs must be at least 2 (Swing.validate)")


static func _at_most(errors: Array[String], low_key: String, low: float, high_key: String,
		high: float) -> void:
	if low > high:
		errors.append("%s (%s) must be at most %s (%s)" % [low_key, low, high_key, high])


static func _positive(errors: Array[String], key: String, v: float) -> void:
	if v <= 0.0:
		errors.append("%s (%s) must be above 0" % [key, v])


static func _float(d: Dictionary, key: String, errors: Array[String]) -> float:
	var v: Variant = d.get(key)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	errors.append("%s is missing or not a number" % key)
	return 0.0
