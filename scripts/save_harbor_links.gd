extends SceneTree
## E13-S1: rebuilds courses/harbor_links.json from its fixture (tests/fixtures/harbor_links.gd,
## HarborLinks) and quits, as `scripts/play_course.gd -- playtest --save-only` does for the
## playtest nine. It writes only the course file, never user://.
##   godot --headless --path . -s scripts/save_harbor_links.gd


func _initialize() -> void:
	var course := HarborLinks.course()
	var err := CourseSave.save_file(course, HarborLinks.PATH)
	if err != OK:
		push_error("save_harbor_links: could not save %s (%s)" % [HarborLinks.PATH, error_string(err)])
		quit(1)
		return
	var open: Array[int] = []
	for h: HoleData in course.holes:
		if h.open:
			open.append(h.number)
	print("save_harbor_links: holes open %s, saved to %s" % [open, ProjectSettings.globalize_path(HarborLinks.PATH)])
	quit(0)
