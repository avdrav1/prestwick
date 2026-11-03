class_name DebugShot
extends Resource
## The fixed debug shot fired by the Play-mode button (E1-S7), beside the swing (E2-S7)
## until E2-S8 moves it behind a debug key. Stored in golf/debug_shot.tres; listed in
## docs/design.md (Ball).
## Defaults suit courses/heights_20x20.json, the course main loads today.

const DEFAULT_PATH := "res://golf/debug_shot.tres"

## Tile the ball is struck from; it sits on the ground at that tile's centre.
@export var start_tile: Vector2i = Vector2i(15, 4)
## Launch speed, yd/s.
@export var speed: float = 20.0
## Launch angle above the ground, degrees.
@export var launch_deg: float = 30.0
## Direction on the ground, degrees from +x towards +y. 180 heads along -x.
@export var heading_deg: float = 180.0
## Seed for the ball's own generator (bounce scatter).
@export var rng_seed: int = 1


static func load_default() -> DebugShot:
	return load(DEFAULT_PATH) as DebugShot


## Launch point in yards: the start tile's centre, on the ground.
func start_position(field: HeightField) -> Vector3:
	var c := field.tile_center(start_tile)
	return Vector3(c.x, c.y, field.height_at(c.x, c.y))


## Launch velocity in yd/s.
func velocity() -> Vector3:
	return Ball.launch_velocity(speed, launch_deg, heading_deg)
