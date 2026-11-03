class_name BallParams
extends Resource
## Tunable numbers for golf/ball.gd, stored in golf/ball_params.tres. Units are yards
## and seconds. Starting values from E1-S6, listed in docs/design.md (Ball); tune with /balance.

const DEFAULT_PATH := "res://golf/ball_params.tres"

## Downward acceleration, yd/s^2. Earth is about 10.7.
@export var gravity: float = 10.7
## Ground size of one tile. docs/design.md: 5 yards per tile.
@export var yards_per_tile: float = 5.0
## Height of one terrain step. 2 yards matches the 16 px riser on a 64x32 tile.
@export var yards_per_step: float = 2.0
## Constant rolling deceleration on a roll factor 1.0 surface, yd/s^2. This is also what
## holds a resting ball on a slope, so keep it well under gravity / 2 or no slope moves it.
@export var roll_decel: float = 1.5
## Extra rolling deceleration per yd/s of speed on a roll factor 1.0 surface (grass drag),
## 1/s. Stops fast balls quickly while slow ones still feel the slope.
@export var roll_drag: float = 0.6
## Below this speed (yd/s) a rolling ball stops, unless the slope pulls harder than roll_decel.
@export var rest_speed: float = 0.1
## Below this speed (yd/s) a rolling ball stops along an axis where it is about to cross a
## low point (a pit's centre or a gully's floor line), so it settles instead of rocking (E1-S13).
@export var low_point_speed: float = 0.25
## A touchdown that would bounce up slower than this (yd/s) rolls instead.
@export var min_bounce_speed: float = 1.0
## Safety cap: a ball still moving after this many ticks is put at rest (60 s at 60 Hz).
@export var max_steps: int = 3600

@export_group("Cup and hazards")
## The cup captures a ball whose centre is this close to the cup's centre (yards), at the
## end of a rolling tick (D15, E2-S6). Larger than a real cup (0.06 yd) so a putt can be
## aimed at a 5 yd tile with the swing's aim step.
@export var cup_radius: float = 0.25
## The fastest ground speed (yd/s) the cup still captures. Faster balls roll over it.
@export var cup_capture_speed: float = 2.0
## E2-S13: when no tile on the map may take a placed ball and the stroke's start is within
## cup_radius of the cup, the ball is placed this far (yards) from the cup's centre on the
## cup's own tile, toward the start. Keep it over cup_radius and under half a tile (2.5 yd).
@export var cup_clear_drop_yd: float = 2.4
## Tree scatter distance from the blocked point, yards (D15: 1 to 2 tiles).
@export var tree_scatter_min_yd: float = 5.0
@export var tree_scatter_max_yd: float = 10.0
## Tree scatter direction: within this many degrees either way of the reversed heading.
@export var tree_scatter_cone_deg: float = 90.0
## Tree scatter draws before falling back to the nearest open tile centre (D15: 8).
@export var tree_scatter_draws: int = 8


static func load_default() -> BallParams:
	return load(DEFAULT_PATH) as BallParams
