class_name AimView
extends Node2D
## The aim line and aim marker in Play (E2-S7, D14), drawn from a ShotPrediction: the same
## Ball step as the live flight (E1-S7), so the marker tells the truth.
##
## A full club: dots on the straight chord, as the screen shows it, from the drawn ball to
## the predicted first touchdown of a perfect swing (the ball flies straight, D14), and the
## marker there. So from a raised tee the line starts at the ball and does not hug the hill.
## The putter: dots along the predicted roll on the drawn ground (the bilinear ground the ball
## rolls on), so the break shows smoothly; the marker sits at the predicted rest point.
##
## The marker stands on the drawn ground under it (D50; D17's tile top before E3-S59), as the
## ball and the struck ball's landing cross do. Everything draws over the terrain (z_index), so a hill never
## hides where the shot goes. Sits at the CourseView's origin. A
## reader only. Drawn in code with art/palette.gpl colours until the final art (E5-S3).
## Shape and colour both say what it is: dots for the line, a ring with a centre dot and
## four ticks for the marker (the landing marker of a struck ball is a red cross).
##
## A blocked club (D20, ClubSet.is_blocked: a riser face or trees ahead stop a perfect
## swing while it is still climbing): the marker sits where the flight is stopped
## (ShotPrediction.stop_point: the first touchdown on a face, or the point trees block it),
## drawn as a filled flag_red octagon with a chalk bar (HazardCue, E6-S16: not a slashed
## ring, so it never reads as the OB cue), with no ticks, and no dots are drawn.
## The club picker says "blocked" too.
##
## The land line (D29, E6-S7): with the aim it draws every edge between owned and unowned
## land (LandBoundary), on the drawn ground (the higher of the two sides at a water bank), as chalk dashes on a solid ink
## line, a boundary of white stakes, so the player sees where a shot goes OB before striking.
## Pattern and shade both read it, and dashes are not the aim's dots. A fully owned course
## (New sandbox) has no line, so its aim is unchanged. Each tile edge carries a short tick
## pointing into the unowned side (LandBoundary.unowned_side), so the line says which side
## is out. An edge hidden by a tile in front (LandBoundary.covered) draws faded
## (land_line_hidden_alpha), as an issue marker's leader does behind a hill (E2-S17), so the
## line never reads as running over the hill's top while the ground behind it decides OB.
## The line stays drawn through the struck ball's flight and its water or OB hold (E6-S16):
## the strike calls clear_aim, which drops the dots and marker but keeps the line, so the
## player sees the boundary the ball crossed. clear (Build, a finished hole) hides it all.
##
## E10-S3, the live landing marker: while the swing's power is being set (and after click 2,
## at the locked power), SwingControl predicts a full club's shot at that power with the same
## ShotModel, Ball step and seed the strike will use and shows it here (show_preview): the dots
## and the marker go to its landing, and the perfect swing's marker stays drawn faded
## (reference_alpha) as the 100% reference. `marker_point` and `marker_screen` stay the perfect
## swing's, so the camera's lead on the marker does not move during the swing. The strike's
## clear_aim drops it.
##
## A shot that ends in water or OB (prediction.penalty_strokes, E6-S7 review): the marker
## shows the hazard cue the struck ball shows there (ShotView, HazardCue): a flag_red circle
## struck through by a slash running past it for OB, chalk splash rings for water, on an ink
## outline, at the point the ball stops in the hazard (prediction.hazard_position, where the
## dots end). A putt draws it in place of the rest ring; a full club keeps its landing ring
## when it lands clear and rolls in, and draws the cue in place of the ring when it lands
## in the hazard.

## sun_yellow dots and ring on an ink outline.
@export var line_color: Color = Color8(240, 200, 58)
@export var outline_color: Color = Color8(26, 28, 34)
## flag_red: the blocked marker (D20).
@export var blocked_color: Color = Color8(216, 58, 58)
## Yards between dots along the line.
@export var dot_spacing_yd: float = 2.5
## Dot radius and marker ring radius (x; the ring is a 2:1 ellipse), screen px at 1x. Below
## 1x they keep their 1x size on screen, so the line still reads at 0.5x.
@export var dot_radius: float = 1.6
@export var marker_radius: float = 9.0
## The land line (E6-S7): chalk dashes on an ink line, screen px at 1x (kept at 0.5x).
@export var land_line_color: Color = Color8(240, 236, 224)
@export var land_line_width: float = 2.0
@export var land_line_dash: float = 6.0
## The unowned-side tick, in tiles from the edge, and the alpha of an edge hidden by terrain.
@export var land_tick_tiles: float = 0.3
@export var land_line_hidden_alpha: float = 0.3
## chalk: the water cue's splash rings (ShotView's hazard cue) and the blocked marker's bar.
@export var splash_color: Color = Color8(240, 236, 224)
## E10-S3: the perfect swing's marker is drawn at this alpha while the live marker shows.
@export var reference_alpha: float = 0.4

## The prediction drawn, or null.
var prediction: ShotPrediction
## True when it is a putt (the line follows the roll and the marker is the rest point).
var is_putt: bool = false
## True when the club is blocked (D20): the marker is the struck-through ring.
var blocked: bool = false
## Screen points of the dots, in the CourseView's space.
var dots: PackedVector2Array = PackedVector2Array()
## The marker's point in yards (the first touchdown, the putt's rest point, or for a
## blocked club where the flight is stopped).
var marker_point: Vector3 = Vector3.ZERO
## Its screen point, on the drawn ground under it.
var marker_screen: Vector2 = Vector2.ZERO
## The land line in the CourseView's space: points 2k and 2k + 1 end one tile edge
## (LandBoundary.segments, projected). Empty on a fully owned course.
var land_line: PackedVector2Array = PackedVector2Array()
## Per land-line edge k: its unowned-side tick, points 2k and 2k + 1 (from the edge's middle
## into unowned land), and whether terrain in front hides it.
var land_ticks: PackedVector2Array = PackedVector2Array()
var land_hidden: Array[bool] = []
## E10-S3: the live landing marker's prediction (a shot at the swing's power), or null; its
## marker point in yards (as `marker_point` is for the aim's) and screen point, dots, blocked
## flag, hazard cue and whether it draws its ring.
var preview: ShotPrediction
var preview_point: Vector3 = Vector3.ZERO
var preview_screen: Vector2 = Vector2.ZERO
var preview_dots: PackedVector2Array = PackedVector2Array()
var preview_blocked: bool = false
var preview_hazard: Ball.Hazard = Ball.Hazard.NONE
var preview_hazard_screen: Vector2 = Vector2.ZERO
var preview_show_ring: bool = true
## The hazard the shot ends in (Ball.Hazard.NONE when none, or the club is blocked), and
## the screen point of its cue (prediction.hazard_position, on the drawn ground).
var hazard_cue: Ball.Hazard = Ball.Hazard.NONE
var hazard_screen: Vector2 = Vector2.ZERO
## False when the cue takes the ring's place (a putt, or a landing in the hazard).
var show_ring: bool = true

## A landing this close to where the ball stops in the hazard landed in it, yards.
const HAZARD_AT_LANDING_YD: float = 0.5

var _field: HeightField
## scenes/shot_view_tuning.tres: the OB slash's reach, as ShotView draws it.
var _cue_tuning: ShotViewTuning = ShotViewTuning.load_default()
## The canvas scale the shapes were last drawn for.
var _view_scale: float = 1.0
## The course and its revision the land line was built for (_build_land_line).
var _land_course: CourseData
var _land_revision: int = -1


func _init() -> void:
	z_index = 2  # over the course layers and the Build tool's outline
	visible = false


## Shows the aim for `p_prediction` of a shot struck from `start` (yards) over `field`.
## `p_blocked` is ClubSet.is_blocked for the shot (D20).
func show_prediction(field: HeightField, p_prediction: ShotPrediction, putt: bool, start: Vector3,
		p_blocked: bool = false) -> void:
	_field = field
	prediction = p_prediction
	is_putt = putt
	blocked = p_blocked
	hazard_cue = Ball.Hazard.NONE
	show_ring = not blocked
	if prediction.penalty_strokes > 0 and not blocked:
		hazard_cue = prediction.hazard
		hazard_screen = ground_screen(prediction.hazard_position)
		var landing := Vector2(prediction.landing.x, prediction.landing.y)
		show_ring = not putt and landing.distance_to(
				Vector2(prediction.hazard_position.x, prediction.hazard_position.y)) > HAZARD_AT_LANDING_YD
	if putt:
		marker_point = prediction.hazard_position if hazard_cue != Ball.Hazard.NONE else prediction.rest
	elif blocked:
		marker_point = prediction.stop_point
	else:
		marker_point = prediction.landing
	marker_screen = ground_screen(marker_point)
	dots = PackedVector2Array()
	if putt:
		_dots_along_roll(prediction.path)
	elif not blocked:
		_dots_along_chord(start, marker_point)
	_build_land_line(field.course)
	visible = true
	queue_redraw()


