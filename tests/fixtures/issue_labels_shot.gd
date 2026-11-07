class_name IssueLabelsShot
extends Node2D
## Screenshot fixture for E3-S40: nine_holes (tests/fixtures/nine_holes.gd) in Build with every
## hole failing two rules (its cup on rough, its par wrong) and holes 4 and 5 sharing number 4,
## so a rule-1 badge stands on a tee beside its "4a" or "4b". ISSUE_SHOT picks the view:
## `course` (the default) the whole map at ISSUE_ZOOM (default 0.175) with the hole list
## collapsed, `hole:<n>` frames hole n as the hole list does (Main.frame_hole), and `hill` the
## tee of hole 1 behind a raised knoll at 0.5x, its number over the terrain.
##   ISSUE_SHOT=course scripts/screenshot.sh tests/fixtures/issue_labels_shot.tscn out.png

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child(main)
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	var view: String = OS.get_environment("ISSUE_SHOT")
	if view == "hill":
		_hill(main, c)
		return
	var data: Dictionary = c.to_dict()
	for h: Dictionary in data["holes"]:
		if int(h["number"]) == 5:
			h["number"] = 4
	c = CourseSave.from_json(JSON.stringify(data))
	main.show_course(c)
	var b: CourseBuilder = main.build_tool.builder
	for spec: Array in NineHoles.HOLES:
		b.paint(spec[3], Surface.Type.ROUGH, 1)
	for slot: int in c.holes.size():
		var h: HoleData = c.holes[slot]
		b.set_par(h.number, 5 if h.par != 5 else 3, slot)
	if view.begins_with("hole:"):
		main.frame_hole(view.split(":")[1].to_int())
		return
	main.hole_panel.set_collapsed(true)
	var zs := OS.get_environment("ISSUE_ZOOM")
	main.camera.set_zoom_level(zs.to_float() if zs != "" else 0.175)
	main.camera.centre_on(main.course_view.screen_bounds().get_center())
	main.camera.position = main.course_view.screen_bounds().get_center()


## Hole 1's tee behind a knoll five steps up just in front of it (toward the camera), at 0.5x.
func _hill(main: Main, c: CourseData) -> void:
	var tee: Vector2i = NineHoles.HOLES[0][2]
	var b := CourseBuilder.new(c)
	for y: int in range(tee.y + 1, tee.y + 4):
		for x: int in range(tee.x + 1, tee.x + 4):
			for k: int in 5:
				b.raise(Vector2i(x, y), 1)
	main.show_course(c)
	main.camera.set_zoom_level(0.5)
	var at: Vector2 = main.tile_world(tee)
	main.camera.centre_on(at)
	main.camera.position = at
