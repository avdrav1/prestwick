class_name Iso
extends RefCounted
## The one isometric projection every system shares (renderer, builder picking, ball sprite,
## guests). 2:1 diamond, 64x32 tile footprint, 16 px per height step (CLAUDE.md Grid).
##
## Tile coordinates are fractional: integer (i, j) is the CENTER of tile (i, j), so the tile
## covers [i - 0.5, i + 0.5) x [j - 0.5, j + 0.5). Height is in steps (0 to 7 for terrain;
## fractional for a ball in the air). Screen is the course's local 2D space, before camera.
##
##   x = (i - j) * 32
##   y = (i + j) * 16 - h * 16
##
## These are grid constants fixed by the art spec (art/specs/surfaces.md), not tunables.

const TILE_W: int = 64
const TILE_H: int = 32
const HALF_W: float = TILE_W / 2.0
const HALF_H: float = TILE_H / 2.0
## Screen pixels per height step. Equals TileArt.riser_px.
const STEP_PX: int = 16


## Screen point of tile position `tile` standing at `height` steps.
static func tile_to_screen(tile: Vector2, height: float = 0.0) -> Vector2:
	return Vector2((tile.x - tile.y) * HALF_W, (tile.x + tile.y) * HALF_H - height * STEP_PX)


## Screen point of a 3D point: x, y in tiles, z in height steps.
static func point_to_screen(p: Vector3) -> Vector2:
	return tile_to_screen(Vector2(p.x, p.y), p.z)


## Inverse of tile_to_screen: the fractional tile position at `height` that projects to `screen`.
## A screen point is ambiguous without a height; picking on raised ground (E1-S5) tries heights.
static func screen_to_tile(screen: Vector2, height: float = 0.0) -> Vector2:
	var a: float = screen.x / HALF_W
	var b: float = (screen.y + height * STEP_PX) / HALF_H
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


## The integer tile whose diamond, raised to `height`, contains `screen`.
static func screen_to_cell(screen: Vector2, height: float = 0.0) -> Vector2i:
	var t: Vector2 = screen_to_tile(screen, height)
	return Vector2i(floori(t.x + 0.5), floori(t.y + 0.5))


## Painter's order. Godot Y-sorts every child of CourseView by `position.y + y_sort_origin`,
## so all sort keys below are in that unit: screen pixels at height 0. A tile's depth row is
## (i + j) * HALF_H. Inside one row, a per-layer bias orders the tile's pieces bottom up:
## riser step k gets 2k, the top at height h gets 2h + 1, and an object resting on height h
## gets 2h + 1.5 (after that top, before the next riser step). The largest bias (15.5, an
## object on height 7) stays below one row (HALF_H = 16), so a nearer row always draws later.
## Equal-depth tiles never overlap, so ties across tiles in one row do not matter.
const BIAS_PER_STEP: int = 2


## Sort key of the depth row holding `cell`, before any layer bias.
static func depth_key(cell: Vector2i) -> int:
	return roundi((cell.x + cell.y) * HALF_H)


## Sort key of riser step `k` (the wall between height k and k + 1) of `cell`.
static func riser_sort_key(cell: Vector2i, k: int) -> int:
	return depth_key(cell) + BIAS_PER_STEP * k


## Sort key of the surface top of `cell` at height `h`.
static func top_sort_key(cell: Vector2i, h: int) -> int:
	return depth_key(cell) + BIAS_PER_STEP * h + 1


## Sort key of an object (ball, guest, flag) at fractional tile position `tile` whose ground
## is height `ground` steps: it draws over that tile's top and under anything nearer. Use the
## ground under the object, not its height in the air. The key is not the object's screen y;
## a sprite gets it by sitting under a Y-sorted Node2D placed at y = key and offsetting itself
## back to Iso.tile_to_screen.
static func object_sort_key(tile: Vector2, ground: float) -> float:
	var cell := Vector2i(floori(tile.x + 0.5), floori(tile.y + 0.5))
	return depth_key(cell) + BIAS_PER_STEP * ground + 1.5
