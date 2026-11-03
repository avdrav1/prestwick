extends GutTest
## E1-S5: paint terrain through course/builder.gd, the only writer. Surface palette for the
## 9 surfaces (`oob` joined in E2-S3, D9), raise and lower, brush 1/3/5, undo stack, heights clamp at 0 and 7, and the
## tile under the cursor is picked correctly on raised ground (TilePicker).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _flat(size: int = 10, h: int = 0) -> CourseData:
	return CourseData.create(size, size, Surface.Type.ROUGH, h)


# --- tuning ---

func test_brush_sizes_come_from_the_resource() -> void:
	var t := BuilderTuning.load_default()
	assert_not_null(t)
	assert_eq(t.brush_sizes, PackedInt32Array([1, 3, 5]), "docs/design.md: brush sizes 1, 3, 5")
	assert_gte(t.undo_limit, 50, "50 edits must be undoable")


# --- paint ---

func test_paint_brush_1_3_5_covers_a_centered_square() -> void:
	for size: int in [1, 3, 5]:
		var c := _flat()
		var b := CourseBuilder.new(c)
		assert_true(b.paint(Vector2i(5, 5), Surface.Type.GREEN, size))
		var painted: int = 0
		for y: int in c.height:
			for x: int in c.width:
				if c.get_surface(x, y) == Surface.Type.GREEN:
					painted += 1
					assert_true(absi(x - 5) <= size / 2 and absi(y - 5) <= size / 2, "(%d, %d) inside brush %d" % [x, y, size])
		assert_eq(painted, size * size, "brush %d" % size)


func test_paint_keeps_heights_and_clips_at_the_map_edge() -> void:
	var c := _flat(10, 3)
	var b := CourseBuilder.new(c)
	b.paint(Vector2i(0, 0), Surface.Type.BUNKER, 5)
	assert_eq(c.get_surface(2, 2), Surface.Type.BUNKER)
	assert_eq(c.get_surface(3, 0), Surface.Type.ROUGH)
	assert_eq(c.get_height(1, 1), 3, "paint does not move ground")
	assert_eq(b.paint(Vector2i(-5, -5), Surface.Type.WATER, 3), false, "wholly off the map: nothing to do")


func test_every_palette_surface_paints() -> void:
	assert_eq(CourseBuilder.PALETTE.size(), Surface.COUNT, "every surface of docs/design.md, oob included (D9)")
	var c := _flat()
	var b := CourseBuilder.new(c)
	for n: int in CourseBuilder.PALETTE.size():
		var s: Surface.Type = CourseBuilder.PALETTE[n]
		b.paint(Vector2i(n, 0), s, 1)
		assert_eq(c.get_surface(n, 0), s, Surface.name_of(s))


func test_painting_the_same_surface_records_nothing() -> void:
	var b := CourseBuilder.new(_flat())
	assert_false(b.paint(Vector2i(2, 2), Surface.Type.ROUGH, 3))
	assert_eq(b.undo_depth(), 0)


# --- raise and lower ---

func test_raise_and_lower_one_step_per_click() -> void:
	var c := _flat(10, 2)
	var b := CourseBuilder.new(c)
	b.raise(Vector2i(4, 4), 3)
	assert_eq(c.get_height(4, 4), 3)
	assert_eq(c.get_height(3, 5), 3)
	assert_eq(c.get_height(6, 4), 2, "outside brush 3")
	b.lower(Vector2i(4, 4), 1)
	assert_eq(c.get_height(4, 4), 2)
	assert_eq(c.get_height(3, 3), 3)
	assert_eq(c.get_surface(4, 4), Surface.Type.ROUGH, "height tools keep the surface")


func test_heights_clamp_at_0_and_7() -> void:
	var c := _flat(6, 0)
	var b := CourseBuilder.new(c)
	for n: int in 12:
		b.raise(Vector2i(2, 2), 1)
	assert_eq(c.get_height(2, 2), CourseData.MAX_HEIGHT, "clamped at 7")
	assert_false(b.raise(Vector2i(2, 2), 1), "raising at 7 changes nothing")
	for n: int in 12:
		b.lower(Vector2i(2, 2), 1)
	assert_eq(c.get_height(2, 2), 0, "clamped at 0")
	assert_false(b.lower(Vector2i(2, 2), 1), "lowering at 0 changes nothing")
	assert_eq(b.undo_depth(), CourseData.MAX_HEIGHT * 2, "no-op clicks are not on the stack")


