extends SceneTree
## E7-S4: how long skip to morning takes, in real time, on a full day. The main scene opens
## courses/playtest_nine.json, its first day is drawn with `ARRIVALS` guests (D58's most, 24,
## through GuestSim.resume_at), Morning is pressed at 0:00, and the frames run until the next
## morning: the real seconds, the frames, the longest frame and the status line's progress.
## Then the same day is run by the brain alone (run_day, no threads) and its end state compared
## with the skipped one, so a fast skip is still the same day.
##
##   godot --path . -s res://scripts/skip_perf.gd [-- --seed N --mode build|play --runs N
##       --frame-ms MS]
##
## With a window the frames are real (vsync, drawing); --headless times the work alone.
## --frame-ms tries another `skip_frame_ms`. Prints the 1-minute load average at the start and
## end (D52): other jobs on the machine slow it. Exits 1 when the day differs from the brain's
## own or the best run is not under TARGET_S.

const MAIN_SCENE := "res://scenes/main.tscn"
const NINE_PATH := "res://courses/playtest_nine.json"
const ARRIVALS := 24
## E7-S4's Accept: a full 24-guest day skipped in under this many real seconds.
const TARGET_S := 3.0

var _main: Main
var _seed := 1
var _play := false
var _runs := 1
var _run := 0
var _phase := 0
var _t0 := 0
var _last := 0
var _frames := 0
var _worst_us := 0
var _lines: PackedStringArray = []
var _ends: Array = []
var _times: Array[float] = []
var _failed := false
var _day_seed := 0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var i := argv.find("--seed")
	if i >= 0 and i + 1 < argv.size():
		_seed = argv[i + 1].to_int()
	i = argv.find("--mode")
	if i >= 0 and i + 1 < argv.size():
		_play = argv[i + 1] == "play"
	i = argv.find("--runs")
	if i >= 0 and i + 1 < argv.size():
		_runs = maxi(argv[i + 1].to_int(), 1)
	print("skip perf: %s, seed %d, %d guests, %s mode, %s, load %s" % [NINE_PATH, _seed, ARRIVALS,
			"Play" if _play else "Build", "headless" if DisplayServer.get_name() == "headless" else "window",
			_load()])
	_open()


func _open() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	_main.course_path = NINE_PATH
	_main.start_seed = _seed
	root.add_child(_main)
	_phase = 0
	_frames = 0


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	match _phase:
		0:
			# The scene is ready by the first frame: day 1 draws ARRIVALS guests. A few frames
			# for it to settle, then Morning.
			_frames += 1
			if _frames == 1:
				_main.guest_sim.resume_at(1, ARRIVALS)
				_main.guest_sim.day_ended.connect(_on_day_ended)
				if _play:
					_main.mode_button.pressed.emit()
			if _frames >= 10:
				var mi := OS.get_cmdline_user_args().find("--frame-ms")
				if mi >= 0:
					_main.guest_sim.tuning.skip_frame_ms = OS.get_cmdline_user_args()[mi + 1].to_float()
				_main.sim_speed_panel.skip_button.pressed.emit()
				if not _main.guest_sim.skipping:
					return _fail("Morning did not start a skip")
				_t0 = now
				_last = now
				_frames = 0
				_worst_us = 0
				_lines.clear()
				_phase = 1
		1:
			_frames += 1
			_worst_us = maxi(_worst_us, now - _last)
			_last = now
			if _frames % 15 == 1:
				_lines.append(_main.sim_speed_panel.status_text())
			if not _main.guest_sim.skipping:
				var real_s := (now - _t0) / 1e6
				_times.append(real_s)
				print("  run %d: day 1 skipped in %.2f real s, %d frames, longest frame %.1f ms, now \"%s\"" % [
						_run + 1, real_s, _frames, _worst_us / 1000.0, _main.sim_speed_panel.status_text()])
				print("    status line on the way: %s" % " | ".join(_lines.slice(0, 8)))
				_phase = 2
		2:
			_run += 1
			_main.queue_free()
			if _run < _runs:
				_open()
			else:
				return _finish()
	return false


func _on_day_ended(d: int, b: GuestBrain) -> void:
	if d == 1 and _run == 0:
		_ends.append(_end_state(b))
		_day_seed = b.day_seed
		print("    day 1: %d guests, %d Ball ticks, %d reactions in the feed" % [b.guests.size(), b.ticks,
				_main.guest_sim.feed.total])


func _finish() -> bool:
	# The same day by the brain alone, one second after another on this thread.
	var c := CourseSave.load_file(NINE_PATH)
	var b := GuestBrain.new(c, _day_seed, GuestTuning.load_default(), null, [], null, ARRIVALS)
	var t0 := Time.get_ticks_usec()
	b.run_day()
	print("  the same day run by the brain alone: %.2f s, %d Ball ticks" % [
			(Time.get_ticks_usec() - t0) / 1e6, b.ticks])
	if _ends.is_empty() or _ends[0] != _end_state(b):
		_fail("the skipped day ends as the day run alone")
	else:
		print("  PASS: the skipped day ends as the day run alone (every guest's records and ticks)")
	_times.sort()
	var best: float = _times[0] if not _times.is_empty() else INF
	print("  best of %d: %.2f s (target under %.1f s); load %s" % [_times.size(), best, TARGET_S, _load()])
	if best >= TARGET_S:
		_fail("a full day skipped in under %.1f s" % TARGET_S)
	quit(1 if _failed else 0)
	return true


static func _end_state(b: GuestBrain) -> Array:
	var out: Array = []
	for g: Guest in b.guests:
		var recs: Array = []
		for r: Guest.HoleRecord in g.records:
			recs.append([r.number, r.score, r.holed, r.picked_up, r.wait_s, r.walk_yd, r.start_s,
					r.end_s, r.reaction.kind if r.reaction != null else -1])
		out.append([g.id, g.skill, g.state, g.arrived_s, g.left_s, g.left_at_dusk, g.ticks, recs])
	return [out, b.second, b.turned_away, b.ticks]


func _fail(what: String) -> bool:
	_failed = true
	print("  FAIL: %s" % what)
	return false


static func _load() -> String:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	return f.get_line().split(" ")[0] if f != null else "?"
