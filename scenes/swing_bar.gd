class_name SwingBar
extends Control
## The three-click swing bar on the Play HUD (E2-S7), drawn from a Swing. A view only.
##
## Left to right it runs from SwingTuning.bar_min to max_power. Shape and colour both say
## what each part is (colorblind rule), with art/palette.gpl colours: the accuracy zone is a
## band with bracket ends round the tall centre line (green, chalk); the 100% mark is a tall
## chalk line, and the overswing part past it is hatched (flag_red); the bar's position is a
## sun_yellow triangle above the bar; the locked power is an ink-outlined chalk triangle
## below it, and the locked accuracy a diamond. It redraws each frame while a swing is in
## progress and on a resize.
##
## E3-S73: with the putter, the marker's pace (the power PuttAim solved, the putt the marker
## shows) is a sun_yellow tick through the bar with a small ring under it, echoing the marker
## ring; `pace` is NAN (no tick) for a full club. SwingPanel sets it.
##
## E10-S3: the bar explains itself. Under it, a full club's yards at 50% and 100% (a short
## chalk tick and the 100% line) and, past the bar's right end, at max ("161 max"): `marks`,
## from ShotModel through SwingControl.carry_at, so the club and the lie both count. The putter
## has none (its readout is the distance to the cup). The accuracy zone is labelled
## `zone_text` under its middle.

@export var bar_width: float = 440.0
@export var bar_height: float = 18.0
## E10-S3: room right of the bar for the max label, and under it for the label row, px.
@export var label_room: float = 58.0
@export var label_row: float = 20.0
@export var label_font_size: int = 13
## The accuracy zone's label.
@export var zone_text: String = "accuracy"
@export var back_color: Color = Color8(58, 60, 70)
@export var fill_color: Color = Color8(106, 108, 118)
@export var zone_color: Color = Color8(124, 192, 78)
@export var over_color: Color = Color8(216, 58, 58)
@export var mark_color: Color = Color8(240, 236, 224)
@export var cursor_color: Color = Color8(240, 200, 58)
@export var ink_color: Color = Color8(26, 28, 34)

var swing: Swing
## E3-S73: the bar position (1.0 = 100%) of the marker's pace, or NAN for none.
var pace: float = NAN
## E10-S3: the labelled bar positions, each {power, yards}, lowest first; the last is max.
## Empty for the putter. SwingPanel sets them.
var marks: Array[Dictionary] = []

## Room above and below the bar for the pointers, px.
const PAD: float = 10.0


func _init() -> void:
	custom_minimum_size = Vector2(bar_width + label_room, bar_height + 2.0 * PAD + label_row)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if swing != null and swing.in_progress():
		queue_redraw()


## The bar redraws every frame only while a swing is in progress, so a resize while idle
## asks for its own redraw (E2-S17).
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## Screen x (in this control) of bar position `v` (1.0 = 100%).
func x_of(v: float) -> float:
	var t := swing.tuning
	return (v - t.bar_min) / (t.max_power - t.bar_min) * bar_width


## E10-S3: the text of mark `i`: "N yd" at 100%, "N max" for the last, else just N.
func mark_text(i: int) -> String:
	var yards := roundi(float(marks[i].yards))
	if i == marks.size() - 1:
		return "%d max" % yards
	if is_equal_approx(float(marks[i].power), 1.0):
		return "%d yd" % yards
	return "%d" % yards


## E10-S3: where the zone's label is centred: the accuracy centre.
func zone_label_x() -> float:
	return x_of(0.0)


## Screen x of the pace tick (x_of(pace)); NAN when there is none.
func pace_x() -> float:
	return NAN if is_nan(pace) else x_of(pace)


func _draw() -> void:
	if swing == null:
		return
	var t := swing.tuning
	var top := PAD
	var bottom := PAD + bar_height
	draw_rect(Rect2(0, top, bar_width, bar_height), back_color)
	# Overswing, hatched.
	var x100 := x_of(1.0)
	var xmax := x_of(t.max_power)
	draw_rect(Rect2(x100, top, xmax - x100, bar_height), Color(over_color, 0.45))
	var hx := x100
	while hx < xmax:
		draw_line(Vector2(hx, bottom), Vector2(minf(hx + bar_height * 0.5, xmax), top), over_color, 1.5)
		hx += 5.0
	# The power filled so far (or locked).
	var filled := swing.bar if swing.phase == Swing.Phase.POWER else swing.power
	if swing.phase != Swing.Phase.IDLE and filled > 0.0:
		draw_rect(Rect2(x_of(0.0), top + 4.0, x_of(filled) - x_of(0.0), bar_height - 8.0), fill_color)
	# Accuracy zone: a band with bracket ends.
	var zh := swing.zone_half_width()
	var zl := x_of(-zh)
	var zr := x_of(zh)
	draw_rect(Rect2(zl, top, zr - zl, bar_height), Color(zone_color, 0.55))
	for zx: float in [zl, zr]:
		draw_line(Vector2(zx, top - 3.0), Vector2(zx, bottom + 3.0), zone_color, 2.0)
	draw_line(Vector2(zl, top - 3.0), Vector2(zl + 4.0, top - 3.0), zone_color, 2.0)
	draw_line(Vector2(zr, top - 3.0), Vector2(zr - 4.0, top - 3.0), zone_color, 2.0)
	draw_line(Vector2(zl, bottom + 3.0), Vector2(zl + 4.0, bottom + 3.0), zone_color, 2.0)
	draw_line(Vector2(zr, bottom + 3.0), Vector2(zr - 4.0, bottom + 3.0), zone_color, 2.0)
	# Centre and 100% lines.
	draw_line(Vector2(x_of(0.0), top - 5.0), Vector2(x_of(0.0), bottom + 5.0), mark_color, 2.0)
	draw_line(Vector2(x100, top - 5.0), Vector2(x100, bottom + 5.0), mark_color, 2.0)
	draw_rect(Rect2(0, top, bar_width, bar_height), ink_color, false, 1.5)
	# E3-S73: the marker's pace, a tick through the bar on an ink outline, a ring under it.
	if not is_nan(pace):
		var kx := pace_x()
		draw_line(Vector2(kx, top - 4.0), Vector2(kx, bottom + 2.0), ink_color, 4.0)
		draw_line(Vector2(kx, top - 4.0), Vector2(kx, bottom + 2.0), cursor_color, 2.0)
		var ring := Vector2(kx, bottom + 6.0)
		draw_arc(ring, 3.5, 0.0, TAU, 16, ink_color, 3.0)
		draw_arc(ring, 3.5, 0.0, TAU, 16, cursor_color, 1.5)
	# Locked power: a triangle below the bar.
	if swing.phase == Swing.Phase.ACCURACY or swing.phase == Swing.Phase.DONE:
		var px := x_of(swing.power)
		_triangle(Vector2(px, bottom), 6.0, false, mark_color)
	if swing.phase == Swing.Phase.DONE:
		var ax := x_of(swing.accuracy)
		var c := Vector2(ax, bottom + 6.0)
		var d := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
		draw_colored_polygon(d, cursor_color)
		draw_polyline(d + PackedVector2Array([d[0]]), ink_color, 1.0)
	# The bar's position: a triangle above the bar.
	if swing.in_progress():
		_triangle(Vector2(x_of(swing.bar), top), 7.0, true, cursor_color)
	_draw_labels(bottom)


## E10-S3: the yards under the bar (the last, max, right of its end) and the zone's label.
func _draw_labels(bottom: float) -> void:
	var font := get_theme_default_font()
	var fs := label_font_size
	var base := bottom + 11.0 + font.get_ascent(fs)
	_text(font, zone_text, zone_label_x(), base, fs, zone_color, HORIZONTAL_ALIGNMENT_CENTER)
	for i in marks.size():
		var x := x_of(float(marks[i].power))
		if i == marks.size() - 1:
			# Max: right of the bar's end, on the bar's middle line.
			var mid := PAD + bar_height * 0.5 + font.get_ascent(fs) * 0.5 - 1.0
			_text(font, mark_text(i), bar_width + 6.0, mid, fs, mark_color, HORIZONTAL_ALIGNMENT_LEFT)
			continue
		if not is_equal_approx(float(marks[i].power), 1.0):
			draw_line(Vector2(x, bottom), Vector2(x, bottom + 4.0), mark_color, 2.0)
		_text(font, mark_text(i), x, base, fs, mark_color, HORIZONTAL_ALIGNMENT_CENTER)


## Draws `text` with its baseline at `y`: centred on `x`, or starting at it, on an ink outline.
func _text(font: Font, text: String, x: float, y: float, fs: int, color: Color,
		align: HorizontalAlignment) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(x - w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else x, y)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, ink_color)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## A triangle with its tip at `tip`, pointing down onto the bar when `down`, else up.
func _triangle(tip: Vector2, r: float, down: bool, color: Color) -> void:
	var s := -1.0 if down else 1.0
	var pts := PackedVector2Array([tip, tip + Vector2(-r, s * r * 1.4), tip + Vector2(r, s * r * 1.4)])
	draw_colored_polygon(pts, color)
	draw_polyline(pts + PackedVector2Array([tip]), ink_color, 1.0)
