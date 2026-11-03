class_name ShotLaunch
extends RefCounted
## One stroke's launch, as ShotModel builds it (D14): everything decided before the ball
## moves, so the aim marker (ShotPrediction) and the live ball start from the same numbers.

var club: Club
var lie: Lie
## Where the ball starts, yards (on the ground).
var start: Vector3 = Vector3.ZERO
## A full club's launch velocity, yd/s. Unused for a putt.
var velocity: Vector3 = Vector3.ZERO
## A putt's starting ground velocity, yd/s. Unused for a full club.
var ground_velocity: Vector2 = Vector2.ZERO
## The heading the ball actually leaves on: aim + accuracy offset + sidehill turn.
var heading_deg: float = 0.0
## `carry × power × lie` for a full club (yards); 0 for a putt.
var target_carry: float = 0.0
var roll_factor: float = 1.0


func is_putt() -> bool:
	return club != null and club.is_putter()


## Sends `ball` off: a flight for a full club, a roll for the putter.
func apply(ball: Ball) -> void:
	ball.roll_factor = roll_factor
	if is_putt():
		ball.start_roll(Vector2(start.x, start.y), ground_velocity)
	else:
		ball.launch(start, velocity)
