class_name CourseCamera
extends Camera2D
## The course camera: pan with WASD or a middle-mouse drag, zoom in steps (0.175x, 0.5x, 1x,
## 2x by default; D45) with the wheel or +/-. Numbers come from CameraTuning (scenes/camera_tuning.tres).
## The center is kept inside `bounds` grown by the edge margin, so the course never gets lost.
##
## Play (E2-S8): Main gives the camera a focus, the ball, when a shot starts, while it moves
## and after it rests. While tracking, the camera eases onto the focus (CameraTuning
## centre_time). A pan (keys or drag) stops tracking so the player can scout; the
## `snap_camera` key (C) snaps back to the ball and tracks it again.
##
## While the player aims at rest, Main also gives a lead, the aim marker (pillar 2: the
## player must see where the shot goes). The first lead after a centre_on (or a snap_back)
## frames the aim: the midpoint of the ball and the marker at the centre of the hold box
## (hold_box: `safe_area`, the free view Main passes, inset by CameraTuning aim_hold_inset),
## and if both do not fit it steps the zoom out, never past CameraTuning aim_farthest_zoom
## (0.5x), until they do. After that the camera holds still (E10-S2): moving the aim, by mouse
## or keys, or changing club does not move it while the ball and the marker stay inside the
## hold box; when one would leave it, the camera glides (CameraTuning aim_glide_time) just far
## enough to bring it back, the ball first when both cannot fit. A flight has no lead, so the
## camera follows the ball alone. The zoom comes back to the player's own level (their last
## zoom key) when the next aim is framed with centre_on.

const PAN_LEFT: StringName = &"pan_left"
const PAN_RIGHT: StringName = &"pan_right"
const PAN_UP: StringName = &"pan_up"
const PAN_DOWN: StringName = &"pan_down"
const ZOOM_IN: StringName = &"zoom_in"
const ZOOM_OUT: StringName = &"zoom_out"
const SNAP_BACK: StringName = &"snap_camera"

@export var tuning: CameraTuning

## Course rectangle in world space. Empty means no clamp.
var bounds: Rect2 = Rect2():
	set(value):
		bounds = value
		position = _clamped(position)

var zoom_index: int:
	get:
		return _zoom_index

## The world point the camera centres on in Play (the ball), valid when `has_focus`.
var focus: Vector2 = Vector2.ZERO
var has_focus: bool = false
## True while the camera follows `focus`; a pan clears it, snap_back sets it.
var tracking: bool = false
## The second world point framed with the focus (the aim marker), valid when `has_lead`.
var lead: Vector2 = Vector2.ZERO
var has_lead: bool = false
## The visible size in screen pixels. Zero, the default, reads the viewport; tests set it.
var view_size_override: Vector2 = Vector2.ZERO
## The part of the view the HUD leaves free, in screen px (Main.free_view_rect, set each Play
## frame). The hold box is inset from it. Empty means the whole view.
var safe_area: Rect2 = Rect2()

var _zoom_index: int = 0
## The zoom level the player chose with the zoom keys (or the start level).
var _player_zoom_index: int = 0
## True after a zoom key, until the next centre_on: the player's zoom wins over the fit.
var _player_zoomed: bool = false
var _dragging: bool = false
## True once the aim is framed (E10-S2): the camera then holds at `_hold`, moved only as far as
## keeps the ball and the lead in the hold box. A centre_on, a snap_back or a cleared lead
## frames the next aim afresh.
var _held: bool = false
var _hold: Vector2 = Vector2.ZERO


func _ready() -> void:
	if tuning == null:
		tuning = CameraTuning.load_default()
	set_zoom_index(tuning.start_zoom_index)
	_player_zoom_index = _zoom_index


func _process(delta: float) -> void:
	var dir: Vector2 = Input.get_vector(PAN_LEFT, PAN_RIGHT, PAN_UP, PAN_DOWN)
	if dir != Vector2.ZERO:
		pan(dir * tuning.pan_speed * delta)
	if tracking and has_focus:
		_ease_to_focus(delta)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = mb.pressed
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and (_dragging or (motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0):
		# Drag the course with the cursor: move opposite to the mouse.
		pan(-motion.relative)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(SNAP_BACK):
		snap_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ZOOM_IN):
		step_zoom(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ZOOM_OUT):
		step_zoom(-1)
		get_viewport().set_input_as_handled()


