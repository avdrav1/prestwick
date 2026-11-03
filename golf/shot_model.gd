class_name ShotModel
extends RefCounted
## The shot model (docs/design.md Swing, D14): club, power, lie and accuracy become a
## launch. No scene, so the swing (E2-S7), the aim marker and guests (E3) share it.
##
## Full club: target carry = carry × power × lie (surface × uphill). The launch speed is the
## one whose flat carry at the club's launch angle is that target: with no drag,
## v_full × sqrt(power × lie). The heading is the aim plus the accuracy offset (hook or
## slice, E2-S7) plus the sidehill turn; the ball then flies straight.
## Putter: a starting ground speed within the putter's range; no lie applies.

var clubs: ClubSet
var lies: LieTable
var params: BallParams


func _init(p_clubs: ClubSet = null, p_lies: LieTable = null, p_params: BallParams = null) -> void:
	clubs = p_clubs if p_clubs != null else ClubSet.load_default()
	lies = p_lies if p_lies != null else LieTable.load_default()
	params = p_params if p_params != null else BallParams.load_default()


## Launch speed, yd/s, of `club` at `power` (1.0 = 100%, 1.1 overswing) from a lie whose
## carry multiplier is `lie_multiplier`.
func launch_speed(club: Club, power: float, lie_multiplier: float) -> float:
	return club.full_speed(params.gravity) * sqrt(maxf(0.0, power * lie_multiplier))


## A full club from the ball resting at `at` (yards), aimed at `aim_deg`. `offset_deg` is
## the accuracy offset (hook or slice) the swing adds. `use_lie` false skips rise and tilt
## (the surface still counts), for measuring the lie's own effect.
func full(field: HeightField, club: Club, power: float, at: Vector2, aim_deg: float,
		offset_deg: float = 0.0, use_lie: bool = true) -> ShotLaunch:
	var lie := lies.measure(field, at, aim_deg) if use_lie else lies.flat(field.surface_at(at.x, at.y))
	return full_with_lie(field, club, power, at, aim_deg, lie, offset_deg)


## A full club from `at` with a lie already read (LieTable.measure or LieTable.flat).
func full_with_lie(field: HeightField, club: Club, power: float, at: Vector2, aim_deg: float,
		lie: Lie, offset_deg: float = 0.0) -> ShotLaunch:
	assert(not club.is_putter(), "the putter is a putt, not a flight")
	var s := ShotLaunch.new()
	s.club = club
	s.lie = lie
	s.start = Vector3(at.x, at.y, field.height_at(at.x, at.y))
	s.target_carry = club.carry_yd * power * lie.carry_multiplier()
	s.heading_deg = aim_deg + offset_deg + lie.turn_deg
	s.velocity = Ball.launch_velocity(launch_speed(club, power, lie.carry_multiplier()),
			club.launch_deg, s.heading_deg)
	s.roll_factor = club.roll_factor
	return s


## A putt from `at` at `speed` yd/s (clamped to the putter's range) along `aim_deg`.
func putt(field: HeightField, putter: Club, speed: float, at: Vector2, aim_deg: float) -> ShotLaunch:
	assert(putter.is_putter(), "putt() takes the putter")
	var s := ShotLaunch.new()
	s.club = putter
	s.lie = lies.flat(field.surface_at(at.x, at.y))
	s.start = Vector3(at.x, at.y, field.height_at(at.x, at.y))
	s.heading_deg = aim_deg
	var v := clampf(speed, putter.putt_min_speed, putter.putt_max_speed)
	s.ground_velocity = Vector2.RIGHT.rotated(deg_to_rad(aim_deg)) * v
	return s
