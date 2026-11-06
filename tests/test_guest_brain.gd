extends GutTest
## E3-S4: guests on a timer. The day's guests spawn at the first open hole's tee, hold a state
## (walking, waiting, playing, done), play the open holes in number order, walk cart paths or
## straight lines, wait behind a slower group, and the sim moves once per simulated second,
## never per frame. The same seed gives the same day. docs/design.md Guests and reactions.

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")
const GuestDay := preload("res://scripts/guest_day.gd")

var tuning: GuestTuning
var model: ShotModel


func before_all() -> void:
	tuning = GuestTuning.load_default()
	model = ShotModel.new()


# --- the day's guests ---

func test_the_days_guests_are_drawn_from_its_seed() -> void:
	var groups := GuestSpawner.day(tuning, 11)
	var count := 0
	var gap := tuning.arrival_window_s / groups.size()
	var tastes := {}
	for i in groups.size():
		var g := groups[i]
		assert_eq(g.index, i)
		assert_almost_eq(g.arrive_s, i * gap, 1e-6, "one group every window / groups seconds")
		assert_lt(g.arrive_s, tuning.arrival_window_s, "within the morning's window")
		assert_between(g.size(), tuning.group_size_min, tuning.group_size_max)
		for guest: Guest in g.guests:
			assert_eq(guest.id, count, "numbered in arrival order")
			assert_eq(guest.group_id, i)
			count += 1
	assert_eq(count, tuning.arrivals_per_day, "the flat arrivals, the last group cut to fit")
	var again := GuestSpawner.day(tuning, 11)
	var other := GuestSpawner.day(tuning, 12)
	assert_eq(_draws(again), _draws(groups), "the same seed draws the same guests")
	assert_ne(_draws(other), _draws(groups), "another seed draws others")
	# Over many days every skill, patience and taste comes up, inside its range.
	var skills := {}
	var patiences := {}
	for day in 40:
		for g: GuestGroup in GuestSpawner.day(tuning, 100 + day):
			for guest: Guest in g.guests:
				skills[guest.skill] = true
				patiences[guest.patience] = true
				tastes[guest.taste] = true
	assert_eq(skills.size(), tuning.skill_max - tuning.skill_min + 1, "every skill 1 to 10")
	assert_eq(patiences.size(), tuning.patience_max - tuning.patience_min + 1, "every patience")
	assert_eq(tastes.size(), 3, "Purist, Adventurer and Casual")
	assert_eq(skills.keys().min(), tuning.skill_min)
	assert_eq(skills.keys().max(), tuning.skill_max)


func test_each_guest_has_skill_patience_taste_and_a_state() -> void:
	var brain := GuestBrain.new(GuestCourse.course(), 3, tuning, model)
	var seen := {}
	while not brain.day_over:
		brain.step()
		for guest: Guest in brain.guests:
			seen[guest.state] = true
			assert_between(guest.skill, tuning.skill_min, tuning.skill_max)
			assert_between(guest.patience, tuning.patience_min, tuning.patience_max)
			assert_true(guest.taste in [Guest.Taste.PURIST, Guest.Taste.ADVENTURER, Guest.Taste.CASUAL])
			if guest.state == Guest.State.WAITING:
				assert_ne(guest.waiting_for, Guest.Wait.NONE, "a waiting guest waits for something")
	for s in [Guest.State.WALKING, Guest.State.WAITING, Guest.State.PLAYING, Guest.State.DONE]:
		assert_true(seen.has(s), "a guest was %s" % Guest.State.keys()[s])
	assert_eq(brain.guests.size(), tuning.arrivals_per_day, "every guest of the day came")
	for guest: Guest in brain.guests:
		assert_true(guest.is_done(), "everyone has gone home by dusk")


# --- the timer ---

func test_the_sim_steps_once_per_simulated_second_never_per_frame() -> void:
	var brain := GuestBrain.new(GuestCourse.course(), 3, tuning, model)
	var frame := 1.0 / 60.0
	var steps := 0
	for i in 60:
		steps += brain.advance_real(frame, 1.0)
	assert_eq(steps, 1, "one step a real second at 1x")
	assert_eq(brain.second, 1)
	steps = 0
	for i in 60:
		steps += brain.advance_real(frame, 3.0)
	assert_eq(steps, 3, "three steps a real second at 3x")
	assert_eq(brain.second, 4)
	for i in 60:
		assert_eq(brain.advance_real(frame, 0.0), 0, "paused")
	assert_eq(brain.second, 4)
	# Between steps nothing a guest is or does changes; only Ball work is spent.
	for s in 30:
		var before := _snapshot(brain, false)
		var ticks := brain.ticks
		var frames_stepped := 0
		var frames := 0
		while frames_stepped == 0:
			frames_stepped = brain.advance_real(frame, 3.0)
			if frames_stepped == 0:
				frames += 1
				assert_eq(_snapshot(brain, false), before, "no guest moves between steps")
		assert_eq(frames_stepped, 1, "one step at a time at 3x and 60 fps")
		assert_between(frames, 18, 20, "a step every 20 frames at 3x")
		assert_gte(brain.ticks, ticks)


func test_ball_work_stays_inside_its_budgets_and_carries_over() -> void:
	var brain := GuestBrain.new(GuestCourse.course(), 5, tuning, model)
	brain.run_day()
	assert_lte(brain.max_guest_second_ticks, tuning.guest_ticks_per_s, "a guest's budget a second")
	assert_lte(brain.max_second_ticks, tuning.sim_ticks_per_s, "the sim's cap a second")
	# A tight sim cap: guests served in fixed order, the rest carried over, the day still played.
	var tight := _tuning({"sim_ticks_per_s": tuning.guest_ticks_per_s})
	var slow := GuestBrain.new(GuestCourse.course(), 5, tight, model)
	slow.run_day()
	assert_lte(slow.max_second_ticks, tight.sim_ticks_per_s)
	assert_gt(slow.capped_seconds, 0, "the cap was reached")
	assert_gt(_records(slow).size(), 0, "holes still finish, later")


# --- spawning and order ---

