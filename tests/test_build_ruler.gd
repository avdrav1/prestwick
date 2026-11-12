extends GutTest
## E8-S5: how long a hole is while you build it. With the Cup tool and a tee down, the ruler runs
## from the tee to the cursor with "285 yd: par 3" (rule 4's par for that yardage, the yardage the
## cup would get there, round a dogleg whose fairway already bends); placing the cup sets that par
## unless the par buttons picked it, and the hole panel says when a hand-picked par disagrees.
## Rings round the tee at the driver's carry and total and at the par lines show while the Tee or
## Cup tool is in hand, and never in Play. The F1 help and docs/how-to-play.md list each club's
## carry and total; a course with no cup shows the first-hole hint.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GROUND: int = 2
const TEE := Vector2i(10, 10)

var _c: CourseData
var _b: CourseBuilder
var _t: BuildTool


## A 140 x 140 rough plot at height 2: room for a 471 yd par 5 from TEE.
func before_each() -> void:
	_c = CourseData.create(140, 140, Surface.Type.ROUGH, GROUND)
	_b = CourseBuilder.new(_c)
	_t = BuildTool.new()
	_t.builder = _b
	add_child_autofree(_t)


func _hover(cell: Vector2i) -> void:
	_t.hover_at(Iso.tile_to_screen(Vector2(cell), _c.get_height(cell.x, cell.y)))
	assert_eq(_t.hover, cell, "the cursor is on %s" % cell)
	_t.ruler.refresh()


## Hole 1's tee on TEE through the tool, then the Cup tool in hand.
func _tee_then_cup_tool() -> void:
	_t.select_hole(1)
	_t.select_tool(BuildTool.Tool.TEE)
	_click(TEE)
	_t.select_tool(BuildTool.Tool.CUP)


func _click(cell: Vector2i) -> void:
	_t.press_at(Iso.tile_to_screen(Vector2(cell), _c.get_height(cell.x, cell.y)))
	_t.release()
	_t.ruler.refresh()


func _ring_yards() -> Array:
	return _t.ruler.rings.map(func(r: Dictionary) -> float: return float(r.yards))


# --- the ruler ---

func test_no_ruler_before_the_hole_has_a_tee() -> void:
	_t.select_hole(1)
	_t.select_tool(BuildTool.Tool.CUP)
	_hover(TEE + Vector2i(40, 0))
	assert_false(_t.ruler.ruler_shown, "no tee, no ruler")
	assert_eq(_t.ruler.ruler_text(), "")


func test_the_ruler_shows_the_yardage_and_the_par_it_makes() -> void:
	_tee_then_cup_tool()
	_hover(TEE + Vector2i(57, 0))
	assert_true(_t.ruler.ruler_shown, "the Cup tool with a tee down shows the ruler")
	assert_eq(_t.ruler.ruler_text(), "285 yd: par 3")
	assert_eq(_t.ruler.ruler_line, PackedVector2Array([Vector2(TEE), Vector2(TEE + Vector2i(57, 0))]),
			"a straight line from the tee to the cursor")
	_hover(TEE + Vector2i(70, 0))
	assert_eq(_t.ruler.ruler_text(), "350 yd: par 4", "it follows the cursor")
	_hover(TEE + Vector2i(95, 0))
	assert_eq(_t.ruler.ruler_text(), "475 yd: par 5")
	# The par bands are rule 4's, read from the validator's tuning.
	var vt: ValidatorTuning = _b.validator.tuning
	_hover(TEE + Vector2i(0, vt.par4_min_yd / 5))
	assert_eq(_t.ruler.ruler_par, 4, "%d yd is the shortest par 4" % vt.par4_min_yd)
	_hover(TEE + Vector2i(0, vt.par4_min_yd / 5 - 1))
	assert_eq(_t.ruler.ruler_par, 3)
	assert_false(_t.ruler.ruler_points().is_empty(), "the line is laid on the ground")


func test_the_ruler_measures_once_per_change_not_per_frame() -> void:
	_tee_then_cup_tool()
	_hover(TEE + Vector2i(30, 0))
	var n: int = _t.ruler.measure_count
	var built: int = _t.ruler.ring_build_count
	for i: int in 5:
		assert_false(_t.ruler.refresh(), "nothing changed: nothing measured")
	assert_eq(_t.ruler.measure_count, n)
	_hover(TEE + Vector2i(31, 0))
	assert_eq(_t.ruler.measure_count, n + 1, "a cursor move measures the ruler once")
	assert_eq(_t.ruler.ring_build_count, built, "the rings are not laid again for a cursor move")