## Moves the view by `screen_delta` screen pixels, whatever the zoom. The player is
## scouting, so the camera stops tracking the ball until snap_back.
func pan(screen_delta: Vector2) -> void:
	tracking = false
	position = _clamped(position + screen_delta / zoom.x)


## Moves the focus (the ball) to the world point `p`. A tracking camera follows it.
func set_focus(p: Vector2) -> void:
	focus = p
	has_focus = true


## Frames `p` with the focus from now on (the aim marker while aiming). The first lead of an
## aim frames it: a tracking camera steps its zoom out until both fit the hold box, unless the
## player zoomed since the last centre_on, and centres their midpoint in it. Every later lead
## only moves the held point as far as keeps both in the hold box (E10-S2), so the zoom never
## steps and the camera never jumps while the player aims.
func set_lead(p: Vector2) -> void:
	lead = p
	has_lead = true
	if not (tracking and has_focus):
		return
	if not _held:
		if not _player_zoomed:
			var floor_index: int = aim_floor_index()
			while _zoom_index > floor_index and not fits_hold(focus, lead, tuning.zoom_levels[_zoom_index]):
				set_zoom_index(_zoom_index - 1)
		_hold = _clamped(held_at(framed_at()))
		_held = true
	else:
		_hold = _clamped(held_at(_hold))


## The hold box (E10-S2), in screen px: `safe_area` (or the whole view) inset on each side by
## CameraTuning aim_hold_inset of its size. While aiming, the camera holds still as long as the
## ball and the aim marker are inside it.
func hold_box() -> Rect2:
	var area: Rect2 = safe_area if safe_area.has_area() else Rect2(Vector2.ZERO, view_size())
	var inset: Vector2 = area.size * (tuning.aim_hold_inset if tuning != null else 0.0)
	return area.grow_individual(-inset.x, -inset.y, -inset.x, -inset.y)


## True when world points `a` and `b` both fit in the hold box at zoom `z`.
func fits_hold(a: Vector2, b: Vector2, z: float) -> bool:
	var d: Vector2 = (b - a).abs() * z
	var box: Vector2 = hold_box().size
	return d.x <= box.x and d.y <= box.y


## Where the camera centres to frame an aim: the midpoint of the focus and held_lead at the
## hold box's centre.
func framed_at() -> Vector2:
	return (focus + held_lead()) * 0.5 - (hold_box().get_center() - view_size() * 0.5) / zoom.x


## The point the camera keeps in the hold box for the lead: the lead itself, or when the ball
## and the lead do not both fit the box (the player zoomed in), the point along the aim line
## from the ball that spans CameraTuning aim_hold_reach of the box. So a zoomed-in camera
## leans toward the marker and still has room for a small turn before it glides.
func held_lead() -> Vector2:
	if fits_hold(focus, lead, zoom.x):
		return lead
	var d: Vector2 = (lead - focus).abs() * zoom.x
	var room: Vector2 = hold_box().size * (tuning.aim_hold_reach if tuning != null else 1.0)
	var s: float = 1.0
	if d.x > room.x:
		s = minf(s, room.x / d.x)
	if d.y > room.y:
		s = minf(s, room.y / d.y)
	return focus + (lead - focus) * s


## The camera position nearest `at` that shows the focus and held_lead inside the hold box at
## the current zoom: `at` itself when both already are, the focus (the ball) first.
func held_at(at: Vector2) -> Vector2:
	var box: Rect2 = hold_box()
	var half: Vector2 = view_size() * 0.5
	var z: float = zoom.x
	var aim: Vector2 = held_lead()
	# A world point w shows inside the box when w - (box.end - half) / z <= position <=
	# w - (box.position - half) / z.
	var ball_lo: Vector2 = focus - (box.end - half) / z
	var ball_hi: Vector2 = focus - (box.position - half) / z
	var lead_lo: Vector2 = aim - (box.end - half) / z
	var lead_hi: Vector2 = aim - (box.position - half) / z
	var p: Vector2 = at.clamp(lead_lo.min(lead_hi), lead_hi.max(lead_lo))
	return p.clamp(ball_lo.min(ball_hi), ball_hi.max(ball_lo))


## The farthest zoom level the aim fit steps out to (CameraTuning aim_farthest_zoom, D45): the
## first level at or nearer than it. The zoom keys and hole framing reach farther.
func aim_floor_index() -> int:
	for i: int in tuning.zoom_levels.size():
		if tuning.zoom_levels[i] >= tuning.aim_farthest_zoom - 0.0001:
			return i
	return tuning.zoom_levels.size() - 1


## Drops the lead (a flight): the camera follows the focus alone. The zoom stays.
func clear_lead() -> void:
	has_lead = false
	_held = false


## Centres on `p` from now on: the focus moves there and the camera tracks it again, even
## after the player panned away. With `restore_zoom` (a new aim: Play, or the ball at rest)
## the zoom goes back to the player's own level, and the lead is dropped until Main sets it.
func centre_on(p: Vector2, restore_zoom: bool = false) -> void:
	set_focus(p)
	tracking = true
	_held = false
	if restore_zoom:
		has_lead = false
		_player_zoomed = false
		set_zoom_index(_player_zoom_index)


## True when world points `a` and `b` both fit on screen at zoom `z`, each at least
## aim_frame_margin screen px inside the edge: of the view, or of an area `area` px in size.
func fits(a: Vector2, b: Vector2, z: float, area: Vector2 = Vector2.ZERO) -> bool:
	var d := (b - a).abs() * z + Vector2.ONE * 2.0 * _frame_margin()
	var v := area if area != Vector2.ZERO else view_size()
	return d.x <= v.x and d.y <= v.y


## The visible size in screen pixels.
func view_size() -> Vector2:
	if view_size_override != Vector2.ZERO:
		return view_size_override
	return get_viewport_rect().size if is_inside_tree() else Vector2.ZERO


## Where the camera wants to centre: the focus, or with a lead the held point (E10-S2), or
## before the aim is framed the framing (the midpoint in the hold box, the ball kept inside).
func goal() -> Vector2:
	if not has_lead:
		return focus
	if _held:
		return _hold
	return held_at(framed_at())


## Back to the ball after a pan (C): tracks the focus again and, while aiming, frames the aim
## afresh. Nothing without a focus.
func snap_back() -> void:
	if has_focus:
		tracking = true
		_held = false
		if has_lead:
			set_lead(lead)


## Moves the zoom one step in (+1) or out (-1), stopping at the ends. The player's choice:
## it holds over the aim fit until the next centre_on, and centre_on comes back to it. While
## aiming, the aim is framed afresh at the new zoom (one glide, E10-S2).
func step_zoom(direction: int) -> void:
	set_zoom_index(_zoom_index + signi(direction))
	_player_zoom_index = _zoom_index
	_player_zoomed = true
	_held = false


func set_zoom_index(index: int) -> void:
	_zoom_index = clampi(index, 0, tuning.zoom_levels.size() - 1)
	var z: float = tuning.zoom_levels[_zoom_index]
	zoom = Vector2(z, z)


## The index of the zoom level nearest `z` (such as 0.5 for 0.5x), so a fixture or script names
## a zoom by its value, not by its place in the list.
func zoom_index_of(z: float) -> int:
	var best: int = 0
	for i: int in tuning.zoom_levels.size():
		if absf(tuning.zoom_levels[i] - z) < absf(tuning.zoom_levels[best] - z):
			best = i
	return best


## Sets the zoom to the level nearest `z` (set_zoom_index).
func set_zoom_level(z: float) -> void:
	set_zoom_index(zoom_index_of(z))


## The zoom level frame_points frames world points `a` and `b` at inside an area `area` px in
## size: the player's own level, stepped out until both fit, never past the farthest (0, 0.175x:
## unlike the aim fit, hole framing reaches it, D45).
func frame_zoom_index(a: Vector2, b: Vector2, area: Vector2) -> int:
	var i: int = clampi(_player_zoom_index, 0, tuning.zoom_levels.size() - 1)
	while i > 0 and not fits(a, b, tuning.zoom_levels[i], area):
		i -= 1
	return i


