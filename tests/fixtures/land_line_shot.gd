class_name LandLineShot
extends Node2D
## Screenshot fixture for E6-S7: the main scene in Play on courses/example_par3.json with
## parcels (1, 1) and (2, 1) not owned (rows 16 to 24, east of x 16, beside the hole), the
## 7-iron picked and the aim turned toward that land, so the aim line, its marker and the
## land line (chalk dashes on ink along the owned edge) all show before the shot.
## Run: scripts/screenshot.sh tests/fixtures/land_line_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COURSE_PATH: String = "res://courses/example_par3.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = COURSE_PATH
	add_child(main)
	# A fixture writes CourseData directly, as tests may (CourseData WRITERS).
	main.course.set_parcel_owned(Vector2i(1, 1), false)
	main.course.set_parcel_owned(Vector2i(2, 1), false)
	main.show_course(main.course)
	main.set_mode(Main.Mode.PLAY)
	var sc := main.swing_control
	sc.set_process(false)
	sc.select_club(sc.model.clubs.club("7i"))
	sc.rotate_aim(12.0)
	sc._refresh_aim()
	main.swing_panel.refresh()
	main.camera.set_zoom_level(0.5)
