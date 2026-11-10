class_name BallArt
extends RefCounted
## The ball sprites (E5-S3, art/specs/ball.md, scripts/art_sprites.py): the player's chalk ball
## and a guest's slate_light ball with a chalk dot, each with a spin frame alternated in flight,
## so a guest's ball differs from the player's by shape and value, not only by size. ShotView and
## GuestView draw them through draw(); the shadow stays drawn in code.

const PATH: String = "res://art/sprites/ball.tres"
## Seconds each frame of the flight's spin shows.
const SPIN_S: float = 0.08

static var _sheet: TileSheet


static func sheet() -> TileSheet:
	if _sheet == null:
		_sheet = load(PATH) as TileSheet
	return _sheet


## The frame name for a ball: the guest's or the player's, spinning or not.
static func frame_name(guest: bool, spin: bool) -> StringName:
	return StringName(("guest" if guest else "player") + ("_spin" if spin else ""))


## Whether a flight `t` seconds old shows its spin frame.
static func spin_at(t: float) -> bool:
	return int(floorf(t / SPIN_S)) % 2 == 1


## Draws the ball centred on `at` on `ci`, `radius` canvas units to its outline's outer edge
## (the 8 px frame is a 4 px radius, outline included).
static func draw(ci: CanvasItem, at: Vector2, radius: float, guest: bool, spin: bool) -> void:
	var s: TileSheet = sheet()
	var region := Rect2(s.region_named(frame_name(guest, spin)))
	var size: Vector2 = region.size * (radius / (region.size.x * 0.5))
	ci.draw_texture_rect_region(s.texture, Rect2(at - size * 0.5, size), region)
