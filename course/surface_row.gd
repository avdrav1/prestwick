class_name SurfaceRow
extends Resource
## One row of the surface table (course/surfaces.tres): how a surface treats the ball.
## Tuned with /balance surfaces. Lie distance and tile cost join this row in E2-S5 and E4.

## Lowercase surface name, as Surface.NAMES. The table checks rows are in enum order.
@export var name: String = ""
## Roll factor from the docs/design.md surface table. Rolling friction is
## (BallParams.roll_decel + BallParams.roll_drag * speed) / roll; 0 stops the ball dead where it touches down.
@export var roll: float = 1.0
## Share of the terrain's slope the ball feels here (E1-S11, D5): it scales the slope pull
## on a rolling ball and the tilt of the ground normal at touchdown. The ball's height still
## follows the terrain. 1.0 everywhere but green, where a 40% one-step contour putts as a break.
@export var slope_scale: float = 1.0
## Share of the constant friction (BallParams.roll_decel / roll) that holds a still ball
## here. It rises linearly back to the full constant friction at decel_ramp_speed, so fast
## balls roll as before. Off the green, keep the one-step pull, scaled by slope_scale, above
## it, or a still ball never starts down a slope. On green it is the gentle-slope hold (D7):
## above the one-step pull, so a ball rests on a one-step contour, and below the two-steps-
## per-tile pull, so steeper greens still roll (GUT tests guard both). 1.0 leaves it as is.
@export var rest_decel_scale: float = 1.0
## Speed (yd/s) at which the constant friction is back to full, when rest_decel_scale < 1.
@export var decel_ramp_speed: float = 1.0
## Multiplies the grass drag (BallParams.roll_drag / roll) here. On green it wins back the
## distance the lighter constant friction gives slow putts. 1.0 leaves the drag as it is.
@export var drag_scale: float = 1.0
## Share of the speed into the ground that comes back out as the bounce (restitution).
@export_range(0.0, 1.0) var bounce: float = 0.25
## Share of the speed along the ground lost at each touchdown.
@export_range(0.0, 1.0) var bounce_friction: float = 0.5
## Bounce direction is turned by a random angle up to this many degrees either way,
## drawn from the ball's own seeded generator.
@export var scatter_deg: float = 0.0
