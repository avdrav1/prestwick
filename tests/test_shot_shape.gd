extends GutTest
## E20-S1 (D74): shot shape. The table (golf/shot_shapes.tres) and the clubs' shape_scale, the
## bend of every shape with every club on flat fairway (the right way, by its tuned amount, off
## the start line and across the aim), Straight byte for byte the flight it was before D74 (the
## pinned digest, tests/fixtures/straight_digest.gd), the roll, the zone narrowing, a mis-hit's
## heading offset kept and a shank flown straight, the putter never shaping, the marker matching
## the live ball's landing, determinism, the curved aim dots, the picker's keys, and the dogleg
## demonstration on Dogleg Hollow's corner holes.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const PAR3_PATH := "res://courses/example_par3.json"

var _model: ShotModel
var _flat: CourseData
var _field: HeightField
## Where the flat course's shots start, yards, aimed along +x.
var _at := Vector2(20.0, 150.0)


func before_all() -> void:
	_model = ShotModel.new()
	_flat = CourseData.create(120, 60, Surface.Type.FAIRWAY, 0)
	_field = HeightField.new(_flat, _model.params)


func _shape(id: String) -> ShotShape:
	return _model.shapes.shape(id)


func _full_clubs() -> Array[Club]:
	var out: Array[Club] = []
	for c: Club in _model.clubs.clubs:
		if not c.is_putter():
			out.append(c)
	return out


func _predict(shot: ShotLaunch, rng_seed: int = 1) -> ShotPrediction:
	return ShotPrediction.run_launch(_flat, rng_seed, shot)


# --- the table ---

func test_the_table_is_valid_and_ordered_hook_to_slice() -> void:
	var t := _model.shapes
	assert_eq(t.validate(), PackedStringArray(), "golf/shot_shapes.tres is valid")
	var ids := PackedStringArray()
	for s: ShotShape in t.shapes:
		ids.append(s.id)
	assert_eq(ids, PackedStringArray(["hook", "draw", "straight", "fade", "slice"]))
	assert_false(t.straight().bends(), "Straight does not bend")
	assert_eq(_shape("draw").side, -1, "a draw bends left (named for a right-hander)")
	assert_eq(_shape("slice").side, 1, "a slice bends right, D14's early side")
	assert_gt(_shape("hook").bend_yd, _shape("draw").bend_yd, "a hook bends more than a draw")
	assert_gt(_shape("slice").bend_yd, _shape("fade").bend_yd, "a slice bends more than a fade")
	for id: String in ["draw", "fade"]:
		assert_between(_shape(id).bend_yd, 10.0, 15.0, "%s 10 to 15 yd at a driver's carry" % id)
	for id: String in ["hook", "slice"]:
		assert_between(_shape(id).bend_yd, 30.0, 40.0, "%s 30 to 40 yd at a driver's carry" % id)


func test_shorter_clubs_bend_less_and_the_putter_never() -> void:
	var last := INF
	for c: Club in _full_clubs():
		assert_gt(c.shape_scale, 0.0, "%s shapes" % c.id)
		assert_lte(c.shape_scale, last, "%s bends no more than the club before it" % c.id)
		last = c.shape_scale
	assert_eq(_model.clubs.club("driver").shape_scale, 1.0, "bend_yd is the driver's")
	assert_eq(ShotShapes.bend_of(_model.clubs.putter(), _shape("hook")), 0.0, "the putter never")
	assert_null(_model.shapes.flight(_model.clubs.putter(), _shape("hook"), 0.0, 10.7))


func test_step_walks_the_picker_and_stops_at_the_ends() -> void:
	var t := _model.shapes
	assert_eq(t.step(t.straight(), -1).id, "draw")
	assert_eq(t.step(t.straight(), 1).id, "fade")
	assert_eq(t.step(_shape("hook"), -1).id, "hook", "stops at Hook")
	assert_eq(t.step(_shape("slice"), 1).id, "slice", "stops at Slice")
	assert_eq(t.step(null, 1).id, "fade", "from nothing, steps from Straight")


# --- Straight unchanged ---

func test_straight_is_byte_for_byte_the_flight_before_d74() -> void:
	assert_eq(StraightDigest.digest(), StraightDigest.BEFORE_E20,
			"every stroke of the digest flies, bounces and rolls as it did on main before E20")


func test_straight_picked_is_the_same_launch_as_no_shape() -> void:
	for c: Club in _full_clubs():
		var plain := _model.full(_field, c, 0.9, _at, 33.0, 1.5)
		var picked := _model.full(_field, c, 0.9, _at, 33.0, 1.5, true, _model.shapes.straight())
		assert_eq(picked.velocity, plain.velocity, "%s: same velocity" % c.id)
		assert_eq(picked.heading_deg, plain.heading_deg)
		assert_eq(picked.roll_factor, plain.roll_factor)
		assert_false(picked.is_shaped())
		assert_null(picked.shape)


# --- the bend ---

## Signed distance of ground point `p` to the right of the line from `from` along `deg`.
func _right_of(from: Vector2, deg: float, p: Vector2) -> float:
	return Vector2.from_angle(deg_to_rad(deg)).cross(p - from)


func test_each_shape_bends_the_right_way_by_its_tuned_amount_at_every_club() -> void:
	for c: Club in _full_clubs():
		for s: ShotShape in _model.shapes.shapes:
			if not s.bends():
				continue
			var shot := _model.full(_field, c, 1.0, _at, 0.0, 0.0, true, s)
			var p := _predict(shot)
			var land := Vector2(p.landing.x, p.landing.y)
			var want := ShotShapes.bend_of(c, s)
			assert_almost_eq(shot.bend_yd, want, 1e-4)
			# Off its start line by the bend, toward the shape's side.
			var off_start := _right_of(_at, shot.heading_deg, land)
			assert_almost_eq(off_start, s.side * want, maxf(0.3, want * 0.02),
					"%s %s: %.2f yd off its start line (want %.2f)" % [c.id, s.id, off_start, s.side * want])
			# It started to the other side of the aim and lands across it, past the aim by
			# (1 - start_share) of the bend.
			assert_lt(signf(shot.heading_deg) * s.side, 0.0, "%s %s starts the other way" % [c.id, s.id])
			var off_aim := _right_of(_at, 0.0, land)
			assert_almost_eq(off_aim, s.side * want * (1.0 - _model.shapes.start_share),
					maxf(0.3, want * 0.03), "%s %s: %.2f yd across the aim" % [c.id, s.id, off_aim])
			# The flight goes out the far side first: its widest point the other side of the aim.
			var widest := 0.0
			for q: Vector3 in p.path:
				widest = minf(widest, s.side * _right_of(_at, 0.0, Vector2(q.x, q.y)))
				if Vector2(q.x, q.y) == land:
					break
			assert_lt(widest, -0.04 * want, "%s %s swings out the other side first (%.2f yd)" % [c.id,
					s.id, widest])


func test_the_bend_scales_with_power() -> void:
	var c := _model.clubs.club("7i")
	var full := _model.full(_field, c, 1.0, _at, 0.0, 0.0, true, _shape("hook"))
	var half := _model.full(_field, c, 0.5, _at, 0.0, 0.0, true, _shape("hook"))
	var a := _right_of(_at, full.heading_deg, Vector2(_predict(full).landing.x, _predict(full).landing.y))
	var b := _right_of(_at, half.heading_deg, Vector2(_predict(half).landing.x, _predict(half).landing.y))
	assert_between(b / a, 0.45, 0.6, "half the carry bends about half as far (%.1f against %.1f)" % [b, a])


func test_draws_run_on_and_fades_sit_down() -> void:
	for id: String in ["driver", "7i"]:
		var c := _model.clubs.club(id)
		var run := {}
		for s: ShotShape in _model.shapes.shapes:
			var p := _predict(_model.full(_field, c, 1.0, _at, 0.0, 0.0, true, s))
			run[s.id] = Vector2(p.landing.x, p.landing.y).distance_to(Vector2(p.rest.x, p.rest.y))
		assert_gt(run["hook"], run["draw"], "%s: a hook runs on more than a draw" % id)
		assert_gt(run["draw"], run["straight"], "%s: a draw runs on" % id)
		assert_gt(run["straight"], run["fade"], "%s: a fade sits down" % id)
		assert_gt(run["fade"], run["slice"], "%s: a slice sits down more" % id)


