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

var _zoom_index: int = 0
var _dragging: bool = false


func _ready() -> void:
	if tuning == null:
		tuning = CameraTuning.load_default()
	set_zoom_index(tuning.start_zoom_index)


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


## Centres on `p` from now on: the focus moves there and the camera tracks it again, even
## after the player panned away.
func centre_on(p: Vector2) -> void:
	set_focus(p)
	tracking = true


## Back to the ball after a pan: tracks the focus again. Nothing without one.
func snap_back() -> void:
	if has_focus:
		tracking = true


## Moves the zoom one step in (+1) or out (-1), stopping at the ends.
func step_zoom(direction: int) -> void:
	set_zoom_index(_zoom_index + signi(direction))


func set_zoom_index(index: int) -> void:
	_zoom_index = clampi(index, 0, tuning.zoom_levels.size() - 1)
	var z: float = tuning.zoom_levels[_zoom_index]
	zoom = Vector2(z, z)


## Centers on `rect` and clamps to it from now on.
func frame(rect: Rect2) -> void:
	tracking = false
	has_focus = false
	bounds = rect
	position = _clamped(rect.get_center())


func _ease_to_focus(delta: float) -> void:
	var goal := _clamped(focus)
	var t: float = tuning.centre_time if tuning != null else 0.0
	if t <= 0.0:
		position = goal
	else:
		position = position.lerp(goal, 1.0 - exp(-delta / t))
		if position.distance_to(goal) < 0.01:
			position = goal


func _clamped(p: Vector2) -> Vector2:
	if not bounds.has_area():
		return p
	var margin: float = tuning.edge_margin if tuning != null else 0.0
	var r: Rect2 = bounds.grow(margin)
	return p.clamp(r.position, r.end)
