class_name WalkOverlay
extends Node2D
## E12-S1 (D68): which walks a cart path serves, and why one does not (pillar 2 and 3). One
## overlay node, a child of the BuildTool like E8-S5's BuildRuler, so it sits in course screen
## space over the ground. A reader only: it never writes the course.
##
## With the Cart path brush in hand (the Paint tool on cart path) in Build, every walk a round
## takes that the Walk check judges (GuestWalk.round_walks: the clubhouse door to the first open
## tee, each open hole's cup to the next open tee) is drawn as the route a guest would walk
## (GuestWalk.route), on the ground:
##   green  a cart path serves it (the route follows the path, being quicker): "2.3 s on the path"
##   red    no path serves it and it is over the least patient guest's walk limit, so it would
##          draw walk complaints: "6.9 s walk" over the reason (GuestWalk.why, the words the
##          complaint uses): "path stops 32 yd short of the 5th tee"
##   chalk  short enough that nobody minds: "1.6 s walk"
##
## Cost (D52): while the brush is not in hand it does not process at all (follow turns
## _process off) and draws nothing. In hand it compares a few values a frame, measures the walks
## when the course, its holes or its clubhouse change (a cart path drag measures once a frame it
## paints), and redraws only then and on a zoom change. Hidden in Play (the tool is not active).

## The route is cut this often (tiles) so it lies on the ground it crosses.
const STEP_TILES: float = 0.5
## Its label stands this far above the route's middle, screen px; the second line under the first.
const LABEL_LIFT_PX: float = 10.0
const LABEL_OUTLINE_PX: int = 4
const LABEL_OUTLINE_ALPHA: float = 0.9
## A dot at each end of a walk, this many px over the line's width.
const END_DOT_PX: float = 2.0
## The gap line's dashes, screen px; the label's backing box padding, px, and its ink's opacity.
const GAP_DASH_PX: float = 6.0
const LABEL_PAD_PX: float = 4.0
const LABEL_BOX_ALPHA: float = 0.7

enum State { SERVED, LONG, QUICK }

## The tool it follows (its parent).
var tool: BuildTool
var tuning: BuilderTuning
var guest_tuning: GuestTuning
## The walks shown, in round order: {from_hole, to_hole, to_slot, points (yards), duration,
## state (State), reason (GuestWalk.Reason or null), label, detail ("" or the reason's words)}.
var walks: Array[Dictionary] = []
## How many times the walks were measured (tests: on a change, not per frame).
var measure_count: int = 0

var _field: HeightField
var _course: CourseData
var _cache := GuestWalk.Cache.new()
var _key: Array = []
var _zoom: float = 0.0


func _init() -> void:
	name = "WalkOverlay"
	tuning = BuilderTuning.load_default()
	guest_tuning = GuestTuning.load_default()
	visible = false
	set_process(false)


func _ready() -> void:
	follow()


## True while the Cart path brush is in Build's hand.
func in_hand() -> bool:
	return tool != null and tool.builder != null and tool.active \
			and tool.tool == BuildTool.Tool.PAINT and tool.surface == Surface.Type.CART_PATH


## The tool changed (its tool, surface or active flag; BuildTool calls it): shows and processes
## only with the brush in hand, measuring then.
func follow() -> void:
	var on := in_hand()
	set_process(on)
	if on:
		refresh()
	elif visible or not walks.is_empty():
		visible = false
		walks = []
		_key = []
		queue_redraw()


## Measures the walks again if what they read changed since the last time, and redraws then.
## Returns true when it did. _process calls it every frame in hand; tests call it at once.
func refresh() -> bool:
	if not in_hand():
		follow()
		return false
	var key: Array = _state_key()
	if key == _key:
		return false
	_key = key
	_measure()
	queue_redraw()
	return true


func _process(_delta: float) -> void:
	refresh()
	if visible and not walks.is_empty():
		var z: float = _view_scale()
		if not is_equal_approx(z, _zoom):
			_zoom = z
			queue_redraw()


## What the walks read: the course (any tile write moves its revision: a walk's time reads every
## tile under it), its holes and its clubhouse door.
func _state_key() -> Array:
	var c: CourseData = tool.builder.course
	var holes: Array = []
	for h: HoleData in c.holes:
		holes.append([h.number, h.tee, h.cup, h.open])
	return [c.get_instance_id(), c.revision, c.bridge_revision, holes, c.has_clubhouse(),
			c.clubhouse_door() if c.has_clubhouse() else Vector2i(-1, -1)]


