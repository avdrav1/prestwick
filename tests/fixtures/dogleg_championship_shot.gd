class_name DoglegChampionshipShot
extends Node2D
## Screenshot fixture for E19-S1: Dogleg Hollow (Championship) (courses/dogleg_hollow_championship.json)
## in Build. DHC_SHOT picks the view: `course` (the default) shows the whole course centred at
## DHC_ZOOM (default 0.175x) with the hole list collapsed; `hole:<n>` centres hole n at 0.5x
## (DHC_ZOOM overrides the zoom) on DHC_AT, `tee`, `cup`, `bend` (its turn, D47) or `mid` (the
## default); `turn` centres the clubhouse at 0.5x.
##   DHC_SHOT=hole:14 DHC_AT=bend scripts/screenshot.sh tests/fixtures/dogleg_championship_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	var c := CourseSave.load_file(DoglegChampionship.PATH)
	main.show_course(c)
	main.hole_panel.set_collapsed(true)
	var spec: PackedStringArray = OS.get_environment("DHC_SHOT").split(":")
	var zs := OS.get_environment("DHC_ZOOM")
	var at: Vector2 = main.course_view.screen_bounds().get_center()
	var z := 0.175
	if spec.size() == 2 and spec[0] == "hole":
		z = 0.5
		for h: HoleData in c.holes:
			if h.number != spec[1].to_int():
				continue
			var tee := main.tile_world(h.tee)
			var cup := main.tile_world(h.cup)
			match OS.get_environment("DHC_AT"):
				"tee":
					at = tee
				"cup":
					at = cup
				"bend":
					var turn: Variant = CourseValidator.new().turn_point(c, h)
					var t: Vector2 = turn if turn != null else Vector2(h.tee + h.cup) * 0.5
					at = main.tile_world(Vector2i(roundi(t.x), roundi(t.y)))
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
