class_name ShotPrediction
extends RefCounted
## Where a shot will go, found by running the real ball ahead of time: a seeded Ball,
## stepped with the same Ball.step the live ball uses, until it comes to rest. Nothing is
## approximated, so a live ball with the same course, seed and launch follows this path
## tick for tick (E1-S7). Usable without a scene (the aim marker, guests).

## Every tick's position, yards, from the launch point to the rest point.
var path: PackedVector3Array = PackedVector3Array()
## First touchdown (the carry), yards.
var landing: Vector3 = Vector3.ZERO
## Where the ball comes to rest, yards.
var rest: Vector3 = Vector3.ZERO
var landing_tile: Vector2i = Vector2i.ZERO
var rest_tile: Vector2i = Vector2i.ZERO
## Ticks from launch to rest.
var ticks: int = 0


## Predicts a flight launched from `start` (yards) at `velocity` (yd/s) with seed `rng_seed`.
## `roll_factor` is the club's (D14, Ball.roll_factor).
static func run(course: CourseData, rng_seed: int, start: Vector3, velocity: Vector3,
		params: BallParams = null, surfaces: SurfaceTable = null,
		roll_factor: float = 1.0) -> ShotPrediction:
	var ball := Ball.new(course, rng_seed, params, surfaces)
	ball.record_path = true
	ball.roll_factor = roll_factor
	ball.launch(start, velocity)
	return _from(ball)


## Predicts a stroke built by ShotModel (a flight or a putt) with seed `rng_seed`.
static func run_launch(course: CourseData, rng_seed: int, shot: ShotLaunch,
		params: BallParams = null, surfaces: SurfaceTable = null) -> ShotPrediction:
	var ball := Ball.new(course, rng_seed, params, surfaces)
	ball.record_path = true
	shot.apply(ball)
	return _from(ball)


static func _from(ball: Ball) -> ShotPrediction:
	ball.run_to_rest()
	var p := ShotPrediction.new()
	p.path = ball.path
	p.landing = ball.landing_position
	p.rest = ball.position
	p.landing_tile = ball.field.tile_at(p.landing.x, p.landing.y)
	p.rest_tile = ball.field.tile_at(p.rest.x, p.rest.y)
	p.ticks = ball.steps
	return p
