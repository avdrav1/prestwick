class_name HoleOpenNoticeShot
extends Node2D
## Screenshot fixture for E8-S1 (D64): the main scene in Build on the flat 20 x 20 plot, just
## after hole 1's cup lands on its green, so the hole opens itself and the notice "Hole 1 is
## open: guests will play it" shows over the map, above the palette.
## Run: scripts/screenshot.sh tests/fixtures/hole_open_notice_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _main: Main


func _ready() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(_main)
	var b: CourseBuilder = _main.build_tool.builder
	b.paint(Vector2i(15, 10), Surface.Type.GREEN, 3)
	b.begin_stroke()
	for x: int in range(5, 13):
		b.paint(Vector2i(x, 10), Surface.Type.FAIRWAY, 3)
	b.end_stroke()
	b.paint(Vector2i(2, 10), Surface.Type.TEE, 3)
	b.place_tee(1, Vector2i(2, 10), 3)
	b.place_cup(1, Vector2i(15, 10))
