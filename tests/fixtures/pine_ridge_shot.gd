class_name PineRidgeShot
extends Node2D
## Screenshot fixture for E13-S3: Pine Ridge (courses/pine_ridge.json, built by
## tests/fixtures/pine_ridge.gd) in Build. PINE_SHOT picks the view: `course` (the default)
## shows the whole course at PINE_ZOOM (default 0.175) with the hole list collapsed, `hole:<n>`
## frames hole n as the hole list does (Main.frame_hole) and then centres it at PINE_ZOOM
## (default 0.5) on PINE_AT: `mid` (the default, half way along its line of play), `tee`,
## `cup` or `turn` (a dogleg's turn, D47).
##   PINE_SHOT=hole:5 PINE_AT=turn scripts/screenshot.sh tests/fixtures/pine_ridge_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	var c := CourseSave.load_file(PineRidge.PATH)
	main.show_course(c)
	var spec: PackedStringArray = OS.get_environment("PINE_SHOT").split(":")
	var view: String = spec[0] if not spec.is_empty() and spec[0] != "" else "course"
	var zs := OS.get_environment("PINE_ZOOM")
	if view == "course":
		main.hole_panel.set_collapsed(true)
		main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.175)
		main.camera.centre_on(main.course_view.screen_bounds().get_center())
		main.camera.position = main.course_view.screen_bounds().get_center()
		return
	var n: int = spec[1].to_int() if spec.size() == 2 else 1
	main.frame_hole(n)
	var hole: HoleData = null
	for h: HoleData in c.holes:
		if h.number == n:
			hole = h
	var v := CourseValidator.new()
	var line: PackedVector2Array = v.line_of_play(c, hole)
	var at := (main.tile_world(hole.tee) + main.tile_world(hole.cup)) * 0.5
	match OS.get_environment("PINE_AT"):
		"tee":
			at = main.tile_world(hole.tee)
		"cup":
			at = main.tile_world(hole.cup)
		"turn":
			if line.size() == 3:
				at = main.tile_world(Vector2i(line[1].round()))
		_:
			if line.size() == 3:
				at = (main.tile_world(hole.tee) + main.tile_world(hole.cup)) * 0.25 \
						+ main.tile_world(Vector2i(line[1].round())) * 0.5
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.5)
	# Centre in the view the HUD leaves free, not under the hole list.
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift
