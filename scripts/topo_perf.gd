extends SceneTree
## E3-S57: the contour overlay's cost on the playtest nine (tests/fixtures/playtest_nine.gd) in
## Play. Needs a display (a real window, vsync off):
##
##   godot --path . -s res://scripts/topo_perf.gd
##
## Prints the one-off trace and layout (entering Play at 0.175x, the whole map), the layout a
## zoom step costs, and idle and panning frame times at 0.175x and 0.5x with the overlay on and
## off (mean, p95 and worst in ms over FRAMES frames). A pan stays inside the traced window, so
## it costs no trace or layout.

const FRAMES: int = 240


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	root.add_child(main)
	await process_frame
	var c := PlaytestNine.course()
	main.show_course(c)
	main.camera.set_zoom_level(0.175)
	main.camera.tracking = false
	main.camera.position = main.course_view.screen_bounds().get_center()
	var topo := main.course_view.topo
	await process_frame
	var t0 := Time.get_ticks_usec()
	main.set_mode(Main.Mode.PLAY)
	main.set_process(false)
	main.camera.tracking = false
	main.camera.set_zoom_level(0.175)
	main.camera.position = main.course_view.screen_bounds().get_center()
	topo.refresh()
	print("enter Play + first trace and layout at 0.175x: %.1f ms (traces %d, layouts %d, %d lines, %d rows, window %s)" % [
			(Time.get_ticks_usec() - t0) / 1000.0, topo.trace_count, topo.layout_count, topo.line_count(),
			topo.rows().size(), topo.traced_window])
	var t1 := Time.get_ticks_usec()
	topo._trace(topo.traced_window)
	var t2 := Time.get_ticks_usec()
	topo._layout(0.175)
	var t3 := Time.get_ticks_usec()
	print("trace alone %.1f ms, layout alone %.1f ms" % [(t2 - t1) / 1000.0, (t3 - t2) / 1000.0])
	for z: float in [0.175, 0.5]:
		main.camera.set_zoom_level(z)
		main.camera.position = main.course_view.screen_bounds().get_center()
		for on: bool in [true, false]:
			topo.user_hidden = not on
			for pan: bool in [false, true]:
				await _frames(10)
				var traces := topo.trace_count
				var layouts := topo.layout_count
				var times: Array[float] = []
				var last := Time.get_ticks_usec()
				for i: int in FRAMES:
					if pan:
						main.camera.position += Vector2(1.5 if (i / 60) % 2 == 0 else -1.5, 0.0) / z
					await process_frame
					var now := Time.get_ticks_usec()
					times.append((now - last) / 1000.0)
					last = now
				times.sort()
				var mean := 0.0
				for f: float in times:
					mean += f
				mean /= times.size()
				print("%.3fx overlay %s %s: mean %.2f ms, p95 %.2f, worst %.2f (traces +%d, layouts +%d)" % [
						z, "on " if on else "off", "pan " if pan else "idle", mean, times[int(times.size() * 0.95)],
						times[times.size() - 1], topo.trace_count - traces, topo.layout_count - layouts])
	quit()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
