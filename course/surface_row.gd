class_name SurfaceRow
extends Resource
## One row of the surface table (course/surfaces.tres): how a surface treats the ball.
## Tuned with /balance surfaces. Lie distance and tile cost join this row in E2-S5 and E4.

## Lowercase surface name, as Surface.NAMES. The table checks rows are in enum order.
@export var name: String = ""
## Roll factor from the docs/design.md surface table. Rolling friction is
## (BallParams.roll_decel + BallParams.roll_drag * speed) / roll; 0 stops the ball dead where it touches down.
@export var roll: float = 1.0
## Share of the speed into the ground that comes back out as the bounce (restitution).
@export_range(0.0, 1.0) var bounce: float = 0.25
## Share of the speed along the ground lost at each touchdown.
@export_range(0.0, 1.0) var bounce_friction: float = 0.5
## Bounce direction is turned by a random angle up to this many degrees either way,
## drawn from the ball's own seeded generator.
@export var scatter_deg: float = 0.0
