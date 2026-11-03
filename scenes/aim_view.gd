class_name AimView
extends Node2D
## The aim line and aim marker in Play (E2-S7, D14), drawn from a ShotPrediction: the same
## Ball step as the live flight (E1-S7), so the marker tells the truth.
##
## A full club: dots on the straight chord, as the screen shows it, from the drawn ball to
## the predicted first touchdown of a perfect swing (the ball flies straight, D14), and the
## marker there. So from a raised tee the line starts at the ball and does not hug the hill.
## The putter: dots along the predicted roll at its true (bilinear) ground height, so the
## break shows smoothly and does not jump 16 px at every tile edge; the marker sits at the
## predicted rest point.
##
## The marker stands on the top of the tile under it (D17), as the ball and the struck
## ball's landing cross do. Everything draws over the terrain (z_index), so a hill never
## hides where the shot goes. Sits at the CourseView's origin. A
## reader only. Drawn in code with art/palette.gpl colours until the final art (E5-S3).
## Shape and colour both say what it is: dots for the line, a ring with a centre dot and
## four ticks for the marker (the landing marker of a struck ball is a red cross).

## sun_yellow dots and ring on an ink outline.
@export var line_color: Color = Color8(240, 200, 58)
@export var outline_color: Color = Color8(26, 28, 34)
## Yards between dots along the line.
@export var dot_spacing_yd: float = 2.5
## Dot radius and marker ring radius (x; the ring is a 2:1 ellipse), screen px at 1x. Below
## 1x they keep their 1x size on screen, so the line still reads at 0.5x.
@export var dot_radius: float = 1.6
@export var marker_radius: float = 9.0

## The prediction drawn, or null.
var prediction: ShotPrediction
## True when it is a putt (the line follows the roll and the marker is the rest point).
var is_putt: bool = false
## Screen points of the dots, in the CourseView's space.
var dots: PackedVector2Array = PackedVector2Array()
## The marker's point in yards (the first touchdown, or the putt's rest point).
var marker_point: Vector3 = Vector3.ZERO
## Its screen point, on the top of the tile under it.
var marker_screen: Vector2 = Vector2.ZERO

var _field: HeightField
## The canvas scale the shapes were last drawn for.
var _view_scale: float = 1.0


func _init() -> void:
	z_index = 2  # over the course layers and the Build tool's outline
	visible = false


## Shows the aim for `p_prediction` of a shot struck from `start` (yards) over `field`.
func show_prediction(field: HeightField, p_prediction: ShotPrediction, putt: bool, start: Vector3) -> void:
	_field = field
	prediction = p_prediction
	is_putt = putt
	marker_point = prediction.rest if putt else prediction.landing
	marker_screen = ground_screen(marker_point)
	dots = PackedVector2Array()
	if putt:
		_dots_along_roll(prediction.path)
	else:
		_dots_along_chord(start, marker_point)
	visible = true
	queue_redraw()


func _process(_delta: float) -> void:
	if not visible or not is_inside_tree():
		return
	var s := get_viewport().get_canvas_transform().get_scale().x
	if not is_equal_approx(s, _view_scale):
		_view_scale = s
		queue_redraw()


## Hides the aim.
func clear() -> void:
	prediction = null
	dots = PackedVector2Array()
	visible = false
	queue_redraw()


## Screen point of the ground point `p` (yards), on the top of the tile under it (D17).
func ground_screen(p: Vector3) -> Vector2:
	return _field.tile_top_screen(p)


## A flight: dots every `dot_spacing_yd` (measured on the ground) on the screen segment from
## the drawn ball (tile top under `start`) to the marker, the chord the ball's straight
## heading takes between them.
func _dots_along_chord(start: Vector3, end: Vector3) -> void:
	var from := ground_screen(start)
	var to := marker_screen
	var length := Vector2(start.x, start.y).distance_to(Vector2(end.x, end.y))
	if length <= 0.0:
		return
	var d := dot_spacing_yd
	while d <= length:
		dots.append(from.lerp(to, d / length))
		d += dot_spacing_yd


## A putt: dots every `dot_spacing_yd` along the predicted roll `points`, each at the roll's
## own ground height (bilinear), so the break reads as a smooth curve.
func _dots_along_roll(points: PackedVector3Array) -> void:
	if points.size() < 2:
		return
	var carry := dot_spacing_yd
	for i in range(1, points.size()):
		var a := Vector2(points[i - 1].x, points[i - 1].y)
		var b := Vector2(points[i].x, points[i].y)
		var seg := a.distance_to(b)
		while carry <= seg:
			var p := a.lerp(b, carry / seg)
			var ground := Vector3(p.x, p.y, _field.height_at(p.x, p.y))
			dots.append(Iso.point_to_screen(_field.iso_point(ground)))
			carry += dot_spacing_yd
		carry -= seg


func _draw() -> void:
	if prediction == null:
		return
	var k := 1.0 / clampf(_view_scale, 0.01, 1.0)
	for d in dots:
		draw_circle(d, (dot_radius + 1.0) * k, outline_color)
		draw_circle(d, dot_radius * k, line_color)
	var at := marker_screen
	var r := marker_radius * k
	draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, outline_color, 4.0 * k)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, line_color, 2.0 * k)
	draw_set_transform(Vector2.ZERO)
	for dir: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
		draw_line(at + dir * (r - 3.0 * k), at + dir * (r + 4.0 * k), outline_color, 3.0 * k)
		draw_line(at + dir * (r - 3.0 * k), at + dir * (r + 4.0 * k), line_color, 1.5 * k)
	draw_circle(at, 2.5 * k, outline_color)
	draw_circle(at, 1.5 * k, line_color)
