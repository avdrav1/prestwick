extends GutTest
## E3-S5: guests on the course. The golfer sheet (art/specs/golfer.md), guests Y-sorted with
## the terrain, on-screen flights replayed and off-screen ones not, the view never changing
## the day, and the speed controls (pause, 1x, 3x) in Play. The Y-sort and the flight are also
## checked by hand: docs/decisions/e3-s5-guests-ysort.png, docs/decisions/e3-s5-guest-flight.png.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
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

func test_a_guest_stands_on_the_ground_and_sorts_under_a_raised_tile_in_front() -> void:
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
	var at := Vector2(10, 10) + view.place_offset(guest.place) / 5.0
	var yd := (at + Vector2(0.5, 0.5)) * 5.0
	var field := sim.brain.field
	var h: float = field.height_at(yd.x, yd.y) / field.yards_per_step
	var key := Iso.object_sort_key(at, h)
	assert_almost_eq(f.sprite.position.y, key, 0.01, "Iso.object_sort_key on the ground under it")
	assert_gt(f.sprite.position.y, float(Iso.depth_key(Vector2i(10, 10))), "over its own row of ground")
	assert_lt(f.sprite.position.y, float(Iso.depth_key(Vector2i(11, 10))), "under the ground in front")
	var feet := view.figure_screen(f)
	assert_almost_eq(feet, Iso.tile_to_screen(at, h), Vector2.ONE * 0.01, "feet on the ground at height_at (D50)")


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
				assert_lt(ground.y, view._field.ground_screen(f.ball_at).y, "drawn above its shadow")
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
	# E3-S20: a leg goes at walk speed over its share of the second (leg_start to leg_end).
	var found := {}
	var walking := func() -> bool:
		for f: GuestView.Figure in view.figures().values():
			var at := f.at - view.place_offset(f.guest.place) * f.spread
			if f.from.distance_to(f.to) > 10.0 and f.anim == GolferArt.Anim.WALK \
					and at.distance_to(f.from) > 3.0 and at.distance_to(f.to) > 3.0:
				found.f = f
				return true
		return false
	assert_true(_run(sim, view, walking), "a guest walks")
	var f: GuestView.Figure = found.f
	var at := f.at - view.place_offset(f.guest.place) * f.spread
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
			if f.anim == GolferArt.Anim.WALK:
				# E3-S20: the last steps of a walk that ended in the address.
				assert_lte(sim.brain.step_fraction(), view.guest_tuning.address_s() + 0.02,
						"walking up only in the address")
				continue
			assert_eq(f.anim, GolferArt.Anim.SWING)
			if f.frame < 2:
				continue  # E3-S20: the group spread closes over a frame's time once it stands
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


# --- swing, flight and walk in sync (E3-S20) ---

func test_the_impact_share_lands_on_the_arts_impact_frame() -> void:
	var art := GolferArt.load_default()
	var t := GuestTuning.load_default()
	var frames := art.frames_per_dir(GolferArt.Anim.SWING)
	assert_eq(art.swing_impact_frame, 4, "address, takeaway, top, down, impact, finish")
	assert_eq(floori(t.swing_impact_share * frames), art.swing_impact_frame,
			"swing_impact_share starts inside the impact frame")
	assert_lt(t.swing_impact_share * frames - art.swing_impact_frame, 0.01, "at its start")


func test_the_ball_leaves_at_the_impact_frame() -> void:
	var sim := _sim(GuestCourse.course(), 7)
	var view := _view(sim, Rect2(-1e5, -1e5, 2e5, 2e5))
	var impact := view.art.swing_impact_frame
	var seen := {"before": 0, "left": 0, "strokes": {}}  # a lambda captures locals by value
	var check := func() -> bool:
		for f: GuestView.Figure in view.figures().values():
			var g := f.guest
			if g.state != Guest.State.PLAYING or not view.is_replaying(f):
				continue
			var start: Vector3 = g.hole.strokes[-1].start
			var moved := f.ball_at.distance_to(start) > 0.01
			if f.frame < impact:
				seen.before += 1
				assert_false(moved, "the ball sits at the stroke's start before impact (frame %d)" % f.frame)
				assert_false(f.ball_flying, "and is not in the air")
			elif moved:
				(seen.strokes as Dictionary)[[g.id, g.hole.hole.number, g.hole.strokes.size()]] = true
				seen.left += 1
		return (seen.strokes as Dictionary).size() >= 8
	assert_true(_run(sim, view, check, 60 * 240), "eight strokes seen leaving on screen")
	assert_gt(seen.before, 100, "many frames before impact")
	assert_gt(seen.left, 0)


