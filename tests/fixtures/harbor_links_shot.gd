class_name HarborLinksShot
extends Node2D
## Screenshot fixture for E13-S1: Harbor Links (tests/fixtures/harbor_links.gd) in Build.
## HARBOR_SHOT picks the view: `course` (the default) shows the whole course at HARBOR_ZOOM
## (0.175 unless set) with the hole list collapsed; `hole:<n>` centres hole n at HARBOR_ZOOM
## (0.5 unless set) on HARBOR_AT, `tee`, `cup` or `mid` (the default, half way from tee to cup).
##   HARBOR_SHOT=hole:9 scripts/screenshot.sh tests/fixtures/harbor_links_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	var c := HarborLinks.course()
	main.show_course(c)
	var spec: PackedStringArray = OS.get_environment("HARBOR_SHOT").split(":")
	var view: String = spec[0] if not spec.is_empty() and spec[0] != "" else "course"
	var zs := OS.get_environment("HARBOR_ZOOM")
	main.hole_panel.set_collapsed(true)
	if view == "course":
		main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.175)
		main.camera.centre_on(main.course_view.screen_bounds().get_center())
		main.camera.position = main.course_view.screen_bounds().get_center()
		return
	var n: int = spec[1].to_int() if spec.size() == 2 else 1
	main.frame_hole(n)
	var at := Vector2.ZERO
	for h: HoleData in c.holes:
		if h.number != n:
			continue
		match OS.get_environment("HARBOR_AT"):
			"cup":
				at = main.tile_world(h.cup)
			"tee":
				at = main.tile_world(h.tee)
			_:
				at = (main.tile_world(h.tee) + main.tile_world(h.cup)) * 0.5
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.5)
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift
