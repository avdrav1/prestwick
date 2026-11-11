class_name BuildRuler
extends Node2D
## E8-S5: how long a hole is while you build it (pillar 2), one overlay node, a child of the
## BuildTool (so it sits in course screen space and draws over the ground and the hover
## outline). A reader only: it never writes the course.
##
## The ruler: with the Cup tool in hand and the picked hole's tee on the map, a line from the tee
## to the tile under the cursor (mouse or keyboard cursor, BuildTool.hover) with its yardage and
## the par that yardage makes under rule 4, "285 yd: par 3". The yardage is the one the cup would
## get there (CourseValidator.hole_yardage, D47): on a dogleg whose fairway already bends (its
## turn_point with the cup at the cursor) the line runs tee -> turn -> cursor with a dot at the
## turn, as the line of play will; otherwise it is the straight line.
##
## The rings: while the picked hole's tee is placed and the Tee or Cup tool is in hand, faint
## rings round the tee at the driver's carry and total on flat fairway (golf/clubs.tres) and at
## rule 4's par 4 and par 5 lines (course/validator_tuning.tres), each labelled. Each ring lies on
## the drawn ground (HeightField.ground_screen) and is clipped to the map. Each label stands, with
## a dot, where its ring crosses the line being measured (the ruler, else the line to the cup),
## below and right of it, so it reads as "the driver gets this far along this line".
##
## Cost (D52): nothing per frame but a few comparisons in _process. The ruler is measured when
## the cursor, the tee, the tool or the ground changes; the rings' points when the tee, the
## ground or the radii change; and the node redraws only then and on a zoom change, so the
## canvas holds the drawing between. Hidden whenever the tool is not active (Play).

## A ring's points: one per this many tiles of its circumference, at least RING_MIN_POINTS.
const RING_STEP_TILES: float = 1.0
const RING_MIN_POINTS: int = 48
## The ruler's line is cut this often (tiles) so it lies on the ground it crosses.
const RULER_STEP_TILES: float = 0.5
## The ruler's text stands this far above the cursor's tile, and a ring's label this far off its
## ring, screen px.
const RULER_TEXT_LIFT_PX: float = 22.0
const RING_LABEL_GAP_PX: float = 4.0
## Where a ring's label stands when its place on the measured line is off the map: tile
## directions from the tee in order of preference, screen up first, then round.
const LABEL_DIRS: Array[Vector2] = [
	Vector2(-1, -1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, -1),
	Vector2(-1, 1), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1),
]
## The labels' ink outline: its width in font px and its opacity.
const LABEL_OUTLINE_PX: int = 4
const LABEL_OUTLINE_ALPHA: float = 0.9

## The tool it follows (its parent).
var tool: BuildTool
var tuning: BuilderTuning
## Whether the ruler shows now, and what it shows: its points in tile coordinates (tee, the
## turn on a dogleg, the cursor), its yardage and the par that makes.
var ruler_shown: bool = false
var ruler_line: PackedVector2Array = PackedVector2Array()
var ruler_yards: int = 0
var ruler_par: int = 0
## The rings shown now, nearest first: {yards, label, color, runs (screen polylines on the
## ground), label_at (screen)}. Empty when none show.
var rings: Array[Dictionary] = []
## How many times the ruler and the rings were measured (tests: on a change, not per frame).
var measure_count: int = 0
var ring_build_count: int = 0

var _clubs: ClubSet
var _field: HeightField
var _course: CourseData
var _key: Array = []
var _ring_key: Array = []
var _zoom: float = 0.0


func _init() -> void:
	name = "BuildRuler"
	tuning = BuilderTuning.load_default()
	_clubs = ClubSet.load_default()


## The rings' radii and labels, nearest first: the driver's carry and total (golf/clubs.tres)
## and the shortest par 4 and par 5 (rule 4, `validator`'s tuning).
func ring_specs(validator: CourseValidator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var driver: Club = null
	for c: Club in _clubs.clubs:
		if c.kind == Club.Kind.DRIVER:
			driver = c
	if driver != null:
		out.append({"yards": driver.carry_yd, "label": "driver carry %d yd" % roundi(driver.carry_yd),
				"color": tuning.ring_club_color})
		out.append({"yards": driver.total_yd, "label": "driver total %d yd" % roundi(driver.total_yd),
				"color": tuning.ring_club_color})
	var vt: ValidatorTuning = validator.tuning
	out.append({"yards": float(vt.par4_min_yd), "label": "par 4 from %d yd" % vt.par4_min_yd,
			"color": tuning.ring_par_color})
	out.append({"yards": float(vt.par5_min_yd), "label": "par 5 from %d yd" % vt.par5_min_yd,
			"color": tuning.ring_par_color})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.yards < b.yards)
	return out


## The ruler's text: "285 yd: par 3".
func ruler_text() -> String:
	return "%d yd: par %d" % [ruler_yards, ruler_par] if ruler_shown else ""


## True while rings show round the picked hole's tee.
func rings_shown() -> bool:
	return not rings.is_empty()


