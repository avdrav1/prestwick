class_name PuttMarkerShot
extends Node2D
## Screenshot fixture for E2-S20 (D21): the main scene in Play on the E1-S9 green contour
## with a cup on the second terrace, the ball on the lowest one, the putter's aim at the cup.
## The marker and dots show the putt at the pace that rests nearest the cup, not a 100% putt.
## Run: scripts/screenshot.sh tests/fixtures/putt_marker_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"


func _ready() -> void:
	var course := GridHeightEvidence.green_contour()
	course.set_holes([HoleData.new(1, 3, Vector2i(1, 5), Vector2i(7, 5), true)] as Array[HoleData])
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	main.show_course(course)
	main.set_mode(Main.Mode.PLAY)
	var sc := main.swing_control
	sc.set_process(false)
	sc.place_ball(Vector2(22.5, 37.5))
	sc.aim_at(sc.field.tile_center(Vector2i(7, 5)))
	sc.rotate_aim(-4.0)
	sc._refresh_aim()
	sc.settle_aim()
	main.swing_panel.refresh()
	print("putt marker: power %.2f, %d runs, miss %.2f yd" % [sc.aim_power, sc.aim_putt.runs, sc.aim_putt.miss_yd])
