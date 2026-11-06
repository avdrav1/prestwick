class_name GreenView
extends Control
## The overhead green view (E3-S52, D48): Mean 18's green inset. Once the player's ball rests
## on a green in Play, this panel opens over the isometric view, centred in the free view
## (Main.free_view_rect), and draws that green and `fringe_tiles` of ground round its bounding
## box top-down, one square per tile: each tile's surface (its palette colour and pattern, the
## colorblind rule of art/specs/surfaces.md), its height as a shade (lower is darker, by
## value), and its slope, as an arrow pointing downhill on every tile the ground falls across
## and an ink contour line on every tile edge with a step (two lines for two steps or more), so
## the break reads in grayscale. Over them: the cup, the ball, the putt line's dots and the
## putter's marker, read from the AimView, which draws the same PuttAim solve in the isometric
## view (no second solve). Guests are not drawn in it.
##
## It closes when the ball comes to rest off the green or the hole ends, and stays open while a
## putt rolls (the ball is drawn where it is each frame). `toggle_green_view` (G) hides and
## shows it; the choice holds until it is pressed again. It only reads CourseData.
##
## Aiming and putting in it (E3-S53): while it shows, the mouse over the panel aims (the heading
## from the ball to the ground point under the cursor, in the panel's top-down space,
## SwingControl.aim_at), so the isometric aim line turns with it; the aim keys still turn the
## aim (SwingControl takes them, and the mouse takes the aim back only once it moves
## SwingTuning.mouse_reaim_px, as on the map). A left click on the panel is a swing click
## (SwingControl.press), as one on the map is, and the swing bar runs as ever. The panel takes
## the mouse motion and the left and right buttons over it, so no click on it reaches the map: no
## tag click (TagClicks), no Build switch, no paint, and the cursor over it never aims at the
## isometric ground behind it. The middle button and the wheel go on to the camera.
##
## Drawn in code with art/palette.gpl colours until the final art (E5-S3). Numbers in
## scenes/green_view_tuning.tres.

const TOGGLE_ACTION: StringName = &"toggle_green_view"

# art/palette.gpl
const INK := Color8(26, 28, 34)
const SLATE_DARK := Color8(58, 60, 70)
const CHALK := Color8(240, 236, 224)
const SUN_YELLOW := Color8(240, 200, 58)
const FLAG_RED := Color8(216, 58, 58)
## Per surface (Surface.Type order): base, pattern colour.
const SURFACE_COLORS: Array = [
	[Color8(111, 174, 74), Color8(86, 150, 60)],  # fairway, fairway_dark
	[Color8(74, 138, 58), Color8(53, 106, 44)],  # rough, rough_dark
	[Color8(154, 216, 106), Color8(124, 192, 78)],  # green, green_dark
	[Color8(120, 184, 88), Color8(95, 160, 64)],  # tee_light, tee_dark
	[Color8(232, 211, 154), Color8(201, 174, 110)],  # sand, sand_dark
	[Color8(58, 123, 200), Color8(122, 180, 232)],  # water, water_light
	[Color8(31, 74, 42), Color8(46, 107, 52)],  # tree_dark, tree
	[Color8(184, 176, 160), Color8(138, 130, 116)],  # path, path_dark
	[Color8(112, 124, 100), Color8(74, 90, 68)],  # oob, oob_dark
]
## Rough's stipple: flecks at these points of a tile (0..1).
const STIPPLE: Array[Vector2] = [Vector2(0.2, 0.25), Vector2(0.7, 0.15), Vector2(0.45, 0.6),
		Vector2(0.85, 0.7), Vector2(0.15, 0.85), Vector2(0.6, 0.9)]

var tuning: GreenViewTuning
var control: SwingControl
var shot_view: ShotView
var aim_view: AimView
## True while the ball is on a green (or a putt from one is rolling): the view is open,
## whether or not the player hid it.
var is_open: bool = false
## The player hid it (toggle_green_view).
var user_hidden: bool = false
## The tiles drawn: the green's bounding box grown by fringe_tiles, clipped to the map.
var window: Rect2i = Rect2i()
## A tile's side in the panel, px.
var tile_px: float = 24.0

var _course: CourseData
var _field: HeightField
## The ball point the window was found for.
var _window_for: Vector2 = Vector2(INF, INF)
## The window's highest tile, steps: the shade's top.
var _top: int = 0
var _terrain: Control
var _overlay: Control


