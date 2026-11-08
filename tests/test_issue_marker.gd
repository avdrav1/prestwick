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


func test_a_higher_tile_in_front_hides_the_foot_only_once_its_slope_covers_it() -> void:
	# E3-S59 (D50): the ground in front is a slope, not a wall, so the tile straight in front
	# must climb past the line of sight to the foot (one step up every half tile of depth).
	var c := _flat()
	c.set_tile(9, 9, 3, Surface.Type.ROUGH)
	assert_false(_one(_view(c), Vector2i(8, 8)).foot_hidden, "a one-step rise in front: its slope shows the foot")
	c.set_tile(9, 9, 5, Surface.Type.ROUGH)
	assert_true(_one(_view(c), Vector2i(8, 8)).foot_hidden, "three steps up in front covers it")
	for beside: Vector2i in [Vector2i(9, 8), Vector2i(8, 9)]:
		var b := _flat()
		b.set_tile(beside.x, beside.y, 4, Surface.Type.ROUGH)
		assert_false(_one(_view(b), Vector2i(8, 8)).foot_hidden, "%s beside the line of sight stays under it" % beside)
		b.set_tile(beside.x, beside.y, 7, Surface.Type.ROUGH)
		assert_true(_one(_view(b), Vector2i(8, 8)).foot_hidden, "%s at 7 lifts the ground in front past it" % beside)


func test_a_far_hill_hides_the_foot_only_when_tall_enough() -> void:
	var c := _flat()
	c.set_tile(10, 10, 5, Surface.Type.ROUGH)
	assert_false(_one(_view(c), Vector2i(8, 8)).foot_hidden, "two rows ahead, three steps up stays under the sight line")
	c.set_tile(10, 10, 7, Surface.Type.ROUGH)
	assert_true(_one(_view(c), Vector2i(8, 8)).foot_hidden, "five steps up two rows ahead covers it")


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
	c.set_tile(9, 9, 5, Surface.Type.ROUGH)
	v.refresh_cell(Vector2i(9, 9))
	assert_true(m.foot_hidden, "raising the tile in front hides the foot")
	c.set_tile(9, 9, 2, Surface.Type.ROUGH)
	v.refresh_cell(Vector2i(9, 9))
	assert_false(m.foot_hidden, "and lowering it shows it again")


func test_the_diamond_lies_on_the_ground_round_its_tile() -> void:
	var c := _flat()
	c.set_tile(9, 8, 5, Surface.Type.ROUGH)
	var m := _one(_view(c), Vector2i(8, 8))
	var ring := TerrainMesh.ring(c, Vector2i(8, 8))
	assert_gt(ring.size(), 8)
	var lifted := 0
	for p: Vector3 in ring:
		assert_almost_eq(p.z, TerrainMesh.ground_in(c, Vector2i(8, 8), Vector2(p.x, p.y)), 0.0001)
		if p.z > 2.0 + 0.01:
			lifted += 1
	assert_gt(lifted, 0, "its edge toward the raised tile climbs the slope")
	assert_eq(m._outer.size(), ring.size(), "drawn through the ring")
	assert_almost_eq(m._outer[0] + m.position, Iso.point_to_screen(ring[0]), Vector2.ONE * 0.001)


# --- a batch of tiles (E3-S16) ---

## Faults on a ring of tiles round (10, 10) and on (10, 10) itself, so a batch edits tiles in
## front of some boxes, behind others, and under one.
func _ring_issues() -> Dictionary:
	var out: Array = []
	for cell: Vector2i in [Vector2i(10, 10), Vector2i(8, 8), Vector2i(12, 9), Vector2i(9, 13), Vector2i(14, 14)]:
		out.append(CourseValidator.Issue.new(2, cell, "cup is on rough, not green"))
	return {1: out}


## A batch of writes: a hill in front of (8, 8), a trench under (10, 10), a ridge behind
## (14, 14), a surface change and a tile written twice in one batch.
func _batch_edit(c: CourseData) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for spec: Array in [[Vector2i(9, 9), 5], [Vector2i(9, 8), 4], [Vector2i(10, 10), 0],
			[Vector2i(11, 10), 0], [Vector2i(13, 13), 1], [Vector2i(15, 15), 7], [Vector2i(10, 14), 6],
			[Vector2i(9, 9), 6], [Vector2i(0, 0), 7], [Vector2i(19, 19), 3]]:
		var cell: Vector2i = spec[0]
		c.set_tile(cell.x, cell.y, spec[1], Surface.Type.FAIRWAY)
		cells.append(cell)
	return cells


func _snapshot(v: CourseView) -> Array:
	v.layout_issue_labels(1.0)
	var out: Array = []
	for m: IssueMarker in v.issue_markers():
		out.append([m.cell, m.ground, m.position, m.label.position, m.foot_hidden, m.collapsed, m.stack, m.shift])
	out.append(v.issue_label_rects())
	for m: HoleMarker in v.hole_markers():
		out.append([m.cell, m.position])
	return out


