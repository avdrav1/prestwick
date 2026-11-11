class_name ReferenceBall
extends RefCounted
## E7-S4 test oracle: golf/ball.gd as it was before E7-S4 spelled its tick out (Ball.run),
## reading the ground through ReferenceField. tests/test_ball_kernel.gd steps it beside Ball
## and checks every tick is the same, bit for bit. Kept as it was; not used by the game.
##
## Custom ball physics (D1): a 3D point stepped at a fixed 60 Hz over the height map.
## No scene and no physics bodies, so the shot preview (E1-S7) and off-screen guests run
## the same step. Units are yards and seconds: x and y on the ground from the map corner,
## z up (HeightField has the yard <-> tile conversions).
##
## A shot: launch() -> FLYING under gravity -> first touchdown sets landing_position ->
## at most one bounce, by surface, its rise held to the bounce budget (E6-S34) -> ROLLING
## along the ground with slope and surface friction -> AT_REST. Randomness (bounce scatter)
## comes only from this ball's own generator, so the same seed and inputs give the same
## result bit for bit.
##
## Cup and hazards (D15, E2-S6; docs/design.md Ball, Cup and hazards): the cup (set_cup)
## captures a slow ball at the end of a rolling tick. A ball that stops on water or OB
## (an `oob` tile, off the map, or land the player does not own, D29) is dropped, at rest, with one penalty stroke, and reports
## it (penalty_strokes, hazard, entry_point, drop_point). A flight lower than the trees row's
## block_height over trees is scattered back toward the start; a rolling ball stops at the
## edge of trees. A ball never rests on water, OB or inside trees.

enum State { READY, FLYING, ROLLING, AT_REST }
## Which hazard dropped the ball (D15). OB is an `oob` tile, off the map, or a tile of a
## parcel the player does not own (D29: HeightField.surface_at reads it as `oob`).
enum Hazard { NONE, WATER, OB }

const TICK_HZ: int = 60
const DT: float = 1.0 / TICK_HZ
## docs/design.md Ball: one bounce on landing, then roll.
const MAX_BOUNCES: int = 1
## Bisection steps that find the touchdown point inside a tick (1/4096 of a tick).
const CONTACT_ITERATIONS: int = 12
## Bisection steps that find a hazard's entry point between two track points.
const ENTRY_ITERATIONS: int = 16
## No cup set (set_cup): nothing captures the ball.
const NO_CUP: Vector2i = Vector2i(-1, -1)

var params: BallParams
var surfaces: SurfaceTable
var field: ReferenceField

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
## The cup's tile (D15: it sits at the tile's centre), or NO_CUP. Set before launch; a new
## stroke keeps it.
var cup_tile: Vector2i = NO_CUP

## True once the cup captured the ball; it then rests at the cup's centre.
var holed: bool = false
## 1 when the ball stopped on water or OB and was dropped (D15), else 0.
var penalty_strokes: int = 0
var hazard: Hazard = Hazard.NONE
## Where the ground track last crossed into the hazard it stopped in, yards (x, y).
var entry_point: Vector2 = Vector2.ZERO
## Where the ball was dropped, at rest, yards. Equal to `position` after a drop.
var drop_point: Vector3 = Vector3.ZERO
## Where the ball stopped in the hazard before the drop, yards. `path` ends here.
var hazard_position: Vector3 = Vector3.ZERO
## True once a flight was blocked by trees and scattered (D15).
var scattered: bool = false
## Where the flight was blocked, yards.
var scatter_from: Vector3 = Vector3.ZERO
## Where the flight first met something, yards: its first touchdown, or the point trees
## blocked it before any touchdown (scatter_from); the start until then, and for a putt.
## Bookkeeping only, for D20's blocked rule; the physics never reads it.
var stop_point: Vector3 = Vector3.ZERO
## The flight's velocity there, yd/s. z > 0: it was stopped while still climbing.
var stop_velocity: Vector3 = Vector3.ZERO

