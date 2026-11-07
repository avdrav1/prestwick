class_name NineHazardsShot
extends Node2D
## Screenshot fixture for E3-S48: tests/fixtures/nine_holes_hazards.gd in Build, centred on
## hole 1's crest cut (tiles CREST_FROM to CREST_TO of hole 1's tee row, one step under a
## 3-tile brush) at NINE_ZOOM (default 1), so the cut that makes hole 1 fair can be seen.
## NINE_AT=tee centres the tee instead, NINE_AT=hole frames hole 1 as the hole list does.
##   scripts/screenshot.sh tests/fixtures/nine_hazards_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const NineHolesHazards := preload("res://tests/fixtures/nine_holes_hazards.gd")


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	var c := NineHolesHazards.land(7)
	NineHolesHazards.build(CourseBuilder.new(c))
	main.show_course(c)
	main.frame_hole(1)
	var where := OS.get_environment("NINE_AT")
	if where == "hole":
		return
	var hole1: Array = NineHoles.HOLES[0]
	var row: int = (hole1[2] as Vector2i).y
	var cell := Vector2i((NineHolesHazards.CREST_FROM + NineHolesHazards.CREST_TO) / 2, row)
	if where == "tee":
		cell = hole1[2]
	var zs := OS.get_environment("NINE_ZOOM")
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 1.0)
	var at: Vector2 = main.tile_world(cell)
	# Centre it in the view the HUD leaves free, not under the hole list.
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift
