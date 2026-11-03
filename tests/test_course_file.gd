extends GutTest
## /course-file inspect and generate hilly (E2-S18): course/course_file.gd and
## course/course_generator.gd. validate and generate flat are tested in tests/test_validator.gd.

const EXAMPLE_PATH := "res://courses/example_par3.json"

var _v: CourseValidator


func before_each() -> void:
	_v = CourseValidator.new()


func _height_range(c: CourseData) -> Vector2i:
	var lo: int = CourseData.MAX_HEIGHT
	var hi: int = 0
	for y: int in c.height:
		for x: int in c.width:
			lo = mini(lo, c.get_height(x, y))
			hi = maxi(hi, c.get_height(x, y))
	return Vector2i(lo, hi)


# --- generate hilly ---

func test_generated_hilly_par4_passes_the_validator() -> void:
	var errors: Array[String] = []
	var c := CourseGenerator.generate(4, true, false, errors)
	assert_not_null(c, "generates: %s" % [errors])
	if c == null:
		return
	assert_eq(c.holes.size(), 1)
	assert_eq(c.holes[0].par, 4)
	assert_eq(_v.check_course(c), {1: [] as Array[CourseValidator.Issue]})


func test_hilly_adds_a_gentle_ridge_across_the_hole() -> void:
	var c := CourseGenerator.generate(4, true, false)
	var flat := CourseGenerator.generate(4, false, false)
	assert_eq(_height_range(flat), Vector2i(CourseGenerator.PLOT_HEIGHT, CourseGenerator.PLOT_HEIGHT))
	assert_eq(_height_range(c), Vector2i(CourseGenerator.PLOT_HEIGHT, CourseGenerator.PLOT_HEIGHT + 1),
			"one step above the plot, never dug")
	var hole: HoleData = c.holes[0]
	# Gentle: no two neighbouring tiles differ by more than one step.
	for y: int in c.height:
		for x: int in c.width - 1:
			assert_true(absi(c.get_height(x, y) - c.get_height(x + 1, y)) <= 1, "step at (%d, %d)" % [x, y])
	# The ridge crosses the line between tee and cup, and the tee box and green stay flat.
	var crest: int = 0
	for x: int in range(hole.tee.x, hole.cup.x + 1):
		if c.get_height(x, hole.tee.y) > CourseGenerator.PLOT_HEIGHT:
			crest += 1
	assert_gt(crest, 0, "the ridge crosses the hole's line")
	for y: int in c.height:
		for x: int in c.width:
			var s: int = c.get_surface(x, y)
			if s == Surface.Type.TEE or s == Surface.Type.GREEN:
				assert_eq(c.get_height(x, y), CourseGenerator.PLOT_HEIGHT, "%s at (%d, %d)" % [Surface.name_of(s), x, y])
	# Only heights differ from the flat hole.
	for y: int in c.height:
		for x: int in c.width:
			assert_eq(c.get_surface(x, y), flat.get_surface(x, y))


func test_every_hilly_variant_passes() -> void:
	for par: int in [3, 4, 5]:
		for water: bool in [false, true]:
			var c := CourseGenerator.generate(par, true, water)
			assert_not_null(c, "par %d water %s" % [par, water])
			if c == null:
				continue
			assert_eq(_v.check_course(c), {1: [] as Array[CourseValidator.Issue]}, "par %d water %s" % [par, water])
			assert_eq(_height_range(c).y, CourseGenerator.PLOT_HEIGHT + 1)


func test_cli_generate_hilly_writes_a_passing_file() -> void:
	var path := "user://test_course_file_hilly.json"
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["generate", "4", "hilly", "--out=" + path]), out), 0,
			"\n".join(out))
	assert_string_contains("\n".join(out), "result: PASS")
	var loaded := CourseSave.load_file(path)
	assert_not_null(loaded)
	if loaded:
		assert_eq(loaded.content_hash(), CourseGenerator.generate(4, true, false).content_hash())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- inspect ---

func test_inspect_names_every_hole_of_the_example() -> void:
	var course := CourseSave.load_file(EXAMPLE_PATH)
	assert_not_null(course)
	if course == null:
		return
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect", EXAMPLE_PATH]), out), 0, "\n".join(out))
	var text := "\n".join(out)
	assert_string_contains(text, "%dx%d" % [course.width, course.height])
	assert_false(course.holes.is_empty())
	for hole: HoleData in course.holes:
		var line := "hole %d: par %d, %d yd, %s, PASS" % [hole.number, hole.par,
				CourseValidator.yardage(hole.tee, hole.cup), "open" if hole.open else "closed"]
		assert_string_contains(text, line)


func test_inspect_prints_heights_and_surface_counts() -> void:
	var path := "user://test_course_file_inspect.json"
	assert_eq(CourseSave.save_file(CourseGenerator.generate(3, true, true), path), OK)
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect", path]), out), 0, "\n".join(out))
	var text := "\n".join(out)
	assert_string_contains(text, "heights: 1 to 3")
	assert_string_contains(text, "surfaces:")
	for s: String in ["fairway", "rough", "green", "tee", "water"]:
		assert_string_contains(text, s)
	assert_false(text.contains("bunker"), "surfaces with no tiles are left out")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_inspect_reports_a_closed_failing_hole() -> void:
	var c := CourseData.create(40, 10, Surface.Type.ROUGH, 2)
	var hole := HoleData.new(1, 4, Vector2i(2, 5), Vector2i(32, 5), false)
	c.set_holes([hole] as Array[HoleData])
	var path := "user://test_course_file_fail.json"
	assert_eq(CourseSave.save_file(c, path), OK)
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect", path]), out), 0, "inspect only reports")
	var text := "\n".join(out)
	assert_string_contains(text, "hole 1: par 4, 150 yd, closed, FAIL")
	assert_string_contains(text, "rule 2 FAIL at (32, 5)")
	assert_string_contains(text, "rule 4 FAIL at (32, 5)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_inspect_rejects_a_missing_file() -> void:
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect", "res://courses/nope.json"]), out), 2)
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect"]), out), 2)