## What the view's ground draws (CourseView.terrain_digest), to compare two views.
func _layers(v: CourseView) -> Array:
	return v.terrain_digest()


func _holed(ground: int = 2) -> CourseData:
	var c := _flat(ground)
	var h := HoleData.new()
	h.number = 1
	h.tee = Vector2i(10, 14)
	h.cup = Vector2i(10, 10)
	c.set_holes([h])
	return c


func test_a_batched_refresh_leaves_the_boxes_where_a_per_tile_refresh_would() -> void:
	var c1 := _holed()
	var c2 := _holed()
	var per_tile := _view(c1)
	var batched := _view(c2)
	per_tile.show_issues(_ring_issues())
	batched.show_issues(_ring_issues())
	var cells: Array[Vector2i] = _batch_edit(c1)
	_batch_edit(c2)
	for cell: Vector2i in cells:
		per_tile.refresh_cell(cell)
	batched.refresh_cells(cells)
	var hidden: int = 0
	for m: IssueMarker in batched.issue_markers():
		hidden += 1 if m.foot_hidden else 0
	assert_gt(hidden, 0, "the batch hides at least one foot, so the boxes were tested")
	assert_eq(batched.issue_markers()[0].ground, 0, "the box on the trench stands on its new top")
	assert_eq(_snapshot(batched), _snapshot(per_tile), "boxes, feet and markers match a per-tile refresh")
	assert_eq(_layers(batched), _layers(per_tile), "the tiles drawn match a per-tile refresh")


func test_a_batched_or_per_tile_refresh_draws_what_a_fresh_draw_would() -> void:
	var c := _holed()
	var batched := _view(c)
	var per_tile := _view(c)
	for round: int in 3:
		var cells: Array[Vector2i] = _batch_edit(c)
		if round == 1:
			for cell: Vector2i in cells:
				c.set_tile(cell.x, cell.y, 2, Surface.Type.ROUGH)
		batched.refresh_cells(cells)
		for cell: Vector2i in cells:
			per_tile.refresh_cell(cell)
	var fresh: Array = _layers(_view(c))
	assert_eq(_layers(batched), fresh, "a batch leaves nothing on the layers its tiles left")
	assert_eq(_layers(per_tile), fresh, "so does a refresh per tile, neighbours written in the same edit")


## E3-S16 review: a surface-only change sets just the tile's top. On hilly land with an unowned
## parcel, surface paints over risers, cues and the land hatch, next to and on tiles whose
## height moved in the same batch, and repainted alone in later batches, draw what a fresh
## draw would.
func test_a_surface_only_batch_draws_what_a_fresh_draw_would() -> void:
	var c := CourseData.create(32, 20, Surface.Type.ROUGH, 2)
	c.set_parcel_owned(Vector2i(1, 0), false)
	for y: int in 20:
		for x: int in 32:
			c.set_tile(x, y, (x * 3 + y * 5) % 8, Surface.Type.ROUGH)
	var v := _view(c)
	for round: int in 3:
		var cells: Array[Vector2i] = []
		for y: int in range(4, 12):
			for x: int in range(10, 22):
				var s: Surface.Type = [Surface.Type.FAIRWAY, Surface.Type.BUNKER, Surface.Type.ROUGH][(x + y + round) % 3]
				var h: int = c.get_height(x, y)
				if round == 1 and (x + y) % 7 == 0:
					h = (h + 3) % 8
				c.set_tile(x, y, h, s)
				cells.append(Vector2i(x, y))
		v.refresh_cells(cells)
	assert_eq(_layers(v), _layers(_view(c)), "surface-only tiles beside moved heights match a fresh draw")


func test_a_brush_edit_reaches_the_view_as_one_batch() -> void:
	var c := _holed()
	var v := _view(c)
	v.show_issues(_ring_issues())
	var b := CourseBuilder.new(c)
	var calls: Array[int] = [0]
	var count := func(_cells: Array[Vector2i]) -> void: calls[0] += 1
	b.tiles_changed.connect(count)
	b.tiles_changed.connect(v.refresh_cells)
	b.raise(Vector2i(10, 9), 3)
	assert_eq(calls[0], 1, "a 3 x 3 brush is one batch")
	# Three steps up, the plateau's slope in front of (8, 8) climbs past its line of sight.
	b.raise(Vector2i(10, 9), 3)
	b.raise(Vector2i(10, 9), 3)
	assert_eq(calls[0], 3, "one batch a raise")
	assert_true(v.issue_markers().any(func(m: IssueMarker) -> bool: return m.foot_hidden),
		"the raised brush covers a foot")


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
	if BestTime.later(self):
		return
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
		assert_lt(ms, 100.0, "196 faults lay out in under 100 ms at %sx (fastest of %d took %.1f ms)" % [scale, BestTime.RUNS, ms] + BestTime.load_note())
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