func test_guests_spawn_at_the_first_open_holes_tee() -> void:
	var b := GuestCourse.build()
	assert_true(b.close_hole(1))
	var brain := GuestBrain.new(b.course, 3, tuning, model)
	var tee := brain.field.tile_center(brain.hole_numbered(2).tee)
	var arrivals: Array[Guest] = []
	brain.guest_arrived.connect(func(g: Guest) -> void: arrivals.append(g))
	brain.step()
	assert_gt(arrivals.size(), 0, "the first group arrives in the morning")
	for g: Guest in arrivals:
		assert_eq(g.position, tee, "at hole 2's tee: hole 1 is closed")
		assert_eq(g.arrived_s, 0)
		assert_eq(brain.group_of(g).hole_number, 2)
	var last := brain.groups[-1]
	while brain.second <= last.arrive_s:
		brain.step()
	assert_eq(brain.guests.size(), tuning.arrivals_per_day, "every group arrived by noon")
	for g: Guest in last.guests:
		assert_eq(g.arrived_s, ceili(last.arrive_s), "the last group arrives at its second")
	# No open hole: nobody stays.
	var none := GuestCourse.build()
	for n in [1, 2, 3]:
		none.close_hole(n)
	var empty := GuestBrain.new(none.course, 3, tuning, model)
	empty.run_day()
	assert_eq(empty.guests.size(), 0)
	assert_eq(empty.turned_away, empty.groups.size())


func test_guests_play_open_holes_in_number_order() -> void:
	# Swap the numbers of holes 1 and 3: CourseData.holes is then not in number order, and the
	# hole numbered 1 is the one back along row 16. Close hole 2.
	var b := GuestCourse.build()
	assert_true(b.renumber_hole(1, 3))
	assert_true(b.close_hole(2))
	var c := b.course
	assert_eq(c.holes[0].number, 3, "course order is not number order")
	var brain := GuestBrain.new(c, 4, tuning, model, [
		GuestSpawner.group(0, 0.0, [[10, 10, Guest.Taste.CASUAL, 21], [9, 10, Guest.Taste.PURIST, 22]]),
	])
	var spawn := brain.field.tile_center(brain.hole_numbered(1).tee)
	assert_eq(brain.hole_numbered(1).tee, Vector2i(40, 16), "hole 1 is the old hole 3")
	brain.step()
	for g: Guest in brain.guests:
		assert_eq(g.position, spawn)
	brain.run_day()
	for g: Guest in brain.guests:
		var played: Array[int] = []
		for r: Guest.HoleRecord in g.records:
			played.append(r.number)
			assert_true(r.holed or r.picked_up)
			assert_eq(r.play.hole.tee, brain.hole_numbered(r.number).tee)
		assert_eq(played, [1, 3] as Array[int], "number order, closed hole 2 skipped")
		assert_true(g.is_done())
		assert_false(g.left_at_dusk, "a pair plays two short holes long before dusk")
		assert_eq(g.records[0].walk_yd, -1.0, "the first hole played has no walk")
		assert_gt(g.records[1].walk_yd, 0.0, "the walk from hole 1's cup to hole 3's tee")


func test_a_group_waits_behind_a_slower_group() -> void:
	var slow := [[1, 5, Guest.Taste.PURIST, 31], [1, 5, Guest.Taste.PURIST, 32],
			[2, 5, Guest.Taste.PURIST, 33], [1, 5, Guest.Taste.PURIST, 34]]
	var groups: Array[GuestGroup] = [
		GuestSpawner.group(0, 0.0, slow, 0),
		GuestSpawner.group(1, 2.0, [[10, 5, Guest.Taste.CASUAL, 41]], 4),
	]
	var brain := GuestBrain.new(GuestCourse.course(), 6, tuning, model, groups)
	var on_hole := {}
	while not brain.day_over:
		brain.step()
		var playing := {}
		for g: GuestGroup in brain.groups:
			# E3-S22: a group may stand on the tee, held, while the group ahead is on the
			# green; it has teed off once it has struck.
			if g.phase == GuestGroup.Phase.ON_HOLE and g.struck:
				assert_false(playing.has(g.hole_number),
						"one group out on hole %d at a time (second %d)" % [g.hole_number, brain.second])
				playing[g.hole_number] = true
				on_hole[g.index] = true
	assert_eq(on_hole.size(), 2)
	var fast: Guest = groups[1].guests[0]
	var waited := 0
	for r: Guest.HoleRecord in fast.records:
		waited += r.wait_s
		var ahead: Guest.HoleRecord = null
		for s: Guest in groups[0].guests:
			for sr: Guest.HoleRecord in s.records:
				if sr.number == r.number:
					assert_gte(r.start_s, sr.end_s, "hole %d: it tees off after the group ahead is done" % r.number)
	assert_gt(waited, 0, "the single waited on the tee behind the foursome")
	assert_eq(fast.records.size(), 3, "and still played all three")


