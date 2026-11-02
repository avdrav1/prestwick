class_name CourseBuilder
extends RefCounted
## The terrain builder: paint surfaces, raise and lower ground, undo. With course/save.gd it is
## one of the two writers of CourseData (CLAUDE.md Architecture); the build tool, HUD and
## anything else go through it.
##
## A brush of size n (1, 3 or 5, from BuilderTuning) is the n x n square of tiles centered on
## the cursor tile, clipped to the map. Heights clamp at 0 and CourseData.MAX_HEIGHT.
##
## Every edit that changes at least one tile pushes one undo step holding the old height and
## surface of each tile it wrote. An edit that changes nothing pushes nothing. Between
## begin_stroke() and end_stroke() (one mouse drag) all edits share one undo step, and raise
## or lower moves each tile at most once, so a drag lifts ground one step, not one per frame.

## Emitted after tiles are written (by an edit or an undo), with every tile that changed.
signal tiles_changed(cells: Array[Vector2i])

## The 8 surfaces a player paints, in palette order (docs/design.md surface table). Oob is a
## surface in the course format but not on the palette.
const PALETTE: Array[Surface.Type] = [
	Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.GREEN, Surface.Type.TEE,
	Surface.Type.BUNKER, Surface.Type.WATER, Surface.Type.TREES, Surface.Type.CART_PATH,
]

var course: CourseData:
	get:
		return _course
var tuning: BuilderTuning:
	get:
		return _tuning

var _course: CourseData
var _tuning: BuilderTuning
## Undo steps, oldest first. Each maps a tile to its packed (height << 4 | surface) before the step.
var _undo: Array[Dictionary] = []
## The open stroke's step, or null when no stroke is open.
var _stroke: Variant = null
## Tiles the open stroke has already raised or lowered.
var _stroke_lifted: Dictionary = {}


func _init(p_course: CourseData, p_tuning: BuilderTuning = null) -> void:
	_course = p_course
	_tuning = p_tuning if p_tuning != null else BuilderTuning.load_default()


## In-bounds tiles under a brush of `size` centered on `center`.
func brush_cells(center: Vector2i, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var lo: int = -(maxi(size, 1) - 1) / 2
	var hi: int = lo + maxi(size, 1) - 1
	for dy: int in range(lo, hi + 1):
		for dx: int in range(lo, hi + 1):
			var c := center + Vector2i(dx, dy)
			if _course.in_bounds(c.x, c.y):
				cells.append(c)
	return cells


## Paints `surface` under the brush. Returns true when any tile changed.
func paint(center: Vector2i, surface: Surface.Type, size: int) -> bool:
	assert(Surface.is_valid(surface), "surface out of range")
	var step := {}
	for c: Vector2i in brush_cells(center, size):
		if _course.get_surface(c.x, c.y) != surface:
			_write(step, c, _course.get_height(c.x, c.y), surface)
	return _commit(step)


## Raises the ground under the brush one step, clamped at MAX_HEIGHT. True when any tile changed.
func raise(center: Vector2i, size: int) -> bool:
	return _lift(center, size, 1)


## Lowers the ground under the brush one step, clamped at 0. True when any tile changed.
func lower(center: Vector2i, size: int) -> bool:
	return _lift(center, size, -1)


## Starts grouping edits into one undo step (a mouse drag). Ends any open stroke first.
func begin_stroke() -> void:
	end_stroke()
	_stroke = {}
	_stroke_lifted = {}


## Closes the open stroke and pushes its undo step if it changed anything.
func end_stroke() -> void:
	if _stroke == null:
		return
	var step: Dictionary = _stroke
	_stroke = null
	_stroke_lifted = {}
	if not step.is_empty():
		_push(step)


## Heights the open stroke has changed, as they were when it began (tile -> height). Empty when
## no stroke is open. The build tool picks against these so a drag does not chase ground it
## just moved.
func stroke_start_heights() -> Dictionary:
	var out := {}
	if _stroke == null:
		return out
	var open: Dictionary = _stroke
	for c: Vector2i in open:
		var packed: int = open[c]
		out[c] = packed >> 4
	return out


func can_undo() -> bool:
	return not _undo.is_empty() or (_stroke != null and not (_stroke as Dictionary).is_empty())


## Undo steps available (an open stroke counts once it changes something).
func undo_depth() -> int:
	return _undo.size() + (1 if _stroke != null and not (_stroke as Dictionary).is_empty() else 0)


## Reverts the latest step (closing an open stroke first). Returns false when there is none.
func undo() -> bool:
	end_stroke()
	if _undo.is_empty():
		return false
	var step: Dictionary = _undo.pop_back()
	var cells: Array[Vector2i] = []
	for c: Vector2i in step:
		var packed: int = step[c]
		_course.set_tile(c.x, c.y, packed >> 4, (packed & 0x0F) as Surface.Type)
		cells.append(c)
	tiles_changed.emit(cells)
	return true


func _lift(center: Vector2i, size: int, delta: int) -> bool:
	var step := {}
	for c: Vector2i in brush_cells(center, size):
		if _stroke != null and _stroke_lifted.has(c):
			continue
		var h: int = _course.get_height(c.x, c.y)
		var to: int = clampi(h + delta, 0, CourseData.MAX_HEIGHT)
		if to != h:
			_write(step, c, to, _course.get_surface(c.x, c.y))
			if _stroke != null:
				_stroke_lifted[c] = true
	return _commit(step)


## Records the tile's old value in `step` (first write wins) and writes the new one.
func _write(step: Dictionary, c: Vector2i, h: int, s: Surface.Type) -> void:
	if not step.has(c):
		step[c] = (_course.get_height(c.x, c.y) << 4) | _course.get_surface(c.x, c.y)
	_course.set_tile(c.x, c.y, h, s)


## Files `step` (the tiles one edit wrote) and announces them. False when it is empty.
func _commit(step: Dictionary) -> bool:
	if step.is_empty():
		return false
	if _stroke != null:
		var open: Dictionary = _stroke
		for c: Vector2i in step:
			if not open.has(c):
				open[c] = step[c]
	else:
		_push(step)
	var cells: Array[Vector2i] = []
	cells.assign(step.keys())
	tiles_changed.emit(cells)
	return true


func _push(step: Dictionary) -> void:
	_undo.append(step)
	while _undo.size() > maxi(_tuning.undo_limit, 1):
		_undo.pop_front()
