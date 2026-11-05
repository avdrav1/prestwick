class_name GuestView
extends Node2D
## Draws the guests' day on the course (E3-S5): every guest on the course as a golfer sprite
## (art/specs/golfer.md: 8 directions, idle, walk, swing) and its ball. A reader only: it
## never changes a guest, a ball or the course, so what the camera looks at never changes the
## day (the same seed gives the same day).
##
## Y-sort: a child of CourseView, Y-sorted like ShotView. Each figure and ball is a node at
## y = Iso.object_sort_key on the top of the tile under it, drawn offset back to its screen
## point, so the terrain sorts it: a hill or a raised tile in front hides it, the tiles behind
## do not, and it sorts with the ball and the hole markers by the same rule.
##
## Walks: the brain moves a guest once per simulated second (up to `walk_yd_per_s` 40 yd), so
## the view slides each figure from where it stood at the last step to where it stands now,
## by the share of the second gone by (GuestBrain.step_fraction): it moves at the sim's speed
## and stops when paused. A figure faces the way it walks, else its hole's cup.
##
## Swing: a stroke is PLAYING for one simulated second (`stroke_s`); the 6 swing frames run
## over it by the same share. The swinging figure stands on its stroke's start, over its own
## ball: no slide (the brain can end a walk and strike in one step) and no group spread, which
## eases back in over `spread_ease_s` once the stroke is done.
##
## Size: the figure is never drawn under `figure_min_screen_scale` times its native 24 px on
## screen (at 0.5x it is drawn at twice its size, one texel a screen pixel), so it reads as a
## person at every zoom (art/specs/golfer.md).
##
## Shirts (E3-S28): a figure wears its group's shirt (GolferArt.shirt_of_group: the day's
## groups take the art spec's shirts in turn), drawn by swapping the sheet's chalk in a shader
## material shared by everyone in that shirt, so a group reads as one and its neighbours differ.
##
## D45 (E3-S9 review): below BuilderTuning marker_min_screen_scale (0.5x) the whole view draws
## at z 1 (CourseView.lifted_z), as the grown tee markers and pins do, so figures and balls
## still Y-sort with them.
##
## Ball flights: the sim runs every guest's ball the same way, watched or not (GuestHole's
## off-screen shortcut: it rests within a simulated second or so). When a guest strikes and
## its ball's start is on screen (within GuestViewTuning.on_screen_margin_px of the view), the
## view replays the stroke's recorded path (GuestHole.stroke_path), `flight_draw_speed` (D38)
## times faster than real, times the sim's speed: the ball at its height with a shadow under
## it in flight, on the tile top (D17) on the ground. Off screen there is no replay: the ball
## shows again where it rests. A ball at rest shows where it lies until the hole is finished.

## Ball look: ShotView's placeholder (art/palette.gpl chalk, ink), until E5-S3's sprite, drawn
## at GuestViewTuning.ball_scale of the player's ball so a guest's ball is never mistaken for it.
@export var ball_color: Color = Color8(240, 236, 224)
@export var outline_color: Color = Color8(26, 28, 34)
@export var shadow_color: Color = Color8(26, 28, 34, 150)
## Ball radius at 1x, canvas units (ShotView.ball_radius), never under
## ShotViewTuning.ball_min_screen_radius on screen.
@export var ball_radius: float = 4.0
## The figure's ground shadow, a 2:1 ellipse under the feet: half-width, canvas units.
@export var figure_shadow_radius: float = 7.0

var sim: GuestSim
var art: GolferArt
var tuning: GuestViewTuning
var guest_tuning: GuestTuning
var shot_tuning: ShotViewTuning
## Tests: the screen rect on-screen checks use (empty: the viewport's).
var screen_rect_override: Rect2 = Rect2()

## {guest id: Figure} for every guest on the course.
var _figures: Dictionary = {}
var _brain: GuestBrain
var _field: HeightField
var _second: int = 0
## Real seconds since the view started drawing (idle frames).
var _time: float = 0.0
## The zoom under which the view draws at z 1 (BuilderTuning marker_min_screen_scale, D45).
var _lift_below: float = 0.5


