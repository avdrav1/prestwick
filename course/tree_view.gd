class_name TreeView
extends Node2D
## The trees standing on every trees tile (E5-S3, art/specs/trees.md): one of the sheet's three
## crowns per tile, picked by a hash of the cell so a course looks the same on every load, its
## foot on the drawn ground at the tile's centre (TerrainMesh.ground_at, D50). A tree is 80 px
## tall at 1x, the trees row's block_height (10 yd, 5 steps), so the player sees the obstacle at
## the height it blocks a flight. A reader only; CourseView owns one.
##
## Sorting: a Y-sorted child of CourseView. The trees of one depth row (i + j) at one whole
## ground height share a Row node at Iso.object_sort_key of that row and height, so they sort
## with the terrain, markers, the clubhouse and guests like any object on their tiles: a guest
## behind a tree (a smaller row) is hidden by its crown, one in front draws over its trunk.
## Trees in one row stand 64 px apart, a crown's width, so trees and guests in one row never
## overlap and the order inside a row does not matter.
##
## Trees on land not owned take BuilderTuning.unowned_tint, as the ground under them does.

const PATH: String = "res://art/sprites/trees.tres"

var sheet: TileSheet
var unowned_tint: Color = Color.WHITE
var _course: CourseData
## depth row -> Array of Row nodes.
var _rows: Dictionary = {}


## The trees of one depth row at one ground height: [frame region, foot point local to it,
## modulate] each.
class Row:
	extends Node2D
	var sheet: TileSheet
	var trees: Array = []

	func _draw() -> void:
		var anchor := Vector2(sheet.anchor)
		for t: Array in trees:
			var region: Rect2 = t[0]
			draw_texture_rect_region(sheet.texture, Rect2((t[1] as Vector2) - anchor, region.size), region, t[2])


func _init() -> void:
	name = "Trees"
	y_sort_enabled = true
	sheet = load(PATH) as TileSheet
	unowned_tint = BuilderTuning.load_default().unowned_tint


## The sheet frame tile `cell` draws: a fixed hash of the cell.
static func variant(cell: Vector2i, count: int) -> int:
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663)
	return posmod(h, count)


## Draws every tree of `c` (or none when null).
func show_course(c: CourseData) -> void:
	_course = c
	for r: int in _rows.keys():
		_clear_row(r)
	_rows.clear()
	if c == null:
		return
	for r: int in c.width + c.height - 1:
		_build_row(r)


## Redraws the trees a batch of edited tiles can move: their rows and the rows beside them
## (a tile's drawn ground reads the heights round it).
func refresh_cells(cells: Array[Vector2i]) -> void:
	if _course == null:
		return
	var rows := {}
	for cell: Vector2i in cells:
		for d: int in range(-2, 3):
			rows[cell.x + cell.y + d] = true
	for r: int in rows:
		if r >= 0 and r < _course.width + _course.height - 1:
			_build_row(r)


## Redraws the trees in `rect` (a bought or sold parcel: their tint).
func refresh_rect(rect: Rect2i) -> void:
	if _course == null:
		return
	for r: int in range(rect.position.x + rect.position.y, rect.end.x + rect.end.y - 1):
		if r >= 0 and r < _course.width + _course.height - 1:
			_build_row(r)


## How many trees stand on the course now (tests).
func tree_count() -> int:
	var n: int = 0
	for nodes: Array in _rows.values():
		for row: Row in nodes:
			n += row.trees.size()
	return n


## The Row node drawing the tree on `cell`, or null (tests).
func row_of(cell: Vector2i) -> Row:
	var r: int = cell.x + cell.y
	if not _rows.has(r) or _course == null:
		return null
	var key: float = Iso.object_sort_key(Vector2(cell), _course.get_height(cell.x, cell.y))
	for row: Row in _rows[r]:
		if is_equal_approx(row.position.y, key):
			return row
	return null


func _clear_row(r: int) -> void:
	if not _rows.has(r):
		return
	for row: Row in _rows[r]:
		remove_child(row)
		row.free()
	_rows.erase(r)


func _build_row(r: int) -> void:
	_clear_row(r)
	var by_height := {}
	for x: int in range(maxi(0, r - _course.height + 1), mini(r, _course.width - 1) + 1):
		var y: int = r - x
		if _course.get_surface(x, y) != Surface.Type.TREES:
			continue
		var cell := Vector2i(x, y)
		var h: int = _course.get_height(x, y)
		if not by_height.has(h):
			var row := Row.new()
			row.sheet = sheet
			row.position = Vector2(0.0, Iso.object_sort_key(Vector2(cell), h))
			by_height[h] = row
		var node: Row = by_height[h]
		var foot: Vector2 = Iso.tile_to_screen(Vector2(cell), TerrainMesh.ground_at(_course, Vector2(cell))) - node.position
		var tint: Color = Color.WHITE if _course.is_owned(x, y) else unowned_tint
		node.trees.append([Rect2(sheet.region(variant(cell, sheet.frame_count()))), foot, tint])
	if by_height.is_empty():
		return
	var nodes: Array = []
	for h: int in by_height:
		var node: Row = by_height[h]
		add_child(node)
		nodes.append(node)
	_rows[r] = nodes
