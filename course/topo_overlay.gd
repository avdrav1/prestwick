class_name TopoOverlay
extends Node2D
## Topographic contour lines over the whole course in Play (E3-S57), a child of CourseView. A
## reader only: it traces HeightField.height_at with ContourTracer (E3-S56) and never writes
## the course.
##
## Lines every TopoTuning.interval steps over the visible land, with short downhill ticks on
## each line's low side, in ink. Since E3-S59 (D50) a line is drawn at its own height, which is
## the ground's there: the course view draws the same bilinear ground the tracer follows (E3-S58),
## so every line lies on the slope it marks, unbroken, and each downhill tick runs on the ground. Water lies flat at its level, not on the
## bilinear ground, so no piece is drawn over a water tile.
##
## Drawing order: each line is cut at tile edges and every piece Y-sorts with the terrain at its
## tile's row key (Iso.depth_key) plus SORT_BIAS, after that row's ground and before an object
## on the tile (Iso.object_sort_key, + 1.5 or more), so a hill in front hides a line behind it
## and the ball, golfers, flags, tags and aim all draw over the lines. The pieces of one sort
## key share one Row node, which draws them in one call.
##
## It traces only when the course changes or the visible window leaves the traced one (the
## visible tiles grown by margin_tiles), and lays its pieces out again (ticks and line widths
## are in screen px) only when the zoom changes; panning inside the traced window costs nothing.
## Shown in Play only (Main._apply_mode sets `enabled`); `toggle_topo` (T) hides and shows it,
## on by default, and the choice holds until it is pressed again. Never drawn in Build.

const TOGGLE_ACTION: StringName = &"toggle_topo"
## A piece's sort key past its tile's row key: after the row's ground (+0) and before an object
## on it (+1.5 or more).
const SORT_BIAS: float = 0.25
const INK := Color8(26, 28, 34)
const CHALK := Color8(240, 236, 224)

var tuning: TopoTuning
## Play turns it on (Main._apply_mode); Build off.
var enabled: bool = false:
	set(value):
		enabled = value
		_sync_visible()
## The player hid it (toggle_topo).
var user_hidden: bool = false:
	set(value):
		user_hidden = value
		_sync_visible()
## The tiles traced last, and the lines found there: [level, Array[PackedVector2Array]] per level
## with any line, in yards (ContourTracer.trace_levels).
var traced_window: Rect2i = Rect2i()
var lines: Array = []
## How many times it has traced, and laid its pieces out (tests read these: never per frame).
var trace_count: int = 0
var layout_count: int = 0

var _course: CourseData
var _field: HeightField
var _dirty: bool = true
## The zoom the pieces were laid out for; 0 forces a layout.
var _zoom: float = 0.0
var _rows: Dictionary = {}


## The pieces of one sort key: line segments and tick segments as pairs, in the Row's space.
class Row:
	extends Node2D
	var segs := PackedVector2Array()
	var ticks := PackedVector2Array()
	var width: float = 1.0
	var halo: float = 0.0
	var color: Color = Color.BLACK
	var halo_color: Color = Color.WHITE

	func _draw() -> void:
		if halo > 0.0:
			if not segs.is_empty():
				draw_multiline(segs, halo_color, width + 2.0 * halo)
			if not ticks.is_empty():
				draw_multiline(ticks, halo_color, width + 2.0 * halo)
		if not segs.is_empty():
			draw_multiline(segs, color, width)
		if not ticks.is_empty():
			draw_multiline(ticks, color, width)


func _init() -> void:
	name = "Topo"
	y_sort_enabled = true
	tuning = TopoTuning.load_default()
	visible = false


## Shows the lines of `c` (null clears them). Traces on the next refresh while shown.
func show_course(c: CourseData) -> void:
	_course = c
	_field = HeightField.new(c, BallParams.load_default()) if c != null else null
	mark_dirty()


## The course's heights changed: trace again on the next refresh.
func mark_dirty() -> void:
	_dirty = true
	if visible:
		refresh()


## Hides or shows the overlay (toggle_topo); the choice holds.
func toggle() -> void:
	user_hidden = not user_hidden


func _sync_visible() -> void:
	visible = enabled and not user_hidden
	if visible and is_inside_tree():
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if enabled and event.is_action_pressed(TOGGLE_ACTION):
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		refresh()


## Traces when the course changed or the visible window left the traced one, else lays the
## pieces out again when the zoom changed; otherwise nothing.
func refresh() -> void:
	if _course == null:
		_clear_rows()
		lines = []
		traced_window = Rect2i()
		return
	var view := visible_window()
	if _dirty or not traced_window.encloses(view):
		var map := Rect2i(0, 0, _course.width, _course.height)
		_trace(view.grow(tuning.margin_tiles).intersection(map))
		_layout(_view_scale())
		return
	var z := _view_scale()
	if not is_equal_approx(z, _zoom):
		_layout(z)


## The tiles under the viewport, at any height 0 to 7, clipped to the map.
func visible_window() -> Rect2i:
	if _course == null or not is_inside_tree():
		return Rect2i()
	var inv := (get_viewport().get_canvas_transform() * get_global_transform()).affine_inverse()
	var r := get_viewport_rect()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var local: Vector2 = inv * corner
		for h: int in [0, CourseData.MAX_HEIGHT]:
			var t := Iso.screen_to_tile(local, h)
			lo = lo.min(t)
			hi = hi.max(t)
	var a := Vector2i(floori(lo.x + 0.5), floori(lo.y + 0.5))
	var b := Vector2i(floori(hi.x + 0.5), floori(hi.y + 0.5)) + Vector2i.ONE
	return Rect2i(a, b - a).intersection(Rect2i(0, 0, _course.width, _course.height))


## The levels traced over `w`: every interval from offset between its lowest and highest ground.
func levels_for(w: Rect2i) -> PackedFloat32Array:
	var span := ContourTracer.height_range(_field, w)
	return ContourTracer.levels_between(span.x, span.y, tuning.interval, tuning.offset)


## The number of lines traced (each polyline once, before it is cut at tile edges).
func line_count() -> int:
	var n := 0
	for entry: Array in lines:
		n += (entry[1] as Array).size()
	return n


## The Y-sorted rows drawn, one per sort key with a piece on it.
func rows() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for k: float in _rows:
		out.append(_rows[k])
	return out


func _trace(w: Rect2i) -> void:
	_dirty = false
	traced_window = w
	lines = []
	trace_count += 1
	if w.size.x <= 0 or w.size.y <= 0:
		return
	var levels := levels_for(w)
	var traced := ContourTracer.trace_levels(_field, levels, w, tuning.subdiv)
	for i: int in levels.size():
		if not (traced[i] as Array).is_empty():
			lines.append([levels[i], traced[i]])


func _view_scale() -> float:
	if not is_inside_tree():
		return 1.0
	return (get_viewport().get_canvas_transform() * get_global_transform()).get_scale().x


## Cuts every line at tile edges into the rows, with its ticks, for zoom `z`.
func _layout(z: float) -> void:
	_zoom = z
	layout_count += 1
	_clear_rows()
	var ypt := _field.yards_per_tile
	# Screen px per yard along a tile edge at zoom 1 (the iso diamond's side).
	var px_per_yd := Vector2(Iso.HALF_W, Iso.HALF_H).length() / ypt
	var spacing := tuning.tick_spacing_px / (z * px_per_yd)
	var length := tuning.tick_length_px / (z * px_per_yd)
	var build := {}  # key -> [segs, ticks]
	for entry: Array in lines:
		var level: float = entry[0]
		for line: PackedVector2Array in entry[1]:
			for i: int in range(1, line.size()):
				_cut(line[i - 1], line[i], level, build)
			var t := ContourTracer.ticks(line, spacing, length)
			for k: int in range(0, t.size(), 2):
				var cell := _field.tile_at(t[k].x, t[k].y)
				if _water(cell):
					continue
				var key := _key(cell)
				var rec: Array = _rec(build, key)
				# A tick starts on its line and runs downhill on the ground, so its foot sits on it.
				(rec[1] as Array).append(_screen(t[k], level) - Vector2(0, key))
				(rec[1] as Array).append(_screen(t[k + 1], _field.drawn_steps(t[k + 1].x, t[k + 1].y)) - Vector2(0, key))
	var col := Color(INK, tuning.line_alpha)
	for key: float in build:
		var row := Row.new()
		row.position = Vector2(0, key)
		row.segs = PackedVector2Array(build[key][0])
		row.ticks = PackedVector2Array(build[key][1])
		row.width = tuning.line_width_px / z
		row.halo = tuning.halo_width_px / z
		row.color = col
		row.halo_color = Color(CHALK, tuning.line_alpha * 0.6)
		add_child(row)
		_rows[key] = row


## The piece of a line from `a` to `b` (yards) cut at every tile edge it crosses, each part
## filed under the row of its tile.
func _cut(a: Vector2, b: Vector2, level: float, build: Dictionary) -> void:
	var ypt := _field.yards_per_tile
	var ts: Array[float] = [0.0, 1.0]
	var d := b - a
	for axis: int in 2:
		var lo := minf(a[axis], b[axis])
		var hi := maxf(a[axis], b[axis])
		if d[axis] == 0.0:
			continue
		var k := floorf(lo / ypt) + 1.0
		while k * ypt < hi:
			ts.append((k * ypt - a[axis]) / d[axis])
			k += 1.0
	ts.sort()
	for i: int in range(1, ts.size()):
		if ts[i] - ts[i - 1] <= 1e-6:
			continue
		var p := a + d * ts[i - 1]
		var q := a + d * ts[i]
		var mid := (p + q) * 0.5
		var cell := _field.tile_at(mid.x, mid.y)
		if _water(cell):
			continue
		var key := _key(cell)
		var rec: Array = _rec(build, key)
		(rec[0] as Array).append(_screen(p, level) - Vector2(0, key))
		(rec[0] as Array).append(_screen(q, level) - Vector2(0, key))


func _rec(build: Dictionary, key: float) -> Array:
	if not build.has(key):
		build[key] = [[], []]  # Arrays, appended in place (packed arrays copy)
	return build[key]


## Whether `cell` (clamped onto the map) is water, which lies flat at its level: no line there.
func _water(cell: Vector2i) -> bool:
	var c := cell.clamp(Vector2i.ZERO, Vector2i(_course.width - 1, _course.height - 1))
	return _course.get_surface(c.x, c.y) == Surface.Type.WATER


## The sort key of the row of `cell`: its row's, plus SORT_BIAS.
func _key(cell: Vector2i) -> float:
	var c := cell.clamp(Vector2i.ZERO, Vector2i(_course.width - 1, _course.height - 1))
	return Iso.depth_key(c) + SORT_BIAS


## The CourseView point of ground point `p` (yards) at `h` steps.
func _screen(p: Vector2, h: float) -> Vector2:
	var ypt := _field.yards_per_tile
	return Iso.tile_to_screen(Vector2(p.x / ypt - 0.5, p.y / ypt - 0.5), h)


func _clear_rows() -> void:
	for k: float in _rows:
		var row: Node2D = _rows[k]
		remove_child(row)
		row.free()
	_rows.clear()
