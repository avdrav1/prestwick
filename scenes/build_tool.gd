class_name BuildTool
extends Node2D
## The Build-mode terrain tool: turns the mouse into CourseBuilder edits and outlines the brush
## under the cursor. Active only in Build mode (Main toggles `active`). It never writes the
## course itself; every edit goes through the builder.
##
## Left click applies the tool at the tile under the cursor (TilePicker, so raised ground and
## tiles half behind a hill pick right). Dragging keeps applying it as one undo step, to every
## tile on the grid line between successive cursor tiles (fast mouse motion skips tiles), and
## picks against the ground as it was when the stroke began (so a Lower drag does not creep
## onto the tile behind the one it just dug).
## ui_undo (Ctrl+Z) undoes. Sits at the same origin as the CourseView, so local points are
## course screen space.

enum Tool { PAINT, RAISE, LOWER }

## Emitted when the tool, surface or brush changes, so the palette can follow.
signal settings_changed

const UNDO_ACTION: StringName = &"ui_undo"

## Brush outline colors (art/palette.gpl `ink` and `sand_light` would be the final pick).
@export var outline_color: Color = Color(1.0, 0.97, 0.8, 0.95)
@export var fill_color: Color = Color(1.0, 0.97, 0.8, 0.18)

var builder: CourseBuilder
var tool: Tool = Tool.PAINT
var surface: Surface.Type = Surface.Type.FAIRWAY
var brush_size: int = 1:
	set(value):
		brush_size = maxi(value, 1)
		queue_redraw()
		settings_changed.emit()
var active: bool = true:
	set(value):
		active = value
		if not active:
			release()
			_hover = TilePicker.NONE
		queue_redraw()
## Tile under the cursor, or TilePicker.NONE.
var hover: Vector2i:
	get:
		return _hover

var _hover: Vector2i = TilePicker.NONE
var _dragging: bool = false
var _last_cell: Vector2i = TilePicker.NONE


func _ready() -> void:
	z_index = 1  # over the course layers


func select_surface(s: Surface.Type) -> void:
	surface = s
	tool = Tool.PAINT
	settings_changed.emit()


func select_tool(t: Tool) -> void:
	tool = t
	settings_changed.emit()


func undo() -> bool:
	if builder == null or not active:
		return false
	_dragging = false
	return builder.undo()


## Mouse moved to `local` (course screen space) with no button held.
func hover_at(local: Vector2) -> void:
	var cell: Vector2i = _pick(local)
	if cell != _hover:
		_hover = cell
		queue_redraw()


## Left button went down at `local`: start a stroke and apply the tool there.
func press_at(local: Vector2) -> void:
	if builder == null or not active:
		return
	hover_at(local)
	_dragging = true
	builder.begin_stroke()
	_last_cell = TilePicker.NONE
	_apply(_hover)


## Mouse moved to `local` with the left button held: apply along the drag.
func drag_to(local: Vector2) -> void:
	hover_at(local)
	if not _dragging or not active:
		return
	if _hover == TilePicker.NONE:
		_last_cell = TilePicker.NONE  # left the map: do not join across the gap
		return
	if _last_cell == TilePicker.NONE:
		_apply(_hover)
		return
	var from: Vector2i = _last_cell
	for cell: Vector2i in grid_line(from, _hover):
		if cell != from:
			_apply(cell)


## Tiles on the 8-connected grid line from `a` to `b`, both included (Bresenham).
static func grid_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var d := Vector2i(absi(b.x - a.x), -absi(b.y - a.y))
	var s := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var err: int = d.x + d.y
	var p := a
	while true:
		cells.append(p)
		if p == b:
			break
		var e2: int = 2 * err
		if e2 >= d.y:
			err += d.y
			p.x += s.x
		if e2 <= d.x:
			err += d.x
			p.y += s.y
	return cells


## Left button released: close the stroke (one undo step).
func release() -> void:
	_dragging = false
	_last_cell = TilePicker.NONE
	if builder != null:
		builder.end_stroke()


func _unhandled_input(event: InputEvent) -> void:
	if not active or builder == null:
		return
	if event.is_action_pressed(UNDO_ACTION):
		undo()
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = _to_local(mb.position)
		if mb.pressed:
			press_at(local)
		else:
			release()
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var local: Vector2 = _to_local(motion.position)
		if _dragging and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			drag_to(local)
		else:
			if _dragging:
				release()
			hover_at(local)


func _draw() -> void:
	if not active or builder == null or _hover == TilePicker.NONE:
		return
	var c: CourseData = builder.course
	for cell: Vector2i in builder.brush_cells(_hover, brush_size):
		var center: Vector2 = Iso.tile_to_screen(Vector2(cell), c.get_height(cell.x, cell.y))
		var pts := PackedVector2Array([
			center + Vector2(0, -Iso.HALF_H), center + Vector2(Iso.HALF_W, 0),
			center + Vector2(0, Iso.HALF_H), center + Vector2(-Iso.HALF_W, 0),
		])
		draw_colored_polygon(pts, fill_color)
		pts.append(pts[0])
		draw_polyline(pts, outline_color, 1.0)


func _apply(cell: Vector2i) -> void:
	if cell == TilePicker.NONE or cell == _last_cell:
		return
	_last_cell = cell
	match tool:
		Tool.PAINT:
			builder.paint(cell, surface, brush_size)
		Tool.RAISE:
			builder.raise(cell, brush_size)
		Tool.LOWER:
			builder.lower(cell, brush_size)
	queue_redraw()


func _pick(local: Vector2) -> Vector2i:
	if builder == null:
		return TilePicker.NONE
	# Inside a stroke, pick against the ground as the stroke found it.
	var frozen: Dictionary = builder.stroke_start_heights() if _dragging else {}
	return TilePicker.pick(builder.course, local, frozen)


## Viewport (event) position to this node's local space, through the camera.
func _to_local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos
