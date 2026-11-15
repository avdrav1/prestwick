class_name ShotShapes
extends Resource
## The shot shapes (D74, E20-S1; docs/design.md Swing, Shot shape), in golf/shot_shapes.tres,
## in the picker's order from left-bending to right-bending: Hook, Draw, Straight, Fade,
## Slice. Tuned with /balance clubs. Read-only for gameplay code.
##
## `flight` is the shape's whole effect on a full club, a pure function of the club, the shape
## and the heading the ball would otherwise leave on, so the swing, the aim marker and guests
## (E20-S2) share it. A shaped ball starts `start_share` of its bend to the far side of the
## aim (a draw starts right) and is pushed sideways in flight, square to its launch heading, by
## a lateral acceleration that decays with the spin (`spin_decay_per_s`), so it curves back
## across the aim and lands `1 - start_share` of the bend beyond it. The push is sized so that
## at the club's flat carry the ball sits exactly the bend off its start line. The forward
## motion is untouched: a shaped ball carries as far along its start line as a straight one.
## Sidespin ends at the first touchdown (Ball).

const DEFAULT_PATH := "res://golf/shot_shapes.tres"
const STRAIGHT_ID := "straight"

## The shape's effect on one stroke (`flight`).
class Flight:
	extends RefCounted
	## The launch heading: the heading given plus `start_deg`.
	var heading_deg: float = 0.0
	## Degrees the ball starts off the heading given, to the side away from the bend.
	var start_deg: float = 0.0
	## The lateral acceleration at launch, yd/s², on the ground plane, square to `heading_deg`.
	var curve: Vector2 = Vector2.ZERO
	## The acceleration is multiplied by this every Ball tick (the spin decays).
	var curve_decay: float = 1.0
	## Multiplies the club's roll factor (ShotShape.roll_scale).
	var roll_scale: float = 1.0
	## The club's bend at its carry, yards (ShotShape.bend_yd × Club.shape_scale).
	var bend_yd: float = 0.0

## Picker order, left-bending to right-bending.
@export var shapes: Array[ShotShape] = []
## The share of the bend a shaped ball starts to the far side of the aim, at the club's carry.
## 0 starts on the aim and bends wholly off it; 0.5 starts half the bend out and lands half
## the bend beyond the aim.
@export_range(0.0, 1.0) var start_share: float = 0.5
## How fast the sidespin decays, per second: the lateral acceleration falls as
## `exp(-spin_decay_per_s × t)`, strongest off the club and fading through the flight. 0 keeps
## it constant.
@export var spin_decay_per_s: float = 0.35


static func load_default() -> ShotShapes:
	return load(DEFAULT_PATH) as ShotShapes


## The shape with this id, or null.
func shape(id: String) -> ShotShape:
	for s in shapes:
		if s.id == id:
			return s
	return null


func straight() -> ShotShape:
	return shape(STRAIGHT_ID)


## The shape `dir` steps along the picker from `from` (-1 toward Hook, +1 toward Slice),
## stopping at the ends.
func step(from: ShotShape, dir: int) -> ShotShape:
	var i := shapes.find(from)
	if i < 0:
		i = shapes.find(straight())
	return shapes[clampi(i + dir, 0, shapes.size() - 1)]


## E20-S2: the shapes that bend toward `side` (-1 left, +1 right), the gentlest first (a draw
## before a hook); empty for side 0.
func bending(side: int) -> Array[ShotShape]:
	var out: Array[ShotShape] = []
	if side == 0:
		return out
	for s in shapes:
		if s != null and s.side == side and s.bends():
			out.append(s)
	out.sort_custom(func(a: ShotShape, b: ShotShape) -> bool: return a.bend_yd < b.bend_yd)
	return out


## The club's bend at its own carry, yards: 0 for the putter and for Straight.
static func bend_of(club: Club, s: ShotShape) -> float:
	if club == null or s == null or club.is_putter() or not s.bends():
		return 0.0
	return s.bend_yd * maxf(0.0, club.shape_scale)


## The shape `s`'s flight for `club` leaving on `heading_deg` (the aim plus the swing's offset
## and the sidehill turn, D14), or null when it does not bend (Straight, the putter, a club
## with no shape_scale): the ball then flies exactly as before. `gravity` is BallParams'.
func flight(club: Club, s: ShotShape, heading_deg: float, gravity: float) -> Flight:
	var bend := bend_of(club, s)
	if bend <= 0.0:
		return null
	var f := Flight.new()
	f.bend_yd = bend
	f.start_deg = -s.side * rad_to_deg(atan2(start_share * bend, club.carry_yd))
	f.heading_deg = heading_deg + f.start_deg
	f.curve_decay = exp(-spin_decay_per_s * Ball.DT)
	var push := bend / unit_push(flight_time(club, gravity), f.curve_decay)
	f.curve = Vector2.from_angle(deg_to_rad(f.heading_deg) + PI * 0.5) * (s.side * push)
	f.roll_scale = s.roll_scale
	return f


## Seconds a perfect swing of `club` stays up over flat ground with no drag.
static func flight_time(club: Club, gravity: float) -> float:
	return 2.0 * club.full_speed(gravity) * sin(deg_to_rad(club.launch_deg)) / gravity


## How far, yards, a lateral acceleration of 1 yd/s² at launch, multiplied by `decay` every
## Ball tick, carries the ball sideways in `seconds`, as Ball steps it (the acceleration held
## over each tick): DT² × (Σ S(n) for n < N + S(N) / 2), S(n) = (1 - r^n) / (1 - r).
static func unit_push(seconds: float, decay: float) -> float:
	var dt := Ball.DT
	var n := seconds / dt
	if absf(1.0 - decay) < 1e-9:
		return 0.5 * seconds * seconds
	var k := 1.0 - decay
	var sum_s := (n - (1.0 - pow(decay, n)) / k) / k
	var s_n := (1.0 - pow(decay, n)) / k
	return dt * dt * (sum_s + 0.5 * s_n)


## Problems with the table, empty when usable.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if straight() == null:
		errors.append("no straight shape")
	var ids := {}
	var last_side := -2
	for s in shapes:
		if s == null:
			errors.append("empty shape slot")
			continue
		if ids.has(s.id):
			errors.append("duplicate shape %s" % s.id)
		ids[s.id] = true
		if s.side < last_side:
			errors.append("%s: shapes go from left-bending to right-bending" % s.id)
		last_side = s.side
		if s.side == 0 and (s.bend_yd != 0.0 or s.roll_scale != 1.0 or s.zone_scale != 1.0):
			errors.append("%s: a shape that does not bend changes nothing" % s.id)
		if s.side != 0 and s.bend_yd <= 0.0:
			errors.append("%s: a bending shape needs a bend" % s.id)
		if s.roll_scale <= 0.0 or s.zone_scale <= 0.0 or s.zone_scale > 1.0:
			errors.append("%s: roll_scale must be positive and zone_scale in (0, 1]" % s.id)
	if spin_decay_per_s < 0.0:
		errors.append("spin_decay_per_s must not be negative")
	return errors
