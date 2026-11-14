class_name CameraTuning
extends Resource
## Designer-tuned camera numbers. Loaded from res://scenes/camera_tuning.tres.

const PATH: String = "res://scenes/camera_tuning.tres"

## Keyboard pan speed in screen pixels per second, the same at every zoom.
@export var pan_speed: float = 600.0
## Zoom steps, smallest first. 1.0 is one texel per pixel. 0.175x (D45, E3-S9) is sized so the
## longest hole of tests/fixtures/nine_holes.gd (hole 3, a 520 yd par 5 along a tile axis)
## frames with its tee and cup inside the view the HUD leaves free at 1280 x 720. The farthest,
## 0.1x (E18-S5, D71), shows the whole 192 x 192 map (about 1,230 x 615 px), where 0.175x
## shows about 40% of it.
@export var zoom_levels: PackedFloat32Array = PackedFloat32Array([0.1, 0.175, 0.5, 1.0, 2.0])
## Index into zoom_levels at start (1x).
@export var start_zoom_index: int = 3
## E18-S5: the farthest zoom hole framing steps out to on its own (D45's 0.175x): a hole is
## framed where its tee and cup still read, and only the zoom keys reach the levels past it.
@export var frame_farthest_zoom: float = 0.175
## How far past the course edge, in screen pixels at 1x, the camera center may go.
@export var edge_margin: float = 128.0
## Play (E2-S8): how quickly the camera eases onto the ball it centres on, a time constant in
## seconds (about 63% of the way in this time, 95% in three). 0 jumps at once.
@export var centre_time: float = 0.15
## Play, aiming at rest (E2-S8 review): the camera frames the ball and the aim marker
## together, each at least this many screen pixels inside the screen edge.
@export var aim_frame_margin: float = 64.0
## Play, aiming at rest: the farthest zoom the aim fit steps out to on its own (D45). The
## player's zoom keys still reach every level; the fit stops here so a swing is aimed at a
## zoom where the ball and the lie read.
@export var aim_farthest_zoom: float = 0.5
## Play, aiming (E10-S2): the hold box is the free view inset by this fraction of its size on
## each side. While the ball and the aim marker are inside it the camera holds still; small
## mouse moves turn the aim, they do not pan.
@export var aim_hold_inset: float = 0.12
## Play, aiming (E10-S2): when the marker or the ball leaves the hold box the camera glides
## back, a time constant in seconds like centre_time (about 63% of the way in this time).
@export var aim_glide_time: float = 0.25
## Play, aiming (E10-S2): when the ball and the marker do not both fit the hold box (the player
## zoomed in), the camera keeps the aim line in it only this fraction of the box long, leaning
## toward the marker with room left for a small turn before it glides.
@export var aim_hold_reach: float = 0.8


static func load_default() -> CameraTuning:
	return load(PATH) as CameraTuning
