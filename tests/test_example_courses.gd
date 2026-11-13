extends GutTest
## E13: the example courses (docs/courses.md), one test per course: the file loads with nine
## holes open and no validator issue, each hole's par and yardage within 10 yd of its fixture
## spec, a scripted stroke from each tee comes to rest, and the file is the fixture rebuilt.
## E13-S5: the four ship (packed by the export presets, beside the build and in each itch
## channel by /ship-it) and the game copies them into the course folder at start, never over a
## file of the same name, so the Import page lists each with its name, author, par and yardage.

const YARD_SLACK: int = 10


## Loads `path`, failing the test on a load error.
func _load(path: String) -> CourseData:
	var errors: Array[String] = []
	var c := CourseSave.load_file(path, errors)
	assert_eq(errors, [] as Array[String], "%s loads" % path)
	return c


## Every hole of `c` open and passing every rule, with the par and yardage of `specs` (each
## {n, par, yd}); a driver (par 4 and 5) or a 7-iron (par 3) from each tee at the cup comes
## to rest on the map.
func _check_holes(c: CourseData, specs: Array) -> void:
	var v := CourseValidator.new()
	var issues: Dictionary = v.check_course(c)
	assert_eq(c.holes.size(), specs.size(), "holes")
	var clubs := ClubSet.load_default()
	for s: Dictionary in specs:
		var n: int = s["n"]
		var h: HoleData = null
		for x: HoleData in c.holes:
			if x.number == n:
				h = x
		assert_not_null(h, "hole %d" % n)
		if h == null:
			continue
		assert_true(h.open, "hole %d open" % n)
		assert_eq(issues.get(n, []), [] as Array[CourseValidator.Issue], "hole %d passes every rule" % n)
		assert_eq(h.par, int(s["par"]), "hole %d par" % n)
		var yd := v.hole_yardage(c, h)
		assert_almost_eq(yd, int(s["yd"]), YARD_SLACK, "hole %d yardage %d" % [n, yd])
		var ball := Ball.new(c, n)
		var at := ball.field.tile_center(h.tee)
		var aim := rad_to_deg((ball.field.tile_center(h.cup) - at).angle())
		# A full swing on a flat lie (ShotModel.full's launch, without the lie, whose classes
		# trip Godot's exit leak, scripts/run_tests.sh).
		var club := clubs.club("driver" if h.par > 3 else "7i")
		ball.roll_factor = club.roll_factor
		ball.launch(Vector3(at.x, at.y, ball.field.height_at(at.x, at.y)),
				Ball.launch_velocity(club.full_speed(ball.params.gravity), club.launch_deg, aim))
		ball.run_to_rest()
		assert_true(ball.is_at_rest(), "hole %d: the tee shot comes to rest" % n)


func test_old_grey_links() -> void:
	var c := _load(OldGreyLinks.PATH)
	if c == null:
		return
	assert_eq(c.course_name, OldGreyLinks.COURSE_NAME)
	assert_eq(c.author, OldGreyLinks.COURSE_AUTHOR)
	assert_true(c.has_unlimited_budget(), "New sandbox land")
	for py: int in c.parcels_high:
		for px: int in c.parcels_wide:
			assert_true(c.is_parcel_owned(Vector2i(px, py)), "parcel %d, %d owned" % [px, py])
	assert_true(c.has_clubhouse(), "the clubhouse")
	_check_holes(c, OldGreyLinks.HOLES)
	var par := 0
	for h: HoleData in c.holes:
		par += h.par
	assert_between(par, 34, 36, "par of the nine")
	# Every walk between holes is within the least patient guest's limit or on a cart path
	# (E9-S2, D68), so none draws the long walk complaint.
	var tuning := GuestTuning.load_default()
	var limit := tuning.walk_base_s + tuning.walk_per_patience_s * tuning.patience_min
	for wk: Dictionary in GuestWalk.round_walks(c):
		var r := GuestWalk.route(c, wk["from"], wk["to"], tuning)
		assert_true(r.on_path or r.duration <= limit,
				"walk to hole %d: %.2f s, on a path %s" % [wk["to_hole"], r.duration, r.on_path])
	var built := OldGreyLinks.course()
	assert_eq(c.content_hash(), built.content_hash(),
			"courses/old_grey_links.json is out of date: rerun scripts/save_old_grey_links.gd")