## Measures the ruler and the rings again if what they read changed since the last time, and
## redraws then. Returns true when it did. _process calls it every frame; tests call it at once.
func refresh() -> bool:
	var key: Array = _state_key()
	if key == _key:
		return false
	_key = key
	_measure()
	queue_redraw()
	return true


func _process(_delta: float) -> void:
	if tool == null:
		return
	refresh()
	if visible and (ruler_shown or rings_shown()):
		var z: float = _view_scale()
		if not is_equal_approx(z, _zoom):
			_zoom = z
			queue_redraw()


## What the ruler and the rings read: the tool's state, the picked hole's tee and cup and the
## ground's revision.
func _state_key() -> Array:
	if tool == null or tool.builder == null or not tool.active:
		return [false]
	var c: CourseData = tool.builder.course
	var h: HoleData = tool.picked_hole()
	return [true, c.get_instance_id(), c.revision, tool.tool, tool.hover,
			h.tee if h != null else HoleData.UNPLACED, h.cup if h != null else HoleData.UNPLACED]


func _measure() -> void:
	measure_count += 1
	ruler_shown = false
	ruler_line = PackedVector2Array()
	ruler_yards = 0
	ruler_par = 0
	visible = tool != null and tool.active
	if tool == null or tool.builder == null or not tool.active:
		rings = []
		_ring_key = []
		return
	var c: CourseData = tool.builder.course
	if c != _course:
		_course = c
		_field = HeightField.new(c, BallParams.load_default())
	var v: CourseValidator = tool.builder.validator
	var h: HoleData = tool.picked_hole()
	var has_tee: bool = h != null and c.in_bounds(h.tee.x, h.tee.y)
	var cursor: Vector2i = tool.hover
	if has_tee and tool.tool == BuildTool.Tool.CUP and cursor != TilePicker.NONE and cursor != h.tee:
		# The hole as it would be with its cup on the cursor's tile.
		var probe := HoleData.new(h.number, h.par, h.tee, cursor, false)
		var turn: Variant = v.turn_point(c, probe)
		ruler_line = CourseValidator.line_of_play_through(probe, turn)
		ruler_yards = CourseValidator.play_yards(probe, turn)
		ruler_par = v.par_for_yardage(ruler_yards)
		ruler_shown = true
	if has_tee and (tool.tool == BuildTool.Tool.CUP or tool.tool == BuildTool.Tool.TEE):
		var ring_key: Array = [c.get_instance_id(), c.revision, h.tee]
		if ring_key != _ring_key:
			_ring_key = ring_key
			_build_rings(c, v, h)
		_place_labels(c, h)
	else:
		rings = []
		_ring_key = []


## Lays each ring on the ground round `h`'s tee, clipped to the map (_place_labels picks
## their labels' spots).
func _build_rings(c: CourseData, v: CourseValidator, h: HoleData) -> void:
	ring_build_count += 1
	rings = []
	var ypt: float = _field.yards_per_tile
	var centre: Vector2 = Vector2(h.tee)
	for spec: Dictionary in ring_specs(v):
		var r: float = float(spec.yards) / ypt
		var n: int = maxi(RING_MIN_POINTS, ceili(TAU * r / RING_STEP_TILES))
		var runs: Array[PackedVector2Array] = []
		var run := PackedVector2Array()
		for i: int in n + 1:
			var a: float = TAU * float(i) / n
			var t: Vector2 = centre + Vector2(cos(a), sin(a)) * r
			if _on_map(c, t):
				run.append(_ground(t))
			elif run.size() > 1:
				runs.append(run)
				run = PackedVector2Array()
			else:
				run = PackedVector2Array()
		if run.size() > 1:
			runs.append(run)
		if runs.is_empty():
			continue
		var ring: Dictionary = spec.duplicate()
		ring["runs"] = runs
		ring["label_at"] = null
		rings.append(ring)


## Puts each ring's label on the line the player is measuring: where the ring crosses the
## ruler (or the ruler's line run on past the cursor), else on the line to the hole's cup, else
## toward the middle of the map; the first of LABEL_DIRS on the map when that point is off it.
func _place_labels(c: CourseData, h: HoleData) -> void:
	var tee := Vector2(h.tee)
	var line := PackedVector2Array()
	if ruler_line.size() >= 2:
		line = ruler_line
	elif c.in_bounds(h.cup.x, h.cup.y) and h.cup != h.tee:
		line = PackedVector2Array([tee, Vector2(h.cup)])
	else:
		var mid := Vector2(c.width - 1, c.height - 1) * 0.5
		line = PackedVector2Array([tee, mid if mid.distance_to(tee) > 1.0 else tee + Vector2(1, 1)])
	for ring: Dictionary in rings:
		var r: float = float(ring.yards) / _field.yards_per_tile
		var t: Vector2 = along(line, r)
		ring["label_at"] = _ground(t) if _on_map(c, t) else _label_spot(c, tee, r)


