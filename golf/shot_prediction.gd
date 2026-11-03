class_name ShotPrediction
extends RefCounted
## Where a shot will go, found by running the real ball ahead of time: a seeded Ball,
## stepped with the same Ball.step the live ball uses, until it comes to rest. Nothing is
## approximated, so a live ball with the same course, seed and launch follows this path
## tick for tick (E1-S7). Usable without a scene (the aim marker, guests).

## Every tick's position, yards, from the launch point to the rest point (to where it
## stopped in a hazard, when it was dropped).
var path: PackedVector3Array = PackedVector3Array()
## First touchdown (the carry), yards.
var landing: Vector3 = Vector3.ZERO
## Ground distance from the launch point to the first touchdown, yards (0 for a putt, which
## counts as landed where it starts). Unsigned: a flight scattered back off trees counts
## its distance behind the start too.
var carry_yd: float = 0.0
## Where the flight first met the ground or trees, yards (Ball.stop_point): the first
## touchdown, or the point trees blocked it. For a putt, the start.
var stop_point: Vector3 = Vector3.ZERO
## D20: the flight met the ground or trees while still climbing, before its apex: the face
## or trees ahead stop it. ClubSet.is_blocked reads it.
var stopped_climbing: bool = false
## Where the ball comes to rest, yards: the drop point after water or OB, the cup's centre
## when holed.
var rest: Vector3 = Vector3.ZERO
var landing_tile: Vector2i = Vector2i.ZERO
var rest_tile: Vector2i = Vector2i.ZERO
## Ticks from launch to rest.
var ticks: int = 0
## The cup captured the ball (E2-S6).
var holed: bool = false
## 1 when the ball was dropped from water or OB (E2-S6), with the hazard it stopped in.
var penalty_strokes: int = 0
var hazard: Ball.Hazard = Ball.Hazard.NONE
## Trees blocked the flight and scattered it (E2-S6).
var scattered: bool = false


## Predicts a flight launched from `start` (yards) at `velocity` (yd/s) with seed `rng_seed`.
## `roll_factor` is the club's (D14, Ball.roll_factor). `cup_tile` is the hole's cup, or
## Ball.NO_CUP.
static func run(course: CourseData, rng_seed: int, start: Vector3, velocity: Vector3,
		params: BallParams = null, surfaces: SurfaceTable = null,
		roll_factor: float = 1.0, cup_tile: Vector2i = Ball.NO_CUP) -> ShotPrediction:
	var ball := Ball.new(course, rng_seed, params, surfaces)
	ball.record_path = true
	ball.roll_factor = roll_factor
	ball.set_cup(cup_tile)
	ball.launch(start, velocity)
	return _from(ball, start)


## Predicts a stroke built by ShotModel (a flight or a putt) with seed `rng_seed`.
static func run_launch(course: CourseData, rng_seed: int, shot: ShotLaunch,
		params: BallParams = null, surfaces: SurfaceTable = null,
		cup_tile: Vector2i = Ball.NO_CUP) -> ShotPrediction:
	var ball := Ball.new(course, rng_seed, params, surfaces)
	ball.record_path = true
	ball.set_cup(cup_tile)
	shot.apply(ball)
	return _from(ball, shot.start)


static func _from(ball: Ball, start: Vector3) -> ShotPrediction:
	ball.run_to_rest()
	var p := ShotPrediction.new()
	p.path = ball.path
	p.landing = ball.landing_position
	p.carry_yd = Vector2(start.x, start.y).distance_to(Vector2(p.landing.x, p.landing.y))
	p.stop_point = ball.stop_point
	p.stopped_climbing = ball.stop_velocity.z > 0.0
	p.rest = ball.position
	p.landing_tile = ball.field.tile_at(p.landing.x, p.landing.y)
	p.rest_tile = ball.field.tile_at(p.rest.x, p.rest.y)
	p.ticks = ball.steps
	p.holed = ball.holed
	p.penalty_strokes = ball.penalty_strokes
	p.hazard = ball.hazard
	p.scattered = ball.scattered
	return p