# --- labels kept apart (E3-S40) ---

const NineHoles := preload("res://tests/fixtures/nine_holes.gd")

## nine_holes with every hole failing two rules (its cup on rough, its par wrong), as E3-S2's
## frame figures: nine boxes of two lines at the cups. Returns [course, builder].
func _nine_failing() -> Array:
	var c := NineHoles.land()
	var b := CourseBuilder.new(c)
	NineHoles.build(b)
	for spec: Array in NineHoles.HOLES:
		b.paint(spec[3], Surface.Type.ROUGH, 1)
		b.set_par(spec[0], 5 if spec[1] != 5 else 3)
	return [c, b]


## Every label drawn at `scale` in screen px: [kind, rect] for each shown issue box ("box"), each
## tee's hole number ("tee") and each issue badge ("badge").
func _labels(v: CourseView, scale: float) -> Array:
	var out: Array = []
	for r: Rect2 in v.issue_label_rects():
		if r.size != Vector2.ZERO:
			out.append(["box", r])
	for hm: HoleMarker in v.hole_markers():
		var r: Rect2 = hm.label_rect(scale)
		if r.size != Vector2.ZERO:
			r.position += hm.draw_point() * scale
			out.append(["tee", r])
	for m: IssueMarker in v.issue_markers():
		var r: Rect2 = m.badge_rect(scale)
		r.position += m.draw_point() * scale
		out.append(["badge", r])
	return out


func test_no_two_labels_overlap_on_nine_holes_with_every_hole_failing() -> void:
	var cb: Array = _nine_failing()
	var c: CourseData = cb[0]
	var b: CourseBuilder = cb[1]
	var v := _view(c)
	v.show_issues(b.issues, b.slot_issues())
	assert_eq(v.issue_markers().size(), 9, "a box at each cup")
	for scale: float in [0.175, 0.5, 1.0]:
		v.layout_hole_labels(scale)
		v.layout_issue_labels(scale)
		var labels: Array = _labels(v, scale)
		var bad: Array = []
		for i: int in labels.size():
			for j: int in range(i + 1, labels.size()):
				if (labels[i][1] as Rect2).intersects(labels[j][1]):
					bad.append("%s %d and %s %d" % [labels[i][0], i, labels[j][0], j])
		assert_eq(bad, [], "no two labels overlap at %sx" % scale)
		_assert_near_and_apart(v, scale)
## A course whose hole 2 is in two slots (2a and 2b), each tee six tiles apart.
func _shared_number() -> CourseData:
	var c := CourseData.create(40, 20, Surface.Type.ROUGH, 2)
	var b := CourseBuilder.new(c)
	for n: int in [1, 2]:
		b.place_tee(n, Vector2i(6, n * 6), 3)
		b.place_cup(n, Vector2i(30, n * 6))
	var data: Dictionary = c.to_dict()
	(data["holes"] as Array)[0]["number"] = 2
	var errors: Array[String] = []
	var loaded := CourseSave.from_json(JSON.stringify(data), errors)
	assert_not_null(loaded, "a shared number loads: %s" % [errors])
	return loaded


func test_a_badge_on_a_tee_clears_its_label_at_every_zoom() -> void:
	var c := _shared_number()
	var b := CourseBuilder.new(c)
	var v := _view(c)
	v.show_issues(b.issues, b.slot_issues())
	var tees := 0
	for scale: float in [0.175, 0.5, 1.0, 2.0]:
		v.layout_hole_labels(scale)
		v.layout_issue_labels(scale)
		for hm: HoleMarker in v.hole_markers():
			if hm.kind != HoleMarker.Kind.TEE:
				continue
			for m: IssueMarker in v.issue_markers():
				if m.cell != hm.cell:
					continue
				tees += 1
				assert_true(m.rules.has(1), "the rule-1 issue stands on a tee")
				assert_false(m.badge_rect(scale).intersects(hm.label_rect(scale)),
						"the badge clears %s's label at %sx" % [hm.label_text(), scale])
	assert_gt(tees, 0, "a rule-1 badge stands on a tee")