func test_a_figure_waits_for_its_ball_to_rest_on_screen_before_it_walks() -> void:
	var sim := _sim(GuestCourse.course(), 7)
	var view := _view(sim, Rect2(-1e5, -1e5, 2e5, 2e5))
	var seen := {"flying": 0, "walks": 0}
	var check := func() -> bool:
		for f: GuestView.Figure in view.figures().values():
			if f.anim == GolferArt.Anim.WALK and f.guest.hole != null \
					and not f.guest.hole.strokes.is_empty():
				seen.walks += 1
			if not view.is_replaying(f):
				continue
			var last := f.replay_hole.stroke_path().size() - 1
			# From impact (head 0) until it rests; before impact it may still be walking up
			# to its ball in the swing's address.
			if f.replay_head >= 0.0 and f.replay_head < last - 1:
				if f.ball_flying:
					seen.flying += 1
				assert_ne(f.anim, GolferArt.Anim.WALK,
						"guest %d does not walk while its ball is drawn (tick %.0f of %d)"
						% [f.guest.id, f.replay_head, last])
		return false
	_run(sim, view, check, 60 * 180)
	assert_gt(seen.flying, 200, "many frames of balls in the air")
	assert_gt(seen.walks, 200, "and of guests walking to their balls")


func test_no_figure_jumps_at_the_start_of_a_swing() -> void:
	for speed: float in [1.0, 3.0]:
		var sim := _sim(GuestCourse.course(), 7)
		sim.set_speed(speed)
		var view := _view(sim, Rect2(-1e5, -1e5, 2e5, 2e5))
		var step_yd := view.guest_tuning.walk_yd_per_s * speed * FRAME + 0.01
		var seen := {"starts": 0, "worst": 0.0, "prev": {}, "anim": {}}
		var check := func() -> bool:
			var prev: Dictionary = seen.prev
			var anim: Dictionary = seen.anim
			for f: GuestView.Figure in view.figures().values():
				var id := f.guest.id
				if prev.has(id) and (f.anim == GolferArt.Anim.SWING
						or f.guest.state == Guest.State.PLAYING):
					if anim.get(id, -1) != GolferArt.Anim.SWING and f.anim == GolferArt.Anim.SWING:
						seen.starts += 1
					var d: float = f.at.distance_to(prev[id])
					seen.worst = maxf(seen.worst, d)
					assert_lte(d, step_yd, "guest %d moved %.2f yd as it began its swing" % [id, d])
				prev[id] = f.at
				anim[id] = f.anim
			return false
		_run(sim, view, check, int(60 * 150 / speed))
		assert_gt(seen.starts, 20, "%sx: many swings begun" % speed)
		gut.p("%sx: %d swings begun, the most a figure moved in a frame while striking %.2f yd (a walk step %.2f)"
				% [speed, seen.starts, seen.worst, step_yd])


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


# --- shirts (E3-S28) ---

const PALETTE_PATH: String = "res://art/palette.gpl"


func _palette() -> Dictionary:
	var colors: Dictionary = {}
	for line: String in FileAccess.get_file_as_string(PALETTE_PATH).split("\n"):
		var s := line.strip_edges()
		if s.is_empty() or s.begins_with("#") or s.begins_with("GIMP") or s.begins_with("Name:") \
				or s.begins_with("Columns:"):
			continue
		var p := s.replace("\t", " ").split(" ", false)
		colors[Color8(p[0].to_int(), p[1].to_int(), p[2].to_int()).to_html(false)] = p[3]
	return colors