## Frames world points `a` and `b` (a hole's tee and cup, E3-S2) inside `safe`, the part of
## the view the HUD leaves free (screen px; an empty rect is the whole view): from the player's
## own zoom, steps the zoom out until both fit inside it, never past the farthest level, and
## puts their midpoint at its centre. When they do not fit even then, `a` (the tee) is held at
## least aim_frame_margin inside it, so a long hole still shows where it starts. `free` (E3-S26)
## is every part of the view the HUD leaves free (Main.free_view_rects); given it, a cup that
## would then show on screen under a control is moved clear (frame_placement). The bounds
## stay; the camera is not tracking. The player's zoom level is kept, so Play's next centre_on
## comes back to it.
func frame_points(a: Vector2, b: Vector2, safe: Rect2 = Rect2(), free: Array[Rect2] = []) -> void:
	tracking = false
	has_focus = false
	has_lead = false
	_held = false
	var f: Framing = frame_placement(a, b, safe, free)
	set_zoom_index(f.zoom_index)
	position = f.position


## Where frame_points would put the camera for `a` and `b` in `safe`, and what it shows.
class Framing:
	extends RefCounted
	var zoom_index: int = 0
	var position: Vector2 = Vector2.ZERO
	## True when `b` (the cup) is either off the screen, at least aim_frame_margin past its edge,
	## or inside one of the free rects (inset by aim_frame_margin, or by a quarter of a strip
	## too thin for it), so no control covers it.
	var cup_clear: bool = true
	## How much of the screen line from `a` to `b` lies in the free rects, 0 to 1.
	var shown: float = 0.0


## The framing frame_points uses (E3-S26). With `free` empty it is E3-S9's: the midpoint at
## `safe`'s centre, the tee held inside when the hole does not fit. With `free` given and a
## hole too long for the farthest zoom whose cup would then show on screen under a control, the
## tee is moved within `safe` (a grid of FRAME_SEARCH_STEP px) to where the cup is clear (off
## the screen, or inside a free rect) and the most of the tee-to-cup line shows; with no such
## place the first framing stays.
func frame_placement(a: Vector2, b: Vector2, safe: Rect2 = Rect2(), free: Array[Rect2] = []) -> Framing:
	var f := Framing.new()
	var v: Vector2 = view_size()
	if not safe.has_area():
		safe = Rect2(Vector2.ZERO, v)
	f.zoom_index = frame_zoom_index(a, b, safe.size)
	var z: float = tuning.zoom_levels[f.zoom_index]
	# A world point w shows at (w - position) * z + v / 2: put the midpoint at safe's centre.
	var p: Vector2 = (a + b) * 0.5 - (safe.get_center() - v * 0.5) / z
	var m: Vector2 = Vector2.ONE * _frame_margin()
	var lo: Vector2 = a - (safe.end - m - v * 0.5) / z
	var hi: Vector2 = a - (safe.position + m - v * 0.5) / z
	f.position = _clamped(p.clamp(lo.min(hi), hi.max(lo)))
	if free.is_empty():
		f.shown = _shown(a, b, f.position, z, [safe])
		return f
	f.cup_clear = _cup_clear(_screen_at(b, f.position, z), free)
	f.shown = _shown(a, b, f.position, z, free)
	if f.cup_clear or fits(a, b, z, safe.size):
		return f
	# The cup would show under a control: look for a tee point in safe that clears it.
	var area: Rect2 = _inset(safe)
	var first_tee: Vector2 = _screen_at(a, f.position, z)
	var best_d: float = INF
	var found: bool = false
	var y: float = area.position.y
	while y <= area.end.y + 0.01:
		var x: float = area.position.x
		while x <= area.end.x + 0.01:
			var q: Vector2 = _clamped(a - (Vector2(x, y) - v * 0.5) / z)
			var t: Vector2 = _screen_at(a, q, z)
			if area.grow(0.5).has_point(t) and _cup_clear(_screen_at(b, q, z), free):
				var shown: float = _shown(a, b, q, z, free)
				var d: float = t.distance_squared_to(first_tee)
				if not found or shown > f.shown + 0.001 or (shown > f.shown - 0.001 and d < best_d):
					found = true
					f.shown = shown
					f.position = q
					best_d = d
			x += FRAME_SEARCH_STEP
		y += FRAME_SEARCH_STEP
	f.cup_clear = found
	return f


## The tee grid frame_placement searches, in screen px (not a tuning number: a finer grid only
## finds the same framing a few px over).
const FRAME_SEARCH_STEP: float = 16.0


## `r` inset by aim_frame_margin on each side, or by a quarter of its size on a side too thin
## for it, so a thin strip (the one under a tall hole panel) still holds a point.
func _inset(r: Rect2) -> Rect2:
	var m: Vector2 = (Vector2.ONE * _frame_margin()).min(r.size * 0.25)
	return r.grow_individual(-m.x, -m.y, -m.x, -m.y)


## True when screen point `c` (a cup) shows under no control: off the screen by at least
## aim_frame_margin, or inside one of `free` inset (_inset).
func _cup_clear(c: Vector2, free: Array[Rect2]) -> bool:
	if not Rect2(Vector2.ZERO, view_size()).grow(_frame_margin()).has_point(c):
		return true
	for r: Rect2 in free:
		if r.has_area() and _inset(r).has_point(c):
			return true
	return false


## How much of the screen line from `a` to `b`, with the camera at `pos` and zoom `z`, lies in
## the union of `rects`, as a fraction of its length (1 for a point inside one).
func _shown(a: Vector2, b: Vector2, pos: Vector2, z: float, rects: Array[Rect2]) -> float:
	var s: Vector2 = _screen_at(a, pos, z)
	var e: Vector2 = _screen_at(b, pos, z)
	var spans: Array[Vector2] = []
	for r: Rect2 in rects:
		var span: Vector2 = _clip(s, e, r)
		if span.y > span.x:
			spans.append(span)
	if spans.is_empty():
		return 0.0
	spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var total: float = 0.0
	var cur: Vector2 = spans[0]
	for i: int in range(1, spans.size()):
		if spans[i].x <= cur.y:
			cur.y = maxf(cur.y, spans[i].y)
		else:
			total += cur.y - cur.x
			cur = spans[i]
	return total + cur.y - cur.x


## The part of the segment `s` to `e` inside `r`, as parameters (t0, t1) along it (Liang-Barsky);
## t1 <= t0 when it misses.
static func _clip(s: Vector2, e: Vector2, r: Rect2) -> Vector2:
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector2 = e - s
	for axis: int in 2:
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(d[axis]) < 0.000001:
			if s[axis] < lo or s[axis] > hi:
				return Vector2(1, 0)
			continue
		var ta: float = (lo - s[axis]) / d[axis]
		var tb: float = (hi - s[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if s == e:
		return Vector2(0, 1) if r.has_point(s) else Vector2(1, 0)
	return Vector2(t0, t1)


## Where world point `w` shows on screen with the camera at `pos` and zoom `z`.
func _screen_at(w: Vector2, pos: Vector2, z: float) -> Vector2:
	return (w - pos) * z + view_size() * 0.5


## Where world point `w` shows on screen, in px, at the camera's position and zoom.
func screen_point(w: Vector2) -> Vector2:
	return (w - position) * zoom.x + view_size() * 0.5


## Back to the player's own zoom level (a new course is framed at it).
func restore_zoom() -> void:
	set_zoom_index(_player_zoom_index)


## Centers on `rect` and clamps to it from now on.
func frame(rect: Rect2) -> void:
	tracking = false
	has_focus = false
	bounds = rect
	position = _clamped(rect.get_center())


## Eases onto goal(): at CameraTuning centre_time on a ball, at aim_glide_time while aiming.
func _ease_to_focus(delta: float) -> void:
	var target := _clamped(goal())
	var t: float = 0.0
	if tuning != null:
		t = tuning.aim_glide_time if has_lead else tuning.centre_time
	if t <= 0.0:
		position = target
	else:
		position = position.lerp(target, 1.0 - exp(-delta / t))
		if position.distance_to(target) < 0.01:
			position = target


func _frame_margin() -> float:
	return tuning.aim_frame_margin if tuning != null else 0.0


func _clamped(p: Vector2) -> Vector2:
	if not bounds.has_area():
		return p
	var margin: float = tuning.edge_margin if tuning != null else 0.0
	var r: Rect2 = bounds.grow(margin)
	return p.clamp(r.position, r.end)
