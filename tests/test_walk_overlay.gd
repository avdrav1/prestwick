extends GutTest
## E12-S1 (D68): make cart paths obvious. With the Cart path brush in hand Build draws every walk
## a round takes, red when it would draw a walk complaint (with the reason), green when a path
## serves it; the complaint names the same reason (GuestWalk.why); laying path a walk can reach
## clears that walk's complaints; hidden in Play and idle without the brush (D52).

const GuestCourse := preload("res://tests/fixtures/guest_course.gd")

## far_next_tee's walk: hole 1's cup (20, 6) to hole 2's tee (70, 30), 277 yd.
const PATH_FROM := Vector2i(21, 8)
## A path that stops at (60, 24): its end tile's centre 58.3 yd from hole 2's tee, 18.3 yd past
## the 40 yd reach, so "19 yd short".
const PATH_SHORT_END := Vector2i(60, 24)
const PATH_FULL_END := Vector2i(69, 28)

var _b: CourseBuilder
var _c: CourseData
var _t: BuildTool
var tuning: GuestTuning


func before_all() -> void:
	tuning = GuestTuning.load_default()


func before_each() -> void:
	_b = _far_builder()
	_c = _b.course
	_t = BuildTool.new()
	_t.builder = _b
	add_child_autofree(_t)


## far_next_tee's course with no path, as a builder (to lay path through).
func _far_builder() -> CourseBuilder:
	var b := CourseBuilder.new(GuestCourse.far_next_tee(false))
	return b


