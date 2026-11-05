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


## Every drawn cell of every layer, as [layer, cell, source, atlas, alternative].
func _layers(v: CourseView) -> Array:
	var layers: Array[TileMapLayer] = []
	for h: int in CourseData.MAX_HEIGHT + 1:
		layers.append(v.top_layer(h))
		layers.append(v.edge_layer(h))
		layers.append(v.land_layer(h))
		if h < CourseData.MAX_HEIGHT:
			layers.append(v.riser_layer(h))
	var out: Array = []
	for i: int in layers.size():
		var used: Array[Vector2i] = layers[i].get_used_cells()
		used.sort()
		for cell: Vector2i in used:
			out.append([i, cell, layers[i].get_cell_source_id(cell), layers[i].get_cell_atlas_coords(cell),
				layers[i].get_cell_alternative_tile(cell)])
	return out


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