var _rng := RandomNumberGenerator.new()
## The stroke's start, yards (the drop of last resort, D15).
var _start: Vector3 = Vector3.ZERO
## The ground track (x and y of every tick, flight and roll alike), walked back for a drop.
var _track: PackedVector2Array = PackedVector2Array()


## `params` and `surfaces` default to golf/ball_params.tres and course/surfaces.tres.
func _init(course: CourseData, rng_seed: int, p_params: BallParams = null,
		p_surfaces: SurfaceTable = null) -> void:
	params = p_params if p_params != null else BallParams.load_default()
	surfaces = p_surfaces if p_surfaces != null else SurfaceTable.load_default()
	field = ReferenceField.new(course, params)
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


## Puts the cup on `tile` (at its centre), or takes it away with NO_CUP.
func set_cup(tile: Vector2i) -> void:
	cup_tile = tile


func has_cup() -> bool:
	return cup_tile != NO_CUP


## Centre of the cup, yards.
func cup_center() -> Vector2:
	return field.tile_center(cup_tile)


## True when a ball at ground point `at` moving at `ground_speed` yd/s is captured: within
## cup_radius of the cup's centre and no faster than cup_capture_speed, both included (D15).
func captures(at: Vector2, ground_speed: float) -> bool:
	return has_cup() and at.distance_to(cup_center()) <= params.cup_radius \
			and ground_speed <= params.cup_capture_speed


## One 1/60 s tick. Does nothing before launch or at rest.
func step() -> void:
	var rolling := state == State.ROLLING
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
	# The cup checks at the end of every rolling tick, never at touchdown (D15). A drop never
	# captures (and never lands on the cup's tile, so the next stroke cannot be a free tap-in).
	if rolling and penalty_strokes == 0 and not holed \
			and captures(Vector2(position.x, position.y), Vector2(velocity.x, velocity.y).length()):
		_hole()
	# The track and the path end where the ball stopped in a hazard, not at the drop.
	var shown := hazard_position if penalty_strokes > 0 else position
	_track.append(Vector2(shown.x, shown.y))
	if record_path:
		path.append(shown)


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
	holed = false
	penalty_strokes = 0
	hazard = Hazard.NONE
	entry_point = Vector2.ZERO
	drop_point = Vector3.ZERO
	hazard_position = Vector3.ZERO
	scattered = false
	scatter_from = Vector3.ZERO
	stop_point = position
	stop_velocity = Vector3.ZERO
	_start = position
	_track = PackedVector2Array([Vector2(position.x, position.y)])
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
		if _blocked_in(1.0):
			return
		position = _flight_at(1.0)
		velocity.z -= params.gravity * DT
		return
	for i in CONTACT_ITERATIONS:
		var mid := (lo + hi) * 0.5
		if _below(_flight_at(mid)):
			hi = mid
		else:
			lo = mid
	# Trees block a flight before it reaches their ground.
	if _blocked_in(hi):
		return
	var hit := _flight_at(hi)
	var hit_velocity := velocity + Vector3(0.0, 0.0, -params.gravity * hi * DT)
	_touch_down(Vector3(hit.x, hit.y, field.height_at(hit.x, hit.y)), hit_velocity)


## True when trees block the flight within the first `t` of this tick (checked at its
## middle and at `t`), after scattering it. A tile is 5 yd and a tick moves the ball at most
## about 1.3 yd, so a flight cannot cross a tree tile between checks.
func _blocked_in(t: float) -> bool:
	for at: float in [t * 0.5, t]:
		var p := _flight_at(at)
		if _blocks(p):
			_scatter(p, velocity + Vector3(0.0, 0.0, -params.gravity * at * DT))
			return true
	return false


## True when a flight at `p` is inside trees: over a tree tile, lower than the trees row's
## block_height above that tile's top (its whole height, as drawn, not the bilinear ground,
## which leans up toward a higher neighbour), or meeting its ground. Trees on unowned land
## block too (HeightField.painted_surface_at, D29): they stand there and are drawn there; the
## scatter then rests only on owned land (may_rest_on).
func _blocks(p: Vector3) -> bool:
	if field.painted_surface_at(p.x, p.y) != Surface.Type.TREES:
		return false
	var row := surfaces.row(Surface.Type.TREES)
	if row.block_height <= 0.0:
		return false
	var t := field.tile_at(p.x, p.y)
	var top := field.course.get_height(t.x, t.y) * field.yards_per_step
	return p.z < top + row.block_height or _below(p)


## Tree scatter (D15): from the blocked point `from`, a target 1 to 2 tiles back toward the
## start (within tree_scatter_cone_deg of the reversed heading), drawn from the ball's own
## generator and redrawn off trees, water and OB, and off the cup's disc (a still ball there
## would be holed on its next tick, E6-S13), up to tree_scatter_draws times; failing that,
## the nearest tile centre the game may place a ball on (_nearest_open: never the cup's tile,
## and with none on the map, _last_resort's point clear of the cup). The ball comes down
## there with no speed, a still ball.
func _scatter(from: Vector3, v: Vector3) -> void:
	scattered = true
	scatter_from = from
	if not has_landed:
		stop_point = from
		stop_velocity = v
	var here := Vector2(from.x, from.y)
	var back := -Vector2(v.x, v.y)
	if back.length_squared() < 1e-8:
		back = Vector2(_start.x, _start.y) - here
	if back.length_squared() < 1e-8:
		back = Vector2.LEFT
	var base := back.angle()
	var target := Vector2.ZERO
	var found := false
	for i in params.tree_scatter_draws:
		var d := _rng.randf_range(params.tree_scatter_min_yd, params.tree_scatter_max_yd)
		var turn := deg_to_rad(_rng.randf_range(-params.tree_scatter_cone_deg,
				params.tree_scatter_cone_deg))
		var q := here + Vector2.from_angle(base + turn) * d
		if may_rest_on(field.tile_at(q.x, q.y)) and _clear_of_cup(q):
			target = q
			found = true
			break
	if not found:
		target = _nearest_open(here)
	position = Vector3(target.x, target.y, field.height_at(target.x, target.y))
	velocity = Vector3.ZERO
	if not has_landed:
		has_landed = true
		landing_position = position
	state = State.ROLLING


## True when a ball may come to rest on `tile`: on the map, on owned land (D29), and not
## water, `oob` or trees.
func may_rest_on(tile: Vector2i) -> bool:
	if not field.course.in_bounds(tile.x, tile.y):
		return false
	var s := field.surface_of(tile)
	return s != Surface.Type.WATER and s != Surface.Type.OOB and s != Surface.Type.TREES


## True when the game may place a ball at rest on `tile`'s centre: it may rest there and
## it is not the cup's tile. The cup sits at its tile's centre, so a ball placed there (a
## drop, or a move off trees) would be holed by any tap on the next stroke (D15).
func may_place_on(tile: Vector2i) -> bool:
	return may_rest_on(tile) and tile != cup_tile


## The nearest tile centre the game may place a ball on (may_place_on), searched ring by
## ring outward from the tile under `at` (yards): in the first ring that has one, the
## centre nearest `at`, ties in row-major order. The stroke's start if the map has none.
func _nearest_open(at: Vector2) -> Vector2:
	var c := field.tile_at(at.x, at.y)
	var rings := maxi(field.course.width, field.course.height)
	for r in rings + 1:
		var best := Vector2.ZERO
		var best_d := INF
		for j in range(c.y - r, c.y + r + 1):
			for i in range(c.x - r, c.x + r + 1):
				if maxi(absi(i - c.x), absi(j - c.y)) != r or not may_place_on(Vector2i(i, j)):
					continue
				var centre := field.tile_center(Vector2i(i, j))
				var d := centre.distance_squared_to(at)
				if d < best_d:
					best_d = d
					best = centre
		if best_d < INF:
			return best
	return _last_resort()