func test_the_sidespin_ends_at_the_first_touchdown() -> void:
	var shot := _model.full(_field, _model.clubs.club("driver"), 1.0, _at, 0.0, 0.0, true, _shape("slice"))
	var ball := Ball.new(_flat, 3)
	shot.apply(ball)
	assert_ne(ball.curve, Vector2.ZERO)
	while not ball.has_landed:
		ball.step()
	assert_eq(ball.curve, Vector2.ZERO, "no push after the touchdown")


# --- the swing ---

func test_a_shape_narrows_the_accuracy_zone() -> void:
	var s := Swing.new()
	var base := s.zone_half_at(1.0)
	s.shape = _shape("draw")
	assert_almost_eq(s.zone_half_at(1.0), base * _shape("draw").zone_scale, 1e-9)
	assert_lt(s.zone_half_at(1.0), base, "a draw narrows the zone")
	s.shape = _shape("hook")
	assert_almost_eq(s.zone_half_at(1.0), base * _shape("hook").zone_scale, 1e-9)
	assert_lt(_shape("hook").zone_scale, _shape("draw").zone_scale, "a hook narrows it more")
	assert_lt(s.zone_half_at(1.1), s.zone_half_at(1.0), "the overswing penalty still applies")
	# A click inside the plain zone but outside the hook's shanks with the hook.
	var click := base * 0.9
	s.set_result(1.0, click)
	assert_true(s.is_shank(), "outside the hook's narrower zone")
	s.shape = null
	assert_false(s.is_shank(), "inside Straight's zone")


func test_a_mis_hit_keeps_d14s_heading_offset_on_a_shaped_shot() -> void:
	var c := _model.clubs.club("5i")
	var s := Swing.new()
	s.shape = _shape("fade")
	s.set_result(1.0, 0.0)
	var clean := s.launch(_model, _field, c, _at, 10.0)
	s.set_result(1.0, 0.1)
	var early := s.launch(_model, _field, c, _at, 10.0)
	assert_almost_eq(early.heading_deg - clean.heading_deg, s.tuning.deg_per_10pct, 1e-6,
			"10% early turns the shaped start 2 degrees right, as D14")
	assert_almost_eq(early.curve.length(), clean.curve.length(), 1e-4, "and keeps the shape's bend")
	assert_true(early.is_shaped())


func test_a_shank_flies_straight_whatever_the_shape() -> void:
	var c := _model.clubs.club("5i")
	var s := Swing.new()
	s.shape = _shape("hook")
	s.set_result(1.0, 0.25)
	assert_true(s.is_shank())
	var shank := s.launch(_model, _field, c, _at, 10.0)
	assert_false(shank.is_shaped(), "the shape is lost with a shank")
	assert_almost_eq(shank.heading_deg, 10.0 + s.tuning.shank_deg, 1e-6, "D14's shank")


func test_the_putter_never_shapes() -> void:
	var s := Swing.new()
	s.shape = _shape("slice")
	s.set_result(0.5, 0.05)
	var putter := _model.clubs.putter()
	var green := CourseData.create(20, 20, Surface.Type.GREEN, 0)
	var f := HeightField.new(green, _model.params)
	var putt := s.launch(_model, f, putter, Vector2(20, 50), 0.0)
	s.shape = null
	var plain := s.launch(_model, f, putter, Vector2(20, 50), 0.0)
	assert_eq(putt.ground_velocity, plain.ground_velocity)
	assert_false(putt.is_shaped())


# --- marker and determinism ---

func test_the_marker_is_where_the_live_ball_lands() -> void:
	for id: String in ["hook", "draw", "fade", "slice"]:
		for club_id: String in ["driver", "6i", "sw"]:
			var s := Swing.new()
			s.shape = _shape(id)
			var shot := s.perfect_launch(_model, _field, _model.clubs.club(club_id), _at, 20.0)
			var marker := _predict(shot, 7)
			var live := Ball.new(_flat, 7)
			shot.apply(live)
			while not live.is_at_rest():
				live.step()
			assert_eq(live.landing_position, marker.landing, "%s %s lands on its marker" % [club_id, id])
			assert_eq(live.position, marker.rest)
			assert_lt(Vector2(live.landing_position.x, live.landing_position.y).distance_to(
					Vector2(marker.landing.x, marker.landing.y)), 5.0, "within a tile")