## E3-S8: on a par 4 the next group does not wait for the group ahead to hole out: it steps
## onto the tee once every one of that group has struck, and tees off once its first tee shot
## is clear (E3-S22: no guest or ball of the group ahead within `play_clear_yd` of the tee or
## inside the drive's landing area, GuestBrain.hold_for; E3-S8's `tee_clear_yd` folded into
## it), so two groups play the par 4 at once. The 80 yd par 3s above never allow it.
func test_the_next_group_tees_off_once_the_group_ahead_is_out_of_reach() -> void:
	assert_false("tee_clear_yd" in tuning,
			"E3-S22: tee_clear_yd is folded into play_clear")
	var c := ReactionHoles.fair_par4()
	var h: HoleData = c.holes[0]
	var groups: Array[GuestGroup] = [
		GuestSpawner.group(0, 0.0, [[6, 5, Guest.Taste.CASUAL, 71], [4, 5, Guest.Taste.CASUAL, 72]], 0),
		GuestSpawner.group(1, 1.0, [[8, 5, Guest.Taste.CASUAL, 81]], 2),
	]
	var brain := GuestBrain.new(c, 3, tuning, model, groups)
	var tee := brain.field.tile_center(h.tee)
	var cup := brain.field.tile_center(h.cup)
	var b_teed := -1
	var held := 0
	while not brain.day_over and b_teed < 0:
		brain.serve(-1)
		var first: Guest = groups[1].guests[0]
		var rest := Vector2.INF
		if first.hole != null and first.hole.state == GuestHole.State.READY:
			rest = Vector2(first.hole.plan.prediction.rest.x, first.hole.plan.prediction.rest.y)
		brain.step()
		if first.waiting_for == Guest.Wait.GROUP_AHEAD:
			held += 1
		if first.hole != null and first.hole.strokes.size() == 1:
			b_teed = brain.second
			assert_eq(brain.teed_off.get(1, 0), 2, "it tees off with its first tee shot")
			assert_eq(groups[0].phase, GuestGroup.Phase.ON_HOLE, "the group ahead is still on the hole")
			var radius := brain.landing_radius(tee.distance_to(rest))
			for g: Guest in groups[0].guests:
				assert_false(g.hole.strokes.is_empty(), "every one of it has struck")
				for at: Vector2 in [g.position, Vector2(g.hole.ball_at.x, g.hole.ball_at.y)]:
					if at == Vector2(g.hole.ball_at.x, g.hole.ball_at.y) and g.hole.is_finished():
						continue
					assert_false(GuestBrain.in_the_way(at, tee, rest, cup, tuning.play_clear_yd, radius),
							"guest %d (or its ball) at %.0f yd from the tee, %.0f from the drive's plan, is out of its way" % [
								g.id, at.distance_to(tee), at.distance_to(rest)])
	assert_gt(b_teed, 0, "the single teed off")
	assert_gt(held, 0, "after waiting for the group ahead to clear its landing area")
	brain.run_day()
	var a_done := 0
	for g: Guest in groups[0].guests:
		a_done = maxi(a_done, g.records[0].end_s)
	assert_lt(groups[1].guests[0].records[0].start_s, a_done,
			"before the group ahead holed out: two groups on the par 4 at once")
	assert_eq(brain.teed_off.get(1, 0), 2, "both groups teed off hole 1")


## E3-S8: ready golf. The guest away among those standing at their balls plays, so a partner
## still walking out to a ball farther from the cup does not hold the group up; nobody plays
## while a ball of the group is moving or a stroke is under way.
func test_ready_golf_lets_a_partner_play_while_the_one_away_walks() -> void:
	assert_true(tuning.ready_golf, "data/guests.json plays ready golf")
	var c := ReactionHoles.fair_par4()
	var cup := Vector2.ZERO
	var specs := []
	for i in 4:
		specs.append([[10, 1, 5, 3][i], 5, Guest.Taste.CASUAL, 90 + i])
	var groups: Array[GuestGroup] = [GuestSpawner.group(0, 0.0, specs, 0)]
	var brain := GuestBrain.new(c, 5, tuning, model, groups)
	cup = brain.field.tile_center(c.holes[0].cup)
	var ready := 0
	var before := {}
	while not brain.day_over:
		var was_walking := {}
		var t := brain.second
		for g: Guest in brain.guests:
			# E3-S20: not yet at its ball also while its ball is still drawn in flight.
			was_walking[g.id] = g.is_walking() or g.ball_moved
			before[g.id] = g.hole.strokes.size() if g.hole != null else 0
		brain.step()
		for g: Guest in brain.guests:
			if g.ball_moved or g.last_walk_s == t:
				was_walking[g.id] = true
		for g: Guest in brain.guests:
			if g.hole == null or g.hole.strokes.size() <= int(before.get(g.id, 0)):
				continue
			if g.hole.strokes.size() == 1:
				continue  # tee shots go in the group's order
			var at := g.hole.strokes[-1].start
			var d := Vector2(at.x, at.y).distance_to(cup)
			for p: Guest in brain.guests:
				if p == g or p.hole == null or p.hole.is_finished() or p.hole.strokes.is_empty():
					continue
				var pd := Vector2(p.hole.ball_at.x, p.hole.ball_at.y).distance_to(cup)
				if pd > d + 0.01:
					if p.is_walking() or bool(was_walking.get(p.id, false)):
						ready += 1
					else:
						fail_test("guest %d played while guest %d stood away at its ball" % [g.id, p.id])
	assert_gt(ready, 0, "someone played while a partner farther out was still walking")


## E3-S20: a guest sets off to its ball only once its flight is drawn to rest (the impact
## share of stroke_s, then the path at flight_draw_speed: GuestBrain.ball_shown_s), part way
## into a second if need be, and never strikes in the second its walk ended unless the walk
## ended within the swing's address, so its figure has finished walking on screen.
func test_a_guest_walks_once_its_ball_is_drawn_and_strikes_after_its_walk_ends() -> void:
	var course: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(course))
	var brain := GuestBrain.new(course, 4, tuning, model)
	var walks := 0
	var strikes := 0
	var late := 0
	var up := 0
	var waited := {}
	while not brain.day_over and brain.second < 300:
		var t := brain.second
		var moved := {}
		var strokes := {}
		for g: Guest in brain.guests:
			moved[g.id] = g.ball_moved
			strokes[g.id] = g.hole.strokes.size() if g.hole != null else 0
		brain.step()
		for g: Guest in brain.guests:
			if g.hole == null or g.is_done():
				continue
			if bool(moved.get(g.id, false)) and not g.ball_moved:
				walks += 1
				var shown := brain.ball_shown_s(g)
				var set_off := float(t) + (g.leg_start if g.last_walk_s == t else 0.0)
				assert_gte(set_off, shown - 1e-6, "guest %d set off at %.2f, its ball drawn to rest at %.2f"
						% [g.id, set_off, shown])
				assert_lt(set_off, maxf(shown, float(g.strike_s) + tuning.stroke_s) + 1.0,
						"and no later than the second it rests in")
				if shown > float(g.strike_s) + tuning.stroke_s:
					late += 1
				waited[t - g.strike_s] = int(waited.get(t - g.strike_s, 0)) + 1
			if g.hole.strokes.size() > int(strokes.get(g.id, 0)):
				strikes += 1
				if g.last_walk_s == t:
					up += 1
					assert_lte(g.leg_end, tuning.address_s() + 1e-6,
							"guest %d struck in the second its walk ended, after the address" % g.id)
	assert_gt(strikes, 300, "a morning's strokes")
	assert_gt(walks, 200)
	assert_gt(late, 50, "many flights draw past the stroke's second")
	assert_gt(up, 10, "some walks end in the address of the stroke")
	gut.p("E3-S20: %d strikes (%d walked up in the address), %d walks to a ball, %d waiting past stroke_s for the drawn flight; seconds from strike to walk %s"
			% [strikes, up, walks, late, waited])


