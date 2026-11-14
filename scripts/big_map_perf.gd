extends SceneTree
## E18-S1 (D71): what a bigger map costs outside the frame loop of scripts/nine_holes_perf.gd.
## The map size comes from `map=WxH` (LandTuning's `map_size` and BuilderTuning's `plot_size`
## changed in the loaded resources for this run only; the files are not touched), 128 x 128
## when it is left out. Prints:
## - New course: LandGenerator.generate and CourseBuilder.new_course (land, block, clubhouse)
##   over SEEDS seeds, and the land each gives against docs/design.md Land's targets (trees,
##   water, high ground, the starting block's rough and water, the clubhouse placed).
## - The test course: the bare nine (tests/fixtures/nine_holes.gd, seed 7 on D26's block) and,
##   with `copies=2`, the nine again as holes 10 to 18 (max_holes 18 for the run), as
##   scripts/nine_holes_perf.gd lays them; its course file's size, and CourseSave.load_file and
##   CourseBuilder.new (the validator's first pass) RUNS times. `out=DIR` writes the file there
##   (absolute path; scripts/skip_perf.gd --course reads it).
## - Routing (D69): the dry search's reading of the course (GuestWalk.DryGrid, once per tile
##   revision) and the dry search alone (GuestWalk._dry_route) on every hole's walks, from the
##   clubhouse door to every tee, and corner to corner.
## - A 24-arrival day run by the brain alone (GuestBrain.run_day), the floor of skip to morning.
## - With a display: Main.show_course of a New course (seed 1 to 3) and of the test course, the
##   call and the frame after it (the view's chunks, trees and decor built).
##
## `counts=area` prints the land's count bounds (hills, tree stands, ponds; min and max), which
## since E18-S2 the generator scales by the map's area over 128 x 128's itself (D71,
## LandTuning.count); in E18-S1 the flag did the scaling, and runs without it kept 128's counts.
##
##   XDG_DATA_HOME=$(mktemp -d) godot [--headless] --path . -s res://scripts/big_map_perf.gd \
##       [-- map=192x192 copies=2 out=/abs/dir]

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const NinePerf := preload("res://scripts/nine_holes_perf.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const SEEDS: int = 10
const RUNS: int = 20
const ARRIVALS: int = 24
## As scripts/nine_holes_perf.gd's COPY_OFFSETS.
const COPY_OFFSETS: Dictionary = {Vector2i(192, 192): Vector2i(64, 100),
		Vector2i(256, 160): Vector2i(128, 80)}

var _map := Vector2i.ZERO
var _copies: int = 1
var _out: String = ""
var _scale_counts: bool = false
var _land_tuning: LandTuning
var _builder_tuning: BuilderTuning
var _course: CourseData
var _main: Main
var _frames: int = 0
var _shows: Array = []
var _show_ms: Array[float] = []
var _after_ms: Array[float] = []
var _last: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("map="):
			var wh: PackedStringArray = arg.substr(4).split("x")
			_map = Vector2i(wh[0].to_int(), wh[1].to_int())
		elif arg.begins_with("copies="):
			_copies = clampi(arg.substr(7).to_int(), 1, 2)
		elif arg.begins_with("out="):
			_out = arg.substr(4)
		elif arg == "counts=area":
			_scale_counts = true
	_land_tuning = LandTuning.load_default()
	_builder_tuning = BuilderTuning.load_default()
	if _map != Vector2i.ZERO:
		_land_tuning.map_size = _map
		_builder_tuning.plot_size = _map
	if _scale_counts:
		# E18-S2 (D71): the generator scales the counts by area itself (LandTuning.count), so
		# counts=area only prints them.
		var t := _land_tuning
		print("counts by area: hills %d to %d, stands %d to %d, ponds %d to %d" % [
				t.count(t.hill_count_min), t.count(t.hill_count_max), t.count(t.tree_stands_min),
				t.count(t.tree_stands_max), t.count(t.ponds_min), t.count(t.ponds_max)])
	if _copies > 1:
		if not COPY_OFFSETS.has(_map):
			push_error("copies=2 needs map= one of %s" % [COPY_OFFSETS.keys()])
			quit(2)
			return
		_builder_tuning.max_holes = 9 * _copies
	print("big map perf: %d x %d, load %s, %s" % [_land_tuning.map_size.x, _land_tuning.map_size.y,
			_load(), DisplayServer.get_name()])
	_time_new_course()
	_build_test_course()
	_time_save_load()
	_time_routing()
	_time_day()
	if DisplayServer.get_name() == "headless":
		print("load at the end %s" % _load())
		quit(0)
		return
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	root.add_child(_main)
	for s: int in [1, 2, 3]:
		_shows.append(["New course seed %d" % s, s])
	_shows.append(["the test course", 0])


func _time_new_course() -> void:
	var gen: Array[float] = []
	var newc: Array[float] = []
	var trees: Array[float] = []
	var water: Array[float] = []
	var high: Array[float] = []
	var block_rough: Array[float] = []
	var block_water: int = 0
	var no_clubhouse: int = 0
	var spots: Array[Vector2i] = []
	for s: int in range(1, SEEDS + 1):
		var t0 := Time.get_ticks_usec()
		var c := LandGenerator.generate(s, _land_tuning)
		gen.append((Time.get_ticks_usec() - t0) / 1000.0)
		t0 = Time.get_ticks_usec()
		var n := CourseBuilder.new_course(s, null, _land_tuning)
		newc.append((Time.get_ticks_usec() - t0) / 1000.0)
		var counts := {}
		var hi := 0
		for y: int in c.height:
			for x: int in c.width:
				var k: int = c.get_surface(x, y)
				counts[k] = counts.get(k, 0) + 1
				hi += 1 if c.get_height(x, y) >= _land_tuning.high_ground_level else 0
		var area := float(c.width * c.height)
		trees.append(100.0 * counts.get(Surface.Type.TREES, 0) / area)
		water.append(100.0 * counts.get(Surface.Type.WATER, 0) / area)
		high.append(100.0 * hi / area)
		var block := LandGenerator.start_block(c.width, c.height, _land_tuning.start_block_parcels)
		var rough := 0
		for y: int in range(block.position.y, block.end.y):
			for x: int in range(block.position.x, block.end.x):
				var k: int = c.get_surface(x, y)
				rough += 1 if k == Surface.Type.ROUGH else 0
				block_water += 1 if k == Surface.Type.WATER else 0
		block_rough.append(100.0 * rough / block.get_area())
		if n.has_clubhouse():
			spots.append(n.clubhouse)
		else:
			no_clubhouse += 1
	var block := LandGenerator.start_block(_land_tuning.map_size.x, _land_tuning.map_size.y,
			_land_tuning.start_block_parcels)
	print("New course land, seeds 1 to %d: LandGenerator.generate %s; CourseBuilder.new_course %s" % [
			SEEDS, _stats(gen), _stats(newc)])
	print("  land: trees %s %% (target %.0f), water %s %% (target %.0f), high ground (>= %d) %s %% (target %.0f)" % [
			_range(trees), 100 * _land_tuning.tree_share, _range(water), 100 * _land_tuning.water_share,
			_land_tuning.high_ground_level, _range(high), 100 * _land_tuning.high_ground_share])
	print("  starting block %s (%d x %d parcels of %d x %d): rough %s %% (floor %.0f), %d water tiles; clubhouse placed on %d of %d, spots %s" % [
			block, _land_tuning.start_block_parcels, _land_tuning.start_block_parcels,
			CourseData.PARCEL_TILES, CourseData.PARCEL_TILES, _range(block_rough),
			100 * _land_tuning.start_block_min_rough, block_water, SEEDS - no_clubhouse, SEEDS, spots])


func _build_test_course() -> void:
	_course = NineHoles.land(7) if _map == Vector2i.ZERO \
			else LandGenerator.generate(7, NinePerf.nine_land(_map))
	var b := CourseBuilder.new(_course)
	var opened: Array[int] = NineHoles.build(b)
	if _copies > 1:
		var offset: Vector2i = COPY_OFFSETS[_map]
		for spec: Array in NineHoles.HOLES:
			var n: int = spec[0] + 9
			var tee: Vector2i = spec[2] + offset
			var cup: Vector2i = spec[3] + offset
			b.begin_stroke()
			for cell: Vector2i in BuildTool.grid_line(tee, cup):
				b.paint(cell, Surface.Type.FAIRWAY, 3)
			b.end_stroke()
			b.paint(tee, Surface.Type.TEE, 3)
			b.paint(cup, Surface.Type.GREEN, 5)
			b.place_tee(n, tee, spec[1])
			b.place_cup(n, cup)
			b.set_par(n, spec[1])
			if b.hole(n).open:
				opened.append(n)
	print("test course: %d x %d, %d holes, %d open, clubhouse %s" % [_course.width, _course.height,
			_course.holes.size(), opened.size(), _course.clubhouse])


func _time_save_load() -> void:
	var text := CourseSave.to_json(_course)
	var packed := text.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var path := "user://e18_s1_test_course.json"
	if _out != "":
		path = _out.path_join("e18_s1_%dx%d_%dholes.json" % [_course.width, _course.height,
				_course.holes.size()])
	CourseSave.save_file(_course, path)
	print("course file: %d bytes (%d gzipped), written to %s" % [text.length(), packed.size(), path])
	var load_ms: Array[float] = []
	var builder_ms: Array[float] = []
	var c: CourseData
	for i: int in RUNS:
		var t0 := Time.get_ticks_usec()
		c = CourseSave.load_file(path)
		load_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		t0 = Time.get_ticks_usec()
		CourseBuilder.new(c)
		builder_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	print("load: CourseSave.load_file %s; CourseBuilder.new (validator's first pass) %s; %d holes open after" % [
			_stats(load_ms), _stats(builder_ms), c.holes.filter(func(h: HoleData) -> bool: return h.open).size()])


func _time_routing() -> void:
	var tuning := GuestTuning.load_default()
	var grid_ms: Array[float] = []
	var grid: GuestWalk.DryGrid
	for i: int in RUNS:
		var t0 := Time.get_ticks_usec()
		grid = GuestWalk.DryGrid.new(_course, tuning)
		grid_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	print("routing: GuestWalk.DryGrid (read once per tile revision) %s" % _stats(grid_ms))
	var ypt := 5.0
	var holes: Array = []
	for h: HoleData in _course.holes:
		holes.append([h.number, h.tee, h.cup])
	holes.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var sets := {"hole walks (tee to cup, cup to next tee)": [], "clubhouse door to every tee": [],
			"corner to corner": []}
	for k: int in holes.size():
		sets["hole walks (tee to cup, cup to next tee)"].append([holes[k][1], holes[k][2]])
		if k > 0:
			sets["hole walks (tee to cup, cup to next tee)"].append([holes[k - 1][2], holes[k][1]])
		if _course.has_clubhouse():
			sets["clubhouse door to every tee"].append([_course.clubhouse_door(), holes[k][1]])
	var w := _course.width - 1
	var h := _course.height - 1
	sets["corner to corner"] = [[Vector2i(0, 0), Vector2i(w, h)], [Vector2i(w, 0), Vector2i(0, h)],
			[Vector2i(0, h / 2), Vector2i(w, h / 2)], [Vector2i(w / 2, 0), Vector2i(w / 2, h)]]
	for what: String in sets:
		var each: Array[float] = []
		var yd := 0.0
		for pair: Array in sets[what]:
			var from := (Vector2(pair[0]) + Vector2(0.5, 0.5)) * ypt
			var to := (Vector2(pair[1]) + Vector2(0.5, 0.5)) * ypt
			var runs: Array[float] = []
			var pts := PackedVector2Array()
			for i: int in 5:
				var t0 := Time.get_ticks_usec()
				pts = GuestWalk._dry_route(_course, from, to, tuning, ypt, grid)
				runs.append((Time.get_ticks_usec() - t0) / 1000.0)
			runs.sort()
			each.append(runs[2])
			yd += from.distance_to(to)
		print("routing: the dry search alone, %s (%d walks, mean %.0f yd straight; median of 5 each): %s" % [
				what, (sets[what] as Array).size(), yd / maxf((sets[what] as Array).size(), 1), _stats(each)])


func _time_day() -> void:
	var b := GuestBrain.new(_course, 1, GuestTuning.load_default(), null, [], null, ARRIVALS)
	var t0 := Time.get_ticks_usec()
	b.run_day()
	var holes_played := 0
	for g: Guest in b.guests:
		holes_played += g.records.size()
	print("a %d-arrival day run by the brain alone: %.2f s, %d Ball ticks, %d guests, %d holes played, %d turned away, %d left at dusk" % [
			ARRIVALS, (Time.get_ticks_usec() - t0) / 1e6, b.ticks, b.guests.size(), holes_played,
			b.turned_away, b.guests.filter(func(g: Guest) -> bool: return g.left_at_dusk).size()])


func _process(_delta: float) -> bool:
	if _main == null:
		return false
	_frames += 1
	var now := Time.get_ticks_usec()
	if _frames < 5:
		_last = now
		return false
	if _frames % 5 == 1 and not _shows.is_empty():
		var job: Array = _shows.pop_front()
		var c: CourseData = _course if job[1] == 0 else CourseBuilder.new_course(job[1], null, _land_tuning)
		var t0 := Time.get_ticks_usec()
		_main.show_course(c)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("Main.show_course, %s: %.1f ms" % [job[0], ms])
		_show_ms.append(ms)
	elif _frames % 5 == 2 and _show_ms.size() > _after_ms.size():
		_after_ms.append((now - _last) / 1000.0)
		print("  the frame after it: %.1f ms" % _after_ms[-1])
	elif _shows.is_empty() and _after_ms.size() == _show_ms.size():
		print("load at the end %s" % _load())
		quit(0)
		return true
	_last = Time.get_ticks_usec()
	return false


func _stats(ms: Array[float]) -> String:
	if ms.is_empty():
		return "none"
	var s: Array[float] = ms.duplicate()
	s.sort()
	var total: float = 0.0
	for v: float in s:
		total += v
	return "median %.2f ms, mean %.2f, p95 %.2f, worst %.2f (n %d)" % [
		s[s.size() / 2], total / s.size(), s[mini(int(s.size() * 0.95), s.size() - 1)], s[-1], s.size()]


func _range(v: Array[float]) -> String:
	var s: Array[float] = v.duplicate()
	s.sort()
	var total := 0.0
	for x: float in s:
		total += x
	return "%.1f (%.1f to %.1f)" % [total / s.size(), s[0], s[-1]]


static func _load() -> String:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	return f.get_line().split(" ")[0] if f != null else "?"