func test_shaped_flights_are_deterministic() -> void:
	var shot := _model.full(_field, _model.clubs.club("3w"), 0.95, _at, 12.0, -0.8, true, _shape("draw"))
	var a := _predict(shot, 11)
	var b := _predict(shot, 11)
	assert_eq(a.path, b.path, "the same seed and launch give the same path")
	var again := _model.full(_field, _model.clubs.club("3w"), 0.95, _at, 12.0, -0.8, true, _shape("draw"))
	assert_eq(again.velocity, shot.velocity)
	assert_eq(again.curve, shot.curve)
	# Stepped in slices, as a frame-spread prediction is, it is the same ball.
	var ball := ShotPrediction.launched(_flat, 11, shot)
	while not ball.is_at_rest():
		ball.run(5)
	assert_eq(ball.path, a.path)


# --- the aim's dots ---

func test_the_aim_dots_follow_the_curve_and_a_guide_runs_along_the_aim() -> void:
	var view := AimView.new()
	add_child_autofree(view)
	var shot := _model.full(_field, _model.clubs.club("driver"), 1.0, _at, 0.0, 0.0, true, _shape("slice"))
	var p := _predict(shot)
	view.show_prediction(_field, p, false, shot.start, false, true, 0.0)
	assert_true(view.curved)
	assert_gt(view.dots.size(), 40)
	assert_gt(view.guide_dots.size(), 40, "a straight guide along the aim")
	# The dots leave the chord from ball to marker: the widest gap is a good part of the bend.
	var from := view.ground_screen(shot.start)
	var to := view.marker_screen
	var widest := 0.0
	for d: Vector2 in view.dots:
		widest = maxf(widest, absf((to - from).normalized().cross(d - from)))
	assert_gt(widest, 6.0, "the arc stands %.1f px off the chord at 1x" % widest)
	assert_lt(view.dots[view.dots.size() - 1].distance_to(to), 20.0,
			"the dots end within a dot's spacing of the marker")
	# A straight shot keeps the chord and no guide.
	var straight := _model.full(_field, _model.clubs.club("driver"), 1.0, _at, 0.0)
	view.show_prediction(_field, _predict(straight), false, straight.start, false, straight.is_shaped(), 0.0)
	assert_false(view.curved)
	assert_eq(view.guide_dots.size(), 0)


func test_track_dots_on_a_straight_track_are_the_chord() -> void:
	var view := AimView.new()
	add_child_autofree(view)
	var shot := _model.full(_field, _model.clubs.club("7i"), 1.0, _at, 30.0)
	var p := _predict(shot)
	view.show_prediction(_field, p, false, shot.start)
	var chord := view.dots
	var track := view._track_dots(shot.start, p.landing, view.marker_screen, p.path)
	assert_eq(track.size(), chord.size())
	for i in chord.size():
		assert_lt(track[i].distance_to(chord[i]), 0.05)


# --- the picker in Play ---

