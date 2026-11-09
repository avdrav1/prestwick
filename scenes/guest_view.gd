class_name GuestView
extends Node2D
## Draws the guests' day on the course (E3-S5): every guest on the course as a golfer sprite
## (art/specs/golfer.md: 8 directions, idle, walk, swing) and its ball. A reader only: it
## never changes a guest, a ball or the course, so what the camera looks at never changes the
## day (the same seed gives the same day).
##
## Y-sort: a child of CourseView, Y-sorted like ShotView. Each figure and ball is a node at
## y = Iso.object_sort_key on the ground under it, drawn offset back to its screen point on the
## drawn ground (HeightField.ground_screen, D50), so the terrain sorts it: a hill in front
## hides it, the ground behind does not, and it sorts with the ball and the hole markers by the
## same rule.
##
## Walks: the brain moves a guest once per simulated second (up to `walk_yd_per_s` 40 yd), so
## the view slides each figure from where it stood at the last step to where it stands now,
## over the share of the second its leg takes (E3-S20: Guest.leg_start to leg_end, at walk
## speed; a whole leg over the whole second) by the share gone by (GuestBrain.step_fraction):
## it moves at the sim's speed and stops when paused. A figure faces the way it walks, else
## its hole's cup.
##
## Swing: a stroke is PLAYING for one simulated second (`stroke_s`); the 6 swing frames run
## over it by the same share. The swinging figure stands on its stroke's start, over its own
## ball. E3-S20: the brain strikes in the second a walk ended only when it ended within the
## swing's address (`swing_address_share`), and the view draws those last steps first, so a
## figure finishes its walk on screen before it swings. Its group spread closes over a swing
## frame's time once it stands there, and eases back in over `spread_ease_s` once the stroke
## is done.
##
## Sync (E3-S20): the ball leaves at the swing's impact frame (`swing_impact_share` of
## `stroke_s`, replay_head), and the brain sets the guest off to its ball only once the
## replay has drawn it to rest (GuestBrain.ball_shown_s), so a figure never walks off under
## its own ball's flight.
##
## Size: the figure is never drawn under `figure_min_screen_scale` times its native 24 px on
## screen (at 0.5x it is drawn at twice its size, one texel a screen pixel), so it reads as a
## person at every zoom (art/specs/golfer.md).
##
## Shirts (E3-S28): a figure wears its group's shirt, drawn by swapping the sheet's chalk in a
## shader material shared by everyone in that shirt, so a group reads as one and its neighbours
## differ. Since E3-S47 a group chooses its shirt when it arrives (assign_shirts): the first no
## group still on the course wears, else the one whose nearest wearer is farthest ahead, so the
## groups on a hole and the next differ by choice, not by arrival count.
##
## D45 (E3-S9 review): below BuilderTuning marker_min_screen_scale (0.5x) the whole view draws
## at z 1 (CourseView.lifted_z), as the grown tee markers and pins do, so figures and balls
## still Y-sort with them.
##
## Ball flights: the sim runs every guest's ball the same way, watched or not (GuestHole's
## off-screen shortcut: it rests within a simulated second or so). When a guest strikes and
## its ball's start is on screen (within GuestViewTuning.on_screen_margin_px of the view), the
## view replays the stroke's recorded path (GuestHole.stroke_path) from the impact frame,
## `flight_draw_speed` (D38; 7.5 since E3-S20) times faster than real, times the sim's speed:
## the ball at its height with a shadow under it in flight, on the drawn ground (D50) on the ground. Off screen there is no replay: the ball
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
## Group index -> the shirt it chose on arriving (assign_shirts), for this view's day.
var _shirts: Dictionary = {}
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
	## E3-S38: the step aside it takes now for a groupmate's swing, yards (in `at`; strike_room).
	var room: Vector2 = Vector2.ZERO
	## E3-S38: the sidestep it takes now walking past a striker, yards (in `at`; pass_room),
	## and the way it steps for each striker ({guest id: unit vector}, kept while it steps
	## aside for that striker, so a new walk leg keeps the same side).
	var aside: Vector2 = Vector2.ZERO
	var pass_sides: Dictionary = {}
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
		_shirts = {}
	if brain == null:
		return
	if brain.second != _second or _shirts.is_empty():
		assign_shirts(brain, _shirts, art.shirt_count())
	_time += delta
	var stepped := brain.second != _second
	_second = brain.second
	var frac := brain.step_fraction()
	# E3-S38: strikers first, so a partner steps aside (strike_room) by this frame's spread.
	for striking: bool in [true, false]:
		for guest: Guest in brain.guests:
			if (guest.state == Guest.State.PLAYING) != striking:
				continue
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


## The shirt figure `f` wears (E3-S28): its group's (assign_shirts, E3-S47), so a group reads
## as one and the groups on a hole and the next differ; the arrival-order shirt
## (GolferArt.shirt_of_group) for a group not yet given one.
func shirt_of(f: Figure) -> int:
	return _shirts.get(f.guest.group_id, art.shirt_of_group(f.guest.group_id))


## Gives every group of `brain` that has arrived and has no shirt in `shirts` (group index ->
## shirt) one of `count` shirts (E3-S47), in arrival order: the first shirt no group still on the
## course (walking to a tee or playing a hole) wears; when every shirt is worn, the shirt whose
## wearer nearest the first tee stands on the highest hole, so the new group (on hole 1, and
## groups never pass) meets it last if at all (the lower shirt at a tie). Groups given a shirt in
## the same call count as on the course whatever their phase, so a view that first looks after
## several arrivals (a fixture, a frame of many steps) still gives them shirts as if it had seen
## each arrive. Deterministic for the same brain stepped the same way; tests step a headless
## brain through it.
static func assign_shirts(brain: GuestBrain, shirts: Dictionary, count: int) -> void:
	count = maxi(count, 1)
	var fresh := {}
	for g: GuestGroup in brain.groups:
		if g.phase == GuestGroup.Phase.PENDING or shirts.has(g.index):
			continue
		# Each worn shirt's lowest hole among the groups on the course.
		var lowest := {}
		for o: GuestGroup in brain.groups:
			if o == g or not shirts.has(o.index):
				continue
			if o.phase != GuestGroup.Phase.TO_TEE and o.phase != GuestGroup.Phase.ON_HOLE \
					and not fresh.has(o.index):
				continue
			var s: int = shirts[o.index]
			lowest[s] = mini(lowest.get(s, o.hole_number), o.hole_number)
		var pick: int = -1
		for s: int in count:
			if not lowest.has(s):
				pick = s
				break
		if pick < 0:
			pick = 0
			for s: int in count:
				if lowest[s] > lowest[pick]:
					pick = s
		shirts[g.index] = pick
		fresh[g.index] = true


## A guest's place in its group as a small sideways step on screen, yards: half a spread left
## and right of the spot, then one and a half (screen x is along +x and -y of the grid). E3-S38:
## nobody stands on the spot itself (until E3-S38 place 0 did), where a striker on the tee
## closes in over its ball.
func place_offset(place: int) -> Vector2:
	var m: float = [-0.5, 0.5, -1.5, 1.5][place % 4]
	return Vector2(1.0, -1.0) * tuning.group_spread_yd * m


## E3-S38: the step back, yards, a figure drawn at `at` takes while a groupmate swings beside
## it: toward the top of the screen (across the group's sideways spread, along which the
## striker closes in over its ball, so the two never cross), up to `strike_room_yd`, in step
## with the striker's spread closing and easing back (a groupmate easing back after its swing
## still counts), and fading out from two `strike_room_yd` away. Smooth both ways, so nobody
## jumps; on the tee no standing partner is drawn over the striker. Strikers are drawn first
## each frame (update_view).
func strike_room(f: Figure, at: Vector2) -> Vector2:
	var room := 0.0
	var reach := maxf(2.0 * tuning.strike_room_yd, 0.001)
	for other: Figure in _figures.values():
		if other == f or other.guest.group_id != f.guest.group_id or other.spread >= 1.0:
			continue
		var near := clampf(1.0 - at.distance_to(other.at) / reach, 0.0, 1.0)
		room = maxf(room, (1.0 - other.spread) * near)
	return Vector2(-1.0, -1.0).normalized() * tuning.strike_room_yd * room


