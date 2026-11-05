class_name FeedShot
extends Node2D
## Screenshot fixture for E3-S7's feed and map tags (by hand): the guest course
## (tests/fixtures/guest_course.gd) with a bunker on hole 2's line and rough round it, so
## hole 2 can be praised (interesting needs a hazard on the line and a way round), in Play.
## The day runs to `run_to_s` (seed 3), every line of the feed is shown and the camera frames
## the three holes, so the picture holds the feed, its marks and colours, and the tags over
## the pins. With `jump`, the feed's top line is then clicked: Build, its hole picked in the
## hole list and framed.
##   scripts/screenshot.sh tests/fixtures/feed_shot.tscn out.png 30
##   scripts/screenshot.sh tests/fixtures/feed_jump_shot.tscn out.png 30

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GuestCourse := preload("res://tests/fixtures/guest_course.gd")

@export var jump: bool = false
@export var run_to_s: int = 150

var main: Main


func _ready() -> void:
	var b: CourseBuilder = GuestCourse.build()
	b.paint(Vector2i(32, 6), Surface.Type.BUNKER, 1)
	b.open_hole(2)
	main = MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	main.show_course(b.course)
	main.set_mode(Main.Mode.PLAY)
	main.set_process(false)
	main.swing_panel.visible = false
	main.aim_view.visible = false
	main.guest_sim.set_process(false)
	main.guest_sim.advance(0.0)
	while main.guest_sim.brain.second < run_to_s and not main.guest_sim.brain.day_over:
		main.guest_sim.brain.step()
	for i: int in 64:
		main.feed_panel.tick(main.feed_panel.tuning.reveal_interval_s)
	main.camera.tracking = false
	var h1: HoleData = main.course.holes[0]
	var h2: HoleData = main.course.holes[1]
	main.camera.frame_points(main.tile_world(h1.tee), main.tile_world(h2.cup), main.free_view_rect())
	if jump:
		main.feed_panel.rows[0].pressed.emit()
