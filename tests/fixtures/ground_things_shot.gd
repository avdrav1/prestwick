class_name GroundThingsShot
extends Node2D
## Screenshot fixture for E3-S59 (D50): things on the ground drawn on the smooth ground, at
## GROUND_ZOOM (default 2). GROUND_SHOT picks the picture:
##   `bank`: the E1-S9 green contour mirrored (falling one step a tile along +x), an 8 yd/s
##     putt rolling down it, stopped part way down a bank: the ball and its shadow on the slope.
##   `behind`: the guest course (tests/fixtures/guest_course.gd, ground 2) with a ridge of 5
##     across columns 10 to 12. A golfer stands at x 8.6 behind it (further from the camera)
##     and the player's ball at x 8.75; another golfer on the ridge's top. The ridge's back slope
##     (three steps in a tile) hides the first golfer's feet and the ball, the golfer's head
##     shows over it; the one on top shows whole.
##   GROUND_SHOT=bank scripts/screenshot.sh tests/fixtures/ground_things_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GuestCourse := preload("res://tests/fixtures/guest_course.gd")


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	var zs := OS.get_environment("GROUND_ZOOM")
	var zoom: float = zs.to_float() if zs != "" else 2.0
	if OS.get_environment("GROUND_SHOT") == "behind":
		_behind(main, zoom)
	else:
		_bank(main, zoom)


func _bank(main: Main, zoom: float) -> void:
	var course := GridHeightEvidence.green_contour(true)
	main.show_course(course)
	main.set_mode(Main.Mode.PLAY)
	main.swing_control.set_process(false)
	main.shot_view.set_process(false)
	var model := ShotModel.new()
	var field := HeightField.new(course, model.params)
	var from := (Vector2(4.2, 5.5) + Vector2(0.5, 0.5)) * 5.0
	main.shot_view.fire_launch(course, model.putt(field, model.clubs.putter(), 8.0, from, 0.0), 1)
	# Stop it part way down the first bank it reaches.
	var start: int = course.get_height(int(from.x / 5.0), int(from.y / 5.0))
	for i: int in 600:
		main.shot_view.advance(1.0 / 60.0)
		var p := main.shot_view.ball.position
		var steps := field.height_at(p.x, p.y) / field.yards_per_step
		if steps < start - 0.4 and absf(steps - roundf(steps)) > 0.3:
			break
	main.aim_view.visible = false
	main.set_process(false)
	main.camera.set_zoom_level(zoom)
	main.camera.tracking = false
	main.camera.position = main.shot_view.ball_screen()


func _behind(main: Main, zoom: float) -> void:
	var c := GuestCourse.course()
	for y: int in c.height:
		for x: int in range(10, 13):
			c.set_tile(x, y, 5, c.get_surface(x, y))
	main.show_course(c)
	main.set_mode(Main.Mode.PLAY)
	main.swing_panel.visible = false
	var sim := main.guest_sim
	while sim.brain == null or sim.brain.guests.size() < 2:
		sim.advance(1.0)
	sim.set_speed(0.0)
	var field := sim.brain.field
	# Behind the ridge's foot (further from the camera), and on its top.
	var spots: Array[Vector2] = [Vector2(8.6, 11.0), Vector2(11.0, 8.0)]
	for i: int in spots.size():
		var g: Guest = sim.brain.guests[i]
		g.position = (spots[i] + Vector2(0.5, 0.5)) * field.yards_per_tile
		g.walk = null
		g.state = Guest.State.WAITING
		g.place = 0
	main.guest_view.clear()
	var ball := (Vector2(8.75, 9.5) + Vector2(0.5, 0.5)) * field.yards_per_tile
	main.swing_control.place_ball(ball, false, true)
	main.swing_control.set_process(false)
	main.aim_view.visible = false
	main.set_process(false)
	main.camera.set_zoom_level(zoom)
	main.camera.tracking = false
	main.camera.position = main.tile_world(Vector2i(10, 11))