## E3-S8 review: on the hole the group behind never plays into the group ahead (play_clear):
## no ball of a following group comes to rest within PLAY_CLEAR_TEST_YD of a guest of a group
## still on the hole ahead of it, and the holds it takes for that count as GROUP_AHEAD waits.
const PLAY_CLEAR_TEST_YD: float = 20.0


func test_the_group_behind_never_plays_into_the_group_ahead() -> void:
	var c := ReactionHoles.fair_par4()
	var close := 0
	var behind := 0
	var held := 0
	for day_seed: int in [1, 2]:
		var brain := GuestBrain.new(c, day_seed, tuning, model)
		var flying := {}
		while not brain.day_over:
			var before := {}
			for g: Guest in brain.guests:
				before[g.id] = g.hole.strokes.size() if g.hole != null else 0
			brain.step()
			var q: Array = brain._queues.get(1, [])
			for i: int in q.size():
				var gg: GuestGroup = q[i]
				if gg.phase != GuestGroup.Phase.ON_HOLE:
					continue
				for g: Guest in gg.guests:
					if g.waiting_for == Guest.Wait.GROUP_AHEAD:
						held += 1
					if g.hole.strokes.size() > int(before.get(g.id, 0)):
						flying[g.id] = true
					if not flying.has(g.id) or g.hole.state == GuestHole.State.FLYING:
						continue
					flying.erase(g.id)
					var rest := Vector2(g.hole.ball_at.x, g.hole.ball_at.y)
					for j: int in i:
						var ahead: GuestGroup = q[j]
						if ahead.phase != GuestGroup.Phase.ON_HOLE:
							continue
						behind += 1
						for o: Guest in ahead.guests:
							if o.position.distance_to(rest) < PLAY_CLEAR_TEST_YD:
								close += 1
	assert_gt(behind, 0, "the group behind played with a group ahead still on the hole")
	assert_gt(held, 0, "and was held for it on the hole")
	assert_eq(close, 0, "no ball of it rested within %.0f yd of a guest ahead" % PLAY_CLEAR_TEST_YD)


## E3-S22: a guest holds for a group on a crossing hole in its landing area. On
## ReactionHoles.crossing_holes hole 2's green lies on hole 1's line 250 yd out, so groups
## putting there stand where the next group's drives come down. No stroke is struck while a
## guest out on another hole (it has struck there), or its unfinished ball, is in the
## stroke's way (GuestBrain.in_the_way at `cross_clear_yd`), unless the striking group has
## waited `cross_hold_max_s` on such groups alone; the holds count against pace as waits.
func test_a_guest_holds_for_a_group_on_a_crossing_hole_in_its_landing_area() -> void:
	var c := ReactionHoles.crossing_holes()
	var strokes := 0
	var violations := 0
	var held_on_hole_1 := 0
	var cross_wait := 0
	# E3-S20: day 18 too, since the drawn-flight walks moved days 1 and 2's groups so no
	# hole 1 tee shot met a group out on hole 2.
	for day_seed: int in [1, 2, 18]:
		var brain := GuestBrain.new(c, day_seed, tuning, model)
		while not brain.day_over:
			brain.serve(-1)
			# Before the step: each guest's strokes, plan and place, and each group's hold count.
			var before := {}
			for g: Guest in brain.guests:
				if g.hole == null:
					continue
				var plan := Vector2.INF
				if g.hole.state == GuestHole.State.READY and g.hole.plan != null:
					plan = Vector2(g.hole.plan.prediction.rest.x, g.hole.plan.prediction.rest.y)
				before[g.id] = [g.hole.strokes.size(), plan, g.position,
						Vector2(g.hole.ball_at.x, g.hole.ball_at.y), g.hole.strokes.is_empty(),
						g.hole.is_finished(), brain.group_of(g).phase, brain.group_of(g).hole_number]
			var capped := {}
			for gr: GuestGroup in brain.groups:
				capped[gr.index] = gr.cross_held_s >= tuning.cross_hold_max_s
			brain.step()
			for g: Guest in brain.guests:
				if g.hole == null or not before.has(g.id) or g.hole.strokes.size() != int(before[g.id][0]) + 1:
					continue
				strokes += 1
				var me := brain.group_of(g)
				if bool(capped[me.index]):
					continue
				var at := Vector2(g.hole.strokes[-1].start.x, g.hole.strokes[-1].start.y)
				var rest: Vector2 = before[g.id][1]
				var cup := brain.field.tile_center(g.hole.hole.cup)
				for o: Guest in brain.guests:
					var og := brain.group_of(o)
					if og == me or not before.has(o.id) or int(before[o.id][7]) == me.hole_number:
						continue
					# Groups update in index order: one ahead of the striker has already moved.
					var b: Array = before[o.id]
					var pos: Vector2 = o.position if og.index < me.index else b[2]
					var ball: Vector2 = Vector2(o.hole.ball_at.x, o.hole.ball_at.y) if og.index < me.index and o.hole != null else b[3]
					if b[6] != GuestGroup.Phase.ON_HOLE or bool(b[4]) or og.hole_number != int(b[7]):
						continue  # not out on another hole (a group moving on this second has left it)
					if og.index < me.index and (o.is_done() or og.phase != GuestGroup.Phase.ON_HOLE):
						continue  # E3-S51: it finished its last hole this second, before the striker moved
					if GuestBrain.in_the_way(pos, at, rest, cup, tuning.cross_clear_yd, tuning.cross_clear_yd) \
							or (not bool(b[5]) and GuestBrain.in_the_way(ball, at, rest, cup,
									tuning.cross_clear_yd, tuning.cross_clear_yd)):
						violations += 1
		for g: Guest in brain.guests:
			for r: Guest.HoleRecord in g.records:
				cross_wait += r.cross_wait_s
				if r.number == 1 and r.cross_wait_s > 0:
					held_on_hole_1 += 1
	assert_gt(strokes, 100, "both days were played")
	assert_eq(violations, 0, "nobody struck into a guest out on the other hole")
	assert_gt(cross_wait, 0, "guests waited for the crossing group, counted against pace")
	assert_gt(held_on_hole_1, 0, "hole 1 guests held for guests out on hole 2")


