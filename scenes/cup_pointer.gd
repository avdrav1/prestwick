class_name CupPointer
extends Control
## The off-screen cup's edge marker (E3-S64; docs/design.md Camera): in Play, when the hole
## being played has its cup outside the free view (Main.free_view_rect), a marker stands just
## inside the free view's edge on the line from the free view's centre to the cup, an arrow
## pointing at the cup and a box with the hole's number, so a neighbouring hole's flag on
## screen never reads as this hole's. It hides once the cup is in the free view. A reader only:
## Main hands it the cup's screen point each frame (follow), and it takes no clicks
## (MOUSE_FILTER_IGNORE), so the swing and the map tags still get them.
##
## Colours (art/palette.gpl): an ink box and arrow edge, chalk number, flag_red arrow (the
## pennant's colour, so it reads as "the flag is this way").

@export var box_color: Color = Color8(26, 28, 34)
@export var text_color: Color = Color8(240, 236, 224)
@export var arrow_color: Color = Color8(216, 58, 58)

var tuning: CupPointerTuning
## The hole number shown.
var number: int = 0
## Where the marker's centre stands, screen px (valid while visible).
var at: Vector2 = Vector2.ZERO
## The unit direction from the marker to the cup (valid while visible).
var direction: Vector2 = Vector2.RIGHT


func _init() -> void:
	tuning = CupPointerTuning.load_default()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Hole `p_number`'s cup shows at screen point `cup`, and `free` is the free view: shows the
## marker at the free view's edge pointing at the cup while the cup is outside `free`, else
## hides it.
func follow(cup: Vector2, free: Rect2, p_number: int) -> void:
	var inner: Rect2 = free.grow(-tuning.edge_inset)
	if free.has_point(cup) or not inner.has_area():
		hide_marker()
		return
	var centre: Vector2 = inner.get_center()
	var d: Vector2 = cup - centre
	# Along the line from the free view's centre to the cup, to the inset rect's edge.
	var t: float = INF
	if not is_zero_approx(d.x):
		t = minf(t, (inner.size.x * 0.5) / absf(d.x))
	if not is_zero_approx(d.y):
		t = minf(t, (inner.size.y * 0.5) / absf(d.y))
	at = centre + d * minf(t, 1.0)
	direction = (cup - at).normalized() if not cup.is_equal_approx(at) else d.normalized()
	number = p_number
	visible = true
	queue_redraw()


func hide_marker() -> void:
	if visible:
		visible = false


## The arrow's tip, screen px.
func tip() -> Vector2:
	return at + direction * tuning.arrow_length


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var text := str(number)
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, tuning.font_size)
	var h: float = font.get_height(tuning.font_size)
	var box := Rect2(at - Vector2(size.x * 0.5 + tuning.padding, h * 0.5 + tuning.padding),
			Vector2(size.x + tuning.padding * 2.0, h + tuning.padding * 2.0))
	draw_rect(box, box_color)
	draw_rect(box, arrow_color, false, 1.5)
	draw_string(font, Vector2(box.position.x + tuning.padding, box.position.y + tuning.padding + font.get_ascent(tuning.font_size)),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, tuning.font_size, text_color)
	# The arrow beside the box, its base by the box's edge, its tip toward the cup.
	var side := Vector2(-direction.y, direction.x)
	var base: Vector2 = at + direction * (tuning.arrow_length * 0.55)
	var arrow := PackedVector2Array([tip(), base + side * tuning.arrow_half_width,
			base - side * tuning.arrow_half_width])
	draw_colored_polygon(arrow, arrow_color)
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), box_color, 1.5)
