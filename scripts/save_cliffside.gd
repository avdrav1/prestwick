extends SceneTree
## E13-S4: rebuilds courses/cliffside.json from its fixture (tests/fixtures/cliffside.gd,
## Cliffside) and quits. Writes only that file, never user://.
##   godot --headless --path . -s res://scripts/save_cliffside.gd


func _initialize() -> void:
	var course := Cliffside.course()
	var err := CourseSave.save_file(course, Cliffside.PATH)
	if err != OK:
		push_error("save_cliffside: could not save %s (%s)" % [Cliffside.PATH, error_string(err)])
		quit(1)
		return
	var open: Array[int] = []
	for h: HoleData in course.holes:
		if h.open:
			open.append(h.number)
	print("save_cliffside: holes open %s, saved to %s" % [open, ProjectSettings.globalize_path(Cliffside.PATH)])
	quit(0)