## Lays cart path on the grid line from `a` to `b` through the builder, reopening any hole it
## closed (as GuestCourse.far_next_tee does). Returns the tiles laid.
func _lay(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	_b.begin_stroke()
	for cell: Vector2i in BuildTool.grid_line(a, b):
		_b.paint(cell, Surface.Type.CART_PATH, 1)
		cells.append(cell)
	_b.end_stroke()
	for h: HoleData in _c.holes:
		if not h.open:
			_b.open_hole(h.number)
	return cells


func _brush() -> void:
	_t.select_surface(Surface.Type.CART_PATH)
	_t.walks.refresh()


# --- the overlay ---

func test_the_overlay_shows_only_with_the_cart_path_brush_and_never_in_play() -> void:
	assert_false(_t.walks.visible, "a new tool holds the fairway brush: no walks")
	assert_false(_t.walks.is_processing(), "and the overlay costs no frame time")
	_brush()
	assert_true(_t.walks.visible, "the Cart path brush shows the walks")
	assert_true(_t.walks.is_processing())
	assert_eq(_t.walks.walks.size(), 2, "the clubhouse to the 1st tee, the 1st green to the 2nd tee")
	_t.select_surface(Surface.Type.FAIRWAY)
	assert_false(_t.walks.visible, "another brush hides them")
	assert_false(_t.walks.is_processing())
	_brush()
	_t.select_tool(BuildTool.Tool.RAISE)
	assert_false(_t.walks.visible, "another tool hides them")
	_t.select_surface(Surface.Type.CART_PATH)
	_t.active = false
	assert_false(_t.walks.visible, "Play hides them")
	assert_false(_t.walks.is_processing(), "and nothing runs in Play")
	_t.active = true
	assert_true(_t.walks.visible, "back in Build with the brush in hand")


func test_a_walk_with_no_path_is_red_and_says_so() -> void:
	_brush()
	var w: Dictionary = _t.walks.walk_to(2)
	assert_eq(int(w.state), WalkOverlay.State.LONG, "277 yd over rough is long")
	assert_eq(w.detail, "no cart path")
	assert_string_starts_with(w.label as String, "6.9 s")
	var first: Dictionary = _t.walks.walk_to(1)
	assert_eq(int(first.state), WalkOverlay.State.QUICK, "the clubhouse stands beside the 1st tee")
	assert_eq(first.detail, "")


func test_a_path_that_stops_short_of_the_tee_shows_the_gap_and_the_complaint_names_it() -> void:
	_lay(PATH_FROM, PATH_SHORT_END)
	_brush()
	var w: Dictionary = _t.walks.walk_to(2)
	assert_eq(int(w.state), WalkOverlay.State.LONG)
	assert_eq(w.detail, "path stops 19 yd short of the 2nd tee")
	assert_eq((w.reason as GuestWalk.Reason).near_tile, PATH_SHORT_END, "where the path stops")
	assert_eq(_t.walks.gap_points(w).size(), 2, "the gap is drawn from there to the tee")
	assert_true(_t.walks.gap_points(_t.walks.walk_to(1)).is_empty(), "a short walk has no gap")
	# The guests say the same thing: every long walk to hole 2 is a complaint naming the gap.
	var brain := GuestBrain.new(_c, 5, tuning)
	brain.run_day()
	var walks := 0
	for g: Guest in brain.guests:
		for r: Guest.HoleRecord in g.records:
			if r.number != 2:
				continue
			walks += 1
			assert_false(r.reaction.passed[GuestReaction.Check.WALK], "the walk is long")
			assert_eq(r.reaction.walk_why(), w.detail, "the complaint's reason is the overlay's")
			assert_string_contains(r.reaction.text, "(277 yd, path stops 19 yd short of the 2nd tee)."
					if r.reaction.lead_check() != GuestReaction.Check.WALK
					else "a long walk from the 1st green to the 2nd tee, 277 yd: path stops 19 yd short of the 2nd tee.")
	assert_gt(walks, 5, "guests played hole 2")


func test_extending_the_path_turns_the_walk_green() -> void:
	_lay(PATH_FROM, PATH_SHORT_END)
	_brush()
	assert_eq(int(_t.walks.walk_to(2).state), WalkOverlay.State.LONG)
	_lay(PATH_SHORT_END, PATH_FULL_END)
	_t.walks.refresh()
	var w: Dictionary = _t.walks.walk_to(2)
	assert_eq(int(w.state), WalkOverlay.State.SERVED, "the path now reaches the tee")
	assert_string_ends_with(w.label as String, "s on the path")
	assert_eq(w.detail, "")
	assert_gt((w.points as PackedVector2Array).size(), 2, "drawn along the path")
	assert_false(_t.walks.route_points(w).is_empty(), "on the ground")


func test_a_path_cut_off_from_the_green_is_named_at_the_green() -> void:
	# A path by the tee only: it stops short of the 1st green.
	_lay(Vector2i(50, 20), PATH_FULL_END)
	_brush()
	assert_string_starts_with(_t.walks.walk_to(2).detail as String, "path stops ")
	assert_string_ends_with(_t.walks.walk_to(2).detail as String, " short of the 1st green")


func test_the_overlay_measures_on_a_change_not_per_frame() -> void:
	_brush()
	var n: int = _t.walks.measure_count
	for i: int in 5:
		assert_false(_t.walks.refresh(), "nothing changed: nothing measured")
	assert_eq(_t.walks.measure_count, n)
	_lay(PATH_FROM, PATH_SHORT_END)
	assert_true(_t.walks.refresh(), "a path laid measures again")
	assert_eq(_t.walks.measure_count, n + 1)


# --- clearing (E3-S17's, the walk check only) ---

## A reaction about hole `hole` that failed its walk (a walk complaint) or not (a pace complaint).
func _complaint(hole: int, walk: bool) -> GuestReaction:
	var r := GuestReaction.new()
	r.hole_number = hole
	r.kind = GuestReaction.Kind.COMPLAINT
	r.passed[GuestReaction.Check.WALK] = not walk
	r.passed[GuestReaction.Check.PACE] = walk
	r.text = "Hole %d: %s." % [hole, "a long walk" if walk else "slow"]
	return r


func test_laying_path_a_walk_can_reach_clears_its_walk_complaints_only() -> void:
	_lay(PATH_FROM, PATH_SHORT_END)
	var feed := ReactionFeed.new(50, 100)
	feed.push(_complaint(2, true), 1, 10, 1)
	feed.push(_complaint(2, false), 1, 11, 1)
	feed.push(_complaint(1, true), 1, 12, 0)
	assert_eq(feed.slot_tallies(_c), {0: Vector2i(0, 1), 1: Vector2i(0, 2)})
	var cells := _lay(PATH_SHORT_END, PATH_FULL_END)
	var cleared := feed.walks_edited(_c, cells, tuning)
	assert_eq(cleared, [1] as Array[int], "the walk to hole 2's tee reaches the new path")
	assert_eq(feed.slot_tallies(_c), {0: Vector2i(0, 1), 1: Vector2i(0, 1)},
			"hole 2 keeps its pace complaint; hole 1's walk is out of reach")
	assert_true(feed.entries[0].edited, "the cleared line is dimmed")
	assert_false(feed.entries[1].edited)
	assert_false(feed.entries[2].edited)
	# Path far from any walk clears nothing.
	feed.push(_complaint(2, true), 1, 20, 1)
	assert_eq(feed.walks_edited(_c, _lay(Vector2i(40, 38), Vector2i(50, 38)), tuning),
			[] as Array[int], "a path no walk can reach")
	assert_eq(feed.slot_tallies(_c)[1], Vector2i(0, 2))


func test_taking_up_path_a_walk_uses_clears_its_complaints_too() -> void:
	_lay(PATH_FROM, PATH_FULL_END)
	var feed := ReactionFeed.new(50, 100)
	feed.push(_complaint(2, true), 1, 10, 1)
	# Take up one tile in the middle of the path: the piece by the green still touches it.
	var mid := Vector2i(40, 16)
	assert_eq(_c.get_surface(mid.x, mid.y), Surface.Type.CART_PATH, "the path runs over %s" % mid)
	_b.begin_stroke()
	_b.paint(mid, Surface.Type.ROUGH, 1)
	_b.end_stroke()
	assert_eq(feed.walks_edited(_c, [mid] as Array[Vector2i], tuning), [1] as Array[int])
	assert_eq(feed.slot_tallies(_c), {})


func test_the_sim_clears_walk_complaints_when_watched_path_changes() -> void:
	_lay(PATH_FROM, PATH_SHORT_END)
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.watch(_b)
	# Three tiles more on the path's end, outside every hole's footprint: hole 2's walk complaint
	# goes, its pace complaint stays.
	sim.feed.push(_complaint(2, true), 1, 8, 1)
	sim.feed.push(_complaint(2, false), 1, 9, 1)
	_lay(PATH_SHORT_END + Vector2i(1, 0), PATH_SHORT_END + Vector2i(3, 1))
	sim._flush_cells()
	assert_eq(sim.feed.slot_tallies(_c), {1: Vector2i(0, 1)}, "the walk complaint alone is cleared")
	sim.feed.clear()
	sim.feed.push(_complaint(2, true), 1, 10, 1)
	sim.feed.push(_complaint(1, false), 1, 11, 0)
	# Laid up to beside hole 2's tee (its footprint too, so E3-S17 would clear the hole whole):
	# the walk complaint is gone, hole 1's pace complaint stays.
	_lay(PATH_SHORT_END, PATH_FULL_END)
	sim._flush_cells()
	assert_eq(sim.feed.slot_tallies(_c), {0: Vector2i(0, 1)}, "the walk complaint is cleared")
	assert_true(sim.feed.entries[0].edited, "and its line dimmed")
	# Fairway painted away from every hole is no path edit: nothing is cleared.
	sim.feed.push(_complaint(2, true), 1, 12, 1)
	_b.begin_stroke()
	_b.paint(Vector2i(30, 36), Surface.Type.FAIRWAY, 1)
	_b.end_stroke()
	sim._flush_cells()
	assert_eq(sim.feed.slot_tallies(_c), {0: Vector2i(0, 1), 1: Vector2i(0, 1)})


## A guest that walked to hole 2's tee before the path reached it, its verdict still to come,
## gives its walk complaint uncounted: the walk it judges is gone.
func test_a_walk_judged_before_the_path_edit_counts_for_nothing() -> void:
	_lay(PATH_FROM, PATH_SHORT_END)
	var sim := GuestSim.new()
	add_child_autofree(sim)
	sim.watch(_b)
	sim.set_process(false)
	sim.start(_c, 5)
	sim._new_day(1)
	# Run until a group stands on hole 2, teed off from its long walk.
	var on_two: Array[GuestHole] = []
	while on_two.is_empty() and not sim.brain.day_over:
		sim.brain.step()
		on_two = sim.brain.walked_to(1)
	assert_false(on_two.is_empty(), "a group tees off on hole 2")
	_lay(PATH_SHORT_END, PATH_FULL_END)
	sim._flush_cells()
	var before := sim.feed.recent.size()
	var players := on_two.size()
	while not sim.brain.day_over and sim.feed.recent.size() < before + players:
		sim.brain.step()
	var uncounted := 0
	for i: int in range(before, sim.feed.recent.size()):
		var r: GuestReaction = sim.feed.recent[i]
		if r.hole_number == 2 and not r.passed[GuestReaction.Check.WALK]:
			assert_eq(sim.feed.recent_slots[i], ReactionFeed.CLEARED, "the old walk counts for nothing")
			uncounted += 1
	assert_gt(uncounted, 0, "its walk complaints came in uncounted")