func test_with_the_tee_tool_or_a_brush_there_is_no_ruler() -> void:
	_tee_then_cup_tool()
	_t.select_tool(BuildTool.Tool.TEE)
	_hover(TEE + Vector2i(30, 0))
	assert_false(_t.ruler.ruler_shown, "the Tee tool shows no ruler")
	_t.select_surface(Surface.Type.FAIRWAY)
	_t.ruler.refresh()
	assert_false(_t.ruler.ruler_shown, "a brush shows no ruler")


func test_the_cup_gets_the_rulers_yardage_and_its_par() -> void:
	_tee_then_cup_tool()
	var cup := TEE + Vector2i(66, 20)
	_hover(cup)
	var yards: int = _t.ruler.ruler_yards
	var p: int = _t.ruler.ruler_par
	_click(cup)
	var h: HoleData = _b.hole(1)
	assert_eq(h.cup, cup)
	assert_eq(_b.yardage_at(_b.slot_of(1)), yards, "the hole measures what the ruler said")
	assert_eq(h.par, p, "placing the cup set the par the ruler said (par %d)" % p)
	assert_eq(p, 4)
	assert_false(h.par_by_hand)


## A dogleg: fairway east 48 tiles (240 yd) from the tee, then south to the cursor. Rule 4's disc on
## the straight line holds no fairway, so the line of play turns at the corner (D47), and the
## ruler bends with it.
func test_on_a_dogleg_the_ruler_follows_the_line_of_play() -> void:
	var cup := Vector2i(58, 60)
	for y: int in range(8, 13):
		for x: int in range(8, 63):
			_c.set_tile(x, y, GROUND, Surface.Type.FAIRWAY)
	for y: int in range(8, 65):
		for x: int in range(56, 61):
			_c.set_tile(x, y, GROUND, Surface.Type.FAIRWAY)
	_tee_then_cup_tool()
	_hover(cup)
	assert_eq(_t.ruler.ruler_line.size(), 3, "tee -> turn -> cursor")
	var straight: int = CourseValidator.yardage(TEE, cup)
	assert_gt(_t.ruler.ruler_yards, straight, "round the dogleg is longer than the straight line")
	var yards: int = _t.ruler.ruler_yards
	var turn: Vector2 = _t.ruler.ruler_line[1]
	_click(cup)
	var h: HoleData = _b.hole(1)
	assert_eq(_b.yardage_at(_b.slot_of(1)), yards, "the cup's yardage is the ruler's")
	assert_eq(_b.validator.line_of_play(_c, h)[1], turn, "the turn is the line of play's")
	assert_eq(h.par, _b.validator.par_for_yardage(yards))


func test_with_no_fairway_the_ruler_is_the_straight_line() -> void:
	_tee_then_cup_tool()
	_hover(Vector2i(58, 60))
	assert_eq(_t.ruler.ruler_line.size(), 2, "rough everywhere: no turn, the straight line")
	assert_eq(_t.ruler.ruler_yards, CourseValidator.yardage(TEE, Vector2i(58, 60)))


# --- auto par ---

func test_moving_the_cup_keeps_the_par_in_step_with_the_yardage() -> void:
	_tee_then_cup_tool()
	_click(TEE + Vector2i(30, 0))
	assert_eq(_b.hole(1).par, 3, "150 yd: par 3")
	_click(TEE + Vector2i(70, 0))
	assert_eq(_b.hole(1).par, 4, "350 yd: par 4")
	_click(TEE + Vector2i(100, 0))
	assert_eq(_b.hole(1).par, 5, "500 yd: par 5")
	assert_true(_b.issues_for(1).filter(func(i: CourseValidator.Issue) -> bool: return i.rule == 4).is_empty(),
			"rule 4 passes after every move")
	assert_true(_b.undo(), "undo")
	assert_eq(_b.hole(1).par, 4, "one undo puts the cup and its par back together")


