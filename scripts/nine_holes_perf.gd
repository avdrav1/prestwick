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
## the frame holding its undo are timed. E3-S16 review: then a drag of fairway off every line
## (brush 5, about 570 tiles below the nine rows) and its undo, so holes stay open and guests
## stay on the course through the undo; the frames holding its drag_to calls and its undo, the
## calls alone, and the guest CPU in those frames.
##
## E3-S14: headless adds a whole guest day (seeds 1 and 2) in frames of 1/60 and 1/30 s at 3x
## with no scene: each frame's guest work in ms and ticks, the frames over
## `frame_guest_ms_max` (data/guests.json) and how late the day ran (frames a due step waited
## for its Ball work, GuestBrain.held_frames). With a display, after the off-line drags, the
## main scene goes to Play with a fresh guest day (GuestSim) stepped until all 16 guests are
## out, then runs 3x in frames of 1/60 s (GuestSim.advance, timed alone) with the guests
## drawn (GuestView), at 1x and 0.5x; then back in Build every hole but hole 1 fails two
## rules and the click edits run with a fresh day of guests playing hole 1 (the script's own
## GuestBrain, as in the other Build phases). The run fails (exit 1) when a 3x frame's guest
## work at 60 fps passes `frame_guest_ms_max`.
##
## E3-S15: in either mode, before the rest, the guests' two searches under load with no scene
## (_time_searches): the cart path search on a dense painted lattice and Interesting's safe
## route on a map whose trees walls make it flood, each with whole guest days running at 3x.
## Each day counts its frames past `frame_guest_ms_max`, as _time_guest_frames does; the run
## fails (exit 1) when a lattice frame passes it (the cart path search is bounded so it does
## not). E3-S34: the flooded map's fail it too: Interesting's safe route reads the map's parts,
## labelled once per terrain (HoleChecks.route_parts), so a step that judges several freshly
## measured holes floods once, not once a hole (5 to 7 ms each before).

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const RUNS: int = 40
## Simulated seconds the guest day is stepped before the first frame (arrivals run to 90 s).
const GUEST_START_S: int = 45
## Simulated seconds a fresh guest day is stepped after each breaking drag's undo, in a frame
## that is not timed: the release closes every hole and sends every guest home, so without it
## the next release would be timed on an empty course (E3-S12 review); 14 to 16 guests are out.
const GUEST_REFRESH_S: int = 80
## E3-S16 review: the off-line drag runs along this row, below hole 9 (row 72) and every
## footprint, from x OFF_LINE_X0 to OFF_LINE_X1 with brush 5, so every hole stays open.
const OFF_LINE_ROW: int = 100
const OFF_LINE_X0: int = 8
const OFF_LINE_X1: int = 120
## E3-S14: frames of Play at 3x at each zoom, and the simulated second the main scene's day is
## stepped to first (every group has arrived by 90 s).
const PLAY_FRAMES: int = 600
const PLAY_START_S: int = 92
## Frames one breaking-drag cycle takes: press, 8 drag frames, release, undo, settle.
const DRAG_CYCLE: int = 16
const WARMUP_FRAMES: int = 60
## E3-S15: the flooded map's trees walls (columns), and how often its guest days get a click edit.
const SEARCH_WALL_X: Array[int] = [37, 106]
const SEARCH_EDIT_FRAMES: int = 60
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
## E3-S16: the drag_to and undo calls alone (tool, builder, view), and the guest CPU in the
## frames holding them.
var _drag_calls: Array[float] = []
var _undo_calls: Array[float] = []
var _drag_guest_ms: Array[float] = []
var _undo_guest_ms: Array[float] = []
## E3-S14: Play frames (3x, 60 fps) whose guest work passed frame_guest_ms_max; and, beside
## _guest_ms in Play, whether each frame ran a step.
var _play_over: int = 0
## E3-S15 review: lattice guest-day frames (3x, 60 fps) whose guest work passed
## frame_guest_ms_max; since E3-S34 the flooded map's too.
var _search_over: int = 0
var _guest_stepped: Array[bool] = []


