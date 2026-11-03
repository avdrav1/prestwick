class_name CameraTuning
extends Resource
## Designer-tuned camera numbers. Loaded from res://scenes/camera_tuning.tres.

const PATH: String = "res://scenes/camera_tuning.tres"

## Keyboard pan speed in screen pixels per second, the same at every zoom.
@export var pan_speed: float = 600.0
## Zoom steps, smallest first. 1.0 is one texel per pixel.
@export var zoom_levels: PackedFloat32Array = PackedFloat32Array([0.5, 1.0, 2.0])
## Index into zoom_levels at start.
@export var start_zoom_index: int = 1
## How far past the course edge, in screen pixels at 1x, the camera center may go.
@export var edge_margin: float = 128.0
## Play (E2-S8): how quickly the camera eases onto the ball it centres on, a time constant in
## seconds (about 63% of the way in this time, 95% in three). 0 jumps at once.
@export var centre_time: float = 0.15
## Play, aiming at rest (E2-S8 review): the camera frames the ball and the aim marker
## together, each at least this many screen pixels inside the screen edge.
@export var aim_frame_margin: float = 64.0


static func load_default() -> CameraTuning:
	return load(PATH) as CameraTuning
