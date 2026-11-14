extends SceneTree
## E18-S6: rebuilds courses/old_grey_championship.json from tests/fixtures/old_grey_championship.gd
## (OldGreyChampionship) and quits. Writes only that file; run it with a throwaway user folder:
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s scripts/save_old_grey_championship.gd


func _initialize() -> void:
	var course := OldGreyChampionship.course()
	var err := CourseSave.save_file(course, OldGreyChampionship.PATH)
	if err != OK:
		push_error("save_old_grey_championship: could not save %s (%s)" % [
				OldGreyChampionship.PATH, error_string(err)])
		quit(1)
		return
	var open: Array[int] = []
	for h: HoleData in course.holes:
		if h.open:
			open.append(h.number)
	print("save_old_grey_championship: holes open %s, saved to %s" % [open, OldGreyChampionship.PATH])
	quit(0)
