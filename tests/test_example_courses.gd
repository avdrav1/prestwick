extends GutTest
## E13: the example courses (docs/courses.md), one test per course: the file loads with nine
## holes open and no validator issue, each hole's par and yardage within 10 yd of its fixture
## spec, a scripted stroke from each tee comes to rest, and the file is the fixture rebuilt.
## E13-S5: the four ship (packed by the export presets, beside the build and in each itch
## channel by /ship-it). E16-S1: Dogleg Hollow, the fifth. E15-S1 (D70): they are the famous courses, played from res://courses/
## and never copied; each file carries its id and version, and a changed file must bump it.

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


## E16-S1: Dogleg Hollow (DoglegHollow), nine famous doglegs. Beyond _check_holes: every hole
## is measured round its bend (D47) and turns at least MIN_TURN_DEG there, to the side its spec
## names; every tee shot is seen and every hole has a hazard on its line and a dry way round it
## (the corner); contoured greens; no walk a guest would complain of (D65, D68); the file is the
## fixture rebuilt.
const MIN_TURN_DEG: float = 30.0


func test_dogleg_hollow() -> void:
	var c := _load(DoglegHollow.PATH)
	if c == null:
		return
	assert_eq(c.course_name, DoglegHollow.COURSE_NAME)
	assert_eq(c.author, DoglegHollow.COURSE_AUTHOR)
	assert_true(c.has_unlimited_budget(), "New sandbox land")
	for py: int in c.parcels_high:
		for px: int in c.parcels_wide:
			assert_true(c.is_parcel_owned(Vector2i(px, py)), "parcel %d, %d owned" % [px, py])
	assert_true(c.has_clubhouse(), "the clubhouse")
	_check_holes(c, DoglegHollow.HOLES)
	var v := CourseValidator.new()
	var checks := HoleChecks.new()
	var par := 0
	for h: HoleData in c.holes:
		par += h.par
		var spec := DoglegHollow.spec_of(h.number)
		assert_not_null(v.turn_point(c, h), "hole %d is measured round its dogleg" % h.number)
		var angle := DoglegHollow.turn_angle(c, h, v)
		assert_gte(absf(angle), MIN_TURN_DEG, "hole %d turns %.0f degrees" % [h.number, angle])
		assert_eq("right" if angle > 0.0 else "left", spec["turn"], "hole %d turns %s" % [h.number, spec["turn"]])
		var st := checks.measure(c, h)
		assert_true(st.fair(), "hole %d tee shot seen (blind at %s)" % [h.number, st.blind_at])
		assert_true(st.interesting(), "hole %d: a hazard on the line and a dry way round" % h.number)
		_assert_contoured(c, h)
	assert_eq(par, DoglegHollow.PAR, "par of the nine")
	var tuning := GuestTuning.load_default()
	var limit := tuning.walk_base_s + tuning.walk_per_patience_s * tuning.patience_min
	for wk: Dictionary in GuestWalk.round_walks(c):
		var r := GuestWalk.route(c, wk["from"], wk["to"], tuning)
		assert_true(r.on_path or r.duration <= limit,
				"walk to hole %d: %.2f s, on a path %s" % [wk["to_hole"], r.duration, r.on_path])
		for p: Array in DoglegHollow.PATHS:
			if int(p[1]) == int(wk["to_hole"]):
				assert_true(r.on_path, "the %d-%d walk follows its path" % [p[0], p[1]])
	assert_eq(c.content_hash(), DoglegHollow.course().content_hash(),
			"courses/dogleg_hollow.json is out of date: rerun scripts/save_dogleg_hollow.gd")


# --- E13-S5: the examples ship; E15-S1 (D70): as the famous courses, versioned ---