## E13-S3: Pine Ridge, nine holes of tree-lined parkland (tests/fixtures/pine_ridge.gd).
func test_pine_ridge() -> void:
	var c := _load(PineRidge.PATH)
	if c == null:
		return
	assert_eq(c.course_name, PineRidge.COURSE_NAME)
	assert_eq(c.author, PineRidge.COURSE_AUTHOR)
	assert_true(c.has_unlimited_budget(), "New sandbox land")
	for py: int in c.parcels_high:
		for px: int in c.parcels_wide:
			assert_true(c.is_parcel_owned(Vector2i(px, py)), "parcel %d, %d owned" % [px, py])
	assert_true(c.has_clubhouse(), "the clubhouse")
	_check_holes(c, PineRidge.HOLES)
	var par := 0
	for h: HoleData in c.holes:
		par += h.par
	assert_between(par, 34, 36, "par of the nine")
	# The three doglegs are measured round the bend (D47).
	var v := CourseValidator.new()
	for h: HoleData in c.holes:
		assert_eq(v.turn_point(c, h) != null, h.number in [1, 5, 9], "hole %d dogleg" % h.number)
	# Every walk is within the least patient guest's limit or on a cart path (E9-S2, D68).
	var tuning := GuestTuning.load_default()
	var limit := tuning.walk_base_s + tuning.walk_per_patience_s * tuning.patience_min
	for wk: Dictionary in GuestWalk.round_walks(c):
		var r := GuestWalk.route(c, wk["from"], wk["to"], tuning)
		assert_true(r.on_path or r.duration <= limit,
				"walk to hole %d: %.2f s, on a path %s" % [wk["to_hole"], r.duration, r.on_path])
	var built := PineRidge.course()
	assert_eq(c.content_hash(), built.content_hash(),
			"courses/pine_ridge.json is out of date: rerun tests/fixtures/pine_ridge_save.gd")


## E13-S1: Harbor Links (HarborLinks), nine holes over water. Beyond _check_holes: par 35, no
## hint (no tee where another hole's approaches land), every tee shot seen and every hole with
## a hazard on its line and a dry way round it (so guests can praise every hole), contoured
## greens D7 holds a ball on, every pond flat one step below its shore (D66), and no walk a
## guest would complain of (D65, D68: each quick enough or on a cart path).
func test_harbor_links() -> void:
	var c := _load(HarborLinks.PATH)
	if c == null:
		return
	assert_eq(c.course_name, HarborLinks.COURSE_NAME)
	assert_eq(c.author, HarborLinks.COURSE_AUTHOR)
	assert_true(c.has_unlimited_budget(), "New sandbox land")
	for py: int in c.parcels_high:
		for px: int in c.parcels_wide:
			assert_true(c.is_parcel_owned(Vector2i(px, py)), "parcel %d, %d owned" % [px, py])
	assert_true(c.has_clubhouse(), "the clubhouse")
	_check_holes(c, HarborLinks.HOLES)
	var v := CourseValidator.new()
	var checks := HoleChecks.new()
	var par := 0
	for h: HoleData in c.holes:
		par += h.par
		var st := checks.measure(c, h)
		assert_true(st.fair(), "hole %d tee shot seen (blind at %s)" % [h.number, st.blind_at])
		assert_true(st.interesting(), "hole %d: a hazard on the line and a dry way round" % h.number)
		_assert_contoured(c, h)
	assert_eq(par, 35, "par of the nine")
	for slot: Array in v.hint_slots(c):
		assert_eq(slot.size(), 0, "no tee where another hole's approaches land: %s" % [slot])
	for y: int in c.height:
		for x: int in c.width:
			if c.get_surface(x, y) != Surface.Type.WATER:
				continue
			assert_eq(c.get_height(x, y), HarborLinks.GROUND - 1, "water at %d, %d" % [x, y])
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var t := Vector2i(x, y) + d
				if c.in_bounds(t.x, t.y) and c.get_surface(t.x, t.y) != Surface.Type.WATER:
					assert_gt(c.get_height(t.x, t.y), c.get_height(x, y), "shore %s above its water" % t)
	var tuning := GuestTuning.load_default()
	var limit := tuning.walk_base_s + tuning.walk_per_patience_s * tuning.patience_min
	var on_path := 0
	for wk: Dictionary in GuestWalk.round_walks(c):
		var r := GuestWalk.route(c, wk["from"], wk["to"], tuning)
		assert_true(r.on_path or r.duration <= limit,
				"walk to hole %d: %.2f s, on a path %s" % [wk["to_hole"], r.duration, r.on_path])
		if r.on_path:
			on_path += 1
	assert_eq(on_path, HarborLinks.PATHS.size(), "every cart path serves its walk")
	assert_eq(c.content_hash(), HarborLinks.course().content_hash(),
			"courses/harbor_links.json is out of date: rerun scripts/save_harbor_links.gd")


