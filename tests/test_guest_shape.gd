extends GutTest
## E20-S2 (D75, amends D54): guests shape the ball on doglegs. A skilled guest plans the shape
## that bends with the hole's turn when it gives a clearer or shorter line and aims it to cut
## the corner; a less skilled guest sometimes curves a shot it planned straight, a slice more
## often than a hook; a chosen shape that cuts the corner earns a word in the praise. Every
## number is in data/guests.json. docs/design.md Guests and reactions (Club and aim).

const DoglegHollow := preload("res://tests/fixtures/dogleg_hollow.gd")
const DoglegChampionship := preload("res://tests/fixtures/dogleg_championship.gd")
const ReactionHoles := preload("res://tests/fixtures/reaction_holes.gd")

var tuning: GuestTuning
var model: ShotModel
var putt_tuning: SwingTuning
var hollow: CourseData
var championship: CourseData


func before_all() -> void:
	tuning = GuestTuning.load_default()
	model = ShotModel.new()
	putt_tuning = tuning.guest_swing_tuning(SwingTuning.load_default())
	hollow = CourseSave.load_file(DoglegHollow.PATH)
	championship = CourseSave.load_file(DoglegChampionship.PATH)


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GuestTuning.PATH))


func _tuning_with(changes: Dictionary) -> GuestTuning:
	var d := _shipped()
	d.merge(changes, true)
	var errors: Array[String] = []
	var t := GuestTuning.from_dict(d, errors)
	assert_eq(errors, [] as Array[String], "the changed tuning loads")
	return t


## The tee-shot plan of a guest of `skill` on `hole`, made to its end.
func _tee_plan(course: CourseData, hole: HoleData, skill: int, t: GuestTuning = null) -> GuestPlan:
	var use := t if t != null else tuning
	var field := HeightField.new(course, model.params)
	var p := GuestPlan.begin(course, field, model, use, putt_tuning, field.tile_center(hole.tee),
			hole.cup, true, GuestHole.hole_seed(11, hole.number) * 1000 + 1,
			GuestHole.turn_of(course, hole), skill)
	p.advance(-1)
	return p


## -1 left, +1 right: the way `hole` turns at its corner from the tee, 0 when straight.
func _turn_side(course: CourseData, hole: HoleData) -> int:
	var turn: Variant = GuestHole.turn_of(course, hole)
	if turn == null:
		return 0
	var field := HeightField.new(course, model.params)
	var tee := field.tile_center(hole.tee)
	var cup := field.tile_center(hole.cup)
	var deg := rad_to_deg(((turn as Vector2) - tee).angle_to(cup - (turn as Vector2)))
	if absf(deg) < tuning.shape_turn_min_deg:
		return 0
	return 1 if deg > 0.0 else -1


# --- tuning ---

func test_the_shape_numbers_are_read_from_data_guests_json() -> void:
	var raw := _shipped()
	assert_eq(tuning.shape_skill_min, int(raw.shape_skill_min))
	assert_eq(tuning.strong_shape_skill_min, int(raw.strong_shape_skill_min))
	assert_eq(tuning.shape_turn_min_deg, float(raw.shape_turn_min_deg))
	assert_eq(tuning.shape_cut_shares.size(), (raw.shape_cut_shares as Array).size())
	assert_eq(tuning.shape_gain_yd, float(raw.shape_gain_yd))
	assert_eq(tuning.miss_shape_skill_max, int(raw.miss_shape_skill_max))
	assert_eq(tuning.miss_shape_share_worst, float(raw.miss_shape_share_worst))
	assert_eq(tuning.miss_slice_share, float(raw.miss_slice_share))
	assert_lt(tuning.miss_shape_skill_max, tuning.shape_skill_min,
			"nobody both plans shapes and misses with them")
	assert_gt(tuning.miss_slice_share, 0.5, "a miss is more often a slice than a hook")


func test_bad_shape_numbers_are_named() -> void:
	for bad: Array in [["shape_skill_min", 0], ["strong_shape_skill_min", 12],
			["strong_shape_skill_min", 3], ["shape_turn_min_deg", -1.0],
			["shape_cut_shares", []], ["shape_cut_shares", [3.0]], ["shape_gain_yd", -1.0],
			["miss_shape_skill_max", 11], ["miss_shape_share_worst", 1.5],
			["miss_slice_share", -0.1], ["miss_shape_scale_min", -1.0]]:
		var d := _shipped()
		d[bad[0]] = bad[1]
		var errors: Array[String] = []
		GuestTuning.from_dict(d, errors)
		assert_eq(errors.size(), 1, "%s = %s is one error" % [bad[0], bad[1]])
		if errors.size() == 1:
			assert_string_contains(errors[0], bad[0])
	var errors: Array[String] = []
	GuestTuning.from_dict(_shipped().merged({"shape_skill_min": 11, "strong_shape_skill_min": 11}, true), errors)
	assert_eq(errors, [] as Array[String], "a skill over skill_max turns shaping off")


func test_the_miss_chance_falls_with_skill_to_none() -> void:
	assert_almost_eq(tuning.miss_shape_chance(tuning.skill_min), tuning.miss_shape_share_worst, 1e-6)
	var last := INF
	for skill: int in range(tuning.skill_min, tuning.skill_max + 1):
		var c := tuning.miss_shape_chance(skill)
		assert_true(c <= last, "skill %d misses no more often than skill %d" % [skill, skill - 1])
		last = c
		if skill > tuning.miss_shape_skill_max:
			assert_eq(c, 0.0, "skill %d never misses with a shape" % skill)
		else:
			assert_gt(c, 0.0, "skill %d sometimes does" % skill)


func test_shot_shapes_list_the_bending_shapes_of_a_side_gentlest_first() -> void:
	var left := model.shapes.bending(-1)
	var right := model.shapes.bending(1)
	assert_eq(left.map(func(s: ShotShape) -> String: return s.id), ["draw", "hook"])
	assert_eq(right.map(func(s: ShotShape) -> String: return s.id), ["fade", "slice"])
	assert_true(model.shapes.bending(0).is_empty())


# --- the pick, per hole turn and skill ---

## A skilled guest shapes its tee shot on some of Dogleg Hollow's and the Championship's
## bending holes (where its shaped marker and its misses pass), always the way the hole turns,
## aimed along the line to the turn give or take the bend; its shaped marker rests nearer the
## cup than the straight plan's, never in a hazard, and its misses (shape_miss_checks) rest
## clear on a lie as good as the straight plan's. Without the miss checks it shapes on more.
func test_a_skilled_guest_shapes_with_the_turn() -> void:
	var loose := _tuning_with({"shape_miss_checks": []})
	for course: CourseData in [hollow, championship]:
		var bending := 0
		var shaped := 0
		for h: HoleData in course.holes:
			var side := _turn_side(course, h)
			var p := _tee_plan(course, h, tuning.skill_max)
			if side == 0 or not p.at_turn:
				assert_null(p.shape, "%s hole %d: no corner, no shape" % [course.course_name, h.number])
				continue
			bending += 1
			assert_eq(p.turn_side, side, "%s hole %d: the plan reads the turn" % [course.course_name, h.number])
			if p.shape == null:
				continue
			shaped += 1
			assert_eq(p.shape.side, side, "%s hole %d: the %s bends with the hole" % [course.course_name,
					h.number, p.shape.id])
			assert_not_null(p.straight_prediction, "the straight plan is kept to compare")
			var cup := HeightField.new(course, model.params).tile_center(h.cup)
			var d := Vector2(p.prediction.rest.x, p.prediction.rest.y).distance_to(cup)
			var d0 := Vector2(p.straight_prediction.rest.x, p.straight_prediction.rest.y).distance_to(cup)
			assert_lt(d, d0, "%s hole %d: the %s rests nearer the cup (%.0f against %.0f yd)" % [
					course.course_name, h.number, p.shape.id, d, d0])
			assert_eq(p.prediction.penalty_strokes, 0)
			assert_false(p.prediction.scattered, "clear of the trees")
			assert_lt(absf(p.offset_deg), 10.0, "aimed near the line to the turn")
			var field := HeightField.new(course, model.params)
			var straight_lie := model.lies.multiplier_for(field.surface_at(
					p.straight_prediction.rest.x, p.straight_prediction.rest.y))
			for m: Vector2 in tuning.shape_miss_checks:
				var miss := model.full(field, p.club, p.power * m.x, field.tile_center(h.tee),
						p.aim_deg + p.turn_side * m.y, 0.0, true, p.shape)
				var q := ShotPrediction.run_launch(course,
						GuestHole.hole_seed(11, h.number) * 1000 + 1, miss, model.params, null, h.cup)
				assert_eq(q.penalty_strokes, 0, "%s hole %d: the miss %s stays dry" % [
						course.course_name, h.number, m])
				assert_false(q.scattered, "and clear of the trees")
				assert_true(model.lies.multiplier_for(field.surface_at(q.rest.x, q.rest.y))
						>= straight_lie - 1e-6, "on a lie as good as the straight plan's")
		var looser := 0
		for h: HoleData in course.holes:
			if _tee_plan(course, h, tuning.skill_max, loose).shape != null:
				looser += 1
		gut.p("%s: shaped on %d of %d bending holes (%d without the miss checks)" % [
				course.course_name, shaped, bending, looser])
		assert_gt(bending, 0, "%s has bending holes" % course.course_name)
		assert_gt(shaped, 0, "%s: shaped on %d of %d bending holes" % [course.course_name,
				shaped, bending])
		assert_true(looser >= shaped, "the miss checks only ever take shapes away")


