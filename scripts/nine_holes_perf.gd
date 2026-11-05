extends SceneTree
## E3-S2: frame time and click-edit validator time with nine holes, in New sandbox on generated
## land (tests/fixtures/nine_holes.gd: LandGenerator seed 7, every parcel owned, nine open
## holes built through CourseBuilder). The figures go in docs/design.md Plot.
##
##   godot --headless --path . -s res://scripts/nine_holes_perf.gd   validator times only
##   godot --path . -s res://scripts/nine_holes_perf.gd              also frame times (a real
##                                                                   window, vsync off)
##
## Headless: CourseValidator.check_course alone, and a click edit (CourseBuilder.paint of one
## tile outside every footprint, which reruns the validator for all nine holes), each timed
## RUNS times; median, p95 and worst in ms. With a display: the main scene in a 1280 x 720
## SubViewport (as scripts/screenshot.gd) shows the course; idle frames at 1x and 0.5x, and
## frames in which a click edit goes through the build tool (press and release, so the view,
## the issue markers and the hole panel refresh too), mean and worst frame in ms; then the
## same click edits with every hole failing two rules (9 issue boxes of 2 lines, E3-S2 review).

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const RUNS: int = 40
const WARMUP_FRAMES: int = 60
const IDLE_FRAMES: int = 300
## Tiles a click edit paints: rough land below the nine rows, outside every footprint.
const EDIT_TILES: Array[Vector2i] = [Vector2i(64, 100), Vector2i(30, 110), Vector2i(100, 96)]

var _main: Main
var _viewport: SubViewport
var _phase: int = 0
var _frames: int = 0
var _last_usec: int = 0
var _samples: Array[float] = []
var _edit_samples: Array[float] = []
var _edits: int = 0
var _course: CourseData


func _initialize() -> void:
	_course = NineHoles.land(7)
	var b := CourseBuilder.new(_course)
	var opened: Array[int] = NineHoles.build(b)
	print("nine holes: %d open %s, issues %s" % [opened.size(), opened, _failing(b)])
	_time_validator(b)
	if DisplayServer.get_name() == "headless":
		quit(0 if opened.size() == 9 else 1)
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


func _failing(b: CourseBuilder) -> Dictionary:
	var out := {}
	for n: int in b.issues:
		if not (b.issues[n] as Array).is_empty():
			out[n] = (b.issues[n] as Array).map(func(i: CourseValidator.Issue) -> String: return str(i))
	return out


func _time_validator(b: CourseBuilder) -> void:
	var check: Array[float] = []
	var edit: Array[float] = []
	for i: int in RUNS:
		var t0 := Time.get_ticks_usec()
		b.validator.check_course(_course)
		check.append((Time.get_ticks_usec() - t0) / 1000.0)
		var cell: Vector2i = EDIT_TILES[i % EDIT_TILES.size()]
		var s: Surface.Type = Surface.Type.FAIRWAY if i % 2 == 0 else Surface.Type.ROUGH
		t0 = Time.get_ticks_usec()
		b.paint(cell, s, 1)
		edit.append((Time.get_ticks_usec() - t0) / 1000.0)
	var still_open: int = 0
	for h: HoleData in _course.holes:
		still_open += 1 if h.open else 0
	print("check_course, 9 holes: %s" % _stats(check))
	print("click edit (paint 1 tile, validator rerun), 9 holes: %s; %d holes still open" % [_stats(edit), still_open])


func _stats(ms: Array[float]) -> String:
	var s: Array[float] = ms.duplicate()
	s.sort()
	var total: float = 0.0
	for v: float in s:
		total += v
	return "median %.2f ms, mean %.2f, p95 %.2f, worst %.2f (n %d)" % [
		s[s.size() / 2], total / s.size(), s[mini(int(s.size() * 0.95), s.size() - 1)], s[-1], s.size()]


func _process(_delta: float) -> bool:
	if _main == null:
		return false
	var now := Time.get_ticks_usec()
	var frame_ms: float = (now - _last_usec) / 1000.0
	_last_usec = now
	_frames += 1
	match _phase:
		0:  # warm up at 1x on hole 1
			if _frames == 1:
				_main.camera.set_zoom_index(1)
			if _frames >= WARMUP_FRAMES:
				_next_phase()
		1, 2:  # idle at 1x, then 0.5x
			if _frames > 2:
				_samples.append(frame_ms)
			if _frames >= IDLE_FRAMES:
				print("idle frames at %sx: %s" % ["1" if _phase == 1 else "0.5", _stats(_samples)])
				_next_phase()
				if _phase == 2:
					_main.camera.set_zoom_index(0)
				else:
					_main.camera.set_zoom_index(1)
		3:  # a click edit every 10th frame at 1x: time the frame after it was applied
			if _frames % 10 == 1 and _frames > 1:
				_edit_samples.append(frame_ms)
			if _frames % 10 == 0:
				var cell: Vector2i = EDIT_TILES[_edits % EDIT_TILES.size()]
				_main.build_tool.select_surface(Surface.Type.FAIRWAY if _edits % 2 == 0 else Surface.Type.ROUGH)
				var at: Vector2 = Iso.tile_to_screen(Vector2(cell), _course.get_height(cell.x, cell.y)) + Vector2(0.5, 0.5)
				var t0 := Time.get_ticks_usec()
				_main.build_tool.press_at(at)
				_main.build_tool.release()
				_samples.append((Time.get_ticks_usec() - t0) / 1000.0)
				_edits += 1
			if _edits >= RUNS and _frames % 10 == 1:
				print("click edit in the main scene (tool, builder, view, panel): %s" % _stats(_samples))
				print("frame holding a click edit, 1x: %s" % _stats(_edit_samples))
				_fail_every_hole()
				_next_phase()
				_edits = 0
				_edit_samples.clear()
		4:  # the same with every hole failing two rules (cup on rough, wrong par): 9 issue
			# boxes of 2 lines each, the camera on the map's centre
			if _frames % 10 == 1 and _frames > 1:
				_edit_samples.append(frame_ms)
			if _frames % 10 == 0:
				var cell: Vector2i = EDIT_TILES[_edits % EDIT_TILES.size()]
				_main.build_tool.select_surface(Surface.Type.FAIRWAY if _edits % 2 == 0 else Surface.Type.ROUGH)
				var at: Vector2 = Iso.tile_to_screen(Vector2(cell), _course.get_height(cell.x, cell.y)) + Vector2(0.5, 0.5)
				var t0 := Time.get_ticks_usec()
				_main.build_tool.press_at(at)
				_main.build_tool.release()
				_samples.append((Time.get_ticks_usec() - t0) / 1000.0)
				_edits += 1
			if _edits >= RUNS and _frames % 10 == 1:
				print("every hole failing (%d issue boxes): click edit in the main scene: %s" % [
					_main.course_view.issue_markers().size(), _stats(_samples)])
				print("every hole failing: frame holding a click edit, 1x: %s" % _stats(_edit_samples))
				quit(0)
	return false


## Paints every hole's cup rough and gives it a par its yardage does not match, through the
## main scene's builder, so every hole fails rules 2 and 4 (and closes), and centres the camera
## on the map.
func _fail_every_hole() -> void:
	var b: CourseBuilder = _main.build_tool.builder
	for spec: Array in NineHoles.HOLES:
		b.paint(spec[3], Surface.Type.ROUGH, 1)
		b.set_par(spec[0], 5 if spec[1] != 5 else 3)
	_main.camera.frame(_main.course_view.screen_bounds())
	_main.camera.set_zoom_index(1)


func _next_phase() -> void:
	_phase += 1
	_frames = 0
	_samples.clear()