## What the view keeps for one guest.
class Figure:
	var guest: Guest
	var sprite: Node2D
	var ball: Node2D
	## Where it stood at the last step and stands now, yards.
	var from: Vector2
	var to: Vector2
	var dir: int = 0
	var anim: GolferArt.Anim = GolferArt.Anim.IDLE
	var frame: int = 0
	var walk_phase: float = 0.0
	## How much of the group spread is drawn: 0 while it swings, easing back to 1.
	var spread: float = 1.0
	## Where the figure is drawn now, yards (place offset included).
	var at: Vector2
	## The hole and stroke count last seen, to spot a new stroke.
	var hole: GuestHole
	var strokes_seen: int = 0
	## The replay under way (replay_hole null: none): that hole's stroke `replay_stroke`
	## (its count of strokes when struck) and how many ticks of its path are drawn.
	var replay_hole: GuestHole
	var replay_stroke: int = 0
	var replay_head: float = 0.0
	## The ball as drawn: shown, where (yards, 3D) and whether in the air.
	var ball_shown: bool = false
	var ball_at: Vector3
	var ball_flying: bool = false


func _init() -> void:
	y_sort_enabled = true
	art = GolferArt.load_default()
	tuning = GuestViewTuning.load_default()
	guest_tuning = GuestTuning.load_default()
	shot_tuning = ShotViewTuning.load_default()
	_lift_below = BuilderTuning.load_default().marker_min_screen_scale


func bind(p_sim: GuestSim) -> void:
	sim = p_sim


func _process(delta: float) -> void:
	update_lift()
	if sim != null and visible:
		update_view(delta, sim.effective_speed())


## Puts the view at z 1 below marker_min_screen_scale, else 0 (CourseView.lifted_z, D45).
func update_lift() -> void:
	if is_inside_tree():
		z_index = CourseView.lifted_z(get_viewport().get_canvas_transform().get_scale().x, _lift_below)


## Every figure drawn, by guest id (tests).
func figures() -> Dictionary:
	return _figures


func figure(guest: Guest) -> Figure:
	return _figures.get(guest.id)


## Brings the drawing up to the sim after `delta` real seconds at `speed` (0 paused).
func update_view(delta: float, speed: float) -> void:
	var brain: GuestBrain = sim.brain if sim != null else null
	if brain != _brain:
		clear()
		_brain = brain
		_field = HeightField.new(brain.course, BallParams.load_default()) if brain != null else null
		_second = brain.second if brain != null else 0
	if brain == null:
		return
	_time += delta
	var stepped := brain.second != _second
	_second = brain.second
	var frac := brain.step_fraction()
	for guest: Guest in brain.guests:
		if guest.is_done():
			_drop(guest.id)
			continue
		var f: Figure = _figures.get(guest.id)
		if f == null:
			f = _add(guest)
		elif stepped:
			f.from = f.to
			f.to = guest.position
		_update_figure(f, delta, speed, frac)


## Removes every figure.
func clear() -> void:
	for id: int in _figures.keys():
		_drop(id)
	_brain = null


func _add(guest: Guest) -> Figure:
	var f := Figure.new()
	f.guest = guest
	f.from = guest.position
	f.to = guest.position
	f.hole = guest.hole
	f.strokes_seen = guest.hole.strokes.size() if guest.hole != null else 0
	f.sprite = _Piece.new(_draw_figure.bind(f))
	f.sprite.name = "Guest%d" % guest.id
	f.sprite.material = art.shirt_material(shirt_of(f))
	add_child(f.sprite)
	f.ball = _Piece.new(_draw_ball.bind(f))
	f.ball.name = "Ball%d" % guest.id
	add_child(f.ball)
	_figures[guest.id] = f
	return f


func _drop(id: int) -> void:
	var f: Figure = _figures.get(id)
	if f == null:
		return
	# Freed now, not queued: the view runs in its own _process, never inside a piece's draw.
	f.sprite.free()
	f.ball.free()
	_figures.erase(id)