func _initialize() -> void:
	_course = NineHoles.land(7)
	var b := CourseBuilder.new(_course)
	var opened: Array[int] = NineHoles.build(b)
	print("nine holes: %d open %s, issues %s" % [opened.size(), opened, _failing(b)])
	_time_validator(b)
	_time_break_drag(b)
	_model = ShotModel.new()
	_guest_tuning = GuestTuning.load_default()
	_time_searches()
	if DisplayServer.get_name() == "headless":
		var over := _time_guest_frames()
		quit(0 if opened.size() == 9 and over == 0 and _search_over == 0 else 1)
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


## E3-S14: whole guest days in frames at 3x, no scene. Returns the 60 fps frames whose guest
## work passed frame_guest_ms_max.
func _time_guest_frames() -> int:
	var over_60 := 0
	var budget := _guest_tuning.frame_guest_ms_max
	for fps: float in [60.0, 30.0]:
		for day: int in [1, 2]:
			var brain := GuestBrain.new(_course, day, _guest_tuning, _model)
			var ms: Array[float] = []
			var ticks: Array[float] = []
			var over := 0
			while not brain.day_over:
				var t0 := Time.get_ticks_usec()
				brain.advance_real(1.0 / fps, 3.0)
				var d: float = (Time.get_ticks_usec() - t0) / 1000.0
				ms.append(d)
				ticks.append(float(brain.frame_ticks))
				over += 1 if d > budget else 0
			if fps == 60.0:
				over_60 += over
			var on_time: int = ceili((_guest_tuning.day_s + 1.0) * fps / 3.0)
			# E3-S35: a frame's tick budget goes with its length (frame_ticks_per_real_s).
			var frame_budget := mini(ceili(_guest_tuning.frame_ticks_per_real_s / fps - 1e-6),
					_guest_tuning.frame_ticks_max)
			var scaled := ms.filter(func(v: float) -> bool: return v > budget * 60.0 / fps).size()
			print("guest day %d at 3x, %d fps: guest work a frame %s; ticks a frame median %d, p95 %d, worst %d (the frame's budget %d); %d frames over %.1f ms (%d over %.1f ms, the same share of the frame); %d frames, %d on time (%d a step waited, %.1f%% late)" % [
				day, fps, _stats(ms), _q(ticks, 0.5), _q(ticks, 0.95), _q(ticks, 1.0),
				frame_budget, over, budget, scaled, budget * 60.0 / fps, ms.size(), on_time,
				brain.held_frames, 100.0 * (ms.size() - on_time) / on_time])
	return over_60


## E3-S15: the guests' two searches under load, guests running (in either mode, no scene):
## the cart path search on a dense painted lattice and Interesting's safe route on a map it
## floods. Each course is the nine-hole fixture on its own land; a whole guest day (seeds 1
## and 2) runs at 3x in frames of 1/60 s with a click edit off every line every
## SEARCH_EDIT_FRAMES frames (untimed), so the terrain changes as it does in Build; each
## frame's guest work is timed, and the frames past 16.7 ms and past `frame_guest_ms_max`
## counted (past `frame_guest_ms_max` they go to _search_over and fail the run). Then each search alone,
## RUNS times: the walks the day's groups make between holes and along them (no cache), and
## each hole's statics measured afresh (HoleChecks.measure).
func _time_searches() -> void:
	var lat := NineHoles.land(7)
	var lb := CourseBuilder.new(lat)
	_paint_lattice(lb)
	var lat_open: Array[int] = NineHoles.build(lb)
	var path_tiles := _count_surface(lat, Surface.Type.CART_PATH)
	print("E3-S15 cart path lattice: %d path tiles (x or y a multiple of 3, painted before the holes), %d holes open" % [
		path_tiles, lat_open.size()])
	_time_search_walks(lat)
	_search_over = _time_search_day("cart path lattice", lat, lb)
	var fl := NineHoles.land(7)
	var fb := CourseBuilder.new(fl)
	NineHoles.build(fb)
	var fl_open := _paint_walls(fb)
	print("E3-S15 flooded map: trees walls at x %s, gap at row %d, %d holes open" % [
		SEARCH_WALL_X, fl.height - 1, fl_open])
	_time_search_statics(fl)
	var fl_over := _time_search_day("flooded map", fl, fb)
	print("E3-S15 3x guest frames over %.1f ms: cart path lattice %d, flooded map %d (any fails the run)" % [
		_guest_tuning.frame_guest_ms_max, _search_over, fl_over])
	_search_over += fl_over


