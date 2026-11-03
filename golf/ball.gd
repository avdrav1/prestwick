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
## The club's roll factor (D14, golf/clubs.tres): multiplies the ground speed kept after the
## first touchdown, after the surface's bounce friction. 1.0 changes nothing. Set before launch.
var roll_factor: float = 1.0

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
	var first := not has_landed
	if first:
		has_landed = true
		landing_position = at
	var row := surfaces.row(field.surface_at(at.x, at.y))
	if row.roll <= 0.0:
		_rest()
		return
	# The normal tilts by the slope this surface lets the ball feel (felt_gradient).
	var n := HeightField.normal_for(felt_gradient(field.gradient_at(at.x, at.y), row))
	var into := v.dot(n)
	var along := (v - n * into) * (1.0 - row.bounce_friction)
	if first:
		along *= roll_factor
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
	var feel := felt_gradient(grad, row)
	var pull := -feel * params.gravity / (1.0 + feel.length_squared())
	var v := Vector2(velocity.x, velocity.y)
	var full := params.roll_decel / row.roll
	var hold := full * row.rest_decel_scale
	# Axes stopped at a low point this tick (0), and the move that would have crossed it.
	var stop := Vector2.ONE
	var crossing := Vector2.ZERO
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
			stop = keep
			crossing = v
			var floor_feel := feel * keep
			var floor_pull := -floor_feel * params.gravity / (1.0 + floor_feel.length_squared())
			if floor_pull.length() <= hold:
				_rest()
				return
			v = still * keep + floor_pull.normalized() * (floor_pull.length() - hold) * DT
			# If that pull would carry it across the other axis's low point too, it is at the
			# bottom of both (E2-S4 review: it stepped to and fro over a steep pit's centre).
			if _low_point_axes(grad, v) * keep != keep:
				_rest()
				return
	else:
		# Friction = constant part + grass drag that grows with speed. Where the surface holds
		# a still ball more lightly, the constant part rises back to full by decel_ramp_speed.
		# Where drag_full_speed is set (E2-S4), the drag fades below it in proportion to speed.
		var constant := full
		if row.rest_decel_scale != 1.0 and v.length() < row.decel_ramp_speed:
			constant = lerpf(hold, full, v.length() / row.decel_ramp_speed)
		var drag := params.roll_drag * row.drag_scale * v.length() / row.roll
		if row.drag_full_speed > 0.0 and v.length() < row.drag_full_speed:
			drag *= v.length() / row.drag_full_speed
		var friction := constant + drag
		v += pull * DT
		var speed := v.length() - friction * DT
		v = v.normalized() * speed if speed > 0.0 else Vector2.ZERO
		# A ball also stops along an axis where it is about to cross a low point slowly on
		# that axis (E1-S13; per axis since E2-S4), so it does not swing to and fro across a
		# pit's centre or a gully's floor while it runs on along the other axis.
		var keep := _low_point_axes(grad, v)
		if absf(v.x) >= params.low_point_speed:
			keep.x = 1.0
		if absf(v.y) >= params.low_point_speed:
			keep.y = 1.0
		if keep != Vector2.ONE:
			stop = keep
			crossing = v
			v *= keep
	var x := position.x + v.x * DT
	var y := position.y + v.y * DT
	# A stopped axis sits exactly on the low point's line (a tile centre), where the slope
	# along it is the mean of both sides (E2-S4 review): so a ball running down a gully's floor
	# feels the floor's own pull, not one wall's trim of it.
	if stop.x == 0.0:
		x = _low_point_line(position.x, position.x + crossing.x * DT)
	if stop.y == 0.0:
		y = _low_point_line(position.y, position.y + crossing.y * DT)
	position = Vector3(x, y, field.height_at(x, y))
	# Where the ground under the ball turns up against it (a concave crease at a tile centre:
	# a valley floor, the foot of a bank), the ball keeps only its velocity along the new
	# ground (E2-S4).
	var next := field.gradient_at(x, y)
	var met := meet_ground(v, crease_slope(grad, next, v, row), crease_slope(next, grad, v, row, true))
	velocity = Vector3(met.x, met.y, grad.dot(met))


## 0 on each axis (x, y) where this tick's move `v` would carry the ball from ground falling
## along `v` on that axis onto ground rising against it: the bottom of that axis, where the
## bilinear gradient jumps at a tile centre. 1 on the others. Friction only trims the pull,
## so without this nothing damps a slow ball swinging across that jump.
func _low_point_axes(grad: Vector2, v: Vector2) -> Vector2:
	var next := field.gradient_at(position.x + v.x * DT, position.y + v.y * DT)
	return Vector2(
			0.0 if grad.x * v.x < 0.0 and next.x * v.x > 0.0 else 1.0,
			0.0 if grad.y * v.y < 0.0 and next.y * v.y > 0.0 else 1.0)


## The tile centre line (yards on one axis) between `from` and `to`, where a low point's
## gradient jumps; `to` if there is none between them.
func _low_point_line(from: float, to: float) -> float:
	var size := field.yards_per_tile
	var k := floorf(maxf(from, to) / size - 0.5)
	var line := (k + 0.5) * size
	return line if line >= minf(from, to) else to


## The slope a ball feels on the surface of `row` where the terrain's gradient is `grad`
## (dh/dx, dh/dy). On each axis: `slope_scale` of it, plus `steep_scale` of the part steeper
## than `steep_from` (E2-S4), never more than the terrain's own slope. So a green feels a
## gentle contour as a break but a bank steeper than any contour as steep, and a gentle
## gully floor stays gentle between steep walls.
static func felt_gradient(grad: Vector2, row: SurfaceRow) -> Vector2:
	if row.steep_scale <= 0.0:
		return grad * row.slope_scale
	return Vector2(_felt_axis(grad.x, row), _felt_axis(grad.y, row))


static func _felt_axis(g: float, row: SurfaceRow) -> float:
	var steepness := absf(g)
	var felt := steepness * row.slope_scale
	if steepness > row.steep_from:
		felt = minf(felt + (steepness - row.steep_from) * row.steep_scale, steepness)
	return signf(g) * felt


## The slope a crease between terrain gradients `here` and `there` feels, per axis, for a
## ball moving at `v` (`here` is the side it leaves, or the side it meets when `meeting`).
## Across a low point (falling along v, then rising) it is the felt slope, so a steep pit or
## gully floor damps the swing in full. Elsewhere, at the foot of a bank, it is slope_scale
## of the terrain's alone, so on a green a steep bank pulls a ball back hard but does not
## take a putt's speed at its foot (E2-S4 review: a putt could not climb a 3-step tier).
## Off the green both are the terrain's slope.
static func crease_slope(here: Vector2, there: Vector2, v: Vector2, row: SurfaceRow,
		meeting: bool = false) -> Vector2:
	var felt := felt_gradient(here, row)
	var scaled := here * row.slope_scale
	var leave := there if meeting else here
	var meet := here if meeting else there
	return Vector2(
			felt.x if leave.x * v.x < 0.0 and meet.x * v.x > 0.0 else scaled.x,
			felt.y if leave.y * v.y < 0.0 and meet.y * v.y > 0.0 else scaled.y)


## Ground velocity `v` of a ball rolling on slope `from` (dh/dx, dh/dy, as the crease
## feels it) once it is over slope `to` (E2-S4). Per axis, as the low points are: only where
## the new ground rises against the ball more than the old along that axis (a concave crease:
## a valley floor, the foot of an upslope) does the ball lose the part of its velocity along
## the new ground's normal, as rigid ground held to it would take it. On that axis it keeps
## (1 + from * to) / (1 + to²) of its speed: 72% across a one-step V floor at slope_scale 1.0,
## all of it onto a flat foot. At a convex crease (a lip, or onto a steeper downhill) and
## where the slope is the same, that axis is unchanged, so a ball over a drop runs on as far
## as on flat ground. A crease never adds ground speed (from a steep downhill onto a gentler
## one the projection would) and never turns the ball back: past a 90 degree crease that axis
## stops instead.
static func meet_ground(v: Vector2, from: Vector2, to: Vector2) -> Vector2:
	return Vector2(_meet_axis(v.x, from.x, to.x), _meet_axis(v.y, from.y, to.y))


static func _meet_axis(v: float, from: float, to: float) -> float:
	if (to - from) * v <= 0.0:
		return v
	return v * clampf((1.0 + from * to) / (1.0 + to * to), 0.0, 1.0)


func _rest() -> void:
	velocity = Vector3.ZERO
	state = State.AT_REST