func _init() -> void:
	tuning = GreenViewTuning.load_default()
	visible = false
	# PASS, not STOP: the panel accepts the motion and left button itself (_gui_input), and the
	# middle button and wheel go on to the camera, so a drag let go over it never sticks.
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_terrain = Control.new()
	_terrain.name = "Terrain"
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.draw.connect(_draw_terrain)
	add_child(_terrain)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Reads the ball, the hole and the aim from these.
func bind(p_control: SwingControl, p_shot_view: ShotView, p_aim_view: AimView) -> void:
	control = p_control
	shot_view = p_shot_view
	aim_view = p_aim_view


## True when the view should be open now: in Play, the hole not finished, and the ball at rest
## on a green, or a putt from one still rolling.
func wants_open() -> bool:
	if control == null or not control.active or control.course == null or control.is_finished():
		return false
	if control.is_ball_moving():
		return is_open
	return control.lie_surface() == Surface.Type.GREEN


## Once a frame in Play (Main._process): opens, moves or closes the view as the ball is, and
## lays it out centred in `free` (the free view, screen px).
func follow(free: Rect2) -> void:
	if not wants_open():
		close()
		return
	var c := control.course
	if c != _course or (not control.is_ball_moving() and control.ball_at != _window_for):
		_open_at(c, control.ball_at)
	is_open = true
	_layout(free)
	visible = not user_hidden
	_overlay.queue_redraw()


## Closes the view (the ball left the green, the hole ended, or Build).
func close() -> void:
	is_open = false
	visible = false
	_course = null
	_window_for = Vector2(INF, INF)


## Hides or shows the open view (toggle_green_view).
func toggle() -> void:
	user_hidden = not user_hidden
	visible = is_open and not user_hidden


func _unhandled_input(event: InputEvent) -> void:
	if control == null or not control.active:
		return
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if control == null:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if control.active and not control.swing.in_progress() \
				and control.mouse_takes_aim(motion.global_position):
			control.aim_at(to_yards(motion.position))
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			control.press()
		accept_event()


func _open_at(c: CourseData, ball: Vector2) -> void:
	_course = c
	_field = control.field
	_window_for = ball
	window = green_window(c, _field, _field.tile_at(ball.x, ball.y), tuning.fringe_tiles)
	_top = 0
	for y: int in range(window.position.y, window.end.y):
		for x: int in range(window.position.x, window.end.x):
			_top = maxi(_top, c.get_height(x, y))
	_terrain.queue_redraw()


## The tiles to draw for the green holding `tile`: the bounding box of the green tiles joined
## to it edge to edge (as the ball plays them, HeightField.surface_of), grown by `fringe` on
## every side and clipped to the map. A tile that is not green gives its own box grown so.
static func green_window(c: CourseData, field: HeightField, tile: Vector2i, fringe: int) -> Rect2i:
	var box := Rect2i(tile, Vector2i.ONE)
	if field.surface_of(tile) == Surface.Type.GREEN:
		var seen := {tile: true}
		var todo: Array[Vector2i] = [tile]
		while not todo.is_empty():
			var t: Vector2i = todo.pop_back()
			box = box.expand(t).expand(t + Vector2i.ONE)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = t + d
				if seen.has(n) or not c.in_bounds(n.x, n.y):
					continue
				seen[n] = true
				if field.surface_of(n) == Surface.Type.GREEN:
					todo.append(n)
	box = box.grow(fringe)
	return box.intersection(Rect2i(0, 0, c.width, c.height))


## Sizes the panel for the window, tiles as large as fit in `free` (less margin_px each side)
## between min_tile_px and max_tile_px, and centres it in `free`.
func _layout(free: Rect2) -> void:
	var t := tuning
	var room := free.size - Vector2.ONE * 2.0 * (t.margin_px + t.inset_px) - Vector2(0.0, t.header_px)
	var fit := minf(room.x / window.size.x, room.y / window.size.y)
	var px := clampf(floorf(fit), t.min_tile_px, t.max_tile_px)
	var want := Vector2(window.size) * px + Vector2.ONE * 2.0 * t.inset_px + Vector2(0.0, t.header_px)
	if px != tile_px:
		tile_px = px
		_terrain.queue_redraw()
	if size != want:
		size = want
		_terrain.size = want
		_overlay.size = want
		_terrain.queue_redraw()
		queue_redraw()
	position = (free.get_center() - want * 0.5).round()


## The panel point (local px) of the ground point `p` (yards).
func to_panel(p: Vector2) -> Vector2:
	return _origin() + (p / _yards_per_tile() - Vector2(window.position)) * tile_px


## The ground point (yards) under the panel point `local`.
func to_yards(local: Vector2) -> Vector2:
	return ((local - _origin()) / tile_px + Vector2(window.position)) * _yards_per_tile()


## The panel square of tile `cell`.
func tile_rect(cell: Vector2i) -> Rect2:
	return Rect2(_origin() + Vector2(cell - window.position) * tile_px, Vector2.ONE * tile_px)


func _origin() -> Vector2:
	return Vector2(tuning.inset_px, tuning.inset_px + tuning.header_px)


func _yards_per_tile() -> float:
	return _field.yards_per_tile if _field != null else 5.0


## The fall at tile `cell`'s centre, steps per tile, pointing downhill: minus the height
## field's slope there (HeightField.gradient_at, the slope the ball feels, before the green's
## slope_scale), so (1, 0) is one step per tile falling toward +x.
static func fall_at(field: HeightField, cell: Vector2i) -> Vector2:
	var c := field.tile_center(cell)
	return -field.gradient_at(c.x, c.y) * (field.yards_per_tile / field.yards_per_step)


## Where the ball is, yards: the rolling ball's point while a putt moves, else where it rests.
func ball_point() -> Vector2:
	if control.is_ball_moving() and shot_view != null and shot_view.ball != null:
		var p := shot_view.drawn_position()
		return Vector2(p.x, p.y)
	return control.ball_at


## The ball's panel point, as drawn (ball_point).
func ball_panel() -> Vector2:
	return to_panel(ball_point())


## The marker's panel point (the AimView's marker: the putt's rest, PuttAim), or null when no
## aim is shown.
func marker_panel() -> Variant:
	if aim_view == null or aim_view.prediction == null:
		return null
	var m := aim_view.marker_point
	return to_panel(Vector2(m.x, m.y))


## The putt line's dots in the panel: every AimView.dot_spacing_yd along the AimView's
## predicted roll (a full club: along the straight line to its marker).
func dot_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if aim_view == null or aim_view.prediction == null or aim_view.blocked:
		return out
	var pts := PackedVector2Array()
	if aim_view.is_putt:
		for p: Vector3 in aim_view.prediction.path:
			pts.append(Vector2(p.x, p.y))
	else:
		pts.append(control.ball_at)
		pts.append(Vector2(aim_view.marker_point.x, aim_view.marker_point.y))
	var step := aim_view.dot_spacing_yd
	var carry := step
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		while carry <= seg:
			out.append(to_panel(pts[i - 1].lerp(pts[i], carry / seg)))
			carry += step
		carry -= seg
	return out


## The cup's centre, yards, or null when the hole has none on the map.
func cup_point() -> Variant:
	if control.cup_tile() == Ball.NO_CUP:
		return null
	return _field.tile_center(control.cup_tile())


# --- Drawing ---


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SLATE_DARK)
	draw_rect(Rect2(Vector2.ZERO, size), INK, false, 2.0)
	var font := get_theme_default_font()
	var fs := 13
	draw_string(font, Vector2(tuning.inset_px + 2.0, tuning.inset_px + fs), "Green view",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CHALK)
	draw_string(font, Vector2(tuning.inset_px, tuning.inset_px + fs), "Mouse aims, click swings, G hides",
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 2.0 * tuning.inset_px - 2.0, fs, Color8(168, 168, 176))


## The shade of a tile `h` steps high: 1 at the window's top, height_shade_step darker per
## step below it, never under height_shade_min.
func shade_of(h: int) -> float:
	return maxf(1.0 - (_top - h) * tuning.height_shade_step, tuning.height_shade_min)


func _draw_terrain() -> void:
	if _course == null:
		return
	var ci := _terrain
	for y: int in range(window.position.y, window.end.y):
		for x: int in range(window.position.x, window.end.x):
			var cell := Vector2i(x, y)
			_draw_tile(ci, tile_rect(cell), _field.surface_of(cell), shade_of(_course.get_height(x, y)))
	# Contours on top of every tile, then the arrows over them.
	for y: int in range(window.position.y, window.end.y):
		for x: int in range(window.position.x, window.end.x):
			_draw_contours(ci, Vector2i(x, y))
	for y: int in range(window.position.y, window.end.y):
		for x: int in range(window.position.x, window.end.x):
			_draw_arrow(ci, Vector2i(x, y))


func _draw_tile(ci: CanvasItem, r: Rect2, s: Surface.Type, shade: float) -> void:
	var cols: Array = SURFACE_COLORS[s]
	var base := _shaded(cols[0], shade)
	var pat := _shaded(cols[1], shade)
	ci.draw_rect(r, base)
	var p := r.position
	var n := r.size.x
	match s:
		Surface.Type.GREEN:
			_hatch(ci, r, n / 3.0, pat, 1.0, true)
			_hatch(ci, r, n / 3.0, pat, 1.0, false)
		Surface.Type.ROUGH:
			for f: Vector2 in STIPPLE:
				ci.draw_rect(Rect2(p + f * (n - 3.0), Vector2(3, 3)), pat)
		Surface.Type.TEE:
			var q := n / 4.0
			for j: int in 4:
				for i: int in 4:
					if (i + j) % 2 == 0:
						ci.draw_rect(Rect2(p + Vector2(i, j) * q, Vector2(q, q)), pat)
		Surface.Type.BUNKER:
			var q := n / 4.0
			for j: int in 4:
				for i: int in 4:
					var off := 0.25 if j % 2 == 1 else 0.75
					ci.draw_circle(p + Vector2((i + off) * q, (j + 0.5) * q), 1.5, pat)
		Surface.Type.WATER:
			var q := n / 3.0
			for j: int in 3:
				var off := 0.5 if j % 2 == 1 else 0.0
				for i: int in 3:
					var c := p + Vector2((i + 0.25 + off) * q, (j + 0.6) * q)
					if c.x + q * 0.5 > p.x + n:
						continue
					ci.draw_arc(c + Vector2(q * 0.25, 0.0), q * 0.3, PI * 1.15, PI * 1.85, 6, pat, 1.5)
		Surface.Type.TREES:
			for f: Vector2 in [Vector2(0.28, 0.3), Vector2(0.72, 0.3), Vector2(0.5, 0.72)]:
				ci.draw_circle(p + f * n, n * 0.2, pat)
		Surface.Type.CART_PATH:
			for j: int in 4:
				var yy := p.y + (j + 0.5) * n / 4.0
				ci.draw_line(Vector2(p.x, yy), Vector2(p.x + n, yy), pat, 1.0)
		Surface.Type.OOB:
			_hatch(ci, r, n / 2.0, pat, maxf(3.0, n / 8.0), true)
	# Seams: a darker line on each tile's right and bottom edges, so the grid counts in tiles.
	ci.draw_line(Vector2(p.x + n - 0.5, p.y), Vector2(p.x + n - 0.5, p.y + n), pat, 1.0)
	ci.draw_line(Vector2(p.x, p.y + n - 0.5), Vector2(p.x + n, p.y + n - 0.5), pat, 1.0)


func _shaded(c: Color, shade: float) -> Color:
	return Color(c.r * shade, c.g * shade, c.b * shade, c.a)


## Diagonal lines `gap` apart across square `r`: "/" when `rising`, else "\".
func _hatch(ci: CanvasItem, r: Rect2, gap: float, col: Color, width: float, rising: bool) -> void:
	var n := r.size.x
	var p := r.position
	var k := gap * 0.5
	while k < 2.0 * n:
		var a: Vector2
		var b: Vector2
		if k <= n:
			a = Vector2(k, 0.0)
			b = Vector2(0.0, k)
		else:
			a = Vector2(n, k - n)
			b = Vector2(k - n, n)
		if not rising:
			a.x = n - a.x
			b.x = n - b.x
		ci.draw_line(p + a, p + b, col, width)
		k += gap