## Paints cart path on every tile of `b`'s course whose x or y is a multiple of 3 (9,159 tiles
## on 128 x 128, E3 review's lattice), as one stroke; the holes painted after it cut it into
## bands, so many walks have a path tile at one end that no path joins to the other.
func _paint_lattice(b: CourseBuilder) -> void:
	var c := b.course
	b.begin_stroke()
	for y: int in c.height:
		for x: int in c.width:
			if x % 3 == 0 or y % 3 == 0:
				b.paint(Vector2i(x, y), Surface.Type.CART_PATH, 1)
	b.end_stroke()


func _count_surface(c: CourseData, s: Surface.Type) -> int:
	var n := 0
	for y: int in c.height:
		for x: int in c.width:
			n += 1 if c.get_surface(x, y) == s else 0
	return n


## Trees walls down columns SEARCH_WALL_X from row 0 to the second last, so a hole whose line
## crosses one (8 of the 9) has a hazard on its line and its only safe route round the wall's
## far end: Interesting's search floods most of the map. The walls close the holes they cross
## (footprint edits), so every hole is opened again. Returns the holes open.
func _paint_walls(b: CourseBuilder) -> int:
	var c := b.course
	b.begin_stroke()
	for x: int in SEARCH_WALL_X:
		for y: int in c.height - 1:
			b.paint(Vector2i(x, y), Surface.Type.TREES, 1)
	b.end_stroke()
	var n := 0
	for spec: Array in NineHoles.HOLES:
		n += 1 if b.open_hole(spec[0]) else 0
	return n


## A whole guest day (seeds 1 and 2) on `c` at 3x in 1/60 s frames, a click edit off every
## line every SEARCH_EDIT_FRAMES frames; each frame's guest work. Returns the frames, over
## both days, whose guest work passed frame_guest_ms_max.
func _time_search_day(what: String, c: CourseData, b: CourseBuilder) -> int:
	var over := 0
	for day: int in [1, 2]:
		var brain := GuestBrain.new(c, day, _guest_tuning, _model)
		var ms: Array[float] = []
		var step_ms: Array[float] = []
		var frames := 0
		var edits := 0
		var measured := 0
		var statics_ms: Array[float] = [0.0]
		while not brain.day_over:
			frames += 1
			if frames % SEARCH_EDIT_FRAMES == 0:
				var cell: Vector2i = EDIT_TILES[edits % EDIT_TILES.size()]
				b.paint(cell, Surface.Type.FAIRWAY if edits % 2 == 0 else Surface.Type.ROUGH, 1)
				edits += 1
			var t0 := Time.get_ticks_usec()
			var stepped := brain.advance_real(1.0 / 60.0, 3.0)
			var d: float = (Time.get_ticks_usec() - t0) / 1000.0
			ms.append(d)
			if stepped > 0:
				step_ms.append(d)
			if brain.checks.measured > measured:
				statics_ms.append(d)
				measured = brain.checks.measured
		over += _over(ms)
		print("E3-S15 %s, guest day %d at 3x, 60 fps, %d click edits: guest work a frame %s; frames that ran a step %s; %d frames over 16.7 ms, %d over frame_guest_ms_max %.1f ms (%d of them measuring a hole); %d holes' statics measured, in frames %s; %d reactions; %d path searches kept at dusk" % [
			what, day, edits, _stats(ms), _stats(step_ms), ms.filter(func(v: float) -> bool: return v > 16.7).size(),
			_over(ms), _guest_tuning.frame_guest_ms_max, _over(statics_ms),
			measured, _stats(statics_ms), _reactions(brain), brain.route_cache_size()])
	return over


func _reactions(brain: GuestBrain) -> int:
	var n := 0
	for g: Guest in brain.guests:
		n += g.records.size()
	return n


