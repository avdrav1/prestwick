class_name EighteenShot
extends Node2D
## Screenshot fixture for E18-S2: eighteen open par 3s on a New sandbox (D71's 192 x 192 plot),
## in two columns of nine, so the hole list groups into Out (1 to 9) and In (10 to 18). The
## hole EIGHTEEN_PICK (default 12) is picked, so its nine is open and the other folded;
## EIGHTEEN_COLLAPSE=1 collapses the list to its row.
##   EIGHTEEN_PICK=3 scripts/screenshot.sh tests/fixtures/eighteen_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	var c := CourseBuilder.new_sandbox()
	var b := CourseBuilder.new(c)
	for k: int in 18:
		@warning_ignore("integer_division")
		var tee := Vector2i(40 + 70 * (k / 9), 40 + 10 * (k % 9))
		var cup := tee + Vector2i(25 + 2 * (k % 4), 0)
		b.paint(cup, Surface.Type.GREEN, 3)
		b.paint(tee, Surface.Type.TEE, 1)
		b.place_tee(k + 1, tee, 3)
		b.place_cup(k + 1, cup)
	main.show_course(c)
	var pick := OS.get_environment("EIGHTEEN_PICK")
	var n: int = pick.to_int() if pick != "" else 12
	main.frame_hole(n, -1, OS.get_environment("EIGHTEEN_COLLAPSE") == "1")