func _key(code: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e


func _tap(m: Main, code: Key) -> void:
	m.get_viewport().push_input(_key(code, true))
	m.get_viewport().push_input(_key(code, false))


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = PAR3_PATH
	add_child_autofree(m)
	m.shot_view.set_process(false)
	m.swing_control.set_process(false)
	m.camera.set_process(false)
	m.guest_sim.set_process(false)
	m.feed_panel.set_process(false)
	return m


func test_q_and_e_step_the_shape_and_the_aim_curves() -> void:
	var m := _main()
	m.set_mode(Main.Mode.PLAY)
	var sc := m.swing_control
	sc.select_club(sc.model.clubs.club("7i"))
	assert_eq(sc.shape.id, "straight", "Straight to start")
	assert_null(sc.swing.shape)
	_tap(m, KEY_Q)
	assert_eq(sc.shape.id, "draw", "Q bends more left")
	assert_eq(sc.swing.shape, sc.shape, "the swing strikes with it")
	_tap(m, KEY_Q)
	_tap(m, KEY_Q)
	assert_eq(sc.shape.id, "hook", "stops at Hook")
	assert_eq(m.swing_panel.shape_label.text, "Shape: Hook")
	assert_true(m.swing_panel.shape_prev_button.disabled, "no further left")
	_tap(m, KEY_E)
	_tap(m, KEY_E)
	_tap(m, KEY_E)
	assert_eq(sc.shape.id, "fade", "E bends more right")
	sc._refresh_aim()
	assert_true(m.aim_view.curved, "the aim draws the curve")
	# Not while a swing is under way.
	sc.press()
	_tap(m, KEY_E)
	assert_eq(sc.shape.id, "fade", "the shape is set before the swing")
	assert_true(m.swing_panel.shape_next_button.disabled)


func test_the_putter_does_not_shape_and_a_new_hole_starts_straight() -> void:
	var m := _main()
	m.set_mode(Main.Mode.PLAY)
	var sc := m.swing_control
	sc.select_shape(sc.model.shapes.shape("slice"))
	assert_eq(sc.swing.shape.id, "slice")
	var putter_only: Array[Club] = [sc.model.clubs.putter()]
	sc.legal = putter_only
	sc.club = null
	sc.select_club(sc.model.clubs.putter())
	assert_null(sc.swing.shape, "the putter strikes without the shape")
	assert_eq(sc.shape.id, "slice", "the pick is kept for the next full club")
	m.swing_panel.refresh()
	assert_eq(m.swing_panel.shape_label.text, "Shape: none (putter)")
	sc.begin(sc.course, Vector2i.ZERO, 0.0, 1)
	assert_eq(sc.shape.id, "straight", "a new hole starts Straight")


func test_the_key_map_lists_the_shapes() -> void:
	assert_has(HelpOverlay.listed_actions(), &"shape_prev")
	assert_has(HelpOverlay.listed_actions(), &"shape_next")
	assert_eq(HelpOverlay.key_text(&"shape_prev"), "Q")
	assert_eq(HelpOverlay.key_text(&"shape_next"), "E")
	var text := HelpOverlay.shape_text(_model.shapes, _model.clubs)
	for s: ShotShape in _model.shapes.shapes:
		assert_string_contains(text, s.title)
	assert_string_contains(text, "Hook 35 yd left")
	assert_string_contains(text, "Fade 12 yd right")


# --- the dogleg ---

## E20-S1 Accept: on Dogleg Hollow's corner holes a shaped drive finishes in the fairway past
## the corner (nearer the cup than the turn) from a line a straight drive puts in the trees.
## Holes 1 (left) and 2 (right) at the aims measured for D74; E20-S3 retouches the rest.
func test_a_shaped_drive_cuts_a_dogleg_a_straight_one_puts_in_the_trees() -> void:
	var course := CourseSave.load_file(DoglegHollow.PATH)
	var field := HeightField.new(course, _model.params)
	var driver := _model.clubs.club("driver")
	for case: Array in [[1, "draw", -39.0], [1, "hook", -37.0], [2, "fade", 11.0], [2, "slice", 10.0]]:
		var h: HoleData = null
		for hole: HoleData in course.holes:
			if hole.number == case[0]:
				h = hole
		var turn: Vector2 = GuestHole.turn_of(course, h)
		var tee := field.tile_center(h.tee)
		var cup := field.tile_center(h.cup)
		var aim := rad_to_deg((turn - tee).angle()) + float(case[2])
		var straight := ShotPrediction.run_launch(course, 1, _model.full(field, driver, 1.0, tee, aim),
				null, null, h.cup)
		assert_true(straight.scattered, "hole %d: the straight drive meets the trees" % h.number)
		var shot := _model.full(field, driver, 1.0, tee, aim, 0.0, true, _shape(case[1]))
		var p := ShotPrediction.run_launch(course, 1, shot, null, null, h.cup)
		var rest := Vector2(p.rest.x, p.rest.y)
		assert_false(p.scattered, "hole %d: the %s clears them" % [h.number, case[1]])
		assert_eq(field.surface_at(rest.x, rest.y), Surface.Type.FAIRWAY,
				"hole %d: the %s finishes in the fairway" % [h.number, case[1]])
		assert_lt(rest.distance_to(cup), turn.distance_to(cup),
				"hole %d: the %s is past the corner (%.0f yd to the cup)" % [h.number, case[1],
				rest.distance_to(cup)])
