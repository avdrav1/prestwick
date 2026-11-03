extends GutTest
## E2-S8: play the hole end to end on the main scene. One click from Build to the tee, the
## swing, the ball, the score, the camera, and one click back to Build with the course as it
## was.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const PAR3_PATH := "res://courses/example_par3.json"
const FLAT_PATH := "res://tests/fixtures/flat_20x20.json"
## Strokes the scripted player may take before a test gives up.
const MAX_STROKES: int = 12


func _main(path: String) -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = path
	add_child_autofree(m)
	m.shot_view.set_process(false)
	m.swing_control.set_process(false)
	m.camera.set_process(false)
	return m


## Shows `c` on a main scene in Build.
func _main_on(c: CourseData) -> Main:
	var m := _main(FLAT_PATH)
	m.show_course(c)
	return m


## Plays the struck ball out to rest.
func _finish_shot(m: Main) -> void:
	var i := 0
	while m.shot_view.playing and i < 10000:
		m.shot_view.advance(0.25)
		i += 1


## Plays the hole with the scripted player until it is finished. Returns the strokes taken.
## `putts_hole_only`: ScriptedRound.plan's, the player holes out only with the putter.
func _play_out(m: Main, putts_hole_only: bool = false) -> int:
	var sc := m.swing_control
	var n := 0
	while not sc.is_finished() and n < MAX_STROKES:
		var plan := ScriptedRound.plan(sc, putts_hole_only)
		assert_not_null(plan, "a stroke can be planned")
		if plan == null:
			break
		ScriptedRound.swing(sc, plan)
		assert_true(m.shot_view.playing, "stroke %d is struck" % (n + 1))
		_finish_shot(m)
		n += 1
	return n


## A strip `w` x 10 at height 0: a 3 x 3 tee at x 1 to 3, fairway, and a green at the far end
## with the cup on it.
func _strip(w: int, par: int) -> CourseData:
	var c := CourseData.create(w, 10, Surface.Type.FAIRWAY, 0)
	for y: int in 10:
		for x: int in w:
			if x >= w - 6:
				c.set_tile(x, y, 0, Surface.Type.GREEN)
			elif x <= 3 and y >= 4 and y <= 6:
				c.set_tile(x, y, 0, Surface.Type.TEE)
	c.set_holes([HoleData.new(1, par, Vector2i(2, 5), Vector2i(w - 3, 5), false)])
	return c


func test_one_click_from_build_puts_the_ball_on_the_tee() -> void:
	var m := _main(PAR3_PATH)
	var hole: HoleData = m.course.holes[0]
	assert_eq(m.mode, Main.Mode.BUILD)
	assert_true(m.mode_button.visible, "the Play button is on the Build HUD")
	m.mode_button.pressed.emit()
	assert_eq(m.mode, Main.Mode.PLAY, "one click to Play, no scene load (D2)")
	assert_eq(m.swing_control.ball_at, m.swing_control.field.tile_center(hole.tee), "on the tee")
	assert_true(m.score_card.visible, "the scorecard shows in Play")
	assert_eq(m.score_card.par_label.text, "Par 3")
	assert_eq(m.score_card.strokes_label.text, "Strokes 0")
	assert_eq(m.score_card.to_par_label.text, "Total: in play", "no total before the hole is finished")
	assert_eq(m.score_card.status_label.text, "Pick up at 6")
	assert_true(m.camera.tracking, "the camera centres on the ball")
	assert_almost_eq(m.camera.focus, m.shot_view.ball_screen(), Vector2(0.01, 0.01))


func test_a_scripted_hole_plays_to_a_score_and_leaves_the_course_unchanged() -> void:
	var m := _main(PAR3_PATH)
	var before := m.course.content_hash()
	m.mode_button.pressed.emit()
	var strokes := _play_out(m)
	var sc := m.swing_control
	var score := sc.score
	assert_true(score.holed, "the ball is holed")
	assert_false(score.picked_up)
	assert_eq(score.strokes, strokes, "every swing is counted")
	assert_eq(sc.strokes, strokes)
	assert_eq(score.total(), score.strokes + score.penalty_strokes)
	assert_lte(score.total(), 4, "a scripted player makes par or close on a flat 160 yd par 3")
	var cup := sc.field.tile_center(sc.cup_tile())
	assert_eq(sc.ball_at, cup, "the ball sits in the cup")
	assert_eq(m.score_card.strokes_label.text, "Strokes %d" % score.total())
	assert_eq(m.score_card.to_par_label.text, "Total %s" % HoleScore.to_par_text(score.total() - 3))
	assert_string_contains(m.score_card.status_label.text, "Holed in %d" % score.total())
	# A finished hole takes no more swings.
	sc.press()
	assert_false(sc.swing.in_progress(), "no swing after the ball is holed")
	assert_false(m.aim_view.visible, "and no aim line")
	assert_false(m.swing_panel.visible, "and no swing panel")
	m.mode_button.pressed.emit()
	assert_eq(m.mode, Main.Mode.BUILD, "one click back to Build")
	assert_eq(m.course.content_hash(), before, "the course is unchanged by playing it")
	assert_false(m.score_card.visible)


func test_play_again_starts_a_fresh_score_on_the_tee() -> void:
	var m := _main(PAR3_PATH)
	m.set_mode(Main.Mode.PLAY)
	_play_out(m)
	m.set_mode(Main.Mode.BUILD)
	m.set_mode(Main.Mode.PLAY)
	assert_true(m.swing_panel.visible, "the swing panel is back")
	assert_eq(m.swing_control.score.strokes, 0)
	assert_false(m.swing_control.is_finished())


func test_a_water_ball_costs_a_stroke_and_the_next_starts_at_the_drop() -> void:
	var c := _strip(60, 5)
	for y: int in 10:
		for x: int in range(30, 54):
			c.set_tile(x, y, 0, Surface.Type.WATER)
	var m := _main_on(c)
	m.set_mode(Main.Mode.PLAY)
	var sc := m.swing_control
	assert_eq(sc.club.id, "driver")
	var plan := ScriptedRound.Plan.new()
	plan.club = sc.club
	plan.aim_deg = sc.aim_deg
	plan.ticks = ScriptedRound.ticks_for(sc, 1.0)
	ScriptedRound.swing(sc, plan)
	_finish_shot(m)
	var ball := m.shot_view.ball
	assert_eq(ball.hazard, Ball.Hazard.WATER, "the drive finds the water")
	assert_eq(sc.score.strokes, 1)
	assert_eq(sc.score.penalty_strokes, 1, "one penalty stroke")
	assert_eq(sc.score.total(), 2)
	assert_eq(sc.ball_at, Vector2(ball.drop_point.x, ball.drop_point.y), "the next shot starts at the drop")
	assert_eq(sc.field.tile_at(sc.ball_at.x, sc.ball_at.y), Vector2i(29, 5), "on the tile before the water")
	assert_eq(m.score_card.strokes_label.text, "Strokes 2 (1 penalty)")
	assert_false(sc.driver_stroke, "a drop is not the tee shot")


func test_a_water_carry_short_of_an_island_green_scores_the_penalty_not_par() -> void:
	# E2-S13: a par 3 to an island green (tiles 34 to 38 by rows 2 to 7, water all round it
	# from tile 16). A full iron that carries short splashes down in the water; the drop is
	# back on the fairway before it, never beside the flag, so the hole costs the penalty.
	var c := _strip(40, 3)
	for y: int in 10:
		for x: int in range(16, 40):
			if x < 34 or x > 38 or y < 2 or y > 7:
				c.set_tile(x, y, 0, Surface.Type.WATER)
	var m := _main_on(c)
	m.set_mode(Main.Mode.PLAY)
	var sc := m.swing_control
	var green_front := 34.0 * sc.field.yards_per_tile
	var plan: ScriptedRound.Plan = null
	for club: Club in sc.legal:
		var full := ScriptedRound.ticks_for(sc, 1.0)
		var p := ScriptedRound.predict(sc, club, sc.aim_deg, full)
		if p.hazard == Ball.Hazard.WATER and p.path[p.path.size() - 1].x < green_front:
			plan = ScriptedRound.Plan.new()
			plan.club = club
			plan.aim_deg = sc.aim_deg
			plan.ticks = full
			break
	assert_not_null(plan, "a full club carries short into the water")
	if plan == null:
		return
	ScriptedRound.swing(sc, plan)
	_finish_shot(m)
	var ball := m.shot_view.ball
	assert_eq(ball.hazard, Ball.Hazard.WATER, "%s carries short into the water" % plan.club.id)
	assert_lt(ball.hazard_position.x, green_front, "short of the island")
	assert_eq(sc.score.total(), 2, "the tee shot and its penalty")
	var drop_tile := sc.field.tile_at(sc.ball_at.x, sc.ball_at.y)
	assert_eq(drop_tile, Vector2i(15, 5), "dropped on the fairway before the water")
	var cup := sc.field.tile_center(sc.cup_tile())
	assert_gt(sc.ball_at.distance_to(cup), 5.0 * sc.field.yards_per_tile, "far from the flag")
	# A perfect-accuracy chip-in from the drop would be a real par; the test is about the
	# drop, so the scripted player holes out with the putter only.
	var rest := _play_out(m, true)
	var score := sc.score
	assert_true(score.holed, "the hole is played out")
	assert_eq(score.penalty_strokes, 1, "one penalty stroke")
	assert_eq(score.total(), score.strokes + 1, "the penalty counts")
	assert_eq(score.strokes, rest + 1)
	assert_gt(score.total(), score.par, "a water carry does not make par: %d" % score.total())
	assert_eq(m.score_card.to_par_label.text, "Total %s" % HoleScore.to_par_text(score.to_par()))


func test_the_ball_is_picked_up_at_double_par() -> void:
	var c := _strip(60, 3)
	var m := _main_on(c)
	m.set_mode(Main.Mode.PLAY)
	var sc := m.swing_control
	sc.select_club(sc.model.clubs.club("sw"))
	for i in 6:
		assert_false(sc.is_finished(), "stroke %d plays" % (i + 1))
		var plan := ScriptedRound.Plan.new()
		plan.club = sc.model.clubs.club("sw")
		plan.aim_deg = sc.aim_deg
		plan.ticks = 4  # a tap of a few yards
		ScriptedRound.swing(sc, plan)
		_finish_shot(m)
	assert_true(sc.score.picked_up, "picked up after 6 on a par 3")
	assert_true(sc.is_finished())
	assert_eq(sc.score.total(), 6)
	assert_eq(m.score_card.strokes_label.text, "Strokes 6")
	assert_eq(m.score_card.to_par_label.text, "Total +3")
	assert_string_contains(m.score_card.status_label.text, "Picked up at 6 (double par)")
	assert_false(m.shot_view.visible, "the ball is picked up")
	sc.press()
	assert_false(sc.swing.in_progress(), "no swing after the pick-up")


func test_the_camera_centres_on_the_ball_at_the_strike_and_at_rest() -> void:
	var m := _main(PAR3_PATH)
	m.set_mode(Main.Mode.PLAY)
	var cam := m.camera
	cam.pan(Vector2(500, 300))
	assert_false(cam.tracking, "the player pans away to scout")
	var sc := m.swing_control
	var plan := ScriptedRound.plan(sc)
	ScriptedRound.swing(sc, plan)
	assert_true(cam.tracking, "a shot starting centres the camera on the ball")
	m.shot_view.advance(1.0)
	m._process(0.0)
	assert_almost_eq(cam.focus, m.shot_view.ball_screen(), Vector2(0.01, 0.01), "and follows it")
	_finish_shot(m)
	assert_true(cam.tracking)
	assert_almost_eq(cam.focus, m.shot_view.ball_screen(), Vector2(0.01, 0.01), "centred where it rests")
	cam.pan(Vector2(-400, 0))
	cam.snap_back()
	cam._process(10.0)
	assert_almost_eq(cam.position, cam.focus, Vector2(0.01, 0.01), "one key snaps back")


## True when world point `p` is inside the camera's view.
func _in_view(cam: CourseCamera, p: Vector2) -> bool:
	var half := cam.view_size() * 0.5 / cam.zoom.x
	return Rect2(cam.position - half, half * 2.0).has_point(p)


func test_from_the_tee_the_ball_and_the_aim_marker_are_both_in_view() -> void:
	# E2-S8 review, pillar 2: on example_par3 the driver's marker is (1568, 784) px from the
	# tee and the 6-iron's (1005, 502); a ball-only camera showed neither.
	var m := _main(PAR3_PATH)
	var cam := m.camera
	cam.view_size_override = Vector2(1280, 720)
	m.set_mode(Main.Mode.PLAY)
	var sc := m.swing_control
	assert_eq(sc.club.id, "driver", "the default club from the tee")
	m._process(0.0)
	cam._process(10.0)
	assert_true(cam.has_lead, "aiming at rest frames the marker too")
	var marker := m.aim_view.marker_screen
	assert_true(_in_view(cam, m.shot_view.ball_screen()), "the ball is in view")
	assert_true(_in_view(cam, marker), "the driver's marker is in view")
	assert_eq(cam.zoom, Vector2(0.5, 0.5), "the driver needs 0.5x")
	for c: Club in sc.legal:
		if c.id == "6i":
			sc.select_club(c)
	m._process(0.0)
	cam._process(10.0)
	assert_true(_in_view(cam, m.aim_view.marker_screen), "the 6-iron's marker is in view")
	assert_true(_in_view(cam, m.shot_view.ball_screen()))
	var plan := ScriptedRound.plan(sc)
	ScriptedRound.swing(sc, plan)
	m._process(0.0)
	assert_false(cam.has_lead, "a flight follows the ball alone")
	_finish_shot(m)
	assert_eq(cam.zoom, Vector2.ONE, "the next aim starts from the player's 1x")


func test_no_hole_plays_without_a_score() -> void:
	var m := _main(FLAT_PATH)
	m.set_mode(Main.Mode.PLAY)
	assert_null(m.swing_control.score)
	assert_eq(m.score_card.title_label.text, "No hole")
	assert_false(m.swing_control.is_finished())