func test_a_par_picked_by_hand_is_kept_and_the_panel_says_it_disagrees() -> void:
	var panel := HolePanel.new()
	add_child_autofree(panel)
	panel.bind(_t)
	_tee_then_cup_tool()
	_click(TEE + Vector2i(30, 0))
	assert_eq(_b.hole(1).par, 3)
	assert_false(panel.par_note_label.visible, "an auto par agrees: nothing to say")
	_t.select_par(4)
	assert_true(_b.hole(1).par_by_hand, "the par button marks the par as picked by hand")
	_click(TEE + Vector2i(40, 0))
	assert_eq(_b.hole(1).par, 4, "moving the cup keeps a hand-picked par")
	panel.refresh()
	assert_true(panel.par_note_label.visible, "the panel says the hand-picked par disagrees")
	assert_eq(panel.par_note_label.text, "You picked par 4 by hand; 200 yd makes a par 3. Press 3 to match.")
	_t.select_par(3)
	panel.refresh()
	assert_false(panel.par_note_label.visible, "once they agree, nothing to say")


func test_a_par_picked_before_the_first_tee_is_kept() -> void:
	_t.select_hole(1)
	_t.select_par(5)
	_t.select_tool(BuildTool.Tool.TEE)
	_click(TEE)
	assert_true(_b.hole(1).par_by_hand, "the hole is made with its par picked by hand")
	_t.select_tool(BuildTool.Tool.CUP)
	_click(TEE + Vector2i(30, 0))
	assert_eq(_b.hole(1).par, 5, "the hand-picked par stays")
	# A new hole picked afterwards starts with an auto par again.
	assert_eq(_t.new_hole(), 2)
	_click(TEE + Vector2i(0, 20))
	_t.select_tool(BuildTool.Tool.CUP)
	_click(TEE + Vector2i(70, 20))
	assert_false(_b.hole(2).par_by_hand)
	assert_eq(_b.hole(2).par, 4, "hole 2's par follows its 350 yd")


func test_the_by_hand_flag_round_trips_through_a_file() -> void:
	var h := HoleData.new(3, 4, Vector2i(1, 1), Vector2i(5, 5), false, false, true)
	var d: Dictionary = h.to_dict()
	assert_eq(d.get("par_by_hand"), true)
	var errors: Array[String] = []
	assert_true(HoleData.from_dict(d, errors).par_by_hand, "read back")
	assert_false(HoleData.new().to_dict().has("par_by_hand"), "written only when set")
	d["par_by_hand"] = "yes"
	assert_null(HoleData.from_dict(d, errors), "not a bool: refused")


func test_the_builder_without_auto_par_leaves_par_alone() -> void:
	assert_true(_b.place_tee(1, TEE, 3))
	assert_true(_b.place_cup(1, TEE + Vector2i(70, 0)))
	assert_eq(_b.hole(1).par, 3, "a caller that does not ask for auto par keeps its par (rule 4 then fails)")


# --- the rings ---

func test_rings_show_round_the_tee_with_the_tee_or_cup_tool() -> void:
	_t.select_hole(1)
	_t.select_tool(BuildTool.Tool.TEE)
	_t.ruler.refresh()
	assert_false(_t.ruler.rings_shown(), "no tee yet: no rings")
	_click(TEE)
	assert_true(_t.ruler.rings_shown(), "the Tee tool with the tee down shows the rings")
	var driver: Club = ClubSet.load_default().club("driver")
	var vt: ValidatorTuning = _b.validator.tuning
	assert_eq(_ring_yards(), [driver.carry_yd, driver.total_yd, float(vt.par4_min_yd), float(vt.par5_min_yd)],
			"the driver's carry and total, then the par 4 and par 5 lines, from their resources")
	assert_eq(_ring_yards(), [235.0, 282.0, 320.0, 471.0])
	var labels: Array = _t.ruler.rings.map(func(r: Dictionary) -> String: return r.label)
	assert_eq(labels, ["driver carry 235 yd", "driver total 282 yd", "par 4 from 320 yd", "par 5 from 471 yd"])
	for r: Dictionary in _t.ruler.rings:
		assert_false((r.runs as Array).is_empty(), "%s is drawn" % r.label)
		assert_not_null(r.label_at, "%s has a label on the map" % r.label)
	_t.select_tool(BuildTool.Tool.CUP)
	_t.ruler.refresh()
	assert_true(_t.ruler.rings_shown(), "the Cup tool shows them too")
	_t.select_tool(BuildTool.Tool.RAISE)
	_t.ruler.refresh()
	assert_false(_t.ruler.rings_shown(), "Raise shows none")
	_t.select_tool(BuildTool.Tool.CUP)
	_t.active = false
	_t.ruler.refresh()
	assert_false(_t.ruler.rings_shown(), "an inactive tool (Play) shows none")
	assert_false(_t.ruler.visible, "and the overlay is hidden")


