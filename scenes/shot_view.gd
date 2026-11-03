class_name ShotView
extends Node2D
## Shows one shot on the isometric map (E1-S7): the ball sprite at its projected 3D position,
## a ground shadow straight below it so its height reads, and a marker on the predicted
## landing point. A reader only: it never writes the course. On the ground the ball and its
## shadow are drawn on the top of the tile under them (D17, E2-S7); in flight the ball is at
## its true height and the shadow on that tile top.
##
## The live ball is a golf/ball.gd Ball stepped at a fixed 60 Hz from frame time (never per
## frame), so it follows the ShotPrediction made at fire time tick for tick.
##
## Water and OB (E2-S13): Ball moves a dropped ball to its drop point the tick it stops in
## the hazard. The view keeps drawing it where it went in (Ball.hazard_position) for
## ShotViewTuning.hazard_show_time, and only then draws it at the drop, ends the shot and
## emits came_to_rest with the drop point. For that hold the landing cross is hidden (a ball
## in water stops where it lands, so the cross would sit on it) and a hazard cue is drawn
## under the ball, its shape set by the hazard so it reads by shape, not only colour: a
## splash ring for water, a struck-through circle for OB.
##
## Place it as a child of CourseView: it is Y-sorted, and each piece sits at y = its
## Iso.object_sort_key and draws itself offset back to its screen point, so hills nearer the
## camera hide the ball and farther ones do not.

signal landed(at: Vector3)
signal came_to_rest(at: Vector3)

## Placeholder look, from art/palette.gpl (chalk, ink, flag_red) until E5-S3 brings a sprite.
@export var ball_color: Color = Color8(240, 236, 224)
@export var outline_color: Color = Color8(26, 28, 34)
@export var shadow_color: Color = Color8(26, 28, 34, 150)
@export var marker_color: Color = Color8(216, 58, 58)
## Ball radius in screen px at 1x.
@export var ball_radius: float = 4.0
## Shadow half-width in screen px at ground level; it shrinks to `shadow_min_scale` of that
## as the ball climbs to `shadow_fade_steps` height steps above the ground.
@export var shadow_radius: float = 6.0
@export var shadow_min_scale: float = 0.7
@export var shadow_fade_steps: float = 8.0
## Half-size of the landing marker cross, screen px.
@export var marker_radius: float = 5.0
## Hazard cue (E2-S13), from art/palette.gpl: chalk splash rings for water, flag_red for OB.
@export var splash_color: Color = Color8(240, 236, 224)
@export var ob_color: Color = Color8(216, 58, 58)
## Half-width of the cue's outer ring, screen px at 1x; drawn 2:1 like the tile footprint.
@export var hazard_cue_radius: float = 14.0

## scenes/shot_view_tuning.tres.
var tuning: ShotViewTuning
var ball: Ball
var prediction: ShotPrediction
## True from fire until the ball comes to rest.
var playing: bool = false
## The ball and its shadow.
var sprite: Node2D
## The predicted landing point.
var marker: Node2D
## The hazard cue, drawn only while showing_hazard().
var hazard_cue: Node2D

var _elapsed: float = 0.0
var _was_landed: bool = false
## Seconds of shot time (from the launch) at which a dropped ball's hazard show ends, or a
## negative number when none is running.
var _drop_at: float = -1.0
## Whether this shot shows its landing cross at all (a putt does not).
var _marker_wanted: bool = false


func _init() -> void:
	tuning = ShotViewTuning.load_default()
	y_sort_enabled = true
	visible = false
	# Before the ball: at the same sort key it draws under the ball, as rings round it.
	hazard_cue = _Piece.new(_draw_hazard_cue)
	hazard_cue.name = "HazardCue"
	hazard_cue.visible = false
	add_child(hazard_cue)
	sprite = _Piece.new(_draw_ball)
	sprite.name = "Ball"
	add_child(sprite)
	marker = _Piece.new(_draw_marker)
	marker.name = "LandingMarker"
	add_child(marker)


func _process(delta: float) -> void:
	if playing:
		advance(delta)