func _measure() -> void:
	measure_count += 1
	visible = true
	var c: CourseData = tool.builder.course
	if c != _course:
		_course = c
		_field = HeightField.new(c, BallParams.load_default())
	var ypt: float = _field.yards_per_tile
	var limit: float = GuestReaction.walk_limit(guest_tuning.patience_min, guest_tuning)
	walks = []
	for w: Dictionary in GuestWalk.round_walks(c, ypt):
		var walk := GuestWalk.route(c, w.from, w.to, guest_tuning, ypt, _cache)
		var out: Dictionary = w.duplicate()
		out["points"] = walk.points
		out["duration"] = walk.duration
		out["reason"] = null
		out["detail"] = ""
		if walk.on_path:
			out["state"] = State.SERVED
			out["label"] = "%.1f s on the path" % walk.duration
		elif walk.duration > limit + GuestReaction.EPS:
			var why := GuestWalk.why(c, w.from, w.to, guest_tuning, ypt, _cache)
			out["state"] = State.LONG
			out["reason"] = why
			out["label"] = "%.1f s walk" % walk.duration
			out["detail"] = why.text(
					GuestReaction.walk_start_name(int(w.from_hole) <= 0, int(w.from_hole)),
					GuestReaction.walk_end_name(int(w.to_hole)))
		else:
			out["state"] = State.QUICK
			out["label"] = "%.1f s walk" % walk.duration
		walks.append(out)


## The walk shown into the tee of hole `number`, or an empty Dictionary.
func walk_to(number: int) -> Dictionary:
	for w: Dictionary in walks:
		if int(w.to_hole) == number:
			return w
	return {}


## For a walk whose path stops short (Reason SHORT): screen points from the path's tile nearest
## the end it misses to that end, on the ground; else empty.
func gap_points(w: Dictionary) -> PackedVector2Array:
	var why: GuestWalk.Reason = w.reason
	if why == null or why.kind != GuestWalk.Reason.Kind.SHORT or why.near_tile.x < 0:
		return PackedVector2Array()
	var end: Vector2 = (w.from if why.at_start else w.to) / _field.yards_per_tile - Vector2(0.5, 0.5)
	return PackedVector2Array([_ground(Vector2(why.near_tile)), _ground(end)])


## The colour of a walk in `state`.
func state_color(state: int) -> Color:
	match state:
		State.SERVED:
			return tuning.walk_served_color
		State.LONG:
			return tuning.walk_long_color
	return tuning.walk_quick_color


## Walk `w`'s route on the ground, screen points, cut every STEP_TILES.
func route_points(w: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pts: PackedVector2Array = w.points
	var ypt: float = _field.yards_per_tile
	for i: int in range(1, pts.size()):
		var a: Vector2 = pts[i - 1] / ypt - Vector2(0.5, 0.5)
		var b: Vector2 = pts[i] / ypt - Vector2(0.5, 0.5)
		var steps: int = maxi(1, ceili(a.distance_to(b) / STEP_TILES))
		for k: int in steps + 1:
			if k == 0 and i > 1:
				continue
			out.append(_ground(a.lerp(b, float(k) / steps)))
	return out


## The screen point of tile position `t` (integer = tile centre) on the drawn ground.
func _ground(t: Vector2) -> Vector2:
	var y: Vector2 = (t + Vector2(0.5, 0.5)) * _field.yards_per_tile
	return Iso.tile_to_screen(t, _field.drawn_steps(y.x, y.y))


## The point halfway along polyline `pts` by length.
static func midpoint(pts: PackedVector2Array) -> Vector2:
	var total := 0.0
	for i: int in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var left := total * 0.5
	for i: int in range(1, pts.size()):
		var d := pts[i - 1].distance_to(pts[i])
		if d >= left and d > 0.0:
			return pts[i - 1].lerp(pts[i], left / d)
		left -= d
	return pts[pts.size() - 1] if not pts.is_empty() else Vector2.ZERO


func _draw() -> void:
	if not visible or walks.is_empty() or _field == null:
		return
	var z: float = _view_scale()
	_zoom = z
	var px: float = 1.0 / z
	var font: Font = ThemeDB.fallback_font
	var halo: Color = tuning.ruler_halo_color
	var lines: Array[PackedVector2Array] = []
	for w: Dictionary in walks:
		lines.append(route_points(w))
	# Every halo first, so a crossing walk's colour is never cut by another's edge. Red last, on top.
	for pts: PackedVector2Array in lines:
		draw_polyline(pts, halo, (tuning.walk_width_px + 2.0 * tuning.walk_halo_px) * px)
	for state: int in [State.QUICK, State.SERVED, State.LONG]:
		for i: int in walks.size():
			var w: Dictionary = walks[i]
			if int(w.state) != state:
				continue
			var col: Color = state_color(state)
			var pts: PackedVector2Array = lines[i]
			draw_polyline(pts, col, tuning.walk_width_px * px)
			for end: Vector2 in [pts[0], pts[pts.size() - 1]]:
				draw_circle(end, (tuning.walk_width_px + END_DOT_PX) * px, halo)
				draw_circle(end, (tuning.walk_width_px + END_DOT_PX - 1.0) * px, col)
	# Where a path stops short: a dashed line from its nearest tile to the end it misses.
	for w: Dictionary in walks:
		var gap: PackedVector2Array = gap_points(w)
		if gap.is_empty():
			continue
		var dash: float = GAP_DASH_PX * px
		draw_dashed_line(gap[0], gap[1], halo, (tuning.walk_width_px + 2.0 * tuning.walk_halo_px) * px,
				dash)
		draw_dashed_line(gap[0], gap[1], tuning.walk_long_color, tuning.walk_width_px * px, dash)
		draw_circle(gap[0], (tuning.walk_width_px + END_DOT_PX + 1.0) * px, halo)
		draw_circle(gap[0], (tuning.walk_width_px + END_DOT_PX) * px, tuning.walk_long_color)
	for state: int in [State.QUICK, State.SERVED, State.LONG]:
		for i: int in walks.size():
			var w: Dictionary = walks[i]
			if int(w.state) != state:
				continue
			var at: Vector2 = midpoint(lines[i])
			var text_col: Color = tuning.walk_long_text_color if state == State.LONG \
					else Color(state_color(state), 1.0)
			var texts := PackedStringArray([w.label as String])
			if not (w.detail as String).is_empty():
				texts.append(w.detail as String)
			var pts: PackedVector2Array = lines[i]
			var d: Vector2 = pts[pts.size() - 1] - pts[0]
			_label(font, texts, at, z, text_col, Color(state_color(state), 1.0), d.x * d.y < 0.0)


## Draws `texts` as left-aligned lines in an ink box edged in `edge`, its corner LABEL_LIFT_PX
## right of `at` (CourseView space) and that far below it (`below`) or above it, at the
## overlay's font size at zoom `z`, in `col`. A walk running up to the right takes its label
## below-right, one running down to the right above-right, so the line (and a gap's dot near
## it) is never under the words.
func _label(font: Font, texts: PackedStringArray, at: Vector2, z: float, col: Color,
		edge: Color, below: bool) -> void:
	var size: int = tuning.walk_font_px
	var line_h: float = size + 2.0
	var wdt: float = 0.0
	for t: String in texts:
		wdt = maxf(wdt, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var ascent: float = font.get_ascent(size)
	var h: float = line_h * texts.size() - 2.0 + 2.0 * LABEL_PAD_PX
	var corner := Vector2(LABEL_LIFT_PX, LABEL_LIFT_PX if below else -LABEL_LIFT_PX - h)
	draw_set_transform(at, 0.0, Vector2.ONE / z)
	var box := Rect2(corner, Vector2(wdt + 2.0 * LABEL_PAD_PX, h))
	draw_rect(box, Color(tuning.ruler_halo_color, LABEL_BOX_ALPHA))
	draw_rect(box, Color(edge, 0.6), false, 1.0)
	for i: int in texts.size():
		var o := corner + Vector2(LABEL_PAD_PX, LABEL_PAD_PX + ascent + line_h * i)
		draw_string_outline(font, o, texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				LABEL_OUTLINE_PX, Color(tuning.ruler_halo_color, LABEL_OUTLINE_ALPHA))
		draw_string(font, o, texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _view_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var s: float = get_global_transform_with_canvas().get_scale().x
	return s if s > 0.0 else 1.0
