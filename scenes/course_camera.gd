class_name CourseCamera
extends Camera2D
## The course camera: pan with WASD or a middle-mouse drag, zoom in steps (0.5x, 1x, 2x by
## default) with the wheel or +/-. Numbers come from CameraTuning (scenes/camera_tuning.tres).
## The center is kept inside `bounds` grown by the edge margin, so the course never gets lost.

const PAN_LEFT: StringName = &"pan_left"
const PAN_RIGHT: StringName = &"pan_right"
const PAN_UP: StringName = &"pan_up"
const PAN_DOWN: StringName = &"pan_down"
const ZOOM_IN: StringName = &"zoom_in"
const ZOOM_OUT: StringName = &"zoom_out"

@export var tuning: CameraTuning

## Course rectangle in world space. Empty means no clamp.
var bounds: Rect2 = Rect2():
	set(value):
		bounds = value
		position = _clamped(position)

var zoom_index: int:
	get:
		return _zoom_index

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
	if event.is_action_pressed(ZOOM_IN):
		step_zoom(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ZOOM_OUT):
		step_zoom(-1)
		get_viewport().set_input_as_handled()


## Moves the view by `screen_delta` screen pixels, whatever the zoom.
func pan(screen_delta: Vector2) -> void:
	position = _clamped(position + screen_delta / zoom.x)


## Moves the zoom one step in (+1) or out (-1), stopping at the ends.
func step_zoom(direction: int) -> void:
	set_zoom_index(_zoom_index + signi(direction))


func set_zoom_index(index: int) -> void:
	_zoom_index = clampi(index, 0, tuning.zoom_levels.size() - 1)
	var z: float = tuning.zoom_levels[_zoom_index]
	zoom = Vector2(z, z)


## Centers on `rect` and clamps to it from now on.
func frame(rect: Rect2) -> void:
	bounds = rect
	position = _clamped(rect.get_center())


func _clamped(p: Vector2) -> Vector2:
	if not bounds.has_area():
		return p
	var margin: float = tuning.edge_margin if tuning != null else 0.0
	var r: Rect2 = bounds.grow(margin)
	return p.clamp(r.position, r.end)
