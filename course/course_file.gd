class_name CourseFileTool
extends SceneTree
## The headless entry point of the /course-file skill (.claude/skills/course-file/SKILL.md).
##
##   godot --headless --path . -s res://course/course_file.gd -- validate <path>
##   godot --headless --path . -s res://course/course_file.gd -- generate <par> [flat|hilly] [water|dry] [--out=<path>]
##   godot --headless --path . -s res://course/course_file.gd -- inspect <path>
##
## validate runs the game's own validator (course/validator.gd) on the file and prints each
## rule of each hole as pass or FAIL, with the tile at fault and the reason. generate writes
## a CourseGenerator course, by default to courses/gen_par<par>_<terrain>_<water>.json.
## inspect prints the size, the height range, the tile count of each surface present, and
## one line per hole (par, yardage, open or closed, the validator's PASS or FAIL) with a line
## for each failing rule. Paths without res:// or user:// are taken from the project folder.
##
## Exit code: 0 when every rule passes (or the file was written, or inspected), 1 when a rule
## fails or the write fails, 2 for bad arguments or a file that will not load. inspect only
## reports: a failing rule does not change its exit code.


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
		"inspect":
			if args.size() != 2:
				return _usage(out)
			return inspect(_resolve(args[1]), out)
	return _usage(out)


## Validates the course file at `path`; see the exit codes above.
static func validate(path: String, out: Array[String]) -> int:
	var course := _load(path, out)
	if course == null:
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


## Prints what the course file at `path` holds; see the exit codes above.
static func inspect(path: String, out: Array[String]) -> int:
	var course := _load(path, out)
	if course == null:
		return 2
	out.append("%s: \"%s\" by \"%s\"" % [path, course.course_name, course.author])
	out.append("size: %dx%d tiles (%d x %d yd)" % [course.width, course.height,
			roundi(course.width * CourseValidator.YARDS_PER_TILE), roundi(course.height * CourseValidator.YARDS_PER_TILE)])
	var counts: Array[int] = []
	counts.resize(Surface.NAMES.size())
	var lo: int = CourseData.MAX_HEIGHT
	var hi: int = 0
	for y: int in course.height:
		for x: int in course.width:
			counts[course.get_surface(x, y)] += 1
			lo = mini(lo, course.get_height(x, y))
			hi = maxi(hi, course.get_height(x, y))
	out.append("heights: %d to %d" % [lo, hi])
	var parts: PackedStringArray = []
	for s: int in counts.size():
		if counts[s] > 0:
			parts.append("%s %d" % [Surface.name_of(s), counts[s]])
	out.append("surfaces: %s" % ", ".join(parts))
	out.append("holes: %d" % course.holes.size())
	var validator := CourseValidator.new()
	var reach := CourseValidator.Reach.new(course)
	for hole: HoleData in course.holes:
		var issues := validator.check_hole(course, hole, reach)
		out.append("hole %d: par %d, %d yd, %s, %s" % [hole.number, hole.par,
				CourseValidator.yardage(hole.tee, hole.cup), "open" if hole.open else "closed",
				"FAIL" if not issues.is_empty() else "PASS"])
		for issue: CourseValidator.Issue in issues:
			out.append("  rule %d FAIL at (%d, %d): %s" % [issue.rule, issue.tile.x, issue.tile.y, issue.reason])
	return 0


static func _load(path: String, out: Array[String]) -> CourseData:
	var errors: Array[String] = []
	var course := CourseSave.load_file(path, errors)
	if course == null:
		out.append("%s: does not load" % path)
		for e: String in errors:
			out.append("  %s" % e)
	return course


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
	out.append("       course_file.gd -- inspect <path>")
	return 2
