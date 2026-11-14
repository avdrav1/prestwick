extends SceneTree
## E18-S5 (D71): the Build overlays that read the whole course, on an 18-hole course with a full
## field: the walk overlay (E12-S1, D68: every walk a round takes, routed, with the Cart path
## brush in hand) and the ruler and rings (E8-S5: with the Cup or Tee tool in hand and a hole
## picked). The main scene in a 1280 x 720 SubViewport (as scripts/nine_holes_perf.gd), vsync
## off, Build, the main scene's own guest day at 3x with the whole field out (as Build runs it
## since D53), the camera at `zoom` (default 0.5) on the clubhouse.
##
## Phases, each frame timed (median / p95, D52's 16.7 ms):
## - Cart path brush in hand, the cursor moving a tile a frame, nothing painted: the walks are
##   measured once when it is picked up (the call timed), then only compared each frame.
## - Cart path drags: a stroke of DRAG_TILES tiles, one tile a frame (each frame's paint moves the
##   course's revision, so the overlay measures every walk again in it; that refresh timed alone),
##   then its release and undo; CYCLES strokes.
## - The Cup tool in hand on hole RULER_HOLE, the cursor moving a tile a frame round its tee:
##   the ruler measures each frame (the refresh timed alone), the rings laid once.
## - The Tee tool in hand on the same hole, the cursor moving: the rings' labels placed each
##   frame the cursor moves.
## Headless it times the refreshes alone (no frames).
##
##   XDG_DATA_HOME=$(mktemp -d) godot --path . -s res://scripts/overlay_perf.gd \
##       [-- course=res://courses/old_grey_championship.json zoom=0.5]

const MAIN_SCENE := "res://scenes/main.tscn"
const COURSE := "res://courses/old_grey_championship.json"
const WARMUP_FRAMES: int = 60
const HOVER_FRAMES: int = 300
const DRAG_TILES: int = 60
const CYCLES: int = 3
## Frames after a release and after an undo before the next stroke (the release and undo frames
## are timed; the rest settle).
const SETTLE_FRAMES: int = 10
const RULER_HOLE: int = 10
## The drag's row and columns on Old Grey Links (Championship): below hole 4's line and above
## hole 18's, between hole 10's tee and the 17th green, so every hole stays open.
const DRAG_ROW: int = 129
const DRAG_X0: int = 16
## Simulated seconds the guest day is stepped before the first frame (as nine_holes_perf).
const GUEST_REFRESH_S: int = 80