## The first point of polyline `line` (tile coordinates, from the tee) `r` tiles from its first
## point; past its end, its last segment run on to that distance.
static func along(line: PackedVector2Array, r: float) -> Vector2:
	var o: Vector2 = line[0]
	for i: int in range(1, line.size()):
		var a: Vector2 = line[i - 1]
		var b: Vector2 = line[i]
		if b.distance_to(o) >= r:
			# Solve |a + (b - a) s - o| = r for s in [0, 1].
			var d: Vector2 = b - a
			var f: Vector2 = a - o
			var qa: float = d.dot(d)
			var qb: float = 2.0 * f.dot(d)
			var qc: float = f.dot(f) - r * r
			if qa > 0.0:
				var s: float = (-qb + sqrt(maxf(qb * qb - 4.0 * qa * qc, 0.0))) / (2.0 * qa)
				return a + d * clampf(s, 0.0, 1.0)
	var last_a: Vector2 = line[line.size() - 2]
	var last_b: Vector2 = line[line.size() - 1]
	var dir: Vector2 = (last_b - last_a).normalized()
	# Run on from the end until r from the start (the end is nearer than r).
	var f2: Vector2 = last_b - o
	var b2: float = f2.dot(dir)
	var s2: float = -b2 + sqrt(maxf(b2 * b2 - (f2.dot(f2) - r * r), 0.0))
	return last_b + dir * s2


## The screen point of the first of LABEL_DIRS whose point on the ring is on the map; null when
## none is.
func _label_spot(c: CourseData, centre: Vector2, r: float) -> Variant:
	for d: Vector2 in LABEL_DIRS:
		var t: Vector2 = centre + d.normalized() * r
		if _on_map(c, t):
			return _ground(t)
	return null


static func _on_map(c: CourseData, t: Vector2) -> bool:
	return t.x >= -0.5 and t.y >= -0.5 and t.x <= c.width - 0.5 and t.y <= c.height - 0.5


## The screen point of tile position `t` (integer = tile centre) on the drawn ground.
func _ground(t: Vector2) -> Vector2:
	var y: Vector2 = (t + Vector2(0.5, 0.5)) * _field.yards_per_tile
	return Iso.tile_to_screen(t, _field.drawn_steps(y.x, y.y))


## The ruler's line on the ground, screen points, cut every RULER_STEP_TILES.
func ruler_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if not ruler_shown or _field == null:
		return out
	for i: int in range(1, ruler_line.size()):
		var a: Vector2 = ruler_line[i - 1]
		var b: Vector2 = ruler_line[i]
		var steps: int = maxi(1, ceili(a.distance_to(b) / RULER_STEP_TILES))
		for k: int in steps + 1:
			if k == 0 and i > 1:
				continue
			out.append(_ground(a.lerp(b, float(k) / steps)))
	return out


func _draw() -> void:
	if not visible or (not ruler_shown and rings.is_empty()):
		return
	var z: float = _view_scale()
	_zoom = z
	var font: Font = ThemeDB.fallback_font
	var px: float = 1.0 / z
	for ring: Dictionary in rings:
		for run: PackedVector2Array in ring.runs:
			draw_polyline(run, ring.color, tuning.ring_width_px * px)
	for ring: Dictionary in rings:
		if ring.label_at != null:
			var col: Color = Color(ring.color, 1.0)
			draw_circle(ring.label_at as Vector2, (tuning.ring_width_px + 1.5) * px, col)
			_text(font, ring.label as String, ring.label_at as Vector2, tuning.ring_font_px, z, col,
					Vector2(RING_LABEL_GAP_PX, tuning.ring_font_px + RING_LABEL_GAP_PX), false)
	if ruler_shown:
		var pts: PackedVector2Array = ruler_points()
		draw_polyline(pts, tuning.ruler_halo_color, (tuning.ruler_width_px + 2.0 * tuning.ruler_halo_px) * px)
		draw_polyline(pts, tuning.ruler_color, tuning.ruler_width_px * px)
		for i: int in range(1, ruler_line.size() - 1):
			var dot: Vector2 = _ground(ruler_line[i])
			draw_circle(dot, (tuning.ruler_width_px + 2.0) * px, tuning.ruler_halo_color)
			draw_circle(dot, (tuning.ruler_width_px + 1.0) * px, tuning.ruler_color)
		_text(font, ruler_text(), pts[pts.size() - 1], tuning.ruler_font_px, z, Color(tuning.ruler_color, 1.0),
				Vector2(0.0, -RULER_TEXT_LIFT_PX))


## Draws `text` at `at` (CourseView space) moved `lift` screen px, centred on it or (not
## `centred`) starting there, `size` screen px tall at zoom `z`, in `col` on an ink outline.
func _text(font: Font, text: String, at: Vector2, size: int, z: float, col: Color, lift: Vector2,
		centred: bool = true) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_set_transform(at + lift / z, 0.0, Vector2.ONE / z)
	var o := Vector2(-w * 0.5 if centred else 0.0, 0.0)
	draw_string_outline(font, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, LABEL_OUTLINE_PX,
			Color(tuning.ruler_halo_color, LABEL_OUTLINE_ALPHA))
	draw_string(font, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _view_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var s: float = get_global_transform_with_canvas().get_scale().x
	return s if s > 0.0 else 1.0
