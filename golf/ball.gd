class_name Ball
extends RefCounted
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
## E7-S4: kept only when the path is not (record_path at launch): the path's x and y are it.
var _track: PackedVector2Array = PackedVector2Array()
var _track_in_path: bool = false
## E7-S4: the cup's centre (cup_center) for the tile `_cup_centre_tile`, worked out once.
var _cup_centre: Vector2 = Vector2.ZERO
var _cup_centre_tile: Vector2i = NO_CUP

## E7-S4, the tick's own copies (_take_params, _take_terrain): a tick reads only these members
## and its locals, not `params`, `surfaces` or `field`, so it pays no GDScript call or object
## lookup for each of the dozens of numbers a tick reads, and guests' balls stepped on several
## threads at once (GuestBrain.serve_second) do not queue on the engine's object lock. The
## numbers are the same, so a tick's result is the same bit for bit (tests/test_ball_kernel.gd).
## BallParams, as of the last launch (_reset).
var _gravity: float = 0.0
var _roll_decel: float = 0.0
var _roll_drag: float = 0.0
var _rest_speed: float = 0.0
var _low_point_speed: float = 0.0
var _cup_radius: float = 0.0
var _cup_capture_speed: float = 0.0
var _max_steps: int = 0
## Each SurfaceRow's numbers a roll reads, by Surface.Type, as of the last launch.
var _row_roll := PackedFloat64Array()
var _row_slope := PackedFloat64Array()
var _row_steep_from := PackedFloat64Array()
var _row_steep_scale := PackedFloat64Array()
var _row_rest_decel := PackedFloat64Array()
var _row_ramp := PackedFloat64Array()
var _row_drag := PackedFloat64Array()
var _row_drag_full := PackedFloat64Array()
var _row_downhill := PackedFloat64Array()
var _row_floor_keep := PackedFloat64Array()
var _row_floor_keep_speed := PackedFloat64Array()
## The course's packed tiles and owned flags as HeightField reads them (_sync), as of
## CourseData.revision `_rev`: checked every tick, so the builder's writes are seen at once.
var _rev: int = -1
var _tiles := PackedByteArray()
var _owned := PackedByteArray()
var _w: int = 0
var _h: int = 0
var _pw: int = 0
var _ypt: float = 5.0
var _yps: float = 2.0
## gradient_at's scaling, steps per tile to yards per yard.
var _slope_k: float = 0.4
## The highest any ground can stand, yards (CourseData.MAX_HEIGHT steps): a bilinear blend of
## heights never passes the highest of them.
var _top: float = 14.0


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


## Puts the cup on `tile` (at its centre), or takes it away with NO_CUP.
func set_cup(tile: Vector2i) -> void:
	cup_tile = tile


func has_cup() -> bool:
	return cup_tile != NO_CUP


## Centre of the cup, yards.
func cup_center() -> Vector2:
	if cup_tile != _cup_centre_tile:
		_cup_centre = field.tile_center(cup_tile)
		_cup_centre_tile = cup_tile
	return _cup_centre


## True when a ball at ground point `at` moving at `ground_speed` yd/s is captured: within
## cup_radius of the cup's centre and no faster than cup_capture_speed, both included (D15).
func captures(at: Vector2, ground_speed: float) -> bool:
	return has_cup() and at.distance_to(cup_center()) <= params.cup_radius \
			and ground_speed <= params.cup_capture_speed


## One 1/60 s tick. Does nothing before launch or at rest.
func step() -> void:
	run(1)


## Steps until the ball is at rest. Returns the number of ticks this call took.
func run_to_rest() -> int:
	return run(-1)


