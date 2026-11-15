class_name ShotShape
extends Resource
## One shot shape of golf/shot_shapes.tres (D74, E20-S1; docs/design.md Swing, Shot shape):
## Straight, Draw, Fade, Hook or Slice, named for a right-hander as D14's slice is. A shape
## gives a full club sidespin at launch: the ball starts off the aim line to one side and bends
## back across it to the other (ShotShapes.flight). Tuned with /balance clubs.

## Short id: "straight", "draw", "fade", "hook", "slice".
@export var id: String = "straight"
## As the swing panel shows it.
@export var title: String = "Straight"
## Which way it bends: -1 left (draw, hook; -heading), +1 right (fade, slice; +heading, D14's
## early side), 0 not at all.
@export_range(-1, 1) var side: int = 0
## The bend, yards: how far the curve carries the ball off its start line at the driver's
## carry. A club bends `bend_yd × Club.shape_scale` at its own carry (golf/clubs.tres).
@export var bend_yd: float = 0.0
## Multiplies the club's roll factor (the ground speed kept after the first touchdown): over
## 1 a draw or hook runs on, under 1 a fade or slice sits down.
@export var roll_scale: float = 1.0
## Multiplies the swing's accuracy zone (Swing.zone_half_at): a shape is harder to time.
@export var zone_scale: float = 1.0


## True when this shape bends the ball at all.
func bends() -> bool:
	return side != 0 and bend_yd > 0.0
