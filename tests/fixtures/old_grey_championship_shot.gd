class_name OldGreyChampionshipShot
extends Node2D
## Screenshot fixture for E18-S6: Old Grey Links (Championship) (courses/old_grey_championship.json)
## in Build. OGC_SHOT picks the view: `course` (the default) shows the whole course centred at
## OGC_ZOOM (default 0.175x) with the hole list collapsed; `hole:<n>` centres hole n at 0.5x
## (OGC_ZOOM overrides the zoom) on OGC_AT, `tee`, `cup` or `mid` (the default); `turn` centres
## the clubhouse at 0.5x.
##   OGC_SHOT=hole:14 scripts/screenshot.sh tests/fixtures/old_grey_championship_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	var c := CourseSave.load_file(OldGreyChampionship.PATH)
	main.show_course(c)
	main.hole_panel.set_collapsed(true)
	var spec: PackedStringArray = OS.get_environment("OGC_SHOT").split(":")
	var zs := OS.get_environment("OGC_ZOOM")
	var at: Vector2 = main.course_view.screen_bounds().get_center()
	var z := 0.175
	if spec.size() == 2 and spec[0] == "hole":
		z = 0.5
		for h: HoleData in c.holes:
			if h.number != spec[1].to_int():
				continue
			var tee := main.tile_world(h.tee)
			var cup := main.tile_world(h.cup)
			match OS.get_environment("OGC_AT"):
				"tee":
					at = tee
				"cup":
					at = cup
				_:
					at = (tee + cup) * 0.5
	elif spec.size() == 1 and spec[0] == "turn":
		z = 0.5
		at = main.tile_world(c.clubhouse)
	if zs != "":
		z = zs.to_float()
	main.camera.set_zoom_level(z)
	main.camera.centre_on(at)
	main.camera.position = at
