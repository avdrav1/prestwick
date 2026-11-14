extends SceneTree
## E19-S1: rebuilds courses/dogleg_hollow_championship.json from tests/fixtures/dogleg_championship.gd
## (DoglegChampionship) and quits. Writes only that file; run it with a throwaway user folder:
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s scripts/save_dogleg_championship.gd


func _initialize() -> void:
	var course := DoglegChampionship.course()
	var err := CourseSave.save_file(course, DoglegChampionship.PATH)
	if err != OK:
		push_error("save_dogleg_championship: could not save %s (%s)" % [
				DoglegChampionship.PATH, error_string(err)])
		quit(1)
		return
	var open: Array[int] = []
	for h: HoleData in course.holes:
		if h.open:
			open.append(h.number)
	print("save_dogleg_championship: holes open %s, saved to %s" % [open, DoglegChampionship.PATH])
	quit(0)