## The shirt figure `f` wears (E3-S28): its group's, so a group reads as one and the groups
## on a hole and the next differ (GolferArt.shirt_of_group).
func shirt_of(f: Figure) -> int:
	return art.shirt_of_group(f.guest.group_id)


## A guest's place in its group as a small sideways step on screen, yards: place 0 on the
## spot, then right, left, two right (screen x is along +x and -y of the grid).
func place_offset(place: int) -> Vector2:
	var m: float = [0.0, 1.0, -1.0, 2.0][place % 4]
	return Vector2(1.0, -1.0) * tuning.group_spread_yd * m


## Screen vector (CourseView space, x right, y down) of a step `d` in yards.
func screen_vector(d: Vector2) -> Vector2:
	var t := d / _field.yards_per_tile
	return Vector2((t.x - t.y) * Iso.HALF_W, (t.x + t.y) * Iso.HALF_H)


func _update_figure(f: Figure, delta: float, speed: float, frac: float) -> void:
	var g := f.guest
	if g.state == Guest.State.PLAYING:
		# Over its own ball for the whole swing, not still sliding along its last walk leg.
		var stand := g.position
		if g.hole != null and not g.hole.strokes.is_empty():
			var start: Vector3 = g.hole.strokes[-1].start
			stand = Vector2(start.x, start.y)
		f.from = stand
		f.to = stand
		f.spread = 0.0
	else:
		f.spread = minf(1.0, f.spread + delta * speed / maxf(tuning.spread_ease_s, 0.001))
	f.at = f.from.lerp(f.to, frac) + place_offset(g.place) * f.spread
	var moving := f.from.distance_squared_to(f.to) > 1e-6
	var d := -1
	if moving:
		d = GolferArt.direction_of(screen_vector(f.to - f.from))
	elif g.hole != null:
		d = GolferArt.direction_of(screen_vector(_field.tile_center(g.hole.hole.cup) - f.at))
	if d >= 0:
		f.dir = d
	if g.state == Guest.State.PLAYING:
		f.anim = GolferArt.Anim.SWING
		f.frame = mini(floori(frac * art.frames_per_dir(f.anim)), art.frames_per_dir(f.anim) - 1)
	elif moving:
		f.anim = GolferArt.Anim.WALK
		f.walk_phase += delta * tuning.walk_fps * speed
		f.frame = floori(f.walk_phase)
	else:
		f.anim = GolferArt.Anim.IDLE
		f.frame = floori(_time * tuning.idle_fps) + g.id
	_place(f.sprite, Vector3(f.at.x, f.at.y, 0.0))
	_update_ball(f, delta, speed)


func _update_ball(f: Figure, delta: float, speed: float) -> void:
	var h := f.guest.hole
	if h != f.hole:
		f.hole = h
		f.strokes_seen = 0
	if h != null and h.strokes.size() > f.strokes_seen:
		f.strokes_seen = h.strokes.size()
		f.replay_hole = null
		var start: Vector3 = h.strokes[-1].start
		if on_screen(_field.tile_top_screen(start)):
			f.replay_hole = h
			f.replay_stroke = h.strokes.size()
			f.replay_head = 0.0
	if f.replay_hole != null:
		var rh := f.replay_hole
		var path := rh.stroke_path()
		if rh.strokes.size() != f.replay_stroke or path.is_empty():
			f.replay_hole = null
		else:
			f.replay_head += delta * speed * Ball.TICK_HZ * guest_tuning.flight_draw_speed
			var last := path.size() - 1
			var i := mini(floori(f.replay_head), last)
			f.ball_shown = true
			f.ball_at = path[i]
			f.ball_flying = f.ball_at.z > _field.height_at(f.ball_at.x, f.ball_at.y) + 0.05
			if i >= last and rh.ball == null:
				f.replay_hole = null  # drawn to where it rested
			_place(f.ball, f.ball_at)
			return
	f.ball_flying = false
	f.ball_shown = h != null and not h.is_finished() and h.state != GuestHole.State.FLYING
	if f.ball_shown:
		f.ball_at = h.ball_at
		_place(f.ball, f.ball_at)
	f.ball.visible = f.ball_shown