## The cart path search alone (no cache), RUNS times each: every hole's cup to the next
## hole's tee, and every hole's tee to points along its line (a guest walking to its ball).
func _time_search_walks(c: CourseData) -> void:
	var ypt := 5.0
	var pairs: Array = []
	for k: int in NineHoles.HOLES.size():
		var tee: Vector2i = NineHoles.HOLES[k][2]
		var cup: Vector2i = NineHoles.HOLES[k][3]
		if k > 0:
			pairs.append([NineHoles.HOLES[k - 1][3], tee])
		for f: float in [0.25, 0.5, 0.75, 1.0]:
			pairs.append([tee, Vector2i(Vector2(tee).lerp(Vector2(cup), f))])
	var grid_ms: Array[float] = []
	for i: int in RUNS / 4:
		var t0 := Time.get_ticks_usec()
		GuestWalk.path_grid(c)
		grid_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	print("E3-S15 cart path lattice: the path grid, read once per course revision: %s" % _stats(grid_ms))
	var cache := GuestWalk.Cache.new()
	var each: Array[float] = []
	var unbounded: Array[float] = []
	var on_path := 0
	for pair: Array in pairs:
		var from := (Vector2(pair[0]) + Vector2(0.5, 0.5)) * ypt
		var to := (Vector2(pair[1]) + Vector2(0.5, 0.5)) * ypt
		var runs: Array[float] = []
		var full: Array[float] = []
		var w: GuestWalk
		var a := GuestWalk._nearest_path_tile(c, from, _guest_tuning.cart_path_reach_yd, ypt)
		var b := GuestWalk._nearest_path_tile(c, to, _guest_tuning.cart_path_reach_yd, ypt)
		for i: int in RUNS / 4:
			cache.searches.clear()  # the grid stays: the search alone
			var t0 := Time.get_ticks_usec()
			w = GuestWalk.route(c, from, to, _guest_tuning, ypt, cache)
			runs.append((Time.get_ticks_usec() - t0) / 1000.0)
			if a.x >= 0 and b.x >= 0 and a != b:
				t0 = Time.get_ticks_usec()
				GuestWalk._search(c, a, b, -1, cache.grid)
				full.append((Time.get_ticks_usec() - t0) / 1000.0)
		runs.sort()
		each.append(runs[runs.size() / 2])
		if not full.is_empty():
			full.sort()
			unbounded.append(full[full.size() / 2])
		on_path += 1 if w.on_path else 0
	print("E3-S15 cart path lattice: one walk's route alone (median of %d runs each; %d walks, %d on the path): %s; the same searches with no bound (%d with path tiles at both ends) %s" % [
		RUNS / 4, pairs.size(), on_path, _stats(each), unbounded.size(), _stats(unbounded)])


## Interesting's safe route alone: every hole's statics measured afresh, RUNS times each.
func _time_search_statics(c: CourseData) -> void:
	var checks := HoleChecks.new(_guest_tuning, _model.params)
	var each: Array[float] = []
	var floods := 0
	for h: HoleData in c.holes:
		var runs: Array[float] = []
		var s: HoleChecks.Statics
		for i: int in RUNS / 4:
			var t0 := Time.get_ticks_usec()
			s = checks.measure(c, h)
			runs.append((Time.get_ticks_usec() - t0) / 1000.0)
		runs.sort()
		each.append(runs[runs.size() / 2])
		floods += 1 if s.hazard_on_line else 0
	print("E3-S15 flooded map: one hole's statics measured afresh (hazard grid, its parts and safe route; median of %d runs each; %d holes, %d with a hazard on the line): %s" % [
		RUNS / 4, c.holes.size(), floods, _stats(each)])
	# E3-S34: the parts of one terrain, then each hole's statics on them (as a step after an edit
	# judges them), against the breadth-first search each hole ran before.
	var grid_ms: Array[float] = []
	var parts_ms: Array[float] = []
	var cached_ms: Array[float] = []
	var bfs_ms: Array[float] = []
	for i: int in RUNS / 4:
		var t0 := Time.get_ticks_usec()
		var hazard := HoleChecks.hazard_grid(c)
		var t1 := Time.get_ticks_usec()
		HoleChecks.route_parts(c, hazard)
		var t2 := Time.get_ticks_usec()
		grid_ms.append((t1 - t0) / 1000.0)
		parts_ms.append((t2 - t1) / 1000.0)
		var key := "perf %d" % i
		for h: HoleData in c.holes:
			var t3 := Time.get_ticks_usec()
			checks.statics(c, h, key)
			cached_ms.append((Time.get_ticks_usec() - t3) / 1000.0)
			t3 = Time.get_ticks_usec()
			HoleChecks._route(c, hazard, h.tee, h.cup)
			bfs_ms.append((Time.get_ticks_usec() - t3) / 1000.0)
	print("E3-S34 flooded map: hazard grid %s; its parts labelled %s; each hole's statics after (the first of a terrain labels the parts) %s; the breadth-first safe route a hole, as before %s" % [
		_stats(grid_ms), _stats(parts_ms), _stats(cached_ms), _stats(bfs_ms)])


