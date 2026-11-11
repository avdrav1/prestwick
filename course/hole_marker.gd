class_name HoleMarker
extends Node2D
## A hole's tee marker or pin on the course view (E2-S2), drawn in code until the final art
## (E5-S1, E5-S3). A reader only. CourseView owns one per placed tee and cup.
##
## It stands on the ground at its tile's centre (E3-S59, D50: the drawn ground there is the
## tile's own whole height h): the shape is drawn at Iso.tile_to_screen(cell, h), the tee's two
## blocks each on the ground under it, and the node sits at y = Iso.object_sort_key(cell, h),
## so it Y-sorts with the terrain like the ball: over its own tile's row, under anything nearer
## the camera.
##
## Shape and colour both say what it is (colorblind rule): the tee marker is two
## square blocks either side of the tile centre, the pin a dark cup with a pole and a pennant.
## Colours are art/palette.gpl entries. With nine holes (E3-S2) the tee marker shows its hole
## number, chalk on an ink outline, so the map says which tee is which. Since E3-S66 it stands
## beside a block (number_gap screen px out from it, level with it), not between the blocks,
## where the ball rests on the tee and covered it at 0.175x: beside the block on the side away
## from its cup on screen (`label_side`, CourseView sets it), so the aim line and the line of
## play, which leave the tee toward the cup, do not run over it.
##
## The number is drawn by a child (`label`, E3-S40) so it can rise over the terrain on its own:
## Y-sorted with the marker, ground in front on raised land could cover it at 0.5x and nearer,
## so CourseView lifts it (`label_lifted`, z_index 1) whenever drawn ground nearer the camera
## covers any part of it (label_covered), and leaves it sorted with the terrain otherwise, so the
## player's ball on the tee still draws over it.

enum Kind { TEE, PIN }
## The hole number's ink outline, screen px.
const LABEL_OUTLINE: int = 3
## E5-S3: the marker sheet (scripts/art_sprites.py markers). Its frames differ in size, so each
## names its region and anchor here (art/specs/hole_markers.md): one row, 1 px gutter.
const SHEET_PATH: String = "res://art/sprites/hole_markers.png"
const SHEET_FRAMES: Dictionary = {
	&"tee_block": [Rect2(0, 0, 8, 8), Vector2(4, 6)],
	&"cup": [Rect2(9, 0, 12, 6), Vector2(6, 3)],
	&"pin_0": [Rect2(22, 0, 16, 36), Vector2(2, 34)],
	&"pin_1": [Rect2(39, 0, 16, 36), Vector2(2, 34)],
	&"pin_2": [Rect2(56, 0, 16, 36), Vector2(2, 34)],
}
## E7-S1: the pennant's wave, as pin frames in order: still, mid, full, mid, then round again.
const PENNANT_CYCLE: Array[int] = [0, 1, 2, 1]
## How many tiles in front label_covered looks for higher ground before casting rays: at 0.5x
## the number stands about two tiles' worth of height over its tile.
const LIFT_REACH: int = 4

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
## The tee marker's hole number: font size, screen px at every zoom (text_scale).
@export var number_font_size: int = 13
## The gap between the right-hand tee block and its hole number, screen px at every zoom
## (E3-S66: the number stands beside the blocks, clear of a ball resting on the tee).
@export var number_gap: float = 3.0

## Which block the number stands beside (E3-S66): 1 the right-hand one, -1 the left. CourseView
## sets it from its hole's cup (side_away_from).
var label_side: float = 1.0:
	set(v):
		label_side = v
		if label != null:
			label.queue_redraw()

var kind: Kind = Kind.TEE
var hole_number: int = 0
## The name its tee shows (CourseData.hole_label): the number, or "4a" and "4b" when two holes
## share it (E3-S27). Empty shows hole_number.
var hole_label: String = ""
var cell: Vector2i = Vector2i.ZERO
## The whole height of the tile it stands on: the ground's height at its centre.
var ground: int = 0
## How far the ground under each tee block (left, right) stands above the centre's, screen px
## (a block on a slope sits on it).
var block_lift: Vector2 = Vector2.ZERO
## Local units per screen pixel (1 / zoom) for the hole number, set by CourseView when the zoom
## changes, so the number keeps number_font_size screen px at 0.5x and 2x alike (E3-S2 review).
var text_scale: float = 1.0:
	set(v):
		if not is_equal_approx(v, text_scale):
			text_scale = v
			label.queue_redraw()
## The hole number, drawn over the terrain while `label_lifted` (E3-S40).
var label: Node2D
## Whether the number draws over the terrain (z_index 1 over the marker's), set by CourseView
## when ground in front covers it (label_covered).
var label_lifted: bool = false:
	set(v):
		label_lifted = v
		label.z_index = 1 if v else 0


