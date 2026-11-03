class_name Club
extends Resource
## One club of golf/clubs.tres (docs/design.md Swing, Clubs). Tuned with /balance clubs.
## A full club is a carry, a launch angle and a roll factor (D14); the putter is a range of
## starting ground speeds instead (it never flies).

## Which legality rule the club follows (D13, ClubSet.is_legal). Every club but these three
## is FULL: legal anywhere but on green and in a bunker.
enum Kind { FULL, DRIVER, SAND_WEDGE, PUTTER }

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


func is_putter() -> bool:
	return kind == Kind.PUTTER


## Launch speed in yd/s of a full swing: the speed whose flat carry at launch_deg is
## carry_yd, with no drag (`carry = v² sin(2θ) / g`).
func full_speed(gravity: float) -> float:
	return sqrt(carry_yd * gravity / sin(deg_to_rad(2.0 * launch_deg)))
