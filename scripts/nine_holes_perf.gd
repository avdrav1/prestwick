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
## E3-S9 (D45): idle Build frames at the farthest step, 0.175x, too, and Play frames at 0.175x
## and 0.5x with the main scene's own guest day (GuestSim) at 3x, stepped to GUEST_REFRESH_S so
## a full field (14 to 16 guests) is on the course and drawn, the camera on the map's centre.
##
## E3-S12: a guest day (GuestBrain, E3-S4) runs through every phase, stepped to GUEST_START_S
## first so groups are out on the course, then advanced each frame by 1/60 s of real time at 3x
## (GuestBrain.advance_real, as Play runs it, whatever the uncapped frame took; a new day when
## one ends), its CPU counted in the frame and printed per phase. Headless adds a drag that breaks every hole at once (one stroke of rough through all
## nine cups, then undone) through the builder, timed RUNS times. With a display the same drag
## goes through the build tool (press on cup 1, then one drag_to a frame through cups 2 to 9,
## release in the frame after the last), building nine new issue boxes at once, and the frame holding the release and
## the frame holding its undo are timed.

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const RUNS: int = 40
## Simulated seconds the guest day is stepped before the first frame (arrivals run to 90 s).
const GUEST_START_S: int = 45
## Simulated seconds a fresh guest day is stepped after each breaking drag's undo, in a frame
## that is not timed: the release closes every hole and sends every guest home, so without it
## the next release would be timed on an empty course (E3-S12 review); 14 to 16 guests are out.
const GUEST_REFRESH_S: int = 80
## Frames one breaking-drag cycle takes: press, 8 drag frames, release, undo, settle.
const DRAG_CYCLE: int = 16
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
var _brain: GuestBrain
var _day: int = 1
var _model: ShotModel
var _guest_tuning: GuestTuning
var _guest_ms: Array[float] = []
var _guest_frames: int = 0
var _undo_samples: Array[float] = []
var _release_samples: Array[float] = []
var _release_guests: Array[int] = []
var _shown: Array[int] = []


func _initialize() -> void:
	_course = NineHoles.land(7)
	var b := CourseBuilder.new(_course)
	var opened: Array[int] = NineHoles.build(b)
	print("nine holes: %d open %s, issues %s" % [opened.size(), opened, _failing(b)])
	_time_validator(b)
	_time_break_drag(b)
	_model = ShotModel.new()
	_guest_tuning = GuestTuning.load_default()
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
	_brain = GuestBrain.new(_course, _day, _guest_tuning, _model)
	for i: int in GUEST_START_S:
		_brain.step()


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


## A drag of rough through every cup, 1 tile wide (rule 2 fails for all nine holes), as one
## stroke through the builder, then its undo; each timed RUNS times.
func _time_break_drag(b: CourseBuilder) -> void:
	var drag: Array[float] = []
	var check: Array[float] = []
	var undo: Array[float] = []
	var failing: int = 0
	for i: int in RUNS:
		var t0 := Time.get_ticks_usec()
		b.begin_stroke()
		var from: Vector2i = NineHoles.HOLES[0][3]
		b.paint(from, Surface.Type.ROUGH, 1)
		for k: int in range(1, NineHoles.HOLES.size()):
			var to: Vector2i = NineHoles.HOLES[k][3]
			for cell: Vector2i in BuildTool.grid_line(from, to):
				if cell != from:
					b.paint(cell, Surface.Type.ROUGH, 1)
			from = to
		b.end_stroke()
		drag.append((Time.get_ticks_usec() - t0) / 1000.0)
		failing = 0
		for n: int in b.issues:
			failing += 0 if (b.issues[n] as Array).is_empty() else 1
		t0 = Time.get_ticks_usec()
		b.validator.check_course(_course)
		check.append((Time.get_ticks_usec() - t0) / 1000.0)
		t0 = Time.get_ticks_usec()
		b.undo()
		undo.append((Time.get_ticks_usec() - t0) / 1000.0)
	var still_open: int = 0
	for h: HoleData in _course.holes:
		still_open += 1 if h.open else 0
	print("drag breaking every hole (%d tiles of rough through 9 cups, %d holes failing): stroke with its validator rerun %s" % [
		_break_cells().size(), failing, _stats(drag)])
	print("check_course, every hole failing: %s" % _stats(check))
	print("undo of that drag, validator rerun: %s; %d holes open after" % [_stats(undo), still_open])


