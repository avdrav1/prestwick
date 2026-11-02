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
## A touchdown that would bounce up slower than this (yd/s) rolls instead.
@export var min_bounce_speed: float = 1.0
## Safety cap: a ball still moving after this many ticks is put at rest (60 s at 60 Hz).
@export var max_steps: int = 3600


static func load_default() -> BallParams:
	return load(DEFAULT_PATH) as BallParams
