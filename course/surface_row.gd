class_name SurfaceRow
extends Resource
## One row of the surface table (course/surfaces.tres): how a surface treats the ball.
## Tuned with /balance surfaces. Lie distance is not here: it lives in golf/lies.tres with the
## other lie numbers (E2-S5). Tile cost joins this row in E4.

## Lowercase surface name, as Surface.NAMES. The table checks rows are in enum order.
@export var name: String = ""
## Roll factor from the docs/design.md surface table. Rolling friction is
## (BallParams.roll_decel + BallParams.roll_drag * speed) / roll; 0 stops the ball dead where it touches down.
@export var roll: float = 1.0
## Share of the terrain's slope the ball feels here (E1-S11, D5): it scales the slope pull
## on a rolling ball and the tilt of the ground normal at touchdown. The ball's height still
## follows the terrain. 1.0 everywhere but green, where a 40% one-step contour putts as a break.
@export var slope_scale: float = 1.0
## Terrain gradient (yd per yd) above which the slope is felt more fully (E2-S4). 0.4 is
## one step per tile. Only used where steep_scale > 0.
@export var steep_from: float = 0.0
## Share of the gradient above steep_from that is felt, on top of slope_scale (E2-S4). On
## green it makes a bank steeper than any contour roll a ball off it in seconds instead of
## trickling. 0 leaves the felt slope as slope_scale times the terrain's.
@export var steep_scale: float = 0.0
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
## Speed (yd/s) below which the grass drag fades in proportion to speed (E2-S4), so a slow
## ball running down a slope is not held to a crawl. 0 keeps the full drag at every speed.
@export var drag_full_speed: float = 0.0
## Share of the rolling friction (constant part and drag alike) kept by a ball the slope
## pulls on along its line (E6-S10, Ball.downhill_share): in full where that pull is at least
## the constant friction, so on every slope of a step per tile or more off the green; none of
## it on flat ground, straight across a slope or uphill. Below 1.0 a ball runs a long downhill
## at pace instead of at the low speed where a one-step pull meets the drag (3.6 yd/s on
## fairway), while every roll on flat ground and every climb is as before. 1.0 keeps it.
@export var downhill_friction_scale: float = 1.0
## Share of its speed, along an axis, that a ball keeps when it crosses a low point on that
## axis (a valley or pit floor, falling then rising), on top of what the crease rule leaves
## it (E6-S10, Ball.meet_ground): the thud into the far wall. Below 1.0 a swing across a
## valley floor dies in a few passes. 1.0 keeps the rigid-ground share alone.
@export var floor_keep: float = 1.0
## Speed (yd/s, along that axis) at which a ball crossing a low point keeps all of what the
## crease leaves it (E6-S10 review, Ball.floor_thud): floor_keep applies to a still ball and
## fades in proportion to speed up to this, so a fast roll through a one-tile dip runs on as
## before floor_keep. 0 takes floor_keep at every speed.
@export var floor_keep_speed: float = 0.0
## Share of the speed into the ground that comes back out as the bounce (restitution).
@export_range(0.0, 1.0) var bounce: float = 0.25
## Share of the speed along the ground lost at each touchdown.
@export_range(0.0, 1.0) var bounce_friction: float = 0.5
## Bounce direction is turned by a random angle up to this many degrees either way,
## drawn from the ball's own seeded generator.
@export var scatter_deg: float = 0.0
## Height above the ground (yards) below which a flight over this surface is blocked and
## scattered (E2-S6, D15). Read on the trees row only; 0 blocks nothing.
@export var block_height: float = 0.0