## The tiles the breaking drag paints: the grid lines from cup to cup, in hole order.
func _break_cells() -> Dictionary:
	var out := {}
	for k: int in range(1, NineHoles.HOLES.size()):
		for cell: Vector2i in BuildTool.grid_line(NineHoles.HOLES[k - 1][3], NineHoles.HOLES[k][3]):
			out[cell] = true
	return out


## A screen point the tile picker resolves to hole k's cup (a cup half behind higher ground
## in front, as hole 7's is, is picked near the back of its top).
func _cup_point(k: int) -> Vector2:
	var cell: Vector2i = NineHoles.HOLES[k][3]
	var top: Vector2 = Iso.tile_to_screen(Vector2(cell), _course.get_height(cell.x, cell.y))
	for dy: float in [0.5, -4.0, -8.0, -12.0, -14.0]:
		if TilePicker.pick(_course, top + Vector2(0.5, dy)) == cell:
			return top + Vector2(0.5, dy)
	push_error("no point picks cup %s" % cell)
	return top


## Advances the guest day by one frame of `delta` real seconds at 3x; a new day when it ends.
func _advance_guests() -> void:
	if _brain.day_over:
		_day += 1
		_brain = GuestBrain.new(_course, _day, _guest_tuning, _model)
	var t0 := Time.get_ticks_usec()
	_brain.advance_real(1.0 / 60.0, 3.0)
	_guest_ms.append((Time.get_ticks_usec() - t0) / 1000.0)