## E3-S8 review: the engine's budget never fails pace by itself. A guest alone on the course
## counts no wait at all, its own putt solve (reading the green) included, so even patience 1
## never fails pace on a hole with nobody ahead.
func test_a_lone_impatient_guest_never_fails_pace_on_wait() -> void:
	var c := ReactionHoles.fair_par4()
	var greens := 0
	# E3-S20: at 480 ticks a second the putt solve now always finishes while the guest waits
	# for its ball to show and walks to it, so a quarter of the budget makes it read the green.
	var tight := _tuning({"guest_ticks_per_s": 120})
	for s: int in 8:
		var groups: Array[GuestGroup] = [
			GuestSpawner.group(0, 0.0, [[1 + s, 1, Guest.Taste.CASUAL, 300 + s]], 0)]
		var brain := GuestBrain.new(c, s, tight, model, groups)
		while not brain.day_over:
			brain.step()
			if not brain.guests.is_empty() \
					and brain.guests[0].waiting_for == Guest.Wait.READING_GREEN:
				greens += 1
		var r: Guest.HoleRecord = brain.guests[0].records[0]
		assert_eq(r.wait_s, 0, "nobody ahead: no counted wait (guest %d)" % s)
		assert_true(r.reaction.passed[GuestReaction.Check.PACE], "so pace passes")
	assert_gt(greens, 0, "some of them did wait reading the green, uncounted")


# --- walking ---

func test_a_walk_follows_a_cart_path_when_one_serves_it() -> void:
	var b := CourseBuilder.new(CourseData.create(40, 20, Surface.Type.ROUGH, 2))
	var from := Vector2(12.5, 12.5)   # tile (2, 2)
	var to := Vector2(162.5, 12.5)    # tile (32, 2)
	var straight := GuestWalk.route(b.course, from, to, tuning)
	assert_false(straight.on_path, "no path: a straight line")
	assert_eq(straight.points, PackedVector2Array([from, to]))
	assert_almost_eq(straight.length, 150.0, 1e-4)
	# A path one row down (5 yd off the line), joined at both ends.
	b.begin_stroke()
	for cell: Vector2i in BuildTool.grid_line(Vector2i(3, 3), Vector2i(31, 3)):
		b.paint(cell, Surface.Type.CART_PATH, 1)
	b.end_stroke()
	var w := GuestWalk.route(b.course, from, to, tuning)
	var cache := GuestWalk.Cache.new()
	var first := GuestWalk.route(b.course, from, to, tuning, 5.0, cache)
	var again := GuestWalk.route(b.course, from, to, tuning, 5.0, cache)
	assert_eq(cache.size(), 1, "one search for both walks")
	assert_eq(first.points, w.points, "a cached search gives the uncached route")
	assert_eq(again.points, w.points)
	assert_true(w.on_path)
	assert_eq(w.points[0], from)
	assert_eq(w.points[-1], to)
	for i in range(1, w.points.size() - 1):
		var t := Vector2i(floori(w.points[i].x / 5.0), floori(w.points[i].y / 5.0))
		assert_eq(b.course.get_surface(t.x, t.y), Surface.Type.CART_PATH, "every corner on the path")
	assert_lte(w.length, straight.length * tuning.cart_path_max_detour)
	# Walking it: 40 yd a second, along the path, to the end.
	var seconds := 0
	while not w.is_done():
		var p := w.move(tuning.walk_yd_per_s)
		seconds += 1
		assert_lte(p.distance_to(Vector2(p.x, 17.5)), 5.0, "on or beside the path row")
	assert_eq(seconds, ceili(w.length / tuning.walk_yd_per_s))
	assert_eq(w.position(), to)
	# A path that would double the walk is not taken.
	var far := CourseBuilder.new(CourseData.create(40, 40, Surface.Type.ROUGH, 2))
	far.begin_stroke()
	for cell: Vector2i in BuildTool.grid_line(Vector2i(2, 3), Vector2i(2, 30)) \
			+ BuildTool.grid_line(Vector2i(2, 30), Vector2i(32, 30)) \
			+ BuildTool.grid_line(Vector2i(32, 30), Vector2i(32, 3)):
		far.paint(cell, Surface.Type.CART_PATH, 1)
	far.end_stroke()
	assert_false(GuestWalk.route(far.course, from, to, tuning).on_path, "too long a detour")
	# Unowned land and water are no wall: the straight walk crosses them.
	var c := CourseData.create(40, 20, Surface.Type.ROUGH, 2)
	var land := CourseBuilder.new(c)
	land.begin_stroke()
	land.paint(Vector2i(17, 2), Surface.Type.WATER, 5)
	land.end_stroke()
	c.set_parcel_owned(Vector2i(1, 0), false)
	assert_false(c.is_owned(20, 2))
	var over := GuestWalk.route(c, from, to, tuning)
	assert_eq(over.points, PackedVector2Array([from, to]), "straight over water and unowned land")


