extends GutTest
## E2-S8: a hole's score (D12), with no scene, so E3 guests reuse it. Strokes plus penalty
## strokes, score to par, holed, and the pick-up at double par.


func test_rules_come_from_the_resource() -> void:
	var r := ScoreRules.load_default()
	assert_not_null(r, "golf/score_rules.tres loads")
	assert_eq(r.pickup_par_multiple, 2, "D12: double par")


func test_limit_is_double_par() -> void:
	assert_eq(HoleScore.new(3).limit(), 6)
	assert_eq(HoleScore.new(4).limit(), 8)
	assert_eq(HoleScore.new(5).limit(), 10)


func test_a_new_score_is_empty() -> void:
	var s := HoleScore.new(4)
	assert_eq(s.par, 4)
	assert_eq(s.strokes, 0)
	assert_eq(s.penalty_strokes, 0)
	assert_eq(s.total(), 0)
	assert_false(s.holed)
	assert_false(s.picked_up)
	assert_false(s.is_finished())


func test_strokes_count_and_holing_finishes() -> void:
	var s := HoleScore.new(3)
	s.record_stroke(0, false)
	s.record_stroke(0, false)
	assert_eq(s.total(), 2)
	assert_eq(s.to_par(), -1)
	assert_false(s.is_finished())
	s.record_stroke(0, true)
	assert_true(s.holed)
	assert_true(s.is_finished())
	assert_false(s.picked_up)
	assert_eq(s.total(), 3)
	assert_eq(s.to_par(), 0, "a par")


func test_penalties_count_in_the_total() -> void:
	var s := HoleScore.new(4)
	s.record_stroke(1, false)
	assert_eq(s.strokes, 1)
	assert_eq(s.penalty_strokes, 1)
	assert_eq(s.total(), 2, "a water ball costs the stroke and one more")
	s.record_stroke(0, false)
	s.record_stroke(0, true)
	assert_eq(s.total(), 4)
	assert_eq(s.to_par(), 0)


func test_under_par() -> void:
	var s := HoleScore.new(4)
	s.record_stroke(0, false)
	s.record_stroke(0, true)
	assert_eq(s.to_par(), -2, "an eagle")


func test_pick_up_at_double_par() -> void:
	var s := HoleScore.new(3)
	for i in 5:
		s.record_stroke(0, false)
	assert_false(s.is_finished(), "5 on a par 3 plays on")
	s.record_stroke(0, false)
	assert_true(s.picked_up, "the 6th stroke without holing picks the ball up")
	assert_true(s.is_finished())
	assert_false(s.holed)
	assert_eq(s.total(), 6, "the card shows double par")
	assert_eq(s.to_par(), 3)


func test_a_penalty_that_reaches_the_limit_picks_up() -> void:
	var s := HoleScore.new(3)
	for i in 4:
		s.record_stroke(0, false)
	s.record_stroke(1, false)
	assert_true(s.picked_up, "4 strokes, then a 5th into water: 6 with the penalty")
	assert_eq(s.total(), 6)


func test_a_penalty_past_the_limit_still_records_double_par() -> void:
	var s := HoleScore.new(3)
	for i in 5:
		s.record_stroke(0, false)
	s.record_stroke(1, false)
	assert_true(s.picked_up)
	assert_eq(s.strokes + s.penalty_strokes, 7, "the strokes as played")
	assert_eq(s.total(), 6, "the score records double par")


func test_holed_on_the_double_par_stroke_is_holed() -> void:
	var s := HoleScore.new(3)
	for i in 5:
		s.record_stroke(0, false)
	s.record_stroke(0, true)
	assert_true(s.holed)
	assert_false(s.picked_up, "D12: holed on the double-par stroke is holed")
	assert_eq(s.total(), 6)


func test_no_strokes_after_the_hole_is_finished() -> void:
	var s := HoleScore.new(3)
	s.record_stroke(0, true)
	s.record_stroke(0, false)
	assert_eq(s.strokes, 1, "a finished hole takes no more strokes")


func test_to_par_text() -> void:
	assert_eq(HoleScore.to_par_text(0), "E")
	assert_eq(HoleScore.to_par_text(2), "+2")
	assert_eq(HoleScore.to_par_text(-1), "-1")


func test_a_custom_multiple() -> void:
	var r := ScoreRules.new()
	r.pickup_par_multiple = 3
	assert_eq(HoleScore.new(4, r).limit(), 12)