## True while a replay is drawing this guest's stroke.
func is_replaying(f: Figure) -> bool:
	return f.replay_hole != null


## True when screen point `p` (CourseView space) is within the view, give or take
## on_screen_margin_px.
func on_screen(p: Vector2) -> bool:
	var rect := screen_rect_override
	if not rect.has_area():
		if not is_inside_tree():
			return false
		rect = get_viewport_rect()
	var s: Vector2 = get_global_transform_with_canvas() * p
	return rect.grow(tuning.on_screen_margin_px).has_point(s)


## Puts `piece` at the sort key of the ground under `p` (yards): the tile top under it.
func _place(piece: Node2D, p: Vector3) -> void:
	piece.visible = true
	var iso := _field.iso_point(p)
	var top := float(_field.tile_top_steps(p.x, p.y))
	var screen := _field.tile_top_screen(p)
	piece.position = Vector2(screen.x, Iso.object_sort_key(Vector2(iso.x, iso.y), top))
	piece.queue_redraw()


## Where figure `f`'s feet are drawn, CourseView space.
func figure_screen(f: Figure) -> Vector2:
	return _field.tile_top_screen(Vector3(f.at.x, f.at.y, 0.0))


## Where `f`'s ball is drawn, CourseView space: at its height in the air, on the tile top on
## the ground (D17).
func ball_screen(f: Figure) -> Vector2:
	if f.ball_flying:
		return Iso.point_to_screen(_field.iso_point(f.ball_at))
	return _field.tile_top_screen(f.ball_at)


func _draw_figure(piece: Node2D, f: Figure) -> void:
	var feet := figure_screen(f) - piece.position
	var s := figure_scale()
	piece.draw_set_transform(feet, 0.0, Vector2(1.0, 0.5))
	piece.draw_circle(Vector2.ZERO, figure_shadow_radius * s, shadow_color)
	var tex := art.frame(f.anim, f.dir, f.frame)
	piece.draw_set_transform(feet, 0.0, Vector2(s, s))
	piece.draw_texture(tex, -Vector2(art.anchor()))
	piece.draw_set_transform(Vector2.ZERO)


## The figure's scale at the current zoom: 1 at 1x and closer, more below it so the figure is
## never under `figure_min_screen_scale` of its native size on screen.
func figure_scale() -> float:
	return maxf(1.0, tuning.figure_min_screen_scale * _cue_k())


## A guest's ball radius, canvas units: the player's ball (ShotView's rule, never under
## ball_min_screen_radius on screen) times `ball_scale`.
func guest_ball_radius() -> float:
	return maxf(ball_radius, shot_tuning.ball_min_screen_radius * _cue_k()) * tuning.ball_scale


func _draw_ball(piece: Node2D, f: Figure) -> void:
	if not f.ball_shown:
		return
	var k := _cue_k()
	if f.ball_flying:
		var shadow := _field.tile_top_screen(f.ball_at) - piece.position
		piece.draw_set_transform(shadow, 0.0, Vector2(1.0, 0.5))
		piece.draw_circle(Vector2.ZERO, ball_radius * tuning.ball_scale * 1.4, shadow_color)
		piece.draw_set_transform(Vector2.ZERO)
	var at := ball_screen(f) - piece.position
	var r := guest_ball_radius()
	piece.draw_circle(at, r + maxf(1.0, k), outline_color)
	piece.draw_circle(at, r, ball_color)


func _cue_k() -> float:
	if not is_inside_tree():
		return 1.0
	return HazardCue.screen_k(get_viewport().get_canvas_transform().get_scale().x)


## One Y-sorted piece drawn by a callback on the view.
class _Piece extends Node2D:
	var _draw_fn: Callable

	func _init(draw_fn: Callable) -> void:
		_draw_fn = draw_fn

	func _draw() -> void:
		_draw_fn.call(self)
