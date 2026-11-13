extends SceneTree
## E13-S3: rebuilds courses/pine_ridge.json from tests/fixtures/pine_ridge.gd (PineRidge) and
## quits. Writes only res://courses/; run it with a throwaway user:// all the same:
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s res://tests/fixtures/pine_ridge_save.gd


func _initialize() -> void:
	var course := PineRidge.course()
	var err := CourseSave.save_file(course, PineRidge.PATH)
	if err != OK:
		push_error("pine_ridge_save: could not save %s (%s)" % [PineRidge.PATH, error_string(err)])
		quit(1)
		return
	var open: Array[int] = []
	for h: HoleData in course.holes:
		if h.open:
			open.append(h.number)
	print("pine_ridge_save: holes open %s, saved to %s" % [open, ProjectSettings.globalize_path(PineRidge.PATH)])
	quit(0)