func test_a_ring_lies_on_the_ground_and_is_clipped_to_the_map() -> void:
	_c.set_tile(TEE.x + 47, TEE.y, 6, Surface.Type.ROUGH)
	_tee_then_cup_tool()
	var carry: Dictionary = _t.ruler.rings[0]
	# The ring round a tee 10 tiles from the map's corner runs off the map: in more than one piece
	# or less than a whole circle, never a point off the map.
	var count: int = 0
	for run: PackedVector2Array in carry.runs:
		count += run.size()
	var r_tiles: float = 235.0 / 5.0
	assert_lt(count, ceili(TAU * r_tiles) + 1, "the part off the map is left out")
	var raised: Vector2 = Iso.tile_to_screen(Vector2(TEE.x + 47, TEE.y), 6)
	var flat: Vector2 = Iso.tile_to_screen(Vector2(TEE.x + 47, TEE.y), GROUND)
	var near_raised: bool = false
	for run: PackedVector2Array in carry.runs:
		for p: Vector2 in run:
			if p.distance_to(raised) < 2.0:
				near_raised = true
			assert_false(p.distance_to(flat) < 2.0, "not on the flat height where the ground is raised")
	assert_true(near_raised, "the ring climbs onto the raised tile's ground")


func test_play_hides_the_ruler_and_the_rings() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	m.course_path = "res://tests/fixtures/flat_20x20.json"
	add_child_autofree(m)
	m.show_course(_c)
	var t: BuildTool = m.build_tool
	var c: CourseData = t.builder.course
	t.select_hole(1)
	assert_true(t.builder.place_tee(1, Vector2i(3, 10)))
	t.select_tool(BuildTool.Tool.CUP)
	t.hover_at(Iso.tile_to_screen(Vector2(16, 10), c.get_height(16, 10)))
	t.ruler.refresh()
	assert_true(t.ruler.visible and t.ruler.ruler_shown and t.ruler.rings_shown(), "Build shows them")
	assert_eq(t.ruler.ruler_text(), "65 yd: par 3")
	m.set_mode(Main.Mode.PLAY)
	t.ruler.refresh()
	assert_false(t.ruler.visible, "Play hides the overlay")
	assert_false(t.ruler.ruler_shown or t.ruler.rings_shown(), "and shows neither")
	m.set_mode(Main.Mode.BUILD)
	t.select_tool(BuildTool.Tool.CUP)
	t.ruler.refresh()
	assert_true(t.ruler.visible and t.ruler.rings_shown(), "back in Build they return")


# --- the club table and the first-hole hint ---

func test_the_help_and_the_guide_list_every_clubs_carry_and_total() -> void:
	var text: String = HelpOverlay.club_text(ClubSet.load_default())
	var f := FileAccess.open("res://docs/how-to-play.md", FileAccess.READ)
	assert_not_null(f, "docs/how-to-play.md")
	var guide: String = f.get_as_text() if f != null else ""
	for c: Club in ClubSet.load_default().clubs:
		if c.is_putter():
			continue
		assert_string_contains(text, "%s %d / %d" % [c.id, roundi(c.carry_yd), roundi(c.total_yd)])
		var row: String = "| %s | %d | %d |" % [c.id, roundi(c.carry_yd), roundi(c.total_yd)]
		assert_string_contains(guide, row, "the guide's club table has %s" % row)
	var help := HelpOverlay.new()
	add_child_autofree(help)
	assert_eq(help.clubs_label.text, text, "F1 shows it")


func test_a_course_with_no_cup_shows_the_first_hole_hint() -> void:
	var panel := HolePanel.new()
	add_child_autofree(panel)
	panel.bind(_t)
	assert_eq(HolePanel.first_hole_text(BuilderTuning.load_default()),
			"A first par 3 is 120 to 300 yd (the cup 24 to 60 tiles from the tee); " +
			"a par 4 of 320 to 380 yd fits corner to corner (64 to 76 tiles)",
			"D67: the 4 x 4 block holds a par 3 up to 300 yd or a par 4")
	assert_true(panel.first_hole_label.visible, "no hole yet: the hint shows")
	_t.select_hole(1)
	_t.select_tool(BuildTool.Tool.TEE)
	_click(TEE)
	panel.refresh()
	assert_true(panel.first_hole_label.visible, "a tee alone: still shown")
	_t.select_tool(BuildTool.Tool.CUP)
	_click(TEE + Vector2i(30, 0))
	panel.refresh()
	assert_false(panel.first_hole_label.visible, "the first cup is down: gone")