## Predicts the shot, then launches the live ball with the same course, seed and launch.
func fire(course: CourseData, start: Vector3, velocity: Vector3, rng_seed: int) -> void:
	prediction = ShotPrediction.run(course, rng_seed, start, velocity)
	ball = Ball.new(course, rng_seed)
	ball.launch(start, velocity)
	_start_live()


## Fires a stroke built by ShotModel (a flight or a putt, E2-S7), predicted the same way.
## `cup_tile` is the hole's cup (E2-S8), or Ball.NO_CUP.
func fire_launch(course: CourseData, shot: ShotLaunch, rng_seed: int,
		cup_tile: Vector2i = Ball.NO_CUP) -> void:
	prediction = ShotPrediction.run_launch(course, rng_seed, shot, null, null, cup_tile)
	ball = Ball.new(course, rng_seed)
	ball.set_cup(cup_tile)
	shot.apply(ball)
	_start_live()
	# A putt starts on the ground: its "landing" is where it was struck.
	_marker_wanted = not shot.is_putt()
	_refresh()


## Shows a ball resting at `at` (yards, on the ground) with nothing in play: the ball the
## next swing strikes. No landing marker.
func show_at_rest(course: CourseData, at: Vector2) -> void:
	ball = Ball.new(course, 1)
	ball.position = Vector3(at.x, at.y, ball.field.height_at(at.x, at.y))
	ball.state = Ball.State.AT_REST
	prediction = null
	playing = false
	visible = true
	_marker_wanted = false
	_refresh()


func _start_live() -> void:
	_elapsed = 0.0
	_drop_at = -1.0
	_was_landed = false
	playing = true
	visible = true
	_marker_wanted = true
	_place_marker()
	_refresh()


## Clears the shot from view.
func clear() -> void:
	playing = false
	visible = false
	ball = null
	prediction = null


## Runs the live ball forward by `delta` seconds of frame time, in whole 1/60 s ticks.
func advance(delta: float) -> void:
	if not playing:
		return
	_elapsed += delta
	var target: int = floori(_elapsed * Ball.TICK_HZ + 1e-6)
	while ball.steps < target and not ball.is_at_rest():
		ball.step()
		if ball.has_landed and not _was_landed:
			_was_landed = true
			landed.emit(ball.landing_position)
		if ball.is_at_rest() and ball.penalty_strokes > 0:
			_drop_at = float(ball.steps) / Ball.TICK_HZ + tuning.hazard_show_time
	if ball.is_at_rest() and not showing_hazard():
		playing = false
		_drop_at = -1.0
		came_to_rest.emit(ball.position)
	_refresh()


## True while a dropped ball is still drawn where it went in (E2-S13).
func showing_hazard() -> bool:
	return playing and _drop_at >= 0.0 and _elapsed + 1e-6 < _drop_at


## Where the ball is drawn, yards: where it went in while showing_hazard, else its position.
func drawn_position() -> Vector3:
	return ball.hazard_position if showing_hazard() else ball.position


## Screen point (in this node's parent space) of the ball. In flight it is the projected 3D
## point. On the ground (rolling or at rest) it is the top of the tile under the ball (D17):
## the physics height between tile centres would draw it off the flat top, or on a riser.
func ball_screen() -> Vector2:
	if on_ground():
		return shadow_screen()
	return Iso.point_to_screen(ball.field.iso_point(drawn_position()))


## Screen point of the shadow: straight below the ball, on the top of the tile under it
## (D17), in flight too.
func shadow_screen() -> Vector2:
	return ball.field.tile_top_screen(drawn_position())


## True while the ball is on the ground: rolling, at rest, or not yet struck.
func on_ground() -> bool:
	return ball.state != Ball.State.FLYING


## Drawn height, in steps, of the top of the tile under the ground point `p` (yards). Past
## the map edge the edge tile's height holds, as it does for the ball (HeightField).
func tile_top_steps(p: Vector3) -> float:
	return float(ball.field.tile_top_steps(p.x, p.y))


