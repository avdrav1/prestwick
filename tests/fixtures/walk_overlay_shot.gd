class_name WalkOverlayShot
extends Node2D
## Screenshot fixture for E12-S1 (D68): the playtest nine in Build with the Cart path brush in
## hand, so every walk a round takes shows (scenes/walk_overlay.gd), the camera on the walk from
## the 7th green to the 8th tee at WALK_ZOOM (default 1). WALK_STATE=red takes up the last
## tiles of that walk's path (from WALK_CUT along it), so it stops short of the 8th tee and shows
## red with the gap; otherwise the path serves it and it shows green.
##   WALK_STATE=red WALK_ZOOM=0.5 scripts/screenshot.sh tests/fixtures/walk_overlay_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## The 7th to 8th path runs (60, 102) to (69, 116) (PlaytestNine.PATHS); red takes it up from
## this row on.
const WALK_CUT_ROW: int = 109


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = PlaytestNine.PATH
	add_child(main)
	var c: CourseData = main.course
	var tool: BuildTool = main.build_tool
	if OS.get_environment("WALK_STATE") == "red":
		var b: CourseBuilder = tool.builder
		b.begin_stroke()
		for y: int in range(WALK_CUT_ROW, 118):
			for x: int in range(58, 72):
				if c.get_surface(x, y) == Surface.Type.CART_PATH:
					b.paint(Vector2i(x, y), Surface.Type.ROUGH, 1)
		b.end_stroke()
	tool.select_surface(Surface.Type.CART_PATH)
	var zs := OS.get_environment("WALK_ZOOM")
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 1.0)
	var seven: HoleData = null
	var eight: HoleData = null
	for h: HoleData in c.holes:
		if h.number == 7:
			seven = h
		elif h.number == 8:
			eight = h
	var at: Vector2 = (main.tile_world(seven.cup) + main.tile_world(eight.tee)) * 0.5
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift
	tool.walks.refresh()