## Ink lines on the edges of `cell` where its neighbour toward +x or +y is at another height:
## one line for a step, two for two or more (the second inside the higher tile), so the step
## count reads as the edge cue's does in the isometric view.
func _draw_contours(ci: CanvasItem, cell: Vector2i) -> void:
	var h := _course.get_height(cell.x, cell.y)
	var r := tile_rect(cell)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var n := cell + d
		if not window.has_point(n):
			continue
		var diff := _course.get_height(n.x, n.y) - h
		if diff == 0:
			continue
		var a := r.position + Vector2(d) * tile_px
		var b := a + (Vector2(0, tile_px) if d.x == 1 else Vector2(tile_px, 0))
		# Into the higher tile: toward -d when this one is higher, +d when the neighbour is.
		var into := Vector2(d) * (1.0 if diff > 0 else -1.0)
		var w := tuning.contour_width
		ci.draw_line(a, b, INK, w)
		if absi(diff) >= 2:
			var o := into * (w + 2.0)
			ci.draw_line(a + o, b + o, INK, w)


## The slope arrow of `cell`: from its centre's fall (fall_at), pointing downhill, on a chalk
## halo so it reads on every shade; a double head on a bank (2 steps a tile or more).
func _draw_arrow(ci: CanvasItem, cell: Vector2i) -> void:
	var fall := fall_at(_field, cell)
	var m := fall.length()
	if m < tuning.arrow_min_fall:
		return
	var dir := fall / m
	var frac := lerpf(tuning.arrow_length, tuning.arrow_length_steep, clampf((m - 0.5) / 0.5, 0.0, 1.0))
	var length := tile_px * frac
	var c := tile_rect(cell).get_center()
	var tail := c - dir * length * 0.5
	var tip := c + dir * length * 0.5
	var head := maxf(5.0, length * 0.35)
	var heads: Array[Vector2] = [tip]
	if m >= 2.0:
		heads.append(tip - dir * head * 0.6)
	var w := tuning.arrow_width
	for pass_i: int in 2:
		var col := CHALK if pass_i == 0 else INK
		var ww := w + 1.5 if pass_i == 0 else w
		ci.draw_line(tail, tip, col, ww)
		for t: Vector2 in heads:
			ci.draw_line(t, t - dir.rotated(0.5) * head, col, ww)
			ci.draw_line(t, t - dir.rotated(-0.5) * head, col, ww)


func _draw_overlay() -> void:
	if _course == null or control == null:
		return
	var ci := _overlay
	var cup: Variant = cup_point()
	if cup != null:
		var at := to_panel(cup as Vector2)
		var r := maxf(tuning.cup_radius_px, control.model.params.cup_radius / _yards_per_tile() * tile_px)
		ci.draw_circle(at, r + 1.5, CHALK)
		ci.draw_circle(at, r, INK)
		# The pin's flag, so the cup reads at a glance.
		ci.draw_line(at, at + Vector2(0, -r * 3.2), CHALK, 2.0)
		ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r * 3.2),
				at + Vector2(r * 2.2, -r * 2.6), at + Vector2(0, -r * 2.0)]), FLAG_RED)
	var dr := tuning.dot_radius_px
	for d: Vector2 in dot_points():
		ci.draw_circle(d, dr + 1.0, INK)
		ci.draw_circle(d, dr, SUN_YELLOW)
	var mp: Variant = marker_panel()
	if mp != null and not control.is_ball_moving():
		_draw_marker(ci, mp as Vector2)
	var ball := ball_panel()
	ci.draw_circle(ball, tuning.ball_radius_px + 1.5, INK)
	ci.draw_circle(ball, tuning.ball_radius_px, CHALK)


## The putter's marker as the AimView draws it, round (top-down): a sun_yellow ring on an ink
## outline, four ticks and a centre dot.
func _draw_marker(ci: CanvasItem, at: Vector2) -> void:
	var r := tuning.marker_radius_px
	ci.draw_arc(at, r, 0.0, TAU, 32, INK, 4.0)
	ci.draw_arc(at, r, 0.0, TAU, 32, SUN_YELLOW, 2.0)
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		ci.draw_line(at + dir * (r - 3.0), at + dir * (r + 4.0), INK, 3.0)
		ci.draw_line(at + dir * (r - 3.0), at + dir * (r + 4.0), SUN_YELLOW, 1.5)
	ci.draw_circle(at, 2.5, INK)
	ci.draw_circle(at, 1.5, SUN_YELLOW)