var _main: Main
var _viewport: SubViewport
var _course: CourseData
var _path: String = COURSE
var _zoom: float = 0.5
var _phase: int = 0
var _frames: int = 0
var _last_usec: int = 0
var _samples: Array[float] = []
var _calls: Array[float] = []
var _guest_ms: Array[float] = []
var _release_frames: Array[float] = []
var _undo_frames: Array[float] = []
var _drag_calls: Array[float] = []
var _undo_calls: Array[float] = []
var _cycle: int = 0
var _ring: Array[Vector2i] = []
var _measures_before: int = 0
var _painted: int = 0
var _tuning: GuestTuning


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("course="):
			_path = arg.substr(7)
		elif arg.begins_with("zoom="):
			_zoom = arg.substr(5).to_float()
	print("load average at the start: %s" % _load_text())
	_course = CourseSave.load_file(_path)
	if _course == null:
		push_error("%s did not load" % _path)
		quit(2)
		return
	_tuning = GuestTuning.load_default()
	print("overlay perf: %s, %d x %d, %d holes (%d open), clubhouse %s, %s" % [_path, _course.width,
			_course.height, _course.holes.size(), _open(), _course.clubhouse, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		_headless()
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	_viewport.add_child(_main)
	_main.show_course.call_deferred(_course)


## Headless: the walks' and the ruler's measures alone, on a BuildTool with no scene.
func _headless() -> void:
	var b := CourseBuilder.new(_course)
	var t := BuildTool.new()
	t.builder = b
	root.add_child(t)
	var ms: Array[float] = []
	for i: int in 20:
		t.select_surface(Surface.Type.FAIRWAY)
		t.walks.follow()
		var t0 := Time.get_ticks_usec()
		t.select_surface(Surface.Type.CART_PATH)
		t.walks.refresh()
		ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	print("walk overlay, picked up (every walk measured): %s; %d walks" % [_stats(ms), t.walks.walks.size()])
	print("load average at the end: %s" % _load_text())
	t.free()
	quit(0)


func _process(_delta: float) -> bool:
	if _main == null or _main.course != _course:
		return false
	_advance_guests()
	var now := Time.get_ticks_usec()
	var frame_ms: float = (now - _last_usec) / 1000.0
	_last_usec = now
	_frames += 1
	var tool: BuildTool = _main.build_tool
	match _phase:
		0:
			if _frames == 1:
				_begin_field()
			if _frames >= WARMUP_FRAMES:
				_ring = _ring_cells()
				tool.select_surface(Surface.Type.FAIRWAY)
				_measures_before = tool.walks.measure_count
				var t0 := Time.get_ticks_usec()
				tool.select_surface(Surface.Type.CART_PATH)
				tool.walks.refresh()
				print("walk overlay picked up (Cart path brush): every walk measured in %.2f ms; %d walks, %d red, %d green" % [
					(Time.get_ticks_usec() - t0) / 1000.0, tool.walks.walks.size(),
					_count_state(WalkOverlay.State.LONG), _count_state(WalkOverlay.State.SERVED)])
				_next()
		1:  # the brush in hand, the cursor moving a tile a frame
			if _frames > 1:
				_samples.append(frame_ms)
			tool.hover_at(_tile_point(_ring[_frames % _ring.size()]))
			if _frames >= HOVER_FRAMES:
				print("Cart path brush in hand, the cursor moving, 1x frames at %sx: %s; walks measured %d times in them" % [
					_main.camera.zoom.x, _stats(_samples), tool.walks.measure_count - _measures_before - 1])
				_print_guests("brush in hand")
				_next()
		2:  # cart path strokes: press, a tile a frame, release, undo
			var f: int = (_frames - 1) % (DRAG_TILES + 2 * SETTLE_FRAMES + 2)
			var cell := Vector2i(DRAG_X0 + mini(f, DRAG_TILES - 1), DRAG_ROW)
			if f == 0:
				tool.press_at(_tile_point(cell))
			elif f < DRAG_TILES:
				if f > 1:
					_samples.append(frame_ms)  # the frame that held the previous drag_to
				var t1 := Time.get_ticks_usec()
				tool.drag_to(_tile_point(cell))
				_drag_calls.append((Time.get_ticks_usec() - t1) / 1000.0)
				var t0 := Time.get_ticks_usec()
				tool.walks.refresh()
				_calls.append((Time.get_ticks_usec() - t0) / 1000.0)
			elif f == DRAG_TILES:
				_samples.append(frame_ms)
				tool.release()
				_painted = _count_path()
			elif f == DRAG_TILES + 1:
				_release_frames.append(frame_ms)
			elif f == DRAG_TILES + SETTLE_FRAMES:
				var t0 := Time.get_ticks_usec()
				tool.undo()
				_undo_calls.append((Time.get_ticks_usec() - t0) / 1000.0)
			elif f == DRAG_TILES + SETTLE_FRAMES + 1:
				_undo_frames.append(frame_ms)
			elif f == DRAG_TILES + 2 * SETTLE_FRAMES + 1:
				_cycle += 1
				if _cycle >= CYCLES:
					print("Cart path drags (%d tiles a stroke, one a frame; %d path tiles after the stroke; %d holes open after the undo): frames holding a drag_to: %s" % [
						DRAG_TILES, _painted, _open(), _stats(_samples)])
					print("  the drag_to call (tool, builder, view): %s" % _stats(_drag_calls))
					print("  the walk overlay's refresh in them (every walk measured again): %s" % _stats(_calls))
					print("  frame holding the release: %s; frame holding the undo: %s; the undo call: %s" % [
						_stats(_release_frames), _stats(_undo_frames), _stats(_undo_calls)])
					_print_guests("cart path drags")
					_next()
					tool.select_hole(RULER_HOLE, _slot(RULER_HOLE))
					tool.select_tool(BuildTool.Tool.CUP)
					_measures_before = tool.ruler.measure_count
		3, 4:  # the Cup tool (ruler and rings), then the Tee tool (rings), the cursor moving
			if _frames > 1:
				_samples.append(frame_ms)
			tool.hover_at(_tile_point(_ring[_frames % _ring.size()]))
			var t0 := Time.get_ticks_usec()
			tool.ruler.refresh()
			_calls.append((Time.get_ticks_usec() - t0) / 1000.0)
			if _frames >= HOVER_FRAMES:
				var what := "Cup tool (ruler and rings)" if _phase == 3 else "Tee tool (rings)"
				print("%s on hole %d, the cursor moving a tile a frame round its tee, frames at %sx: %s; ruler shown %s, %d rings, measured %d times" % [
					what, RULER_HOLE, _main.camera.zoom.x, _stats(_samples), tool.ruler.ruler_shown,
					tool.ruler.rings.size(), tool.ruler.measure_count - _measures_before])
				print("  the ruler's refresh alone: %s" % _stats(_calls))
				_print_guests(what)
				_next()
				if _phase == 4:
					tool.select_tool(BuildTool.Tool.TEE)
					_measures_before = tool.ruler.measure_count
				else:
					print("load average at the end: %s" % _load_text())
					quit(0)
	return false


func _next() -> void:
	_phase += 1
	_frames = 0
	_samples.clear()
	_calls.clear()
	_guest_ms.clear()


## The main scene's day stepped until the whole field is out, then run at 3x a frame at a time
## by _advance_guests (its own _process off), as nine_holes_perf's Build field pass; the camera
## at `_zoom` on the clubhouse.
func _begin_field() -> void:
	var sim: GuestSim = _main.guest_sim
	sim.set_process(false)
	sim.set_speed(1.0)
	for i: int in GUEST_REFRESH_S:
		sim.advance(1.0)
	while sim.guests_on_course() < _tuning.arrivals_per_day and sim.brain.second < sim.brain.arrival_window_s + 10.0:
		sim.brain.step()
	sim.set_speed(3.0)
	_main.camera.set_zoom_level(_zoom)
	_main.camera.centre_on(Iso.tile_to_screen(Vector2(_course.clubhouse) + Vector2(10, 0), 0))


func _advance_guests() -> void:
	if _phase == 0 and _frames == 0:
		return
	var t0 := Time.get_ticks_usec()
	_main.guest_sim.advance(1.0 / 60.0)
	_guest_ms.append((Time.get_ticks_usec() - t0) / 1000.0)


func _print_guests(what: String) -> void:
	print("  guests at 3x during %s: CPU a frame %s; day at %d s, %d on the course" % [what,
			_stats(_guest_ms), _main.guest_sim.brain.second, _main.guest_sim.guests_on_course()])


## Tiles round hole RULER_HOLE's tee at 20 to 50 tiles (100 to 250 yd), on the map.
func _ring_cells() -> Array[Vector2i]:
	var h: HoleData = _course.holes[_slot(RULER_HOLE)]
	var out: Array[Vector2i] = []
	for k: int in 120:
		var a: float = TAU * k / 120.0
		var r: float = 20.0 + 30.0 * float(k % 7) / 6.0
		var cell := h.tee + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
		if _course.in_bounds(cell.x, cell.y):
			out.append(cell)
	return out


func _slot(number: int) -> int:
	for i: int in _course.holes.size():
		if _course.holes[i].number == number:
			return i
	return -1


func _open() -> int:
	var n := 0
	for h: HoleData in _course.holes:
		n += 1 if h.open else 0
	return n


func _count_state(s: int) -> int:
	var n := 0
	for w: Dictionary in _main.build_tool.walks.walks:
		n += 1 if w["state"] == s else 0
	return n


func _count_path() -> int:
	var n := 0
	for x: int in range(DRAG_X0, DRAG_X0 + DRAG_TILES):
		n += 1 if _course.get_surface(x, DRAG_ROW) == Surface.Type.CART_PATH else 0
	return n


## A point in the course's screen space the tile picker resolves to `cell` (nine_holes_perf's).
func _tile_point(cell: Vector2i) -> Vector2:
	var top: Vector2 = Iso.tile_to_screen(Vector2(cell), _course.get_height(cell.x, cell.y))
	for dy: float in [0.5, -4.0, -8.0, -12.0, -14.0]:
		if TilePicker.pick(_course, top + Vector2(0.5, dy)) == cell:
			return top + Vector2(0.5, dy)
	return top + Vector2(0.5, 0.5)


func _stats(ms: Array[float]) -> String:
	if ms.is_empty():
		return "none"
	var s := ms.duplicate()
	s.sort()
	var total := 0.0
	for v: float in s:
		total += v
	return "median %.2f ms, mean %.2f, p95 %.2f, worst %.2f (n %d)" % [s[int(s.size() / 2.0)],
			total / s.size(), s[mini(s.size() - 1, int(ceil(0.95 * s.size())) - 1)], s[-1], s.size()]


func _load_text() -> String:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	return f.get_line() if f != null else "unknown"
