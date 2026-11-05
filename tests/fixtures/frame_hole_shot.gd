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
## frame_hole_shot_across.tscn (`across_steps`, E3-S26) is a plot of eight par 3 rows and a
## hole 9 running straight across the screen, too long for either free strip even at 0.175x,
## framed with its cup clear of the hole panel (tests/test_course_camera.gd builds the same).
## Run: scripts/screenshot.sh tests/fixtures/frame_hole_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")

## The hole to frame.
@export var hole: int = 2
## Play the hole at the farthest zoom with guests out, rather than frame it in Build.
@export var play: bool = false
## Simulated seconds of the guests' day before the capture, in Play.
@export var guest_s: int = 150
## When over 0, the across plot (above) with hole 9 this many tiles east and north, not nine_holes.
@export var across_steps: int = 0


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	var c: CourseData = across_course(across_steps) if across_steps > 0 else NineHoles.land(7)
	if across_steps <= 0:
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


## The across plot: eight par 3 rows down the top-left and hole 9 from (10, 124), `steps` tiles
## east and north, so it runs straight across the screen.
static func across_course(steps: int) -> CourseData:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	var b := CourseBuilder.new(c)
	for k: int in 8:
		var n: int = b.next_hole_number()
		b.paint(Vector2i(22, 3 + 7 * k), Surface.Type.GREEN, 1)
		b.place_tee(n, Vector2i(2, 3 + 7 * k), 3)
		b.place_cup(n, Vector2i(22, 3 + 7 * k))
	var tee := Vector2i(10, 124)
	var cup: Vector2i = tee + Vector2i(steps, -steps)
	b.paint(cup, Surface.Type.GREEN, 1)
	b.place_tee(9, tee, 3)
	b.place_cup(9, cup)
	return c
