class_name PlaytestNineShot
extends Node2D
## Screenshot fixture for E3-S50: the playtest nine (tests/fixtures/playtest_nine.gd) in Build.
## PLAYTEST_SHOT picks the view: `green:<n>` centres hole n's cup at 1x (its green's contours),
## `corner:<n>` centres dogleg n's turn (CourseValidator.turn_point, D47) at 0.5x, `hole:<n>`
## frames hole n's tee and cup as the hole list does (Main.frame_hole), `course` shows the
## whole course at the farthest zoom with the hole list collapsed, and `open` (the default)
## leaves the camera where Main.show_course put it: hole 1 framed by Main.frame_first_hole,
## the game's opening frame.
##   PLAYTEST_SHOT=green:3 scripts/screenshot.sh tests/fixtures/playtest_nine_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH: String = "res://tests/fixtures/flat_20x20.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = FLAT_PATH
	add_child(main)
	var c := PlaytestNine.land()
	PlaytestNine.build(CourseBuilder.new(c))
	main.show_course(c)
	var spec: PackedStringArray = OS.get_environment("PLAYTEST_SHOT").split(":")
	var view: String = spec[0] if not spec.is_empty() and spec[0] != "" else "open"
	var n: int = spec[1].to_int() if spec.size() == 2 else 1
	if view == "open":
		return
	if view == "course":
		# The list collapsed to hole 1's row, so the east corner of the map shows.
		main.hole_panel.set_collapsed(true)
		main.camera.set_zoom_level(0.175)
		main.camera.centre_on(main.course_view.screen_bounds().get_center())
		main.camera.position = main.course_view.screen_bounds().get_center()
		return
	main.frame_hole(n)
	if view != "green" and view != "corner":
		return
	var at := Vector2.ZERO
	for h: HoleData in c.holes:
		if h.number != n:
			continue
		var cell: Vector2i = h.cup
		if view == "corner":
			var turn: Variant = CourseValidator.new().turn_point(c, h)
			if turn != null:
				cell = Vector2i((turn as Vector2).round())
		at = main.tile_world(cell)
	main.camera.set_zoom_level(1.0 if view == "green" else 0.5)
	# Centre the cup in the view the HUD leaves free, not under the hole list.
	var free: Rect2 = main.free_view_rect()
	var shift: Vector2 = (main.camera.view_size() * 0.5 - free.get_center()) / main.camera.zoom.x
	main.camera.centre_on(at + shift)
	main.camera.position = at + shift