## E7-S4: steps the ball by up to `max_ticks` ticks (below 0: no limit), stopping at rest;
## returns the ticks stepped. The same ticks as calling `step` that many times, in one call:
## the course is checked for writes once (nothing writes it during a call; GuestBrain's threads
## run while the builder's thread waits) and the cup's centre is read once.
##
## The tick is spelled out here, flight and roll, with HeightField's reads and the static
## helpers (felt_gradient, crease_slope, meet_ground, downhill_share, captures) written into it
## on the tick's copies (_take_params, _take_terrain): a GDScript call costs as much as dozens
## of sums, and calls from several threads at once queue on each other in the engine (about
## four times slower than one thread making them all), so a tick that makes none is what lets
## GuestBrain.serve_second spread guests over threads. Only what is rare calls out: a flight's
## touchdown (_flight_contact), trees, a ball at rest or nearly so, a tile centre line or the
## map's edge (_terrain_edge, _ground, _slope), a crease felt as a low point (_felt). The same
## sums in the same order as before, so the same ball bit for bit (tests/test_ball_kernel.gd).
@warning_ignore("integer_division")
func run(max_ticks: int = -1) -> int:
	if state != State.FLYING and state != State.ROLLING:
		return 0
	if field.course.revision != _rev:
		_take_terrain()
	var cup_set := cup_tile != NO_CUP
	var cup := cup_center() if cup_set else Vector2.ZERO
	var tiles := _tiles
	var owned := _owned
	var w := _w
	var hgt := _h
	var wl := _w - 1
	var hl := _h - 1
	var pw := _pw
	var ypt := _ypt
	var yps := _yps
	var slope_k := _slope_k
	var gravity := _gravity
	var top := _top
	var pt := CourseData.PARCEL_TILES
	var n := 0
	while (state == State.FLYING or state == State.ROLLING) and (max_ticks < 0 or n < max_ticks):
		var rolling := state == State.ROLLING
		if rolling:
			# One pass: a break ends the roll's tick early (the ball came to rest).
			while true:
				# The surface under the ball (HeightField.surface_at).
				var here := Surface.Type.OOB as int
				var tx := floori(position.x / ypt)
				var ty := floori(position.y / ypt)
				if tx >= 0 and ty >= 0 and tx < w and ty < hgt and owned[(ty / pt) * pw + tx / pt] != 0:
					here = tiles[ty * w + tx] & 0x0F
				var roll := _row_roll[here]
				if roll <= 0.0:
					_rest()
					break
				var slope_scale := _row_slope[here]
				# The slope under the ball (HeightField.gradient_at; _terrain's common case).
				var gux := position.x / ypt - 0.5
				var guy := position.y / ypt - 0.5
				var gdx := 0.0
				var gdy := 0.0
				var g_fast := false
				if gux > 0.0 and guy > 0.0 and gux < wl and guy < hl:
					var gx0 := floori(gux)
					var gy0 := floori(guy)
					if gux != gx0 and guy != gy0:
						var gb := Vector2(gux - gx0, guy - gy0)
						var gi := gy0 * w + gx0
						var g00 := tiles[gi] >> 4
						var g10 := tiles[gi + 1] >> 4
						var g01 := tiles[gi + w] >> 4
						var g11 := tiles[gi + w + 1] >> 4
						gdx = lerpf(g10 - g00, g11 - g01, gb.y)
						gdy = lerpf(g01 - g00, g11 - g10, gb.x)
						g_fast = true
				var grad := Vector2(gdx, gdy) * slope_k
				if not g_fast:
					grad = _slope(position.x, position.y)
				# Gravity along the slope the surface lets the ball feel (felt_gradient),
				# projected onto the ground plane. Peaks at gravity / 2.
				var feel := grad * slope_scale
				var steep_scale := _row_steep_scale[here]
				if steep_scale > 0.0:
					var steep_from := _row_steep_from[here]
					var sx := absf(grad.x)
					var fx := sx * slope_scale
					if sx > steep_from:
						fx = minf(fx + (sx - steep_from) * steep_scale, sx)
					var sy := absf(grad.y)
					var fy := sy * slope_scale
					if sy > steep_from:
						fy = minf(fy + (sy - steep_from) * steep_scale, sy)
					feel = Vector2(signf(grad.x) * fx, signf(grad.y) * fy)
				var pull := -feel * gravity / (1.0 + feel.length_squared())
				var v := Vector2(velocity.x, velocity.y)
				var full := _roll_decel / roll
				var hold := full * _row_rest_decel[here]
				# Axes stopped at a low point this tick (0), and the move that would have crossed it.
				# A low point on an axis: this tick's move `v` would carry the ball from ground
				# falling along `v` on that axis onto ground rising against it, the bottom of that
				# axis, where the bilinear gradient jumps at a tile centre. Friction only trims the
				# pull, so without stopping there nothing damps a slow ball swinging across it.
				var stop := Vector2.ONE
				var crossing := Vector2.ZERO
				# The gradient read ahead of the ball (at its position plus this tick's move),
				# where, and the ground's height there (NAN: not read).
				var ahead := Vector2.ZERO
				var ahead_x := NAN
				var ahead_y := NAN
				var ahead_z := NAN
				var speed_now := v.length()
				if speed_now < _rest_speed:
					# Static: stays put unless the slope pulls harder than the constant friction.
					if pull.length() <= hold:
						_rest()
						break
					var still := v
					v += pull.normalized() * (pull.length() - hold) * DT
					# At a low point (E1-S13), per axis (`stop` above). With both axes
					# stopped (a pit) it rests. With one stopped (a gully that slopes along its
					# length) it goes on down the other, pulled by that axis's slope alone, as on
					# the gully's floor line, and rests only if that pull is no more than the hold.
					ahead_x = position.x + v.x * DT
					ahead_y = position.y + v.y * DT
					ahead = _slope(ahead_x, ahead_y)
					var lows := Vector2(
							0.0 if grad.x * v.x < 0.0 and ahead.x * v.x > 0.0 else 1.0,
							0.0 if grad.y * v.y < 0.0 and ahead.y * v.y > 0.0 else 1.0)
					if lows != Vector2.ONE:
						stop = lows
						crossing = v
						var floor_feel := feel * lows
						var floor_pull := -floor_feel * gravity / (1.0 + floor_feel.length_squared())
						if floor_pull.length() <= hold:
							_rest()
							break
						v = still * lows + floor_pull.normalized() * (floor_pull.length() - hold) * DT
						# If that pull would carry it across the other axis's low point too, it is
						# at the bottom of both (E2-S4 review: it stepped to and fro over a steep
						# pit's centre).
						ahead_x = position.x + v.x * DT
						ahead_y = position.y + v.y * DT
						ahead = _slope(ahead_x, ahead_y)
						var again := Vector2(
								0.0 if grad.x * v.x < 0.0 and ahead.x * v.x > 0.0 else 1.0,
								0.0 if grad.y * v.y < 0.0 and ahead.y * v.y > 0.0 else 1.0)
						if again * lows != lows:
							_rest()
							break
				else:
					# Friction = constant part + grass drag that grows with speed. Where the
					# surface holds a still ball more lightly, the constant part rises back to full
					# by decel_ramp_speed. Where drag_full_speed is set (E2-S4), the drag fades
					# below it in proportion to speed.
					var constant := full
					var ramp := _row_ramp[here]
					if _row_rest_decel[here] != 1.0 and speed_now < ramp:
						constant = lerpf(hold, full, speed_now / ramp)
					var drag := _roll_drag * _row_drag[here] * speed_now / roll
					var drag_full := _row_drag_full[here]
					if drag_full > 0.0 and speed_now < drag_full:
						drag *= speed_now / drag_full
					# Downhill (E6-S10, downhill_share): where the slope pulls the ball on along
					# its line, the friction falls toward downhill_friction_scale of itself, so a
					# long slope off the green is run at pace, not at the crawl where a one-step
					# pull meets the drag.
					var downhill := 0.0
					if speed_now > 0.0 and full > 0.0:
						downhill = clampf(pull.dot(v / speed_now) / full, 0.0, 1.0)
					if downhill > 0.0:
						var eased := lerpf(1.0, _row_downhill[here], downhill)
						constant *= eased
						drag *= eased
					var friction := constant + drag
					v += pull * DT
					var speed := v.length() - friction * DT
					v = v.normalized() * speed if speed > 0.0 else Vector2.ZERO
					# A ball also stops along an axis where it is about to cross a low point
					# slowly on that axis (E1-S13; per axis since E2-S4), so it does not swing to
					# and fro across a pit's centre or a gully's floor while it runs on along the
					# other axis. The slope and height ahead (_terrain's common case).
					ahead_x = position.x + v.x * DT
					ahead_y = position.y + v.y * DT
					var aux := ahead_x / ypt - 0.5
					var auy := ahead_y / ypt - 0.5
					var a_fast := false
					if aux > 0.0 and auy > 0.0 and aux < wl and auy < hl:
						var ax0 := floori(aux)
						var ay0 := floori(auy)
						if aux != ax0 and auy != ay0:
							var ab := Vector2(aux - ax0, auy - ay0)
							var ai := ay0 * w + ax0
							var a00 := tiles[ai] >> 4
							var a10 := tiles[ai + 1] >> 4
							var a01 := tiles[ai + w] >> 4
							var a11 := tiles[ai + w + 1] >> 4
							var at := Vector3(lerpf(a10 - a00, a11 - a01, ab.y),
									lerpf(a01 - a00, a11 - a10, ab.x),
									lerpf(lerpf(a00, a10, ab.x), lerpf(a01, a11, ab.x), ab.y) * yps)
							ahead = Vector2(at.x, at.y) * slope_k
							ahead_z = at.z
							a_fast = true
					if not a_fast:
						var at_edge := _terrain_edge(ahead_x, ahead_y)
						ahead = Vector2(at_edge.x, at_edge.y) * slope_k
						ahead_z = at_edge.z
					var keep := Vector2(
							0.0 if grad.x * v.x < 0.0 and ahead.x * v.x > 0.0 else 1.0,
							0.0 if grad.y * v.y < 0.0 and ahead.y * v.y > 0.0 else 1.0)
					if absf(v.x) >= _low_point_speed:
						keep.x = 1.0
					if absf(v.y) >= _low_point_speed:
						keep.y = 1.0
					if keep != Vector2.ONE:
						stop = keep
						crossing = v
						v *= keep
				var x := position.x + v.x * DT
				var y := position.y + v.y * DT
				# A rolling ball stops where it is at the edge of trees, as if against the trunks
				# (D15).
				if here != Surface.Type.TREES:
					var nx := floori(x / ypt)
					var ny := floori(y / ypt)
					# Still on the tile it started the tick on: that is `here`, not trees.
					if (nx != tx or ny != ty) and nx >= 0 and ny >= 0 and nx < w and ny < hgt \
							and owned[(ny / pt) * pw + nx / pt] != 0 \
							and (tiles[ny * w + nx] & 0x0F) == Surface.Type.TREES:
						_rest()
						break
				# A stopped axis sits exactly on the low point's line (a tile centre), where the
				# slope along it is the mean of both sides (E2-S4 review): so a ball running down
				# a gully's floor feels the floor's own pull, not one wall's trim of it.
				if stop.x == 0.0:
					x = _low_point_line(position.x, position.x + crossing.x * DT)
				if stop.y == 0.0:
					y = _low_point_line(position.y, position.y + crossing.y * DT)
				# The slope and height read ahead serve when the ball moved to that very point.
				var same := x == ahead_x and y == ahead_y
				position = Vector3(x, y, ahead_z if same and not is_nan(ahead_z) else _ground(x, y))
				# Where the ground under the ball turns up against it (a concave crease at a tile
				# centre: a valley floor, the foot of a bank), the ball keeps only its velocity
				# along the new ground (E2-S4).
				var next := ahead if same else _slope(x, y)
				# crease_slope(grad, next, v, row) and crease_slope(next, grad, v, row, true): both
				# take the felt slope on an axis exactly where grad falls and next rises along v,
				# else slope_scale's.
				var cross_x := grad.x * v.x < 0.0 and next.x * v.x > 0.0
				var cross_y := grad.y * v.y < 0.0 and next.y * v.y > 0.0
				var from := grad * slope_scale
				var to := next * slope_scale
				if cross_x or cross_y:
					var felt_next := _felt(next, here)
					if cross_x:
						from.x = feel.x
						to.x = felt_next.x
					if cross_y:
						from.y = feel.y
						to.y = felt_next.y
				# meet_ground: per axis, _meet_axis with floor_thud.
				var met := v
				if (to.x - from.x) * v.x > 0.0:
					var kx := clampf((1.0 + from.x * to.x) / (1.0 + to.x * to.x), 0.0, 1.0)
					if from.x * v.x < 0.0 and to.x * v.x > 0.0:
						var fks := _row_floor_keep_speed[here]
						if fks <= 0.0:
							kx *= _row_floor_keep[here]
						else:
							kx *= lerpf(_row_floor_keep[here], 1.0, clampf(absf(v.x) / fks, 0.0, 1.0))
					met.x = v.x * kx
				if (to.y - from.y) * v.y > 0.0:
					var ky := clampf((1.0 + from.y * to.y) / (1.0 + to.y * to.y), 0.0, 1.0)
					if from.y * v.y < 0.0 and to.y * v.y > 0.0:
						var fks_y := _row_floor_keep_speed[here]
						if fks_y <= 0.0:
							ky *= _row_floor_keep[here]
						else:
							ky *= lerpf(_row_floor_keep[here], 1.0, clampf(absf(v.y) / fks_y, 0.0, 1.0))
					met.y = v.y * ky
				velocity = Vector3(met.x, met.y, grad.dot(met))
				break
		else:
			# Flight. Check the middle of the tick too, so a sharp crest cannot be skipped; each
			# point (_flight_at(0.5), _flight_at(1.0)) is worked out once and reused by the tree
			# checks and the move. No ground stands higher than `top` (CourseData.MAX_HEIGHT
			# steps), so above it a point's ground is not read.
			var lo := -1.0
			var hi := -1.0
			var s := 0.5 * DT
			var half := position + velocity * s + Vector3(0.0, 0.0, -0.5 * gravity * s * s)
			var whole := Vector3.ZERO
			var below := false
			if half.z < top:
				var hux := half.x / ypt - 0.5
				var huy := half.y / ypt - 0.5
				var hz := 0.0
				if hux > 0.0 and huy > 0.0 and hux < wl and huy < hl:
					var hx0 := floori(hux)
					var hy0 := floori(huy)
					var hb := Vector2(hux - hx0, huy - hy0)
					var hi0 := hy0 * w + hx0
					hz = lerpf(lerpf(tiles[hi0] >> 4, tiles[hi0 + 1] >> 4, hb.x),
							lerpf(tiles[hi0 + w] >> 4, tiles[hi0 + w + 1] >> 4, hb.x), hb.y) * yps
				else:
					hz = _ground(half.x, half.y)
				below = half.z < hz
			if below:
				lo = 0.0
				hi = 0.5
			else:
				s = 1.0 * DT
				whole = position + velocity * s + Vector3(0.0, 0.0, -0.5 * gravity * s * s)
				if whole.z < top:
					var wux := whole.x / ypt - 0.5
					var wuy := whole.y / ypt - 0.5
					var wz := 0.0
					if wux > 0.0 and wuy > 0.0 and wux < wl and wuy < hl:
						var wx0 := floori(wux)
						var wy0 := floori(wuy)
						var wb := Vector2(wux - wx0, wuy - wy0)
						var wi := wy0 * w + wx0
						wz = lerpf(lerpf(tiles[wi] >> 4, tiles[wi + 1] >> 4, wb.x),
								lerpf(tiles[wi + w] >> 4, tiles[wi + w + 1] >> 4, wb.x), wb.y) * yps
					else:
						wz = _ground(whole.x, whole.y)
					if whole.z < wz:
						lo = 0.5
						hi = 1.0
			if hi >= 0.0:
				_flight_contact(lo, hi)
			else:
				# _blocked_in(1.0): its middle, then its end (_blocks only over painted trees).
				var scattered_now := false
				var bx := floori(half.x / ypt)
				var by := floori(half.y / ypt)
				if bx >= 0 and by >= 0 and bx < w and by < hgt \
						and (tiles[by * w + bx] & 0x0F) == Surface.Type.TREES and _blocks(half):
					_scatter(half, velocity + Vector3(0.0, 0.0, -gravity * 0.5 * DT))
					scattered_now = true
				if not scattered_now:
					bx = floori(whole.x / ypt)
					by = floori(whole.y / ypt)
					if bx >= 0 and by >= 0 and bx < w and by < hgt \
							and (tiles[by * w + bx] & 0x0F) == Surface.Type.TREES and _blocks(whole):
						_scatter(whole, velocity + Vector3(0.0, 0.0, -gravity * 1.0 * DT))
						scattered_now = true
				if not scattered_now:
					position = whole
					velocity.z -= gravity * DT
		steps += 1
		n += 1
		if state != State.AT_REST and steps >= _max_steps:
			_rest()
		# The cup checks at the end of every rolling tick, never at touchdown (D15). A drop never
		# captures (and never lands on the cup's tile, so the next stroke cannot be a free
		# tap-in). captures(), spelled out.
		if rolling and cup_set and penalty_strokes == 0 and not holed \
				and Vector2(position.x, position.y).distance_to(cup) <= _cup_radius \
				and Vector2(velocity.x, velocity.y).length() <= _cup_capture_speed:
			_hole()
		# The track and the path end where the ball stopped in a hazard, not at the drop.
		var shown := hazard_position if penalty_strokes > 0 else position
		if not _track_in_path:
			_track.append(Vector2(shown.x, shown.y))
		if record_path:
			path.append(shown)
	return n


