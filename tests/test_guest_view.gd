extends GutTest
## E3-S5: guests on the course. The golfer sheet (art/specs/golfer.md), guests Y-sorted with
## the terrain, on-screen flights replayed and off-screen ones not, the view never changing
## the day, and the speed controls (pause, 1x, 3x) in Play. The Y-sort and the flight are also
## checked by hand: docs/decisions/e3-s5-guests-ysort.png, docs/decisions/e3-s5-guest-flight.png.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FRAME := 1.0 / 60.0


# --- the sheet ---

func test_golfer_sheet_has_eight_directions_of_idle_walk_and_swing() -> void:
	var art := GolferArt.load_default()
	assert_eq(GolferArt.DIRS.size(), 8)
	var want := {GolferArt.Anim.IDLE: 2, GolferArt.Anim.WALK: 4, GolferArt.Anim.SWING: 6}
	for anim: GolferArt.Anim in want:
		var sheet := art.sheet(anim)
		assert_eq(art.frames_per_dir(anim), want[anim], "frames per direction")
		assert_eq(sheet.frame_count(), 8 * want[anim])
		assert_eq(sheet.frame_size, Vector2i(24, 24), "24 px tall")
		assert_eq(sheet.anchor, Vector2i(12, 23), "anchored at the feet")
		var tex := sheet.texture
		assert_eq(tex.get_width(), sheet.frame_count() * 25 - 1, "1 px gutter, no padding")
		assert_eq(tex.get_height(), 24)
		for d in 8:
			assert_not_null(art.frame(anim, d, want[anim] - 1))
	assert_eq(art.frame_name(GolferArt.Anim.WALK, 6, 5), &"e_1", "frames wrap")


func test_direction_of_picks_the_nearest_of_eight() -> void:
	var cases := {
		Vector2(0, 1): "s", Vector2(-1, 1): "sw", Vector2(-1, 0): "w", Vector2(-1, -1): "nw",
		Vector2(0, -1): "n", Vector2(1, -1): "ne", Vector2(1, 0): "e", Vector2(1, 1): "se",
		Vector2(32, 16): "se", Vector2(-32, 16): "sw",
	}
	for v: Vector2 in cases:
		assert_eq(GolferArt.DIRS[GolferArt.direction_of(v)], cases[v], str(v))
	assert_eq(GolferArt.direction_of(Vector2.ZERO), -1, "no move keeps the facing")


# --- helpers ---

func _sim(c: CourseData, day_seed_base: int = 3) -> GuestSim:
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.set_process(false)
	sim.start(c, day_seed_base)
	return sim


func _view(sim: GuestSim, rect: Rect2) -> GuestView:
	var view := GuestView.new()
	add_child_autofree(view)
	view.set_process(false)
	view.bind(sim)
	view.screen_rect_override = rect
	return view


## Runs frames until `pred` holds or `max_frames` pass; true if it held.
func _run(sim: GuestSim, view: GuestView, pred: Callable, max_frames: int = 3000) -> bool:
	for i in max_frames:
		sim.advance(FRAME)
		if view != null:
			view.update_view(FRAME, sim.speed)
		if pred.call():
			return true
	return false


# --- Y-sort ---

func test_a_guest_sorts_on_its_tile_top_and_under_a_raised_tile_in_front() -> void:
	var c := GuestCourse.course()
	# A two-step block just in front of (nearer the camera than) tile (10, 10).
	c.set_tile(11, 11, 4, Surface.Type.TREES)
	var sim := _sim(c)
	var view := _view(sim, Rect2(-1e5, -1e5, 2e5, 2e5))
	sim.advance(1.0)
	view.update_view(FRAME, 0.0)
	var guest: Guest = sim.brain.guests[0]
	guest.position = sim.brain.field.tile_center(Vector2i(10, 10))
	view.clear()
	view.update_view(FRAME, 0.0)
	var f := view.figure(guest)
	assert_not_null(f)
	var h := c.get_height(10, 10)
	var key := Iso.object_sort_key(Vector2(10, 10) + view.place_offset(guest.place) / 5.0, h)
	assert_almost_eq(f.sprite.position.y, key, 0.01, "Iso.object_sort_key on its tile top")
	assert_gt(f.sprite.position.y, float(Iso.top_sort_key(Vector2i(10, 10), h)), "over its own top")
	assert_lt(f.sprite.position.y, float(Iso.top_sort_key(Vector2i(11, 11), 4)), "under the raised tile in front")
	assert_lt(f.sprite.position.y, float(Iso.riser_sort_key(Vector2i(11, 11), 2)), "and its risers")
	var feet := view.figure_screen(f)
	assert_almost_eq(feet, Iso.tile_to_screen(Vector2(10, 10) + view.place_offset(guest.place) / 5.0, h),
			Vector2.ONE * 0.01, "feet on the tile top (D17)")


# --- flights ---

func _first_stroke(sim: GuestSim) -> Callable:
	return func() -> bool:
		if sim.brain == null:
			return false
		for g: Guest in sim.brain.guests:
			if g.hole != null and g.hole.strokes.size() > 0:
				return true
		return false


func test_an_on_screen_stroke_is_replayed_in_the_air() -> void:
	var sim := _sim(GuestCourse.course())
	var view := _view(sim, Rect2(-1e5, -1e5, 2e5, 2e5))
	var watch := func() -> bool:
		for f: GuestView.Figure in view.figures().values():
			if f.ball_flying and view.is_replaying(f):
				assert_true(f.ball.visible)
				var ground := view.ball_screen(f)
				assert_lt(ground.y, view._field.tile_top_screen(f.ball_at).y, "drawn above its shadow")
				return true
		return false
	assert_true(_run(sim, view, watch), "an on-screen tee shot is drawn in flight")


func test_an_off_screen_stroke_is_not_drawn_until_it_rests() -> void:
	var sim := _sim(GuestCourse.course())
	var view := _view(sim, Rect2(1e6, 1e6, 10, 10))
	var check := func() -> bool:
		for f: GuestView.Figure in view.figures().values():
			assert_false(view.is_replaying(f), "no replay off screen")
			assert_false(f.ball_flying, "no ball in the air off screen")
			if f.guest.hole != null and f.guest.hole.state == GuestHole.State.FLYING:
				assert_false(f.ball.visible, "the ball in flight is not drawn")
		return false
	_run(sim, view, check, 900)
	# After the first stroke rests, its ball shows where it lies.
	var rested := func() -> bool:
		for f: GuestView.Figure in view.figures().values():
			var h := f.guest.hole
			if h != null and h.strokes.size() > 0 and h.state != GuestHole.State.FLYING \
					and not h.is_finished():
				return f.ball.visible and f.ball_at == h.ball_at
		return false
	assert_true(_run(sim, view, rested), "a rested ball shows at its lie")


func test_watching_never_changes_the_day() -> void:
	var watched := _sim(GuestCourse.course(), 5)
	var view := _view(watched, Rect2(-1e5, -1e5, 2e5, 2e5))
	var alone := _sim(GuestCourse.course(), 5)
	for i in 60 * 40:
		watched.advance(FRAME)
		view.update_view(FRAME, watched.speed)
		alone.advance(FRAME)
	assert_eq(watched.brain.second, alone.brain.second)
	assert_eq(_trace(watched.brain), _trace(alone.brain), "the same seed gives the same day, watched or not")


func _trace(b: GuestBrain) -> Array:
	var out := []
	for g: Guest in b.guests:
		out.append([g.id, g.state, g.position, g.records.size()])
		for r: Guest.HoleRecord in g.records:
			out.append([r.number, r.score, r.end_s, r.wait_s])
	return out


func test_walks_slide_between_steps_and_stop_when_paused() -> void:
	var sim := _sim(GuestCourse.course())
	var view := _view(sim, Rect2(-1e5, -1e5, 2e5, 2e5))
	var walking := func() -> bool:
		for f: GuestView.Figure in view.figures().values():
			if f.from.distance_to(f.to) > 10.0 and sim.brain.step_fraction() > 0.3 \
					and sim.brain.step_fraction() < 0.7:
				return true
		return false
	assert_true(_run(sim, view, walking), "a guest walks")
	var f: GuestView.Figure = null
	for each: GuestView.Figure in view.figures().values():
		if each.from.distance_to(each.to) > 10.0:
			f = each
	var at := f.at - view.place_offset(f.guest.place)
	assert_gt(at.distance_to(f.from), 1.0, "between where it stood")
	assert_gt(at.distance_to(f.to), 1.0, "and where it stands now")
	assert_eq(f.anim, GolferArt.Anim.WALK)
	sim.set_speed(0.0)
	var before := f.at
	for i in 30:
		sim.advance(FRAME)
		view.update_view(FRAME, sim.speed)
	assert_eq(f.at, before, "paused: nobody moves")


