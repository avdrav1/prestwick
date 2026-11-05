class_name FrameHoleShot
extends Node2D
## Screenshot fixture for E3-S9: nine open holes in New sandbox on generated land
## (tests/fixtures/nine_holes.gd), with hole `hole` framed clear of the HUD (Main.frame_hole).
## frame_hole_shot.tscn frames hole 2, a par 3 whose tee and cup both fit at 0.5x;
## frame_hole_shot_long.tscn frames hole 8, a 520 yd par 5, and frame_hole_shot_longest.tscn
## hole 3, the longest (520 yd, a little taller on screen), both at the farthest step, 0.175x
## (D45). frame_hole_shot_play.tscn (`play`) is the same course in Play at 0.175x, the player's
## own zoom, on hole 8's tee, with the guests' day stepped to `guest_s` and paused, so
## terrain, markers, guests and the ball can be read at the farthest step.
## Run: scripts/screenshot.sh tests/fixtures/frame_hole_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")

## The hole to frame.
@export var hole: int = 2
## Play the hole at the farthest zoom with guests out, rather than frame it in Build.
@export var play: bool = false
## Simulated seconds of the guests' day before the capture, in Play.
@export var guest_s: int = 150


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	main.show_course(c)
	main.frame_hole(hole)
	if not play:
		return
	# The player's own zoom: the farthest step, which Play's camera comes back to.
	for i: int in main.camera.tuning.zoom_levels.size():
		main.camera.step_zoom(-1)
	main.set_mode(Main.Mode.PLAY)
	var sim := main.guest_sim
	for i: int in guest_s:
		sim.advance(1.0)
	sim.set_speed(0.0)