# --- internals ---

## E7-S4: the tick's copies of `params` and the surface rows, taken at each launch.
func _take_params() -> void:
	_gravity = params.gravity
	_roll_decel = params.roll_decel
	_roll_drag = params.roll_drag
	_rest_speed = params.rest_speed
	_low_point_speed = params.low_point_speed
	_cup_radius = params.cup_radius
	_cup_capture_speed = params.cup_capture_speed
	_max_steps = params.max_steps
	var n := surfaces.rows.size()
	if _row_roll.size() != n:
		_row_roll.resize(n)
		_row_slope.resize(n)
		_row_steep_from.resize(n)
		_row_steep_scale.resize(n)
		_row_rest_decel.resize(n)
		_row_ramp.resize(n)
		_row_drag.resize(n)
		_row_drag_full.resize(n)
		_row_downhill.resize(n)
		_row_floor_keep.resize(n)
		_row_floor_keep_speed.resize(n)
	for i in n:
		var row := surfaces.row(i as Surface.Type)
		_row_roll[i] = row.roll
		_row_slope[i] = row.slope_scale
		_row_steep_from[i] = row.steep_from
		_row_steep_scale[i] = row.steep_scale
		_row_rest_decel[i] = row.rest_decel_scale
		_row_ramp[i] = row.decel_ramp_speed
		_row_drag[i] = row.drag_scale
		_row_drag_full[i] = row.drag_full_speed
		_row_downhill[i] = row.downhill_friction_scale
		_row_floor_keep[i] = row.floor_keep
		_row_floor_keep_speed[i] = row.floor_keep_speed


