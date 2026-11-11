extends GutTest
## E2-S3: a hole made in Build through course/builder.gd. A new sandbox on the D10 plot, the
## tee and cup tools, par, all on the terrain's undo stack, and `oob` on the palette (D9).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _flat(size: int = 40, h: int = 2) -> CourseData:
	return CourseData.create(size, size, Surface.Type.ROUGH, h)


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
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
	assert_true(m.course_view.chunk_at(Vector2i(127, 127)).parts.has(Vector2i(127, 127)),
			"the view shows the whole plot")
	assert_true(m.new_sandbox_button.visible, "New sandbox is on the Build HUD")


func test_new_sandbox_button_starts_the_plot_and_hides_in_play() -> void:
	var m := _main()
	m.new_sandbox_button.pressed.emit()
	assert_eq(Vector2i(m.course.width, m.course.height), Vector2i(128, 128))
	assert_eq(m.course.get_height(64, 64), 2)
	m.set_mode(Main.Mode.PLAY)
	assert_false(m.new_sandbox_button.visible, "Build only")


func test_main_starts_on_a_new_course_not_the_blank_plot() -> void:
	# E2-S8 started on the D10 plot; from E6-S6 the main scene starts on a New course
	# (tests/test_new_course.gd), and the plot is New sandbox's.
	var m := MAIN_SCENE.instantiate() as Main
	m.start_seed = 3
	assert_eq(m.course_path, "", "no startup course file")
	add_child_autofree(m)
	assert_eq(Vector2i(m.course.width, m.course.height), Vector2i(128, 128))
	assert_eq(m.course.content_hash(), CourseBuilder.new_course(3).content_hash(), "generated land")
	assert_ne(m.course.content_hash(), CourseBuilder.new_sandbox().content_hash(), "not the blank plot")


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


# --- a dogleg's line through a drag (E3-S61) ---

## E3-S61: the builder keeps each hole's line of play between paints and measures it again only
## when a fairway write lands on a tile its turn read (CourseValidator.turn_point's `reads`). A fairway write far off keeps the dogleg's line; one at its landing zone, off the
## dogleg's footprint, makes it straight, and the hole closes on the line now even though the
## same stroke had measured (and kept) the dogleg's line a paint before.
func test_a_dogleg_whose_turn_an_edit_moves_still_closes() -> void:
	var c := ReactionHoles.dogleg_par4()
	var b := CourseBuilder.new(c)
	var v := b.validator
	var h: HoleData = c.holes[0]
	assert_true(h.open, "the fixture's dogleg opens")
	var line: PackedVector2Array = b.slot_lines()[0]
	assert_eq(line.size(), 3, "tee, turn, cup")
	var reads := {}
	assert_eq(v.line_of_play(c, h, reads), line)
	var z := Vector2i((v.landing_zone(h) as Vector2).round())
	assert_false(v.near_line(line, z), "the landing zone is off the dogleg's footprint")
	assert_true(reads.has(z), "but its turn reads it")
	var far := Vector2i(66, 57)
	assert_false(reads.has(far), "not a corner of the map")
	assert_false(v.near_line(line, far))
	b.begin_stroke()
	assert_true(b.paint(far, Surface.Type.FAIRWAY, 1))
	assert_true(c.holes[0].open, "fairway far off: still open")
	assert_eq(b.lines_now()[0], line, "and the dogleg's line is kept")
	assert_true(b.paint(z, Surface.Type.FAIRWAY, 1))
	assert_null(v.turn_point(c, c.holes[0]), "fairway in the landing zone plays it straight")
	assert_false(c.holes[0].open, "closed: the line now runs over the tile painted")
	assert_eq(b.lines_now()[0].size(), 2, "measured again, straight")
	b.end_stroke()
	assert_eq(b.slot_lines()[0].size(), 2)
	# Undone, the dogleg is back and open; its line is the dogleg's again.
	assert_true(b.undo())
	assert_true(c.holes[0].open)
	assert_eq(b.lines_now()[0], line)