func _q(a: Array[float], q: float) -> int:
	var s: Array[float] = a.duplicate()
	s.sort()
	return int(s[mini(int(s.size() * q), s.size() - 1)])


## The tiles the breaking drag paints: the grid lines from cup to cup, in hole order.
func _break_cells() -> Dictionary:
	var out := {}
	for k: int in range(1, NineHoles.HOLES.size()):
		for cell: Vector2i in BuildTool.grid_line(NineHoles.HOLES[k - 1][3], NineHoles.HOLES[k][3]):
			out[cell] = true
	return out


## Point k (0 to 8) of the off-line drag: along OFF_LINE_ROW from OFF_LINE_X0 to OFF_LINE_X1.
func _off_line_cell(k: int) -> Vector2i:
	var steps: int = NineHoles.HOLES.size() - 1
	return Vector2i(OFF_LINE_X0 + (OFF_LINE_X1 - OFF_LINE_X0) * k / steps, OFF_LINE_ROW)


## Tiles the off-line drag paints (brush 5 along its row).
func _off_line_cells() -> int:
	return (OFF_LINE_X1 - OFF_LINE_X0 + 5) * 5


## A screen point the tile picker resolves to `cell` (searching up its top, as _cup_point).
func _tile_point(cell: Vector2i) -> Vector2:
	var top: Vector2 = Iso.tile_to_screen(Vector2(cell), _course.get_height(cell.x, cell.y))
	for dy: float in [0.5, -4.0, -8.0, -12.0, -14.0]:
		if TilePicker.pick(_course, top + Vector2(0.5, dy)) == cell:
			return top + Vector2(0.5, dy)
	push_error("no point picks %s" % cell)
	return top


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
	elif _phase == 9:
		_advance_budget_guests()
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
				var t0 := Time.get_ticks_usec()
				_main.build_tool.drag_to(_cup_point(f))
				_drag_calls.append((Time.get_ticks_usec() - t0) / 1000.0)
				_drag_guest_ms.append(_guest_ms[-1])
			elif f == n:
				_release_guests.append(_brain.on_course().size())
				var t0 := Time.get_ticks_usec()
				_main.build_tool.release()
				_release_samples.append((Time.get_ticks_usec() - t0) / 1000.0)
				if _edits == 0:
					print("drag breaking every hole: %d issue boxes after release, %d holes open" % [
						_main.course_view.issue_markers().size(), _open_count()])
			elif f == n + 3:
				var t0 := Time.get_ticks_usec()
				_main.build_tool.undo()
				_undo_calls.append((Time.get_ticks_usec() - t0) / 1000.0)
				_undo_guest_ms.append(_guest_ms[-1])
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
				print("drag breaking every hole: drag_to call (tool, builder, view) %s; guest CPU in its frame %s" % [
					_stats(_drag_calls), _stats(_drag_guest_ms)])
				print("drag breaking every hole: undo call (tool, builder, view, 528 tiles) %s; guest CPU in its frame %s" % [
					_stats(_undo_calls), _stats(_undo_guest_ms)])
				_print_guests("breaking drags")
				for a: Array in [_drag_calls, _undo_calls, _drag_guest_ms, _undo_guest_ms, _undo_samples]:
					a.clear()
				_release_guests.clear()
				_next_phase()
				_edits = 0
				_edit_samples.clear()
		8:  # E3-S16 review: a large drag off every line (fairway, brush 5, along OFF_LINE_ROW,
			# every DRAG_CYCLE frames: press (0), one drag_to a frame (1 to 8), release (9),
			# undo (12)), so every hole stays open and guests stay out through the undo; a fresh
			# guest day is stepped to GUEST_REFRESH_S in the phase's first frame (untimed), since
			# phase 7's last release sent every guest home
			var f: int = _frames % DRAG_CYCLE
			var n: int = NineHoles.HOLES.size()
			if _frames == 1:
				_brain = GuestBrain.new(_course, _day, _guest_tuning, _model)
				for i: int in GUEST_REFRESH_S:
					_brain.step()
			if _frames > DRAG_CYCLE:
				if f == n + 4:
					_undo_samples.append(frame_ms)
				elif f >= 1 and f < n:
					_samples.append(frame_ms)
			if _frames < DRAG_CYCLE:
				pass
			elif f == 0:
				_main.build_tool.select_surface(Surface.Type.FAIRWAY)
				_main.build_tool.brush_size = 5
				_main.build_tool.press_at(_tile_point(_off_line_cell(0)))
			elif f < n:
				var t0 := Time.get_ticks_usec()
				_main.build_tool.drag_to(_tile_point(_off_line_cell(f)))
				_drag_calls.append((Time.get_ticks_usec() - t0) / 1000.0)
				_drag_guest_ms.append(_guest_ms[-1])
			elif f == n:
				_main.build_tool.release()
				if _edits == 0:
					print("drag off every line: %d holes open after release, %d guests on the course" % [
						_open_count(), _brain.on_course().size()])
			elif f == n + 3:
				_release_guests.append(_brain.on_course().size())
				var t0 := Time.get_ticks_usec()
				_main.build_tool.undo()
				_undo_calls.append((Time.get_ticks_usec() - t0) / 1000.0)
				_undo_guest_ms.append(_guest_ms[-1])
				_edits += 1
			if _edits >= RUNS and f == n + 4:
				_release_guests.sort()
				print("drag off every line: frames holding a drag_to (brush 5, about 70 tiles each), 1x: %s" % _stats(_samples))
				print("drag off every line: frame holding its undo, 1x: %s; %d to %d guests on the course at undo, %d holes open after" % [
					_stats(_undo_samples), _release_guests[0], _release_guests[-1], _open_count()])
				print("drag off every line: drag_to call %s; guest CPU in its frame %s" % [
					_stats(_drag_calls), _stats(_drag_guest_ms)])
				print("drag off every line: undo call (tool, builder, view, %d tiles) %s; guest CPU in its frame %s" % [
					_off_line_cells(), _stats(_undo_calls), _stats(_undo_guest_ms)])
				_print_guests("off-line drags")
				_begin_budget_play()
				_next_phase()
				_edits = 0
				_edit_samples.clear()
		9:  # E3-S14: Play at 3x with the main scene's fresh day, all 16 guests out and drawn:
			# PLAY_FRAMES frames at 1x, then as many at 0.5x
			if _frames > 2:
				_samples.append(frame_ms)
			if _frames == PLAY_FRAMES or _frames == 2 * PLAY_FRAMES:
				var zoom: String = str(snappedf(_main.camera.zoom.x, 0.001))
				var steps: Array[float] = []
				for i: int in _guest_ms.size():
					if _guest_stepped[i]:
						steps.append(_guest_ms[i])
				print("Play at 3x, %sx zoom, all guests drawn: frame %s; guest work a frame (GuestSim.advance) %s; %d frames over %.1f ms (%d of them ran a step); frames that ran a step %s; day %d at %d s, %d on the course, %d drawn, %d on screen" % [
					zoom, _stats(_samples), _stats(_guest_ms), _over(_guest_ms),
					_guest_tuning.frame_guest_ms_max, _over(steps), _stats(steps),
					_main.guest_sim.day, _main.guest_sim.brain.second,
					_main.guest_sim.guests_on_course(), _main.guest_view.figures().size(),
					_on_screen()])
				_play_over += _over(_guest_ms)
				_samples.clear()
				_guest_ms.clear()
				_guest_stepped.clear()
				if _frames == PLAY_FRAMES:
					_set_play_zoom(0.5)
				else:
					_end_budget_play()
					_next_phase()
		10:  # every hole but hole 1 failing two rules (cup on rough, wrong par): 8 issue boxes
			# of 2 lines each, the camera on the map's centre, a fresh day of guests on hole 1
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
				print("every hole but hole 1 failing (%d issue boxes, %d open): click edit in the main scene: %s" % [
					_main.course_view.issue_markers().size(), _open_count(), _stats(_samples)])
				print("every hole but hole 1 failing: frame holding a click edit, 1x: %s" % _stats(_edit_samples))
				_print_guests("every hole but hole 1 failing")
				print("3x guest frames over %.1f ms in Play: %d" % [_guest_tuning.frame_guest_ms_max, _play_over])
				print("3x guest frames over %.1f ms on the cart path lattice and the flooded map: %d" % [_guest_tuning.frame_guest_ms_max, _search_over])
				quit(0 if _play_over == 0 and _search_over == 0 else 1)
	return false

	return false


