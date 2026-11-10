class_name ClubhouseShot
extends Node2D
## Screenshot fixture for E5-S10: the playtest nine's clubhouse (courses/playtest_nine.json) in
## Build, centred at CLUB_ZOOM (0.175, 0.5 or 1; default 0.5). CLUB_HOVER puts the Clubhouse
## tool's outline on a spot: `ok` (an allowed spot beside it), `refused` (across hole 1's line),
## or none. CLUB_FACING turns it first (0 to 3, CourseData.FACINGS). CLUB_NEW=<seed> shows a New
## course of that land seed instead (its clubhouse in the starting block, Buy land on the bar).
##   CLUB_ZOOM=1 CLUB_HOVER=ok scripts/screenshot.sh tests/fixtures/clubhouse_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## An allowed spot east of the clubhouse, and one across hole 1's line of play (tee (10, 56)).
const OK_SPOT := Vector2i(15, 60)
const REFUSED_SPOT := Vector2i(14, 47)


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = PlaytestNine.PATH
	add_child(main)
	if OS.get_environment("CLUB_NEW") != "":
		main.new_course(OS.get_environment("CLUB_NEW").to_int())
	var c: CourseData = main.course
	var tool: BuildTool = main.build_tool
	var f := OS.get_environment("CLUB_FACING")
	if f != "":
		tool.builder.move_clubhouse(c.clubhouse, f.to_int())
	var zs := OS.get_environment("CLUB_ZOOM")
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.5)
	var at: Vector2 = main.tile_world(c.clubhouse + Vector2i(2, 0))
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift
	match OS.get_environment("CLUB_HOVER"):
		"ok":
			_hover(main, OK_SPOT)
		"refused":
			_hover(main, REFUSED_SPOT)


func _hover(main: Main, cell: Vector2i) -> void:
	var tool: BuildTool = main.build_tool
	tool.select_tool(BuildTool.Tool.CLUBHOUSE)
	tool.hover_at(Iso.tile_to_screen(Vector2(cell), main.course.get_height(cell.x, cell.y)))
	main.land_panel.refresh()
