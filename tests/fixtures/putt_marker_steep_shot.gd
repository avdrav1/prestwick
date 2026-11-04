class_name PuttMarkerSteepShot
extends Node2D
## Screenshot fixture for E6-S12: the main scene in Play on a green rising two steps per
## tile (a bank no ball rests on), the cup on the bank and the ball below it. The putter's
## solve runs over frames as in play (SwingTuning.putt_aim_frame_ticks a frame); the
## marker settles on the putt that drops, found in a capture window 2% of the bar wide.
## Run: scripts/screenshot.sh tests/fixtures/putt_marker_steep_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"
const CUP := Vector2i(11, 6)

var _main: Main
var _reported: bool = false


func _ready() -> void:
	var course := CourseData.create(30, 12, Surface.Type.GREEN, 0)
	for y in 12:
		for x in 30:
			course.set_tile(x, y, clampi((x - 10) * 2, 0, 7), Surface.Type.GREEN)
	course.set_holes([HoleData.new(1, 3, Vector2i(1, 6), CUP, true)] as Array[HoleData])
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = FLAT_PATH
	add_child(_main)
	_main.show_course(course)
	_main.set_mode(Main.Mode.PLAY)
	var sc := _main.swing_control
	sc.place_ball(Vector2(45.0, 31.0))
	sc.aim_at(sc.field.tile_center(CUP))
	_main.swing_panel.refresh()


func _process(_delta: float) -> void:
	var sc := _main.swing_control
	if _reported or sc.aim_putt == null or not sc.aim_putt.done:
		return
	_reported = true
	_main.swing_panel.refresh()
	print("steep putt marker: power %.2f, %d runs, %d ticks, miss %.2f yd, holed %s" % [
			sc.aim_power, sc.aim_putt.runs, sc.aim_putt.ticks, sc.aim_putt.miss_yd,
			sc.aim_putt.prediction.holed])