func test_a_tee_label_behind_a_hill_rises_over_the_terrain_at_half_zoom() -> void:
	var c := _flat()
	var b := CourseBuilder.new(c)
	b.place_tee(1, Vector2i(8, 8), 3)
	b.place_cup(1, Vector2i(8, 16))
	var v := _view(c)
	v.layout_hole_labels(0.5)
	var tee := v.hole_marker(1, HoleMarker.Kind.TEE)
	assert_false(tee.label_lifted, "on flat ground the number sorts with the terrain")
	assert_eq(tee.label.z_index, 0)
	# A hill just in front, five steps up, rises over the number on screen.
	var cells: Array[Vector2i] = []
	for y: int in range(9, 12):
		for x: int in range(9, 12):
			c.set_tile(x, y, 7, Surface.Type.ROUGH)
			cells.append(Vector2i(x, y))
	v.refresh_cells(cells)
	v.layout_hole_labels(0.5)
	assert_true(tee.label_covered(c, 0.5), "the hill covers the number")
	assert_true(tee.label_lifted, "so it rises over the terrain")
	assert_gt(tee.label.z_index, 0)


## E3-S40: a framed hole's box keeps off its line of play where it can.
func test_a_framed_holes_box_sits_off_its_line() -> void:
	var c := CourseData.create(60, 20, Surface.Type.ROUGH, 2)
	var b := CourseBuilder.new(c)
	b.place_tee(1, Vector2i(4, 10), 4)
	b.place_cup(1, Vector2i(50, 10))
	var v := _view(c)
	v.show_play_lines(b.slot_lines())
	# A fault on the line, half way along it.
	v.show_issues({1: [CourseValidator.Issue.new(3, Vector2i(30, 10), "no path from tee to cup")]})
	v.framed_slot = 0
	var line: Array[Rect2] = v.framed_line_rects(0.5)
	assert_gt(line.size(), 0)
	v.framed_slot = -1
	v.layout_issue_labels(0.5)
	var free: Rect2 = v.issue_label_rects()[0]
	var crossed := false
	for r: Rect2 in line:
		crossed = crossed or r.intersects(free)
	assert_true(crossed, "unframed, the box stands over the line")
	v.framed_slot = 0
	v.layout_issue_labels(0.5)
	var off: Rect2 = v.issue_label_rects()[0]
	for r: Rect2 in line:
		assert_false(r.intersects(off), "framed, it keeps off the line")
	assert_false(v.issue_markers()[0].collapsed, "and still shows")


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


# --- E3-S66: the tee's number clear of the ball on it ---

## The player's ball resting on each tee of tests/fixtures/guest_course.gd in Play (holes 1 and 2
## run east, hole 3 west; hole 2's tee has a rise by its blocks): at every zoom step (D45), the
## tee's number box and the ball's (outline included) do not overlap, and the number stands
## beside the blocks, on the side away from the cup, so the aim line leaves it clear.
func test_a_tees_number_stands_clear_of_the_ball_resting_on_it_at_every_zoom() -> void:
	var guest_course: GDScript = load("res://tests/fixtures/guest_course.gd")
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	var c: CourseData = guest_course.call("course")
	var b := CourseBuilder.new(c)
	b.paint(Vector2i(23, 7), Surface.Type.ROUGH, 5)
	b.paint(Vector2i(25, 5), Surface.Type.ROUGH, 5)
	m.show_course(c)
	m.camera.view_size_override = Vector2(1280, 720)
	for number: int in [1, 2, 3]:
		m.play_hole(number)
		m.set_process(false)
		var h: HoleData = m.swing_control.hole
		var tee: HoleMarker = m.course_view.hole_marker(number, HoleMarker.Kind.TEE)
		var shot: ShotView = m.shot_view
		assert_not_null(shot.ball, "hole %d: the ball is on the tee" % number)
		var cup_dx: float = Iso.tile_to_screen(Vector2(h.cup), 0.0).x - Iso.tile_to_screen(Vector2(h.tee), 0.0).x
		assert_eq(tee.label_side, -1.0 if cup_dx > 0.0 else 1.0, "hole %d: the side away from its cup" % number)
		for z: float in m.camera.tuning.zoom_levels:
			m.course_view.layout_hole_labels(z)
			var label: Rect2 = tee.label_rect(z)
			label.position += tee.draw_point() * z
			var k: float = HazardCue.screen_k(z)
			var r: float = (shot.ball_draw_radius(k) + shot.ball_outline_width(k)) * z
			var at: Vector2 = shot.ball_screen() * z
			var ball := Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0)
			assert_false(label.intersects(ball),
					"hole %d at %.3fx: the number %s clears the ball %s" % [number, z, label, ball])
			var reach: float = (tee.tee_block_offset + tee.tee_block_radius) * tee.shape_scale * z
			var x0: float = tee.draw_point().x * z
			if tee.label_side > 0.0:
				assert_gt(label.position.x, x0 + reach, "hole %d at %.3fx: beside the right-hand block" % [number, z])
			else:
				assert_lt(label.end.x, x0 - reach, "hole %d at %.3fx: beside the left-hand block" % [number, z])
			assert_true(label.get_center().y > ball.position.y - label.size.y and label.get_center().y < ball.end.y + label.size.y,
					"hole %d at %.3fx: and level with the tee" % [number, z])
