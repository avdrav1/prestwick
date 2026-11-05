class_name HoleListShot
extends Node2D
## Screenshot fixture for E3-S2: nine open holes in New sandbox on generated land
## (tests/fixtures/nine_holes.gd), loaded so the camera frames hole 1, then hole 3 picked and
## a fault on hole 7's green (closing it) so its issue box names the hole.
## hole_list_collapsed_shot.tscn (E3-S10) then collapses the list and frames hole 3 again, in the
## free view that follows the panel's height.
## hole_list_duplicate_shot.tscn (E3-S11) loads the course with hole 5 renumbered 4 through
## course/save.gd, so two rows share number 4, each marked with rule 1's text, and picks the
## second.
## Run: scripts/screenshot.sh tests/fixtures/hole_list_shot.tscn

## Collapse the list to the picked hole and frame it (E3-S10).
@export var collapse: bool = false
## Load hole 5 as a second hole 4 (E3-S11).
@export var duplicate: bool = false

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	if duplicate:
		var data: Dictionary = c.to_dict()
		for h: Dictionary in data["holes"]:
			if int(h["number"]) == 5:
				h["number"] = 4
		c = CourseSave.from_json(JSON.stringify(data))
		main.show_course(c)
		main.hole_panel.rows_for(4)[1].pick_button.pressed.emit()
		return
	main.show_course(c)
	main.hole_panel.row_for(3).pick_button.pressed.emit()
	main.build_tool.builder.paint(Vector2i(4, 44), Surface.Type.WATER, 1)
	main.build_tool.builder.paint(Vector2i(6, 44), Surface.Type.ROUGH, 1)
	if collapse:
		main.hole_panel.collapse_button.pressed.emit()
		main.frame_hole(3)
