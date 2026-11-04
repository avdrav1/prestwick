extends GutTest
## E2-S17: the issue markers' hidden leader foot and the box distance (course/issue_marker.gd,
## course/course_view.gd), and the swing bar's idle redraw on resize (scenes/swing_bar.gd).


func _flat(ground: int = 2) -> CourseData:
	return CourseData.create(20, 20, Surface.Type.ROUGH, ground)


func _view(c: CourseData) -> CourseView:
	var v: CourseView = autofree(CourseView.new())
	v.show_course(c)
	return v


func _one(v: CourseView, cell: Vector2i) -> IssueMarker:
	v.show_issues({1: [CourseValidator.Issue.new(2, cell, "cup is on rough, not green")]})
	return v.issue_markers()[0]


# --- the hidden foot ---

func test_a_foot_on_flat_ground_is_not_hidden() -> void:
	var m := _one(_view(_flat()), Vector2i(8, 8))
	assert_false(m.foot_hidden, "nothing in front stands higher")


func test_a_higher_tile_in_front_hides_the_foot() -> void:
	for front: Vector2i in [Vector2i(9, 9), Vector2i(9, 8), Vector2i(8, 9)]:
		var c := _flat()
		c.set_tile(front.x, front.y, 3, Surface.Type.ROUGH)
		var m := _one(_view(c), Vector2i(8, 8))
		assert_true(m.foot_hidden, "a one-step rise at %s covers the foot" % front)


func test_a_far_hill_hides_the_foot_only_when_tall_enough() -> void:
	var c := _flat()
	c.set_tile(10, 10, 4, Surface.Type.ROUGH)
	assert_false(_one(_view(c), Vector2i(8, 8)).foot_hidden, "two rows ahead, two steps up is level with the foot")
	c.set_tile(10, 10, 5, Surface.Type.ROUGH)
	assert_true(_one(_view(c), Vector2i(8, 8)).foot_hidden, "three steps up two rows ahead covers it")


func test_a_higher_tile_behind_or_beside_does_not_hide_the_foot() -> void:
	for other: Vector2i in [Vector2i(7, 7), Vector2i(7, 8), Vector2i(8, 7), Vector2i(9, 7), Vector2i(7, 9)]:
		var c := _flat()
		c.set_tile(other.x, other.y, 7, Surface.Type.ROUGH)
		assert_false(_one(_view(c), Vector2i(8, 8)).foot_hidden, "%s is behind or level in depth with the foot" % other)


func test_an_edit_in_front_updates_the_foot() -> void:
	var c := _flat()
	var v := _view(c)
	var m := _one(v, Vector2i(8, 8))
	assert_false(m.foot_hidden)
	c.set_tile(9, 9, 3, Surface.Type.ROUGH)
	v.refresh_cell(Vector2i(9, 9))
	assert_true(m.foot_hidden, "raising the tile in front hides the foot")
	c.set_tile(9, 9, 2, Surface.Type.ROUGH)
	v.refresh_cell(Vector2i(9, 9))
	assert_false(m.foot_hidden, "and lowering it shows it again")


# --- the box distance ---

func _cluster() -> Array:
	var out: Array = []
	for x: int in range(6, 12):
		for y: int in range(6, 12):
			out.append(CourseValidator.Issue.new(3, Vector2i(x, y), "no path from tee to cup round water and oob"))
	return out


func test_the_max_stack_is_in_the_builder_tuning() -> void:
	var t := BuilderTuning.load_default()
	assert_gt(t.issue_box_max_stack, 0.0)
	assert_eq(_view(_flat()).issue_max_stack, t.issue_box_max_stack)


func test_the_max_side_is_in_the_builder_tuning() -> void:
	var t := BuilderTuning.load_default()
	assert_gt(t.issue_box_max_side, 0.0)
	assert_eq(_view(_flat()).issue_max_side, t.issue_box_max_side)


