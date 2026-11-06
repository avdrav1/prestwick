extends SceneTree
## E3-S58: what drawing the ground costs on the playtest nine (tests/fixtures/playtest_nine.gd).
## Needs a display (a real window, vsync off):
##
##   godot --path . -s res://scripts/terrain_perf.gd
##
## Prints the one-off draw of the whole course (CourseView.show_course), the redraw after a
## one-tile and a 5 x 5 raise (CourseView.refresh_cells, the builder's own time left out), and
## idle frame times in Build and in Play (contours hidden, then shown) at 0.175x, 0.5x and 1x on
## the map's centre (mean, p95 and worst in ms over FRAMES frames).

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
	var view := main.course_view
	var t0 := Time.get_ticks_usec()
	view.show_course(c)
	print("draw the whole course: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var b := CourseBuilder.new(c)
	var centre := Vector2i(c.width / 2, c.height / 2)
	for brush: int in [1, 5]:
		b.raise(centre, brush)
		var cells: Array[Vector2i] = []
		for y: int in range(centre.y - brush / 2, centre.y + brush / 2 + 1):
			for x: int in range(centre.x - brush / 2, centre.x + brush / 2 + 1):
				cells.append(Vector2i(x, y))
		var t1 := Time.get_ticks_usec()
		view.refresh_cells(cells)
		print("redraw after a %dx%d raise: %.2f ms" % [brush, brush, (Time.get_ticks_usec() - t1) / 1000.0])
		b.undo()
		view.refresh_cells(cells)
	main.set_process(false)
	for mode: int in [Main.Mode.BUILD, Main.Mode.PLAY]:
		main.set_mode(mode)
		main.set_process(false)
		if main.swing_control != null:
			main.swing_control.set_process(false)
		for z: float in [0.175, 0.5, 1.0]:
			for topo_on: bool in ([false] if mode == Main.Mode.BUILD else [false, true]):
				view.topo.user_hidden = not topo_on
				main.camera.tracking = false
				main.camera.set_zoom_level(z)
				main.camera.position = view.screen_bounds().get_center()
				await _frames(20)
				var times: Array[float] = []
				var last := Time.get_ticks_usec()
				for i: int in FRAMES:
					await process_frame
					var now := Time.get_ticks_usec()
					times.append((now - last) / 1000.0)
					last = now
				times.sort()
				var mean := 0.0
				for f: float in times:
					mean += f
				mean /= times.size()
				print("%s %.3fx%s idle: mean %.2f ms, p95 %.2f, worst %.2f" % [
						"Build" if mode == Main.Mode.BUILD else "Play ", z,
						"" if mode == Main.Mode.BUILD else (" contours on " if topo_on else " contours off"),
						mean, times[int(times.size() * 0.95)], times[times.size() - 1]])
	quit()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