## E3-S14: the main scene to Play, its own guest day (GuestSim) stepped until every guest of
## the day is out, run at 3x by this script (GuestSim.advance at 1/60 s a frame, timed alone)
## rather than by its own _process; the script's GuestBrain rests meanwhile.
func _begin_budget_play() -> void:
	_brain = null
	_guest_ms.clear()
	_main.set_mode(Main.Mode.PLAY)
	var sim: GuestSim = _main.guest_sim
	sim.set_process(false)
	sim.set_speed(3.0)
	sim.start(sim.course, sim.base_seed)  # E3-S9's Play phases ran day 1 on: start afresh
	sim.advance(0.0)  # builds day 1
	var all: int = _guest_tuning.arrivals_per_day
	while sim.brain.second < PLAY_START_S or (sim.guests_on_course() < all
			and sim.brain.second < _guest_tuning.arrival_window_s + 10.0):
		sim.brain.step()
	_set_play_zoom(1.0)


## Sets the camera to the zoom level `level` by value, not by index, so the Play phase measures
## the zoom it prints whatever steps camera.tres holds (E3-S14 review); quits 1 if it has none.
## It goes there as the player's own zoom key does (step_zoom), since in Play the aim fit
## (CourseCamera.set_lead) steps a set_zoom_index level out again until the tee and aim fit:
## before the review the "1x" pass was measured at 0.5x.
func _set_play_zoom(level: float) -> void:
	var i: int = -1
	for j: int in _main.camera.tuning.zoom_levels.size():
		if is_equal_approx(_main.camera.tuning.zoom_levels[j], level):
			i = j
	if i < 0:
		push_error("no %sx zoom step in camera tuning" % str(level))
		quit(1)
		return
	var d: int = 1 if i > 0 else -1
	_main.camera.set_zoom_index(i - d)
	_main.camera.step_zoom(d)


## Back to Build with every hole but hole 1 failing, and a fresh day of the script's own
## guests out on hole 1.
func _end_budget_play() -> void:
	_main.guest_sim.set_process(true)
	_main.set_mode(Main.Mode.BUILD)
	_fail_all_but_first_hole()
	_brain = GuestBrain.new(_course, _day, _guest_tuning, _model)
	for i: int in GUEST_START_S:
		_brain.step()


func _over(ms: Array[float]) -> int:
	return ms.filter(func(v: float) -> bool: return v > _guest_tuning.frame_guest_ms_max).size()


## The main scene's guest figures whose feet are in the view.
func _on_screen() -> int:
	var n: int = 0
	for f: GuestView.Figure in _main.guest_view.figures().values():
		n += 1 if _main.guest_view.on_screen(_main.guest_view.figure_screen(f)) else 0
	return n


## Paints the cup of every hole but hole 1 rough and gives it a par its yardage does not
## match, through the main scene's builder, so each fails rules 2 and 4 (and closes) while
## hole 1 stays open for guests, and centres the camera on the map.
func _fail_all_but_first_hole() -> void:
	var b: CourseBuilder = _main.build_tool.builder
	for spec: Array in NineHoles.HOLES:
		if spec[0] == 1:
			continue
		b.paint(spec[3], Surface.Type.ROUGH, 1)
		b.set_par(spec[0], 5 if spec[1] != 5 else 3)
	_main.camera.frame(_main.course_view.screen_bounds())
	_main.camera.set_zoom_level(1.0)



## E3-S14: the main scene's guest day by one frame of 1/60 s at 3x, timed alone, and whether
## the frame ran a step.
func _advance_budget_guests() -> void:
	var t1 := Time.get_ticks_usec()
	var stepped: int = _main.guest_sim.advance(1.0 / 60.0)
	_guest_ms.append((Time.get_ticks_usec() - t1) / 1000.0)
	_guest_stepped.append(stepped > 0)


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
