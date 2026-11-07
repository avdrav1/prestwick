extends GutTest
## E3-S2: the hole list. Up to nine holes (BuilderTuning.max_holes), numbered in build order
## and renumberable through course/builder.gd (undo steps); picking a hole in the list points
## the tee and cup tools at it, the list opens or closes it and plays it in one click, and a
## course loaded with holes frames hole 1. Numbers and order round-trip through course/save.gd.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")


## A 40 x 70 rough plot at height 2.
func _plot() -> CourseData:
	return CourseData.create(40, 70, Surface.Type.ROUGH, 2)


## Row k's par 3: tee (2, 3 + 7k), cup (22, 3 + 7k), 100 yd. Rows 7 tiles (35 yd) apart sit
## outside each other's footprints (30 yd), so building one never closes another.
func _tee(k: int) -> Vector2i:
	return Vector2i(2, 3 + 7 * k)


func _cup(k: int) -> Vector2i:
	return Vector2i(22, 3 + 7 * k)


## Builds `count` par 3s through `b`, numbered as the builder picks (next_hole_number), each
## cup on a green, each opened. Returns the numbers in build order.
func _build(b: CourseBuilder, count: int, open: bool = true) -> Array[int]:
	var out: Array[int] = []
	for k: int in count:
		var n: int = b.next_hole_number()
		b.paint(_cup(k), Surface.Type.GREEN, 1)
		assert_true(b.place_tee(n, _tee(k), 3), "hole %d's tee" % n)
		assert_true(b.place_cup(n, _cup(k)), "hole %d's cup" % n)
		if open:
			assert_true(b.open_hole(n), "hole %d opens" % n)
		out.append(n)
	return out


func _main_with(c: CourseData) -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(c)
	return m


## A course with `count` open par 3s, made through a builder of its own.
func _course_with(count: int) -> CourseData:
	var c := _plot()
	_build(CourseBuilder.new(c), count)
	return c


func _at(c: CourseData, cell: Vector2i) -> Vector2:
	return Iso.tile_to_screen(Vector2(cell), c.get_height(cell.x, cell.y)) + Vector2(0.5, 0.5)


func _click(m: Main, cell: Vector2i) -> void:
	m.build_tool.press_at(_at(m.course, cell))
	m.build_tool.release()


# --- numbering ---

func test_tuning_allows_nine_holes() -> void:
	assert_eq(BuilderTuning.load_default().max_holes, 9, "a nine-hole course (E3)")


func test_holes_are_numbered_in_build_order() -> void:
	var c := _plot()
	var b := CourseBuilder.new(c)
	assert_eq(b.next_hole_number(), 1, "an empty course starts at hole 1")
	var numbers: Array[int] = _build(b, 3)
	assert_eq(numbers, [1, 2, 3] as Array[int])
	assert_eq(b.hole_numbers(), [1, 2, 3] as Array[int])
	assert_eq(b.next_hole_number(), 4)
	assert_eq(b.hole(2).tee, _tee(1), "the second hole built is hole 2")


func test_a_course_holds_at_most_nine_holes() -> void:
	var c := _plot()
	var b := CourseBuilder.new(c)
	assert_eq(_build(b, 9).size(), 9)
	assert_eq(c.holes.size(), 9)
	assert_eq(b.next_hole_number(), 0, "no tenth hole")
	watch_signals(b)
	var depth: int = b.undo_depth()
	assert_false(b.place_tee(10, Vector2i(30, 5)), "hole 10 is refused")
	assert_signal_emitted_with_parameters(b, "refused", [CourseBuilder.TOO_MANY_HOLES % 9])
	assert_false(b.place_cup(10, Vector2i(30, 5)))
	assert_eq(c.holes.size(), 9)
	assert_eq(b.undo_depth(), depth, "a refused hole is not an undo step")
	assert_true(b.place_tee(9, Vector2i(30, 60)), "an existing hole still moves")
	for n: int in b.hole_numbers():
		assert_true(n >= 1 and n <= 9)


func test_a_number_past_nine_is_refused_even_with_room() -> void:
	var b := CourseBuilder.new(_plot())
	assert_false(b.place_tee(0, _tee(0)), "no hole 0")
	assert_false(b.place_tee(12, _tee(0)), "no hole 12")
	assert_eq(b.course.holes.size(), 0)


func test_the_lowest_free_number_comes_next() -> void:
	var b := CourseBuilder.new(_plot())
	_build(b, 3)
	assert_true(b.renumber_hole(2, 5))
	assert_eq(b.hole_numbers(), [1, 3, 5] as Array[int])
	assert_eq(b.next_hole_number(), 2, "the gap is filled first")


# --- renumbering ---

func test_renumbering_swaps_with_the_hole_already_there() -> void:
	var c := _plot()
	var b := CourseBuilder.new(c)
	_build(b, 3)
	var depth: int = b.undo_depth()
	watch_signals(b)
	assert_true(b.renumber_hole(3, 1))
	assert_eq(b.hole(1).tee, _tee(2), "the third hole built is hole 1 now")
	assert_eq(b.hole(3).tee, _tee(0), "and the old hole 1 is hole 3")
	assert_eq(b.hole(2).tee, _tee(1), "hole 2 is untouched")
	assert_true(b.hole(1).open and b.hole(3).open, "renumbering keeps a hole open")
	assert_eq(b.undo_depth(), depth + 1, "one undo step")
	assert_signal_emitted(b, "holes_changed")
	assert_true(b.issues_for(1).is_empty() and b.issues_for(3).is_empty())
	b.undo()
	assert_eq(b.hole(1).tee, _tee(0), "undo puts the numbers back")
	assert_eq(b.hole(3).tee, _tee(2))


func test_renumbering_to_a_free_number_moves_the_hole() -> void:
	var b := CourseBuilder.new(_plot())
	_build(b, 2)
	assert_true(b.renumber_hole(2, 7))
	assert_null(b.hole(2))
	assert_eq(b.hole(7).tee, _tee(1))
	assert_eq(b.hole_numbers(), [1, 7] as Array[int])


func test_renumbering_refuses_what_it_cannot_do() -> void:
	var b := CourseBuilder.new(_plot())
	_build(b, 2)
	var depth: int = b.undo_depth()
	assert_false(b.renumber_hole(1, 1), "the same number")
	assert_false(b.renumber_hole(4, 1), "no hole 4")
	assert_false(b.renumber_hole(1, 0), "no hole 0")
	assert_false(b.renumber_hole(1, 10), "past nine")
	assert_eq(b.undo_depth(), depth)


