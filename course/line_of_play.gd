class_name LineOfPlay
extends Node2D
## Each hole's line of play in Build (E3-S46, D47, pillar 2), a child of CourseView. A reader
## only: it draws the lines the validator measured (CourseBuilder.slot_lines) and never writes
## the course.
##
## A faint dashed chalk line, edged in faint ink so it reads on light and dark ground, runs tee -> turn -> cup on a dogleg, with a small dot at the turn, and
## tee -> cup on a straight hole, so the map shows the line rule 4 measures and where it bends:
## painting the corner moves the turn, and the line with it. Numbers in BuilderTuning
## (play_line_*).
##
## Drawn on the ground (D50): every dash is cut at tile edges and centre lines (CUT_TILES), each
## end at HeightField.drawn_steps, so the line lies on the slope it crosses.
## Each piece Y-sorts with the terrain at its tile's row key (Iso.depth_key) plus SORT_BIAS,
## after that row's ground and before an object on it (+ 1.5 or more), so a hill in front hides
## the line behind it and the tee markers, pins and issue diamonds draw over it. The pieces of
## one sort key share one Row node. The geometry is built when the lines change or the ground
## under them moved (show_lines, after every validator run, with the run's own lines); a zoom change only resizes the widths (screen px).
## Shown in Build only (Main._apply_mode sets `enabled`).

## A piece's sort key past its tile's row key: after the row's ground (+0), above a contour
## line (+0.25) and before an object on it (+1.5 or more).
const SORT_BIAS: float = 0.3
## A dash is cut wherever it crosses a line of this many tiles' spacing through the tile
## centres and edges: the drawn ground's grid lines (TerrainTuning.subdiv 2) and where the
## bilinear ground bends, so each straight piece lies on it.
const CUT_TILES: float = 0.5
## A height change this many tiles from a line moves the ground under it (TerrainMesh reach).
const REACH_TILES: float = 2.0

var tuning: BuilderTuning
## Main turns it on in Build, off in Play.
var enabled: bool = true:
	set(value):
		enabled = value
		visible = value
## Each hole's line, in tile coordinates (integer = tile centre), one per slot in CourseData.holes
## order: [tee, cup] or [tee, turn, cup], empty for a hole without both a tee and a cup.
var lines: Array[PackedVector2Array] = []
## Every turn drawn (tile coordinates).
var turns: PackedVector2Array = PackedVector2Array()
## How many times the geometry was built (tests: once per show_lines, not per frame).
var build_count: int = 0

var _course: CourseData
var _field: HeightField
var _zoom: float = 0.0
## Each slot's line as last cut, and its pieces (_pieces_of); an empty cached line forces a cut.
var _slot_lines: Array[PackedVector2Array] = []
var _slot_pieces: Array = []
var _rows: Dictionary = {}


## The pieces of one sort key, in the Row's space: segments as pairs, and turn dots.
class Row:
	extends Node2D
	var segs := PackedVector2Array()
	var dots := PackedVector2Array()
	var width: float = 1.0
	var radius: float = 2.0
	var color: Color = Color.WHITE
	var halo: float = 0.0
	var halo_color: Color = Color.BLACK

	func _draw() -> void:
		if halo > 0.0:
			if not segs.is_empty():
				draw_multiline(segs, halo_color, width + 2.0 * halo)
			for d: Vector2 in dots:
				draw_circle(d, radius + halo, halo_color)
		if not segs.is_empty():
			draw_multiline(segs, color, width)
		for d: Vector2 in dots:
			draw_circle(d, radius, color)


func _init() -> void:
	name = "LineOfPlay"
	y_sort_enabled = true
	tuning = BuilderTuning.load_default()


## Shows the lines of `c` (null clears them). Call show_lines to draw them.
func show_course(c: CourseData) -> void:
	_course = c
	_field = HeightField.new(c, BallParams.load_default()) if c != null else null
	lines = []
	turns = PackedVector2Array()
	_slot_lines = []
	_slot_pieces = []
	_clear_rows()


## Every hole's line of play as `validator` measures it now (CourseValidator.line_of_play, D47,
## D51), one per slot, for tests and callers with no builder run (Main reads the builder's,
## CourseBuilder.slot_lines).
static func lines_of(c: CourseData, validator: CourseValidator) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if c == null:
		return out
	for h: HoleData in c.holes:
		out.append(validator.line_of_play(c, h))
	return out


## The ground at `cells` moved (CourseView.refresh_cells): the next show_lines rebuilds every
## line passing within REACH_TILES of one, even when it is unchanged. Not rebuilt now: a raise
## drag moves heights every frame, and the check at the end of the stroke calls show_lines.
func mark_dirty(cells: Array[Vector2i]) -> void:
	for slot: int in _slot_lines.size():
		var line: PackedVector2Array = _slot_lines[slot]
		if line.is_empty():
			continue
		var box := Rect2(line[0], Vector2.ZERO)
		for p: Vector2 in line:
			box = box.expand(p)
		box = box.grow(REACH_TILES)
		for c: Vector2i in cells:
			if box.has_point(Vector2(c)):
				_slot_lines[slot] = PackedVector2Array()  # forces this slot's rebuild
				break


## Draws `p_lines` (tile coordinates, one per slot, as CourseBuilder.slot_lines gives) on the ground. Only a
## slot whose line changed, or whose ground moved (mark_dirty), is cut again; with none, nothing
## is rebuilt.
func show_lines(p_lines: Array[PackedVector2Array]) -> void:
	if _course == null:
		return
	var changed: bool = p_lines.size() != _slot_lines.size()
	_slot_lines.resize(p_lines.size())
	_slot_pieces.resize(p_lines.size())
	for slot: int in p_lines.size():
		if _slot_pieces[slot] == null or _slot_lines[slot] != p_lines[slot]:
			_slot_lines[slot] = p_lines[slot]
			_slot_pieces[slot] = _pieces_of(p_lines[slot])
			changed = true
	if not changed and build_count > 0:
		return
	lines = p_lines.duplicate()
	turns = PackedVector2Array()
	for line: PackedVector2Array in lines:
		for i: int in range(1, line.size() - 1):
			turns.append(line[i])
	_build()


## The Y-sorted rows drawn, one per sort key with a piece on it.
func rows() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for k: float in _rows:
		out.append(_rows[k])
	return out


## Every piece's end points as drawn, in CourseView space (tests).
func drawn_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for k: float in _rows:
		var row: Row = _rows[k]
		for p: Vector2 in row.segs:
			out.append(p + row.position)
	return out


## Every turn dot as drawn, in CourseView space (tests).
func drawn_dots() -> PackedVector2Array:
	var out := PackedVector2Array()
	for k: float in _rows:
		var row: Row = _rows[k]
		for p: Vector2 in row.dots:
			out.append(p + row.position)
	return out


## The CourseView point of tile position `t` on the ground the view draws there.
func ground_point(t: Vector2) -> Vector2:
	var ypt := _field.yards_per_tile
	var y := (t + Vector2(0.5, 0.5)) * ypt
	return Iso.tile_to_screen(t, _field.drawn_steps(y.x, y.y))


func _process(_delta: float) -> void:
	if not visible or _rows.is_empty():
		return
	var z := _view_scale()
	if not is_equal_approx(z, _zoom):
		_size(z)


## Lays the rows out again from every slot's cut pieces.
func _build() -> void:
	build_count += 1
	_clear_rows()
	var build := {}  # key -> [segs, dots], CourseView space
	for pieces: Variant in _slot_pieces:
		for key: float in pieces:
			var rec: Array = _rec(build, key)
			(rec[0] as Array).append_array(pieces[key][0])
			(rec[1] as Array).append_array(pieces[key][1])
	for key: float in build:
		var row := Row.new()
		row.position = Vector2(0, key)
		var segs := PackedVector2Array(build[key][0])
		var dots := PackedVector2Array(build[key][1])
		var off := Vector2(0, key)
		for i: int in segs.size():
			segs[i] -= off
		for i: int in dots.size():
			dots[i] -= off
		row.segs = segs
		row.dots = dots
		row.color = tuning.play_line_color
		row.halo_color = tuning.play_line_halo_color
		add_child(row)
		_rows[key] = row
	_size(_view_scale())


## One line's dashes and turn dots cut into rows: sort key -> [segs, dots], in CourseView space.
func _pieces_of(line: PackedVector2Array) -> Dictionary:
	var build := {}
	var dash: float = tuning.play_line_dash_yd / _field.yards_per_tile
	var gap: float = tuning.play_line_gap_yd / _field.yards_per_tile
	var period: float = dash + gap
	# The dashes run on along the whole line, round its turn.
	var s: float = 0.0
	for i: int in range(1, line.size()):
		var a: Vector2 = line[i - 1]
		var b: Vector2 = line[i]
		var length: float = a.distance_to(b)
		if length <= 0.0:
			continue
		# The dashes start every dash + gap along the line: [k * period, k * period + dash].
		var k: int = floori(s / period)
		while k * period < s + length:
			var lo: float = maxf(k * period, s) - s
			var hi: float = minf(k * period + dash, s + length) - s
			if hi > lo:
				_cut(a.lerp(b, lo / length), a.lerp(b, hi / length), build)
			k += 1
		s += length
	for i: int in range(1, line.size() - 1):
		var t: Vector2 = line[i]
		(_rec(build, _key(Vector2i(t.round())))[1] as Array).append(ground_point(t))
	return build


## The piece from `a` to `b` (tiles) cut at every grid line it crosses (CUT_TILES), each part
## filed under the row of its tile.
func _cut(a: Vector2, b: Vector2, build: Dictionary) -> void:
	var d := b - a
	var ts: Array[float] = [0.0, 1.0]
	for axis: int in 2:
		if d[axis] == 0.0:
			continue
		var lo := minf(a[axis], b[axis])
		var hi := maxf(a[axis], b[axis])
		# Grid lines lie at multiples of CUT_TILES from the tile edges (half-integers).
		var e := (floorf((lo + 0.5) / CUT_TILES) + 1.0) * CUT_TILES - 0.5
		while e < hi:
			ts.append((e - a[axis]) / d[axis])
			e += CUT_TILES
	ts.sort()
	for i: int in range(1, ts.size()):
		if ts[i] - ts[i - 1] <= 1e-6:
			continue
		var p := a + d * ts[i - 1]
		var q := a + d * ts[i]
		var mid := (p + q) * 0.5
		var key := _key(Vector2i(floori(mid.x + 0.5), floori(mid.y + 0.5)))
		var segs: Array = _rec(build, key)[0]
		segs.append(ground_point(p))
		segs.append(ground_point(q))


## build[key], made on first use: [segs, dots], plain Arrays appended in place (packed arrays
## copy).
func _rec(build: Dictionary, key: float) -> Array:
	if not build.has(key):
		build[key] = [[], []]
	return build[key]


## The sort key of the row of `cell` (clamped onto the map): its row's, plus SORT_BIAS.
func _key(cell: Vector2i) -> float:
	var c := cell.clamp(Vector2i.ZERO, Vector2i(_course.width - 1, _course.height - 1))
	return Iso.depth_key(c) + SORT_BIAS


## Sets every row's line width and dot radius for zoom `z` (screen px held).
func _size(z: float) -> void:
	_zoom = z
	for k: float in _rows:
		var row: Row = _rows[k]
		row.width = tuning.play_line_width_px / z
		row.radius = tuning.play_line_turn_radius_px / z
		row.halo = tuning.play_line_halo_px / z
		row.queue_redraw()


func _view_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var s: float = (get_viewport().get_canvas_transform() * get_global_transform()).get_scale().x
	return s if s > 0.0 else 1.0


func _clear_rows() -> void:
	for k: float in _rows:
		var row: Node2D = _rows[k]
		remove_child(row)
		row.free()
	_rows.clear()
