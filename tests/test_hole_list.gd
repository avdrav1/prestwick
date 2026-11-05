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
	var cut: int = 0
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
		var full: float = panel.issues_label.get_combined_minimum_size().y
		if full > panel.issues_scroll.custom_minimum_size.y + 0.5:
			cut += 1
		assert_eq(panel.issues_label.text.count("\n") + 1, rules.size(),
				"hole %d: every issue is still in the text, the rest scrolls" % n)
		gut.p("E3-S10: hole %d fails %s: issues %.0f px, shown %.0f, panel %.0f px collapsed"
				% [n, rules, full, panel.issues_scroll.custom_minimum_size.y, shut_h])
	assert_gt(cut, 0, "the worst case needs the issue text cut to stay under the limit")
	panel.collapse_button.pressed.emit()
	assert_almost_eq(panel.issues_scroll.custom_minimum_size.y,
			panel.issues_label.get_combined_minimum_size().y, 0.5, "expanded, the issues show in full")


func test_a_collapsed_list_frames_a_hole_under_the_panel_when_it_fits_nearer() -> void:
	# Nine par 3s on the plot, each failing rule 4 (issue text), and hole 9 turned to run across
	# the screen: 13 tiles each way, about 830 px wide at 1x, too wide for the strip beside the
	# panel but not for the strip under the collapsed one.
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
	assert_eq(open_zoom[8], 0.5, "expanded, hole 9 frames at the farthest zoom")
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
			assert_gt(strips[0].get_area(), strips[1].get_area(),
					"hole 9's issue text keeps the strip beside the collapsed panel the larger")
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
	var inner: Rect2 = m.free_view_rect().grow(-cam.tuning.aim_frame_margin + 0.5)
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
	var free: Rect2 = m.free_view_rect()
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


func test_a_hole_too_long_to_frame_keeps_its_tee_clear_of_the_hud() -> void:
	var c: CourseData = NineHoles.land(7)
	NineHoles.build(CourseBuilder.new(c))
	var m := _main_with(c)
	assert_eq(m.camera.zoom.x, m.camera.tuning.zoom_levels[0], "framed at the farthest zoom")
	var free: Rect2 = m.free_view_rect()
	var tee: Vector2 = _screen_of(m, c.holes[0].tee)
	assert_true(free.grow(-m.camera.tuning.aim_frame_margin + 0.5).has_point(tee),
			"hole 1's tee %s shows inside %s" % [tee, free])
	for ctl: Control in [m.mode_button, m.new_sandbox_button, m.hole_panel, m.build_palette]:
		assert_false(m._hud_rect(ctl).has_point(tee), "%s does not cover it" % ctl.name)


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
