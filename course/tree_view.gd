class_name TreeView
extends Node2D
## The trees standing on every trees tile (E5-S3, art/specs/trees.md): one of the sheet's three
## crowns per tile, picked by a hash of the cell so a course looks the same on every load, its
## foot on the drawn ground at the tile's centre (TerrainMesh.ground_at, D50: there, its own
## height). A tree is 80 px tall at 1x, the trees row's block_height (10 yd, 5 steps), so the
## player sees the obstacle at the height it blocks a flight. A reader only; CourseView owns one.
##
## Sorting: a Y-sorted child of CourseView. The trees of one depth row (i + j) at one whole
## ground height share a Row node at Iso.object_sort_key of that row and height, so they sort
## with the terrain, markers, the clubhouse and guests like any object on their tiles: a guest
## behind a tree (a smaller row) is hidden by its crown, one in front draws over its trunk.
## Trees in one row stand 64 px apart, a crown's width, so trees and guests in one row never
## overlap and the order inside a row does not matter.
##
## Trees on land not owned take BuilderTuning.unowned_tint, as the ground under them does.
##
## E5-S15: edits redraw tree by tree (refresh_cells), not row by row: a drag emits a batch per
## brush step, and rebuilding every depth row within 2 of each batch's tiles cost a drag_to
## frame 20 ms with about 1,750 trees on the nine (docs/decisions/e5-s15-perf.txt).

const PATH: String = "res://art/sprites/trees.tres"
## What a tile's tree reads of it (E5-S15): its height in the low bits, this bit when trees.
const MARK_TREES: int = 8

var sheet: TileSheet
var unowned_tint: Color = Color.WHITE
var _course: CourseData
## Vector2i(depth row, ground height) -> Row.
var _rows: Dictionary = {}
## Tile -> the Row drawing its tree.
var _at: Dictionary = {}
## E5-S15: per tile (y * width + x), its height | MARK_TREES as the trees last drew it, so an
## edit that changes neither (a surface painted over a surface, no trees in or out) costs a
## compare, not a redraw.
var _marks := PackedByteArray()


## The trees of one depth row at one ground height: tile -> [frame region, foot point local to
## it, modulate].
class Row:
	extends Node2D
	var sheet: TileSheet
	## Vector2i(depth row, ground height): its key in TreeView._rows.
	var key: Vector2i
	var trees: Dictionary = {}

	func _draw() -> void:
		var anchor := Vector2(sheet.anchor)
		for t: Array in trees.values():
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
	for row: Row in _rows.values():
		remove_child(row)
		row.free()
	_rows.clear()
	_at.clear()
	_marks = PackedByteArray()
	if c == null:
		return
	_marks.resize(c.width * c.height)
	for y: int in c.height:
		for x: int in c.width:
			_marks[y * c.width + x] = _mark(x, y)
			if c.get_surface(x, y) == Surface.Type.TREES:
				_place(Vector2i(x, y))
	for row: Row in _rows.values():
		row.queue_redraw()


## Redraws the trees a batch of edited tiles can move (E5-S15: tile by tile): a tile that
## turned to or from trees, or a trees tile whose height moved. A tree's foot reads its own tile
## alone (the drawn ground at a land tile's centre is its height, _place), so a tile that changed
## neither costs a compare: a drag across a fairway redraws no tree.
func refresh_cells(cells: Array[Vector2i]) -> void:
	if _course == null:
		return
	var w: int = _course.width
	var dirty := {}
	for cell: Vector2i in cells:
		if not _course.in_bounds(cell.x, cell.y):
			continue
		var i: int = cell.y * w + cell.x
		var m: int = _mark(cell.x, cell.y)
		var was: int = _marks[i]
		if m == was:
			continue
		_marks[i] = m
		if (m | was) & MARK_TREES:
			dirty[cell] = true
	_redraw(dirty)


## Redraws the trees in `rect` (a bought or sold parcel: their tint).
func refresh_rect(rect: Rect2i) -> void:
	if _course == null:
		return
	var dirty := {}
	for y: int in range(maxi(rect.position.y, 0), mini(rect.end.y, _course.height)):
		for x: int in range(maxi(rect.position.x, 0), mini(rect.end.x, _course.width)):
			_marks[y * _course.width + x] = _mark(x, y)
			if _at.has(Vector2i(x, y)) or _course.get_surface(x, y) == Surface.Type.TREES:
				dirty[Vector2i(x, y)] = true
	_redraw(dirty)


## How many trees stand on the course now (tests).
func tree_count() -> int:
	return _at.size()


## The Row node drawing the tree on `cell`, or null (tests).
func row_of(cell: Vector2i) -> Row:
	return _at.get(cell) as Row


## What a tree reads of tile (x, y): its height, and whether it is trees.
func _mark(x: int, y: int) -> int:
	return _course.get_height(x, y) | (MARK_TREES if _course.get_surface(x, y) == Surface.Type.TREES else 0)


## Takes each tile of `dirty` (tile -> true) off its row and stands it again as the course has it.
func _redraw(dirty: Dictionary) -> void:
	if dirty.is_empty():
		return
	var touched := {}
	for cell: Vector2i in dirty:
		var old: Row = _at.get(cell) as Row
		if old != null:
			old.trees.erase(cell)
			_at.erase(cell)
			touched[old] = true
		if _course.get_surface(cell.x, cell.y) == Surface.Type.TREES:
			touched[_place(cell)] = true
	for row: Row in touched:
		if row.trees.is_empty():
			_rows.erase(row.key)
			remove_child(row)
			row.free()
		else:
			row.queue_redraw()


## Stands the tree of trees tile `cell` in the Row of its depth row and height; returns it.
func _place(cell: Vector2i) -> Row:
	var h: int = _course.get_height(cell.x, cell.y)
	var key := Vector2i(cell.x + cell.y, h)
	var row: Row = _rows.get(key) as Row
	if row == null:
		row = Row.new()
		row.sheet = sheet
		row.key = key
		row.position = Vector2(0.0, Iso.object_sort_key(Vector2(cell), h))
		_rows[key] = row
		add_child(row)
	# The drawn ground at a land tile's centre is its own height (TerrainMesh: the centre is a
	# grid vertex, at HeightField.height_at, the bilinear ground through the tile centres;
	# tests/test_sprites.gd holds it to TerrainMesh.ground_at), so no neighbour is read.
	var foot: Vector2 = Iso.tile_to_screen(Vector2(cell), float(h)) - row.position
	var tint: Color = Color.WHITE if _course.is_owned(cell.x, cell.y) else unowned_tint
	row.trees[cell] = [Rect2(sheet.region(variant(cell, sheet.frame_count()))), foot, tint]
	_at[cell] = row
	return row