func _print_guests(phase: String) -> void:
	if not _guest_ms.is_empty():
		var b: GuestBrain = _main.guest_sim.brain if phase == "Play" else _brain
		print("  guests at 3x during %s: CPU a frame %s; day %d at %d s, %d on the course" % [
			phase, _stats(_guest_ms), _main.guest_sim.day if phase == "Play" else _day, b.second,
			b.on_course().size()])
	_guest_ms.clear()


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
	if _phase == 4 or _phase == 5:
		_advance_main_guests()
	else:
		_advance_guests()
	var now := Time.get_ticks_usec()
	var frame_ms: float = (now - _last_usec) / 1000.0
	_last_usec = now
	_frames += 1
	match _phase:
		0:  # warm up at 1x on hole 1
			if _frames == 1:
				_main.camera.set_zoom_level(1.0)
			if _frames >= WARMUP_FRAMES:
				_next_phase()
		1, 2, 3:  # idle in Build at 1x, then 0.5x, then the farthest zoom (D45) on the map's centre
			if _frames > 2:
				_samples.append(frame_ms)
			if _frames >= IDLE_FRAMES:
				print("idle frames in Build at %sx: %s" % [_main.camera.zoom.x, _stats(_samples)])
				_print_guests("idle")
				_next_phase()
				if _phase == 2:
					_main.camera.set_zoom_level(0.5)
				elif _phase == 3:
					_main.camera.frame(_main.course_view.screen_bounds())
					_main.camera.set_zoom_index(0)
				else:
					_begin_play_phase()
		4, 5:  # E3-S9 (D45): Play at the farthest zoom, then 0.5x, the whole map's guests shown
			# and the main scene's own day at 3x (_advance_main_guests)
			if _frames > 2:
				_samples.append(frame_ms)
				_shown.append(_main.guest_view.figures().size())
			if _frames >= IDLE_FRAMES:
				_shown.sort()
				print("Play frames at %sx, guests at 3x, %d to %d figures shown: %s" % [
					_main.camera.zoom.x, _shown[0], _shown[-1], _stats(_samples)])
				_print_guests("Play")
				_shown.clear()
				_next_phase()
				if _phase == 5:
					_main.camera.set_zoom_level(0.5)
				else:
					_main.set_mode(Main.Mode.BUILD)
					_main.guest_sim.set_process(true)
					_main.camera.frame(_main.course_view.screen_bounds())
					_main.camera.set_zoom_level(1.0)
		6:  # a click edit every 10th frame at 1x: time the frame after it was applied
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
				_print_guests("click edits")
				_main.camera.frame(_main.course_view.screen_bounds())
				_main.camera.set_zoom_level(1.0)
				_next_phase()
				_edits = 0
				_edit_samples.clear()
		7:  # a drag that breaks every hole at once, through the build tool, every DRAG_CYCLE
			# frames: press on cup 1 (frame 0), one drag_to a frame through cups 2 to 9 (1 to 8),
			# release (9: the check, nine new issue boxes), undo (12); time the frames holding
			# the release and the undo; a fresh guest day stepped to GUEST_REFRESH_S after the
			# undo (14, untimed), so guests are out at every release
			var f: int = _frames % DRAG_CYCLE
			var n: int = NineHoles.HOLES.size()
			if _frames > DRAG_CYCLE:
				if f == n + 1:
					_edit_samples.append(frame_ms)
				elif f == n + 4:
					_undo_samples.append(frame_ms)
				elif f >= 1 and f < n:
					_samples.append(frame_ms)
			if _frames < DRAG_CYCLE:
				pass
			elif f == 0:
				_main.build_tool.select_surface(Surface.Type.ROUGH)
				_main.build_tool.brush_size = 1
				_main.build_tool.press_at(_cup_point(0))
			elif f < n:
				_main.build_tool.drag_to(_cup_point(f))
			elif f == n:
				_release_guests.append(_brain.on_course().size())
				var t0 := Time.get_ticks_usec()
				_main.build_tool.release()
				_release_samples.append((Time.get_ticks_usec() - t0) / 1000.0)
				if _edits == 0:
					print("drag breaking every hole: %d issue boxes after release, %d holes open" % [
						_main.course_view.issue_markers().size(), _open_count()])
			elif f == n + 3:
				_main.build_tool.undo()
				_edits += 1
			elif f == n + 5:
				_brain = GuestBrain.new(_course, _day, _guest_tuning, _model)
				for i: int in GUEST_REFRESH_S:
					_brain.step()
			if _edits >= RUNS and f == n + 4:
				print("drag breaking every hole: frames holding a drag_to (about 60 tiles each), 1x: %s" % _stats(_samples))
				print("drag breaking every hole: release (validator rerun, view, 9 new boxes, panel) %s" % _stats(_release_samples))
				_release_guests.sort()
				print("drag breaking every hole: frame holding the release, 1x: %s; %d to %d guests on the course at release" % [
					_stats(_edit_samples), _release_guests[0], _release_guests[-1]])
				print("drag breaking every hole: frame holding its undo, 1x: %s; %d holes open after" % [
					_stats(_undo_samples), _open_count()])
				_print_guests("breaking drags")
				_fail_every_hole()
				_next_phase()
				_edits = 0
				_edit_samples.clear()
		8:  # the same with every hole failing two rules (cup on rough, wrong par): 9 issue
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
				_print_guests("every hole failing")
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
	_main.camera.set_zoom_level(1.0)


## E3-S9 (D45): Play on the nine holes with the main scene's own guest day (GuestSim), stepped
## to GUEST_REFRESH_S at 1x first so a full field is out (14 to 16 guests, E3-S9 review: at
## GUEST_START_S only 8 to 10 were), then run at 3x by _advance_main_guests; the
## camera holds the map's centre at the farthest zoom, so every guest on the course is drawn.
func _begin_play_phase() -> void:
	_main.set_mode(Main.Mode.PLAY)
	var sim: GuestSim = _main.guest_sim
	sim.set_process(false)
	sim.set_speed(1.0)
	for i: int in GUEST_REFRESH_S:
		sim.advance(1.0)
	sim.set_speed(3.0)
	_main.camera.frame(_main.course_view.screen_bounds())
	_main.camera.set_zoom_index(0)


## The main scene's guest day by one frame of 1/60 s of real time at 3x, its CPU counted.
func _advance_main_guests() -> void:
	var t0 := Time.get_ticks_usec()
	_main.guest_sim.advance(1.0 / 60.0)
	_guest_ms.append((Time.get_ticks_usec() - t0) / 1000.0)


func _open_count() -> int:
	var n: int = 0
	for h: HoleData in _course.holes:
		n += 1 if h.open else 0
	return n


func _next_phase() -> void:
	_phase += 1
	_frames = 0
	_samples.clear()