## E7-S4: the tick's copy of the course's packed tiles (HeightField._sync).
@warning_ignore("integer_division")
func _take_terrain() -> void:
	var course := field.course
	_rev = course.revision
	_tiles = course.packed_tiles()
	_owned = course.packed_owned()
	_w = course.width
	_h = course.height
	_pw = (_w + CourseData.PARCEL_TILES - 1) / CourseData.PARCEL_TILES
	_ypt = field.yards_per_tile
	_yps = field.yards_per_step
	_slope_k = _yps / _ypt
	_top = CourseData.MAX_HEIGHT * _yps


func _reset(start: Vector3) -> void:
	_take_params()
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
	_track_in_path = record_path
	path = PackedVector3Array()
	if record_path:
		path.append(position)


## Flight position `t` of the way through the current tick (0 to 1).
func _flight_at(t: float) -> Vector3:
	var s := t * DT
	return position + velocity * s + Vector3(0.0, 0.0, -0.5 * _gravity * s * s)


func _below(p: Vector3) -> bool:
	return p.z < _ground(p.x, p.y)


## A flight that meets the ground within this tick, between `lo` and `hi` of it (the
## middle or the end was below the ground): the touchdown point found by bisection, then
## trees, then the touchdown itself.
func _flight_contact(lo: float, hi: float) -> void:
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
	return _blocked_at(t * 0.5) or _blocked_at(t)