## E7-S5: an undo of a stroke that kept its lines writes its tiles without searching the lines'
## reads, since it puts the lines and their reads back whole: after it the reads still count,
## so the same fairway write at the landing zone measures the line again and closes the hole.
func test_an_undo_puts_back_the_reads_a_later_paint_moves_the_turn_by() -> void:
	var c := ReactionHoles.dogleg_par4()
	var b := CourseBuilder.new(c)
	var v := b.validator
	var line: PackedVector2Array = b.slot_lines()[0]
	var z := Vector2i((v.landing_zone(c.holes[0]) as Vector2).round())
	b.begin_stroke()
	assert_true(b.paint(Vector2i(66, 57), Surface.Type.FAIRWAY, 1))
	assert_true(b.paint(z, Surface.Type.FAIRWAY, 1))
	b.end_stroke()
	assert_eq(b.slot_lines()[0].size(), 2, "straight after the stroke")
	assert_true(b.undo())
	assert_true(c.holes[0].open)
	assert_eq(b.lines_now()[0], line, "the dogleg's line, kept")
	assert_eq(b.lines_now()[0], v.line_of_play(c, c.holes[0]), "as a fresh measure has it")
	assert_true(b.paint(z, Surface.Type.FAIRWAY, 1))
	assert_eq(b.lines_now()[0].size(), 2, "the landing zone's read still counts: measured again")
	# E8-S1 (D64): the footprint closes it and the rerun opens it again, since it still passes.
	assert_true(c.holes[0].open, "still legal straight, so open after the paint")
	# A step that kept no lines (a paint outside a stroke) searches the reads as it writes.
	assert_true(b.undo())
	assert_eq(b.lines_now()[0], line)
	assert_true(c.holes[0].open)


## E3-S61: the tiles turn_point reads hold every tile whose surface can change its answer: a
## fairway tile painted on any other leaves the turn where it was.
func test_a_turn_reads_nothing_but_the_tiles_it_names() -> void:
	var c := ReactionHoles.dogleg_par4()
	var v := CourseValidator.new()
	var h: HoleData = c.holes[0]
	var reads := {}
	var turn: Variant = v.turn_point(c, h, reads)
	assert_not_null(turn)
	assert_true(reads.has(Vector2i((turn as Vector2).round())), "the fairway at its turn")
	var outside := 0
	for y: int in c.height:
		for x: int in c.width:
			if reads.has(Vector2i(x, y)) or c.get_surface(x, y) == Surface.Type.FAIRWAY:
				continue
			var was: Surface.Type = c.get_surface(x, y)
			c.set_tile(x, y, c.get_height(x, y), Surface.Type.FAIRWAY)
			assert_eq(v.turn_point(c, h), turn, "fairway at (%d, %d) moves nothing" % [x, y])
			c.set_tile(x, y, c.get_height(x, y), was)
			outside += 1
	assert_gt(outside, 1000, "most of the map is not read")
	# A hole too short to turn reads nothing.
	var short := HoleData.new(2, 3, Vector2i(6, 6), Vector2i(20, 6), false)
	var none := {}
	assert_null(v.turn_point(c, short, none))
	assert_true(none.is_empty())


# --- E8-S1 (D64): a hole opens itself the moment it passes every rule ---

## A 150 yd par 3 along y = 20 on an 80 x 40 rough plot, its cup on a green: legal once both
## are placed.
const AUTO_TEE := Vector2i(5, 20)
const AUTO_CUP := Vector2i(35, 20)


func _auto_course() -> CourseData:
	return CourseData.create(80, 40, Surface.Type.ROUGH, 2)


## Hole 1 built legal on `c`: green first, then tee and cup, so the cup is what makes it legal.
func _legal_par3(c: CourseData) -> CourseBuilder:
	var b := CourseBuilder.new(c)
	b.paint(AUTO_CUP, Surface.Type.GREEN, 3)
	b.place_tee(1, AUTO_TEE, 3)
	b.place_cup(1, AUTO_CUP)
	return b


func test_a_hole_opens_itself_the_moment_it_passes_every_rule() -> void:
	var b := CourseBuilder.new(_auto_course())
	var opened: Array = []
	b.holes_opened.connect(func(numbers: Array[int]) -> void: opened.append(numbers))
	b.place_tee(1, AUTO_TEE, 3)
	assert_false(b.hole(1).open, "a tee alone fails rule 1")
	b.place_cup(1, AUTO_CUP)
	assert_false(b.hole(1).open, "the cup on rough fails rule 2")
	assert_eq(opened, [], "no notice while it fails")
	b.paint(AUTO_CUP, Surface.Type.GREEN, 3)
	assert_true(b.hole(1).open, "the green makes it legal and it opens, no Open pressed")
	assert_false(b.hole(1).closed_by_hand)
	assert_eq(opened, [[1]], "one notice, for hole 1")
	assert_eq(CourseBuilder.opened_line([1]), "Hole 1 is open: guests will play it")
	assert_eq(CourseBuilder.opened_line([2, 3]), "Holes 2 and 3 are open: guests will play them")
	assert_false(b.can_open(1), "nothing for Open to do")
	b.paint(Vector2i(60, 5), Surface.Type.BUNKER, 1)
	assert_eq(opened.size(), 1, "an edit elsewhere gives no second notice")


func test_close_by_hand_holds_until_open_by_hand() -> void:
	var b := _legal_par3(_auto_course())
	assert_true(b.hole(1).open)
	assert_true(b.close_hole(1))
	assert_false(b.hole(1).open)
	assert_true(b.hole(1).closed_by_hand, "Close marks it closed by hand")
	b.paint(Vector2i(20, 24), Surface.Type.FAIRWAY, 1)
	b.set_par(1, 4)
	b.set_par(1, 3)
	b.place_tee(1, AUTO_TEE + Vector2i(0, 1))
	assert_false(b.hole(1).open, "no edit opens a hole closed by hand")
	assert_true(b.can_open(1))
	assert_true(b.open_hole(1), "Open opens it")
	assert_true(b.hole(1).open)
	assert_false(b.hole(1).closed_by_hand, "and clears the flag")


func test_a_rule_closes_it_and_it_reopens_once_fixed() -> void:
	var b := _legal_par3(_auto_course())
	var opened: Array = []
	b.holes_opened.connect(func(numbers: Array[int]) -> void: opened.append(numbers))
	b.paint(AUTO_CUP, Surface.Type.ROUGH, 1)
	assert_false(b.hole(1).open, "the cup on rough breaks it and it closes, as before")
	assert_false(b.hole(1).closed_by_hand, "a rule's close is not the player's")
	b.paint(AUTO_CUP, Surface.Type.GREEN, 1)
	assert_true(b.hole(1).open, "fixed, it opens itself again")
	assert_eq(opened, [[1]])
	# Closed by hand, then broken and fixed: it stays closed.
	b.close_hole(1)
	b.paint(AUTO_CUP, Surface.Type.ROUGH, 1)
	b.paint(AUTO_CUP, Surface.Type.GREEN, 1)
	assert_false(b.hole(1).open, "a hole closed by hand stays closed through a break and a fix")
	assert_eq(opened.size(), 1)


func test_an_edit_in_the_footprint_that_keeps_it_legal_keeps_it_open() -> void:
	var b := _legal_par3(_auto_course())
	var opened: Array = []
	b.holes_opened.connect(func(numbers: Array[int]) -> void: opened.append(numbers))
	b.paint(Vector2i(20, 24), Surface.Type.FAIRWAY, 1)
	assert_true(b.hole(1).open, "a click edit in the footprint: closed and reopened by its rerun")
	b.begin_stroke()
	b.paint(Vector2i(20, 20), Surface.Type.FAIRWAY, 1)
	assert_false(b.hole(1).open, "a drag in the footprint closes it while it lasts (D11)")
	b.paint(Vector2i(21, 20), Surface.Type.FAIRWAY, 1)
	b.end_stroke()
	assert_true(b.hole(1).open, "and it opens again when the drag ends")
	assert_eq(opened, [], "a hole that was open before the edit gives no notice")


func test_undo_restores_the_open_and_by_hand_flags() -> void:
	var b := _legal_par3(_auto_course())
	b.undo()
	assert_false(b.hole(1).open, "undoing the cup leaves a tee alone: closed")
	b.place_cup(1, AUTO_CUP)
	assert_true(b.hole(1).open)
	b.close_hole(1)
	b.undo()
	assert_true(b.hole(1).open, "undo of Close: open again")
	assert_false(b.hole(1).closed_by_hand, "and not closed by hand")
	b.close_hole(1)
	b.open_hole(1)
	b.undo()
	assert_false(b.hole(1).open, "undo of Open: closed")
	assert_true(b.hole(1).closed_by_hand, "by hand, as before the press")
	b.paint(Vector2i(60, 5), Surface.Type.BUNKER, 1)
	assert_false(b.hole(1).open, "and it stays so")


