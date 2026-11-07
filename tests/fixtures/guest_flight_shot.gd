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
## E3-S38: with `catch_tee_swing` (guest_flight_shot_tee_swing.tscn) it pauses at the top of a
## tee shot's swing by a guest whose partners all still stand on the tee, so the picture shows
## them stepped aside round the striker.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GuestCourse := preload("res://tests/fixtures/guest_course.gd")

## E3-S20: pause as the drawn ball lands, not as it first flies.
@export var catch_landing: bool = false
@export var landing_ticks: float = 15.0
## E3-S38: pause mid-swing on a tee with partners beside the striker.
@export var catch_tee_swing: bool = false
## The guest days' base seed (GuestSim.start), or below 0 for the course's own.
@export var day_base_seed: int = -1

var main: Main
var caught: bool = false


func _ready() -> void:
	main = MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	main.show_course(GuestCourse.course())
	if day_base_seed >= 0:
		main.guest_sim.start(main.course, day_base_seed)
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
		if catch_tee_swing:
			if f.guest.state == Guest.State.PLAYING and f.guest.hole.strokes.size() == 1 \
					and f.spread <= 0.0 \
					and _partners_on_tee(f.guest):
				caught = true
				main.guest_sim.set_speed(0.0)
				return
			continue
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


## E3-S38: every partner of `guest` (a group of three or more) has yet to strike.
func _partners_on_tee(guest: Guest) -> bool:
	var g: GuestGroup = main.guest_sim.brain.group_of(guest)
	if g.size() < 3:
		return false
	for o: Guest in g.guests:
		if o != guest and (o.hole == null or not o.hole.strokes.is_empty()):
			return false
	return true
