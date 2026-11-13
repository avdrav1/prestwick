class_name BridgeView
extends Node2D
## The course's footbridges (E14-S1, D69, art/specs/bridge.md): each bridge tile one frame of
## art/sprites/bridge.png, its anchor on the drawn water surface at the tile's centre
## (TerrainMesh.ground_at), Y-sorted with the terrain, trees, markers and guests just before
## Iso.object_sort_key of its tile, so a guest on the bridge draws over its deck. A reader only;
## CourseView owns one and redraws it when the bridges or the water under them change.
##
## The frame (frame_for): the deck runs along x when its x neighbours (bridge or dry land) are
## at least as many as its y neighbours, else along y, and has a rail on each side whose
## neighbour is open water (water with no bridge) or off the map.

const PATH: String = "res://art/sprites/bridge.tres"
## Under Iso.object_sort_key by this much, so a figure on the same tile draws over the deck.
const SORT_UNDER: float = 0.5
## The four sides by bit, as scripts/art_sprites.py draws them: +x, -x, +y, -y.
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var sheet: TileSheet
var _course: CourseData
var _drawn_revision: int = -1


## One drawn bridge tile.
class Piece:
	extends Node2D
	var sheet: TileSheet
	var region: Rect2
	var foot: Vector2
	var cell: Vector2i
	var frame: int

	func _draw() -> void:
		draw_texture_rect_region(sheet.texture, Rect2(foot - Vector2(sheet.anchor), region.size), region)


func _init() -> void:
	name = "Bridges"
	y_sort_enabled = true
	sheet = load(PATH) as TileSheet


## Draws every bridge of `c` (none when null).
func show_course(c: CourseData) -> void:
	_course = c
	refresh()


## Draws the bridges again when they changed since the last draw (or `force`).
func refresh(force: bool = true) -> void:
	if not force and _course != null and _course.bridge_revision == _drawn_revision:
		return
	for child: Node in get_children():
		remove_child(child)
		child.free()
	if _course == null:
		return
	_drawn_revision = _course.bridge_revision
	for cell: Vector2i in _course.bridge_cells():
		var p := Piece.new()
		p.sheet = sheet
		p.cell = cell
		p.frame = frame_for(_course, cell)
		p.region = Rect2(sheet.region(p.frame))
		var h: int = _course.get_height(cell.x, cell.y)
		p.position = Vector2(0.0, Iso.object_sort_key(Vector2(cell), h) - SORT_UNDER)
		p.foot = Iso.tile_to_screen(Vector2(cell), TerrainMesh.ground_at(_course, Vector2(cell))) - p.position
		add_child(p)


## The sheet frame of the bridge on `cell`: 0 to 15 along x, 16 to 31 along y, plus the rail bits.
static func frame_for(c: CourseData, cell: Vector2i) -> int:
	var rails: int = 0
	var links := Vector2i.ZERO
	for bit: int in SIDES.size():
		var n: Vector2i = cell + SIDES[bit]
		var open_water: bool = not c.in_bounds(n.x, n.y) \
				or (c.get_surface(n.x, n.y) == Surface.Type.WATER and not c.is_bridge(n.x, n.y))
		if open_water:
			rails |= 1 << bit
		elif bit < 2:
			links.x += 1
		else:
			links.y += 1
	return rails + (0 if links.x >= links.y else 16)


## The pieces drawn now (tests).
func pieces() -> Array[Node]:
	return get_children()
