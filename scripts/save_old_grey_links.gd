extends SceneTree
## E13-S2: rebuilds courses/old_grey_links.json from tests/fixtures/old_grey_links.gd
## (OldGreyLinks) and quits. Writes only that file; run it with a throwaway user folder:
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s scripts/save_old_grey_links.gd


func _initialize() -> void:
	var course := OldGreyLinks.course()
	var err := CourseSave.save_file(course, OldGreyLinks.PATH)
	if err != OK:
		push_error("save_old_grey_links: could not save %s (%s)" % [OldGreyLinks.PATH, error_string(err)])
		quit(1)
		return
	var open: Array[int] = []
	for h: HoleData in course.holes:
		if h.open:
			open.append(h.number)
	print("save_old_grey_links: holes open %s, saved to %s" % [open, OldGreyLinks.PATH])
	quit(0)