## Each example's famous course page line (CourseExport.summary): holes, par, yardage.
const SUMMARIES := {
	"cliffside": "9 holes, par 36, 3,353 yd",
	"dogleg_hollow": "9 holes, par 37, 3,545 yd",
	"harbor_links": "9 holes, par 35, 3,200 yd",
	"old_grey_links": "9 holes, par 34, 3,023 yd",
	"pine_ridge": "9 holes, par 34, 2,935 yd",
}
## Each fixture's [COURSE_ID, COURSE_VERSION], by its course id.
func _fixture_ids() -> Dictionary:
	return {
		"harbor_links": [HarborLinks.COURSE_ID, HarborLinks.COURSE_VERSION],
		"old_grey_links": [OldGreyLinks.COURSE_ID, OldGreyLinks.COURSE_VERSION],
		"pine_ridge": [PineRidge.COURSE_ID, PineRidge.COURSE_VERSION],
		"cliffside": [Cliffside.COURSE_ID, Cliffside.COURSE_VERSION],
		"dogleg_hollow": [DoglegHollow.COURSE_ID, DoglegHollow.COURSE_VERSION],
	}


func test_the_famous_courses_are_the_shipped_files() -> void:
	var ids := Array(FamousCourses.ids())
	ids.sort()
	var want := SUMMARIES.keys()
	want.sort()
	assert_eq(ids, want, "FamousCourses names the five famous courses")
	for id: String in FamousCourses.ids():
		assert_eq(FamousCourses.spec(id)["file"], "%s.json" % id)
		assert_true(FileAccess.file_exists(FamousCourses.path(id)), FamousCourses.path(id))
		var c := _load(FamousCourses.path(id))
		if c != null:
			assert_eq(CourseExport.summary(c), SUMMARIES[id], id)
			assert_eq(c.author, "Prestwick")


## E15-S1 (D70): the bump check. Each file carries its fixture's id and version, and its bytes
## hash to that version's entry in FamousCourses, the last one. A change to a fixture that
## changes its file fails here until the version goes up and the new hash is appended.
func test_a_changed_course_file_bumps_its_version() -> void:
	for id: String in FamousCourses.ids():
		var fixture: Array = _fixture_ids()[id]
		var c := _load(FamousCourses.path(id))
		if c == null:
			continue
		assert_eq(c.course_id, fixture[0], "%s: the file carries its id" % id)
		assert_eq(c.course_id, id)
		assert_eq(c.course_version, fixture[1], "%s: the file carries the fixture's version" % id)
		var hashes := FamousCourses.shipped_hashes(id)
		assert_eq(FamousCourses.latest_version(id), fixture[1],
				"%s: FamousCourses lists every version up to the fixture's" % id)
		var sha := FileAccess.get_sha256(FamousCourses.path(id))
		assert_eq(hashes[-1], sha, ("courses/%s.json changed without a version bump: set its fixture's"
				+ " COURSE_VERSION to %d, rerun its save script, and append its new SHA-256 to"
				+ " FamousCourses (now %s)") % [id, hashes.size() + 1, sha])
		assert_eq(hashes.find(sha), hashes.size() - 1, "%s: no older version had this file" % id)


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
	for f: String in FamousCourses.files():
		assert_string_contains(text, "courses/%s" % f)
	assert_string_contains(text, "courses/playtest_nine.json")


## E15-S1: the game no longer copies them into the course folder: a fresh one stays empty.
func test_the_game_copies_no_course_into_the_course_folder() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	add_child_autofree(main)
	for f: String in FamousCourses.files():
		assert_false(FileAccess.file_exists(CourseExport.FOLDER.path_join(f)), "%s not copied" % f)
	assert_false(CourseExport.new().has_method("install_examples"), "the copy step is gone")


## E14-S3 (D69): each example course carries its footbridges where its lines cross water (Harbor
## Links' island green and creeks, Old Grey Links' burns, Pine Ridge's creeks, Cliffside's cove),
## every one on a water tile; every hole passes rule 7, on foot; and a walk across each bridged
## water goes over its bridge, dry, near the straight line. E14-S5: the bridges the audit
## (scripts/bridge_audit.gd) asked for: Old Grey Links' home burn bridge laid bank to bank,
## Cliffside's over the 3rd's chasm and the inlet beside the 5th; and every bridge crosses (its
## banks lie farther apart than it is long, so none ends on the water).
func test_the_example_courses_have_their_bridges() -> void:
	var tuning := GuestTuning.load_default()
	# [path, bridge tiles at least, walks across bridged water: [from tile, to tile], ...].
	var cases: Array = [
		["res://courses/harbor_links.json", 23, [[Vector2i(30, 50), Vector2i(28, 73)]]],
		["res://courses/old_grey_links.json", 11, [[Vector2i(118, 50), Vector2i(118, 70)],
				[Vector2i(70, 56), Vector2i(74, 56)]]],
		["res://courses/pine_ridge.json", 4, [[Vector2i(58, 94), Vector2i(73, 94)]]],
		["res://courses/cliffside.json", 33, [[Vector2i(52, 108), Vector2i(90, 111)],
				[Vector2i(9, 87), Vector2i(9, 97)], [Vector2i(32, 86), Vector2i(40, 86)]]],
		# E16-S1: Dogleg Hollow needs none (scripts/bridge_audit.gd: no walk or ball detour).
		["res://courses/dogleg_hollow.json", 0, []],
	]
	var v := CourseValidator.new()
	for k: Array in cases:
		var c := _load(k[0])
		assert_gte(c.bridge_cells().size(), k[1], "%s: its bridges" % c.course_name)
		for t: Vector2i in c.bridge_cells():
			assert_eq(c.get_surface(t.x, t.y), Surface.Type.WATER)
		_assert_bridges_cross(c)
		for h: HoleData in c.holes:
			for i: CourseValidator.Issue in v.check_hole(c, h):
				assert_ne(i.rule, 7, "%s hole %d: %s" % [c.course_name, h.number, i.reason])
			assert_true(h.open)
		for ends: Array in k[2]:
			var from := (Vector2(ends[0]) + Vector2(0.5, 0.5)) * 5.0
			var to := (Vector2(ends[1]) + Vector2(0.5, 0.5)) * 5.0
			var w := GuestWalk.route(c, from, to, tuning)
			assert_gt(w.path_yd, 0.0, "%s: the walk %s crosses a bridge" % [c.course_name, ends])
			assert_lt(w.length, from.distance_to(to) * 1.3, "%s: %s near the straight line, %.0f yd" % [
					c.course_name, ends, w.length])
			var t := 0.0
			while t < w.duration:
				var p := w.point_at_time(t)
				assert_true(GuestWalk.walkable(c, floori(p.x / 5.0), floori(p.y / 5.0)), "dry at %s" % p)
				t += 0.05


## E14-S5: every 4-connected run of bridge tiles on `c` reaches land at both ends: the land tiles
## beside it lie farther apart than the run is long (as scripts/bridge_audit.gd checks).
func _assert_bridges_cross(c: CourseData) -> void:
	var left := {}
	for t: Vector2i in c.bridge_cells():
		left[t] = true
	var sides: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for t0: Vector2i in c.bridge_cells():
		if not left.has(t0):
			continue
		left.erase(t0)
		var todo: Array[Vector2i] = [t0]
		var lo := t0
		var hi := t0
		var banks: Array[Vector2i] = []
		while not todo.is_empty():
			var p: Vector2i = todo.pop_back()
			lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
			hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
			for d: Vector2i in sides:
				var q: Vector2i = p + d
				if left.has(q):
					left.erase(q)
					todo.append(q)
				elif c.in_bounds(q.x, q.y) and c.get_surface(q.x, q.y) != Surface.Type.WATER:
					banks.append(q)
		var span := 0.0
		for a: Vector2i in banks:
			for b: Vector2i in banks:
				span = maxf(span, Vector2(a).distance_to(Vector2(b)))
		assert_gt(span, float(maxi(hi.x - lo.x, hi.y - lo.y) + 1),
				"%s: the bridge %s..%s reaches land at both ends" % [c.course_name, lo, hi])
