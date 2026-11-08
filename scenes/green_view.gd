class_name GreenView
extends Control
## The overhead green view (E3-S52, D48): Mean 18's green inset. Once the player's ball rests
## on a green in Play, this panel opens over the isometric view, centred in the free view
## (Main.free_view_rect), and draws that green and `fringe_tiles` of ground round its bounding
## box top-down, one square per tile: each tile's surface (its palette colour and pattern, the
## colorblind rule of art/specs/surfaces.md), and over it a topographic map of the ground the
## ball rolls on (E3-S56): its height as a smooth shade (lower is darker, by value, sampled from
## HeightField.height_at below a tile), ink contour lines from ContourTracer every half step, a
## heavier index line every whole step, short downhill ticks on each line's low side, and a fall
## arrow only on a tile steep enough that a ball will not stop on it, so the break reads in
## grayscale. Flat ground has no lines. Over them: the cup, the ball, the putt line's dots and the
## putter's marker, read from the AimView, which draws the same PuttAim solve in the isometric
## view (no second solve). Guests are not drawn in it.
##
## It closes when the ball comes to rest off the green or the hole ends, and stays open while a
## putt rolls (the ball is drawn where it is each frame). `toggle_green_view` (G) hides and
## shows it; hidden holds for this green only (E3-S72): it opens again when the ball next rests
## on a different green or a new hole starts. It only reads CourseData.
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
## Turned to the putt (E3-S71): when it opens for a putt, the top-down drawing turns, smoothly
## (any angle, not snapped to quarter turns), so the line from the ball to the cup points up the
## panel, as in Mean 18: the ball at the bottom, the cup above it. The tiles, contours, ticks,
## arrows, the dots and the marker turn with it (the cup's flag stays upright). The panel is
## sized to the turned window's bounding box and draws every map tile under it (`drawn`), so no
## corner shows the frame. The turn holds while the putt rolls and is taken again at the next
## rest (`turn_for`). The mouse maps back through the same turn (to_yards).
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
## The player hid it (toggle_green_view), for this green only (E3-S72).
var user_hidden: bool = false
## The window and hole it was hidden on: a rest on another green, or another hole, shows it.
var _hidden_window: Rect2i = Rect2i()
var _hidden_hole: HoleData
## The tiles the panel is fitted to: the green's bounding box grown by fringe_tiles, clipped to
## the map.
var window: Rect2i = Rect2i()
## The tiles drawn (E3-S71): every map tile under the panel's turned content, clipped to the
## map. Encloses `window`; equal to it at turn 0.
var drawn: Rect2i = Rect2i()
## The panel's turn, radians (E3-S71): a ground offset in the map's top-down space (+x right,
## +y down) is turned by this in the panel. 0 is map-aligned.
var turn: float = 0.0
## A tile's side in the panel, px.
var tile_px: float = 24.0

var _course: CourseData
var _field: HeightField
## The ball point the window was found for.
var _window_for: Vector2 = Vector2(INF, INF)
## The window's highest tile, steps: the shade's top.
var _top: int = 0
## The contours of the window, traced when it opens: [level (steps), is an index line,
## Array[PackedVector2Array] of polylines in yards] per level, lowest first.
var contours: Array = []
## The panel's content (the tiles' area below the title strip), px: the turned window's
## bounding box at tile_px. Zero until fitted.
var _span: Vector2 = Vector2.ZERO
## Clips the terrain and overlay to the content, so turned tiles never cover the frame.
var _content: Control
var _terrain: Control
var _overlay: Control


func _init() -> void:
	tuning = GreenViewTuning.load_default()
	visible = false
	# PASS, not STOP: the panel accepts the motion and left button itself (_gui_input), and the
	# middle button and wheel go on to the camera, so a drag let go over it never sticks.
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.clip_contents = true
	add_child(_content)
	_terrain = Control.new()
	_terrain.name = "Terrain"
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.draw.connect(_draw_terrain)
	_content.add_child(_terrain)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_content.add_child(_overlay)


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
		if control != null and control.is_finished():
			user_hidden = false  # E3-S72: the next hole opens it again
		close()
		return
	var c := control.course
	if c != _course or (not control.is_ball_moving() and control.ball_at != _window_for):
		_open_at(c, control.ball_at)
		if user_hidden and (window != _hidden_window or control.hole != _hidden_hole):
			user_hidden = false  # E3-S72: hidden for that green only
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


## Hides or shows the open view (toggle_green_view). Hidden holds for this green and hole only
## (E3-S72): it opens again when the ball next rests on another green or a new hole starts.
func toggle() -> void:
	user_hidden = not user_hidden
	if user_hidden:
		_hidden_window = window
		_hidden_hole = control.hole if control != null else null
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
	var cup: Variant = cup_point()
	turn = turn_for(ball, cup as Vector2) if cup != null else 0.0
	drawn = Rect2i()
	_span = Vector2.ZERO
	_terrain.queue_redraw()


## The panel's turn that puts the cup straight above the ball (E3-S71), radians in [-PI, PI):
## the ball-to-cup line turned to point up. 0 when the ball is on the cup.
static func turn_for(ball: Vector2, cup: Vector2) -> float:
	var d := cup - ball
	if d.length() < 0.01:
		return 0.0
	return wrapf(-PI * 0.5 - d.angle(), -PI, PI)


## Turns the panel by `radians` and fits it again (the open view keeps it until the next rest).
func turn_to(radians: float) -> void:
	turn = radians
	_fit(tile_px)


## Sizes the content for the window turned by `turn` at `px` a tile, finds the tiles under it
## (drawn), and traces them again when they change.
func _fit(px: float) -> void:
	tile_px = px
	_span = turned_box(window.size, turn) * px
	size = _span + Vector2.ONE * 2.0 * tuning.inset_px + Vector2(0.0, tuning.header_px)
	_content.position = _origin()
	_content.size = _span
	_terrain.size = _span
	_overlay.size = _span
	var lo := Vector2(INF, INF)
	var hi := -lo
	for k: Vector2 in [Vector2.ZERO, Vector2(_span.x, 0.0), _span, Vector2(0.0, _span.y)]:
		var t := to_yards(_origin() + k) / _yards_per_tile()
		lo = lo.min(t)
		hi = hi.max(t)
	var a := Vector2i((lo + Vector2.ONE * 1e-4).floor())
	var b := Vector2i((hi - Vector2.ONE * 1e-4).ceil())
	var cover := Rect2i(a, b - a).intersection(Rect2i(0, 0, _course.width, _course.height)).merge(window)
	if cover != drawn:
		drawn = cover
		_top = 0
		for y: int in range(drawn.position.y, drawn.end.y):
			for x: int in range(drawn.position.x, drawn.end.x):
				_top = maxi(_top, _course.get_height(x, y))
		contours = trace_contours(_field, drawn, tuning)
	_terrain.queue_redraw()
	queue_redraw()


## The bounding box, in tiles, of a `tiles` window turned by `radians`.
static func turned_box(tiles: Vector2i, radians: float) -> Vector2:
	var w := Vector2(tiles)
	var cs := absf(cos(radians))
	var sn := absf(sin(radians))
	return Vector2(w.x * cs + w.y * sn, w.x * sn + w.y * cs)


## The contours of `window`: a level every contour_interval steps (from contour_offset; an index
## line every index_interval from it) between its lowest and highest
## ground (ContourTracer.levels_between over ContourTracer.height_range), each traced with
## contour_subdiv, as [level, index line, polylines in yards]. Levels with no line are left out.
static func trace_contours(field: HeightField, w: Rect2i, t: GreenViewTuning) -> Array:
	var span := ContourTracer.height_range(field, w)
	var levels := ContourTracer.levels_between(span.x, span.y, t.contour_interval, t.contour_offset)
	var traced := ContourTracer.trace_levels(field, levels, w, t.contour_subdiv)
	var out: Array = []
	for i: int in levels.size():
		if (traced[i] as Array).is_empty():
			continue
		var r := fposmod(levels[i] - t.contour_offset, t.index_interval)
		var index := r < 0.001 or t.index_interval - r < 0.001
		out.append([levels[i], index, traced[i]])
	return out


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