func _blocked_at(at: float) -> bool:
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


## E7-S4: felt_gradient for surface `s`, on the tick's copy of its row.
func _felt(grad: Vector2, s: int) -> Vector2:
	var slope_scale := _row_slope[s]
	var steep_scale := _row_steep_scale[s]
	if steep_scale <= 0.0:
		return grad * slope_scale
	var steep_from := _row_steep_from[s]
	var gx := grad.x
	var sx := absf(gx)
	var fx := sx * slope_scale
	if sx > steep_from:
		fx = minf(fx + (sx - steep_from) * steep_scale, sx)
	var gy := grad.y
	var sy := absf(gy)
	var fy := sy * slope_scale
	if sy > steep_from:
		fy = minf(fy + (sy - steep_from) * steep_scale, sy)
	return Vector2(signf(gx) * fx, signf(gy) * fy)



## E7-S4: HeightField.height_at on the tick's copy of the tiles (_take_terrain).
func _ground(x: float, y: float) -> float:
	var ux := x / _ypt - 0.5
	var uy := y / _ypt - 0.5
	if ux > 0.0 and uy > 0.0 and ux < _w - 1 and uy < _h - 1:
		# Inside the map's tile centres (most of the time): no clamp.
		var x0 := floori(ux)
		var y0 := floori(uy)
		var b := Vector2(ux - x0, uy - y0)
		var i := y0 * _w + x0
		return lerpf(lerpf(_tiles[i] >> 4, _tiles[i + 1] >> 4, b.x),
				lerpf(_tiles[i + _w] >> 4, _tiles[i + _w + 1] >> 4, b.x), b.y) * _yps
	if _w == 0 or _h == 0:
		return 0.0
	var x0 := 0
	var x1 := 0
	var bx := 0.0
	if ux <= 0.0 or _w < 2:
		pass
	elif ux >= _w - 1:
		x0 = _w - 1
		x1 = x0
	else:
		x0 = floori(ux)
		x1 = x0 + 1
		bx = Vector2(ux - x0, 0.0).x
	var r0 := 0
	var r1 := 0
	var by := 0.0
	if uy <= 0.0 or _h < 2:
		pass
	elif uy >= _h - 1:
		r0 = (_h - 1) * _w
		r1 = r0
	else:
		var y0 := floori(uy)
		r0 = y0 * _w
		r1 = r0 + _w
		by = Vector2(uy - y0, 0.0).x
	var top := lerpf(_tiles[r0 + x0] >> 4, _tiles[r0 + x1] >> 4, bx)
	var bottom := lerpf(_tiles[r1 + x0] >> 4, _tiles[r1 + x1] >> 4, bx)
	return lerpf(top, bottom, by) * _yps