func test_the_bounded_path_search_takes_the_route_an_unbounded_one_would() -> void:
	# E3-S15: random lattices of cart path (some pieces cut off from the rest) and random walks
	# across them: the bounded search gives the same walk as the unbounded search with the
	# detour check after it, every time, and searches fewer tiles where an end is cut off.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1515
	var taken := 0
	var refused := 0
	for lattice in 6:
		var c := CourseData.create(48, 48, Surface.Type.ROUGH, 2)
		var b := CourseBuilder.new(c)
		b.begin_stroke()
		var step := 2 + lattice % 3
		for y in 48:
			for x in 48:
				if (x % step == 0 or y % step == 0) and rng.randf() < 0.85:
					b.paint(Vector2i(x, y), Surface.Type.CART_PATH, 1)
		b.end_stroke()
		for walk in 40:
			var from := Vector2(rng.randf_range(0.0, 240.0), rng.randf_range(0.0, 240.0))
			var to := Vector2(rng.randf_range(0.0, 240.0), rng.randf_range(0.0, 240.0))
			var w := GuestWalk.route(c, from, to, tuning)
			var want := _unbounded_route(c, from, to)
			assert_eq(w.points, want, "lattice %d walk %d: the unbounded search's walk" % [lattice, walk])
			if want.size() > 2:
				taken += 1
			else:
				refused += 1
	assert_gt(taken, 20, "many walks follow the path")
	assert_gt(refused, 20, "and many do not")
	# A disconnected end: a long path row and one lone path tile below it. No route either way,
	# bounded or not (the bound only stops the search sooner), so the walk is straight.
	var c := CourseData.create(120, 10, Surface.Type.ROUGH, 2)
	var row := CourseBuilder.new(c)
	row.begin_stroke()
	for x in 119:
		row.paint(Vector2i(x, 2), Surface.Type.CART_PATH, 1)
	row.paint(Vector2i(20, 6), Surface.Type.CART_PATH, 1)
	row.end_stroke()
	assert_eq(GuestWalk._search(c, Vector2i(0, 2), Vector2i(20, 6), 30), [] as Array[Vector2i])
	assert_eq(GuestWalk.route(c, Vector2(2.5, 12.5), Vector2(102.5, 32.5), tuning).points,
			PackedVector2Array([Vector2(2.5, 12.5), Vector2(102.5, 32.5)]), "no path: straight")


func test_a_cached_walk_equals_a_fresh_one_after_a_path_edit() -> void:
	# E3-S15: the brain keeps cart path searches across steps and drops them when the course is
	# written (CourseData.revision), so a walk after a path edit is the fresh walk on the edited
	# course, never the one cached before it.
	var b := CourseBuilder.new(CourseData.create(40, 20, Surface.Type.ROUGH, 2))
	b.begin_stroke()
	for cell: Vector2i in BuildTool.grid_line(Vector2i(3, 3), Vector2i(31, 3)):
		b.paint(cell, Surface.Type.CART_PATH, 1)
	b.end_stroke()
	var brain := GuestBrain.new(b.course, 1, tuning, model, [
		GuestSpawner.group(0, 0.0, [[10, 10, Guest.Taste.CASUAL, 61]]),
	])
	var from := Vector2(12.5, 12.5)
	var to := Vector2(162.5, 12.5)
	var first := brain.route(from, to)
	assert_true(first.on_path, "the path serves the walk")
	assert_eq(brain.route_cache_size(), 1)
	for i in 5:
		brain.step()
	var again := brain.route(from, to)
	assert_eq(again.points, first.points, "kept across steps")
	assert_eq(brain.route_cache_size(), 1, "the search ran once")
	# Cut the path in the middle: the cached route crosses rough now; the brain's walk is the
	# fresh one (straight: no path joins the ends).
	b.paint(Vector2i(17, 3), Surface.Type.ROUGH, 1)
	var cut := brain.route(from, to)
	assert_eq(cut.points, GuestWalk.route(b.course, from, to, tuning).points, "fresh after the cut")
	assert_false(cut.on_path, "the cut path no longer serves the walk")
	# Mend it one row down round the cut: the fresh walk follows the new tiles.
	b.begin_stroke()
	for cell: Vector2i in [Vector2i(16, 4), Vector2i(17, 4), Vector2i(18, 4)]:
		b.paint(cell, Surface.Type.CART_PATH, 1)
	b.end_stroke()
	var mended := brain.route(from, to)
	assert_eq(mended.points, GuestWalk.route(b.course, from, to, tuning).points, "fresh after the mend")
	assert_true(mended.on_path)
	assert_true(Vector2(17.5, 4.5) * 5.0 in mended.points, "round the cut")
	# An undo writes the tiles back: the walk is the original one again, searched afresh.
	b.undo()
	b.undo()
	assert_eq(brain.route(from, to).points, first.points, "the old path, searched afresh")


## GuestWalk.route as it was before E3-S15: an unbounded search, then the detour check.
func _unbounded_route(c: CourseData, from: Vector2, to: Vector2) -> PackedVector2Array:
	var straight := PackedVector2Array([from, to])
	var a := GuestWalk._nearest_path_tile(c, from, tuning.cart_path_reach_yd, 5.0)
	var e := GuestWalk._nearest_path_tile(c, to, tuning.cart_path_reach_yd, 5.0)
	if a.x < 0 or e.x < 0 or a == e:
		return straight
	var tiles := GuestWalk._search(c, a, e, -1)
	if tiles.is_empty():
		return straight
	var out := PackedVector2Array([from])
	for t: Vector2i in tiles:
		out.append((Vector2(t) + Vector2(0.5, 0.5)) * 5.0)
	out.append(to)
	if GuestWalk._polyline_length(out) <= from.distance_to(to) * tuning.cart_path_max_detour:
		return out
	return straight


func test_guests_walk_the_cart_path_between_holes() -> void:
	# A path from beside hole 2's green, south and west, to beside hole 3's tee: the walk off
	# hole 2 follows it. Without it the walk is straight.
	var b := GuestCourse.build()
	b.begin_stroke()
	for cell: Vector2i in BuildTool.grid_line(Vector2i(42, 7), Vector2i(42, 15)):
		b.paint(cell, Surface.Type.CART_PATH, 1)
	b.end_stroke()
	for n in [2, 3]:
		b.open_hole(n)  # the path runs through their footprints, which closed them
	assert_true(b.course.holes.all(func(h: HoleData) -> bool: return h.open), "every hole open again")
	var on_path := _path_steps(b.course)
	assert_gt(on_path, 0, "a guest stood on the cart path on the way to hole 3")
	assert_eq(_path_steps(GuestCourse.course()), 0, "no path, no path steps")