## How many times its 1x size the shape is drawn, in the CourseView's space (D45, E3-S9): 1 at
## 0.5x and nearer; below that CourseView grows it (layout_hole_labels, BuilderTuning
## marker_min_screen_scale) so the tee blocks and the pin keep their 0.5x size on screen. A
## grown marker spans several tiles, so it draws over the terrain (z_index 1), as the aim
## marker does, rather than be cut by the tiles in front of it. The ball and the guests go to
## z 1 at the same zooms (CourseView.lifted_z), so they still Y-sort with it.
var shape_scale: float = 1.0:
	set(v):
		if not is_equal_approx(v, shape_scale):
			shape_scale = v
			z_index = 1 if shape_scale > 1.0 + 0.0001 else 0
			queue_redraw()
			label.queue_redraw()


func _init(p_kind: Kind = Kind.TEE, p_hole_number: int = 0, p_cell: Vector2i = Vector2i.ZERO) -> void:
	kind = p_kind
	hole_number = p_hole_number
	cell = p_cell
	name = "%s%d" % ["Tee" if kind == Kind.TEE else "Pin", hole_number]
	label = Node2D.new()
	label.name = "Label"
	label.draw.connect(_draw_label)
	add_child(label)


## Stands the marker on its tile's ground in `course`.
func place(course: CourseData) -> void:
	ground = course.get_height(cell.x, cell.y)
	# A block tee_block_offset px either side on screen is (+-o, -+o) tiles from the centre.
	var o: float = tee_block_offset / Iso.TILE_W
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var t := Vector2(cell) + Vector2(side * o, -side * o)
		block_lift[i] = (TerrainMesh.ground_at(course, t) - ground) * Iso.STEP_PX
	var at: Vector2 = draw_point()
	position = Vector2(at.x, Iso.object_sort_key(Vector2(cell), ground))
	queue_redraw()
	label.queue_redraw()


## Where its shape is drawn, in the CourseView's space: its tile's centre, on the ground.
func draw_point() -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), ground)


## The text it shows: its hole's name (hole_label, else its number) on a tee marker, nothing
## on a pin.
func label_text() -> String:
	if kind != Kind.TEE or hole_number <= 0:
		return ""
	return hole_label if not hole_label.is_empty() else str(hole_number)


## The hole number's height on screen at a zoom of `zoom` screen px per local unit, in px.
func label_screen_height(zoom: float) -> float:
	return ThemeDB.fallback_font.get_height(number_font_size) * text_scale * zoom


## The hole number's box on screen at a zoom of `zoom` screen px per local unit, in px relative
## to its tile centre on the ground (draw_point), outline included; empty on a pin or a tee
## with no number (E3-S40).
func label_rect(zoom: float) -> Rect2:
	var text: String = label_text()
	if text.is_empty():
		return Rect2()
	var font: Font = ThemeDB.fallback_font
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size).x
	var ascent: float = font.get_ascent(number_font_size)
	var descent: float = font.get_descent(number_font_size)
	# Drawn from label_origin, its baseline ascent / 2 below it (local).
	var o: Vector2 = label_origin(w) * zoom
	var k: float = text_scale * zoom
	var base_y: float = o.y + ascent * 0.5 * k
	var r := Rect2(o.x, base_y - ascent * k, w * k, (ascent + descent) * k)
	return r.grow(LABEL_OUTLINE * 0.5 * k)


## Where the hole number's text starts (its left edge, at its vertical middle), local units from
## the tile centre on the ground (draw_point), for text `text_w` screen px wide: number_gap
## screen px (and its outline) out from the ink edge of the block on `label_side`, level with
## that block's centre (E3-S66).
func label_origin(text_w: float) -> Vector2:
	var i: int = 1 if label_side >= 0.0 else 0
	var edge: float = (tee_block_offset + tee_block_radius + 1.0) * shape_scale
	var out: float = edge + (number_gap + LABEL_OUTLINE * 0.5) * text_scale
	var x: float = out if i == 1 else -out - text_w * text_scale
	return Vector2(x, -tee_block_radius * shape_scale - block_lift[i])


## The label_side for a tee at `tee` whose cup is at `cup` (E3-S66): the side away from the cup
## on screen (a tile's screen x runs with x - y), the right-hand one when the cup is straight up
## or down the screen from it.
static func side_away_from(tee: Vector2i, cup: Vector2i) -> float:
	return -1.0 if (cup.x - cup.y) > (tee.x - tee.y) else 1.0


## Whether drawn ground nearer the camera than this tee's row covers any part of its number at
## a zoom of `zoom` (E3-S40): the frontmost ground under the bottom corners and middle of
## label_rect stands on a row in front (ground in front rises up the screen from below, so the
## bottom edge is covered first). With no tile within LIFT_REACH in front higher than this one,
## nothing can cover it and no ray is cast.
func label_covered(course: CourseData, zoom: float) -> bool:
	var r: Rect2 = label_rect(zoom)
	if r.size == Vector2.ZERO or zoom <= 0.0:
		return false
	var higher: bool = false
	for dy: int in range(0, LIFT_REACH + 1):
		for dx: int in range(0, LIFT_REACH + 1):
			var c := cell + Vector2i(dx, dy)
			if (dx > 0 or dy > 0) and course.in_bounds(c.x, c.y) and course.get_height(c.x, c.y) > ground:
				higher = true
	if not higher:
		return false
	var at: Vector2 = draw_point()
	for p: Vector2 in [Vector2(r.position.x, r.end.y), Vector2(r.get_center().x, r.end.y), r.end]:
		var hit: Array = TilePicker.cast(course, at + p / zoom)
		if not hit.is_empty() and (hit[0] as Vector2i).x + (hit[0] as Vector2i).y > cell.x + cell.y:
			return true
	return false


## Its Y-sort key, in the CourseView's space (Iso.object_sort_key on its tile).
func sort_key() -> float:
	return position.y


func _draw() -> void:
	var at: Vector2 = draw_point() - position
	# The shape, drawn about its tile's centre at shape_scale (D45: never under its 0.5x size),
	# from the hole marker sheet (E5-S3, art/specs/hole_markers.md).
	var k: float = shape_scale
	draw_set_transform(at, 0.0, Vector2.ONE * k)
	if kind == Kind.TEE:
		for i: int in 2:
			var side: float = -1.0 if i == 0 else 1.0
			_draw_frame(&"tee_block", Vector2(side * tee_block_offset, -block_lift[i] / k))
	else:
		_draw_frame(&"cup", Vector2.ZERO)
		# The pole and its waving pennant (E7-S1): the one texture every pin shares.
		var pin: Array = SHEET_FRAMES[&"pin_0"]
		draw_texture(pennant_texture(), -(pin[1] as Vector2))
	draw_set_transform(Vector2.ZERO)


## Draws sheet frame `frame` with its anchor on `foot` (in the transform set by _draw).
func _draw_frame(frame: StringName, foot: Vector2) -> void:
	var f: Array = SHEET_FRAMES[frame]
	var region: Rect2 = f[0]
	draw_texture_rect_region(_sheet_texture(), Rect2(foot - (f[1] as Vector2), region.size), region)


static var _texture: Texture2D


static func _sheet_texture() -> Texture2D:
	if _texture == null:
		_texture = load(SHEET_PATH) as Texture2D
	return _texture


## The pin frame (0 still, 1 mid wave, 2 full wave) the pennant shows `t` seconds into its wave
## at `frame_s` seconds a frame (BuilderTuning.pennant_frame_s, E7-S1); PENNANT_CYCLE wraps. A
## rate of 0 or less holds the still frame.
static func pennant_frame(t: float, frame_s: float) -> int:
	if frame_s <= 0.0:
		return 0
	return PENNANT_CYCLE[posmod(int(floorf(t / frame_s)), PENNANT_CYCLE.size())]


## The pin frame the shared pennant texture shows now.
static var pennant_shown: int = 0
static var _pennant: ImageTexture
static var _pennant_frames: Array[Image] = []


## The pole and pennant every pin draws (E7-S1): one texture shared by all of them, whose
## pixels show_pennant swaps for the next wave frame. The pins' draw commands keep pointing at
## it, so the wave redraws no pin and costs one 16 x 36 upload a frame change, whatever the
## hole count.
static func pennant_texture() -> ImageTexture:
	if _pennant == null:
		var sheet: Image = _sheet_texture().get_image()
		for i: int in 3:
			var r: Rect2 = SHEET_FRAMES[StringName("pin_%d" % i)][0]
			_pennant_frames.append(sheet.get_region(Rect2i(r)))
		_pennant = ImageTexture.create_from_image(_pennant_frames[pennant_shown])
	return _pennant


## The pixels of the frame pennant_texture shows now.
static func pennant_image() -> Image:
	pennant_texture()
	return _pennant_frames[pennant_shown]


## Shows pin frame `frame` on every pin (its pixels into pennant_texture), if not shown already.
static func show_pennant(frame: int) -> void:
	if frame == pennant_shown and _pennant != null:
		return
	var tex: ImageTexture = pennant_texture()
	pennant_shown = frame
	tex.update(_pennant_frames[frame])


## The tee's hole number, on `label`, at screen size (text_scale).
func _draw_label() -> void:
	var text: String = label_text()
	if text.is_empty():
		return
	var at: Vector2 = draw_point() - position
	var font: Font = ThemeDB.fallback_font
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size).x
	var base := Vector2(0.0, font.get_ascent(number_font_size) * 0.5)
	label.draw_set_transform(at + label_origin(w), 0.0, Vector2.ONE * text_scale)
	label.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size, LABEL_OUTLINE, ink_color)
	label.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size, pole_color)
	label.draw_set_transform(Vector2.ZERO)