## E10-S3: shows the live landing marker for `p_prediction`, a full club's shot from `start`
## (yards) at the swing's power; `p_blocked` is ClubSet.is_blocked for it. Over the aim shown.
func show_preview(field: HeightField, p_prediction: ShotPrediction, start: Vector3,
		p_blocked: bool = false) -> void:
	_field = field
	preview = p_prediction
	preview_blocked = p_blocked
	preview_hazard = Ball.Hazard.NONE
	preview_show_ring = not p_blocked
	if preview.penalty_strokes > 0 and not p_blocked:
		preview_hazard = preview.hazard
		preview_hazard_screen = ground_screen(preview.hazard_position)
		var landing := Vector2(preview.landing.x, preview.landing.y)
		preview_show_ring = landing.distance_to(Vector2(preview.hazard_position.x,
				preview.hazard_position.y)) > HAZARD_AT_LANDING_YD
	preview_point = preview.stop_point if p_blocked else preview.landing
	preview_screen = ground_screen(preview_point)
	preview_dots = PackedVector2Array()
	if not p_blocked:
		preview_dots = _chord_dots(start, preview_point, preview_screen)
	queue_redraw()


## Drops the live landing marker; the aim's own marker draws as before.
func clear_preview() -> void:
	if preview == null:
		return
	preview = null
	preview_dots = PackedVector2Array()
	queue_redraw()


func _process(_delta: float) -> void:
	if not visible or not is_inside_tree():
		return
	var s := get_viewport().get_canvas_transform().get_scale().x
	if not is_equal_approx(s, _view_scale):
		_view_scale = s
		queue_redraw()


## Drops the aim (its dots, marker and cue) at the strike but keeps the land line drawn
## through the flight and the hazard hold (E6-S16). Visible only while there is a line.
func clear_aim() -> void:
	clear_preview()
	prediction = null
	blocked = false
	dots = PackedVector2Array()
	hazard_cue = Ball.Hazard.NONE
	visible = not land_line.is_empty()
	queue_redraw()


## Hides the aim and the land line.
func clear() -> void:
	clear_preview()
	prediction = null
	blocked = false
	dots = PackedVector2Array()
	land_line = PackedVector2Array()
	land_ticks = PackedVector2Array()
	land_hidden = []
	_land_course = null
	hazard_cue = Ball.Hazard.NONE
	visible = false
	queue_redraw()


## The land line, its unowned-side ticks and which edges terrain hides, in screen space. Built
## again only when the course or its tiles or ownership changed (CourseData.revision): which
## edges the ground hides is a ray cast per edge (E3-S59), too dear for every aim move.
func _build_land_line(course: CourseData) -> void:
	if course == _land_course and course.revision == _land_revision:
		return
	_land_course = course
	_land_revision = course.revision
	land_line = PackedVector2Array()
	land_ticks = PackedVector2Array()
	land_hidden = []
	var s := LandBoundary.segments(course)
	for k in range(0, s.size(), 2):
		var a := s[k]
		var b := s[k + 1]
		land_line.append(Iso.point_to_screen(a))
		land_line.append(Iso.point_to_screen(b))
		var m := (a + b) * 0.5
		var out := LandBoundary.unowned_side(course, a, b) * land_tick_tiles
		land_ticks.append(Iso.point_to_screen(m))
		land_ticks.append(Iso.point_to_screen(m + Vector3(out.x, out.y, 0.0)))
		land_hidden.append(LandBoundary.covered(course, a, b))


## Screen point of the ground point `p` (yards), on the drawn ground under it (D50).
func ground_screen(p: Vector3) -> Vector2:
	return _field.ground_screen(p)


## A flight: dots every `dot_spacing_yd` (measured on the ground) on the screen segment from
## the drawn ball (the ground under `start`) to the marker, the chord the ball's straight
## heading takes between them.
func _dots_along_chord(start: Vector3, end: Vector3) -> void:
	dots = _chord_dots(start, end, marker_screen)