# --- determinism ---

func test_the_same_seed_gives_the_same_day() -> void:
	var a := _day_log(9, -1.0)
	var again := _day_log(9, -1.0)
	assert_gt(a.size(), 100)
	assert_eq(again, a, "the same seed, stepped twice")
	var framed := _day_log(9, 3.0)
	assert_eq(framed, a, "the same day at 3x in 60 fps frames, Ball work spread over them")
	var other := _day_log(10, -1.0)
	assert_ne(other, a, "another seed, another day")


func test_a_day_run_in_sliced_frames_gives_the_same_records_as_one_run_a_step_at_a_time() -> void:
	# E3-S14: Ball work is sliced over a second's frames by need, at most frame_ticks_max a frame;
	# a step whose second's work is not done waits for it. Only the day's lateness changes.
	var direct := _day_log(9, -1.0)
	var brains: Array = []
	assert_eq(_day_log(9, 3.0, 1.0 / 30.0, null, brains), direct, "3x at 30 fps")
	assert_lte((brains[0] as GuestBrain).max_frame_ticks, tuning.frame_ticks_max)
	var tight := _tuning({"frame_ticks_max": 40})
	brains.clear()
	assert_eq(_day_log(9, 3.0, 1.0 / 60.0, tight, brains), direct,
			"a frame budget so tight that steps wait for their work")
	var held: GuestBrain = brains[0]
	assert_lte(held.max_frame_ticks, 40, "never past the frame budget")
	assert_gt(held.held_frames, 0, "steps waited: the day ran late, not differently")
	brains.clear()
	assert_eq(_day_log(9, 1.0, 1.0 / 60.0, tight, brains), direct, "1x under the tight budget")


func test_ball_work_is_paced_by_need_not_spent_up_to_the_cap_at_once() -> void:
	# A lone guest needs at most guest_ticks_per_s a second: at 3x and 60 fps a frame spends
	# about a twentieth of that, not 240 (a twentieth of the sim's cap) until it runs out.
	var brain := GuestBrain.new(GuestCourse.course(), 3, tuning, model, [
		GuestSpawner.group(0, 0.0, [[5, 5, Guest.Taste.CASUAL, 71]]),
	])
	var share := ceili(tuning.guest_ticks_per_s / 20.0) + 1
	var busy := 0
	for i in 20 * 60:
		var before := brain.ticks
		brain.advance_real(1.0 / 60.0, 3.0)
		assert_lte(brain.ticks - before, share, "a lone guest's share a frame")
		busy += 1 if brain.ticks > before else 0
		if brain.day_over:
			break
	assert_gt(busy, 100, "its work spread over many frames")
	# A full field: at most the cap's share a frame (80 at 1x, 240 at 3x) and the frame budget.
	for speed: float in [1.0, 3.0]:
		var brains: Array = []
		_day_log(9, speed, 1.0 / 60.0, null, brains)
		var b: GuestBrain = brains[0]
		assert_lte(b.max_frame_ticks, mini(ceili(tuning.sim_ticks_per_s * speed / 60.0) + 1,
				tuning.frame_ticks_max), "%sx" % speed)
		assert_eq(b.held_frames, 0, "%sx at 60 fps keeps time" % speed)


# --- dusk and edits ---

## D46 (E3-S21): the day is long enough for every group that tees off to finish its nine.
## The slowest group a day draws is a skill-1 foursome, and it starts latest as the last of
## the most groups a day can draw with a foursome last (`arrivals_per_day` - 4 singles first,
## so (n - 1) / n of `arrival_window_s`, n = arrivals_per_day - 3). Alone on the nine-hole
## fixture from there it holes out on all nine before dusk. `scripts/guest_day.gd` measures
## days 1 to 10 with the field ahead of it.
func test_a_skill_1_foursome_arriving_last_finishes_its_nine_by_dusk() -> void:
	var course: CourseData = NineHoles.land(7)
	var opened: Array[int] = NineHoles.build(CourseBuilder.new(course))
	assert_eq(opened.size(), 9, "nine open holes")
	var n := tuning.arrivals_per_day - 3
	var arrive := float(n - 1) * tuning.arrival_window_s / float(n)
	var specs := []
	for i in 4:
		specs.append([tuning.skill_min, 5, Guest.Taste.CASUAL, 900 + i])
	var brain := GuestBrain.new(course, 1, tuning, model,
			[GuestSpawner.group(0, arrive, specs)])
	brain.run_day()
	for g: Guest in brain.guests:
		assert_eq(g.records.size(), 9, "guest %d played all nine" % g.id)
		assert_false(g.left_at_dusk, "guest %d went home before dusk (left at %d of %d s)" % [
				g.id, g.left_s, tuning.day_s])


## D46 review: a slow foursome early in the day holds up every group behind it, since groups
## never pass. Day seed 6 with its first group made a skill-1 foursome is the latest day of the
## sweep (`scripts/guest_day.gd`, the foursome in every slot of days 1 to 10: last finish 490 s);
## every guest of that field still holes out on all nine before dusk.
func test_a_skill_1_foursome_leading_the_latest_day_still_lets_everyone_finish_nine() -> void:
	var course: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(course))
	var groups := GuestDay.with_foursome(GuestSpawner.day(tuning, 6), 0)
	assert_eq(groups[0].size(), 4, "the first group is the foursome")
	var brain := GuestBrain.new(course, 6, tuning, model, groups)
	brain.run_day()
	var field := 0
	for gr: GuestGroup in groups:
		field += gr.size()
	assert_eq(brain.guests.size(), field, "every group teed off")
	for g: Guest in brain.guests:
		assert_eq(g.records.size(), 9, "guest %d (group %d) played all nine" % [g.id, g.group_id])
		assert_false(g.left_at_dusk, "guest %d went home before dusk (left at %d of %d s)" % [
				g.id, g.left_s, tuning.day_s])


