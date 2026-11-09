class_name SaveNoticeShot
extends Node2D
## Screenshot fixture for E4-S7: the main scene just after loading tests/fixtures/
## save_v1_short_par4.json (a course saved before D33 with an open 280 yd par 4 and an open
## 350 yd par 3), so the load notice lists both holes the validator closed, with their reasons.
## Run: scripts/screenshot.sh tests/fixtures/save_notice_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _main: Main


func _ready() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(_main)
	_main.load_game("res://tests/fixtures/save_v1_short_par4.json")