## A green D7 holds a still ball on: 25 to 60 tiles, at least one contour, each one step.
func _assert_contoured(c: CourseData, h: HoleData) -> void:
	var tiles: Array[Vector2i] = [h.cup]
	var seen := {h.cup: true}
	var i := 0
	while i < tiles.size():
		var t: Vector2i = tiles[i]
		i += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := t + d
			if not seen.has(n) and c.in_bounds(n.x, n.y) and c.get_surface(n.x, n.y) == Surface.Type.GREEN:
				seen[n] = true
				tiles.append(n)
	assert_between(tiles.size(), 25, 60, "hole %d green tiles" % h.number)
	var low := CourseData.MAX_HEIGHT
	var high := 0
	var steepest := 0
	for t: Vector2i in tiles:
		low = mini(low, c.get_height(t.x, t.y))
		high = maxi(high, c.get_height(t.x, t.y))
		for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if seen.has(t + d):
				steepest = maxi(steepest, absi(c.get_height(t.x + d.x, t.y + d.y) - c.get_height(t.x, t.y)))
	assert_gte(high - low, 1, "hole %d green has a contour" % h.number)
	assert_eq(steepest, 1, "hole %d contours are one step" % h.number)


## E13-S4: Cliffside (Cliffside), nine holes round an island of clifftops. Beyond _check_holes:
## all land owned, the sea at height 0 under shores a step above it, every tee shot seen, and no
## walk a guest would complain of (D65, D68).
func test_cliffside() -> void:
	var c := _load(Cliffside.PATH)
	if c == null:
		return
	assert_eq(c.course_name, Cliffside.COURSE_NAME)
	assert_eq(c.author, Cliffside.COURSE_AUTHOR)
	assert_eq(c.width, Cliffside.SIZE)
	assert_eq(c.height, Cliffside.SIZE)
	assert_true(c.has_unlimited_budget(), "New sandbox land")
	for py: int in c.parcels_high:
		for px: int in c.parcels_wide:
			assert_true(c.is_parcel_owned(Vector2i(px, py)), "parcel %d, %d owned" % [px, py])
	assert_true(c.has_clubhouse(), "the clubhouse")
	_check_holes(c, Cliffside.HOLES)
	var par := 0
	for h: HoleData in c.holes:
		par += h.par
	assert_between(par, 34, 36, "par of the nine")
	# The sea is water at height 0 under every shore tile, and the bluffs rise from it a step a
	# tile at most (D50's smooth slopes).
	var sea := Cliffside.sea_mask()
	var wrong: Array[Vector2i] = []
	var sea_tiles := 0
	for y: int in c.height:
		for x: int in c.width:
			if sea[y * c.width + x] == 0:
				continue
			sea_tiles += 1
			if c.get_surface(x, y) != Surface.Type.WATER or c.get_height(x, y) != 0:
				wrong.append(Vector2i(x, y))
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				var n := Vector2i(x, y) + d
				if c.in_bounds(n.x, n.y) and sea[n.y * c.width + n.x] == 0 and c.get_height(n.x, n.y) > 1:
					wrong.append(n)
	assert_gt(sea_tiles, 0, "the sea")
	assert_eq(wrong, [] as Array[Vector2i], "sea at height 0, every shore tile one step above it")
	# Every tee shot is seen from the tee (D43), so the holes can be praised.
	var checks := HoleChecks.new()
	for h: HoleData in c.holes:
		assert_true(checks.measure(c, h).fair(), "hole %d seen from the tee" % h.number)
	# Every walk between holes is within the least patient guest's limit or on a cart path
	# (E9-S2, D68), and each of the fixture's paths serves its walk.
	var tuning := GuestTuning.load_default()
	var limit := tuning.walk_base_s + tuning.walk_per_patience_s * tuning.patience_min
	for wk: Dictionary in GuestWalk.round_walks(c):
		var r := GuestWalk.route(c, wk["from"], wk["to"], tuning)
		assert_true(r.on_path or r.duration <= limit,
				"walk to hole %d: %.2f s, on a path %s" % [wk["to_hole"], r.duration, r.on_path])
		for p: Array in Cliffside.PATHS:
			if int(p[1]) == int(wk["to_hole"]):
				assert_true(r.on_path, "the %d-%d walk follows its path" % [p[0], p[1]])
	var built := Cliffside.course()
	assert_eq(c.content_hash(), built.content_hash(),
			"courses/cliffside.json is out of date: rerun scripts/save_cliffside.gd")