func test_dusk_sends_everyone_home_and_an_unfinished_hole_gives_no_record() -> void:
	var short := _tuning({"day_s": 30, "arrival_window_s": 15})
	var brain := GuestBrain.new(GuestCourse.course(), 3, short, model)
	var records: Array[Guest.HoleRecord] = []
	brain.hole_finished.connect(func(_g: Guest, r: Guest.HoleRecord) -> void: records.append(r))
	brain.run_day()
	assert_eq(brain.second, 31, "the day ends at day_s")
	var at_dusk := 0
	for g: Guest in brain.guests:
		assert_true(g.is_done())
		if g.left_at_dusk:
			at_dusk += 1
			assert_eq(g.left_s, 30)
			assert_lt(g.records.size(), 3, "out at dusk: its hole under way gave no record")
		else:
			assert_eq(g.records.size(), 3, "gone home early: a round done")
	assert_gt(at_dusk, 0, "guests still out at dusk left")
	for r in records:
		assert_true(r.holed or r.picked_up, "a record is a finished hole")
		assert_lte(r.end_s, 30)
	brain.step()
	assert_eq(brain.second, 31, "nothing after dusk")


func test_a_hole_edited_under_a_group_ends_with_no_record() -> void:
	var b := GuestCourse.build()
	var brain := GuestBrain.new(b.course, 4, tuning, model, [
		GuestSpawner.group(0, 0.0, [[6, 5, Guest.Taste.CASUAL, 51]]),
	])
	var guest: Guest = brain.groups[0].guests[0]
	while not (brain.groups[0].hole_number == 2 and brain.groups[0].struck):
		brain.step()
	assert_true(b.close_hole(2), "closed while the guest plays it")
	brain.run_day()
	var played: Array[int] = []
	for r: Guest.HoleRecord in guest.records:
		played.append(r.number)
	assert_eq(played, [1, 3] as Array[int], "no record for hole 2; on to hole 3")
	assert_eq(guest.records[1].walk_yd, -1.0,
			"hole 2 was left mid-play: no pace walk from hole 1's cup to hole 3's tee")


func test_a_long_frame_runs_at_most_max_steps_per_frame() -> void:
	var brain := GuestBrain.new(GuestCourse.course(), 3, tuning, model)
	assert_eq(brain.advance_real(2.0, 3.0), tuning.max_steps_per_frame, "a 2 s hitch at 3x")
	assert_lte(brain.max_frame_ticks, tuning.frame_ticks_max, "its catch-up inside the frame budget")
	assert_eq(brain.second, tuning.max_steps_per_frame)
	var frame := 1.0 / 60.0
	var steps := 0
	for i in 60:
		steps += brain.advance_real(frame, 3.0)
	assert_eq(steps, 3, "the hitch's extra time was let go, not owed")
	# The late day is the same day: a step's state never depends on the frames around it.
	var direct := GuestBrain.new(GuestCourse.course(), 3, tuning, model)
	for i in brain.second:
		direct.step()
	assert_eq(_snapshot(brain, false), _snapshot(direct, false))


# --- helpers ---

func _tuning(overrides: Dictionary) -> GuestTuning:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GuestTuning.PATH))
	d.merge(overrides, true)
	var errors: Array[String] = []
	var t := GuestTuning.from_dict(d, errors)
	assert_eq(errors, [] as Array[String])
	return t


func _draws(groups: Array[GuestGroup]) -> Array:
	var out := []
	for g: GuestGroup in groups:
		for guest: Guest in g.guests:
			out.append([g.index, g.arrive_s, guest.skill, guest.patience, guest.taste, guest.guest_seed])
	return out


func _records(brain: GuestBrain) -> Array[Guest.HoleRecord]:
	var out: Array[Guest.HoleRecord] = []
	for g: Guest in brain.guests:
		out.append_array(g.records)
	return out


## Every guest's state, what it waits for, where it stands, its strokes and, with `work`, its
## hole's state (which Ball work changes between steps: a plan finishing, a ball resting).
func _snapshot(brain: GuestBrain, work: bool = true) -> String:
	var parts := PackedStringArray()
	for g: Guest in brain.guests:
		parts.append("%d:%d:%d:%.3f,%.3f:%d:%d" % [g.id, g.state, g.waiting_for, g.position.x,
				g.position.y, g.hole.state if g.hole != null and work else -1,
				g.hole.strokes.size() if g.hole != null else -1])
	return " ".join(parts)


## The day of `day_seed` on the fixture: one snapshot a step and every record. `speed` below
## 0 steps directly; else it runs frames of `frame` real seconds at that speed, with `t`'s
## numbers (null: data/guests.json's). `out_brain` gets the brain, for its frame figures.
func _day_log(day_seed: int, speed: float, frame: float = 1.0 / 60.0, t: GuestTuning = null,
		out_brain: Array = []) -> PackedStringArray:
	var brain := GuestBrain.new(GuestCourse.course(), day_seed, t if t != null else tuning, model)
	out_brain.append(brain)
	var out := PackedStringArray()
	brain.hole_finished.connect(func(g: Guest, r: Guest.HoleRecord) -> void:
		out.append("record %d hole %d score %d wait %d walk %.2f %d-%d" % [g.id, r.number, r.score,
				r.wait_s, r.walk_yd, r.start_s, r.end_s]))
	while not brain.day_over:
		if speed < 0.0:
			brain.step()
		elif brain.advance_real(frame, speed) == 0:
			continue
		out.append("%d %s" % [brain.second, _snapshot(brain)])
	return out


## Seconds any guest stood on a cart path tile during a pair's day.
func _path_steps(c: CourseData) -> int:
	var brain := GuestBrain.new(c, 4, tuning, model, [
		GuestSpawner.group(0, 0.0, [[10, 10, Guest.Taste.CASUAL, 61], [10, 10, Guest.Taste.CASUAL, 62]]),
	])
	var n := 0
	while not brain.day_over:
		brain.step()
		for g: Guest in brain.guests:
			var t := Vector2i(floori(g.position.x / 5.0), floori(g.position.y / 5.0))
			if g.is_walking() and c.get_surface(t.x, t.y) == Surface.Type.CART_PATH:
				n += 1
	return n
