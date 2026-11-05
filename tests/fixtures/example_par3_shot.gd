class_name ExamplePar3Shot
extends Node2D
## Screenshot fixture for E2-S2: the main scene showing courses/example_par3.json, its tee
## marker and pin. Run: scripts/screenshot.sh tests/fixtures/example_par3_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COURSE_PATH: String = "res://courses/example_par3.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = COURSE_PATH
	add_child(main)
	# 0.5x, so the whole 160 yd hole fits the window.
	main.camera.set_zoom_level(0.5)