## True when a ball placed at rest at ground point `at` cannot be holed by a tap: there is no
## cup, or `at` is further than cup_radius from its centre (E2-S13).
func _clear_of_cup(at: Vector2) -> bool:
	return not has_cup() or at.distance_to(cup_center()) > params.cup_radius


## Where the game places a ball when no tile on the map may take one (E2-S13): the stroke's
## start, unless that is within cup_radius of the cup (where the next tap could be holed);
## then cup_clear_drop_yd from the cup's centre, on its own tile, toward the start.
func _last_resort() -> Vector2:
	var s := Vector2(_start.x, _start.y)
	if _clear_of_cup(s):
		return s
	var c := cup_center()
	var away := s - c
	if away.length_squared() < 1e-8:
		away = Vector2.LEFT
	return c + away.normalized() * params.cup_clear_drop_yd


func _touch_down(at: Vector3, v: Vector3) -> void:
	position = at
	var first := not has_landed
	if first:
		has_landed = true
		landing_position = at
		stop_point = at
		stop_velocity = v
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
		velocity.z = minf(velocity.z, max_bounce_lift(params))
		state = State.FLYING
	else:
		velocity = Vector3(along.x, along.y, 0.0)
		state = State.ROLLING


## The fastest a bounce may leave the ground upward, yd/s (E6-S34): the speed that comes back
## to the touchdown height after `max_bounce_s`, the bounce budget. INF with no budget.
static func max_bounce_lift(p: BallParams) -> float:
	return p.gravity * p.max_bounce_s * 0.5 if p.max_bounce_s > 0.0 else INF


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
		# Downhill (E6-S10): where the slope pulls the ball on along its line, the friction
		# falls toward downhill_friction_scale of itself, so a long slope off the green is run
		# at pace, not at the crawl where a one-step pull meets the drag.
		var downhill := downhill_share(pull, v, full)
		if downhill > 0.0:
			var keep := lerpf(1.0, row.downhill_friction_scale, downhill)
			constant *= keep
			drag *= keep
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
	# A rolling ball stops where it is at the edge of trees, as if against the trunks (D15).
	if field.surface_at(x, y) == Surface.Type.TREES \
			and field.surface_at(position.x, position.y) != Surface.Type.TREES:
		_rest()
		return
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
	var met := meet_ground(v, crease_slope(grad, next, v, row), crease_slope(next, grad, v, row, true),
			row.floor_keep, row.floor_keep_speed)
	velocity = Vector3(met.x, met.y, grad.dot(met))


## How much the slope pulls a ball moving at `v` on along its line, as a share of the
## constant friction `full` (E6-S10): 1 wherever that pull is at least the constant friction
## (every slope of a step per tile or more, off the green), less on a gentler downhill, and 0
## on flat ground, straight across a slope and uphill.
static func downhill_share(pull: Vector2, v: Vector2, full: float) -> float:
	var speed := v.length()
	if speed <= 0.0 or full <= 0.0:
		return 0.0
	return clampf(pull.dot(v / speed) / full, 0.0, 1.0)


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
## stops instead. Across a low point on that axis (falling, then rising: a valley or pit
## floor) the ball keeps only `floor_keep` (the row's, E6-S10) of what rigid ground leaves it,
## as a ball thuds into the far wall, so a swing across a valley floor dies in a few passes;
## the thud fades out by `floor_keep_speed` (floor_thud), so a fast roll through a dip runs on.
static func meet_ground(v: Vector2, from: Vector2, to: Vector2, floor_keep: float = 1.0,
		floor_keep_speed: float = 0.0) -> Vector2:
	return Vector2(_meet_axis(v.x, from.x, to.x, floor_keep, floor_keep_speed),
			_meet_axis(v.y, from.y, to.y, floor_keep, floor_keep_speed))


static func _meet_axis(v: float, from: float, to: float, floor_keep: float = 1.0,
		floor_keep_speed: float = 0.0) -> float:
	if (to - from) * v <= 0.0:
		return v
	var keep := clampf((1.0 + from * to) / (1.0 + to * to), 0.0, 1.0)
	if from * v < 0.0 and to * v > 0.0:
		keep *= floor_thud(absf(v), floor_keep, floor_keep_speed)
	return v * keep


## The share of its speed along an axis that a ball crossing a low point at `speed` (yd/s,
## on that axis) keeps on top of the rigid-ground share (E6-S10 review): `floor_keep` for a
## still ball, rising in proportion to speed back to all of it at `floor_keep_speed`, so a
## slow swing across a valley floor dies out while a fast roll through a dip runs on as
## before. A `floor_keep_speed` of 0 takes `floor_keep` at every speed.
static func floor_thud(speed: float, floor_keep: float, floor_keep_speed: float) -> float:
	if floor_keep_speed <= 0.0:
		return floor_keep
	return lerpf(floor_keep, 1.0, clampf(speed / floor_keep_speed, 0.0, 1.0))


## Every way to rest comes here, so a ball never rests on water, OB or inside trees (D15).
func _rest() -> void:
	velocity = Vector3.ZERO
	state = State.AT_REST
	var h := hazard_at(Vector2(position.x, position.y))
	if h != Hazard.NONE:
		_drop(h)
	elif field.surface_at(position.x, position.y) == Surface.Type.TREES:
		# Only when trees block nothing (block_height 0) can a ball reach their ground.
		var open := _nearest_open(Vector2(position.x, position.y))
		position = Vector3(open.x, open.y, field.height_at(open.x, open.y))


## The hazard under ground point `at`: water, OB (an `oob` tile, off the map or unowned
## land), or none.
func hazard_at(at: Vector2) -> Hazard:
	match field.surface_at(at.x, at.y):
		Surface.Type.WATER:
			return Hazard.WATER
		Surface.Type.OOB:
			return Hazard.OB
	return Hazard.NONE


## Water and OB (D15): walk the ground track back to where it last crossed into hazard `h`
## (the entry point), then drop the ball at rest on the centre of the tile the track was
## over just before it, or further back past water, OB, trees and the cup's tile, else at the
## stroke's start. A start within cup_radius of the cup would leave a free tap-in, so then
## the nearest tile centre the game may place a ball on (E2-S13, _nearest_open).
## One penalty stroke.
func _drop(h: Hazard) -> void:
	hazard = h
	penalty_strokes = 1
	hazard_position = position
	var track := _track.duplicate()
	track.append(Vector2(position.x, position.y))
	var drop := Vector2(_start.x, _start.y)
	if not _clear_of_cup(drop):
		drop = _nearest_open(drop)
	var i := track.size() - 2
	while i >= 0 and not (hazard_at(track[i]) != h and hazard_at(track[i + 1]) == h):
		i -= 1
	if i >= 0:
		var lo := track[i]
		var hi := track[i + 1]
		for k in ENTRY_ITERATIONS:
			var mid := (lo + hi) * 0.5
			if hazard_at(mid) == h:
				hi = mid
			else:
				lo = mid
		entry_point = hi
		# The tile just before the entry point, then each earlier track point's tile.
		var tiles: Array[Vector2i] = [field.tile_at(lo.x, lo.y)]
		for k in range(i, -1, -1):
			tiles.append(field.tile_at(track[k].x, track[k].y))
		for t in tiles:
			if may_place_on(t):
				drop = field.tile_center(t)
				break
	else:
		entry_point = Vector2(position.x, position.y)
	position = Vector3(drop.x, drop.y, field.height_at(drop.x, drop.y))
	drop_point = position
	velocity = Vector3.ZERO
	state = State.AT_REST


## The cup captured the ball: it rests at the cup's centre.
func _hole() -> void:
	holed = true
	var c := cup_center()
	position = Vector3(c.x, c.y, field.height_at(c.x, c.y))
	velocity = Vector3.ZERO
	state = State.AT_REST
