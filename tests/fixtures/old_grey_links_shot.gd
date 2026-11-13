class_name OldGreyLinksShot
extends Node2D
## Screenshot fixture for E13-S2: Old Grey Links (courses/old_grey_links.json) in Build.
## OGL_SHOT picks the view: `course` (the default) shows the whole course at 0.175x with the
## hole list collapsed; `hole:<n>` centres hole n at 0.5x (OGL_ZOOM overrides the zoom) on
## OGL_AT, `tee`, `cup` or `mid` (the default).
##   OGL_SHOT=hole:4 OGL_AT=cup scripts/screenshot.sh tests/fixtures/old_grey_links_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	var c := CourseSave.load_file(OldGreyLinks.PATH)
	main.show_course(c)
	main.hole_panel.set_collapsed(true)
	var spec: PackedStringArray = OS.get_environment("OGL_SHOT").split(":")
	var zs := OS.get_environment("OGL_ZOOM")
	var at: Vector2 = main.course_view.screen_bounds().get_center()
	var z := 0.175
	if spec.size() == 2 and spec[0] == "hole":
		z = 0.5
		for h: HoleData in c.holes:
			if h.number != spec[1].to_int():
				continue
			var tee := main.tile_world(h.tee)
			var cup := main.tile_world(h.cup)
			match OS.get_environment("OGL_AT"):
				"tee":
					at = tee
				"cup":
					at = cup
				_:
					at = (tee + cup) * 0.5
	if zs != "":
		z = zs.to_float()
	main.camera.set_zoom_level(z)
	main.camera.centre_on(at)
	main.camera.position = at
