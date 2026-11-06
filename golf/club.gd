class_name Club
extends Resource
## One club of golf/clubs.tres (docs/design.md Swing, Clubs). Tuned with /balance clubs.
## A full club is a carry, a launch angle and a roll factor (D14); the putter is a range of
## starting ground speeds instead (it never flies).

## Which legality rule the club follows (D13, ClubSet.is_legal). Every club but these three
## is FULL: legal anywhere but on green and in a bunker.
enum Kind { FULL, DRIVER, SAND_WEDGE, PUTTER }
## Bisection steps for putt_power_for: 2^-24 of the bar.
const POWER_FOR_STEPS: int = 24

## Short id, as the club picker and the docs write it: "driver", "3w", "3i" .. "9i", "pw",
## "sw", "putter".
@export var id: String = ""
@export var kind: Kind = Kind.FULL
## Flat-ground carry in yards of a perfect swing (100% power, accuracy at centre) from a
## 1.0 lie, with no drag (Ball). Power and the lie scale this carry, not the speed (D14).
@export var carry_yd: float = 100.0
## Launch angle above the ground, degrees.
@export var launch_deg: float = 30.0
## Multiplies the ground speed the ball keeps after its first touchdown, after the surface's
## bounce friction (D14). Nothing else: the surface's Roll and friction stay as they are.
@export var roll_factor: float = 1.0
## Putter only: the slowest and fastest starting ground speed a putt can have, yd/s. The
## bar maps across this range (E2-S7). A full putt (putt_max_speed) on a flat green rolls
## at most ClubSet.full_putt_max_yd.
@export var putt_min_speed: float = 0.0
@export var putt_max_speed: float = 0.0
## Putter only (E3-S51, D49): how the bar's power maps onto that range. 0 is linear (the same
## yd/s for every % of the bar), 1 geometric (the same share of the speed for every %:
## `min × (max / min)^power`), and between them a blend of the two. Geometric gives a short
## putt as much of the bar as a long one, so a click error costs about the same share of the
## pace at any length, as a real stroke's does.
@export_range(0.0, 1.0) var putt_bar_curve: float = 0.0


func is_putter() -> bool:
	return kind == Kind.PUTTER


## Launch speed in yd/s of a full swing: the speed whose flat carry at launch_deg is
## carry_yd, with no drag (`carry = v² sin(2θ) / g`).
func full_speed(gravity: float) -> float:
	return sqrt(carry_yd * gravity / sin(deg_to_rad(2.0 * launch_deg)))


## Putter only: the starting ground speed, yd/s, of a putt struck at `power` (clamped to 0
## to 1): putt_min_speed at 0, putt_max_speed at 1, along putt_bar_curve between.
func putt_speed_at(power: float) -> float:
	var p := clampf(power, 0.0, 1.0)
	var linear := lerpf(putt_min_speed, putt_max_speed, p)
	if putt_bar_curve <= 0.0 or putt_min_speed <= 0.0:
		return linear
	var geometric := putt_min_speed * pow(putt_max_speed / putt_min_speed, p)
	return lerpf(linear, geometric, putt_bar_curve)


## Putter only: the power, 0 to 1, whose putt starts at `speed` yd/s (clamped to the range);
## the inverse of putt_speed_at, which rises with power.
func putt_power_for(speed: float) -> float:
	var v := clampf(speed, putt_min_speed, putt_max_speed)
	if putt_bar_curve <= 0.0 or putt_min_speed <= 0.0:
		return inverse_lerp(putt_min_speed, putt_max_speed, v)
	if v <= putt_min_speed:
		return 0.0
	if v >= putt_max_speed:
		return 1.0
	var lo := 0.0
	var hi := 1.0
	for i in POWER_FOR_STEPS:
		var mid := 0.5 * (lo + hi)
		if putt_speed_at(mid) < v:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)
