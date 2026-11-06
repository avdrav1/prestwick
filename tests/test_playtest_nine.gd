extends GutTest
## E3-S50: the playtest nine, courses/playtest_nine.json, rebuilt by
## tests/fixtures/playtest_nine.gd (PlaytestNine). Nine open holes on generated land, every
## rule passing, at least four doglegs (hole 1, the hole the game opens on, among them) whose
## fairways sweep 35 to 75 degrees in smooth arcs, no sharp corner, and whose line of play
## (D47) sets their par, every hole's fairway at least 3 tiles from every other hole's,
## contoured greens D7 holds a ball on, and the file in step with the fixture.

var _v: CourseValidator
var _c: CourseData


func before_all() -> void:
	_v = CourseValidator.new()
	var errors: Array[String] = []
	_c = CourseSave.load_file(PlaytestNine.PATH, errors)
	assert_eq(errors, [] as Array[String], "the file loads")


func _hole(n: int) -> HoleData:
	for h: HoleData in _c.holes:
		if h.number == n:
			return h
	return null


## The green tiles 4-connected to `h`'s cup.
func _green(h: HoleData) -> Array[Vector2i]:
	var out: Array[Vector2i] = [h.cup]
	var seen := {h.cup: true}
	var i := 0
	while i < out.size():
		var t: Vector2i = out[i]
		i += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := t + d
			if seen.has(n) or not _c.in_bounds(n.x, n.y):
				continue
			seen[n] = true
			if _c.get_surface(n.x, n.y) == Surface.Type.GREEN:
				out.append(n)
	return out


func test_file_is_the_fixture_built_through_the_builder() -> void:
	var built := PlaytestNine.course()
	assert_not_null(built)
	assert_eq(_c.content_hash(), built.content_hash(), "courses/playtest_nine.json is out of date: rerun play_course.gd -- playtest --save-only")
	assert_eq(_c.course_name, PlaytestNine.COURSE_NAME)


func test_new_sandbox_land_every_parcel_owned() -> void:
	assert_true(_c.has_unlimited_budget())
	for py: int in _c.parcels_high:
		for px: int in _c.parcels_wide:
			assert_true(_c.is_parcel_owned(Vector2i(px, py)), "parcel %d, %d owned" % [px, py])
	var text := FileAccess.get_file_as_string(PlaytestNine.PATH)
	assert_eq(int((JSON.parse_string(text) as Dictionary)["version"]), CourseData.FORMAT_VERSION)


func test_nine_open_holes_every_rule_passes() -> void:
	assert_eq(_c.holes.size(), 9)
	var par := 0
	var issues: Dictionary = _v.check_course(_c)
	for n: int in range(1, 10):
		var h := _hole(n)
		assert_not_null(h, "hole %d" % n)
		if h == null:
			continue
		assert_true(h.open, "hole %d open" % n)
		assert_eq(issues.get(n, []), [] as Array[CourseValidator.Issue], "hole %d passes" % n)
		par += h.par
	assert_between(par, 34, 37, "par of the nine")


func test_a_mix_of_lengths() -> void:
	var short3 := 0
	var long3 := 0
	var fives := 0
	for h: HoleData in _c.holes:
		var yd := _v.hole_yardage(_c, h)
		if h.par == 3 and yd < 180:
			short3 += 1
		if h.par == 3 and yd > 220:
			long3 += 1
		if h.par == 5:
			fives += 1
			# Driver then 3-wood, both perfect, total 543 yd on flat fairway (Balance targets,
			# clubs): within reach of two perfect swings and little else.
			assert_between(yd, 520, 543, "hole %d, the par 5" % h.number)
	assert_gte(short3, 2, "par 3s under 180 yd")
	assert_gte(long3, 1, "par 3s over 220 yd")
	assert_gte(fives, 1, "a par 5")


func test_doglegs_sweep_in_smooth_arcs() -> void:
	var doglegs: Array[int] = []
	var lefts := 0
	var rights := 0
	var watered := 0
	var par_moved := 0
	for spec: Dictionary in PlaytestNine.HOLES:
		var h := _hole(spec["n"])
		var line := _centre_line(h, spec)
		if line.size() < 3:
			continue
		# The painted fairway's heading changes a little at a time: no corner.
		var bend := 0.0
		for i: int in range(1, line.size() - 1):
			var step := rad_to_deg((line[i] - line[i - 1]).angle_to(line[i + 1] - line[i]))
			assert_lte(absf(step), 30.0, "hole %d bends %.0f degrees between samples %d and %d" % [h.number, step, i, i + 1])
			bend += step
		if absf(bend) < 35.0:
			continue
		doglegs.append(h.number)
		# A sweep, not a hairpin: 35 to 75 degrees from the tee's heading to the green's.
		assert_between(absf(bend), 35.0, 75.0, "hole %d turns %.0f degrees tee to green" % [h.number, bend])
		# Tile y runs down the map, so a positive angle turns right.
		if bend > 0.0:
			rights += 1
		else:
			lefts += 1
		# D47: the bend still reads as one, so the hole is measured along its line of play.
		var turn: Variant = _v.turn_point(_c, h)
		assert_not_null(turn, "hole %d is measured round its bend" % h.number)
		if turn == null:
			continue
		var yd := _v.hole_yardage(_c, h)
		assert_eq(h.par, _v.par_for_yardage(yd), "hole %d: par from %d yd round the bend" % [h.number, yd])
		if _v.par_for_yardage(CourseValidator.yardage(h.tee, h.cup)) != h.par:
			par_moved += 1
		if _water_near(turn, 8.0):
			watered += 1
	assert_gte(doglegs.size(), 4, "doglegs %s" % [doglegs])
	assert_has(doglegs, 1, "hole 1, the hole the game opens on, is a dogleg")
	assert_gte(lefts, 1, "a dogleg left")
	assert_gte(rights, 1, "a dogleg right")
	assert_gte(watered, 1, "a dogleg with water inside the bend")
	assert_gte(par_moved, 1, "a dogleg whose straight line would be another par")