## E3-S38: the sidestep, yards, a figure drawn at `at` and walking along `dir` (unit) takes past
## a groupmate that swings (or eases its spread back): across its walk line, away from the
## striker, so its distance to the striker never falls under `pass_room_yd` on a straight walk.
## The step is `pass_room_yd` less the walk line's distance from the striker, times
## 1 - (along / reach)^2 where `along` is how far the figure is from the striker along its walk
## (reach two strike_room_yd: wide enough that the eased step never dips inside), times how far
## the striker's spread has closed. Smooth both ways and always to one side of each striker
## (kept in `pass_sides` while it steps), so a walker bends round the striker, never orbits it.
func pass_room(f: Figure, at: Vector2, dir: Vector2) -> Vector2:
	var clear := tuning.pass_room_yd
	var reach := maxf(2.0 * tuning.strike_room_yd, clear * 1.5)
	var normal := Vector2(-dir.y, dir.x)
	var out := Vector2.ZERO
	var sides := {}
	for other: Figure in _figures.values():
		if other == f or other.guest.group_id != f.guest.group_id or other.spread >= 1.0:
			continue
		var rel := at - other.at
		var along := rel.dot(dir)
		var bump := 1.0 - (along / reach) * (along / reach)
		if bump <= 0.0:
			continue
		var perp := rel.dot(normal)
		var side := 1.0 if perp >= 0.0 else -1.0
		if f.pass_sides.has(other.guest.id):
			side = 1.0 if (f.pass_sides[other.guest.id] as Vector2).dot(normal) >= 0.0 else -1.0
		var need := maxf(clear - perp * side, 0.0) * bump * (1.0 - other.spread)
		if need <= 0.0:
			continue
		sides[other.guest.id] = normal * side
		if need > out.length():
			out = normal * side * need
	f.pass_sides = sides
	return out


## Screen vector (CourseView space, x right, y down) of a step `d` in yards.
func screen_vector(d: Vector2) -> Vector2:
	var t := d / _field.yards_per_tile
	return Vector2((t.x - t.y) * Iso.HALF_W, (t.x + t.y) * Iso.HALF_H)


func _update_figure(f: Figure, delta: float, speed: float, frac: float) -> void:
	var g := f.guest
	# E3-S20: the leg walked in the step just run goes at walk speed from `leg_start` to
	# `leg_end` of the second (a whole leg 0 to 1; a first leg after a stroke sets off as the
	# ball rests on screen; a last leg ends when the guest gets there).
	var s0 := 0.0
	var s1 := 1.0
	if g.last_walk_s == _brain.second - 1:
		s0 = g.leg_start
		s1 = maxf(g.leg_end, s0 + 0.001)
	var p := clampf((frac - s0) / (s1 - s0), 0.0, 1.0)
	var walking := frac >= s0 and frac < s1
	if g.state == Guest.State.PLAYING:
		# Over its own ball for the swing, not still sliding along its last walk leg.
		var stand := g.position
		if g.hole != null and not g.hole.strokes.is_empty():
			var start: Vector3 = g.hole.strokes[-1].start
			stand = Vector2(start.x, start.y)
		# E3-S20: a walk that ended in the second it struck ended within the address
		# (GuestBrain.at_ball): its last steps are drawn first, then the address.
		var up := 0.0
		if g.last_walk_s != g.strike_s or f.from.distance_squared_to(stand) <= 1e-6:
			f.from = stand
			walking = false
		else:
			up = s1
		f.to = stand
		# The group spread closes over a swing frame's time once it stands at its ball, not in
		# one jump (E3-S20), nor while it still walks.
		var closing := maxf(frac - up, 0.0) * art.frames_per_dir(GolferArt.Anim.SWING)
		f.spread = minf(f.spread, maxf(0.0, 1.0 - closing))
	else:
		f.spread = minf(1.0, f.spread + delta * speed / maxf(tuning.spread_ease_s, 0.001))
	f.at = f.from.lerp(f.to, p) + place_offset(g.place) * f.spread
	# E3-S38: a figure walking this second sidesteps round a striker across its walk line
	# (pass_room) instead of stepping back up the screen (strike_room), whose push would carry it
	# across the line it steps aside from. Over the last yards of the walk the sidestep fades out
	# and the step back fades in, so a walker that stops beside the striker (or swings next) is
	# where a standing figure would be when it stops. Either step moves no faster than a walk.
	var walker := g.state != Guest.State.PLAYING and f.from.distance_squared_to(f.to) > 1e-6
	var step := guest_tuning.walk_yd_per_s * speed * delta
	var walk_share := 0.0
	if walker:
		var end: Vector2 = g.walk.end() if g.walk != null else f.to
		walk_share = clampf(f.at.distance_to(end) / maxf(4.0 * tuning.strike_room_yd, 0.001), 0.0, 1.0)
	var room := strike_room(f, f.at) * (1.0 - walk_share)
	if g.state == Guest.State.PLAYING:
		# A striker that stood aside for the last stroke steps back to its ball as its own
		# spread closes, so it neither jumps nor swings off its ball.
		room *= f.spread
	var aside := Vector2.ZERO
	if walker:
		aside = pass_room(f, f.at + f.room.move_toward(room, step), (f.to - f.from).normalized()) * walk_share
	else:
		f.pass_sides = {}
	# E4-S10: the step back and the sidestep move together no faster than a walk, not each at a
	# walk: a walker that stops beside a striker still holding its sidestep and then strikes
	# itself drops the sidestep as it takes up the step back, in the same frame.
	var shift := _together(room - f.room, aside - f.aside, step)
	f.room += shift[0]
	f.at += f.room
	f.aside += shift[1]
	f.at += f.aside
	var moving := walking and f.from.distance_squared_to(f.to) > 1e-6
	var d := -1
	if moving:
		d = GolferArt.direction_of(screen_vector(f.to - f.from))
	elif g.hole != null:
		d = GolferArt.direction_of(screen_vector(_field.tile_center(g.hole.hole.cup) - f.at))
	if d >= 0:
		f.dir = d
	if g.state == Guest.State.PLAYING and not moving:
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