func test_a_swinging_guest_stands_over_its_own_ball() -> void:
	var sim := _sim(GuestCourse.course(), 7)
	var view := _view(sim, Rect2(-1e5, -1e5, 2e5, 2e5))
	var seen := {"swings": 0, "spread": 0}  # a lambda captures locals by value
	var check := func() -> bool:
		for f: GuestView.Figure in view.figures().values():
			var g := f.guest
			if g.state != Guest.State.PLAYING or g.hole == null or g.hole.strokes.is_empty():
				continue
			seen.swings += 1
			var start: Vector3 = g.hole.strokes[-1].start
			assert_eq(f.anim, GolferArt.Anim.SWING)
			assert_almost_eq(f.at, Vector2(start.x, start.y), Vector2.ONE * 0.01,
					"the swing is at the stroke's start, no slide and no group spread")
			if g.place != 0:
				seen.spread += 1
		return false
	_run(sim, view, check, 60 * 90)
	assert_gt(seen.swings, 60, "many swing frames seen")
	assert_gt(seen.spread, 0, "including guests that stand spread in their group")
	# Once the stroke is done the spread eases back in.
	var eased := func() -> bool:
		for f: GuestView.Figure in view.figures().values():
			if f.guest.place != 0 and f.guest.state == Guest.State.WAITING and f.spread >= 1.0:
				return true
		return false
	assert_true(_run(sim, view, eased), "the group spread comes back")


func test_guest_balls_are_smaller_than_the_players_and_figures_read_at_half_zoom() -> void:
	var view := GuestView.new()
	add_child_autofree(view)
	view.set_process(false)
	var shot := ShotView.new()
	add_child_autofree(shot)
	assert_lt(view.tuning.ball_scale, 1.0)
	assert_almost_eq(view.guest_ball_radius(), shot.ball_radius * view.tuning.ball_scale, 0.001,
			"at 1x: the player's radius times ball_scale")
	assert_eq(view.figure_scale(), 1.0, "native size at 1x")
	var vp := view.get_viewport()
	var keep := vp.canvas_transform
	vp.canvas_transform = Transform2D().scaled(Vector2(0.5, 0.5))
	assert_almost_eq(view.figure_scale(), 2.0 * view.tuning.figure_min_screen_scale, 0.001,
			"at 0.5x the figure keeps its on-screen size")
	assert_almost_eq(view.guest_ball_radius(),
			view.shot_tuning.ball_min_screen_radius * 2.0 * view.tuning.ball_scale, 0.001,
			"and its ball stays smaller than the player's minimum")
	vp.canvas_transform = keep


# --- speed ---

func test_speeds_pause_1x_and_3x_step_the_day() -> void:
	var sim := _sim(GuestCourse.course())
	sim.advance(FRAME)  # builds day 1
	assert_eq(sim.day, 1)
	var counts := {}
	for s: float in GuestSim.SPEEDS:
		sim.set_speed(s)
		var start := sim.brain.second
		for i in 120:
			sim.advance(FRAME)
		counts[s] = sim.brain.second - start
	assert_eq(counts[0.0], 0, "paused")
	assert_almost_eq(float(counts[1.0]), 2.0, 1.0, "one step a real second at 1x")
	assert_almost_eq(float(counts[3.0]), 6.0, 1.0, "three at 3x")


func test_the_next_day_starts_at_dusk_with_the_next_seed() -> void:
	var sim := _sim(GuestCourse.course(), 4)
	sim.advance(FRAME)
	assert_eq(sim.brain.day_seed, GuestSim.day_seed(4, 1))
	sim.brain.run_day()
	sim.advance(FRAME)
	assert_eq(sim.day, 2)
	assert_eq(sim.brain.day_seed, GuestSim.day_seed(4, 2))


func test_main_runs_the_day_in_play_with_its_speed_controls() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(main)
	main.show_course(GuestCourse.course())
	assert_false(main.guest_sim.running, "Build holds the day")
	assert_false(main.sim_speed_panel.visible)
	assert_false(main.guest_view.visible)
	main.set_mode(Main.Mode.PLAY)
	assert_true(main.guest_sim.running)
	assert_true(main.sim_speed_panel.visible, "speed controls in Play")
	assert_true(main.guest_view.visible)
	assert_true(main.sim_speed_panel in main.hud_controls(), "framing keeps clear of it")
	(main.sim_speed_panel.buttons[3.0] as Button).pressed.emit()
	assert_eq(main.guest_sim.speed, 3.0)
	assert_true((main.sim_speed_panel.buttons[3.0] as Button).button_pressed)
	var key := InputEventAction.new()
	key.action = &"sim_pause"
	key.pressed = true
	main.sim_speed_panel._unhandled_input(key)
	assert_eq(main.guest_sim.speed, 0.0, "P pauses")
	assert_true((main.sim_speed_panel.buttons[0.0] as Button).button_pressed)
	key.action = &"sim_speed_1"
	main.sim_speed_panel._unhandled_input(key)
	assert_eq(main.guest_sim.speed, 1.0, "1 is 1x")
	main.guest_sim.advance(1.0)
	assert_string_contains(main.sim_speed_panel.status_text(), "Day 1")
	main.set_mode(Main.Mode.BUILD)
	assert_false(main.guest_sim.running)
	var second := main.guest_sim.brain.second
	await wait_physics_frames(5)
	assert_eq(main.guest_sim.brain.second, second, "Build holds the day where it is")