func test_the_shirt_set_is_palette_only_and_reads_in_grayscale() -> void:
	var art := GolferArt.load_default()
	var palette := _palette()
	var n := art.shirt_count()
	assert_gte(n, 7, "as many shirts as groups on a hole and the next on a backed-up day (D46)")
	assert_eq(art.shirt_trim.size(), n)
	assert_eq(art.shirt_pattern.size(), n)
	assert_eq(palette.get(art.shirt_key.to_html(false)), "chalk", "the sheets draw the shirt in chalk")
	assert_eq(art.shirt_body[0], art.shirt_key, "shirt 0 is the sheet's own chalk polo")
	for i in n:
		for c: Color in [art.shirt_body[i], art.shirt_trim[i]]:
			assert_true(palette.has(c.to_html(false)),
					"shirt %d colour %s is in the palette" % [i, c.to_html(false)])
	# Grayscale: every pair differs in pattern, or by a clear step in luma.
	for i in n:
		for j in range(i + 1, n):
			var same_pattern := art.shirt_pattern[i] == art.shirt_pattern[j]
			var step := absf(GolferArt.luma(art.shirt_body[i]) - GolferArt.luma(art.shirt_body[j]))
			assert_true(not same_pattern or step >= art.shirt_min_luma_step,
					"shirts %d and %d tell apart in grayscale (step %.0f)" % [i, j, step])
		if art.shirt_pattern[i] != GolferArt.Pattern.PLAIN:
			var trim := absf(GolferArt.luma(art.shirt_body[i]) - GolferArt.luma(art.shirt_trim[i]))
			assert_gte(trim, art.shirt_min_luma_step, "shirt %d's trim shows in grayscale" % i)


func test_the_shirt_key_is_only_on_the_shirt() -> void:
	# The shader swaps every key pixel, so the sheets keep chalk to the shirt rows.
	var art := GolferArt.load_default()
	for anim: GolferArt.Anim in [GolferArt.Anim.IDLE, GolferArt.Anim.WALK, GolferArt.Anim.SWING]:
		var img := art.sheet(anim).texture.get_image()
		var rows := {}
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).is_equal_approx(art.shirt_key):
					rows[y] = true
		assert_false(rows.is_empty(), "the sheet has a shirt")
		for y: int in rows:
			assert_true(y >= art.shirt_rows.x and y <= art.shirt_rows.y,
					"chalk only on the shirt rows, not row %d" % y)


func test_shirt_rows_follow_each_pattern() -> void:
	var art := GolferArt.load_default()
	for i in art.shirt_count():
		var seen := {}
		for y in range(art.shirt_rows.x, art.shirt_rows.y + 1):
			var c := art.shirt_color(i, y)
			assert_true(c == art.shirt_body[i] or c == art.shirt_trim[i])
			seen[c.to_html(false)] = true
		var want := 1 if art.shirt_pattern[i] == GolferArt.Pattern.PLAIN else 2
		assert_eq(seen.size(), want, "shirt %d shows %d colours" % [i, want])


func test_the_shirt_preview_matches_the_set() -> void:
	# scripts/placeholder.py golfer draws the idle s_0 frame in each shirt by its own copy of
	# the set: it must dress the frame as GolferArt.shirt_color does.
	var art := GolferArt.load_default()
	var preview := (load("res://art/sprites/golfer_shirts_placeholder.png") as Texture2D).get_image()
	var base := art.idle.texture.get_image().get_region(art.idle.region(art.idle.frame_index(&"s_0")))
	assert_eq(preview.get_width(), art.shirt_count() * 25 - 1, "one frame a shirt")
	for i in art.shirt_count():
		for y in base.get_height():
			for x in base.get_width():
				var c := base.get_pixel(x, y)
				var want := art.shirt_color(i, y) if c.is_equal_approx(art.shirt_key) else c
				var got := preview.get_pixel(i * 25 + x, y)
				if c.a == 0.0 and got.a == 0.0:
					continue  # transparent (the import bleeds colour into it)
				if not got.is_equal_approx(want):
					fail_test("shirt %d pixel (%d, %d): %s, want %s" % [i, x, y, got, want])
					return
	pass_test("the preview dresses every frame as the shader does")