## E4-S10: moves `a` and `b` (yards) cut by one share, so that each, and the two together, are
## no longer than `step`: [a, b] as cut.
static func _together(a: Vector2, b: Vector2, step: float) -> Array[Vector2]:
	var longest := maxf(maxf(a.length(), b.length()), (a + b).length())
	var k := 1.0 if longest <= step else step / longest
	return [a * k, b * k]


func _update_ball(f: Figure, delta: float, speed: float) -> void:
	var h := f.guest.hole
	if h != f.hole:
		f.hole = h
		f.strokes_seen = 0
	if h != null and h.strokes.size() > f.strokes_seen:
		f.strokes_seen = h.strokes.size()
		f.replay_hole = null
		var start: Vector3 = h.strokes[-1].start
		if on_screen(_field.ground_screen(start)):
			f.replay_hole = h
			f.replay_stroke = h.strokes.size()
			f.replay_head = 0.0
	if f.replay_hole != null:
		var rh := f.replay_hole
		var path := rh.stroke_path()
		if rh.strokes.size() != f.replay_stroke or path.is_empty():
			f.replay_hole = null
		else:
			f.replay_head = replay_head(f.guest)
			var last := path.size() - 1
			var i := clampi(floori(f.replay_head), 0, last)
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


## The tick of `guest`'s latest stroke path drawn now (E3-S20): none before the club meets
## the ball (`swing_impact_share` of `stroke_s` after the strike, the swing's impact frame),
## then `flight_draw_speed` ticks a simulated tick. Timed from the brain's clock (the strike's
## second and the share of the second gone by), as the swing frames are, so the ball leaves
## on the impact frame at any speed and stops when paused; the brain walks the guest once it
## is drawn to rest (GuestBrain.ball_shown_s).
func replay_head(guest: Guest) -> float:
	var since := float(_brain.second - 1 - guest.strike_s) + _brain.step_fraction()
	return (since - guest_tuning.impact_s()) * Ball.TICK_HZ * guest_tuning.flight_draw_speed


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


## Puts `piece` at the sort key of the ground under `p` (yards), on the drawn ground.
func _place(piece: Node2D, p: Vector3) -> void:
	piece.visible = true
	var iso := _field.iso_point(p)
	var screen := _field.ground_screen(p)
	piece.position = Vector2(screen.x, Iso.object_sort_key(Vector2(iso.x, iso.y), _field.drawn_steps(p.x, p.y)))
	piece.queue_redraw()


## Where figure `f`'s feet are drawn, CourseView space.
func figure_screen(f: Figure) -> Vector2:
	return _field.ground_screen(Vector3(f.at.x, f.at.y, 0.0))


## Where `f`'s ball is drawn, CourseView space: at its height in the air, on the drawn ground
## on the ground (D50).
func ball_screen(f: Figure) -> Vector2:
	if f.ball_flying:
		return Iso.point_to_screen(_field.iso_point(f.ball_at))
	return _field.ground_screen(f.ball_at)


## The box figure `f`'s sprite covers, CourseView space (as _draw_figure lays it out).
func figure_rect(f: Figure) -> Rect2:
	var s := figure_scale()
	var tex := art.frame(f.anim, f.dir, f.frame)
	return Rect2(figure_screen(f) - Vector2(art.anchor()) * s, tex.get_size() * s)


## The boxes of every figure drawn now (E3-S63: a map tag over one fades), CourseView space;
## none while the view is hidden.
func figure_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _field == null or not is_visible_in_tree():
		return out
	for f: Figure in _figures.values():
		if f.sprite.visible:
			out.append(figure_rect(f))
	return out


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
		var shadow := _field.ground_screen(f.ball_at) - piece.position
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