## Sizes the panel for the window turned by `turn` (its bounding box, turned_box), tiles as
## large as fit in `free` (less margin_px each side) between min_tile_px and max_tile_px, and
## centres it in `free`.
func _layout(free: Rect2) -> void:
	var t := tuning
	var room := free.size - Vector2.ONE * 2.0 * (t.margin_px + t.inset_px) - Vector2(0.0, t.header_px)
	var box := turned_box(window.size, turn)
	var fit := minf(room.x / box.x, room.y / box.y)
	var px := clampf(floorf(fit), t.min_tile_px, t.max_tile_px)
	if px != tile_px or _span == Vector2.ZERO:
		_fit(px)
	position = (free.get_center() - size * 0.5).round()


## The panel point (local px) of the ground point `p` (yards): its offset from the window's
## centre turned by `turn`, about the content's centre.
func to_panel(p: Vector2) -> Vector2:
	return _origin() + _span * 0.5 + _local(p).rotated(turn)


## The ground point (yards) under the panel point `local`.
func to_yards(local: Vector2) -> Vector2:
	var u := (local - _origin() - _span * 0.5).rotated(-turn)
	return (u / tile_px + _window_centre()) * _yards_per_tile()


## The ground point `p` (yards) in the terrain's unturned drawing space: px from the window's
## centre, +x right, +y down. The terrain draws in it under the turn (_draw_terrain).
func _local(p: Vector2) -> Vector2:
	return (p / _yards_per_tile() - _window_centre()) * tile_px


## Tile `cell`'s square in the terrain's unturned drawing space (_local).
func _square(cell: Vector2i) -> Rect2:
	return Rect2((Vector2(cell) - _window_centre()) * tile_px, Vector2.ONE * tile_px)


func _window_centre() -> Vector2:
	return Vector2(window.position) + Vector2(window.size) * 0.5


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


## The steepest fall in tile `cell`, steps per tile, pointing downhill: of the height field's
## slope a quarter tile from the centre toward each of its four sides (inside the tile, so in
## each of the four cells round its centre, where the bilinear slope is one-sided), the
## largest. A two-step bank to a neighbour reads 2 on both tiles beside it, where fall_at's
## centred mean reads 1.
static func steep_fall_at(field: HeightField, cell: Vector2i) -> Vector2:
	var c := field.tile_center(cell)
	var q := field.yards_per_tile * 0.25
	var best := Vector2.ZERO
	for d: Vector2 in [Vector2(q, 0), Vector2(-q, 0), Vector2(0, q), Vector2(0, -q)]:
		var g := -field.gradient_at(c.x + d.x, c.y + d.y) * (field.yards_per_tile / field.yards_per_step)
		if g.length() > best.length() + 1e-6:
			best = g
	return best


## The tiles of the window that draw a fall arrow: steep_fall_at reaching arrow_steep_fall.
func arrow_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _field == null:
		return out
	for y: int in range(drawn.position.y, drawn.end.y):
		for x: int in range(drawn.position.x, drawn.end.x):
			if steep_fall_at(_field, Vector2i(x, y)).length() >= tuning.arrow_steep_fall - 1e-6:
				out.append(Vector2i(x, y))
	return out


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


## The shade of ground `h` steps high: 1 at the window's top, height_shade_step darker per
## step below it, never under height_shade_min.
func shade_of(h: float) -> float:
	return maxf(1.0 - (_top - h) * tuning.height_shade_step, tuning.height_shade_min)


func _draw_terrain() -> void:
	if _course == null:
		return
	var ci := _terrain
	# Turned about the content's centre: everything below draws in _local's unturned space.
	ci.draw_set_transform(_span * 0.5, turn)
	for y: int in range(drawn.position.y, drawn.end.y):
		for x: int in range(drawn.position.x, drawn.end.x):
			var cell := Vector2i(x, y)
			_draw_tile(ci, _square(cell), _field.surface_of(cell))
	_draw_shade(ci)
	_draw_contours(ci)
	for cell: Vector2i in arrow_cells():
		_draw_arrow(ci, cell)