func test_the_by_hand_flag_is_an_optional_field_of_format_3() -> void:
	var c := _auto_course()
	var b := _legal_par3(c)
	var open_text := CourseSave.to_json(c)
	assert_false(open_text.contains("closed_by_hand"), "a hole not closed by hand writes as before")
	b.close_hole(1)
	var data: Dictionary = JSON.parse_string(CourseSave.to_json(c))
	assert_eq(int(data["version"]), CourseData.FORMAT_VERSION, "no version bump")
	assert_eq(data["holes"][0]["closed_by_hand"], true)
	var errors: Array[String] = []
	var loaded := CourseSave.from_dict(data, errors)
	assert_eq(errors, [] as Array[String])
	assert_true(loaded.holes[0].closed_by_hand)
	assert_false(loaded.holes[0].open)
	var lb := CourseBuilder.new(loaded)
	assert_false(lb.hole(1).open, "a hole closed by hand loads closed")
	assert_eq(lb.load_notes(), [] as Array[String], "and says nothing")
	assert_eq(loaded.content_hash(), c.content_hash())
	data["holes"][0]["closed_by_hand"] = "yes"
	assert_null(CourseSave.from_dict(data, errors), "a flag that is not true or false is refused")


func test_a_course_from_before_d64_opens_its_legal_closed_holes_and_says_so() -> void:
	var c := _auto_course()
	c.set_tile(AUTO_CUP.x, AUTO_CUP.y, 2, Surface.Type.GREEN)
	var hs: Array[HoleData] = [HoleData.new(1, 3, AUTO_TEE, AUTO_CUP, false),
			HoleData.new(2, 3, AUTO_TEE + Vector2i(0, 12), AUTO_CUP + Vector2i(0, 12), false)]
	c.set_holes(hs)
	var errors: Array[String] = []
	var loaded := CourseSave.from_json(CourseSave.to_json(c), errors)
	var b := CourseBuilder.new(loaded)
	assert_true(b.hole(1).open, "a legal hole the file had closed, never by hand, opens")
	assert_false(b.hole(2).open, "hole 2's cup is on rough: it stays closed")
	assert_eq(b.opened_on_load, ["Hole 1 is open: guests will play it"] as Array[String])
	assert_eq(b.load_notes(), ["Hole 1 is open: guests will play it"] as Array[String])
	assert_false(b.can_undo(), "opening it is not an undo step")


func test_the_hud_shows_one_notice_as_a_hole_opens_itself() -> void:
	var m := _main()
	var c: CourseData = m.course
	m.build_tool.select_tool(BuildTool.Tool.TEE)
	m.build_tool.press_at(_at(c, Vector2i(2, 10)))
	m.build_tool.release()
	m.build_tool.select_surface(Surface.Type.GREEN)
	m.build_tool.select_tool(BuildTool.Tool.PAINT)
	m.build_tool.press_at(_at(c, Vector2i(15, 10)))
	m.build_tool.release()
	assert_false(m.hole_open_notice.visible, "no notice before the hole is legal")
	m.build_tool.select_tool(BuildTool.Tool.CUP)
	m.build_tool.press_at(_at(c, Vector2i(15, 10)))
	m.build_tool.release()
	assert_true(m.build_tool.builder.hole(1).open, "the cup on the green opens it")
	assert_true(m.hole_open_notice.visible, "and the notice shows")
	assert_eq(m.hole_open_notice.label.text, "Hole 1 is open: guests will play it")
	assert_eq(m.hole_open_notice.mouse_filter, Control.MOUSE_FILTER_IGNORE, "it takes no clicks")
	assert_string_contains(m.hole_panel.status_label.text, "open")
	m.hole_open_notice._process(m.hole_open_notice.tuning.open_notice_s + 0.1)
	assert_false(m.hole_open_notice.visible, "it goes by itself")
	m.hole_panel.rows[0].open_button.pressed.emit()
	assert_false(m.build_tool.builder.hole(1).open, "the row's Close closes it")
	assert_eq(m.hole_panel.status_label.text, "Status: closed by you")
	assert_false(m.hole_panel.open_button.disabled, "Open is offered to reopen it")
