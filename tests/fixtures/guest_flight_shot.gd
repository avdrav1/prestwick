class_name GuestFlightShot
extends Node2D
## Screenshot fixture for E3-S5's ball flights (by hand): the guest course
## (tests/fixtures/guest_course.gd) in Play at 3x with hole 1 framed. The first time an
## on-screen guest's ball is drawn in the air (GuestView's replay), the fixture pauses the
## day with the Pause button's speed, so the picture holds the ball over its shadow and the
## speed panel shows Pause pressed. Run with enough frames for the first tee shot:
## scripts/screenshot.sh tests/fixtures/guest_flight_shot.tscn out.png 240
## E3-S20: with `catch_landing` (guest_flight_shot_landing.tscn) it pauses instead as a tee
## shot's drawn ball is about to rest, `landing_ticks` ticks from its end: its guest still
## stands on the tee, in its finish, and has not set off after it.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GuestCourse := preload("res://tests/fixtures/guest_course.gd")

## E3-S20: pause as the drawn ball lands, not as it first flies.
@export var catch_landing: bool = false
@export var landing_ticks: float = 15.0

var main: Main
var caught: bool = false


func _ready() -> void:
	main = MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	main.show_course(GuestCourse.course())
	main.set_mode(Main.Mode.PLAY)
	main.swing_panel.visible = false
	main.set_process(false)
	main.aim_view.visible = false
	main.guest_sim.set_speed(3.0)
	main.camera.set_zoom_level(2.0)
	main.camera.tracking = false
	main.camera.position = main.tile_world(Vector2i(8, 6))


func _process(_delta: float) -> void:
	if caught:
		return
	for f: GuestView.Figure in main.guest_view.figures().values():
		if catch_landing:
			if main.guest_view.is_replaying(f) and f.guest.hole.strokes.size() == 1 \
					and f.replay_head > f.replay_hole.stroke_path().size() - 1 - landing_ticks:
				caught = true
				main.guest_sim.set_speed(0.0)
				return
			continue
		if f.ball_flying and f.replay_head > 20.0:
			caught = true
			main.guest_sim.set_speed(0.0)
			return
