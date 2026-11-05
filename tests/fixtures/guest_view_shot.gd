class_name GuestViewShot
extends Node2D
## Screenshot fixture for E3-S5's Y-sort check (by hand): the guest course
## (tests/fixtures/guest_course.gd) with a two-step hill (tiles 10 to 12, rows 10 to 12) and a
## one-step block of trees (tiles 20 to 22, rows 11 to 13) between its holes. The day runs in
## Play until a few guests have arrived, then the sim is paused and four of them are stood
## (a fixture may write guest data; the view only reads it) on the hill's top, behind the
## middle of the hill's back-left edge, behind the middle of the trees' back-left edge, and in
## front of the trees. At a tile's centre behind a block's edge a one-step block hides
## nothing (the feet sit on the top's back vertex) and a two-step block hides 16 of the
## figure's 24 px, so the two behind are moved within their tiles (SHIFTS, along the screen's
## vertical): the one behind the hill 0.3 tile back, so the hill's top hides its feet and the
## rest stands over it; the one behind the trees 0.3 tile forward, so the trees hide its feet
## and legs and its body and head show over them. The guests on top and in front show whole.
## Run: scripts/screenshot.sh tests/fixtures/guest_view_shot.tscn
## At 0.5x (zoom_level 0.5, guest_view_shot_0_5x.tscn): the figures keep their 24 px on screen
## (GuestViewTuning.figure_min_screen_scale), docs/decisions/e3-s5-guests-0.5x.png.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GuestCourse := preload("res://tests/fixtures/guest_course.gd")

## Where the staged guests stand: on the hill, behind the hill, behind the trees, in front.
const SPOTS: Array[Vector2i] = [Vector2i(11, 11), Vector2i(9, 11), Vector2i(19, 12), Vector2i(23, 14)]
## Each guest's shift from its tile's centre, tiles (+x+y: down the screen, toward the camera).
const SHIFTS: Array[Vector2] = [Vector2.ZERO, Vector2(-0.45, -0.45), Vector2(0.1, 0.1), Vector2.ZERO]

## The camera's zoom (one of CameraTuning.zoom_levels): 2.0 is 2x, 0.5 is 0.5x.
@export var zoom_level: float = 2.0


## The guest course with the hill and the trees (a fixture writes CourseData directly).
static func course() -> CourseData:
	var c := GuestCourse.course()
	for y in range(10, 13):
		for x in range(10, 13):
			c.set_tile(x, y, 4, c.get_surface(x, y))
	for y in range(11, 14):
		for x in range(20, 23):
			c.set_tile(x, y, 3, Surface.Type.TREES)
	return c


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	main.show_course(course())
	main.set_mode(Main.Mode.PLAY)
	main.swing_panel.visible = false
	var sim := main.guest_sim
	while sim.brain == null or sim.brain.guests.size() < SPOTS.size():
		sim.advance(1.0)
	sim.set_speed(0.0)
	var field := sim.brain.field
	for i in SPOTS.size():
		var g: Guest = sim.brain.guests[i]
		g.position = field.tile_center(SPOTS[i]) + SHIFTS[i] * field.yards_per_tile
		g.walk = null
		g.state = Guest.State.WAITING
		g.place = 0
	main.guest_view.clear()
	# The player's ball and aim stay off this picture: the camera holds still.
	main.set_process(false)
	main.aim_view.visible = false
	main.camera.set_zoom_level(zoom_level)
	main.camera.tracking = false
	main.camera.position = main.tile_world(Vector2i(15, 11))
