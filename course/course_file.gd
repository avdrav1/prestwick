class_name CourseFileTool
extends SceneTree
## The headless entry point of the /course-file skill (.claude/skills/course-file/SKILL.md).
##
##   godot --headless --path . -s res://course/course_file.gd -- validate <path>
##   godot --headless --path . -s res://course/course_file.gd -- generate <par> [flat|hilly] [water|dry] [--out=<path>]
##
## validate runs the game's own validator (course/validator.gd) on the file and prints each
## rule of each hole as pass or FAIL, with the tile at fault and the reason. generate writes
## a CourseGenerator course, by default to courses/gen_par<par>_<terrain>_<water>.json.
## Paths without res:// or user:// are taken from the project folder.
##
## Exit code: 0 when every rule passes (or the file was written), 1 when a rule fails or the
## write fails, 2 for bad arguments or a file that will not load.


func _initialize() -> void:
	var out: Array[String] = []
	var code: int = run(OS.get_cmdline_user_args(), out)
	for line: String in out:
		print(line)
	quit(code)


## Runs one command, appending its output lines to `out`. Returns the exit code.
static func run(args: PackedStringArray, out: Array[String]) -> int:
	if args.is_empty():
		return _usage(out)
	match args[0]:
		"validate":
			if args.size() != 2:
				return _usage(out)
			return validate(_resolve(args[1]), out)
		"generate":
			return _generate(args.slice(1), out)
	return _usage(out)


## Validates the course file at `path`; see the exit codes above.
static func validate(path: String, out: Array[String]) -> int:
	var errors: Array[String] = []
	var course := CourseSave.load_file(path, errors)
	if course == null:
		out.append("%s: does not load" % path)
		for e: String in errors:
			out.append("  %s" % e)
		return 2
	out.append("%s: \"%s\", %dx%d, %d hole(s)" % [path, course.course_name, course.width, course.height,
			course.holes.size()])
	if course.holes.is_empty():
		out.append("result: PASS (no holes to check)")
		return 0
	var validator := CourseValidator.new()
	var failed: bool = false
	for hole: HoleData in course.holes:
		var issues := validator.check_hole(course, hole)
		out.append("hole %d, par %d, %d yd" % [hole.number, hole.par, CourseValidator.yardage(hole.tee, hole.cup)])
		for rule: int in range(1, CourseValidator.RULE_COUNT + 1):
			var line := "  rule %d pass" % rule
			for issue: CourseValidator.Issue in issues:
				if issue.rule == rule:
					line = "  rule %d FAIL at (%d, %d): %s" % [rule, issue.tile.x, issue.tile.y, issue.reason]
					failed = true
					break
			out.append(line)
	out.append("result: %s" % ("FAIL" if failed else "PASS"))
	return 1 if failed else 0


static func _generate(args: PackedStringArray, out: Array[String]) -> int:
	if args.is_empty() or not args[0].is_valid_int():
		return _usage(out)
	var par: int = args[0].to_int()
	var hilly: bool = false
	var water: bool = false
	var path: String = ""
	for a: String in args.slice(1):
		match a:
			"flat":
				hilly = false
			"hilly":
				hilly = true
			"dry":
				water = false
			"water":
				water = true
			_:
				if a.begins_with("--out="):
					path = _resolve(a.substr(6))
				else:
					return _usage(out)
	var errors: Array[String] = []
	var course := CourseGenerator.generate(par, hilly, water, errors)
	if course == null:
		for e: String in errors:
			out.append("generate: %s" % e)
		return 2
	if path.is_empty():
		path = "res://courses/gen_par%d_%s_%s.json" % [par, "hilly" if hilly else "flat", "water" if water else "dry"]
	var err: Error = CourseSave.save_file(course, path)
	if err != OK:
		out.append("generate: cannot write %s (%s)" % [path, error_string(err)])
		return 1
	out.append("generate: wrote %s" % path)
	return validate(path, out)


static func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	return "res://" + path.trim_prefix("./")


static func _usage(out: Array[String]) -> int:
	out.append("usage: course_file.gd -- validate <path>")
	out.append("       course_file.gd -- generate <par> [flat|hilly] [water|dry] [--out=<path>]")
	return 2
