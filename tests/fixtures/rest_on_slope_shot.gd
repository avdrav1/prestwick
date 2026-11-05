class_name RestOnSlopeShot
extends Node2D
## Screenshot fixture for E2-S7 (D17): the E1-S9 green contour in Play at 2x, a 6 yd/s
## uphill putt from the front tier at rest partway up a one-step slope, drawn on the tile
## top, with the putter's aim (dots along the predicted roll, and its rest point) from there.
## Run: scripts/screenshot.sh tests/fixtures/rest_on_slope_shot.tscn (2x), or
## tests/fixtures/rest_on_slope_shot_1x.tscn for the same putt at 1x.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## The camera's zoom (one of CameraTuning.zoom_levels): 2.0 is 2x, 1.0 is 1x.
@export var zoom_level: float = 2.0


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	var course := GridHeightEvidence.green_contour()
	main.show_course(course)
	main.set_mode(Main.Mode.PLAY)
	var sc := main.swing_control
	sc.set_process(false)
	main.shot_view.set_process(false)
	var model := ShotModel.new()
	var field := HeightField.new(course, model.params)
	var from := (Vector2(4.5, 5.5) + Vector2(0.5, 0.5)) * 5.0
	main.shot_view.fire_launch(course, model.putt(field, model.clubs.putter(), 6.0, from, 0.0), 1)
	main.shot_view.advance(30.0)
	# A shot fired straight through ShotView is not a swing, so put the swing ball there.
	var rest := main.shot_view.ball.position
	sc.place_ball(Vector2(rest.x, rest.y), false, false)
	sc.rotate_aim(-25.0 - sc.aim_deg)
	sc._refresh_aim()
	main.camera.set_zoom_level(zoom_level)
	main.camera.position = main.shot_view.ball_screen()
	main.camera.tracking = false
