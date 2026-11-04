extends GutTest
## /course-file inspect and generate hilly (E2-S18; land in E6-S20): course/course_file.gd and
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


## Fails the test where the hilly course `c` is not laid over land as E6-S20 says: tee box,
## green and pond each flat, the pond one step below its dry ring, edge neighbours one step
## apart at most, the flat hole's surfaces, and at least two steps of relief.
func _assert_hilly(c: CourseData, flat: CourseData, label: String) -> void:
	var hole: HoleData = c.holes[0]
	var range_h := _height_range(c)
	assert_gte(range_h.y - range_h.x, 2, "%s: hills, not a plot (%s)" % [label, range_h])
	for y: int in c.height:
		for x: int in c.width:
			assert_eq(c.get_surface(x, y), flat.get_surface(x, y), "%s: surface at (%d, %d)" % [label, x, y])
			if x + 1 < c.width:
				assert_true(absi(c.get_height(x, y) - c.get_height(x + 1, y)) <= 1, "%s: step at (%d, %d) x" % [label, x, y])
			if y + 1 < c.height:
				assert_true(absi(c.get_height(x, y) - c.get_height(x, y + 1)) <= 1, "%s: step at (%d, %d) y" % [label, x, y])
	var tee_level: int = c.get_height(hole.tee.x, hole.tee.y)
	var green_level: int = c.get_height(hole.cup.x, hole.cup.y)
	var water_level: int = -1
	var water_rect := Rect2i()
	for y: int in c.height:
		for x: int in c.width:
			match c.get_surface(x, y):
				Surface.Type.TEE:
					assert_eq(c.get_height(x, y), tee_level, "%s: tee box flat at (%d, %d)" % [label, x, y])
				Surface.Type.GREEN:
					assert_eq(c.get_height(x, y), green_level, "%s: green flat at (%d, %d)" % [label, x, y])
				Surface.Type.WATER:
					if water_level < 0:
						water_level = c.get_height(x, y)
						water_rect = Rect2i(x, y, 1, 1)
					assert_eq(c.get_height(x, y), water_level, "%s: pond flat at (%d, %d)" % [label, x, y])
					water_rect = water_rect.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
	if water_level >= 0:
		var ring := water_rect.grow(1)
		for y: int in range(ring.position.y, ring.end.y):
			for x: int in range(ring.position.x, ring.end.x):
				if not water_rect.has_point(Vector2i(x, y)):
					assert_eq(c.get_height(x, y), water_level + 1,
							"%s: dry ring one step above the pond at (%d, %d)" % [label, x, y])


func test_hilly_lays_the_hole_over_generated_land() -> void:
	var c := CourseGenerator.generate(4, true, false)
	var flat := CourseGenerator.generate(4, false, false)
	assert_eq(_height_range(flat), Vector2i(CourseGenerator.PLOT_HEIGHT, CourseGenerator.PLOT_HEIGHT))
	_assert_hilly(c, flat, "par 4 dry")
	# The heights are LandGenerator's, in the window centred on its map, away from the
	# levelled parts: most tiles keep the land's height exactly.
	var land := LandGenerator.generate(CourseGenerator.HILLY_LAND_SEED)
	var x0: int = (land.width - c.width) / 2
	var y0: int = (land.height - c.height) / 2
	var same: int = 0
	for y: int in c.height:
		for x: int in c.width:
			if c.get_height(x, y) == land.get_height(x0 + x, y0 + y):
				same += 1
	assert_gt(same, c.width * c.height * 3 / 4, "%d of %d tiles keep the land's height" % [same, c.width * c.height])
	assert_eq(c.content_hash(), CourseGenerator.generate(4, true, false).content_hash(), "deterministic")


func test_every_hilly_variant_passes() -> void:
	for par: int in [3, 4, 5]:
		for water: bool in [false, true]:
			var c := CourseGenerator.generate(par, true, water)
			assert_not_null(c, "par %d water %s" % [par, water])
			if c == null:
				continue
			assert_eq(_v.check_course(c), {1: [] as Array[CourseValidator.Issue]}, "par %d water %s" % [par, water])
			_assert_hilly(c, CourseGenerator.generate(par, false, water), "par %d water %s" % [par, water])


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
	var hilly := CourseGenerator.generate(3, true, true)
	assert_eq(CourseSave.save_file(hilly, path), OK)
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect", path]), out), 0, "\n".join(out))
	var text := "\n".join(out)
	var range_h := _height_range(hilly)
	assert_string_contains(text, "heights: %d to %d" % [range_h.x, range_h.y])
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


func test_inspect_prints_the_land_of_a_sandbox_file() -> void:
	var course := CourseSave.load_file(EXAMPLE_PATH)
	assert_not_null(course)
	if course == null:
		return
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect", EXAMPLE_PATH]), out), 0, "\n".join(out))
	var at: int = out.find("land: %dx%d parcels of %d tiles, %d owned" % [course.parcels_wide,
			course.parcels_high, CourseData.PARCEL_TILES, course.parcels_wide * course.parcels_high])
	assert_gt(at, -1, "\n".join(out))
	if at < 0:
		return
	for q: int in course.parcels_high:
		assert_eq(out[at + 1 + q], "  " + "1".repeat(course.parcels_wide), "parcel row %d" % q)
	assert_eq(out[at + 1 + course.parcels_high], "land budget: unlimited")


func test_inspect_prints_bought_and_unbought_parcels_and_the_budget() -> void:
	var c := CourseData.create(40, 40, Surface.Type.ROUGH, 2)
	c.set_parcel_owned(Vector2i(0, 0), false)
	c.set_parcel_owned(Vector2i(2, 1), false)
	c.set_parcel_owned(Vector2i(1, 2), false)
	c.set_land_budget(4200)
	var path := "user://test_course_file_land.json"
	assert_eq(CourseSave.save_file(c, path), OK)
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect", path]), out), 0, "\n".join(out))
	var at: int = out.find("land: 3x3 parcels of 16 tiles, 6 owned")
	assert_gt(at, -1, "\n".join(out))
	if at >= 0:
		assert_eq(out.slice(at + 1, at + 5), ["  011", "  110", "  101", "land budget: $4,200"] as Array[String])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_inspect_rejects_a_missing_file() -> void:
	var out: Array[String] = []
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect", "res://courses/nope.json"]), out), 2)
	assert_eq(CourseFileTool.run(PackedStringArray(["inspect"]), out), 2)
