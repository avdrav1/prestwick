class_name PlaytestNineShot
extends Node2D
## Screenshot fixture for E3-S50: the playtest nine (tests/fixtures/playtest_nine.gd) in Build.
## PLAYTEST_SHOT picks the view: `green:<n>` centres hole n's cup at 1x (its green's contours),
## `corner:<n>` centres dogleg n's turn (CourseValidator.turn_point, D47) at 0.5x, `hole:<n>`
## frames hole n's tee and cup as the hole list does (Main.frame_hole), `course` shows the
## whole course at the farthest zoom with the hole list collapsed, and `open` (the default)
## leaves the camera where Main.show_course put it: hole 1 framed by Main.frame_first_hole,
## the game's opening frame.
##   PLAYTEST_SHOT=green:3 scripts/screenshot.sh tests/fixtures/playtest_nine_shot.tscn out.png
## E3-S57: `play:<n>` starts Play on hole n (the contour overlay on) at PLAYTEST_ZOOM (0.175,
## 0.5, 1 or 2; default 0.5), centred on PLAYTEST_AT, `tee`, `cup` or `mid` (the default, half
## way from tee to cup), or the whole course at 0.175x. PLAYTEST_TOPO picks the overlay's
## offset to compare (`whole`, `half`; E3-S57's placements went with D17 in E3-S59), and
## PLAYTEST_GRAY=1 draws the screen in luminance only.
##   PLAYTEST_SHOT=play:4 PLAYTEST_ZOOM=1 scripts/screenshot.sh tests/fixtures/playtest_nine_shot.tscn
## E3-S58: PLAYTEST_ZOOM also sets the zoom of `course`, `green` and `corner` in Build, and
## PLAYTEST_GRAY=1 works there too.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	var c := PlaytestNine.land()
	PlaytestNine.build(CourseBuilder.new(c))
	main.show_course(c)
	var spec: PackedStringArray = OS.get_environment("PLAYTEST_SHOT").split(":")
	var view: String = spec[0] if not spec.is_empty() and spec[0] != "" else "open"
	var n: int = spec[1].to_int() if spec.size() == 2 else 1
	var zs := OS.get_environment("PLAYTEST_ZOOM")
	if OS.get_environment("PLAYTEST_GRAY") == "1" and view != "play":
		_gray()
	if view == "open":
		return
	if view == "play":
		_play(main, c, n)
		return
	if view == "course":
		# The list collapsed to hole 1's row, so the east corner of the map shows.
		main.hole_panel.set_collapsed(true)
		main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.175)
		main.camera.centre_on(main.course_view.screen_bounds().get_center())
		main.camera.position = main.course_view.screen_bounds().get_center()
		return
	main.frame_hole(n)
	if view != "green" and view != "corner":
		return
	var at := Vector2.ZERO
	for h: HoleData in c.holes:
		if h.number != n:
			continue
		var cell: Vector2i = h.cup
		if view == "corner":
			var turn: Variant = CourseValidator.new().turn_point(c, h)
			if turn != null:
				cell = Vector2i((turn as Vector2).round())
		at = main.tile_world(cell)
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 1.0 if view == "green" else 0.5)
	# Centre the cup in the view the HUD leaves free, not under the hole list.
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift


## E3-S57: Play on hole `n` with the contour overlay, framed as the PLAYTEST_ env vars say.
func _play(main: Main, c: CourseData, n: int) -> void:
	main.build_tool.select_hole(n)
	main.set_mode(Main.Mode.PLAY)
	main.swing_control.set_process(false)
	var topo := main.course_view.topo
	var opt := OS.get_environment("PLAYTEST_TOPO")
	if opt != "":
		var t: TopoTuning = topo.tuning.duplicate()
		t.offset = 0.5 if opt.ends_with("half") else 0.0
		topo.tuning = t
		topo.mark_dirty()
	if OS.get_environment("PLAYTEST_GRAY") == "1":
		_gray()
	var zs := OS.get_environment("PLAYTEST_ZOOM")
	var z: float = zs.to_float() if zs != "" else 0.5
	main.camera.tracking = false
	main.camera.set_zoom_level(z)
	_frame_play(main, c, n, z)


## Draws the screen in luminance only (PLAYTEST_GRAY).
func _gray() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D screen: hint_screen_texture;\nvoid fragment() {\n\tvec3 c = texture(screen, SCREEN_UV).rgb;\n\tfloat l = dot(c, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(l, l, l, 1.0);\n}\n"
	mat.shader = sh
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)


func _frame_play(main: Main, c: CourseData, n: int, z: float) -> void:
	var at := main.course_view.screen_bounds().get_center()
	if z > 0.2:
		var hole: HoleData = null
		for h: HoleData in c.holes:
			if h.number == n:
				hole = h
		var tee := main.tile_world(hole.tee)
		var cup := main.tile_world(hole.cup)
		match OS.get_environment("PLAYTEST_AT"):
			"tee":
				at = tee
			"cup":
				at = cup
			_:
				at = (tee + cup) * 0.5
	# Hold the camera there: Main's Play camera would frame the ball and its aim marker.
	main.set_process(false)
	main.camera.tracking = false
	main.camera.position = at