## The centre line `h`'s fairway is painted along (PlaytestNine.centre_line, the Bezier sweep
## on a dogleg), a sample every 2 tiles, each checked to sit on fairway the course holds, so
## the bend measured is the one on the map.
func _centre_line(h: HoleData, spec: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p: Vector2 in PlaytestNine.centre_line(spec):
		if out.is_empty() or p.distance_to(out[-1]) >= 2.0:
			out.append(p)
	for p: Vector2 in out:
		var t := Vector2i(p.round())
		assert_eq(_c.get_surface(t.x, t.y), Surface.Type.FAIRWAY, "hole %d centre line %s on fairway" % [h.number, t])
	return out


func _water_near(p: Vector2, r: float) -> bool:
	for y: int in range(floori(p.y - r), ceili(p.y + r) + 1):
		for x: int in range(floori(p.x - r), ceili(p.x + r) + 1):
			if _c.in_bounds(x, y) and _c.get_surface(x, y) == Surface.Type.WATER \
					and Vector2(x, y).distance_to(p) <= r:
				return true
	return false


## Every fairway tile belongs to exactly one hole's fairway (its spec's strip), and no two
## holes' fairways come within 3 tiles of each other (8 neighbours), so no fairways merge.
func test_fairways_are_separate() -> void:
	var owner := {}
	for spec: Dictionary in PlaytestNine.HOLES:
		for t: Vector2i in PlaytestNine.fairway_tiles(spec):
			if _c.in_bounds(t.x, t.y) and _c.get_surface(t.x, t.y) == Surface.Type.FAIRWAY:
				assert_false(owner.has(t), "fairway %s is in two holes' strips" % t)
				owner[t] = spec["n"]
	for y: int in _c.height:
		for x: int in _c.width:
			if _c.get_surface(x, y) == Surface.Type.FAIRWAY:
				assert_true(owner.has(Vector2i(x, y)), "fairway %d, %d belongs to a hole" % [x, y])
	var close := {}
	for t: Vector2i in owner:
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				var n: Vector2i = t + Vector2i(dx, dy)
				if owner.has(n) and owner[n] != owner[t]:
					close[Vector2i(mini(owner[t], owner[n]), maxi(owner[t], owner[n]))] = true
	assert_eq(close.keys(), [], "pairs of holes whose fairways are under 3 tiles apart")


func test_fairways_with_bunkers_and_trees() -> void:
	for spec: Dictionary in PlaytestNine.HOLES:
		var h := _hole(spec["n"])
		if h.par == 3:
			continue
		assert_between(float(spec["width"]), 4.0, 7.0, "hole %d fairway width" % h.number)
		var count := {}
		for t: Vector2i in _v.footprint(_c, h):
			var s: int = _c.get_surface(t.x, t.y)
			count[s] = int(count.get(s, 0)) + 1
		assert_gt(int(count.get(Surface.Type.FAIRWAY, 0)), 0, "hole %d fairway" % h.number)
		assert_gt(int(count.get(Surface.Type.BUNKER, 0)), 0, "hole %d bunkers" % h.number)
		assert_gte(int(count.get(Surface.Type.TREES, 0)), 10, "hole %d trees" % h.number)


func test_greens_are_contoured_and_hold_a_ball() -> void:
	var two_step := 0
	for h: HoleData in _c.holes:
		var tiles := _green(h)
		assert_between(tiles.size(), 25, 60, "hole %d green tiles" % h.number)
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := -lo
		var low_h := CourseData.MAX_HEIGHT
		var high_h := 0
		var steepest := 0
		var on := {}
		for t: Vector2i in tiles:
			on[t] = true
		for t: Vector2i in tiles:
			lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
			hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
			var th := _c.get_height(t.x, t.y)
			low_h = mini(low_h, th)
			high_h = maxi(high_h, th)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				if on.has(t + d):
					steepest = maxi(steepest, absi(_c.get_height(t.x + d.x, t.y + d.y) - th))
		var size := hi - lo + Vector2i.ONE
		assert_true(size.x != size.y or tiles.size() < size.x * size.y,
				"hole %d green is not square (%s, %d tiles)" % [h.number, size, tiles.size()])
		assert_gte(high_h - low_h, 1, "hole %d green has a slope or tier" % h.number)
		# D7: a one-step contour holds a still ball; two steps between neighbours would not.
		assert_eq(steepest, 1, "hole %d contours are one step" % h.number)
		if high_h - low_h >= 2:
			two_step += 1
	assert_gte(two_step, 2, "greens with a two-step tier")


func test_round_trips_through_course_save() -> void:
	var errors: Array[String] = []
	var again := CourseSave.from_json(CourseSave.to_json(_c), errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(again)
	if again == null:
		return
	assert_eq(again.content_hash(), _c.content_hash())
	assert_eq(again.holes.size(), _c.holes.size())
	for i: int in _c.holes.size():
		assert_eq(again.holes[i].to_dict(), _c.holes[i].to_dict())