func test_brush_raise_on_mixed_heights_clamps_per_tile() -> void:
	var c := _flat(5, 6)
	c.set_tile(2, 2, 7, Surface.Type.GREEN)
	var b := CourseBuilder.new(c)
	assert_true(b.raise(Vector2i(2, 2), 3))
	assert_eq(c.get_height(2, 2), 7)
	assert_eq(c.get_height(1, 1), 7)
	b.undo()
	assert_eq(c.get_height(1, 1), 6)
	assert_eq(c.get_height(2, 2), 7)


# --- undo ---

func test_50_edits_then_50_undos_restore_the_hash() -> void:
	var c := HeightsFixture.build()
	var original: String = c.content_hash()
	var b := CourseBuilder.new(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 50
	var sizes := BuilderTuning.load_default().brush_sizes
	for n: int in 50:
		var at := Vector2i(rng.randi_range(0, c.width - 1), rng.randi_range(0, c.height - 1))
		var size: int = sizes[rng.randi_range(0, sizes.size() - 1)]
		var changed: bool
		match n % 3:
			0:
				var n_pal: int = CourseBuilder.PALETTE.size()
				var s: Surface.Type = CourseBuilder.PALETTE[rng.randi_range(0, n_pal - 1)]
				if s == c.get_surface(at.x, at.y):
					s = CourseBuilder.PALETTE[(CourseBuilder.PALETTE.find(s) + 1) % n_pal]
				changed = b.paint(at, s, size)
			1:
				changed = b.raise(at, size) if c.get_height(at.x, at.y) < CourseData.MAX_HEIGHT else b.lower(at, size)
			2:
				changed = b.lower(at, size) if c.get_height(at.x, at.y) > 0 else b.raise(at, size)
		assert_true(changed, "edit %d changes the course" % n)
	assert_eq(b.undo_depth(), 50)
	assert_ne(c.content_hash(), original, "the edits changed the course")
	for n: int in 50:
		assert_true(b.undo(), "undo %d" % n)
	assert_eq(c.content_hash(), original, "50 undos restore the original CourseData")
	assert_false(b.can_undo())
	assert_false(b.undo(), "empty stack")


func test_a_stroke_is_one_undo_and_lifts_each_tile_once() -> void:
	var c := _flat(10, 0)
	var original := c.content_hash()
	var b := CourseBuilder.new(c)
	b.begin_stroke()
	b.raise(Vector2i(2, 2), 1)
	b.raise(Vector2i(2, 2), 1)  # drag wobbles back over the same tile
	b.raise(Vector2i(3, 2), 1)
	b.end_stroke()
	assert_eq(c.get_height(2, 2), 1, "a drag lifts each tile once")
	assert_eq(c.get_height(3, 2), 1)
	b.begin_stroke()
	for x: int in 6:
		b.paint(Vector2i(x, 5), Surface.Type.CART_PATH, 1)
	b.end_stroke()
	assert_eq(b.undo_depth(), 2)
	b.undo()
	assert_eq(c.get_surface(3, 5), Surface.Type.ROUGH, "the whole drag undoes at once")
	b.undo()
	assert_eq(c.content_hash(), original)


func test_empty_stroke_records_nothing() -> void:
	var b := CourseBuilder.new(_flat())
	b.begin_stroke()
	b.end_stroke()
	assert_eq(b.undo_depth(), 0)


func test_undo_stack_drops_the_oldest_past_the_limit() -> void:
	var t := BuilderTuning.new()
	t.undo_limit = 3
	var c := _flat(6, 0)
	var b := CourseBuilder.new(c, t)
	for n: int in 5:
		b.raise(Vector2i(1, 1), 1)
	assert_eq(b.undo_depth(), 3)
	while b.undo():
		pass
	assert_eq(c.get_height(1, 1), 2, "the two oldest edits fell off the stack")


func test_tiles_changed_reports_every_written_tile() -> void:
	var b := CourseBuilder.new(_flat())
	var seen: Array = []
	b.tiles_changed.connect(func(cells: Array[Vector2i]) -> void: seen.append(cells.duplicate()))
	b.paint(Vector2i(0, 0), Surface.Type.TEE, 3)
	assert_eq(seen.size(), 1)
	assert_eq((seen[0] as Array).size(), 4, "corner brush 3 writes 4 tiles")
	b.undo()
	assert_eq(seen.size(), 2)
	assert_eq((seen[1] as Array).size(), 4)


# --- picking ---

## Screen point of tile `cell` at `h`, nudged by `offset` px.
func _at(cell: Vector2i, h: int, offset: Vector2 = Vector2.ZERO) -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), h) + offset


func test_pick_on_flat_ground_matches_the_projection() -> void:
	var c := _flat(10, 0)
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(4, 7), Vector2i(9, 9)]:
		assert_eq(TilePicker.pick(c, _at(cell, 0, Vector2(3.3, 2.1))), cell)
	assert_eq(TilePicker.pick(c, _at(Vector2i(-3, 4), 0)), TilePicker.NONE, "off the map")


func test_pick_on_raised_ground() -> void:
	var c := _flat(12, 0)
	c.set_tile(8, 8, 4, Surface.Type.GREEN)
	var p: Vector2 = _at(Vector2i(8, 8), 4, Vector2(1.5, 0.5))
	assert_eq(Iso.screen_to_cell(p, 0), Vector2i(6, 6), "a height-0 pick would miss")
	assert_eq(TilePicker.pick(c, p), Vector2i(8, 8), "the raised top is picked")
	# The tile whose ground the raised top now covers is hidden, so it is not picked.
	assert_eq(TilePicker.pick(c, _at(Vector2i(6, 6), 0, Vector2(0.5, 0.5))), Vector2i(8, 8))


func test_pick_a_tile_partly_hidden_by_a_nearer_hill() -> void:
	# (5, 5) at 2 stands behind (6, 6) at 3. The top half of (5, 5)'s diamond shows; the
	# bottom half is behind the nearer hill's top.
	var c := _flat(12, 0)
	c.set_tile(5, 5, 2, Surface.Type.GREEN)
	c.set_tile(6, 6, 3, Surface.Type.FAIRWAY)
	assert_eq(TilePicker.pick(c, _at(Vector2i(5, 5), 2, Vector2(0.5, -8.5))), Vector2i(5, 5), "visible part")
	assert_eq(TilePicker.pick(c, _at(Vector2i(5, 5), 2, Vector2(18.5, -2.5))), Vector2i(5, 5), "visible right corner")
	assert_eq(TilePicker.pick(c, _at(Vector2i(5, 5), 2, Vector2(0.5, 8.5))), Vector2i(6, 6), "hidden part")
	# The nearer hill's wall belongs to the hill.
	assert_eq(TilePicker.pick(c, _at(Vector2i(6, 6), 0, Vector2(-10.5, 0.5))), Vector2i(6, 6), "its wall")


## What the renderer draws frontmost at `p`: every drawn piece (top at h, visible riser faces)
## tested by its own shape, winner by Iso sort key. Independent of TilePicker's math.
func _reference_pick(c: CourseData, p: Vector2) -> Vector2i:
	var best := TilePicker.NONE
	var best_key: float = -INF
	for y: int in c.height:
		for x: int in c.width:
			var cell := Vector2i(x, y)
			var h: int = c.get_height(x, y)
			var top: Vector2 = Iso.tile_to_screen(Vector2(cell), h)
			if absf(p.x - top.x) / Iso.HALF_W + absf(p.y - top.y) / Iso.HALF_H <= 1.0:
				if Iso.top_sort_key(cell, h) > best_key:
					best_key = Iso.top_sort_key(cell, h)
					best = cell
			for k: int in h:
				var frame: StringName = CourseView.riser_frame(c, x, y, k)
				if frame.is_empty() or Iso.riser_sort_key(cell, k) <= best_key:
					continue
				# The band between the bottom edges of the diamond at k + 1 and at k.
				var ctr: Vector2 = Iso.tile_to_screen(Vector2(cell), k + 1)
				var dx: float = p.x - ctr.x
				if absf(dx) > Iso.HALF_W:
					continue
				if dx < 0.0 and frame == &"right" or dx >= 0.0 and frame == &"left":
					continue
				var edge_y: float = ctr.y + Iso.HALF_H - absf(dx) * 0.5
				if p.y >= edge_y and p.y <= edge_y + Iso.STEP_PX:
					best_key = Iso.riser_sort_key(cell, k)
					best = cell
	return best


func test_pick_matches_what_is_drawn_frontmost() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var c := CourseData.create(8, 8)
	for y: int in 8:
		for x: int in 8:
			c.set_tile(x, y, rng.randi_range(0, 7), Surface.Type.ROUGH)
	var r := Rect2(Iso.tile_to_screen(Vector2(-0.5, 7.5), 7) - Vector2(0, 0), Vector2.ZERO)
	r = r.expand(Iso.tile_to_screen(Vector2(7.5, -0.5), 7)).expand(Iso.tile_to_screen(Vector2(7.5, 7.5), 0))
	var misses: Array[String] = []
	var hits: int = 0
	for n: int in 1500:
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
		var want: Vector2i = _reference_pick(c, p)
		var got: Vector2i = TilePicker.pick(c, p)
		if want != TilePicker.NONE:
			hits += 1
		if want != got:
			misses.append("%s: drawn %s, picked %s" % [p, want, got])
	assert_gt(hits, 800, "most samples land on the course")
	assert_eq(misses.size(), 0, "\n".join(misses.slice(0, 5)))


# --- the build tool in the main scene ---

func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = ""
	add_child_autofree(m)
	return m


func test_main_paints_through_the_builder_in_build_mode() -> void:
	var m := _main()
	var tool: BuildTool = m.build_tool
	assert_true(tool.active, "starts in Build")
	assert_same(tool.builder.course, m.course, "the tool writes the shown course")
	tool.select_surface(Surface.Type.WATER)
	tool.brush_size = 3
	tool.press_at(_at(Vector2i(4, 4), 0, Vector2(0.5, 0.5)))
	tool.release()
	assert_eq(m.course.get_surface(5, 5), Surface.Type.WATER)
	assert_eq(m.course_view.top_layer(0).get_cell_atlas_coords(Vector2i(5, 5)), Vector2i(Surface.Type.WATER, 0),
			"the view redraws edited tiles")
	tool.select_tool(BuildTool.Tool.RAISE)
	tool.press_at(_at(Vector2i(4, 4), 0, Vector2(0.5, 0.5)))
	tool.release()
	assert_eq(m.course.get_height(4, 4), 1)
	assert_eq(m.course_view.top_layer(1).get_cell_source_id(Vector2i(4, 4)), CourseView.SURFACE_SOURCE)
	tool.undo()
	tool.undo()
	assert_eq(m.course.get_height(4, 4), 0)
	assert_eq(m.course.get_surface(5, 5), Surface.Type.ROUGH)


func test_drag_paints_a_line_as_one_undo() -> void:
	var m := _main()
	var tool: BuildTool = m.build_tool
	tool.select_surface(Surface.Type.CART_PATH)
	tool.brush_size = 1
	tool.press_at(_at(Vector2i(2, 6), 0, Vector2(0.5, 0.5)))
	for x: int in range(3, 9):
		tool.drag_to(_at(Vector2i(x, 6), 0, Vector2(0.5, 0.5)))
	tool.release()
	for x: int in range(2, 9):
		assert_eq(m.course.get_surface(x, 6), Surface.Type.CART_PATH, "x %d" % x)
	assert_eq(tool.builder.undo_depth(), 1)


func test_fast_drag_fills_every_tile_it_crosses() -> void:
	var m := _main()
	var tool: BuildTool = m.build_tool
	tool.select_surface(Surface.Type.CART_PATH)
	tool.brush_size = 1
	tool.press_at(_at(Vector2i(2, 6), 0, Vector2(0.5, 0.5)))
	tool.drag_to(_at(Vector2i(8, 6), 0, Vector2(0.5, 0.5)))  # one motion event, six tiles
	tool.drag_to(_at(Vector2i(4, 2), 0, Vector2(0.5, 0.5)))  # and a diagonal back
	tool.release()
	for x: int in range(2, 9):
		assert_eq(m.course.get_surface(x, 6), Surface.Type.CART_PATH, "x %d" % x)
	for cell: Vector2i in BuildTool.grid_line(Vector2i(8, 6), Vector2i(4, 2)):
		assert_eq(m.course.get_surface(cell.x, cell.y), Surface.Type.CART_PATH, str(cell))
	assert_eq(m.course.get_surface(2, 5), Surface.Type.ROUGH, "nothing off the line")
	assert_eq(tool.builder.undo_depth(), 1)


func test_grid_line_is_8_connected_and_inclusive() -> void:
	var line := BuildTool.grid_line(Vector2i(1, 1), Vector2i(6, 3))
	assert_eq(line[0], Vector2i(1, 1))
	assert_eq(line[-1], Vector2i(6, 3))
	assert_eq(line.size(), 6, "one tile per step along the long axis")
	for i: int in range(1, line.size()):
		var d: Vector2i = (line[i] - line[i - 1]).abs()
		assert_true(d.x <= 1 and d.y <= 1, "neighbors")
	assert_eq(BuildTool.grid_line(Vector2i(3, 3), Vector2i(3, 3)), [Vector2i(3, 3)] as Array[Vector2i])


func test_a_small_drag_after_lower_lowers_one_tile() -> void:
	var m := _main()
	var tool: BuildTool = m.build_tool
	var b: CourseBuilder = tool.builder
	b.begin_stroke()
	for y: int in m.course.height:
		for x: int in m.course.width:
			b.raise(Vector2i(x, y), 1)
	b.end_stroke()
	var before: int = m.course.get_height(8, 8)
	tool.select_tool(BuildTool.Tool.LOWER)
	tool.brush_size = 1
	var p: Vector2 = _at(Vector2i(8, 8), before, Vector2(0.5, 0.5))
	tool.press_at(p)
	# A few pixels of jiggle, up the screen: on the dug ground that point is now the back tile.
	for d: Vector2 in [Vector2(0.5, -1.0), Vector2(1.0, -3.0), Vector2(-1.0, -2.5), Vector2(0.0, -0.5)]:
		tool.drag_to(p + d)
	tool.release()
	assert_eq(m.course.get_height(8, 8), before - 1)
	var lowered: Array[Vector2i] = []
	for y: int in m.course.height:
		for x: int in m.course.width:
			if m.course.get_height(x, y) != before:
				lowered.append(Vector2i(x, y))
	assert_eq(lowered, [Vector2i(8, 8)] as Array[Vector2i], "the drag does not creep onto the tile behind")


func test_tool_is_inactive_in_play_mode() -> void:
	var m := _main()
	var before: String = m.course.content_hash()
	m.set_mode(Main.Mode.PLAY)
	assert_false(m.build_tool.active)
	assert_false(m.build_palette.visible, "palette hidden in Play")
	m.build_tool.select_surface(Surface.Type.GREEN)
	m.build_tool.press_at(_at(Vector2i(3, 3), 0))
	m.build_tool.release()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(640, 360)
	m.build_tool._unhandled_input(click)
	assert_eq(m.course.content_hash(), before, "no edits in Play")
	m.set_mode(Main.Mode.BUILD)
	assert_true(m.build_tool.active)
	assert_true(m.build_palette.visible)


func test_palette_drives_the_tool() -> void:
	var m := _main()
	var pal: BuildPalette = m.build_palette
	assert_eq(pal.surface_buttons.size(), CourseBuilder.PALETTE.size())
	pal.surface_buttons[CourseBuilder.PALETTE.find(Surface.Type.BUNKER)].pressed.emit()
	assert_eq(m.build_tool.tool, BuildTool.Tool.PAINT)
	assert_eq(m.build_tool.surface, Surface.Type.BUNKER)
	pal.lower_button.pressed.emit()
	assert_eq(m.build_tool.tool, BuildTool.Tool.LOWER)
	pal.brush_buttons[2].pressed.emit()
	assert_eq(m.build_tool.brush_size, 5)
	# Changes made on the tool (not by clicking) leave exactly one button lit per group.
	m.build_tool.select_surface(Surface.Type.GREEN)
	m.build_tool.select_surface(Surface.Type.TEE)
	m.build_tool.brush_size = 3
	var lit: Array[String] = []
	for b: Button in pal.surface_buttons + [pal.raise_button, pal.lower_button, pal.tee_button, pal.cup_button] + pal.brush_buttons:
		if b.button_pressed:
			lit.append(b.text)
	assert_eq(lit, ["tee", "3"] as Array[String])


func test_undo_shortcut() -> void:
	assert_true(InputMap.has_action(BuildTool.UNDO_ACTION))
	var m := _main()
	m.build_tool.select_tool(BuildTool.Tool.RAISE)
	m.build_tool.press_at(_at(Vector2i(3, 3), 0))
	m.build_tool.release()
	assert_eq(m.course.get_height(3, 3), 1)
	var ev := InputEventAction.new()
	ev.action = BuildTool.UNDO_ACTION
	ev.pressed = true
	m.build_tool._unhandled_input(ev)
	assert_eq(m.course.get_height(3, 3), 0)