func _assert_near_and_apart(v: CourseView, scale: float) -> void:
	var rects: Array[Rect2] = v.issue_label_rects()
	var markers: Array[IssueMarker] = v.issue_markers()
	for i: int in rects.size():
		if markers[i].collapsed:
			assert_eq(rects[i], Rect2(), "a collapsed box %d has no rect" % i)
			continue
		assert_lte(markers[i].stack, v.issue_max_stack, "box %d is at most the max stack above its rest at %sx" % [i, scale])
		assert_lte(absf(markers[i].shift), v.issue_max_side, "box %d is at most the max side off centre at %sx" % [i, scale])
		var tile_y: float = markers[i].draw_point().y * scale
		assert_lte(tile_y - rects[i].end.y, markers[i].text_lift * scale + v.issue_max_stack + 0.01,
			"box %d bottom is within the set distance above its tile at %sx" % [i, scale])
		for j: int in range(i + 1, rects.size()):
			if not markers[j].collapsed:
				assert_false(rects[i].intersects(rects[j]), "boxes %d and %d overlap at %sx" % [i, j, scale])


func test_many_faults_close_together_stay_near_their_tiles_and_never_overlap() -> void:
	var v := _view(_flat())
	v.show_issues({1: _cluster()})
	assert_eq(v.issue_markers().size(), 36)
	for scale: float in [1.0, 0.5, 2.0]:
		v.layout_issue_labels(scale)
		_assert_near_and_apart(v, scale)
		var shown: int = 0
		for m: IssueMarker in v.issue_markers():
			if not m.collapsed:
				shown += 1
		assert_gt(shown, 0, "some boxes still show at %sx" % scale)
		assert_lt(shown, 36, "a cluster this dense collapses some boxes at %sx" % scale)


func test_a_dense_cluster_lays_out_quickly() -> void:
	var c := CourseData.create(40, 40, Surface.Type.ROUGH, 2)
	var v := _view(c)
	var issues: Array = []
	for x: int in range(5, 19):
		for y: int in range(5, 19):
			issues.append(CourseValidator.Issue.new(3, Vector2i(x, y), "no path from tee to cup round water and oob"))
	v.show_issues({1: issues})
	assert_eq(v.issue_markers().size(), 196)
	for scale: float in [1.0, 0.5, 2.0]:
		var ms: float = BestTime.ms(func() -> void: v.layout_issue_labels(scale))
		assert_lt(ms, 100.0, "196 faults lay out in under 100 ms at %sx (fastest of %d took %.1f ms)" % [scale, BestTime.RUNS, ms])
		_assert_near_and_apart(v, scale)


func test_a_collapsed_box_draws_its_badge_only_and_comes_back_when_there_is_room() -> void:
	var v := _view(_flat())
	v.show_issues({1: _cluster()})
	var hidden: IssueMarker = null
	for m: IssueMarker in v.issue_markers():
		if m.collapsed:
			hidden = m
			break
	assert_not_null(hidden, "the cluster collapses at least one box")
	v.show_issues({1: [CourseValidator.Issue.new(3, hidden.cell, "no path")]})
	assert_false(v.issue_markers()[0].collapsed, "alone, the same fault shows its box")


func test_a_lone_box_stays_centred_over_its_tile() -> void:
	var v := _view(_flat())
	var m := _one(v, Vector2i(8, 8))
	assert_eq(m.stack, 0.0)
	assert_eq(m.shift, 0.0)
	assert_false(m.collapsed)


# --- the swing bar ---

func test_the_swing_bar_redraws_on_resize_while_idle() -> void:
	var bar := SwingBar.new()
	bar.swing = Swing.new(SwingTuning.load_default())
	add_child_autofree(bar)
	await wait_physics_frames(3)
	assert_false(bar.swing.in_progress(), "idle")
	var draws: Array[int] = [0]
	bar.draw.connect(func() -> void: draws[0] += 1)
	await wait_physics_frames(3)
	assert_eq(draws[0], 0, "an idle bar does not redraw on its own")
	bar.size = bar.size + Vector2(40, 0)
	await wait_physics_frames(3)
	assert_gt(draws[0], 0, "a resize redraws it")
