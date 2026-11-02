class_name Ball
extends RefCounted
## Custom ball physics (D1): a 3D point stepped at a fixed 60 Hz over the height map.
## No scene and no physics bodies, so the shot preview (E1-S7) and off-screen guests run
## the same step. Units are yards and seconds: x and y on the ground from the map corner,
## z up (HeightField has the yard <-> tile conversions).
##
## A shot: launch() -> FLYING under gravity -> first touchdown sets landing_position ->
## at most one bounce, by surface -> ROLLING along the ground with slope and surface
## friction -> AT_REST. Randomness (bounce scatter) comes only from this ball's own
## generator, so the same seed and inputs give the same result bit for bit.
## Hazards (water, trees, OB penalties) are E2-S6; for now they are rows in the table.

enum State { READY, FLYING, ROLLING, AT_REST }

const TICK_HZ: int = 60
const DT: float = 1.0 / TICK_HZ
## docs/design.md Ball: one bounce on landing, then roll.
const MAX_BOUNCES: int = 1
## Bisection steps that find the touchdown point inside a tick (1/4096 of a tick).
const CONTACT_ITERATIONS: int = 12

var params: BallParams
var surfaces: SurfaceTable
var field: HeightField

var state: State = State.READY
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Ticks since launch.
var steps: int = 0
var bounces: int = 0
## Where the ball first touched the ground (the carry), valid once has_landed.
var landing_position: Vector3 = Vector3.ZERO
var has_landed: bool = false
## When true, every tick appends the position to `path` (for drawing or prediction).
var record_path: bool = false
var path: PackedVector3Array = PackedVector3Array()

var _rng := RandomNumberGenerator.new()


## `params` and `surfaces` default to golf/ball_params.tres and course/surfaces.tres.
func _init(course: CourseData, rng_seed: int, p_params: BallParams = null,
		p_surfaces: SurfaceTable = null) -> void:
	params = p_params if p_params != null else BallParams.load_default()
	surfaces = p_surfaces if p_surfaces != null else SurfaceTable.load_default()
	field = HeightField.new(course, params)
	_rng.seed = rng_seed


## Velocity in yd/s for a ball struck at `speed` yd/s, `launch_deg` above the ground and
## `heading_deg` around from +x towards +y.
static func launch_velocity(speed: float, launch_deg: float, heading_deg: float) -> Vector3:
	var up := deg_to_rad(launch_deg)
	var around := deg_to_rad(heading_deg)
	var flat := speed * cos(up)
	return Vector3(flat * cos(around), flat * sin(around), speed * sin(up))


## Starts a flight from `start` (yards; a z below the ground is lifted onto it).
func launch(start: Vector3, p_velocity: Vector3) -> void:
	_reset(start)
	velocity = p_velocity
	state = State.FLYING


## Starts the ball rolling on the ground at `start` with ground speed `ground_velocity`
## (a putt). Counts as landed where it starts.
func start_roll(start: Vector2, ground_velocity: Vector2) -> void:
	_reset(Vector3(start.x, start.y, 0.0))
	has_landed = true
	landing_position = position
	velocity = Vector3(ground_velocity.x, ground_velocity.y, 0.0)
	state = State.ROLLING


func is_at_rest() -> bool:
	return state == State.AT_REST


## One 1/60 s tick. Does nothing before launch or at rest.
func step() -> void:
	match state:
		State.FLYING:
			_step_flight()
		State.ROLLING:
			_step_roll()
		_:
			return
	steps += 1
	if state != State.AT_REST and steps >= params.max_steps:
		_rest()
	if record_path:
		path.append(position)


## Steps until the ball is at rest. Returns the number of ticks this call took.
func run_to_rest() -> int:
	var start := steps
	while state == State.FLYING or state == State.ROLLING:
		step()
	return steps - start


# --- internals ---

func _reset(start: Vector3) -> void:
	position = Vector3(start.x, start.y, maxf(start.z, field.height_at(start.x, start.y)))
	velocity = Vector3.ZERO
	steps = 0
	bounces = 0
	has_landed = false
	landing_position = Vector3.ZERO
	path = PackedVector3Array()
	if record_path:
		path.append(position)


## Flight position `t` of the way through the current tick (0 to 1).
func _flight_at(t: float) -> Vector3:
	var s := t * DT
	return position + velocity * s + Vector3(0.0, 0.0, -0.5 * params.gravity * s * s)


func _below(p: Vector3) -> bool:
	return p.z < field.height_at(p.x, p.y)


