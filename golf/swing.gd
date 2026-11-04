class_name Swing
extends RefCounted
## The three-click swing bar (docs/design.md Swing, E2-S7), with no scene, so the Play HUD,
## tests and guests (E3) share it. Numbers in golf/swing_tuning.tres.
##
## Click 1 starts the bar filling from 0: it reaches 100% in `fill_time / bar_speed` seconds
## and runs on to `max_power` (110%), where it locks if the player has not clicked. Click 2
## locks the power at the bar's position, and the bar runs back down past the accuracy
## centre (0) to `bar_min`. Click 3 locks the accuracy: the bar's position then, positive
## when early (above the centre), negative when late. Reaching `bar_min` without a third
## click is a late miss.
##
## Within the zone (`zone_half` either side of the centre, narrowed above 100%, the overswing
## penalty) the shot turns `deg_per_10pct` degrees per 10% off centre: early to the right
## (+heading, a slice for a right-hander), late to the left (a hook). Outside it the shot
## shanks: `shank_deg` toward the side of the miss at `shank_power` of the power. The turn is
## a heading offset at launch (D14); the ball then flies straight.

enum Phase { IDLE, POWER, ACCURACY, DONE }

var tuning: SwingTuning
var phase: Phase = Phase.IDLE
## Where the bar is now (1.0 = 100%).
var bar: float = 0.0
## The locked power (1.0 = 100%, up to max_power), valid from the second click.
var power: float = 0.0
## The locked accuracy: the bar's position at the third click, valid once DONE.
var accuracy: float = 0.0
## The bar speed setting (accessibility), clamped to the tuning's range.
var bar_speed: float = 1.0:
	set(value):
		bar_speed = value if tuning == null \
				else clampf(value, tuning.bar_speed_min, tuning.bar_speed_max)


func _init(p_tuning: SwingTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else SwingTuning.load_default()
	bar_speed = tuning.bar_speed_default


## Back to the start, ready for click 1. Keeps the bar speed.
func reset() -> void:
	phase = Phase.IDLE
	bar = 0.0
	power = 0.0
	accuracy = 0.0


## True between the first click and the third.
func in_progress() -> bool:
	return phase == Phase.POWER or phase == Phase.ACCURACY


func is_done() -> bool:
	return phase == Phase.DONE


## One click of the swing input.
func click() -> void:
	match phase:
		Phase.IDLE:
			bar = 0.0
			phase = Phase.POWER
		Phase.POWER:
			_lock_power()
		Phase.ACCURACY:
			_lock_accuracy()


## Moves the bar by `delta` seconds.
func tick(delta: float) -> void:
	match phase:
		Phase.POWER:
			bar += rate() * delta
			if bar >= tuning.max_power:
				bar = tuning.max_power
				_lock_power()
		Phase.ACCURACY:
			bar -= rate() * delta
			if bar <= tuning.bar_min:
				bar = tuning.bar_min
				_lock_accuracy()


## Bar travel per second, in shares of a full swing.
func rate() -> float:
	return bar_speed / tuning.fill_time


## Seconds the bar takes from 0 to 100% at the current bar speed.
func fill_seconds() -> float:
	return 1.0 / rate()


## Half the accuracy zone's width for a swing locked at `p_power`: `zone_half` up to 100%,
## narrowing linearly to `overswing_zone_scale` of it at `max_power` (the overswing penalty).
func zone_half_at(p_power: float) -> float:
	var over := 0.0
	if tuning.max_power > 1.0:
		over = clampf((p_power - 1.0) / (tuning.max_power - 1.0), 0.0, 1.0)
	return tuning.zone_half * lerpf(1.0, tuning.overswing_zone_scale, over)


## The zone for this swing: at the locked power once it is locked, else at the bar.
func zone_half_width() -> float:
	return zone_half_at(power if phase == Phase.ACCURACY or phase == Phase.DONE else bar)


## Sets a finished swing directly (tests, guests): `p_power` and `p_accuracy` as the clicks
## would have locked them.
func set_result(p_power: float, p_accuracy: float) -> void:
	power = clampf(p_power, 0.0, tuning.max_power)
	accuracy = p_accuracy
	bar = accuracy
	phase = Phase.DONE


## A perfect swing: 100% power, accuracy at the centre (the aim marker's shot, D14).
func set_perfect() -> void:
	set_result(1.0, 0.0)


## True when the locked accuracy is outside the zone (edges count as inside).
func is_shank() -> bool:
	return absf(accuracy) > zone_half_width() + 1e-9


## The heading offset this swing adds to the aim, degrees.
func offset_deg() -> float:
	if is_shank():
		return signf(accuracy) * tuning.shank_deg
	return accuracy / 0.1 * tuning.deg_per_10pct


## The power the shot is struck with: the locked power, cut by a shank.
func effective_power() -> float:
	return power * (tuning.shank_power if is_shank() else 1.0)


## A putt's starting ground speed: the bar maps linearly across the putter's range, 0% the
## slowest and 100% the fastest. Overswing adds no speed (a putt cannot go past the range).
func putt_speed(putter: Club) -> float:
	return lerpf(putter.putt_min_speed, putter.putt_max_speed, clampf(effective_power(), 0.0, 1.0))


## The stroke this finished swing makes with `club` from the ball at `at`, aimed `aim_deg`.
func launch(model: ShotModel, field: HeightField, club: Club, at: Vector2, aim_deg: float) -> ShotLaunch:
	if club.is_putter():
		return model.putt(field, club, putt_speed(club), at, aim_deg, offset_deg())
	return model.full(field, club, effective_power(), at, aim_deg, offset_deg())


## The stroke a perfect swing makes (the aim marker's), whatever this swing's state.
func perfect_launch(model: ShotModel, field: HeightField, club: Club, at: Vector2,
		aim_deg: float) -> ShotLaunch:
	var s := Swing.new(tuning)
	s.set_perfect()
	return s.launch(model, field, club, at, aim_deg)


## Problems with the tuning, empty when usable.
static func validate(t: SwingTuning) -> PackedStringArray:
	var errors := PackedStringArray()
	if t.fill_time <= 0.0:
		errors.append("fill_time must be positive")
	if t.max_power < 1.0:
		errors.append("max_power must be at least 1.0")
	if -t.bar_min <= t.zone_half:
		errors.append("bar_min must lie past the zone, or a missed third click is not a shank")
	if t.bar_speed_min <= 0.0 or t.bar_speed_max < t.bar_speed_min:
		errors.append("bar speed range must be 0 < min <= max")
	if t.bar_speed_default < t.bar_speed_min or t.bar_speed_default > t.bar_speed_max:
		errors.append("bar_speed_default must lie in the range")
	if t.putt_aim_tolerance_yd <= 0.0:
		errors.append("putt_aim_tolerance_yd must be positive")
	if t.putt_aim_max_runs < 2:
		errors.append("putt_aim_max_runs must be at least 2")
	if t.putt_aim_scan_powers < 2:
		errors.append("putt_aim_scan_powers must be at least 2")
	if t.putt_aim_refine_power <= 0.0:
		errors.append("putt_aim_refine_power must be positive")
	if t.putt_aim_frame_ticks < 1:
		errors.append("putt_aim_frame_ticks must be at least 1")
	if t.putt_aim_frame_usec < 1:
		errors.append("putt_aim_frame_usec must be at least 1")
	return errors


func _lock_power() -> void:
	power = clampf(bar, 0.0, tuning.max_power)
	phase = Phase.ACCURACY


func _lock_accuracy() -> void:
	accuracy = bar
	phase = Phase.DONE
