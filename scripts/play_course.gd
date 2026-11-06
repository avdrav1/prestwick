extends SceneTree
## Opens the game on a course for a hand playtest, since there is no load menu until E4-S7.
##   godot --path . -s scripts/play_course.gd -- playtest        # courses/playtest_nine.json (E3-S50)
##   godot --path . -s scripts/play_course.gd -- playtest --rebuild
##   godot --headless --path . -s scripts/play_course.gd -- playtest --save-only
##   godot --path . -s scripts/play_course.gd -- nine            # nine_holes fixture (E3-S2)
##   godot --path . -s scripts/play_course.gd -- hazards         # nine_holes_hazards (E3-S23)
##   godot --path . -s scripts/play_course.gd -- res://courses/example_par3.json
## A fixture is built through CourseBuilder on land seed 7 and saved to
## user://playtest_<name>.json, which the main scene then loads as any course file.
## `playtest` opens courses/playtest_nine.json, the nine with doglegs and contoured greens
## (tests/fixtures/playtest_nine.gd); `--rebuild` first rebuilds that file from the fixture
## (and so does a missing file), `--save-only` rebuilds it and quits without opening the game.

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const NineHolesHazards := preload("res://tests/fixtures/nine_holes_hazards.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const LAND_SEED := 7


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var which: String = args[0] if not args.is_empty() else "hazards"
	var path := which
	if which == "playtest":
		path = PlaytestNine.PATH
		var save_only := args.has("--save-only")
		if save_only or args.has("--rebuild") or not FileAccess.file_exists(path):
			if not _save(PlaytestNine.course(), path, which):
				return
		if save_only:
			quit(0)
			return
	elif which == "nine" or which == "hazards":
		var fixture: GDScript = NineHoles if which == "nine" else NineHolesHazards
		var course: CourseData = fixture.land(LAND_SEED)
		fixture.build(CourseBuilder.new(course))
		path = "user://playtest_%s.json" % which
		if not _save(course, path, which):
			return
	var main := (load(MAIN_SCENE) as PackedScene).instantiate() as Main
	main.course_path = path
	main.land_seed = LAND_SEED
	root.add_child(main)


func _save(course: CourseData, path: String, which: String) -> bool:
	var err := CourseSave.save_file(course, path)
	if err != OK:
		push_error("play_course: could not save %s (%s)" % [path, error_string(err)])
		quit(1)
		return false
	var open: Array[int] = []
	for h: HoleData in course.holes:
		if h.open:
			open.append(h.number)
	print("play_course: %s, holes open %s, saved to %s" % [which, open, ProjectSettings.globalize_path(path)])
	return true