# --- E13-S5: the examples ship, and the Import page lists them ---

## Where these tests install the examples: a folder of their own under this run's user://
## (scripts/run_tests.sh gives every test job its own), never CourseExport.FOLDER.
const INSTALL_DIR := "user://test_example_courses"
## Each example's Import page line (CourseExport.Entry.label): name, author, par, yardage.
const LABELS := {
	"cliffside.json": "\"Cliffside\" by Prestwick: 9 holes, par 36, 3,353 yd",
	"harbor_links.json": "\"Harbor Links\" by Prestwick: 9 holes, par 35, 3,200 yd",
	"old_grey_links.json": "\"Old Grey Links\" by Prestwick: 9 holes, par 34, 3,023 yd",
	"pine_ridge.json": "\"Pine Ridge\" by Prestwick: 9 holes, par 34, 2,935 yd",
}


func before_each() -> void:
	_clear(INSTALL_DIR)


func after_each() -> void:
	_clear(INSTALL_DIR)


func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func test_the_four_examples_are_the_shipped_files() -> void:
	var files := Array(CourseExport.EXAMPLES)
	files.sort()
	var want := LABELS.keys()
	want.sort()
	assert_eq(files, want, "CourseExport.EXAMPLES names the four example courses")
	for f: String in CourseExport.EXAMPLES:
		assert_true(FileAccess.file_exists(CourseExport.EXAMPLES_FROM.path_join(f)), "res://courses/%s" % f)


## The export packs courses/*.json, so res://courses/ holds the examples in the itch build.
func test_every_export_preset_packs_the_course_files() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg")
	var presets := 0
	for section: String in cfg.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		presets += 1
		var include := String(cfg.get_value(section, "include_filter", ""))
		var exclude := String(cfg.get_value(section, "exclude_filter", ""))
		var preset := String(cfg.get_value(section, "name", section))
		assert_string_contains(include, "courses/*.json", "%s packs courses/*.json" % preset)
		assert_false(exclude.contains("courses"), "%s excludes no course file" % preset)
	assert_gte(presets, 2, "the Linux and Windows presets")


## /ship-it puts every example (and the playtest nine) beside the build and in each itch channel.
func test_ship_it_ships_every_example() -> void:
	var text := FileAccess.get_file_as_string("res://.claude/skills/ship-it/SKILL.md")
	assert_false(text.is_empty(), "the ship-it skill")
	for f: String in CourseExport.EXAMPLES:
		assert_string_contains(text, "courses/%s" % f)
	assert_string_contains(text, "courses/playtest_nine.json")


func test_installing_into_an_empty_folder_lists_every_example_on_the_import_page() -> void:
	var written := CourseExport.install_examples(INSTALL_DIR)
	assert_eq(written.size(), CourseExport.EXAMPLES.size(), "all four copied: %s" % [written])
	for f: String in CourseExport.EXAMPLES:
		assert_eq(FileAccess.get_file_as_bytes(INSTALL_DIR.path_join(f)),
				FileAccess.get_file_as_bytes(CourseExport.EXAMPLES_FROM.path_join(f)),
				"%s copied byte for byte" % f)
	assert_eq(Array(DirAccess.get_files_at(INSTALL_DIR)).filter(
			func(f: String) -> bool: return f.ends_with(".tmp")), [], "no temp file left")
	var labels := {}
	for e: CourseExport.Entry in CourseExport.list_folder(INSTALL_DIR):
		assert_not_null(e.course, "%s reads: %s" % [e.path, e.error])
		labels[e.path.get_file()] = e.label()
	assert_eq(labels, LABELS, "the Import page's lines: name, author Prestwick, par and yardage")


