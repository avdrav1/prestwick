extends GutTest
## E2-S3: opening a hole (D11). Open is enabled only when all six rules pass. An edit inside
## an open hole's footprint closes it; after every build edit the validator reruns for every
## open hole and closes any that now fails. Failing rules reach the view, tile and reason.
## E8-S1 (D64): a hole opens itself once every rule passes (unless closed by hand), so an edit
## in the footprint closes it only while the edit lasts.
## Play never waits for the validator (pillar 1).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## Hole 1 on an 80 x 40 rough plot at height 2: a 150 yd par 3 along y = 20. Its footprint
## is the capsule 6 tiles (30 yd) either side of the tee-to-cup segment.
const TEE := Vector2i(5, 20)
const CUP := Vector2i(35, 20)


func _course() -> CourseData:
	return CourseData.create(80, 40, Surface.Type.ROUGH, 2)


## A builder with hole 1 placed, its cup on a green, and opened.
func _open_par3(c: CourseData) -> CourseBuilder:
	var b := CourseBuilder.new(c)
	b.paint(CUP, Surface.Type.GREEN, 3)
	b.place_tee(1, TEE, 3)
	b.place_cup(1, CUP)
	assert_true(b.hole(1).open, "the par 3 opens itself (E8-S1, D64)")
	return b


func _rules(issues: Array) -> Array[int]:
	var out: Array[int] = []
	for i: CourseValidator.Issue in issues:
		out.append(i.rule)
	return out


func _paint_column(b: CourseBuilder, x: int, from_y: int, to_y: int, s: Surface.Type) -> void:
	b.level_water = false  # D66: a water column as a plain paint, not a flood
	b.begin_stroke()
	for y: int in range(from_y, to_y + 1):
		b.paint(Vector2i(x, y), s, 1)
	b.end_stroke()


# --- the footprint ---

func test_footprint_is_a_30_yd_capsule_round_the_segment() -> void:
	var v := CourseValidator.new()
	var c := _course()
	var h := HoleData.new(1, 3, TEE, CUP, false)
	assert_true(v.in_footprint(c, h, Vector2i(20, 20)), "on the line")
	assert_true(v.in_footprint(c, h, Vector2i(20, 26)), "30 yd beside it")
	assert_false(v.in_footprint(c, h, Vector2i(20, 27)), "35 yd beside it")
	assert_true(v.in_footprint(c, h, TEE + Vector2i(-5, 0)), "25 yd behind the tee")
	assert_true(v.in_footprint(c, h, TEE + Vector2i(-4, -4)), "28 yd off the tee corner")
	assert_false(v.in_footprint(c, h, Vector2i(TEE.x - 5, 15)), "35 yd off the tee corner")
	assert_true(v.in_footprint(c, h, CUP + Vector2i(6, 0)), "30 yd past the cup")
	var tiles: Array[Vector2i] = v.footprint(c, h)
	for t: Vector2i in tiles:
		assert_true(v.in_footprint(c, h, t), str(t))
	assert_true(Vector2i(20, 26) in tiles and not Vector2i(20, 27) in tiles)
	assert_eq(v.footprint(c, HoleData.new(1, 3, TEE, HoleData.UNPLACED)), [] as Array[Vector2i], "no cup, no footprint")


# --- open gating ---

func test_open_only_when_every_rule_passes() -> void:
	var c := _course()
	var b := CourseBuilder.new(c)
	assert_false(b.can_open(1), "no hole yet")
	b.place_tee(1, TEE, 3)
	assert_false(b.can_open(1), "no cup yet")
	assert_eq(_rules(b.issues_for(1)), [1] as Array[int])
	b.place_cup(1, CUP)
	assert_eq(_rules(b.issues_for(1)), [2] as Array[int], "the cup is on rough")
	assert_false(b.can_open(1))
	assert_false(b.open_hole(1), "Open refuses a failing hole")
	assert_false(b.hole(1).open)
	b.paint(CUP, Surface.Type.GREEN, 1)
	assert_eq(b.issues_for(1), [], "all six pass")
	assert_true(b.hole(1).open, "and it opens itself (E8-S1, D64)")
	assert_false(b.can_open(1), "already open")
	assert_false(b.open_hole(1))
	b.close_hole(1)
	assert_true(b.can_open(1), "closed by hand, Open is offered")
	assert_true(b.open_hole(1))
	assert_true(b.hole(1).open)
	b.undo()
	assert_false(b.hole(1).open, "Open is on the undo stack too")


