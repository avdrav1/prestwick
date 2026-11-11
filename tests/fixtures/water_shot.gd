extends Node
## Screenshot fixture for E10-S4 (D66): main in Build over a dug hollow beside a hill, before
## and after one dab of water fills it.
##
##   WATER_STEP=before scripts/screenshot.sh tests/fixtures/water_shot.tscn before.png 20
##   WATER_STEP=after  scripts/screenshot.sh tests/fixtures/water_shot.tscn after.png 20
##
## WATER_STEP=perf (with a display, run with godot --path . directly) prints the frame times of
## a fill of a WATER_SIDE x WATER_SIDE hollow (default 60: 3,600 tiles) on a 128 x 128 map and
## of its undo, then quits.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SIZE: int = 40

var _main: Main


func _ready() -> void:
	var step: String = OS.get_environment("WATER_STEP")
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(_main)
	if step == "perf":
		_perf.call_deferred()
		return
	var c := CourseData.create(SIZE, SIZE, Surface.Type.ROUGH, 3)
	# A hollow two steps deep in its middle, one at its edges, with an arm; a hill beside it.
	for y: int in range(12, 26):
		for x: int in range(10, 24):
			var d: float = Vector2(x - 16.5, (y - 18.5) * 1.3).length()
			if d < 4.0:
				c.set_tile(x, y, 1, Surface.Type.ROUGH)
			elif d < 6.5:
				c.set_tile(x, y, 2, Surface.Type.ROUGH)
	for x: int in range(23, 28):
		c.set_tile(x, 18, 2, Surface.Type.ROUGH)
	for y: int in range(8, 16):
		for x: int in range(26, 32):
			var hh: int = 3 + maxi(0, 3 - int(Vector2(x - 29, y - 12).length()))
			c.set_tile(x, y, hh, Surface.Type.ROUGH)
	c.set_tile(29, 12, 7, Surface.Type.WATER)  # a towering pool from before D66, kept on load
	_main.show_course(c)
	var b: CourseBuilder = _main.build_tool.builder
	if step == "after":
		b.paint(Vector2i(16, 18), Surface.Type.WATER, 1)
		b.paint(Vector2i(28, 11), Surface.Type.WATER, 3)  # the hill: refused, the HUD says why
	_main.camera.tracking = false
	_main.camera.set_zoom_index(_main.camera.tuning.zoom_levels.find(1.0))
	_main.camera.position = Iso.tile_to_screen(Vector2(20, 16), 3)
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(330, 40)
	label.text = "E10-S4 water: %s" % ("one dab of water on the hollow, one on the hill"
			if step == "after" else "a dug hollow, a hill with an old towering pool")
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	add_child(layer)


func _perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var fills: Array[float] = []
	var undos: Array[float] = []
	var fill_frames: Array[float] = []
	var undo_frames: Array[float] = []
	var side: int = 60 if OS.get_environment("WATER_SIDE").is_empty() else OS.get_environment("WATER_SIDE").to_int()
	for run: int in 5:
		var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
		for y: int in range(34, 34 + side):
			for x: int in range(34, 34 + side):
				c.set_tile(x, y, 1, Surface.Type.ROUGH)
		_main.show_course(c)
		_main.camera.tracking = false
		_main.camera.set_zoom_index(_main.camera.tuning.zoom_levels.find(0.5))
		_main.camera.position = Iso.tile_to_screen(Vector2(64, 64), 1)
		for i: int in 20:
			await get_tree().process_frame
		var b: CourseBuilder = _main.build_tool.builder
		var f0: int = Time.get_ticks_usec()
		var t0: int = Time.get_ticks_usec()
		b.paint(Vector2i(40, 40), Surface.Type.WATER, 1)
		fills.append((Time.get_ticks_usec() - t0) / 1000.0)
		await get_tree().process_frame
		fill_frames.append((Time.get_ticks_usec() - f0) / 1000.0)
		for i: int in 10:
			await get_tree().process_frame
		f0 = Time.get_ticks_usec()
		t0 = Time.get_ticks_usec()
		b.undo()
		undos.append((Time.get_ticks_usec() - t0) / 1000.0)
		await get_tree().process_frame
		undo_frames.append((Time.get_ticks_usec() - f0) / 1000.0)
	for a: Array[float] in [fills, fill_frames, undos, undo_frames]:
		a.sort()
	print("%d-tile fill: call (builder and view) median %.1f ms, min %.1f; its frame median %.1f ms, min %.1f" % [
			side * side, fills[2], fills[0], fill_frames[2], fill_frames[0]])
	print("its undo: call median %.1f ms, min %.1f; its frame median %.1f ms, min %.1f" % [
			undos[2], undos[0], undo_frames[2], undo_frames[0]])
	get_tree().quit()