func test_installing_keeps_a_file_of_the_same_name_and_copies_the_rest() -> void:
	DirAccess.make_dir_recursive_absolute(INSTALL_DIR)
	var mine := FileAccess.open(INSTALL_DIR.path_join("pine_ridge.json"), FileAccess.WRITE)
	mine.store_string("my own edit")
	mine.close()
	var written := CourseExport.install_examples(INSTALL_DIR)
	assert_eq(written.size(), 3, "the other three: %s" % [written])
	assert_false(written.has(INSTALL_DIR.path_join("pine_ridge.json")))
	assert_eq(FileAccess.get_file_as_string(INSTALL_DIR.path_join("pine_ridge.json")), "my own edit",
			"the player's file is never written over")
	assert_eq(CourseExport.install_examples(INSTALL_DIR), [] as Array[String],
			"a second start copies nothing")


func test_a_missing_source_is_skipped() -> void:
	var written := CourseExport.install_examples(INSTALL_DIR, CourseExport.EXAMPLES_FROM,
			PackedStringArray(["no_such_course.json", "cliffside.json"]))
	assert_eq(written, [INSTALL_DIR.path_join("cliffside.json")] as Array[String])


## Only the game itself installs (Main as the running scene, scenes/main.gd _ready): a test that
## adds Main to its own tree leaves the course folder alone.
func test_main_added_by_a_test_installs_nothing() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	add_child_autofree(main)
	for f: String in CourseExport.EXAMPLES:
		assert_false(FileAccess.file_exists(CourseExport.FOLDER.path_join(f)), "%s not installed" % f)


## E14-S3 (D69): each example course carries its footbridges where its lines cross water (Harbor
## Links' island green and creeks, Old Grey Links' burns, Pine Ridge's creeks, Cliffside's cove),
## every one on a water tile; every hole passes rule 7, on foot; and a walk across each bridged
## water goes over its bridge, dry, near the straight line.
func test_the_example_courses_have_their_bridges() -> void:
	var tuning := GuestTuning.load_default()
	# [path, bridge tiles at least, a walk across bridged water: from tile, to tile].
	var cases: Array = [
		["res://courses/harbor_links.json", 20, Vector2i(30, 50), Vector2i(28, 73)],
		["res://courses/old_grey_links.json", 8, Vector2i(118, 50), Vector2i(118, 70)],
		["res://courses/pine_ridge.json", 4, Vector2i(58, 94), Vector2i(73, 94)],
		["res://courses/cliffside.json", 20, Vector2i(52, 108), Vector2i(90, 111)],
	]
	var v := CourseValidator.new()
	for k: Array in cases:
		var c := _load(k[0])
		assert_gte(c.bridge_cells().size(), k[1], "%s: its bridges" % c.course_name)
		for t: Vector2i in c.bridge_cells():
			assert_eq(c.get_surface(t.x, t.y), Surface.Type.WATER)
		for h: HoleData in c.holes:
			for i: CourseValidator.Issue in v.check_hole(c, h):
				assert_ne(i.rule, 7, "%s hole %d: %s" % [c.course_name, h.number, i.reason])
			assert_true(h.open)
		var from := (Vector2(k[2]) + Vector2(0.5, 0.5)) * 5.0
		var to := (Vector2(k[3]) + Vector2(0.5, 0.5)) * 5.0
		var w := GuestWalk.route(c, from, to, tuning)
		assert_gt(w.path_yd, 0.0, "%s: the walk crosses a bridge" % c.course_name)
		assert_lt(w.length, from.distance_to(to) * 1.3, "%s: near the straight line, %.0f yd" % [c.course_name, w.length])
		var t := 0.0
		while t < w.duration:
			var p := w.point_at_time(t)
			assert_true(GuestWalk.walkable(c, floori(p.x / 5.0), floori(p.y / 5.0)), "dry at %s" % p)
			t += 0.05