## Below shape_skill_min a guest plays the D54 plan exactly: the same club, power, aim and marker.
func test_a_less_skilled_guest_plans_no_shape() -> void:
	var off := _tuning_with({"shape_skill_min": tuning.skill_max + 1,
			"strong_shape_skill_min": tuning.skill_max + 1})
	for h: HoleData in hollow.holes:
		var p := _tee_plan(hollow, h, tuning.shape_skill_min - 1)
		assert_null(p.shape, "hole %d: skill %d plays it straight" % [h.number, tuning.shape_skill_min - 1])
		var s := _tee_plan(hollow, h, tuning.skill_max)
		var o := _tee_plan(hollow, h, tuning.skill_max, off)
		assert_null(o.shape, "hole %d: shaping off" % h.number)
		if s.shape == null:
			assert_eq(s.aim_deg, o.aim_deg, "hole %d: an unshaped plan is the straight one" % h.number)
		assert_eq(s.club, o.club, "hole %d: the same club either way" % h.number)
		assert_eq(s.power, o.power)
		assert_eq(o.aim_deg, p.aim_deg, "hole %d: the same straight aim at any skill" % h.number)


## Only the strongest guests try the hook or slice; a draw or fade first at shape_skill_min.
func test_the_hook_and_slice_are_for_the_strongest() -> void:
	var tried_strong := false
	for course: CourseData in [hollow, championship]:
		for h: HoleData in course.holes:
			var p := _tee_plan(course, h, tuning.shape_skill_min)
			if p.shape != null:
				assert_true(p.shape.bend_yd <= 15.0, "skill %d: only the draw or fade (%s)" % [
						tuning.shape_skill_min, p.shape.id])
			var top := _tee_plan(course, h, tuning.skill_max)
			if top.shape != null and top.shape.bend_yd > 15.0:
				tried_strong = true
	assert_true(tried_strong or tuning.strong_shape_skill_min > tuning.skill_max,
			"the best guests hook or slice round some corner")


## A straight hole, a gentle bend and a ball past the corner never shape.
func test_no_corner_no_shape() -> void:
	var fair: CourseData = ReactionHoles.fair_par4()
	assert_null(_tee_plan(fair, fair.holes[0], tuning.skill_max).shape, "a straight hole")
	var gentle := _tuning_with({"shape_turn_min_deg": 179.0})
	for h: HoleData in hollow.holes:
		assert_null(_tee_plan(hollow, h, tuning.skill_max, gentle).shape,
				"hole %d: a corner gentler than shape_turn_min_deg" % h.number)


# --- the swing ---

## A shaped plan is swung with its shape: the stroke records it, the zone is the shape's, a
## shank flies straight. The same seed plays the same strokes whatever the tick budget.
func test_a_shaped_plan_is_struck_with_its_shape_and_replays() -> void:
	var h := _shaped_hole(hollow)
	assert_not_null(h, "some hole of Dogleg Hollow is shaped at skill 10")
	var shaped := 0
	for i: int in 12:
		var g := GuestHole.new(hollow, h, tuning.skill_max, GuestHole.hole_seed(300 + i, h.number),
				tuning, model)
		g.play_out()
		var first: GuestHole.StrokeRecord = g.strokes[0]
		if first.shank:
			assert_eq(first.shape_id, "", "a shank loses the shape")
		elif first.shape_id != "":
			shaped += 1
			assert_false(first.unwanted_shape, "chosen, not a miss")
		var again := GuestHole.new(hollow, h, tuning.skill_max, GuestHole.hole_seed(300 + i, h.number),
				tuning, model)
		again.play_out(97)
		assert_eq(_strokes_of(again), _strokes_of(g), "guest %d: the same strokes at any budget" % i)
	assert_gt(shaped, 8, "most tee shots are struck shaped (%d of 12)" % shaped)


## A skilled guest's strokes on a straight hole are the same with shaping on or off: shaping
## draws no random number, so nothing else moves.
func test_shaping_changes_nothing_on_a_straight_hole() -> void:
	var fair: CourseData = ReactionHoles.fair_par4()
	var off := _tuning_with({"shape_skill_min": tuning.skill_max + 1,
			"strong_shape_skill_min": tuning.skill_max + 1})
	for i: int in 6:
		var a := GuestHole.new(fair, fair.holes[0], tuning.skill_max, GuestHole.hole_seed(50 + i, 1),
				tuning, model)
		var b := GuestHole.new(fair, fair.holes[0], tuning.skill_max, GuestHole.hole_seed(50 + i, 1),
				off, model)
		a.play_out()
		b.play_out()
		assert_eq(_strokes_of(a), _strokes_of(b), "guest %d" % i)


## Less skilled guests curve some long-club shots they planned straight, slices more than hooks,
## at about the tuned chance (raised here to 0.4 so the count means something); their click noise
## is the same as with no misses at all. At the shipped chance some skill-1 guests still miss.
func test_a_less_skilled_guest_sometimes_slices_more_often_than_hooks() -> void:
	var fair: CourseData = ReactionHoles.fair_par4()
	var none := _tuning_with({"miss_shape_share_worst": 0.0})
	var wild := _tuning_with({"miss_shape_share_worst": 0.4})
	var full := 0
	var slices := 0
	var hooks := 0
	for i: int in 80:
		var g := GuestHole.new(fair, fair.holes[0], tuning.skill_min, GuestHole.hole_seed(500 + i, 1),
				wild, model)
		g.play_out()
		var plain := GuestHole.new(fair, fair.holes[0], tuning.skill_min,
				GuestHole.hole_seed(500 + i, 1), none, model)
		plain.play_out()
		assert_eq(g.strokes[0].power, plain.strokes[0].power, "the same click noise")
		assert_eq(g.strokes[0].accuracy, plain.strokes[0].accuracy)
		for r: GuestHole.StrokeRecord in g.strokes:
			if r.club_id == "putter" or r.shank \
					or model.clubs.club(r.club_id).shape_scale < tuning.miss_shape_scale_min:
				assert_eq(r.shape_id, "", "a short club or a shank flies as planned")
				continue
			full += 1
			if r.shape_id == "":
				continue
			assert_true(r.unwanted_shape, "a skill-1 guest never chooses a shape")
			if model.shapes.shape(r.shape_id).side > 0:
				slices += 1
			else:
				hooks += 1
	var share := float(slices + hooks) / float(full)
	assert_almost_eq(share, wild.miss_shape_chance(tuning.skill_min), 0.08,
			"misses on %d of %d long-club shots" % [slices + hooks, full])
	assert_gt(slices, hooks * 2, "%d slices against %d hooks" % [slices, hooks])
	var shipped := 0
	for i: int in 120:
		var g := GuestHole.new(fair, fair.holes[0], tuning.skill_min, GuestHole.hole_seed(500 + i, 1),
				tuning, model)
		g.play_out()
		for r: GuestHole.StrokeRecord in g.strokes:
			shipped += 1 if r.unwanted_shape else 0
	assert_gt(shipped, 0, "at the shipped chance skill-1 guests miss now and then (%d)" % shipped)
	# A guest above miss_shape_skill_max never misses with a shape.
	for i: int in 20:
		var g := GuestHole.new(fair, fair.holes[0], tuning.miss_shape_skill_max + 1,
				GuestHole.hole_seed(700 + i, 1), tuning, model)
		g.play_out()
		for r: GuestHole.StrokeRecord in g.strokes:
			assert_eq(r.shape_id, "", "skill %d hits what it planned" % (tuning.miss_shape_skill_max + 1))


# --- the corner and the praise ---