## The height shade over the tiles: ink at alpha 1 - shade_of(height_at), so each colour is
## multiplied by the shade, on a grid of shade_subdiv a tile side with the alpha blended
## between its points (smooth, by value).
func _draw_shade(ci: CanvasItem) -> void:
	var n := maxi(tuning.shade_subdiv, 1)
	var ypt := _yards_per_tile()
	var cols := drawn.size.x * n + 1
	var rows := drawn.size.y * n + 1
	var alpha := PackedFloat32Array()
	alpha.resize(cols * rows)
	for j: int in rows:
		for i: int in cols:
			var p := (Vector2(drawn.position) + Vector2(i, j) / n) * ypt
			alpha[j * cols + i] = 1.0 - shade_of(_field.height_at(p.x, p.y) / _field.yards_per_step)
	var pts := PackedVector2Array()
	var colors := PackedColorArray()
	var black := Color(0, 0, 0)
	for j: int in rows - 1:
		for i: int in cols - 1:
			var a00 := alpha[j * cols + i]
			var a10 := alpha[j * cols + i + 1]
			var a01 := alpha[(j + 1) * cols + i]
			var a11 := alpha[(j + 1) * cols + i + 1]
			if a00 == 0.0 and a10 == 0.0 and a01 == 0.0 and a11 == 0.0:
				continue
			var p00 := _local((Vector2(drawn.position) + Vector2(i, j) / n) * ypt)
			var p11 := _local((Vector2(drawn.position) + Vector2(i + 1, j + 1) / n) * ypt)
			pts.append_array([p00, Vector2(p11.x, p00.y), p11, p00, p11, Vector2(p00.x, p11.y)])
			colors.append_array([Color(black, a00), Color(black, a10), Color(black, a11),
					Color(black, a00), Color(black, a11), Color(black, a01)])
	if not pts.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), pts, colors)


## The contour lines (contours) in ink, index lines heavier, each with its downhill ticks.
func _draw_contours(ci: CanvasItem) -> void:
	var ypt := _yards_per_tile()
	var spacing := tuning.tick_spacing_px / tile_px * ypt
	var length := tuning.tick_length_px / tile_px * ypt
	for entry: Array in contours:
		var index: bool = entry[1]
		var w := tuning.index_width if index else tuning.contour_width
		for line: PackedVector2Array in entry[2]:
			var pts := PackedVector2Array()
			for p: Vector2 in line:
				pts.append(_local(p))
			ci.draw_polyline(pts, INK, w, true)
			var t := ContourTracer.ticks(line, spacing, length)
			for k: int in range(0, t.size(), 2):
				ci.draw_line(_local(t[k]), _local(t[k + 1]), INK, tuning.contour_width, true)


func _draw_tile(ci: CanvasItem, r: Rect2, s: Surface.Type) -> void:
	var cols: Array = SURFACE_COLORS[s]
	var base: Color = cols[0]
	var pat: Color = cols[1]
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


## The fall arrow of `cell`: from its steepest fall (steep_fall_at), pointing downhill, on a
## chalk halo so it reads on every shade, with a double head (a bank a ball will not stop on).
func _draw_arrow(ci: CanvasItem, cell: Vector2i) -> void:
	var fall := steep_fall_at(_field, cell)
	var dir := fall.normalized()
	var length := tile_px * tuning.arrow_length
	var c := _square(cell).get_center()
	var tail := c - dir * length * 0.5
	var tip := c + dir * length * 0.5
	var head := maxf(5.0, length * 0.35)
	var heads: Array[Vector2] = [tip, tip - dir * head * 0.6]
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
	# The overlay draws in panel points (to_panel): the content starts at the panel's _origin.
	ci.draw_set_transform(-_origin())
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
## outline, four ticks (turned with the panel) and a centre dot.
func _draw_marker(ci: CanvasItem, at: Vector2) -> void:
	var r := tuning.marker_radius_px
	ci.draw_arc(at, r, 0.0, TAU, 32, INK, 4.0)
	ci.draw_arc(at, r, 0.0, TAU, 32, SUN_YELLOW, 2.0)
	for side: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var dir := side.rotated(turn)
		ci.draw_line(at + dir * (r - 3.0), at + dir * (r + 4.0), INK, 3.0)
		ci.draw_line(at + dir * (r - 3.0), at + dir * (r + 4.0), SUN_YELLOW, 1.5)
	ci.draw_circle(at, 2.5, INK)
	ci.draw_circle(at, 1.5, SUN_YELLOW)
