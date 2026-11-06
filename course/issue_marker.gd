class_name IssueMarker
extends Node2D
## The highlight on a tile where a hole rule fails (E2-S3), drawn in code until the final art.
## A reader only. CourseView owns one per tile at fault and shows them in Build mode.
##
## Shape and colour both say what it is (colorblind rule): a doubled diamond outline round the
## tile, on its ground, ink outside and flag_red inside, a warning badge with "!" on its right corner,
## and one line per failing rule, "rule <n>: <reason>", in chalk on an ink box above the
## tile, clear of a pin standing there, joined to the tile centre by a leader line. Lines wrap
## at `text_width`. Colours are art/palette.gpl entries.
##
## Depth: the diamond Y-sorts with the terrain like a HoleMarker (the node sits at
## Iso.object_sort_key on its tile), so ground nearer the camera hides it and a fault behind a
## hill does not read as being on the hill. Since E3-S59 (D50) the diamond follows the drawn
## ground round the tile's edges (TerrainMesh.ring), so on a slope it lies on it. The badge, leader and text box are a
## child drawn over everything (`label`, z_index 2), so the fault still shows.
##
## The leader's foot (the dot on the tile centre) draws over everything too, so when ground in
## front stands high enough to cover the tile centre (`foot_hidden`, E2-S17; since E3-S59 the
## drawn ground, TilePicker.hidden) the leader draws dashed, the foot as a faded ring and the
## badge faded, so the fault does not read as being on the hill.
##
## The text keeps its screen size at every zoom step, so a reason reads at 0.5x. CourseView
## lays the boxes out in screen space (`text_scale`, `stack`, `shift`) so neighbouring boxes
## never cover each other and none sits far above or beside its tile; one with no room
## near its tile collapses to its badge (`collapsed`).

@export var line_color: Color = Color8(216, 58, 58)
@export var ink_color: Color = Color8(26, 28, 34)
@export var text_color: Color = Color8(240, 236, 224)
## Outline width (screen px at 1x); how far above the tile centre the text box ends, clear of
## a pin (HoleMarker pole_height plus its cup); the text size, wrap width and box padding
## (screen px at every zoom).
@export var outline_width: float = 2.0
@export var text_lift: float = 40.0
@export var font_size: int = 14
@export var text_width: float = 320.0
@export var text_padding: float = 4.0
## A hidden foot's (and its badge's) alpha, and its leader's dash length (screen px at 1x).
@export var hidden_alpha: float = 0.45
@export var dash_length: float = 4.0

var cell: Vector2i = Vector2i.ZERO
## The whole height of the tile it stands on.
var ground: int = 0
## The diamond's outline and its inner line, on the ground, in the node's space (place).
var _outer := PackedVector2Array()
var _inner := PackedVector2Array()
## Whether a tile in front covers this tile's centre, so the leader's foot is hidden (E2-S17).
var foot_hidden: bool = false:
	set(value):
		if value != foot_hidden:
			foot_hidden = value
			label.queue_redraw()
## The failing rules on this tile, one per reason, in the validator's order.
var rules: PackedInt32Array = PackedInt32Array()
var reasons: PackedStringArray = PackedStringArray()
## The hole each rule belongs to (0 when not given), so with nine holes a box says which.
var holes: PackedInt32Array = PackedInt32Array()
## The name each rule's hole goes by on the map (CourseData.hole_label, E3-S27): "4a" and "4b"
## for two holes sharing number 4; empty gives the number.
var names: PackedStringArray = PackedStringArray()
## The badge, leader line and text box, drawn over the terrain (z_index 2).
var label: Node2D
## The wrapped lines and the box size, measured once per set of rules (add clears them): the
## layout asks for box_size many times per check, and measuring text is the costly part.
var _wrapped_lines: PackedStringArray = PackedStringArray()
var _box_size: Vector2 = Vector2(-1.0, -1.0)
## Local units per screen pixel (1 / zoom), set by CourseView's layout.
var text_scale: float = 1.0:
	set(value):
		if value != text_scale:
			text_scale = value
			label.queue_redraw()
## How far the text box is pushed up past text_lift, screen px, set by CourseView's layout.
var stack: float = 0.0:
	set(value):
		if value != stack:
			stack = value
			label.queue_redraw()
## How far the text box is moved sideways off centre, screen px, set by CourseView's layout.
var shift: float = 0.0:
	set(value):
		if value != shift:
			shift = value
			label.queue_redraw()
## Whether the layout found no room for the text box near the tile, so only the diamond and
## badge draw (the hole panel still lists the reasons), set by CourseView's layout.
var collapsed: bool = false:
	set(value):
		if value != collapsed:
			collapsed = value
			label.queue_redraw()


func _init(p_cell: Vector2i = Vector2i.ZERO) -> void:
	cell = p_cell
	name = "Issue_%d_%d" % [cell.x, cell.y]
	label = Node2D.new()
	label.name = "Label"
	label.z_index = 2
	label.draw.connect(_draw_label)
	add_child(label)


## Adds one failing rule and its one-line reason, of hole `hole` (0: not named, E3-S2), named
## `hole_name` on the map ("4a" for a duplicate, E3-S27; empty names it by its number).
func add(rule: int, reason: String, hole: int = 0, hole_name: String = "") -> void:
	rules.append(rule)
	reasons.append(reason)
	holes.append(hole)
	names.append(hole_name)
	_box_size = Vector2(-1.0, -1.0)
	label.queue_redraw()


## True when it shows exactly `p_rules`, `p_reasons`, `p_holes` and `p_names` (CourseView keeps
## it then).
func shows(p_rules: PackedInt32Array, p_reasons: PackedStringArray, p_holes: PackedInt32Array,
		p_names: PackedStringArray = PackedStringArray()) -> bool:
	if p_names.is_empty():
		p_names.resize(p_rules.size())
	return rules == p_rules and reasons == p_reasons and holes == p_holes and names == p_names


## Stands the marker on its tile in `course`: its diamond on the ground round the tile.
func place(course: CourseData) -> void:
	ground = course.get_height(cell.x, cell.y)
	var at: Vector2 = draw_point()
	position = Vector2(at.x, Iso.object_sort_key(Vector2(cell), ground))
	label.position = at - position
	foot_hidden = covered(course, cell)
	_outer = _ring(course, 1.0)
	_inner = _ring(course, 0.7)
	queue_redraw()
	label.queue_redraw()


## Whether ground in front of `at` (nearer the camera) covers the centre of `at`, where the
## leader's foot is drawn (TilePicker.hidden on the drawn ground, E3-S59).
static func covered(course: CourseData, at: Vector2i) -> bool:
	return TilePicker.hidden(course, Vector3(at.x, at.y, course.get_height(at.x, at.y)))


## Where it is drawn, in the CourseView's space: its tile's centre, on the ground (its height).
func draw_point() -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), ground)


## Its Y-sort key, in the CourseView's space (Iso.object_sort_key on its tile).
func sort_key() -> float:
	return position.y


## The lines it shows, one per failing rule: "hole 3, rule 2: ..." when the hole is named,
## "hole 4b, rule 2: ..." for the second of two holes numbered 4 (E3-S27).
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in rules.size():
		var hole: String = ""
		if i < names.size() and not names[i].is_empty():
			hole = "hole %s, " % names[i]
		elif holes[i] > 0:
			hole = "hole %d, " % holes[i]
		out.append("%srule %d: %s" % [hole, rules[i], reasons[i]])
	return out


## The text box size in screen px (zero when there are no rules).
func box_size() -> Vector2:
	if rules.is_empty():
		return Vector2.ZERO
	if _box_size.x >= 0.0:
		return _box_size
	var font: Font = ThemeDB.fallback_font
	var text: PackedStringArray = _wrapped(font)
	var width: float = 0.0
	for t: String in text:
		width = maxf(width, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	_box_size = Vector2(width + text_padding * 2.0, font.get_height(font_size) * text.size() + text_padding * 2.0)
	return _box_size


## The text box in screen px, relative to the tile centre, at a zoom of `scale` screen px per
## local unit, pushed up by `push` px and sideways by `side` px: centred over the tile, its
## bottom text_lift above it.
func box_rect(scale: float, push: float, side: float = 0.0) -> Rect2:
	var size: Vector2 = box_size()
	var bottom: float = -text_lift * scale - push
	return Rect2(Vector2(-size.x * 0.5 + side, bottom - size.y), size)


## `line` broken at spaces into pieces no wider than text_width (a single long word stays whole).
func wrap_line(font: Font, line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current: String = ""
	for word: String in line.split(" "):
		var next: String = word if current.is_empty() else current + " " + word
		if not current.is_empty() and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > text_width:
			out.append(current)
			current = "  " + word
		else:
			current = next
	out.append(current)
	return out


func _wrapped(font: Font) -> PackedStringArray:
	if _box_size.x >= 0.0:
		return _wrapped_lines
	var text := PackedStringArray()
	for l: String in lines():
		text.append_array(wrap_line(font, l))
	_wrapped_lines = text
	return text


## The diamond round the tile scaled by `k`, on the drawn ground, relative to the node.
func _ring(course: CourseData, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in TerrainMesh.ring_screen(course, cell, k):
		out.append(p - position)
	return out


## The diamond, on the ground round the tile, sorted with the terrain.
func _draw() -> void:
	if _outer.is_empty():
		return
	draw_polyline(_outer, ink_color, outline_width * 2.0 + 2.0)
	draw_polyline(_outer, line_color, outline_width)
	draw_polyline(_inner, line_color, 1.0)


## The badge, leader line and text box, over everything; drawn on `label`, at the tile centre.
func _draw_label() -> void:
	var font: Font = ThemeDB.fallback_font
	# The warning badge on the right corner: a triangle with "!", faded with a hidden foot.
	var a: float = hidden_alpha if foot_hidden else 1.0
	var corner := Vector2(Iso.HALF_W - 2.0, -4.0)
	var tri := PackedVector2Array([corner + Vector2(-7, 6), corner + Vector2(7, 6), corner + Vector2(0, -7), corner + Vector2(-7, 6)])
	label.draw_colored_polygon(tri, Color(line_color, a))
	label.draw_polyline(tri, Color(ink_color, a), 1.0)
	label.draw_string(font, corner + Vector2(-2, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(text_color, a))
	if rules.is_empty() or collapsed:
		return
	# The reasons, at screen size, above the tile; a leader line down to the tile centre.
	label.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * text_scale)
	var s: float = 1.0 / text_scale if text_scale > 0.0 else 1.0
	var box: Rect2 = box_rect(s, stack, shift)
	# The leader meets the box bottom straight above the tile, or its nearest end when shifted.
	var inset: float = minf(text_padding * 2.0, box.size.x * 0.5)
	var top := Vector2(clampf(0.0, box.position.x + inset, box.end.x - inset), box.end.y)
	if foot_hidden:
		var faded := Color(line_color, hidden_alpha)
		label.draw_dashed_line(Vector2.ZERO, top, Color(ink_color, hidden_alpha), 3.0, dash_length)
		label.draw_dashed_line(Vector2.ZERO, top, faded, 1.0, dash_length)
		label.draw_arc(Vector2.ZERO, 2.5, 0.0, TAU, 12, faded, 1.0)
	else:
		label.draw_line(Vector2.ZERO, top, ink_color, 3.0)
		label.draw_line(Vector2.ZERO, top, line_color, 1.0)
		label.draw_circle(Vector2.ZERO, 2.5, line_color)
	label.draw_rect(box, Color(ink_color, 0.85))
	label.draw_rect(box, line_color, false, 1.0)
	var line_h: float = font.get_height(font_size)
	var text: PackedStringArray = _wrapped(font)
	for i: int in text.size():
		var at := Vector2(box.position.x + text_padding, box.position.y + text_padding + line_h * i + font.get_ascent(font_size))
		label.draw_string(font, at, text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	label.draw_set_transform(Vector2.ZERO)