func test_numbers_and_order_survive_a_save() -> void:
	var c := _plot()
	var b := CourseBuilder.new(c)
	_build(b, 4)
	b.renumber_hole(4, 1)
	b.renumber_hole(2, 6)
	b.close_hole(3)
	var errors: Array[String] = []
	var back: CourseData = CourseSave.from_json(CourseSave.to_json(c), errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(back.content_hash(), c.content_hash(), "the same course")
	assert_eq(back.holes.size(), 4)
	for i: int in c.holes.size():
		assert_eq(back.holes[i].number, c.holes[i].number, "hole %d keeps its place" % i)
		assert_eq(back.holes[i].tee, c.holes[i].tee)
		assert_eq(back.holes[i].open, c.holes[i].open)
	var b2 := CourseBuilder.new(back)
	assert_eq(b2.hole_numbers(), [1, 3, 4, 6] as Array[int])
	assert_eq(b2.hole(1).tee, _tee(3))
	assert_false(b2.hole(3).open, "a closed hole loads closed")


# --- open and close ---

func test_close_hole_is_an_undo_step() -> void:
	var b := CourseBuilder.new(_plot())
	_build(b, 2)
	var depth: int = b.undo_depth()
	assert_true(b.close_hole(2))
	assert_false(b.hole(2).open)
	assert_true(b.hole(1).open, "only that hole")
	assert_false(b.close_hole(2), "already closed")
	assert_false(b.close_hole(5), "no hole 5")
	assert_eq(b.undo_depth(), depth + 1)
	b.undo()
	assert_true(b.hole(2).open, "undo opens it again")


# --- the build tool ---

func test_the_tools_build_the_picked_hole() -> void:
	var m := _main_with(_plot())
	var tool: BuildTool = m.build_tool
	m.build_tool.builder.paint(_cup(0), Surface.Type.GREEN, 1)
	tool.select_hole(3)
	assert_eq(tool.hole_number, 3)
	tool.select_tool(BuildTool.Tool.TEE)
	_click(m, _tee(0))
	tool.select_tool(BuildTool.Tool.CUP)
	_click(m, _cup(0))
	assert_null(tool.builder.hole(1), "hole 1 is not touched")
	assert_eq(tool.builder.hole(3).tee, _tee(0), "the tee tool built hole 3")
	assert_eq(tool.builder.hole(3).cup, _cup(0), "and the cup tool")
	assert_not_null(m.course_view.hole_marker(3, HoleMarker.Kind.TEE), "the view shows hole 3")


func test_new_hole_picks_the_next_number_and_the_tee_tool() -> void:
	var m := _main_with(_course_with(2))
	var panel: HolePanel = m.hole_panel
	assert_false(panel.new_hole_button.disabled)
	panel.new_hole_button.pressed.emit()
	assert_eq(m.build_tool.hole_number, 3, "the next hole in build order")
	assert_eq(m.build_tool.tool, BuildTool.Tool.TEE, "ready to place its tee")
	assert_string_contains(panel.title_label.text, "Hole 3")
	_click(m, _tee(2))
	assert_eq(m.build_tool.builder.hole(3).tee, _tee(2))


func test_new_hole_is_disabled_at_nine() -> void:
	var m := _main_with(_course_with(8))
	assert_false(m.hole_panel.new_hole_button.disabled)
	m.hole_panel.new_hole_button.pressed.emit()
	_click(m, _tee(8))
	assert_eq(m.build_tool.builder.hole(9).tee, _tee(8), "the ninth hole")
	assert_true(m.hole_panel.new_hole_button.disabled, "nine holes: no tenth")
	m.build_tool.undo()
	assert_false(m.hole_panel.new_hole_button.disabled, "undo frees a number")


# --- the list in the hole panel ---

func test_the_list_shows_every_hole_in_number_order() -> void:
	var c := _course_with(3)
	CourseBuilder.new(c).renumber_hole(1, 5)
	var m := _main_with(c)
	var panel: HolePanel = m.hole_panel
	var rows: Array[HolePanel.HoleRow] = panel.shown_rows()
	assert_eq(rows.size(), 3)
	assert_eq([rows[0].number, rows[1].number, rows[2].number], [2, 3, 5])
	assert_string_contains(rows[0].pick_button.text, "2")
	assert_string_contains(rows[0].pick_button.text, "Par 3")
	assert_string_contains(rows[0].pick_button.text, "100 yd")
	assert_string_contains(rows[0].pick_button.text, "open")


func test_picking_a_row_points_the_tools_at_it() -> void:
	var m := _main_with(_course_with(3))
	var panel: HolePanel = m.hole_panel
	assert_eq(m.build_tool.hole_number, 1, "a loaded course starts on hole 1")
	assert_true(panel.row_for(1).pick_button.button_pressed)
	panel.row_for(2).pick_button.pressed.emit()
	assert_eq(m.build_tool.hole_number, 2)
	assert_true(panel.row_for(2).pick_button.button_pressed, "the picked row shows it")
	assert_false(panel.row_for(1).pick_button.button_pressed)
	assert_string_contains(panel.title_label.text, "Hole 2")
	m.build_tool.select_tool(BuildTool.Tool.TEE)
	_click(m, Vector2i(4, 11))
	assert_eq(m.build_tool.builder.hole(2).tee, Vector2i(4, 11), "the tee tool moved hole 2's tee")
	assert_eq(m.build_tool.builder.hole(1).tee, _tee(0))


func test_a_row_opens_and_closes_its_hole_in_one_click() -> void:
	var m := _main_with(_course_with(2))
	var panel: HolePanel = m.hole_panel
	var row: HolePanel.HoleRow = panel.row_for(2)
	assert_eq(row.open_button.text, "Close")
	row.open_button.pressed.emit()
	assert_false(m.build_tool.builder.hole(2).open, "one click closes it")
	assert_eq(panel.row_for(2).open_button.text, "Open")
	assert_string_contains(panel.row_for(2).pick_button.text, "closed")
	panel.row_for(2).open_button.pressed.emit()
	assert_true(m.build_tool.builder.hole(2).open, "one click opens it again")
	assert_eq(m.build_tool.hole_number, 1, "without moving the pick")


func test_a_row_cannot_open_a_failing_hole() -> void:
	var c := _course_with(2)
	var b := CourseBuilder.new(c)
	b.paint(_cup(1), Surface.Type.ROUGH, 1)  # rule 2 fails: hole 2 closes
	var m := _main_with(c)
	var row: HolePanel.HoleRow = m.hole_panel.row_for(2)
	assert_eq(row.open_button.text, "Open")
	assert_true(row.open_button.disabled, "Open needs every rule to pass")


func test_a_row_plays_its_hole_in_one_click() -> void:
	var m := _main_with(_course_with(3))
	m.hole_panel.row_for(3).play_button.pressed.emit()
	assert_eq(m.mode, Main.Mode.PLAY, "one click to Play")
	assert_eq(m.swing_control.hole.number, 3, "on hole 3")
	var ypt: float = m.swing_control.field.yards_per_tile
	assert_almost_eq(m.swing_control.ball_at, (Vector2(_tee(2)) + Vector2(0.5, 0.5)) * ypt,
			Vector2(0.01, 0.01), "the ball sits on hole 3's tee")
	assert_eq(m.score_card.title_label.text, "Hole 3")
	m.set_mode(Main.Mode.BUILD)
	assert_eq(m.build_tool.hole_number, 3, "back in Build, hole 3 is picked")


func test_tab_plays_the_picked_hole() -> void:
	var m := _main_with(_course_with(3))
	m.hole_panel.row_for(2).pick_button.pressed.emit()
	m.toggle_mode()
	assert_eq(m.swing_control.hole.number, 2)


func test_a_picked_hole_with_no_tee_plays_the_first_hole() -> void:
	var m := _main_with(_course_with(2))
	m.hole_panel.new_hole_button.pressed.emit()
	m.toggle_mode()
	assert_eq(m.swing_control.hole.number, 1, "hole 3 has no tee yet")


func test_up_and_down_renumber_the_hole() -> void:
	var m := _main_with(_course_with(3))
	var panel: HolePanel = m.hole_panel
	assert_true(panel.row_for(1).up_button.disabled, "hole 1 has no number above it")
	assert_true(panel.row_for(3).down_button.disabled, "the last hole has none below it")
	panel.row_for(3).pick_button.pressed.emit()
	panel.row_for(3).up_button.pressed.emit()
	var b: CourseBuilder = m.build_tool.builder
	assert_eq(b.hole(2).tee, _tee(2), "up: the third hole built is hole 2 now")
	assert_eq(b.hole(3).tee, _tee(1))
	assert_eq(m.build_tool.hole_number, 2, "the pick follows the hole it moved")
	panel.row_for(1).down_button.pressed.emit()
	assert_eq(b.hole(2).tee, _tee(0), "down swaps with the hole below")
	assert_eq(b.hole(1).tee, _tee(2))
	assert_eq(m.course_view.hole_marker(1, HoleMarker.Kind.TEE).cell, _tee(2), "the map follows")
	m.build_tool.undo()
	assert_eq(b.hole(1).tee, _tee(0), "Ctrl+Z undoes a renumber")


func test_the_pick_stays_on_a_hole_swapped_out_of_its_number() -> void:
	var m := _main_with(_course_with(3))
	var panel: HolePanel = m.hole_panel
	panel.row_for(2).pick_button.pressed.emit()
	panel.row_for(3).up_button.pressed.emit()
	assert_eq(m.build_tool.hole_number, 3, "up on hole 3 swaps hole 2 to 3, and the pick goes too")
	assert_eq(m.build_tool.builder.hole(m.build_tool.hole_number).tee, _tee(1), "still the hole picked")
	panel.row_for(1).down_button.pressed.emit()
	assert_eq(m.build_tool.hole_number, 3, "a swap of two other holes leaves the pick")
	panel.row_for(2).pick_button.pressed.emit()
	panel.row_for(1).down_button.pressed.emit()
	assert_eq(m.build_tool.hole_number, 1, "down on hole 1 swaps hole 2 to 1, and the pick goes too")
	assert_eq(m.build_tool.builder.hole(1).tee, _tee(0), "the hole first built")


func test_the_pick_stays_on_its_hole_through_undo() -> void:
	var m := _main_with(_course_with(3))
	var panel: HolePanel = m.hole_panel
	var b: CourseBuilder = m.build_tool.builder
	panel.row_for(3).pick_button.pressed.emit()
	panel.row_for(3).up_button.pressed.emit()
	assert_eq(m.build_tool.hole_number, 2)
	assert_true(m.build_tool.undo())
	assert_eq(m.build_tool.hole_number, 3, "undoing the renumber takes the pick back to 3")
	assert_eq(b.hole(m.build_tool.hole_number).tee, _tee(2), "the hole the player picked")
	m.build_tool.select_tool(BuildTool.Tool.TEE)
	_click(m, Vector2i(4, 17))
	assert_eq(b.hole(3).tee, Vector2i(4, 17), "the Tee tool moves the picked hole's tee")
	assert_eq(b.hole(2).tee, _tee(1), "and no other")
	assert_true(m.build_tool.undo())
	assert_eq(m.build_tool.hole_number, 3, "undoing a tee move keeps the number")
	assert_eq(b.hole(3).tee, _tee(2))


func test_the_list_follows_undo() -> void:
	var m := _main_with(_plot())
	var b: CourseBuilder = m.build_tool.builder
	b.place_tee(1, _tee(0))
	b.place_tee(2, _tee(1))
	assert_eq(m.hole_panel.shown_rows().size(), 2)
	b.undo()
	assert_eq(m.hole_panel.shown_rows().size(), 1)
	assert_null(m.hole_panel.row_for(2))


func test_issue_boxes_name_their_hole() -> void:
	var c := _course_with(2)
	CourseBuilder.new(c).paint(_cup(1), Surface.Type.ROUGH, 1)
	var m := _main_with(c)
	var lines: PackedStringArray = m.course_view.issue_markers()[0].lines()
	assert_eq(lines.size(), 1)
	assert_string_contains(lines[0], "hole 2")
	assert_string_contains(lines[0], "rule 2")


func test_a_check_keeps_the_issue_boxes_that_did_not_change() -> void:
	var c := _course_with(3)
	var setup := CourseBuilder.new(c)
	setup.paint(_cup(1), Surface.Type.ROUGH, 1)
	setup.paint(_cup(2), Surface.Type.ROUGH, 1)
	var m := _main_with(c)
	var b: CourseBuilder = m.build_tool.builder
	var before: Array[IssueMarker] = m.course_view.issue_markers()
	assert_eq(before.size(), 2, "holes 2 and 3 fail rule 2")
	b.paint(Vector2i(30, 60), Surface.Type.FAIRWAY, 1)  # far from every hole: a check, no change
	var after: Array[IssueMarker] = m.course_view.issue_markers()
	assert_eq(after.size(), 2)
	assert_same(after[0], before[0], "an unchanged box is kept")
	assert_same(after[1], before[1])
	b.set_par(3, 5)  # hole 3's cup tile now fails rules 2 and 4
	after = m.course_view.issue_markers()
	assert_same(after[0], before[0], "hole 2's box is still kept")
	assert_ne(after[1], before[1], "hole 3's is rebuilt")
	assert_eq(after[1].lines().size(), 2)
	b.paint(_cup(1), Surface.Type.GREEN, 1)
	assert_eq(m.course_view.issue_markers().size(), 1, "a box whose rules pass goes")


func test_tee_markers_show_their_number() -> void:
	var m := _main_with(_course_with(2))
	assert_eq(m.course_view.hole_marker(2, HoleMarker.Kind.TEE).label_text(), "2")
	assert_eq(m.course_view.hole_marker(2, HoleMarker.Kind.PIN).label_text(), "", "the pin has no number")



func test_a_tee_number_keeps_its_screen_size_at_every_zoom() -> void:
	var m := _main_with(_course_with(2))
	var tee: HoleMarker = m.course_view.hole_marker(1, HoleMarker.Kind.TEE)
	var at_1x: float = ThemeDB.fallback_font.get_height(tee.number_font_size)
	for index: int in m.camera.tuning.zoom_levels.size():
		m.camera.set_zoom_index(index)
		await wait_process_frames(2)
		var zoom: float = m.course_view.get_global_transform_with_canvas().get_scale().x
		assert_almost_eq(zoom, m.camera.zoom.x, 0.001, "the camera drives the view")
		assert_almost_eq(tee.label_screen_height(zoom), at_1x, 0.01, "%.1fx: as tall as at 1x" % zoom)
	m.course_view.refresh_holes()
	tee = m.course_view.hole_marker(1, HoleMarker.Kind.TEE)
	assert_almost_eq(tee.label_screen_height(m.camera.zoom.x), at_1x, 0.01, "a rebuilt marker too")

## E3-S9 (D45): at the farthest step, 0.175x, a tee marker and pin keep their 0.5x size on
## screen and draw over the terrain, so a tile in front does not cut them; at 0.5x and nearer
## they are drawn at their own size and sort with the terrain as before.
func test_hole_markers_keep_their_half_size_at_the_farthest_step() -> void:
	var m := _main_with(_course_with(2))
	var min_scale: float = BuilderTuning.load_default().marker_min_screen_scale
	assert_eq(min_scale, 0.5, "from the tuning resource")
	for z: float in m.camera.tuning.zoom_levels:
		m.camera.set_zoom_level(z)
		await wait_process_frames(2)
		for kind: HoleMarker.Kind in [HoleMarker.Kind.TEE, HoleMarker.Kind.PIN]:
			var marker: HoleMarker = m.course_view.hole_marker(1, kind)
			var on_screen: float = marker.shape_scale * z
			if z < min_scale:
				assert_almost_eq(on_screen, min_scale, 0.001, "%.3fx: shown as at 0.5x" % z)
				assert_eq(marker.z_index, 1, "%.3fx: over the terrain" % z)
			else:
				assert_eq(marker.shape_scale, 1.0, "%.3fx: its own size" % z)
				assert_eq(marker.z_index, 0, "%.3fx: sorted with the terrain" % z)
	m.course_view.refresh_holes()
	var rebuilt: HoleMarker = m.course_view.hole_marker(1, HoleMarker.Kind.PIN)
	assert_almost_eq(rebuilt.shape_scale * m.camera.zoom.x, maxf(min_scale, m.camera.zoom.x), 0.001,
			"a rebuilt marker too")

## E3-S9 review (D45): where the markers grow over the terrain (z 1) the ball and the guests
## go to z 1 too, so they still Y-sort with them: a ball resting on its tee at 0.175x draws over
## the tee's blocks and hole number (same sort key, drawn after), as it does at 0.5x.
func test_the_ball_on_its_tee_draws_over_the_tee_at_every_zoom() -> void:
	var m := _main_with(_course_with(2))
	m.set_mode(Main.Mode.PLAY)
	await wait_process_frames(2)
	var shot: ShotView = m.shot_view
	assert_true(shot.visible and shot.ball != null, "the ball rests on hole 1's tee")
	var tee: HoleMarker = m.course_view.hole_marker(1, HoleMarker.Kind.TEE)
	var min_scale: float = BuilderTuning.load_default().marker_min_screen_scale
	var holes_index: int = tee.get_parent().get_index()
	assert_gt(shot.get_index(), holes_index, "ties go to the ball: it comes after the markers")
	assert_gt(m.guest_view.get_index(), holes_index, "and so do the guests")
	for z: float in m.camera.tuning.zoom_levels:
		m.camera.set_zoom_level(z)
		await wait_process_frames(2)
		var want: int = 1 if z < min_scale else 0
		assert_eq(tee.z_index, want, "%.3fx: the tee" % z)
		assert_eq(shot.sprite.z_index + shot.z_index, tee.z_index, "%.3fx: the ball at the tee's z" % z)
		assert_eq(m.guest_view.z_index, tee.z_index, "%.3fx: the guests at the markers' z" % z)
		assert_true(shot.sprite.position.y >= tee.sort_key() - 0.001,
				"%.3fx: the ball sorts no earlier than its tee" % z)

# --- collapsing the list (E3-S10) ---

func test_collapsing_and_expanding_keep_the_pick() -> void:
	var m := _main_with(_course_with(3))
	var panel: HolePanel = m.hole_panel
	panel.row_for(2).pick_button.pressed.emit()
	assert_false(panel.collapsed, "the list starts expanded")
	assert_eq(panel.listed_rows().size(), 3)
	panel.collapse_button.pressed.emit()
	assert_true(panel.collapsed, "one click collapses it")
	assert_eq(m.build_tool.hole_number, 2, "the pick stays")
	var listed: Array[HolePanel.HoleRow] = panel.listed_rows()
	assert_eq(listed.size(), 1, "a collapsed list shows the picked hole alone")
	assert_eq(listed[0].number, 2)
	assert_true(listed[0].pick_button.button_pressed)
	assert_string_contains(listed[0].pick_button.text, "open", "with its status")
	assert_eq(panel.shown_rows().size(), 3, "every hole still has its row")
	listed[0].open_button.pressed.emit()
	assert_false(m.build_tool.builder.hole(2).open, "the collapsed row still closes its hole")
	assert_string_contains(panel.listed_rows()[0].pick_button.text, "closed")
	m.build_tool.select_hole(3)
	assert_eq(panel.listed_rows()[0].number, 3, "a collapsed list follows the pick")
	panel.collapse_button.pressed.emit()
	assert_false(panel.collapsed, "one click expands it")
	assert_eq(panel.listed_rows().size(), 3)
	assert_eq(m.build_tool.hole_number, 3, "the pick stays")
	assert_true(panel.row_for(3).pick_button.button_pressed)
	assert_false(panel.row_for(2).pick_button.button_pressed)


func test_a_collapsed_list_says_how_many_holes_it_hides() -> void:
	var m := _main_with(_course_with(3))
	var panel: HolePanel = m.hole_panel
	panel.collapse_button.pressed.emit()
	assert_string_contains(panel.collapse_button.text, "3", "it names the hole count")
	m.hole_panel.new_hole_button.pressed.emit()
	assert_eq(panel.listed_rows().size(), 0, "hole 4 has no row until its tee is down")
	assert_string_contains(panel.title_label.text, "Hole 4", "the details still name the pick")


## Every nine_holes hole failing rules 2 and 4 (cup on rough, wrong par): two issue lines each.
func _nine_failing(m: Main) -> void:
	var b: CourseBuilder = m.build_tool.builder
	for spec: Array in NineHoles.HOLES:
		b.paint(spec[3], Surface.Type.ROUGH, 1)
		b.set_par(spec[0], 5 if spec[1] != 5 else 3)


func test_a_collapsed_panel_stays_under_its_limit_with_nine_failing_holes() -> void:
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	var m := _main_with(c)
	m.camera.view_size_override = Vector2(1280, 720)
	_nine_failing(m)
	var panel: HolePanel = m.hole_panel
	var limit: float = panel.tuning.max_height
	assert_gt(limit, 0.0)
	for n: int in range(1, 10):
		m.build_tool.select_hole(n)
		assert_eq(m.build_tool.builder.issues_for(n).size(), 2, "hole %d fails two rules" % n)
		var open_h: float = m._hud_rect(panel).size.y
		assert_gt(open_h, limit, "hole %d: expanded, nine rows and the issues pass the limit" % n)
		panel.collapse_button.pressed.emit()
		var shut_h: float = m._hud_rect(panel).size.y
		assert_lte(shut_h, limit, "hole %d: collapsed, %.0f px is under %.0f" % [n, shut_h, limit])
		assert_lt(m._hud_rect(panel).end.y, 720.0 - m._hud_rect(m.build_palette).size.y,
				"and clear of the palette")
		gut.p("E3-S10: hole %d panel %.0f px expanded, %.0f px collapsed" % [n, open_h, shut_h])
		panel.collapse_button.pressed.emit()


## The most a nine_holes hole can fail at once: its cup on water (rules 2 and 3, with rule 3's
## long reason wrapping), the wrong par (rule 4) and its tee and cup on land the player does not own (both rule 6 lines,
## as on a New course).
func _nine_failing_worst() -> CourseData:
	var c: CourseData = NineHoles.land(7)
	var b := CourseBuilder.new(c)
	NineHoles.build(b)
	for spec: Array in NineHoles.HOLES:
		b.paint(spec[3], Surface.Type.WATER, 1)
		b.set_par(spec[0], 5 if spec[1] != 5 else 3)
	for spec: Array in NineHoles.HOLES:
		for cell: Vector2i in [spec[2], spec[3]]:
			c.set_parcel_owned(c.parcel_of(cell.x, cell.y), false)
	return c


func test_a_collapsed_panel_stays_under_its_limit_whatever_the_hole_fails() -> void:
	var m := _main_with(_nine_failing_worst())
	m.camera.view_size_override = Vector2(1280, 720)
	var panel: HolePanel = m.hole_panel
	var limit: float = panel.tuning.max_height
	panel.collapse_button.pressed.emit()
	for n: int in range(1, 10):
		m.build_tool.select_hole(n)
		var rules: Array[int] = []
		for issue: CourseValidator.Issue in m.build_tool.builder.issues_for(n):
			rules.append(issue.rule)
		for want: int in [2, 3, 4, 6]:
			assert_has(rules, want, "hole %d fails rule %d" % [n, want])
		assert_eq(rules.count(6), 2, "hole %d: both rule 6 lines" % n)
		var shut_h: float = m._hud_rect(panel).size.y
		assert_lte(shut_h, limit, "hole %d: collapsed, %.0f px is under %.0f" % [n, shut_h, limit])
		assert_false(panel.issues_label.text.contains("\n"), "hole %d: one summary line (E3-S27)" % n)
		assert_string_starts_with(panel.issues_label.text, "Fails rules 2, 3, 4 and 6")
		assert_eq(panel.issues_label.tooltip_text.count("\n") + 1, rules.size(),
				"hole %d: every issue is still on hover" % n)
		gut.p("E3-S27: hole %d fails %s: issue line %.0f px, panel %.0f px collapsed"
				% [n, rules, panel.issues_label.get_combined_minimum_size().y, shut_h])
	panel.collapse_button.pressed.emit()
	assert_eq(panel.issues_label.text.count("\n") + 1, 5, "expanded, the issues show in full")
	assert_eq(panel.issues_label.tooltip_text, "")


## E3-S27: collapsed, the issue text is one summary line at text_width, cut with an ellipsis,
## so a long text and a short one give the panel one width (no wrap, no scrollbar), and with
## two failing rules the panel is short enough (under 185 px) for the strip under it to win.
func test_a_collapsed_panels_width_is_the_same_with_long_and_short_issue_text() -> void:
	var m := _nine_main()
	var panel: HolePanel = m.hole_panel
	var b: CourseBuilder = m.build_tool.builder
	panel.collapse_button.pressed.emit()
	m.build_tool.select_hole(2)
	var none_w: float = m._hud_rect(panel).size.x
	b.set_par(2, 5)  # one short rule 4 line
	assert_eq(b.issues_for(2).size(), 1)
	var short_w: float = m._hud_rect(panel).size.x
	var short_text: String = panel.issues_label.text
	assert_string_starts_with(short_text, "rule 4: ", "one rule: its reason")
	# The most a hole fails (rules 2, 3 with its long reason, 4 and both 6 lines).
	var worst := _main_with(_nine_failing_worst())
	worst.camera.view_size_override = Vector2(1280, 720)
	worst.hole_panel.collapse_button.pressed.emit()
	worst.build_tool.select_hole(2)
	assert_eq(worst.build_tool.builder.issues_for(2).size(), 5)
	var long_w: float = worst._hud_rect(worst.hole_panel).size.x
	panel = worst.hole_panel
	assert_gt(panel.issues_label.tooltip_text.length(), short_text.length() * 3, "a far longer text")
	assert_false(panel.issues_label.text.contains("\n"))
	assert_almost_eq(long_w, short_w, 0.5, "a long text does not widen the panel")
	assert_almost_eq(short_w, none_w, 0.5, "nor a short one")
	# A single long reason is cut at text_width, not wrapped or widened.
	var lone: Array[CourseValidator.Issue] = [CourseValidator.Issue.new(3, Vector2i.ZERO,
			"no way from the tee to the green over playable ground, ".repeat(4))]
	panel.issues_label.text = HolePanel.issues_summary(lone)
	assert_almost_eq(panel.issues_label.get_combined_minimum_size().x, panel.text_width, 0.5,
			"a cut line keeps text_width")
	gut.p("E3-S27: collapsed panel %.0f px wide with no, short and long issue text" % long_w)


func test_a_collapsed_panel_with_two_failing_rules_frees_the_strip_under_it() -> void:
	var m := _nine_main()
	var panel: HolePanel = m.hole_panel
	_nine_failing(m)
	panel.collapse_button.pressed.emit()
	for n: int in range(1, 10):
		m.build_tool.select_hole(n)
		assert_eq(m.build_tool.builder.issues_for(n).size(), 2, "hole %d fails two rules" % n)
		var h: float = m._hud_rect(panel).size.y
		assert_lt(h, 185.0, "hole %d: collapsed with two rules, %.0f px is under 185" % [n, h])
		var strips: Array[Rect2] = m.free_view_rects()
		assert_gt(strips[1].get_area(), strips[0].get_area(),
				"hole %d: the strip under the panel is the larger" % n)
		assert_eq(m.free_view_rect(), strips[1])
		gut.p("E3-S27: hole %d collapsed with two rules: %.0f px" % [n, h])


func test_a_collapsed_list_frames_a_hole_under_the_panel_when_it_fits_nearer() -> void:
	# Nine par 3s on the plot, each failing rule 4 (issue text), and hole 9 turned to run across
	# the screen: 13 tiles each way, about 830 px wide at 1x, too wide for the strip beside the
	# panel but not for the strip under the collapsed one. (Before E3-S27's one-line summary
	# the issue text kept the strip beside the panel the larger; free_view_rect_for still picks
	# the strip that frames nearer whichever is larger.)
	var c := _plot()
	var b := CourseBuilder.new(c)
	_build(b, 9, false)
	assert_true(b.place_tee(9, Vector2i(4, 66), 3))
	assert_true(b.place_cup(9, Vector2i(17, 53)))
	for n: int in range(1, 10):
		b.set_par(n, 5)
	var m := _main_with(c)
	m.camera.view_size_override = Vector2(1280, 720)
	var panel: HolePanel = m.hole_panel
	var cam: CourseCamera = m.camera
	var open_zoom: Array[float] = []
	for n: int in range(1, 10):
		assert_false(m.build_tool.builder.issues_for(n).is_empty(), "hole %d has issue text" % n)
		m.frame_hole(n)
		open_zoom.append(cam.zoom.x)
	assert_eq(open_zoom[8], 0.5, "expanded, hole 9 frames at 0.5x")
	panel.collapse_button.pressed.emit()
	var strips: Array[Rect2] = []
	for n: int in range(1, 10):
		var h: HoleData = m.build_tool.builder.hole(n)
		assert_true(m.frame_hole(n))
		strips = m.free_view_rects()  # the picked hole's issue text sets the panel's height
		var tee_w: Vector2 = m.tile_world(h.tee)
		var cup_w: Vector2 = m.tile_world(h.cup)
		var free: Rect2 = m.free_view_rect_for(tee_w, cup_w)
		assert_true(free == strips[0] or free == strips[1], "hole %d frames in one of the strips" % n)
		if n == 9:
			assert_gt(strips[1].get_area(), strips[0].get_area(),
					"hole 9's one-line issue summary leaves the strip under the panel the larger (E3-S27)")
			assert_eq(free, strips[1], "yet hole 9 frames in the strip under the panel")
			assert_eq(cam.zoom.x, 1.0, "nearer than expanded")
		assert_gte(cam.zoom.x, open_zoom[n - 1], "hole %d: collapsing never frames it farther out" % n)
		var inner: Rect2 = free.grow(-cam.tuning.aim_frame_margin + 0.5)
		for at: Vector2 in [cam.screen_point(tee_w), cam.screen_point(cup_w)]:
			assert_true(inner.has_point(at), "hole %d: %s shows in the free view %s" % [n, at, free])
			for ctl: Control in m.hud_controls():
				assert_false(m._hud_rect(ctl).has_point(at), "hole %d: %s does not cover it" % [n, ctl.name])
		for ctl: Control in m.hud_controls():
			assert_false(free.intersects(m._hud_rect(ctl)), "hole %d: the free view misses %s" % [n, ctl.name])


func test_the_free_view_follows_the_panel_height() -> void:
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	var m := _main_with(c)
	m.camera.view_size_override = Vector2(1280, 720)
	var panel: HolePanel = m.hole_panel
	var open_free: Rect2 = m.free_view_rect()
	panel.collapse_button.pressed.emit()
	var shut_free: Rect2 = m.free_view_rect()
	var shut_panel: Rect2 = m._hud_rect(panel)
	assert_gt(shut_free.get_area(), open_free.get_area(), "a short panel frees more of the view")
	assert_gt(shut_free.end.x, shut_panel.position.x, "the free view runs under the collapsed panel")
	for ctl: Control in m.hud_controls():
		assert_false(shut_free.intersects(m._hud_rect(ctl)), "it misses %s" % ctl.name)
	assert_true(m.frame_hole(2))
	var cam: CourseCamera = m.camera
	var inner: Rect2 = m.free_view_rect_for(m.tile_world(c.holes[1].tee), m.tile_world(c.holes[1].cup)).grow(-cam.tuning.aim_frame_margin + 0.5)
	for cell: Vector2i in [c.holes[1].tee, c.holes[1].cup]:
		var at: Vector2 = cam.screen_point(m.tile_world(cell))
		assert_true(inner.has_point(at), "hole 2's %s shows in the free view" % cell)
		assert_false(m._hud_rect(panel).has_point(at), "not under the panel")
	panel.collapse_button.pressed.emit()
	assert_eq(m.free_view_rect(), open_free, "expanding gives the old free view back")


# --- framing hole 1 ---

func test_loading_a_course_with_holes_frames_hole_one() -> void:
	var c := _course_with(3)
	var b := CourseBuilder.new(c)
	b.renumber_hole(1, 2)  # hole 1 is the second row now
	var m := _main_with(c)
	var h: HoleData = b.hole(1)
	var free: Rect2 = m.free_view_rect_for(m.tile_world(h.tee), m.tile_world(h.cup))
	assert_true(free.has_area(), "the HUD leaves part of the view free")
	var view := Rect2(Vector2.ZERO, m.camera.view_size())
	assert_lt(free.size.x, view.size.x, "the left column and the hole panel are taken off")
	assert_lt(free.size.y, view.size.y, "and the palette")
	var tee: Vector2 = _screen_of(m, h.tee)
	var cup: Vector2 = _screen_of(m, h.cup)
	assert_almost_eq((tee + cup) * 0.5, free.get_center(), Vector2(0.5, 0.5),
			"the camera centres hole 1 in the free part of the view")
	var inner: Rect2 = free.grow(-m.camera.tuning.aim_frame_margin + 0.5)
	assert_true(inner.has_point(tee), "its tee %s is clear of the HUD %s" % [tee, free])
	assert_true(inner.has_point(cup), "and its cup %s" % cup)
	assert_eq(m.build_tool.hole_number, 1, "and picks it in the list")


## E3-S9 (D45): hole 1 of nine_holes, a 380 yd par 4, is too long for 0.5x; loading frames it
## at the farthest step with its tee and cup both clear of the HUD.
func test_a_long_hole_one_frames_tee_and_cup_clear_of_the_hud() -> void:
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	var m := _main_with(c)
	assert_eq(m.camera.zoom.x, m.camera.tuning.zoom_levels[0], "framed at the farthest zoom")
	var free: Rect2 = m.free_view_rect_for(m.tile_world(c.holes[0].tee), m.tile_world(c.holes[0].cup))
	for cell: Vector2i in [c.holes[0].tee, c.holes[0].cup]:
		var at: Vector2 = _screen_of(m, cell)
		assert_true(free.grow(-m.camera.tuning.aim_frame_margin + 0.5).has_point(at),
				"hole 1's %s at %s shows inside %s" % [cell, at, free])
		for ctl: Control in [m.mode_button, m.new_sandbox_button, m.hole_panel, m.build_palette]:
			assert_false(m._hud_rect(ctl).has_point(at), "%s does not cover it" % ctl.name)


## Where tile `cell`'s top centre shows on screen in `m`.
func _screen_of(m: Main, cell: Vector2i) -> Vector2:
	var at: Vector2 = Iso.tile_to_screen(Vector2(cell), m.course.get_height(cell.x, cell.y))
	return m.camera.screen_point(m.camera.get_parent().to_local(m.course_view.to_global(at)))


func test_a_course_with_no_holes_still_frames_its_centre() -> void:
	var m := _main_with(_plot())
	var centre: Vector2 = m.course_view.screen_bounds().get_center()
	assert_almost_eq(m.camera.position, m.camera._clamped(centre), Vector2(0.5, 0.5))
	assert_eq(m.camera.zoom, Vector2.ONE, "at 1x")


# --- a New course (D30) ---

func test_on_a_new_course_the_list_works_with_owned_land() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.start_seed = 7
	add_child_autofree(m)
	var b: CourseBuilder = m.build_tool.builder
	var block := LandGenerator.start_block(m.course.width, m.course.height)
	var tool: BuildTool = m.build_tool
	m.hole_panel.new_hole_button.pressed.emit()
	assert_eq(tool.hole_number, 1)
	_click(m, block.position + Vector2i(4, 4))
	tool.select_tool(BuildTool.Tool.CUP)
	_click(m, block.position + Vector2i(26, 4))
	m.hole_panel.new_hole_button.pressed.emit()
	assert_eq(tool.hole_number, 2)
	_click(m, block.position + Vector2i(4, 20))
	tool.select_tool(BuildTool.Tool.CUP)
	_click(m, block.position + Vector2i(26, 20))
	assert_eq(m.hole_panel.shown_rows().size(), 2, "two holes on the starting block")
	m.hole_panel.new_hole_button.pressed.emit()
	watch_signals(b)
	_click(m, Vector2i(5, 5))
	assert_signal_emitted_with_parameters(b, "refused", [CourseBuilder.NOT_YOUR_LAND])
	assert_null(b.hole(3), "no hole 3 on land the player does not own")
	assert_eq(m.hole_panel.shown_rows().size(), 2)
	m.hole_panel.row_for(2).play_button.pressed.emit()
	assert_eq(m.swing_control.hole.number, 2, "and plays hole 2")


## A course JSON text holding holes numbered `numbers`, every one a par 3 on its own row.
func _file_with(numbers: Array) -> String:
	var c := _plot()
	var hs: Array[HoleData] = []
	for k: int in numbers.size():
		hs.append(HoleData.new(numbers[k], 3, _tee(k % 9), _cup(k % 9) + Vector2i(0, k / 9), false))
	c.set_holes(hs)
	return JSON.stringify(c.to_dict())


func test_a_file_must_hold_at_most_nine_holes_numbered_1_to_9() -> void:
	var errors: Array[String] = []
	assert_not_null(CourseSave.from_json(_file_with([1, 2, 3, 4, 5, 6, 7, 8, 9]), errors), "nine load: %s" % [errors])
	for numbers: Array in [[1, 12], [0, 1], [1, 2, 3, 4, 5, 6, 7, 8, 9, 1]]:
		errors.clear()
		assert_null(CourseSave.from_json(_file_with(numbers), errors), "%s is refused" % [numbers])
		assert_string_contains(" ".join(errors), "holes", "and says why")
	errors.clear()
	var dup := CourseSave.from_json(_file_with([1, 1, 2]), errors)
	assert_not_null(dup, "a shared number loads: %s" % [errors])
	var issues: Dictionary = CourseValidator.new().check_course(dup)
	assert_true((issues[1] as Array).any(func(i: CourseValidator.Issue) -> bool: return i.rule == 1),
		"and fails rule 1")


# --- duplicate numbers (E3-S11) ---

## A loaded course (through course/save.gd) with three par 3s on rows 0, 1 and 2, numbered 1,
## 2 and 2: the second and third share number 2, in slots 1 and 2, every cup on a green.
func _main_with_duplicate() -> Main:
	var c := _course_with(3)
	var data: Dictionary = c.to_dict()
	(data["holes"] as Array)[2]["number"] = 2
	var errors: Array[String] = []
	var loaded := CourseSave.from_json(JSON.stringify(data), errors)
	assert_not_null(loaded, "a shared number loads: %s" % [errors])
	return _main_with(loaded)


func test_a_loaded_duplicate_number_lists_both_holes() -> void:
	var m := _main_with_duplicate()
	var panel: HolePanel = m.hole_panel
	var rows: Array[HolePanel.HoleRow] = panel.shown_rows()
	assert_eq(rows.size(), 3, "one row per hole, not per number")
	assert_eq([rows[0].number, rows[1].number, rows[2].number], [1, 2, 2])
	assert_eq(panel.rows_for(2).size(), 2)
	assert_false(rows[0].duplicate)
	assert_false(rows[0].duplicate_label.visible)
	for k: int in [1, 2]:
		var r: HolePanel.HoleRow = rows[k]
		assert_eq(r.slot, k, "row %d shows its own hole" % k)
		assert_true(r.duplicate, "row %d is marked a duplicate" % k)
		assert_string_contains(r.pick_button.tooltip_text, "rule 1", "its pick says why too")
		assert_true(r.duplicate_label.visible)
	# E3-S41: the same words as the map's box on each one's own tee.
	assert_eq(rows[1].duplicate_label.text, "Duplicate number. rule 1: shares number 2 with hole 2b",
			"each names the other as the map labels it")
	assert_eq(rows[2].duplicate_label.text, "Duplicate number. rule 1: shares number 2 with hole 2a")
	assert_eq(panel.collapse_button.text, "Hide the list (3 holes)")


## E3-S27: two holes sharing a number are told apart by a letter in course order, on their tee
## markers, their issue boxes, their rows and the details' title.
func test_duplicates_are_told_apart_on_the_map_and_in_the_list() -> void:
	var m := _main_with_duplicate()
	var c: CourseData = m.course
	assert_eq([c.hole_label(0), c.hole_label(1), c.hole_label(2)], ["1", "2a", "2b"])
	var tees := PackedStringArray()
	for marker: HoleMarker in m.course_view.hole_markers():
		if marker.kind == HoleMarker.Kind.TEE:
			tees.append(marker.label_text())
	assert_eq(tees, PackedStringArray(["1", "2a", "2b"]), "two tees marked 2 read 2a and 2b")
	var named := PackedStringArray()
	for box: IssueMarker in m.course_view.issue_markers():
		for line: String in box.lines():
			named.append(line.get_slice(",", 0))
	assert_has(named, "hole 2a", "the first duplicate's issue box")
	assert_has(named, "hole 2b", "the second's")
	assert_false(named.has("hole 2"), "no box names a bare 2")
	var rows: Array[HolePanel.HoleRow] = m.hole_panel.shown_rows()
	assert_string_starts_with(rows[0].pick_button.text, "1  ")
	assert_string_starts_with(rows[1].pick_button.text, "2a  ")
	assert_string_starts_with(rows[2].pick_button.text, "2b  ")
	rows[2].pick_button.pressed.emit()
	assert_string_starts_with(m.hole_panel.title_label.text, "Hole 2b")
	m.hole_panel.rows_for(2)[1].down_button.pressed.emit()
	assert_eq([c.hole_label(1), c.hole_label(2)], ["2", "3"], "parted, plain numbers again")
	assert_eq(m.course_view.hole_marker(3, HoleMarker.Kind.TEE).label_text(), "3")


## E3-S27 review, E3-S41: rule 1 puts each duplicate's issue on its own tee, so the box there
## names the hole whose tee it stands on and the twin it shares the number with: never "hole 2b"
## on the tee marked 2a. The validator's reason is the box's words, so the panel rows and
## /course-file read the same.
func test_each_duplicate_box_names_the_tee_under_it() -> void:
	var m := _main_with_duplicate()
	var tee_label := {}
	for marker: HoleMarker in m.course_view.hole_markers():
		if marker.kind == HoleMarker.Kind.TEE:
			tee_label[marker.cell] = marker.label_text()
	var checked: int = 0
	for box: IssueMarker in m.course_view.issue_markers():
		for i: int in box.rules.size():
			if box.rules[i] != 1:
				continue
			assert_true(tee_label.has(box.cell), "a rule-1 box stands on a tee")
			var own: String = tee_label.get(box.cell, "?")
			var twin: String = "2b" if own == "2a" else "2a"
			assert_eq(box.lines()[i], "hole %s, rule 1: shares number 2 with hole %s" % [own, twin])
			assert_eq(box.cell, _tee(1) if own == "2a" else _tee(2), "on hole %s's own tee" % own)
			checked += 1
	assert_eq(checked, 2, "one rule-1 box per duplicate")

func test_renumbering_one_duplicate_leaves_the_other_in_place() -> void:
	var m := _main_with_duplicate()
	var panel: HolePanel = m.hole_panel
	var b: CourseBuilder = m.build_tool.builder
	assert_false(panel.rows_for(2)[1].down_button.disabled, "3 is free below")
	assert_true(panel.rows_for(2)[1].up_button.disabled, "nothing is free above: 1 is taken")
	panel.rows_for(2)[1].down_button.pressed.emit()
	assert_eq(b.hole_at(1).number, 2, "the other duplicate keeps number 2")
	assert_eq(b.hole_at(1).tee, _tee(1))
	assert_eq(b.hole_at(2).number, 3, "the renumbered one parts")
	assert_eq(b.hole_at(2).tee, _tee(2))
	assert_eq(b.hole_at(0).number, 1, "hole 1 is untouched")
	var rows: Array[HolePanel.HoleRow] = panel.shown_rows()
	assert_eq([rows[0].number, rows[1].number, rows[2].number], [1, 2, 3])
	for r: HolePanel.HoleRow in rows:
		assert_false(r.duplicate, "hole %d is no longer a duplicate" % r.number)
		assert_false(r.duplicate_label.visible)
	assert_false(1 in _rules(b.issues_for(2)), "rule 1 passes for both")
	assert_false(1 in _rules(b.issues_for(3)))
	m.build_tool.undo()
	assert_eq(b.hole_at(2).number, 2, "undo brings the duplicate back")
	assert_true(panel.rows_for(2)[1].duplicate)


func test_renumbering_the_first_duplicate_moves_only_it() -> void:
	var m := _main_with_duplicate()
	var b: CourseBuilder = m.build_tool.builder
	m.hole_panel.rows_for(2)[0].down_button.pressed.emit()
	assert_eq(b.hole_at(1).number, 3, "the first duplicate moved to the free 3")
	assert_eq(b.hole_at(2).number, 2, "the second stays at 2")


func test_builder_renumbers_one_slot_of_a_shared_number() -> void:
	var m := _main_with_duplicate()
	var b: CourseBuilder = m.build_tool.builder
	assert_true(b.renumber_hole(2, 1, 2), "slot 2 to number 1, swapping hole 1 onto 2")
	assert_eq([b.hole_at(0).number, b.hole_at(1).number, b.hole_at(2).number], [2, 2, 1],
			"slot 1 kept its number; only slot 2 and hole 1 swapped")
	assert_eq(b.slot_of(2), 0, "a stale or missing slot falls back to the first with the number")
	assert_eq(b.slot_of(2, 1), 1)
	assert_eq(b.slot_of(2, 2), 0, "slot 2 holds hole 1 now")


func test_picking_a_duplicate_row_builds_its_own_hole() -> void:
	var m := _main_with_duplicate()
	var panel: HolePanel = m.hole_panel
	var b: CourseBuilder = m.build_tool.builder
	panel.rows_for(2)[1].pick_button.pressed.emit()
	assert_eq(m.build_tool.hole_number, 2)
	assert_eq(m.build_tool.picked_slot(), 2, "the second hole numbered 2")
	assert_true(panel.rows_for(2)[1].pick_button.button_pressed, "its row shows the pick")
	assert_false(panel.rows_for(2)[0].pick_button.button_pressed, "its twin's does not")
	assert_string_contains(panel.issues_label.text, "shares number 2 with hole 2a",
			"the details show its own rule 1, naming its twin")
	m.build_tool.select_tool(BuildTool.Tool.TEE)
	_click(m, Vector2i(4, 17))
	assert_eq(b.hole_at(2).tee, Vector2i(4, 17), "the tee tool moved the picked duplicate's tee")
	assert_eq(b.hole_at(1).tee, _tee(1), "and left its twin's")
	m.build_tool.select_par(4)
	assert_eq(b.hole_at(2).par, 4, "par goes to the picked duplicate")
	assert_eq(b.hole_at(1).par, 3)
	panel.rows_for(2)[1].down_button.pressed.emit()
	assert_eq(m.build_tool.hole_number, 3, "the pick follows the duplicate it renumbered")
	assert_eq(m.build_tool.picked_hole().tee, Vector2i(4, 17))


func test_a_collapsed_list_shows_the_picked_duplicate() -> void:
	var m := _main_with_duplicate()
	var panel: HolePanel = m.hole_panel
	panel.rows_for(2)[1].pick_button.pressed.emit()
	panel.set_collapsed(true)
	var listed: Array[HolePanel.HoleRow] = panel.listed_rows()
	assert_eq(listed.size(), 1)
	assert_eq(listed[0].slot, 2, "the picked duplicate's row, not its twin's")
	assert_true(listed[0].duplicate_label.visible)
	assert_false(panel.rows_for(2)[0].duplicate_label.visible, "the hidden twin's text hides too")


func test_a_duplicate_row_plays_its_own_hole() -> void:
	var m := _main_with_duplicate()
	m.hole_panel.rows_for(2)[1].play_button.pressed.emit()
	assert_eq(m.mode, Main.Mode.PLAY)
	var ypt: float = m.swing_control.field.yards_per_tile
	assert_almost_eq(m.swing_control.ball_at, (Vector2(_tee(2)) + Vector2(0.5, 0.5)) * ypt,
			Vector2(0.01, 0.01), "the ball sits on the second duplicate's tee")


func _rules(issues: Array[CourseValidator.Issue]) -> Array[int]:
	var out: Array[int] = []
	for i: CourseValidator.Issue in issues:
		out.append(i.rule)
	return out


## D47 (E3-S25): the list row and the panel's title quote the line of play.
func test_a_doglegs_row_shows_its_line_of_play() -> void:
	var c := ReactionHoles.dogleg_par4()
	assert_eq(HolePanel.row_text(c, c.holes[0]), "1  Par 4  450 yd  open")
	var m := _main_with(c)
	assert_string_contains(m.hole_panel.title_label.text, "450 yd")


# --- why guests complained (E3-S18) ---

## A guest's reaction to hole `number` of par `par`, judged as the brain judges it: a purist
## on a blind tee shot who waited 60 s and scored 9 (fair leads, pace and challenge follow),
## or with `praise` a casual guest's par.
func _verdict(number: int, par: int, praise: bool = false) -> GuestReaction:
	var t := GuestTuning.load_default()
	var g := Guest.new()
	g.skill = 10
	g.patience = 5
	g.taste = Guest.Taste.CASUAL if praise else Guest.Taste.PURIST
	var rec := Guest.HoleRecord.new()
	rec.number = number
	rec.par = par
	rec.score = par if praise else par + 5
	rec.wait_s = 0 if praise else 60
	var s := HoleChecks.Statics.new()
	s.blind = not praise
	s.hazard_on_line = true
	s.safe_route = true
	return GuestReaction.judge(g, rec, s, t)


## The longest complaint a hole can draw: an adventurer failing all four checks, its doubled
## interesting check leading with its taste's sentence.
func _worst_verdict(number: int, par: int) -> GuestReaction:
	var t := GuestTuning.load_default()
	var g := Guest.new()
	g.skill = 1
	g.patience = 0
	g.taste = Guest.Taste.ADVENTURER
	var rec := Guest.HoleRecord.new()
	rec.number = number
	rec.par = par
	rec.score = par + 9
	rec.wait_s = 99
	rec.walk_yd = 400.0
	var s := HoleChecks.Statics.new()
	s.blind = true
	s.target_is_zone = true
	s.hazard_on_line = true
	s.safe_route = false
	return GuestReaction.judge(g, rec, s, t)


func _nine_main() -> Main:
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	var m := _main_with(c)
	m.camera.view_size_override = Vector2(1280, 720)
	return m


func _give(m: Main, r: GuestReaction, second: int) -> void:
	m.guest_sim.feed.push(r, 1, second, GuestSim.hole_slot(m.course, r.hole_number))


func test_a_picked_hole_with_a_complaint_shows_its_lead_check() -> void:
	var m := _nine_main()
	var panel: HolePanel = m.hole_panel
	m.build_tool.select_hole(3)
	assert_false(panel.reaction_label.visible, "no guest has played hole 3: nothing to show")
	var r := _verdict(3, 5)
	assert_true(r.is_complaint())
	assert_eq(r.lead_check(), GuestReaction.Check.FAIR, "a purist's blind tee shot leads")
	assert_eq(r.failed().size(), 3)
	_give(m, r, 10)
	assert_true(panel.reaction_label.visible, "the picked hole shows its complaint at once")
	var shown: String = panel.reaction_label.text
	assert_string_starts_with(shown, "Complaint: blind from the tee",
			"led by the check that failed, in the guest's words")
	assert_string_contains(shown, "Also slow", "expanded, the whole line")
	assert_false(shown.begins_with("Hole"), "the panel already names the hole")
	assert_string_contains(panel.reaction_label.tooltip_text, "Failed: sight line, pace and difficulty.",
			"the tooltip names every failed check in the player's words")
	panel.set_collapsed(true)
	assert_eq(panel.reaction_label.text, "Complaint: blind from the tee, could not see the flag.",
			"collapsed, the lead sentence alone")
	assert_string_contains(panel.reaction_label.tooltip_text, "Also slow", "the rest on hover")
	m.build_tool.select_hole(4)
	assert_false(panel.reaction_label.visible, "another hole shows its own verdicts, here none")
	_give(m, _verdict(4, 3), 11)
	m.build_tool.select_hole(3)
	assert_string_contains(panel.reaction_label.text, "blind", "hole 3 keeps its own")
	# A neutral is quiet (D39); a newer praise does not hide a complaint still in the window
	# (E3-S18 review): the tag reads "+1 !1", and the panel says what to fix.
	var neutral := _verdict(3, 5, true)
	neutral.passed[GuestReaction.Check.PACE] = false
	neutral.kind = GuestReaction.Kind.NEUTRAL
	_give(m, neutral, 12)
	assert_string_contains(panel.reaction_label.text, "blind", "a neutral does not replace it")
	var praise := _verdict(3, 5, true)
	assert_true(praise.is_praise())
	_give(m, praise, 13)
	assert_string_starts_with(panel.reaction_label.text, "Complaint: blind",
			"a praise after a complaint leaves the complaint showing")
	# An edit clears the hole's verdicts (E3-S17): the panel no longer shows them.
	m.build_tool.builder.set_par(3, 4)
	assert_false(panel.reaction_label.visible, "an edited hole shows no stale verdict")
	# With no complaint in the window, its newest praise shows.
	_give(m, _verdict(3, 4, true), 14)
	assert_eq(panel.reaction_label.text, "Praise: loved it, 4 on a par 4.",
			"a hole guests only praised shows its praise")
	assert_false(panel.reaction_label.tooltip_text.contains("Failed"), "a praise failed nothing")


func test_a_collapsed_panel_with_a_complaint_stays_under_its_limit() -> void:
	var m := _main_with(_nine_failing_worst())
	m.camera.view_size_override = Vector2(1280, 720)
	var panel: HolePanel = m.hole_panel
	var limit: float = panel.tuning.max_height
	var second: int = 0
	for spec: Array in NineHoles.HOLES:
		second += 1
		_give(m, _worst_verdict(spec[0], spec[1]), second)
	panel.collapse_button.pressed.emit()
	for n: int in range(1, 10):
		m.build_tool.select_hole(n)
		var h: HoleData = m.build_tool.picked_hole()
		var r: GuestReaction = HolePanel.latest_reaction(m.guest_sim.feed, m.course, m.build_tool.picked_slot())
		assert_not_null(r, "hole %d has its complaint" % n)
		assert_eq(r.failed().size(), 4, "hole %d: all four checks failed" % n)
		assert_true(panel.reaction_label.visible)
		assert_string_starts_with(panel.reaction_label.text, "Complaint: no way round the trouble.",
				"hole %d: led by the adventurer's doubled check" % n)
		var shut: Rect2 = m._hud_rect(panel)
		assert_lte(shut.size.y, limit, "hole %d (par %d): collapsed, %.0f px is under %.0f"
				% [n, h.par, shut.size.y, limit])
		assert_lte(shut.end.x, 1280.0, "on screen")
		assert_true(panel.issues_label.visible and panel.issues_label.size.y >= 0.0
				and panel.issues_label.get_combined_minimum_size().y > 10.0,
				"hole %d: the issue line keeps its room beside the complaint" % n)
		gut.p("E3-S18: hole %d collapsed with its complaint: %.0f x %.0f px, reaction %.0f px"
				% [n, shut.size.x, shut.size.y, panel.reaction_label.get_combined_minimum_size().y])
