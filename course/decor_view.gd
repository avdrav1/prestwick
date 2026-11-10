class_name DecorView
extends Node2D
## The course's decor (E5-S3, art/specs/decor.md): each bench, flag and sign its sheet frame,
## its anchor on the drawn ground at its tile's centre (TerrainMesh.ground_at), Y-sorted with
## the terrain, trees, markers and guests at Iso.object_sort_key of its tile. A reader only;
## CourseView owns one and redraws it when the decor or the ground under it changes.

const PATH: String = "res://art/sprites/decor.tres"

var sheet: TileSheet
var _course: CourseData


## One placed piece.
class Piece:
	extends Node2D
	var sheet: TileSheet
	var region: Rect2
	var foot: Vector2

	func _draw() -> void:
		draw_texture_rect_region(sheet.texture, Rect2(foot - Vector2(sheet.anchor), region.size), region)


func _init() -> void:
	name = "Decor"
	y_sort_enabled = true
	sheet = load(PATH) as TileSheet


## Draws every piece of `c`'s decor (none when null).
func show_course(c: CourseData) -> void:
	_course = c
	refresh()


## Draws the decor again as the course has it now.
func refresh() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	if _course == null:
		return
	for cell: Vector2i in _course.decor_cells():
		var p := Piece.new()
		p.sheet = sheet
		p.region = Rect2(sheet.region(_course.decor_at(cell.x, cell.y)))
		p.position = Vector2(0.0, Iso.object_sort_key(Vector2(cell), _course.get_height(cell.x, cell.y)))
		p.foot = Iso.tile_to_screen(Vector2(cell), TerrainMesh.ground_at(_course, Vector2(cell))) - p.position
		add_child(p)


## The pieces drawn now (tests).
func pieces() -> Array[Node]:
	return get_children()