func test_wrong_par_cannot_open() -> void:
	var c := _course()
	var b := CourseBuilder.new(c)
	b.paint(CUP, Surface.Type.GREEN, 1)
	b.place_tee(1, TEE, 4)
	b.place_cup(1, CUP)
	assert_eq(_rules(b.issues_for(1)), [4] as Array[int], "150 yd is a par 3")
	assert_false(b.hole(1).open)
	assert_false(b.open_hole(1))
	b.set_par(1, 3)
	assert_true(b.hole(1).open, "the right par opens it")


func test_a_course_brought_in_with_a_failing_open_hole_has_it_closed() -> void:
	var c := _course()
	var hs: Array[HoleData] = [HoleData.new(1, 3, TEE, CUP, true)]
	c.set_holes(hs)
	var b := CourseBuilder.new(c)
	assert_eq(_rules(b.issues_for(1)), [2] as Array[int], "the cup is on rough")
	assert_false(b.hole(1).open, "an open hole that fails a rule closes when the builder is made")
	assert_false(b.can_undo(), "closing it is not an undo step")


func test_a_course_brought_in_with_a_passing_open_hole_keeps_it_open() -> void:
	var c := _course()
	c.set_tile(CUP.x, CUP.y, 2, Surface.Type.GREEN)
	var hs: Array[HoleData] = [HoleData.new(1, 3, TEE, CUP, true)]
	c.set_holes(hs)
	var b := CourseBuilder.new(c)
	assert_true(b.hole(1).open)


## D33: a course saved before D33 (0.2.0's version 1, par 4 from 250 yd) with an open par 4
## of 250 to 319 yd loads, and the builder then closes it with a rule-4 issue. No migration
## re-pars it; the player sets it to par 3 and opens it again.
func test_a_pre_d33_open_short_par4_loads_closed_until_set_to_par3() -> void:
	var c := _course()
	var cup := Vector2i(61, 20) # 56 tiles from TEE: 280 yd
	c.set_tile(cup.x, cup.y, 2, Surface.Type.GREEN)
	var hs: Array[HoleData] = [HoleData.new(1, 4, TEE, cup, true)]
	c.set_holes(hs)
	var v1 := c.to_dict()
	v1["version"] = 1
	v1.erase("owned")
	v1.erase("land_budget")
	var errors: Array[String] = []
	var loaded := CourseSave.from_json(JSON.stringify(v1), errors)
	assert_not_null(loaded, "a version 1 file with a 280 yd par 4 loads: %s" % [errors])
	if loaded == null:
		return
	assert_eq(errors, [] as Array[String], "without errors")
	assert_true(loaded.holes[0].open, "it loads open")
	assert_eq(loaded.holes[0].par, 4, "and keeps its par")
	var b := CourseBuilder.new(loaded)
	assert_false(b.hole(1).open, "the builder closes it")
	assert_eq(_rules(b.issues_for(1)), [4] as Array[int], "280 yd is a par 3 since D33")
	assert_true(b.set_par(1, 3))
	assert_true(b.hole(1).open, "set to par 3 it opens itself")


## D47 (E3-S25): a course saved before rule 4 measured doglegs round their corner may hold
## an open par 4 whose line of play is a par 5's. The builder closes it on load and says so in
## one line per hole (closed_on_load), for the load notice (D35, E4-S7, E5-S5).
func test_a_dogleg_saved_as_a_straight_par4_loads_closed_with_a_notice_line() -> void:
	var c := CourseData.create(100, 70, Surface.Type.ROUGH, 1)
	var tee := Vector2i(6, 6)
	var corner := Vector2i(60, 6)
	var cup := Vector2i(60, 60)
	var painter := CourseBuilder.new(c)
	for leg: Array in [[tee, corner], [corner, cup]]:
		for cell: Vector2i in BuildTool.grid_line(leg[0], leg[1]):
			painter.paint(cell, Surface.Type.FAIRWAY, 5)
	painter.paint(cup, Surface.Type.GREEN, 5)
	var hs: Array[HoleData] = [HoleData.new(1, 4, tee, cup, true)]
	c.set_holes(hs)
	var errors: Array[String] = []
	var loaded := CourseSave.from_json(JSON.stringify(c.to_dict()), errors)
	assert_not_null(loaded, "it loads: %s" % [errors])
	if loaded == null:
		return
	assert_true(loaded.holes[0].open, "the file has it open, a par 4 by its 382 yd straight line")
	var b := CourseBuilder.new(loaded)
	assert_false(b.hole(1).open, "the builder closes it")
	assert_eq(_rules(b.issues_for(1)), [4] as Array[int])
	assert_eq(b.closed_on_load.size(), 1, "one notice line")
	if b.closed_on_load.size() == 1:
		assert_string_starts_with(b.closed_on_load[0],
				"Hole 1 closed: 512 yd round the dogleg is a par 5, not par 4")
	assert_true(b.set_par(1, 5))
	assert_true(b.hole(1).open, "set to par 5 it opens itself")
	assert_eq(b.closed_on_load.size(), 1, "the notice is the load's, not later edits'")


func test_a_course_that_loads_clean_has_no_notice_lines() -> void:
	var c := _course()
	c.set_tile(CUP.x, CUP.y, 2, Surface.Type.GREEN)
	var hs: Array[HoleData] = [HoleData.new(1, 3, TEE, CUP, true), HoleData.new(2, 4, TEE + Vector2i(0, 10), CUP + Vector2i(0, 10), false)]
	c.set_holes(hs)
	var b := CourseBuilder.new(c)
	assert_eq(b.closed_on_load, [] as Array[String], "hole 2 was closed already, hole 1 passes")


# --- an edit inside the footprint closes the hole ---

## E8-S1 (D64): the footprint closes it while a drag lasts; the rerun at its end opens it again
## when it still passes, so a click edit that keeps it legal leaves it open.
func test_an_edit_inside_the_footprint_closes_a_passing_hole_while_it_lasts() -> void:
	var c := _course()
	var b := _open_par3(c)
	b.begin_stroke()
	b.paint(Vector2i(20, 24), Surface.Type.FAIRWAY, 1)
	assert_false(b.hole(1).open, "a paint inside the footprint closes it")
	b.end_stroke()
	assert_eq(b.issues_for(1), [], "it still passes")
	assert_true(b.hole(1).open, "so it opens itself again as the drag ends")
	b.begin_stroke()
	b.raise(Vector2i(10, 21), 1)
	assert_false(b.hole(1).open, "a height edit closes it too")
	b.end_stroke()
	assert_true(b.hole(1).open)
	b.raise(Vector2i(12, 21), 1)
	assert_true(b.hole(1).open, "a click edit that keeps it legal leaves it open")


func test_an_edit_outside_the_footprint_leaves_it_open() -> void:
	var c := _course()
	var b := _open_par3(c)
	b.paint(Vector2i(20, 27), Surface.Type.BUNKER, 1)
	b.raise(Vector2i(70, 5), 3)
	b.lower(Vector2i(60, 35), 5)
	assert_true(b.hole(1).open)


func test_a_brush_reaching_into_the_footprint_closes_it() -> void:
	var c := _course()
	var b := _open_par3(c)
	b.begin_stroke()
	b.paint(Vector2i(20, 28), Surface.Type.BUNKER, 5)
	assert_false(b.hole(1).open, "the 5x5 brush's top row is at y 26")
	b.end_stroke()