## A chosen shape that rests past the corner on the fairway cut it; the hole's praise names it.
func test_a_shape_that_cuts_the_corner_is_recorded_and_praised() -> void:
	var h := _shaped_hole(hollow)
	var cut: GuestHole = null
	for i: int in 40:
		var g := GuestHole.new(hollow, h, tuning.skill_max, GuestHole.hole_seed(900 + i, h.number),
				tuning, model)
		g.play_out()
		for r: GuestHole.StrokeRecord in g.strokes:
			if r.cut_corner:
				assert_true(r.at_turn and r.shape_id != "" and not r.unwanted_shape)
				assert_eq(r.penalty_strokes, 0)
				var cup := g.field.tile_center(h.cup)
				var rest := Vector2(r.rest.x, r.rest.y)
				assert_lt(rest.distance_to(cup), (g.turn as Vector2).distance_to(cup), "past the corner")
		if cut == null and g.shape_cut() != "":
			cut = g
	assert_not_null(cut, "some skilled guest cuts the corner")
	var rec := Guest.HoleRecord.new()
	rec.number = h.number
	rec.par = h.par
	rec.score = h.par
	rec.shape_cut = cut.shape_cut()
	var guest := Guest.new()
	guest.skill = tuning.skill_max
	guest.patience = 5
	guest.taste = Guest.Taste.CASUAL
	var statics := HoleChecks.Statics.new()
	statics.hazard_on_line = true
	statics.safe_route = true
	var r := GuestReaction.judge(guest, rec, statics, tuning)
	assert_eq(r.kind, GuestReaction.Kind.PRAISE)
	assert_eq(r.text, "Hole %d: loved it, %d on a par %d, and the %s round the corner was worth the risk."
			% [h.number, h.par, h.par, rec.shape_cut])
	var errors: Array[String] = []
	var back := GuestReaction.from_save(r.to_save(), errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(back.shape_cut, rec.shape_cut, "a save keeps it")
	var old := r.to_save()
	old.erase("shape_cut")
	assert_eq(GuestReaction.from_save(old, errors).shape_cut, "", "an older save has none")
	# With the cart path's word too, both are said.
	rec.walk_s = 2.0
	rec.walk_bare_s = 30.0
	rec.walk_on_path = true
	rec.walk_from_hole = h.number - 1
	var both := GuestReaction.judge(guest, rec, statics, tuning)
	assert_string_contains(both.text, "round the corner was worth the risk, and the cart path")
	# A complaint or a neutral says nothing of it.
	rec.score = h.par + 6
	assert_false(GuestReaction.judge(guest, rec, statics, tuning).text.contains("round the corner"))


# --- an example-course day ---

## A day on Dogleg Hollow: shapes are chosen only by guests of shape_skill_min or more, always
## bending with the hole; misses only by guests of miss_shape_skill_max or less; the day replays.
func test_a_day_on_dogleg_hollow() -> void:
	var brain := GuestBrain.new(hollow, 3, tuning, model)
	brain.run_day()
	var chosen := 0
	var missed := 0
	var plays := 0
	for g: Guest in brain.guests:
		for rec: Guest.HoleRecord in g.records:
			plays += 1
			var side := _turn_side(hollow, rec.play.hole)
			for r: GuestHole.StrokeRecord in rec.play.strokes:
				if r.shape_id == "":
					continue
				if r.unwanted_shape:
					missed += 1
					assert_true(g.skill <= tuning.miss_shape_skill_max, "a miss at skill %d" % g.skill)
				else:
					chosen += 1
					assert_true(g.skill >= tuning.shape_skill_min, "a shape at skill %d" % g.skill)
					assert_true(r.at_turn, "a shape is planned at the turn")
					assert_eq(model.shapes.shape(r.shape_id).side, side, "it bends with the hole")
	assert_gt(plays, 50, "a full day")
	assert_gt(chosen, 0, "skilled guests shape (%d strokes)" % chosen)
	assert_gt(missed, 0, "weaker guests miss (%d strokes)" % missed)
	var again := GuestBrain.new(hollow, 3, tuning, model)
	again.run_day()
	assert_eq(_day_of(again), _day_of(brain), "the same seed gives the same day")


func _shaped_hole(course: CourseData) -> HoleData:
	for h: HoleData in course.holes:
		if _tee_plan(course, h, tuning.skill_max).shape != null:
			return h
	return null


func _strokes_of(g: GuestHole) -> Array:
	var out := []
	for r: GuestHole.StrokeRecord in g.strokes:
		out.append([r.club_id, r.aim_deg, r.power, r.accuracy, r.shape_id, r.rest])
	return out


func _day_of(brain: GuestBrain) -> Array:
	var out := []
	for g: Guest in brain.guests:
		for rec: Guest.HoleRecord in g.records:
			out.append([g.id, rec.number, rec.score, rec.shape_cut, _strokes_of(rec.play)])
	return out
