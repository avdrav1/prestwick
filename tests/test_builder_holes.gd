extends GutTest
## E2-S3: a hole made in Build through course/builder.gd. A new sandbox on the D10 plot, the
## tee and cup tools, par, all on the terrain's undo stack, and `oob` on the palette (D9).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _flat(size: int = 40, h: int = 2) -> CourseData:
	return CourseData.create(size, size, Surface.Type.ROUGH, h)


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = ""
	add_child_autofree(m)
	return m


func _at(c: CourseData, cell: Vector2i) -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), c.get_height(cell.x, cell.y)) + Vector2(0.5, 0.5)


# --- new sandbox ---

func test_tuning_holds_the_d10_plot() -> void:
	var t := BuilderTuning.load_default()
	assert_eq(t.plot_size, Vector2i(128, 128), "D10: 128 x 128 tiles")
	assert_eq(t.plot_surface, Surface.Type.ROUGH, "D10: every tile rough")
	assert_eq(t.plot_ground, 2, "D10: height 2")
	assert_true(t.default_par in [3, 4, 5])


func test_new_sandbox_is_the_d10_plot() -> void:
	var c := CourseBuilder.new_sandbox()
	assert_eq(Vector2i(c.width, c.height), Vector2i(128, 128))
	var wrong: int = 0
	for y: int in c.height:
		for x: int in c.width:
			if c.get_surface(x, y) != Surface.Type.ROUGH or c.get_height(x, y) != 2:
				wrong += 1
	assert_eq(wrong, 0, "every tile rough at height 2")
	assert_eq(c.holes.size(), 0, "no holes yet")


func test_main_new_sandbox_shows_a_blank_plot_with_a_fresh_builder() -> void:
	var m := _main()
	m.build_tool.builder.raise(Vector2i(2, 2), 1)
	m.new_sandbox()
	assert_eq(Vector2i(m.course.width, m.course.height), Vector2i(128, 128))
	assert_same(m.build_tool.builder.course, m.course, "the tool builds the new plot")
	assert_false(m.build_tool.builder.can_undo(), "a new sandbox starts with an empty undo stack")
	assert_eq(m.course_view.top_layer(2).get_cell_atlas_coords(Vector2i(127, 127)), Vector2i(Surface.Type.ROUGH, 0),
			"the view shows the whole plot")
	assert_true(m.new_sandbox_button.visible, "New sandbox is on the Build HUD")


func test_new_sandbox_button_starts_the_plot_and_hides_in_play() -> void:
	var m := _main()
	m.new_sandbox_button.pressed.emit()
	assert_eq(Vector2i(m.course.width, m.course.height), Vector2i(128, 128))
	assert_eq(m.course.get_height(64, 64), 2)
	m.set_mode(Main.Mode.PLAY)
	assert_false(m.new_sandbox_button.visible, "Build only")


func test_main_startup_course_is_unchanged_until_e2_s8() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	assert_eq(m.course_path, "res://courses/heights_20x20.json")
	m.free()


# --- tee, cup and par ---

func test_tee_then_cup_creates_hole_one() -> void:
	var c := _flat()
	var b := CourseBuilder.new(c)
	assert_true(b.place_tee(1, Vector2i(5, 20), 3))
	assert_eq(c.holes.size(), 1)
	var h: HoleData = b.hole(1)
	assert_eq(h.tee, Vector2i(5, 20))
	assert_eq(h.cup, HoleData.UNPLACED, "the cup is not placed yet")
	assert_eq(h.par, 3)
	assert_false(h.open, "a new hole starts closed")
	assert_true(b.place_cup(1, Vector2i(30, 20)))
	assert_eq(c.holes.size(), 1, "the cup joins the same hole")
	assert_eq(b.hole(1).cup, Vector2i(30, 20))


func test_cup_first_also_creates_the_hole() -> void:
	var b := CourseBuilder.new(_flat())
	assert_true(b.place_cup(1, Vector2i(30, 20), 4))
	assert_eq(b.hole(1).tee, HoleData.UNPLACED)
	assert_eq(b.hole(1).par, 4)


func test_moving_the_tee_and_cup() -> void:
	var c := _flat()
	var b := CourseBuilder.new(c)
	b.place_tee(1, Vector2i(5, 20))
	b.place_cup(1, Vector2i(30, 20))
	assert_true(b.place_tee(1, Vector2i(6, 21)))
	assert_true(b.place_cup(1, Vector2i(31, 19)))
	assert_eq(c.holes.size(), 1, "moving never adds a hole")
	assert_eq(b.hole(1).tee, Vector2i(6, 21))
	assert_eq(b.hole(1).cup, Vector2i(31, 19))
	var depth: int = b.undo_depth()
	assert_false(b.place_cup(1, Vector2i(31, 19)), "placing on the same tile changes nothing")
	assert_false(b.place_tee(1, Vector2i(-1, 3)), "off the map")
	assert_false(b.place_cup(1, Vector2i(3, 40)), "off the map")
	assert_eq(b.undo_depth(), depth, "no-op placements are not recorded")


func test_hole_edits_share_the_terrain_undo_stack() -> void:
	var c := _flat()
	var original: String = c.content_hash()
	var b := CourseBuilder.new(c)
	b.place_tee(1, Vector2i(5, 20))
	b.paint(Vector2i(30, 20), Surface.Type.GREEN, 3)
	b.place_cup(1, Vector2i(30, 20))
	b.set_par(1, 4)
	b.place_tee(1, Vector2i(4, 20))
	assert_eq(b.undo_depth(), 5, "tee, paint, cup, par and a move: five steps")
	b.undo()
	assert_eq(b.hole(1).tee, Vector2i(5, 20), "undo a move")
	b.undo()
	assert_eq(b.hole(1).par, 3, "undo par")
	b.undo()
	assert_eq(b.hole(1).cup, HoleData.UNPLACED, "undo the cup")
	assert_eq(c.get_surface(30, 20), Surface.Type.GREEN, "the paint is still there")
	b.undo()
	assert_eq(c.get_surface(30, 20), Surface.Type.ROUGH, "undo the paint")
	b.undo()
	assert_null(b.hole(1), "undo the tee: no hole")
	assert_eq(c.content_hash(), original)
	assert_false(b.can_undo())


func test_a_hole_edit_closes_an_open_stroke_first() -> void:
	var c := _flat()
	var b := CourseBuilder.new(c)
	b.begin_stroke()
	b.raise(Vector2i(3, 3), 1)
	b.place_tee(1, Vector2i(5, 5))
	b.raise(Vector2i(4, 4), 1)
	b.end_stroke()
	assert_eq(b.undo_depth(), 3, "the drag so far, the tee, then the raise after it on its own")


func test_par_is_3_4_or_5() -> void:
	var b := CourseBuilder.new(_flat())
	b.place_tee(1, Vector2i(5, 20))
	for p: int in [3, 4, 5]:
		b.set_par(1, p)
		assert_eq(b.hole(1).par, p)
	var depth: int = b.undo_depth()
	assert_false(b.set_par(1, 2), "par 2 is not a par")
	assert_false(b.set_par(1, 6), "par 6 is not a par")
	assert_false(b.set_par(1, 5), "unchanged")
	assert_false(b.set_par(2, 4), "no hole 2")
	assert_eq(b.hole(1).par, 5)
	assert_eq(b.undo_depth(), depth)


func test_holes_changed_is_emitted_for_hole_edits_and_their_undo() -> void:
	var b := CourseBuilder.new(_flat())
	watch_signals(b)
	b.place_tee(1, Vector2i(5, 20))
	assert_signal_emit_count(b, "holes_changed", 1)
	b.undo()
	assert_signal_emit_count(b, "holes_changed", 2)
	b.paint(Vector2i(2, 2), Surface.Type.GREEN, 1)
	assert_signal_emit_count(b, "holes_changed", 2, "a paint that closes no hole leaves the holes alone")


# --- oob on the palette (D9) ---

func test_oob_paints_from_the_palette() -> void:
	assert_true(Surface.Type.OOB in CourseBuilder.PALETTE, "D9: oob is on the Build palette")
	var c := _flat()
	var b := CourseBuilder.new(c)
	assert_true(b.paint(Vector2i(4, 4), Surface.Type.OOB, 3))
	assert_eq(c.get_surface(5, 5), Surface.Type.OOB)
	assert_eq(c.get_height(5, 5), 2, "oob keeps the ground")
	b.undo()
	assert_eq(c.get_surface(5, 5), Surface.Type.ROUGH)


func test_oob_button_paints_in_the_main_scene() -> void:
	var m := _main()
	var pal: BuildPalette = m.build_palette
	var i: int = CourseBuilder.PALETTE.find(Surface.Type.OOB)
	assert_eq(pal.surface_buttons[i].text, "oob")
	pal.surface_buttons[i].pressed.emit()
	m.build_tool.press_at(_at(m.course, Vector2i(3, 3)))
	m.build_tool.release()
	assert_eq(m.course.get_surface(3, 3), Surface.Type.OOB)


# --- the tee and cup tools in the main scene ---

func test_tee_and_cup_tools_place_hole_one() -> void:
	var m := _main()
	var tool: BuildTool = m.build_tool
	m.build_palette.tee_button.pressed.emit()
	assert_eq(tool.tool, BuildTool.Tool.TEE)
	tool.press_at(_at(m.course, Vector2i(2, 10)))
	tool.drag_to(_at(m.course, Vector2i(4, 10)))
	tool.release()
	assert_eq(tool.builder.hole(1).tee, Vector2i(2, 10), "the tee goes where the click was; a drag does not move it")
	m.build_palette.cup_button.pressed.emit()
	assert_eq(tool.tool, BuildTool.Tool.CUP)
	tool.press_at(_at(m.course, Vector2i(15, 10)))
	tool.release()
	assert_eq(tool.builder.hole(1).cup, Vector2i(15, 10))
	assert_not_null(m.course_view.hole_marker(1, HoleMarker.Kind.TEE), "the view shows the tee")
	assert_eq(m.course_view.hole_marker(1, HoleMarker.Kind.PIN).cell, Vector2i(15, 10), "and the pin")
	tool.undo()
	assert_null(m.course_view.hole_marker(1, HoleMarker.Kind.PIN), "undo takes the pin away")


func test_par_buttons_set_the_hole_par() -> void:
	var m := _main()
	var panel: HolePanel = m.hole_panel
	assert_eq(panel.par_buttons.size(), 3)
	panel.par_buttons[1].pressed.emit()
	assert_eq(m.build_tool.par, 4, "the par for the next hole")
	m.build_tool.select_tool(BuildTool.Tool.TEE)
	m.build_tool.press_at(_at(m.course, Vector2i(2, 10)))
	m.build_tool.release()
	assert_eq(m.build_tool.builder.hole(1).par, 4, "a new hole takes the picked par")
	panel.par_buttons[2].pressed.emit()
	assert_eq(m.build_tool.builder.hole(1).par, 5, "and a par button changes an existing hole")
	m.build_tool.undo()
	assert_eq(m.build_tool.builder.hole(1).par, 4)
	assert_true(panel.par_buttons[1].button_pressed, "the panel follows the undo")
