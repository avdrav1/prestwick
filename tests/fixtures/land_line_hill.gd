class_name LandLineHill
extends Node2D
## Screenshot fixture for the E6-S7 review: land_line_shot.tscn's course (parcels (1, 1) and
## (2, 1) not owned) with a height-7 hill on unowned tiles x 20 to 33, rows 18 to 22, in front
## of the land line at row 15.5. The edges the hill covers draw faded (LandBoundary.covered),
## so the line does not read as running over the hill's top; each edge's tick points into the
## unowned side. The 7-iron is aimed over the line, so the aim marker shows the OB cue.
## Run: scripts/screenshot.sh tests/fixtures/land_line_hill.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COURSE_PATH: String = "res://courses/example_par3.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = COURSE_PATH
	add_child(main)
	# A fixture writes CourseData directly, as tests may (CourseData WRITERS).
	var c := main.course
	c.set_parcel_owned(Vector2i(1, 1), false)
	c.set_parcel_owned(Vector2i(2, 1), false)
	for y in range(18, 23):
		for x in range(20, 34):
			c.set_tile(x, y, 7, c.get_surface(x, y))
	main.show_course(c)
	main.set_mode(Main.Mode.PLAY)
	var sc := main.swing_control
	sc.set_process(false)
	sc.select_club(sc.model.clubs.club("7i"))
	sc.rotate_aim(12.0)
	sc._refresh_aim()
	main.swing_panel.refresh()
	main.camera.set_zoom_level(0.5)
