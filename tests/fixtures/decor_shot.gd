class_name DecorShot
extends Node2D
## Screenshot fixture for E5-S3: the playtest nine in Build at DECOR_ZOOM (default 1) by the
## clubhouse, with a bench along each axis, a flag and a sign placed through the builder (a
## fixture may edit through it), the Decor tool selected and hovering a free tile.
##   DECOR_ZOOM=1 scripts/screenshot.sh tests/fixtures/decor_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = PlaytestNine.PATH
	add_child(main)
	var c: CourseData = main.course
	var tool: BuildTool = main.build_tool
	var base: Vector2i = c.clubhouse + Vector2i(3, 0)
	var spots: Array[Vector2i] = [base + Vector2i(0, -2), base + Vector2i(1, 2), base + Vector2i(2, -1), base + Vector2i(0, 3)]
	for i: int in spots.size():
		tool.builder.set_decor(spots[i], i)
	var zs := OS.get_environment("DECOR_ZOOM")
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 1.0)
	var at: Vector2 = main.tile_world(base)
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift
	tool.select_tool(BuildTool.Tool.DECOR)
	var hover: Vector2i = base + Vector2i(2, 2)
	tool.hover_at(Iso.tile_to_screen(Vector2(hover), c.get_height(hover.x, hover.y)))