func test_moving_its_own_tee_or_cup_closes_it_unless_it_still_passes() -> void:
	var c := _course()
	var b := _open_par3(c)
	b.place_tee(1, TEE + Vector2i(0, 1))
	assert_true(b.hole(1).open, "the tee moved and the hole still passes: open (D64)")
	b.place_cup(1, CUP + Vector2i(4, 0))
	assert_false(b.hole(1).open, "the cup moved off the green: closed")
	assert_eq(_rules(b.issues_for(1)), [2] as Array[int])
	b.place_cup(1, CUP)
	assert_true(b.hole(1).open, "back on the green: open again")


func test_undoing_the_edit_that_closed_it_restores_it() -> void:
	var c := _course()
	var b := _open_par3(c)
	var open_hash: String = c.content_hash()
	b.paint(CUP, Surface.Type.ROUGH, 1)
	assert_false(b.hole(1).open)
	b.undo()
	assert_true(b.hole(1).open, "undo puts the course back as it was, open hole included")
	assert_eq(c.content_hash(), open_hash)


# --- the rerun closes an open hole that now fails, wherever the edit was ---

func test_water_on_a_rule3_path_outside_the_footprint_closes_it() -> void:
	var c := _course()
	var b := _open_par3(c)
	# A lake across the whole capsule (y 14 to 26) and past it: inside the footprint, so it
	# closes the hole, but the path still goes round its ends.
	_paint_column(b, 20, 10, 30, Surface.Type.WATER)
	assert_eq(b.issues_for(1), [], "the path goes round the end of the lake")
	assert_true(b.hole(1).open, "so it opens again as the drag ends (D64)")
	# Water on the path round the top end, outside the footprint: still a path round the bottom.
	_paint_column(b, 20, 0, 9, Surface.Type.WATER)
	assert_true(b.hole(1).open, "outside the footprint and the hole still passes")
	# And round the bottom end: no path is left, so the rerun closes it.
	_paint_column(b, 20, 31, 39, Surface.Type.WATER)
	assert_false(b.hole(1).open, "the rerun closes a hole that now fails rule 3")
	# E14-S3 (D69): and rule 7, the lake cuts the green off from the tee's side on foot too.
	assert_eq(_rules(b.issues_for(1)), [3, 7] as Array[int])
	assert_false(b.can_open(1))


func test_another_holes_tee_moved_into_its_zone_closes_it() -> void:
	var c := _course()
	var b := CourseBuilder.new(c)
	# Hole 1: a 330 yd par 4 along y = 20 (320 yd is the shortest, D33), zone centre 240 yd
	# out at (53, 20).
	var cup1 := Vector2i(71, 20)
	b.paint(cup1, Surface.Type.GREEN, 3)
	b.place_tee(1, TEE, 4)
	b.place_cup(1, cup1)
	# Hole 2: a 150 yd par 3 along y = 35.
	b.paint(Vector2i(35, 35), Surface.Type.GREEN, 3)
	b.place_tee(2, Vector2i(5, 35), 3)
	b.place_cup(2, Vector2i(35, 35))
	assert_true(b.hole(1).open)
	assert_true(b.hole(2).open)
	b.place_tee(2, Vector2i(60, 26))
	assert_true(b.hole(1).open, "inside hole 1's footprint, outside its zone: another hole's tee is not hole 1's edit")
	b.place_tee(2, Vector2i(53, 24))
	assert_false(b.hole(1).open, "hole 2's tee in hole 1's zone closes hole 1")
	assert_true(5 in _rules(b.issues_for(1)))
	assert_true(5 in _rules(b.issues_for(2)), "both fail rule 5")
	assert_false(b.hole(2).open)


# --- the view and the HUD ---

func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	return m


func _click(m: Main, t: BuildTool.Tool, cell: Vector2i) -> void:
	m.build_tool.select_tool(t)
	m.build_tool.press_at(Iso.tile_to_screen(Vector2(cell), m.course.get_height(cell.x, cell.y)) + Vector2(0.5, 0.5))
	m.build_tool.release()


func test_a_failing_rule_reaches_the_view_with_its_tile_and_reason() -> void:
	var m := _main()
	_click(m, BuildTool.Tool.TEE, Vector2i(2, 10))
	_click(m, BuildTool.Tool.CUP, Vector2i(15, 10))
	var markers: Array[IssueMarker] = m.course_view.issue_markers()
	assert_eq(markers.size(), 1, "one failing rule, one highlight")
	var marker: IssueMarker = markers[0]
	assert_eq(marker.cell, Vector2i(15, 10), "rule 2's tile is the cup")
	assert_eq(marker.rules, PackedInt32Array([2]))
	assert_eq(marker.reasons, PackedStringArray(["cup is on rough, not green"]))
	assert_eq(marker.draw_point(), Iso.tile_to_screen(Vector2(15, 10), 0), "on the tile's top")
	var panel: HolePanel = m.hole_panel
	assert_true(panel.open_button.disabled, "Open is disabled while a rule fails")
	assert_string_contains(panel.issues_label.text, "cup is on rough, not green")
	assert_string_contains(panel.issues_label.text, "rule 2")


func test_a_highlight_sorts_with_the_terrain_and_only_its_text_draws_on_top() -> void:
	var c := CourseData.create(20, 20, Surface.Type.ROUGH, 2)
	var v: CourseView = autofree(CourseView.new())
	v.show_course(c)
	v.show_issues({1: [CourseValidator.Issue.new(2, Vector2i(6, 6), "cup is on rough, not green")]})
	var m: IssueMarker = v.issue_markers()[0]
	assert_eq(m.sort_key(), Iso.object_sort_key(Vector2(6, 6), 2), "the diamond Y-sorts like a pin on its tile")
	assert_eq(m.z_index, 0, "so a hill in front hides it")
	assert_true(m.get_parent().y_sort_enabled)
	assert_eq(m.label.z_index, 2, "the badge and text draw over everything")
	assert_eq(m.position + m.label.position, Iso.tile_to_screen(Vector2(6, 6), 2), "the text hangs off the tile centre")


func test_neighbouring_highlights_lay_their_text_out_clear_of_each_other() -> void:
	var c := CourseData.create(20, 20, Surface.Type.ROUGH, 2)
	var v: CourseView = autofree(CourseView.new())
	v.show_course(c)
	# A water-guarded cup: rule 3's first blocked tile next to the cup's rule 2 and rule 4.
	v.show_issues({1: [
		CourseValidator.Issue.new(2, Vector2i(10, 10), "cup is on rough, not green"),
		CourseValidator.Issue.new(4, Vector2i(10, 10), "150 yd is a par 3, not a par 4"),
		CourseValidator.Issue.new(3, Vector2i(9, 10), "no path from tee to cup round water and oob"),
		CourseValidator.Issue.new(3, Vector2i(10, 9), "no path from tee to cup round water and oob"),
	]})
	assert_eq(v.issue_markers().size(), 3)
	for scale: float in [1.0, 0.5, 2.0]:
		v.layout_issue_labels(scale)
		var rects: Array[Rect2] = v.issue_label_rects()
		for i: int in rects.size():
			for j: int in range(i + 1, rects.size()):
				assert_false(rects[i].intersects(rects[j]), "boxes %d and %d overlap at %sx" % [i, j, scale])
	v.show_issues({1: [CourseValidator.Issue.new(2, Vector2i(10, 10), "cup is on rough, not green")]})
	assert_eq(v.issue_markers()[0].stack, 0.0, "a lone box sits just above its tile")