## The dots of a flight's chord from the drawn ball under `start` to `to` (the screen point of
## `end`), every `dot_spacing_yd` measured on the ground.
func _chord_dots(start: Vector3, end: Vector3, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var from := ground_screen(start)
	var length := Vector2(start.x, start.y).distance_to(Vector2(end.x, end.y))
	if length <= 0.0:
		return out
	var d := dot_spacing_yd
	while d <= length:
		out.append(from.lerp(to, d / length))
		d += dot_spacing_yd
	return out


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
			dots.append(_field.ground_screen(Vector3(p.x, p.y, 0.0)))
			carry += dot_spacing_yd
		carry -= seg


## The marker's k at canvas scale `view_scale`: its sizes are screen px at 1x times k. Below
## 1x the marker keeps its 1x size on screen; above 1x it grows with the map, so at 2x the
## marker, its hazard cue and the OB slash are twice their 1x length on screen (E6-S32).
static func marker_k(view_scale: float) -> float:
	return 1.0 / clampf(view_scale, 0.01, 1.0)


## The OB preview's slash at canvas scale `view_scale`, its two ends in the CourseView's space,
## as _draw_hazard draws it: one unbroken slash at the plain ob_slash_reach, since no ball sits
## under the marker to break it round (ShotView's ob_slash_reach_at lengthens the struck
## ball's slash at 2x only to make up for the gap round its growing ball).
func ob_preview_slash(view_scale: float) -> PackedVector2Array:
	return HazardCue.ob_slash(hazard_screen, marker_radius * marker_k(view_scale),
			_cue_tuning.ob_slash_reach)


func _draw() -> void:
	var k := marker_k(_view_scale)
	_draw_land_line(k)
	if prediction == null:
		return
	var r := marker_radius * k
	if preview == null:
		_draw_dots(dots, k, 1.0)
		_draw_marker(marker_screen, blocked, hazard_cue, hazard_screen, show_ring, r, k, 1.0)
		return
	# E10-S3: the live marker over the faded 100% reference.
	_draw_marker(marker_screen, blocked, hazard_cue, hazard_screen, show_ring, r, k, reference_alpha)
	_draw_dots(preview_dots, k, 1.0)
	_draw_marker(preview_screen, preview_blocked, preview_hazard, preview_hazard_screen,
			preview_show_ring, r, k, 1.0)


func _draw_dots(points: PackedVector2Array, k: float, alpha: float) -> void:
	for d in points:
		draw_circle(d, (dot_radius + 1.0) * k, Color(outline_color, alpha))
		draw_circle(d, dot_radius * k, Color(line_color, alpha))


## One marker at `at`: the blocked octagon, or the hazard cue at `cue_at` and (when `ring`)
## the landing ring with its ticks, at `alpha`.
func _draw_marker(at: Vector2, is_blocked: bool, cue: Ball.Hazard, cue_at: Vector2, ring: bool,
		r: float, k: float, alpha: float) -> void:
	var ink := Color(outline_color, alpha)
	var line := Color(line_color, alpha)
	if is_blocked:
		HazardCue.draw_blocked(self, at, r, k, Color(blocked_color, alpha), ink,
				Color(splash_color, alpha))
		return
	if cue != Ball.Hazard.NONE:
		_draw_hazard(cue, cue_at, r, k, alpha)
	if not ring:
		return
	draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, ink, 4.0 * k)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, line, 2.0 * k)
	draw_set_transform(Vector2.ZERO)
	for dir: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
		draw_line(at + dir * (r - 3.0 * k), at + dir * (r + 4.0 * k), ink, 3.0 * k)
		draw_line(at + dir * (r - 3.0 * k), at + dir * (r + 4.0 * k), line, 1.5 * k)
	draw_circle(at, 2.5 * k, ink)
	draw_circle(at, 1.5 * k, line)


## The hazard cue at the end of the shot, as ShotView draws it (HazardCue): OB a flag_red
## circle struck through by a slash running past it, water two chalk splash rings.
func _draw_hazard(cue: Ball.Hazard, at: Vector2, r: float, k: float, alpha: float = 1.0) -> void:
	if cue == Ball.Hazard.OB:
		HazardCue.draw_ob(self, at, r, k, _cue_tuning.ob_slash_reach, Color(blocked_color, alpha),
				Color(outline_color, alpha))
	else:
		HazardCue.draw_water(self, at, r, k, Color(splash_color, alpha), Color(outline_color, alpha))


## The land line: a solid ink line under chalk dashes along every owned-to-unowned edge,
## each with its tick into unowned land, faded where terrain in front hides the edge.
func _draw_land_line(k: float) -> void:
	for e: int in land_hidden.size():
		var i := 2 * e
		var alpha := land_line_hidden_alpha if land_hidden[e] else 1.0
		var ink := Color(outline_color, outline_color.a * alpha)
		var chalk := Color(land_line_color, land_line_color.a * alpha)
		draw_line(land_line[i], land_line[i + 1], ink, (land_line_width + 2.0) * k)
		draw_line(land_ticks[i], land_ticks[i + 1], ink, (land_line_width + 2.0) * k)
		draw_dashed_line(land_line[i], land_line[i + 1], chalk, land_line_width * k,
				land_line_dash * k)
		draw_line(land_ticks[i], land_ticks[i + 1], chalk, land_line_width * k)