func _step_flight() -> void:
	# Check the middle of the tick too, so a sharp crest cannot be skipped.
	var lo := -1.0
	var hi := -1.0
	if _below(_flight_at(0.5)):
		lo = 0.0
		hi = 0.5
	elif _below(_flight_at(1.0)):
		lo = 0.5
		hi = 1.0
	if hi < 0.0:
		position = _flight_at(1.0)
		velocity.z -= params.gravity * DT
		return
	for i in CONTACT_ITERATIONS:
		var mid := (lo + hi) * 0.5
		if _below(_flight_at(mid)):
			hi = mid
		else:
			lo = mid
	var hit := _flight_at(hi)
	var hit_velocity := velocity + Vector3(0.0, 0.0, -params.gravity * hi * DT)
	_touch_down(Vector3(hit.x, hit.y, field.height_at(hit.x, hit.y)), hit_velocity)


func _touch_down(at: Vector3, v: Vector3) -> void:
	position = at
	if not has_landed:
		has_landed = true
		landing_position = at
	var row := surfaces.row(field.surface_at(at.x, at.y))
	if row.roll <= 0.0:
		_rest()
		return
	# The normal tilts by the slope this surface lets the ball feel (slope_scale).
	var n := HeightField.normal_for(field.gradient_at(at.x, at.y) * row.slope_scale)
	var into := v.dot(n)
	var along := (v - n * into) * (1.0 - row.bounce_friction)
	# Always draw, so the generator stream does not depend on which branch runs.
	var turn := deg_to_rad(_rng.randf_range(-row.scatter_deg, row.scatter_deg))
	var out := -into * row.bounce
	if bounces < MAX_BOUNCES and out >= params.min_bounce_speed:
		bounces += 1
		var flat := Vector2(along.x, along.y).rotated(turn)
		velocity = Vector3(flat.x, flat.y, along.z) + n * out
		state = State.FLYING
	else:
		velocity = Vector3(along.x, along.y, 0.0)
		state = State.ROLLING


func _step_roll() -> void:
	var row := surfaces.row(field.surface_at(position.x, position.y))
	if row.roll <= 0.0:
		_rest()
		return
	var grad := field.gradient_at(position.x, position.y)
	# Gravity along the slope the surface lets the ball feel, projected onto the ground
	# plane. Peaks at gravity / 2.
	var feel := grad * row.slope_scale
	var pull := -feel * params.gravity / (1.0 + feel.length_squared())
	var v := Vector2(velocity.x, velocity.y)
	var full := params.roll_decel / row.roll
	var hold := full * row.rest_decel_scale
	if v.length() < params.rest_speed:
		# Static: stays put unless the slope pulls harder than the constant friction.
		if pull.length() <= hold:
			_rest()
			return
		var still := v
		v += pull.normalized() * (pull.length() - hold) * DT
		# At a low point (E1-S13), per axis: see _low_point_axes. With both axes stopped (a
		# pit) it rests. With one stopped (a gully that slopes along its length) it goes on
		# down the other, pulled by that axis's slope alone, as on the gully's floor line,
		# and rests only if that pull is no more than the hold.
		var keep := _low_point_axes(grad, v)
		if keep != Vector2.ONE:
			var floor_feel := feel * keep
			var floor_pull := -floor_feel * params.gravity / (1.0 + floor_feel.length_squared())
			if floor_pull.length() <= hold:
				_rest()
				return
			v = still * keep + floor_pull.normalized() * (floor_pull.length() - hold) * DT
	else:
		# Friction = constant part + grass drag that grows with speed. Where the surface holds
		# a still ball more lightly, the constant part rises back to full by decel_ramp_speed.
		var constant := full
		if row.rest_decel_scale != 1.0 and v.length() < row.decel_ramp_speed:
			constant = lerpf(hold, full, v.length() / row.decel_ramp_speed)
		var friction := constant + params.roll_drag * row.drag_scale * v.length() / row.roll
		v += pull * DT
		var speed := v.length() - friction * DT
		v = v.normalized() * speed if speed > 0.0 else Vector2.ZERO
		# A slow ball also stops along an axis where it is about to cross a low point
		# (E1-S13), so it does not swing to and fro across a pit's centre or a gully's floor.
		if v.length() < params.low_point_speed:
			v *= _low_point_axes(grad, v)
	var x := position.x + v.x * DT
	var y := position.y + v.y * DT
	position = Vector3(x, y, field.height_at(x, y))
	velocity = Vector3(v.x, v.y, grad.dot(v))


## 0 on each axis (x, y) where this tick's move `v` would carry the ball from ground falling
## along `v` on that axis onto ground rising against it: the bottom of that axis, where the
## bilinear gradient jumps at a tile centre. 1 on the others. Friction only trims the pull,
## so without this nothing damps a slow ball swinging across that jump.
func _low_point_axes(grad: Vector2, v: Vector2) -> Vector2:
	var next := field.gradient_at(position.x + v.x * DT, position.y + v.y * DT)
	return Vector2(
			0.0 if grad.x * v.x < 0.0 and next.x * v.x > 0.0 else 1.0,
			0.0 if grad.y * v.y < 0.0 and next.y * v.y > 0.0 else 1.0)


func _rest() -> void:
	velocity = Vector3.ZERO
	state = State.AT_REST
