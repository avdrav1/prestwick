class_name DoglegHollowShot
extends Node2D
## Screenshot fixture for E16-S1: courses/dogleg_hollow.json (tests/fixtures/dogleg_hollow.gd) in Build.
## DOG_SHOT picks the view: `course` (the default) the whole course at DOG_ZOOM (default
## 0.175) with the hole list collapsed; `hole:<n>` centres hole n half way from tee to cup at
## DOG_ZOOM (default 0.5); `walks` the same whole-course view with the Cart path brush in hand,
## so every walk a round takes shows (scenes/walk_overlay.gd, D68). DOG_AT=cup (or a tile, "9,96") centres
## `hole:<n>` on its cup instead.
##   DOG_SHOT=hole:3 scripts/screenshot.sh tests/fixtures/dogleg_hollow_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = DoglegHollow.PATH
	add_child(main)
	var c: CourseData = main.course
	var spec: PackedStringArray = OS.get_environment("DOG_SHOT").split(":")
	var view: String = spec[0] if not spec.is_empty() and spec[0] != "" else "course"
	var zs := OS.get_environment("DOG_ZOOM")
	if view == "course" or view == "walks":
		main.hole_panel.set_collapsed(true)
		if view == "walks":
			main.build_tool.select_surface(Surface.Type.CART_PATH)
		main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.175)
		var mid := main.course_view.screen_bounds().get_center()
		main.camera.centre_on(mid)
		main.camera.position = mid
		if view == "walks":
			main.build_tool.walks.refresh()
		return
	var n: int = spec[1].to_int() if spec.size() == 2 else 1
	main.frame_hole(n)
	main.hole_panel.set_collapsed(true)
	var at := Vector2.ZERO
	for h: HoleData in c.holes:
		if h.number == n:
			at = (main.tile_world(h.tee) + main.tile_world(h.cup)) * 0.5
			var where := OS.get_environment("DOG_AT")
			if where == "cup":
				at = main.tile_world(h.cup)
			elif where.contains(","):
				var xy := where.split(",")
				at = main.tile_world(Vector2i(xy[0].to_int(), xy[1].to_int()))
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.5)
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift
