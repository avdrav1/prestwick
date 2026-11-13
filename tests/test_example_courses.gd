extends GutTest
## E13: the example courses (docs/courses.md), one test per course: the file loads with nine
## holes open and no validator issue, each hole's par and yardage within 10 yd of its fixture
## spec, a scripted stroke from each tee comes to rest, and the file is the fixture rebuilt.

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
