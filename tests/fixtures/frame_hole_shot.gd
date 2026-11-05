class_name FrameHoleShot
extends Node2D
## Screenshot fixture for E3-S9: nine open holes in New sandbox on generated land
## (tests/fixtures/nine_holes.gd), with hole `hole` framed clear of the HUD (Main.frame_hole).
## frame_hole_shot.tscn frames hole 2, a par 3 whose tee and cup both fit at 0.5x;
## frame_hole_shot_long.tscn frames hole 8, a par 5 too long for 0.5x, which favours its tee.
## Run: scripts/screenshot.sh tests/fixtures/frame_hole_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")

## The hole to frame.
@export var hole: int = 2


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	main.show_course(c)
	main.frame_hole(hole)
