class_name GuestShirtsShot
extends Node2D
## Screenshot fixture for E3-S28's shirts (by hand): the guest course (tests/fixtures/
## guest_course.gd) in Play, the day run until the first GROUPS groups have arrived, then the
## sim paused and each group stood (a fixture may write guest data; the view only reads it) in
## a row along hole 1 with its group spread, on the tee, the fairway, the rough and the green,
## so each shirt shows on several surfaces. Seven groups, all still out, so they choose the
## seven shirts in order (GuestView.assign_shirts, E3-S47): chalk, flag_red hoops, water_dark
## yoke, sun_yellow, earth, slate_light with a water_dark yoke, water_light with water_dark
## hoops (art/specs/golfer.md "Shirts"). Pixels: scripts/shirt_render_check.gd checks the shader's output is exact.
## Run: scripts/screenshot.sh tests/fixtures/guest_shirts_shot.tscn, then the grayscale check:
## magick <png> -colorspace Gray <gray.png>. docs/decisions/e3-s28-shirts*.png.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GuestCourse := preload("res://tests/fixtures/guest_course.gd")

const GROUPS: int = 7
## Where each group stands: hole 1's tee (4, 6), its fairway, the rough beside it, its green.
const SPOTS: Array[Vector2i] = [Vector2i(4, 6), Vector2i(8, 6), Vector2i(11, 8), Vector2i(14, 6),
		Vector2i(17, 4), Vector2i(20, 6), Vector2i(9, 3)]

## The camera's zoom level (CameraTuning.zoom_levels index): 2 is 1x, 1 is 0.5x (D45 added
## 0.175x at 0).
@export var zoom_index: int = 2


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	main.show_course(GuestCourse.course())
	main.set_mode(Main.Mode.PLAY)
	main.swing_panel.visible = false
	var sim := main.guest_sim
	while sim.brain == null or sim.brain.groups.size() < GROUPS \
			or sim.brain.groups[GROUPS - 1].phase == GuestGroup.Phase.PENDING:
		sim.advance(1.0)
	sim.set_speed(0.0)
	var field := sim.brain.field
	for gi in GROUPS:
		for g: Guest in sim.brain.groups[gi].guests:
			g.position = field.tile_center(SPOTS[gi])
			g.walk = null
			g.state = Guest.State.WAITING
	main.guest_view.clear()
	main.set_process(false)
	main.aim_view.visible = false
	main.camera.set_zoom_index(zoom_index)
	main.feed_panel.set_in_play(false)  # E3-S27 shows the feed in Play; it would cover the row
	main.camera.tracking = false
	main.camera.position = main.tile_world(Vector2i(12, 6))
