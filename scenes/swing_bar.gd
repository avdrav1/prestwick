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

@export var bar_width: float = 420.0
@export var bar_height: float = 18.0
@export var back_color: Color = Color8(58, 60, 70)
@export var fill_color: Color = Color8(106, 108, 118)
@export var zone_color: Color = Color8(124, 192, 78)
@export var over_color: Color = Color8(216, 58, 58)
@export var mark_color: Color = Color8(240, 236, 224)
@export var cursor_color: Color = Color8(240, 200, 58)
@export var ink_color: Color = Color8(26, 28, 34)

var swing: Swing

## Room above and below the bar for the pointers, px.
const PAD: float = 10.0


func _init() -> void:
	custom_minimum_size = Vector2(bar_width, bar_height + 2.0 * PAD)
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


## A triangle with its tip at `tip`, pointing down onto the bar when `down`, else up.
func _triangle(tip: Vector2, r: float, down: bool, color: Color) -> void:
	var s := -1.0 if down else 1.0
	var pts := PackedVector2Array([tip, tip + Vector2(-r, s * r * 1.4), tip + Vector2(r, s * r * 1.4)])
	draw_colored_polygon(pts, color)
	draw_polyline(pts + PackedVector2Array([tip]), ink_color, 1.0)
