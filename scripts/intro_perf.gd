extends SceneTree
## E21-S1 (D77): frame times over the whole opening flyover, as the game plays it at first
## launch: the main scene on a New course (seed 1) in a 1280 x 720 SubViewport (as
## scripts/screenshot.gd and scripts/nine_holes_perf.gd), vsync off and the frame rate uncapped,
## the intro stepping itself by each frame's real time. Every frame from the first after play()
## to the intro's end is timed (the time between two process frames, so drawing counts); the
## frame that builds the intro's course view (play() itself) is timed alone.
## Prints the median, p95 and worst over the whole intro and per beat, and fails (exit 1) when
## the whole intro's p95 is over BUDGET_MS (60 fps). Headless, no pixels are drawn: it times
## the intro's own work a frame (OpeningFlyover.advance) instead.
##
##   XDG_DATA_HOME=$(mktemp -d) godot --path . -s res://scripts/intro_perf.gd
##
## A throwaway user:// is required: the intro writes its played flag to user://.

const MAIN_SCENE := "res://scenes/main.tscn"
const BUDGET_MS: float = 16.7
## Frames run before the intro starts, so the New course's first frames are not counted.
const WARMUP_FRAMES: int = 60

var _main: Main
var _viewport: SubViewport
var _frames: int = 0
var _last_us: int = 0
var _started: bool = false
var _windowed: bool = false
var _build_ms: float = 0.0
## Beat -> frame times, ms.
var _by_beat: Dictionary = {}
var _all: Array[float] = []


func _initialize() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("intro_perf: set XDG_DATA_HOME to a temp folder first; the intro writes user://")
		quit(2)
		return
	_windowed = DisplayServer.get_name() != "headless"
	if _windowed:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	_main.start_seed = 1
	_viewport.add_child(_main)
	print("intro perf: %s, load average %s" % ["window" if _windowed else "headless (intro work only)",
			_load_average()])


func _process(_delta: float) -> bool:
	_frames += 1
	if not _started:
		if _frames < WARMUP_FRAMES:
			return false
		_started = true
		_main.intro.auto_advance = _windowed
		var t0 := Time.get_ticks_usec()
		if not _main.play_intro():
			push_error("intro_perf: the intro did not start")
			quit(1)
			return true
		_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
		_last_us = Time.get_ticks_usec()
		return false
	var now := Time.get_ticks_usec()
	var ms: float
	var beat: int = _main.intro.beat()
	if _windowed:
		ms = (now - _last_us) / 1000.0
	else:
		var t0 := Time.get_ticks_usec()
		_main.intro.advance(1.0 / 60.0)
		ms = (Time.get_ticks_usec() - t0) / 1000.0
	_last_us = now
	_all.append(ms)
	if not _by_beat.has(beat):
		_by_beat[beat] = [] as Array[float]
	(_by_beat[beat] as Array[float]).append(ms)
	if _main.intro.playing:
		return false
	_report()
	return true


func _report() -> void:
	print("intro perf: play() (loads the course, builds its view) %.1f ms, once" % _build_ms)
	for b: int in _by_beat:
		print("  %-6s %s" % [OpeningFlyover.Beat.keys()[b], _stats(_by_beat[b])])
	var p95 := _q(_all, 0.95)
	print("  whole  %s" % _stats(_all))
	print("intro perf: load average %s" % _load_average())
	if p95 > BUDGET_MS:
		print("intro perf: FAIL, p95 %.2f ms over %.1f ms" % [p95, BUDGET_MS])
		quit(1)
	else:
		print("intro perf: PASS, p95 %.2f ms within %.1f ms" % [p95, BUDGET_MS])
		quit(0)


func _stats(ms: Array[float]) -> String:
	return "%d frames, median %.2f ms, p95 %.2f ms, worst %.2f ms" % [ms.size(), _q(ms, 0.5),
			_q(ms, 0.95), _q(ms, 1.0)]


static func _q(values: Array[float], q: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return s[clampi(ceili(q * s.size()) - 1, 0, s.size() - 1)]


static func _load_average() -> String:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	return f.get_line().split(" ")[0] if f != null else "?"