func test_neighbouring_groups_get_different_shirts() -> void:
	var art := GolferArt.load_default()
	var n := art.shirt_count()
	for g in 20:
		for k in range(1, n):
			assert_ne(art.shirt_of_group(g), art.shirt_of_group(g + k),
					"groups %d and %d differ" % [g, g + k])


## Same-shirt groups on one hole or on neighbouring holes (a group heading for a tee counts on
## that hole), as [second, hole, group, group], for `brain` stepped to dusk.
static func _shirt_clashes(brain: GuestBrain, art: GolferArt) -> Array:
	var clashes := []
	var shirts := {}  # chosen on arrival, as GuestView does (E3-S47)
	while not brain.day_over:
		brain.step()
		GuestView.assign_shirts(brain, shirts, art.shirt_count())
		var by_hole := {}
		for g: GuestGroup in brain.groups:
			if g.phase == GuestGroup.Phase.TO_TEE or g.phase == GuestGroup.Phase.ON_HOLE:
				by_hole.get_or_add(g.hole_number, []).append(g)
		for h: int in by_hole:
			var near: Array = by_hole[h] + by_hole.get(h + 1, [])
			var worn := {}
			for g: GuestGroup in near:
				var shirt: int = shirts[g.index]
				if worn.has(shirt):
					clashes.append([brain.second, h, worn[shirt], g.index])
				worn[shirt] = g.index
	return clashes


func test_a_backed_up_day_keeps_shirts_apart_on_neighbouring_holes() -> void:
	# E3-S28 review: play backs up. On the nine-hole fixture day seed 5 puts five groups on one
	# hole and six on two neighbouring holes, seed 7 six on two (scripts/guest_day.gd's course),
	# so four shirts by arrival order met; the set has as many shirts as that. D46 (E3-S21):
	# with every group playing all nine, seed 7 puts seven groups on holes 7 and 8, so seven.
	var course: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(course))
	var art := GolferArt.load_default()
	var model := ShotModel.new()
	# E3-S47: by arrival order seed 16 put groups 0 and 7 in one shirt on holes 7 and 8 for 47 s;
	# chosen on arrival, no group meets its shirt.
	for day_seed: int in [5, 7, 16]:
		var clashes := _shirt_clashes(GuestBrain.new(course, day_seed, null, model), art)
		assert_eq(clashes, [], "seed %d: no two groups in one shirt on a hole or the next" % day_seed)


func test_two_groups_on_one_hole_draw_different_shirts() -> void:
	var sim := _sim(GuestCourse.course(), 3)
	var view := _view(sim, Rect2(-1e5, -1e5, 2e5, 2e5))
	var found := {"a": null, "b": null}  # a lambda captures locals by value
	var two_on_a_hole := func() -> bool:
		var by_hole := {}
		for f: GuestView.Figure in view.figures().values():
			var grp := sim.brain.group_of(f.guest)
			if grp.phase != GuestGroup.Phase.ON_HOLE and grp.phase != GuestGroup.Phase.TO_TEE:
				continue
			var here: Dictionary = by_hole.get_or_add(grp.hole_number, {})
			here[grp.index] = f
			if here.size() >= 2:
				var ks := here.keys()
				found.a = here[ks[0]]
				found.b = here[ks[1]]
				return true
		return false
	assert_true(_run(sim, view, two_on_a_hole, 60 * 180), "two groups share a hole")
	var a: GuestView.Figure = found.a
	var b: GuestView.Figure = found.b
	assert_ne(a.guest.group_id, b.guest.group_id)
	assert_ne(view.shirt_of(a), view.shirt_of(b), "two groups on one hole wear different shirts")
	assert_ne(a.sprite.material, b.sprite.material, "and draw them")
	var mat := a.sprite.material as ShaderMaterial
	assert_eq(mat.get_shader_parameter("body_color"), view.art.shirt_body[view.shirt_of(a)])
	for f: GuestView.Figure in view.figures().values():
		if f.guest.group_id == a.guest.group_id:
			assert_eq(view.shirt_of(f), view.shirt_of(a), "one group, one shirt")
			assert_eq(f.sprite.material, a.sprite.material)
