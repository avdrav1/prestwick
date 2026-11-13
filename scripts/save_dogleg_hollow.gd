extends SceneTree
## E16-S1: rebuilds courses/dogleg_hollow.json from its fixture (tests/fixtures/dogleg_hollow.gd,
## DoglegHollow) and quits. Writes only that file; run it with a throwaway user:// all the same:
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s res://scripts/save_dogleg_hollow.gd


func _initialize() -> void:
	var course := DoglegHollow.course()
	var err := CourseSave.save_file(course, DoglegHollow.PATH)
	if err != OK:
		push_error("save_dogleg_hollow: could not save %s (%s)" % [DoglegHollow.PATH, error_string(err)])
		quit(1)
		return
	var open: Array[int] = []
	for h: HoleData in course.holes:
		if h.open:
			open.append(h.number)
	print("save_dogleg_hollow: holes open %s, saved to %s" % [open, ProjectSettings.globalize_path(DoglegHollow.PATH)])
	quit(0)