## E7-S4: HeightField.gradient_at on the tick's copy of the tiles (_take_terrain).
func _slope(x: float, y: float) -> Vector2:
	var r := _terrain(x, y)
	return Vector2(r.x, r.y) * _slope_k


## E7-S4: HeightField.gradient_at and height_at at one point, reading its four tiles once:
## (dh/dx, dh/dy) in steps per tile, before gradient_at's scaling to yards per yard (Vector3
## rounds them to 32 bits as gradient_at's Vector2 does), and the height in yards (rounded as a
## ball's position rounds it). The same lerps in the same order as HeightField's.
func _terrain(x: float, y: float) -> Vector3:
	var ux := x / _ypt - 0.5
	var uy := y / _ypt - 0.5
	if ux > 0.0 and uy > 0.0 and ux < _w - 1 and uy < _h - 1:
		# Inside the map's tile centres and on no centre line (most of the time): no clamp,
		# each blend weight 1, and the four tiles are the slopes' too.
		var x0 := floori(ux)
		var y0 := floori(uy)
		if ux != x0 and uy != y0:
			var b := Vector2(ux - x0, uy - y0)
			var i := y0 * _w + x0
			var h00 := _tiles[i] >> 4
			var h10 := _tiles[i + 1] >> 4
			var h01 := _tiles[i + _w] >> 4
			var h11 := _tiles[i + _w + 1] >> 4
			return Vector3(lerpf(h10 - h00, h11 - h01, b.y), lerpf(h01 - h00, h11 - h10, b.x),
					lerpf(lerpf(h00, h10, b.x), lerpf(h01, h11, b.x), b.y) * _yps)
	return _terrain_edge(x, y)


## _terrain at the map's edge or on a tile centre line.
func _terrain_edge(x: float, y: float) -> Vector3:
	if _w == 0 or _h == 0:
		return Vector3.ZERO
	var ux := x / _ypt - 0.5
	var x0 := 0
	var x1 := 0
	var bx := 0.0
	var wx := 0.0
	if ux <= 0.0 or _w < 2:
		pass
	elif ux >= _w - 1:
		x0 = _w - 1
		x1 = x0
	else:
		x0 = floori(ux)
		x1 = x0 + 1
		bx = Vector2(ux - x0, 0.0).x
		wx = 1.0
	var uy := y / _ypt - 0.5
	var y0 := 0
	var y1 := 0
	var by := 0.0
	var wy := 0.0
	if uy <= 0.0 or _h < 2:
		pass
	elif uy >= _h - 1:
		y0 = _h - 1
		y1 = y0
	else:
		y0 = floori(uy)
		y1 = y0 + 1
		by = Vector2(uy - y0, 0.0).x
		wy = 1.0
	var t := _tiles
	var w := _w
	var r0 := y0 * w
	var r1 := y1 * w
	var h00 := t[r0 + x0] >> 4
	var h10 := t[r0 + x1] >> 4
	var h01 := t[r1 + x0] >> 4
	var h11 := t[r1 + x1] >> 4
	var dfx := 0.0
	if _w < 2 or ux < 0.0 or ux > _w - 1 or ux != floorf(ux):
		dfx = lerpf(h10 - h00, h11 - h01, by) * wx
	else:
		# On a tile centre line: the mean of the slopes either side (E2-S4).
		var i := int(ux)
		var left := lerpf((t[r0 + i] >> 4) - (t[r0 + i - 1] >> 4),
				(t[r1 + i] >> 4) - (t[r1 + i - 1] >> 4), by) if i > 0 else 0.0
		var right := lerpf((t[r0 + i + 1] >> 4) - (t[r0 + i] >> 4),
				(t[r1 + i + 1] >> 4) - (t[r1 + i] >> 4), by) if i < _w - 1 else 0.0
		dfx = 0.5 * (left + right)
	var dfy := 0.0
	if _h < 2 or uy < 0.0 or uy > _h - 1 or uy != floorf(uy):
		dfy = lerpf(h01 - h00, h11 - h10, bx) * wy
	else:
		var j := int(uy)
		var rj := j * w
		var up := lerpf((t[rj + x0] >> 4) - (t[rj - w + x0] >> 4),
				(t[rj + x1] >> 4) - (t[rj - w + x1] >> 4), bx) if j > 0 else 0.0
		var down := lerpf((t[rj + w + x0] >> 4) - (t[rj + x0] >> 4),
				(t[rj + w + x1] >> 4) - (t[rj + x1] >> 4), bx) if j < _h - 1 else 0.0
		dfy = 0.5 * (up + down)
	return Vector3(dfx, dfy, lerpf(lerpf(h00, h10, bx), lerpf(h01, h11, bx), by) * _yps)




## How much the slope pulls a ball moving at `v` on along its line, as a share of the
## constant friction `full` (E6-S10): 1 wherever that pull is at least the constant friction
## (every slope of a step per tile or more, off the green), less on a gentler downhill, and 0
## on flat ground, straight across a slope and uphill.
static func downhill_share(pull: Vector2, v: Vector2, full: float) -> float:
	var speed := v.length()
	if speed <= 0.0 or full <= 0.0:
		return 0.0
	return clampf(pull.dot(v / speed) / full, 0.0, 1.0)



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
	if _track_in_path:
		track.resize(path.size())
		for k in path.size():
			track[k] = Vector2(path[k].x, path[k].y)
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
