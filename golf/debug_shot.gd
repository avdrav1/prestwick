class_name DebugShot
extends Resource
## The fixed debug shot (E1-S7), fired in Play by the `debug_shot` key (F3, debug builds
## only, E2-S8). Stored in golf/debug_shot.tres; listed in docs/design.md (Ball).
## Defaults suit courses/heights_20x20.json, where design.md pins its landing and rest; on a
## course with no tee, Play also puts the swing ball on its tile.

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


## Launch point in yards: the centre of `tile` (start_tile when left at -1, -1), on the ground.
## Main passes owned land on a New course, where start_tile is unowned (E6-S21).
func start_position(field: HeightField, tile: Vector2i = Vector2i(-1, -1)) -> Vector3:
	var c := field.tile_center(start_tile if tile == Vector2i(-1, -1) else tile)
	return Vector3(c.x, c.y, field.height_at(c.x, c.y))


## Launch velocity in yd/s.
func velocity() -> Vector3:
	return Ball.launch_velocity(speed, launch_deg, heading_deg)