func test_a_passing_hole_opens_itself_and_highlights_clear() -> void:
	var m := _main()
	_click(m, BuildTool.Tool.TEE, Vector2i(2, 10))
	_click(m, BuildTool.Tool.CUP, Vector2i(15, 10))
	m.build_tool.select_surface(Surface.Type.GREEN)
	_click(m, BuildTool.Tool.PAINT, Vector2i(15, 10))
	assert_eq(m.course_view.issue_markers().size(), 0, "nothing fails, nothing is highlighted")
	var panel: HolePanel = m.hole_panel
	assert_true(m.build_tool.builder.hole(1).open, "it opened itself (E8-S1, D64)")
	assert_true(panel.open_button.disabled, "an open hole cannot be opened again")
	assert_string_contains(panel.status_label.text, "open")
	m.build_tool.select_surface(Surface.Type.FAIRWAY)
	_click(m, BuildTool.Tool.PAINT, Vector2i(8, 10))
	assert_true(m.build_tool.builder.hole(1).open, "a paint in the footprint that keeps it legal")
	m.build_tool.set_hole_open(1, false)
	assert_false(m.build_tool.builder.hole(1).open, "closed by hand")
	assert_false(panel.open_button.disabled, "and Open is offered again")
	panel.open_button.pressed.emit()
	assert_true(m.build_tool.builder.hole(1).open, "Open reopens it")


func test_highlights_show_in_build_only() -> void:
	var m := _main()
	_click(m, BuildTool.Tool.TEE, Vector2i(2, 10))
	_click(m, BuildTool.Tool.CUP, Vector2i(15, 10))
	assert_true(m.course_view.issues_visible)
	m.set_mode(Main.Mode.PLAY)
	assert_false(m.course_view.issues_visible)
	assert_false(m.hole_panel.visible)
	m.set_mode(Main.Mode.BUILD)
	assert_true(m.course_view.issues_visible)


func test_play_stays_available_while_the_hole_fails() -> void:
	var m := _main()
	_click(m, BuildTool.Tool.TEE, Vector2i(2, 10))
	_click(m, BuildTool.Tool.CUP, Vector2i(15, 10))
	assert_false(m.build_tool.builder.issues_for(1).is_empty(), "the hole fails rule 2")
	m.toggle_mode()
	assert_eq(m.mode, Main.Mode.PLAY, "pillar 1: the validator never blocks Play")
	assert_true(m.score_card.visible, "the scorecard shows")
	assert_true(m.swing_control.active, "and the swing takes input")


# --- rule 5 by length (D35, E6-S37) ---

## Hole 1 a par `par1` from TEE to `cup1` and hole 2 a 150 yd par 3 from `tee2` back 30
## tiles west, on a rough course `w` x 40, each cup on a green. Neither hole is opened.
func _long_par3_and_a_tee(cup1: Vector2i, tee2: Vector2i, par1: int = 3, w: int = 80) -> CourseBuilder:
	var c := CourseData.create(w, 40, Surface.Type.ROUGH, 2)
	var b := CourseBuilder.new(c)
	b.paint(cup1, Surface.Type.GREEN, 3)
	b.place_tee(1, TEE, par1)
	b.place_cup(1, cup1)
	var cup2 := Vector2i(tee2.x - 30, tee2.y)
	b.paint(cup2, Surface.Type.GREEN, 1)
	b.place_tee(2, tee2, 3)
	b.place_cup(2, cup2)
	return b


func test_zone_from_yd_is_tuned_at_300() -> void:
	assert_eq(ValidatorTuning.load_default().zone_from_yd, 300)


func test_a_300_yd_par3_has_a_zone_and_a_tee_inside_it_fails() -> void:
	# 60 tiles along y = 20: 300 yd, a par 3 (under 320), zone centre 240 yd out at (53, 20).
	var b := _long_par3_and_a_tee(Vector2i(65, 20), Vector2i(53, 24))  # 20 yd from the centre
	assert_eq(CourseValidator.yardage(TEE, Vector2i(65, 20)), 300)
	var zone: Variant = CourseValidator.new().landing_zone(b.hole(1))
	assert_not_null(zone, "a 300 yd par 3 has a zone")
	assert_almost_eq((zone as Vector2).x, 53.0, 0.001, "240 yd out")
	assert_eq(_rules(b.issues_for(1)), [5] as Array[int], "the long par 3 fails rule 5")
	assert_eq(_rules(b.issues_for(2)), [5] as Array[int], "and so does the hole whose tee is in it")
	assert_eq(b.issues_for(1)[0].tile, Vector2i(53, 24), "the failing tee is highlighted")
	assert_eq(b.issues_for(2)[0].tile, Vector2i(53, 24))
	assert_false(b.can_open(1))
	assert_false(b.can_open(2))


func test_a_300_yd_par3_with_a_tee_outside_its_zone_opens() -> void:
	var b := _long_par3_and_a_tee(Vector2i(65, 20), Vector2i(53, 27))  # 35 yd from the centre
	assert_eq(b.issues_for(1), [] as Array[CourseValidator.Issue])
	assert_eq(b.issues_for(2), [] as Array[CourseValidator.Issue])
	assert_true(b.hole(1).open)
	assert_true(b.hole(2).open)


func test_a_299_yd_par3_has_no_zone_and_a_tee_where_it_would_be_opens() -> void:
	# (59, 10) tiles apart is 299.2 yd, rounded 299. min(240, 299 - 60) = 239 yd out puts
	# the zone it would have at about (52.1, 23.0).
	var cup1 := TEE + Vector2i(59, 10)
	var b := _long_par3_and_a_tee(cup1, Vector2i(52, 23))
	assert_eq(CourseValidator.yardage(TEE, cup1), 299)
	assert_null(CourseValidator.new().landing_zone(b.hole(1)), "under zone_from_yd, no zone")
	assert_eq(b.issues_for(1), [] as Array[CourseValidator.Issue])
	assert_eq(b.issues_for(2), [] as Array[CourseValidator.Issue])
	assert_true(b.hole(1).open)
	assert_true(b.hole(2).open)


func test_par4_and_par5_zones_are_unchanged() -> void:
	# The shortest par 4 (320 yd) and a 500 yd par 5 keep their zone 240 yd out, and a tee
	# inside it fails both holes as before.
	for case: Array in [[Vector2i(69, 20), 4, 80], [Vector2i(105, 20), 5, 120]]:
		var b := _long_par3_and_a_tee(case[0], Vector2i(53, 24), case[1], case[2])
		var zone: Variant = CourseValidator.new().landing_zone(b.hole(1))
		assert_not_null(zone, "par %d has a zone" % case[1])
		assert_almost_eq((zone as Vector2).x, 53.0, 0.001, "par %d: 240 yd out" % case[1])
		assert_eq(_rules(b.issues_for(1)), [5] as Array[int], "par %d" % case[1])
		assert_eq(_rules(b.issues_for(2)), [5] as Array[int], "par %d" % case[1])
		assert_eq(b.issues_for(2)[0].tile, Vector2i(53, 24))
		b.place_tee(2, Vector2i(53, 27))
		assert_eq(b.issues_for(1), [] as Array[CourseValidator.Issue], "par %d, tee outside" % case[1])


func test_footprint_holds_the_zone_of_a_long_par3() -> void:
	var v := CourseValidator.new()
	var c := _course()
	var h := HoleData.new(1, 3, TEE, Vector2i(65, 20), false)
	var zone: Vector2 = v.landing_zone(h)
	var r: int = ceili(v.tuning.zone_radius_yd / CourseValidator.YARDS_PER_TILE)
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var t := Vector2i(roundi(zone.x) + dx, roundi(zone.y) + dy)
			if Vector2(t).distance_to(zone) * CourseValidator.YARDS_PER_TILE <= v.tuning.zone_radius_yd:
				assert_true(v.in_footprint(c, h, t), str(t))