func _ground_below(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y, ball.field.height_at(p.x, p.y))


## Moves `piece` to the sort key of the ground point `ground` (yards).
func _sort_at(piece: Node2D, ground: Vector3) -> void:
	var iso := ball.field.iso_point(ground)
	var tile := Vector2(iso.x, iso.y)
	piece.position = Vector2(Iso.point_to_screen(iso).x, Iso.object_sort_key(tile, sort_ground(tile, iso.z)))
	piece.queue_redraw()


## Ground height (steps) a piece at `tile` sorts on: the bilinear ground, but never below the
## drawn top of the cell it stands in. Bilinear ground dips under that top wherever the cell
## has a lower neighbour, and sorting on it would paint the cell's own top over the ball.
func sort_ground(tile: Vector2, ground_steps: float) -> float:
	var cell := Vector2i(floori(tile.x + 0.5), floori(tile.y + 0.5))
	return maxf(ground_steps, float(ball.field.course.get_height(cell.x, cell.y)))


func _refresh() -> void:
	if ball == null:
		return
	var hold := showing_hazard()
	marker.visible = _marker_wanted and not hold
	hazard_cue.visible = hold
	_sort_at(sprite, _ground_below(drawn_position()))
	if hold:
		_sort_at(hazard_cue, _ground_below(drawn_position()))


## The landing cross stands on the tile top under the landing point (D17's rule), like the
## aim ring, so a perfect swing's cross sits exactly on the ring the player aimed with.
func _place_marker() -> void:
	var p := prediction.landing
	_sort_at(marker, Vector3(p.x, p.y, tile_top_steps(p) * ball.field.yards_per_step))


## Screen point of the landing cross, on the tile top under the predicted landing.
func marker_screen() -> Vector2:
	return ball.field.tile_top_screen(prediction.landing)


func _draw_ball(piece: Node2D) -> void:
	if ball == null:
		return
	var shadow := shadow_screen() - piece.position
	var at := ball_screen() - piece.position
	var lift := (shadow.y - at.y) / Iso.STEP_PX
	var s := lerpf(1.0, shadow_min_scale, clampf(lift / shadow_fade_steps, 0.0, 1.0))
	# An ellipse 2:1 like the tile footprint.
	piece.draw_set_transform(shadow, 0.0, Vector2(1.0, 0.5))
	piece.draw_circle(Vector2.ZERO, shadow_radius * s, shadow_color)
	piece.draw_set_transform(Vector2.ZERO)
	piece.draw_circle(at, ball_radius + 1.0, outline_color)
	piece.draw_circle(at, ball_radius, ball_color)


func _draw_marker(piece: Node2D) -> void:
	if prediction == null:
		return
	var at := marker_screen() - piece.position
	var r := marker_radius
	piece.draw_line(at + Vector2(-r, -r * 0.5), at + Vector2(r, r * 0.5), marker_color, 2.0)
	piece.draw_line(at + Vector2(-r, r * 0.5), at + Vector2(r, -r * 0.5), marker_color, 2.0)


## Water: two splash rings round where the ball went in. OB: a circle struck through.
func _draw_hazard_cue(piece: Node2D) -> void:
	if ball == null or not showing_hazard():
		return
	var at := shadow_screen() - piece.position
	var r := hazard_cue_radius
	piece.draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
	if ball.hazard == Ball.Hazard.OB:
		piece.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, ob_color, 2.0)
		piece.draw_line(Vector2(-r, r) * 0.7071, Vector2(r, -r) * 0.7071, ob_color, 2.0)
	else:
		piece.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, splash_color, 2.0)
		piece.draw_arc(Vector2.ZERO, r * 0.6, 0.0, TAU, 24, splash_color, 1.5)
	piece.draw_set_transform(Vector2.ZERO)


## One Y-sorted piece of the shot, drawn by a callback on the view.
class _Piece extends Node2D:
	var _draw_fn: Callable

	func _init(draw_fn: Callable) -> void:
		_draw_fn = draw_fn

	func _draw() -> void:
		_draw_fn.call(self)
