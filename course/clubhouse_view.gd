class_name ClubhouseView
extends Node2D
## The clubhouse on the course view (D60, E5-S10, art/specs/clubhouse.md): its sheet's frame for
## the course's facing, drawn over its 3x3 footprint. A reader only; CourseView owns one and
## calls show_clubhouse after the course or the clubhouse changes.
##
## It stands at the lowest whole height of its 9 tiles (so on a slope its walls sink into the
## uphill ground) and sorts with the terrain like a hole marker, at Iso.object_sort_key of the
## footprint's front tile (centre + (1, 1), the nearest the camera): every row of its footprint's
## ground draws first, and ground, markers and guests nearer the camera draw over it; a guest
## behind it is hidden by it. Hidden when the course has no clubhouse.

const PATH: String = "res://art/sprites/clubhouse.tres"

var sheet: TileSheet
## The footprint's centre and facing drawn now (CourseData.NO_CLUBHOUSE: none).
var centre: Vector2i = CourseData.NO_CLUBHOUSE
var facing: int = 1
## The whole height it stands at.
var ground: int = 0
## Where the frame's anchor lands, in this node's local space.
var _anchor_at: Vector2 = Vector2.ZERO


func _init() -> void:
	name = "Clubhouse"
	sheet = load(PATH) as TileSheet


## Places it for `c`'s clubhouse, or hides it when `c` is null or has none.
func show_clubhouse(c: CourseData) -> void:
	if c == null or not c.has_clubhouse():
		centre = CourseData.NO_CLUBHOUSE
		visible = false
		queue_redraw()
		return
	centre = c.clubhouse
	facing = c.clubhouse_facing
	ground = CourseData.MAX_HEIGHT
	for cell: Vector2i in c.clubhouse_cells():
		ground = mini(ground, c.get_height(cell.x, cell.y))
	var front: Vector2i = centre + Vector2i(CourseData.CLUBHOUSE_REACH, CourseData.CLUBHOUSE_REACH)
	var screen: Vector2 = Iso.tile_to_screen(Vector2(centre), ground)
	position = Vector2(screen.x, Iso.object_sort_key(Vector2(front), ground))
	_anchor_at = Vector2(0.0, screen.y - position.y)
	visible = true
	queue_redraw()


## The frame drawn now: the facing's name (CourseData.FACING_NAMES).
func frame_name() -> String:
	return CourseData.FACING_NAMES[facing]


## The frame's rectangle in course screen space (for tests and the camera).
func screen_rect() -> Rect2:
	return Rect2(position + _anchor_at - Vector2(sheet.anchor), Vector2(sheet.frame_size))


func _draw() -> void:
	if centre == CourseData.NO_CLUBHOUSE or sheet == null:
		return
	var region := Rect2(sheet.region_named(frame_name()))
	draw_texture_rect_region(sheet.texture, Rect2(_anchor_at - Vector2(sheet.anchor), region.size), region)
