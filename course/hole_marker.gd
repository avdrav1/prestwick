class_name HoleMarker
extends Node2D
## A hole's tee marker or pin on the course view (E2-S2), drawn in code until the final art
## (E5-S1, E5-S3). A reader only. CourseView owns one per placed tee and cup.
##
## It stands on the top of its tile: the shape is drawn at Iso.tile_to_screen(cell, h), h the
## tile's whole height, and the node sits at y = Iso.object_sort_key(cell, h), so it Y-sorts
## with the terrain like the ball: over its own tile's top, under anything nearer the camera.
##
## Shape and colour both say what it is (colorblind rule): the tee marker is two
## square blocks either side of the tile centre, the pin a dark cup with a pole and a pennant.
## Colours are art/palette.gpl entries.

enum Kind { TEE, PIN }

## Tee blocks: sun_yellow on ink. Pin: flag_red pennant, chalk pole, ink cup and outlines.
@export var tee_color: Color = Color8(240, 200, 58)
@export var flag_color: Color = Color8(216, 58, 58)
@export var pole_color: Color = Color8(240, 236, 224)
@export var ink_color: Color = Color8(26, 28, 34)
## Tee blocks: half-size of each square block and its distance from the tile centre, screen px.
@export var tee_block_radius: float = 4.0
@export var tee_block_offset: float = 14.0
## Pin: cup half-width, pole height, pennant width and height, screen px at 1x.
@export var cup_radius: float = 4.0
@export var pole_height: float = 30.0
@export var flag_width: float = 13.0
@export var flag_height: float = 8.0

var kind: Kind = Kind.TEE
var hole_number: int = 0
var cell: Vector2i = Vector2i.ZERO
## The whole height of the tile it stands on.
var ground: int = 0


func _init(p_kind: Kind = Kind.TEE, p_hole_number: int = 0, p_cell: Vector2i = Vector2i.ZERO) -> void:
	kind = p_kind
	hole_number = p_hole_number
	cell = p_cell
	name = "%s%d" % ["Tee" if kind == Kind.TEE else "Pin", hole_number]


## Stands the marker on its tile's top in `course`.
func place(course: CourseData) -> void:
	ground = course.get_height(cell.x, cell.y)
	var at: Vector2 = draw_point()
	position = Vector2(at.x, Iso.object_sort_key(Vector2(cell), ground))
	queue_redraw()


## Where its shape is drawn, in the CourseView's space: its tile's centre on its top.
func draw_point() -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), ground)


## Its Y-sort key, in the CourseView's space (Iso.object_sort_key on its tile).
func sort_key() -> float:
	return position.y


func _draw() -> void:
	var at: Vector2 = draw_point() - position
	if kind == Kind.TEE:
		for side: float in [-1.0, 1.0]:
			var c: Vector2 = at + Vector2(side * tee_block_offset, -tee_block_radius)
			var r := Vector2(tee_block_radius, tee_block_radius)
			draw_rect(Rect2(c - r - Vector2.ONE, (r + Vector2.ONE) * 2.0), ink_color)
			draw_rect(Rect2(c - r, r * 2.0), tee_color)
		return
	draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, cup_radius, ink_color)
	draw_set_transform(Vector2.ZERO)
	var top: Vector2 = at + Vector2(0.0, -pole_height)
	draw_line(at, top, ink_color, 4.0)
	draw_line(at, top, pole_color, 2.0)
	var flag := PackedVector2Array([top, top + Vector2(flag_width, flag_height * 0.5), top + Vector2(0.0, flag_height)])
	draw_colored_polygon(flag, flag_color)
	flag.append(top)
	draw_polyline(flag, ink_color, 1.0)

