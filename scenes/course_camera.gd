class_name CourseCamera
extends Camera2D
## The course camera: pan with WASD or a middle-mouse drag, zoom in steps (0.5x, 1x, 2x by
## default) with the wheel or +/-. Numbers come from CameraTuning (scenes/camera_tuning.tres).
## The center is kept inside `bounds` grown by the edge margin, so the course never gets lost.
##
## Play (E2-S8): Main gives the camera a focus, the ball, when a shot starts, while it moves
## and after it rests. While tracking, the camera eases onto the focus (CameraTuning
## centre_time). A pan (keys or drag) stops tracking so the player can scout; the
## `snap_camera` key (C) snaps back to the ball and tracks it again.
##
## While the player aims at rest, Main also gives a lead, the aim marker (pillar 2: the
## player must see where the shot goes). The camera then centres on the midpoint of the ball
## and the marker, held so the ball stays on screen (CameraTuning aim_frame_margin), and if
## both do not fit it steps the zoom out, never past the farthest level, until they do. A
## flight has no lead, so the camera follows the ball alone. The zoom comes back to the
## player's own level (their last zoom key) when the next aim is framed with centre_on.

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

var _zoom_index: int = 0
## The zoom level the player chose with the zoom keys (or the start level).
var _player_zoom_index: int = 0
## True after a zoom key, until the next centre_on: the player's zoom wins over the fit.
var _player_zoomed: bool = false
var _dragging: bool = false


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


## Frames `p` with the focus from now on (the aim marker while aiming). A tracking camera
## steps its zoom out until both fit, unless the player zoomed since the last centre_on.
func set_lead(p: Vector2) -> void:
	lead = p
	has_lead = true
	if tracking and has_focus and not _player_zoomed:
		while _zoom_index > 0 and not fits(focus, lead, tuning.zoom_levels[_zoom_index]):
			set_zoom_index(_zoom_index - 1)


## Drops the lead (a flight): the camera follows the focus alone. The zoom stays.
func clear_lead() -> void:
	has_lead = false


## Centres on `p` from now on: the focus moves there and the camera tracks it again, even
## after the player panned away. With `restore_zoom` (a new aim: Play, or the ball at rest)
## the zoom goes back to the player's own level, and the lead is dropped until Main sets it.
func centre_on(p: Vector2, restore_zoom: bool = false) -> void:
	set_focus(p)
	tracking = true
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


## Where the camera wants to centre: the focus, or with a lead the midpoint of the two, held
## so the focus stays at least aim_frame_margin screen px inside the edge.
func goal() -> Vector2:
	if not has_lead:
		return focus
	var mid := (focus + lead) * 0.5
	var reach := (view_size() * 0.5 - Vector2.ONE * _frame_margin()) / zoom.x
	reach = reach.max(Vector2.ZERO)
	return mid.clamp(focus - reach, focus + reach)


## Back to the ball after a pan: tracks the focus again. Nothing without one.
func snap_back() -> void:
	if has_focus:
		tracking = true


## Moves the zoom one step in (+1) or out (-1), stopping at the ends. The player's choice:
## it holds over the aim fit until the next centre_on, and centre_on comes back to it.
func step_zoom(direction: int) -> void:
	set_zoom_index(_zoom_index + signi(direction))
	_player_zoom_index = _zoom_index
	_player_zoomed = true


func set_zoom_index(index: int) -> void:
	_zoom_index = clampi(index, 0, tuning.zoom_levels.size() - 1)
	var z: float = tuning.zoom_levels[_zoom_index]
	zoom = Vector2(z, z)


## The zoom level frame_points frames world points `a` and `b` at inside an area `area` px in
## size: the player's own level, stepped out until both fit, never past the farthest (0).
func frame_zoom_index(a: Vector2, b: Vector2, area: Vector2) -> int:
	var i: int = clampi(_player_zoom_index, 0, tuning.zoom_levels.size() - 1)
	while i > 0 and not fits(a, b, tuning.zoom_levels[i], area):
		i -= 1
	return i


## Frames world points `a` and `b` (a hole's tee and cup, E3-S2) inside `safe`, the part of
## the view the HUD leaves free (screen px; an empty rect is the whole view): from the player's
## own zoom, steps the zoom out until both fit inside it, never past the farthest level, and
## puts their midpoint at its centre. When they do not fit even then, `a` (the tee) is held at
## least aim_frame_margin inside it, so a long hole still shows where it starts. The bounds
## stay; the camera is not tracking. The player's zoom level is kept, so Play's next centre_on
## comes back to it.
func frame_points(a: Vector2, b: Vector2, safe: Rect2 = Rect2()) -> void:
	tracking = false
	has_focus = false
	has_lead = false
	var v: Vector2 = view_size()
	if not safe.has_area():
		safe = Rect2(Vector2.ZERO, v)
	set_zoom_index(frame_zoom_index(a, b, safe.size))
	var z: float = zoom.x
	# A world point w shows at (w - position) * z + v / 2: put the midpoint at safe's centre.
	var p: Vector2 = (a + b) * 0.5 - (safe.get_center() - v * 0.5) / z
	var m: Vector2 = Vector2.ONE * _frame_margin()
	var lo: Vector2 = a - (safe.end - m - v * 0.5) / z
	var hi: Vector2 = a - (safe.position + m - v * 0.5) / z
	position = _clamped(p.clamp(lo.min(hi), hi.max(lo)))


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


func _ease_to_focus(delta: float) -> void:
	var target := _clamped(goal())
	var t: float = tuning.centre_time if tuning != null else 0.0
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
