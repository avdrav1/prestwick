extends GutTest
## E10-S1: a New course's goal checklist (scenes/goal_list.gd, scenes/goals_panel.gd). The goals
## read the game and tick as they are met, each with a one-line how naming the real controls;
## done goals stay done; the panel folds to "Next: ..." and the menu's Goals opens it again; the
## game save keeps the ticks and the fold; Play hole (and Tab) wait for a hole with a tee and a
## cup; the panel fits the left column clear of the free view; F6 reaches it.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SAVE_PATH := "user://test_goals_save.json"
## A par 3 on seed 7's starting block (D67: tiles 32 to 95 each way), as test_economy_build's.
const TEE := Vector2i(51, 60)
const CUP := Vector2i(76, 60)
const ROW2 := 10


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _main() -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.start_seed = 7
	add_child_autofree(m)
	m.guest_sim.set_process(false)
	m.camera.set_process(false)
	m.save_path = SAVE_PATH
	return m


## Paints a passing par 3's ground `dy` tiles south of row 60: fairway from tee to cup, a tee box
## and a green round the cup (when `green`).
func _ground(b: CourseBuilder, dy: int, green: bool) -> void:
	for x: int in range(TEE.x - 1, CUP.x + 3):
		for y: int in range(TEE.y + dy - 2, TEE.y + dy + 3):
			b.paint(Vector2i(x, y), Surface.Type.FAIRWAY, 1)
	b.paint(TEE + Vector2i(0, dy), Surface.Type.TEE, 1)
	if green:
		b.paint(CUP + Vector2i(0, dy), Surface.Type.GREEN, 3)


func _names(list: GoalList) -> PackedStringArray:
	var out: PackedStringArray = []
	for g: GoalList.Goal in list.goals():
		out.append(g.id)
	return out


# --- the list ---

func test_the_list_names_each_step_with_a_how_that_teaches_the_controls() -> void:
	var list := GoalList.new()
	assert_eq(_names(list), GoalList.ORDER, "tee, cup, green, open, guests, hole 2, parcel, stars (D67)")
	assert_eq(list.done_count(), 0)
	assert_eq(list.next_goal().id, GoalList.TEE, "a new course starts at its tee")
	for g: GoalList.Goal in list.goals():
		assert_false(g.title.is_empty(), "%s has a title" % g.id)
		assert_false(g.how.is_empty(), "%s has a how" % g.id)
		assert_false(g.how.contains("\n"), "%s's how is one line" % g.id)
	# The real controls, by the names the HUD gives them.
	assert_string_contains(list.goal(GoalList.TEE).how, "Pick Tee")
	assert_string_contains(list.goal(GoalList.TEE).how, "your land")
	assert_string_contains(list.goal(GoalList.CUP).how, "Pick Cup")
	assert_string_contains(list.goal(GoalList.CUP).how, "ruler")
	assert_string_contains(list.goal(GoalList.GREEN).how, "green")
	assert_string_contains(list.goal(GoalList.PARCEL).how, "Buy land")
	assert_string_contains(list.goal(GoalList.HOLE2).how, "New hole")
	# How money is made: the green fee at the first tee, upkeep at dusk.
	var money: String = list.goal(GoalList.GUESTS).how
	assert_string_contains(money, "clubhouse")
	assert_string_contains(money, "green fee")
	assert_string_contains(money, "first tee")
	assert_string_contains(money, "upkeep at dusk")
	assert_eq(list.goal(GoalList.STARS).title, "Reach %d stars" % roundi(list.tuning.target_stars))


func test_the_course_ticks_tee_cup_green_open_and_hole_two() -> void:
	var c := CourseBuilder.new_course(7)
	var b := CourseBuilder.new(c)
	var list := GoalList.new()
	list.refresh(c)
	assert_eq(list.done_count(), 0, "bare land meets nothing")
	_ground(b, 0, false)
	assert_true(b.place_tee(1, TEE, 3))
	list.refresh(c)
	assert_eq(list.done_ids(), PackedStringArray([GoalList.TEE]))
	assert_false(GoalList.has_playable_hole(c), "a tee alone is no hole to play")
	assert_true(b.place_cup(1, CUP))
	list.refresh(c)
	assert_eq(list.done_ids(), PackedStringArray([GoalList.TEE, GoalList.CUP]), "the cup on fairway")
	assert_true(GoalList.has_playable_hole(c))
	assert_eq(list.next_goal().id, GoalList.GREEN)
	b.paint(CUP, Surface.Type.GREEN, 3)
	list.refresh(c)
	assert_true(list.is_done(GoalList.GREEN), "a green round the cup")
	assert_true(c.holes[0].open, "the hole opens by itself (E8-S1)")
	assert_true(list.is_done(GoalList.OPEN))
	assert_eq(list.next_goal().id, GoalList.GUESTS)
	assert_false(list.is_done(GoalList.HOLE2), "one open hole")
	_ground(b, ROW2, true)
	assert_true(b.place_tee(2, TEE + Vector2i(0, ROW2), 3))
	assert_true(b.place_cup(2, CUP + Vector2i(0, ROW2)))
	list.refresh(c)
	assert_true(b.hole(2).open)
	assert_true(list.is_done(GoalList.HOLE2), "a second open hole")


func test_done_goals_stay_done() -> void:
	var c := CourseBuilder.new_course(7)
	var b := CourseBuilder.new(c)
	var list := GoalList.new()
	_ground(b, 0, true)
	b.place_tee(1, TEE, 3)
	b.place_cup(1, CUP)
	list.refresh(c)
	assert_eq(list.done_count(), 4)
	while b.can_undo():
		b.undo()
	assert_eq(c.holes.size(), 0, "everything undone")
	list.refresh(c)
	assert_eq(list.done_count(), 4, "the ticks stay")
	assert_false(list.mark(GoalList.TEE), "marking a done goal again changes nothing")
	assert_false(list.mark("no such goal"))


# --- the save ---

func test_the_game_save_keeps_the_ticks_and_the_fold() -> void:
	var s := GameSave.State.new()
	s.course = CourseBuilder.new_course(7)
	s.feed_data = ReactionFeed.new(50, 100).to_save(1)
	var plain := JSON.parse_string(GameSave.to_json(s)) as Dictionary
	assert_false(plain.has("goals"), "a game without goals writes none")
	s.goals_on = true
	s.goals_done = PackedStringArray([GoalList.TEE, GoalList.CUP])
	s.goals_collapsed = true
	var text := GameSave.to_json(s)
	var errors: Array[String] = []
	var back := GameSave.from_json(text, errors)
	assert_eq(errors, [] as Array[String])
	assert_true(back.goals_on)
	assert_eq(back.goals_done, PackedStringArray([GoalList.TEE, GoalList.CUP]))
	assert_true(back.goals_collapsed)
	var old := GameSave.from_json(JSON.stringify(plain), errors)
	assert_false(old.goals_on, "a save from before E10-S1 has no goals")
	for bad: Variant in [[1], {"done": "tee"}, {"done": [3]}, {"done": [], "collapsed": 1}]:
		var d := plain.duplicate(true)
		d["goals"] = bad
		var e: Array[String] = []
		assert_null(GameSave.from_json(JSON.stringify(d), e), "goals %s is refused" % [bad])
		assert_false(e.is_empty())


func test_main_saves_and_loads_the_goals() -> void:
	var m := _main()
	var b: CourseBuilder = m.build_tool.builder
	_ground(b, 0, true)
	b.place_tee(1, TEE, 3)
	m.goals_panel.set_collapsed(true)
	assert_eq(m.save_game(), OK)
	m.new_course(8)
	assert_eq(m.goals.done_count(), 0, "a New course starts its goals afresh")
	assert_false(m.goals.collapsed, "open")
	assert_true(m.load_game())
	assert_not_null(m.goals)
	assert_eq(m.goals.done_ids(), PackedStringArray([GoalList.TEE]))
	assert_true(m.goals.collapsed, "folded as saved")
	assert_true(m.goals_panel.shows_line())
	m.new_sandbox()
	assert_null(m.goals, "a sandbox has no goals")
	assert_false(m.goals_panel.visible)


# --- Main ---

func test_a_new_course_shows_the_goals_in_build() -> void:
	var m := _main()
	assert_not_null(m.goals)
	assert_true(m.goals_panel.visible)
	assert_false(m.goals_panel.shows_line(), "open at the start")
	assert_eq(m.goals_panel.row_texts().size(), GoalList.ORDER.size())
	assert_eq(m.goals_panel.line_text(), "Next: Place a tee")
	assert_true(m.main_menu.goals_button.visible, "the menu has Goals")
	m.set_mode(Main.Mode.PLAY)
	assert_false(m.goals_panel.visible, "Build only")
	m.set_mode(Main.Mode.BUILD)
	assert_true(m.goals_panel.visible)


func test_the_goals_tick_from_the_game() -> void:
	var m := _main()
	var b: CourseBuilder = m.build_tool.builder
	_ground(b, 0, true)
	b.place_tee(1, TEE, 3)
	assert_true(m.goals.is_done(GoalList.TEE), "a builder check ticks the course's goals")
	b.place_cup(1, CUP)
	assert_eq(m.goals.done_count(), 4, "tee, cup, green, open")
	assert_eq(m.goals_panel.line_text(), "Next: Guests arrive and pay")
	# A dusk before any guest is no rating.
	m.guest_sim.day_ended.emit(1, null)
	assert_false(m.goals.is_done(GoalList.STARS), "no guests, no stars")
	m.guest_sim.guest_arrived.emit(null)
	assert_true(m.goals.is_done(GoalList.GUESTS), "a guest arrives and pays")
	assert_gt(m.ledger.fees, 0, "the green fee")
	assert_true(b.buy_parcel(Vector2i(6, 3)), "a parcel next to the block")
	assert_true(m.goals.is_done(GoalList.PARCEL))
	m.guest_sim.day_ended.emit(1, null)
	assert_true(m.goals.is_done(GoalList.STARS), "a day with guests at %s stars" % m.goals.tuning.target_stars)


func test_the_panel_folds_to_its_next_line_and_the_menu_opens_it() -> void:
	var m := _main()
	var panel: GoalsPanel = m.goals_panel
	panel.hide_button.pressed.emit()
	assert_true(m.goals.collapsed)
	assert_true(panel.shows_line())
	assert_true(panel.next_label.visible)
	assert_eq(panel.next_label.text, "Next: Place a tee")
	assert_string_contains(panel.next_label.tooltip_text, "Pick Tee", "its how is the line's tooltip")
	var folded: float = panel.get_combined_minimum_size().y
	assert_lt(folded, 48.0, "one line")
	m.set_mode(Main.Mode.PLAY)
	m.main_menu.goals_button.pressed.emit()
	assert_eq(m.mode, Main.Mode.BUILD, "Goals comes back to Build")
	assert_false(m.goals.collapsed, "and opens the list")
	assert_false(panel.shows_line())
	panel.hide_button.pressed.emit()
	panel.show_button.pressed.emit()
	assert_false(m.goals.collapsed, "its own Goals opens it too")


func test_play_hole_waits_for_a_tee_and_a_cup() -> void:
	var m := _main()
	assert_true(m.mode_button.disabled, "no hole: Play hole is disabled")
	assert_eq(m.mode_button.tooltip_text, Main.NO_HOLE_TIP, "its tooltip says why")
	var tab := InputEventAction.new()
	tab.action = Main.TOGGLE_ACTION
	tab.pressed = true
	m._unhandled_input(tab)
	assert_eq(m.mode, Main.Mode.BUILD, "Tab waits too")
	assert_true(m.save_notice.visible, "and says why")
	assert_string_contains(m.save_notice.label.text, "pick Tee")
	var b: CourseBuilder = m.build_tool.builder
	_ground(b, 0, false)
	b.place_tee(1, TEE, 3)
	assert_true(m.mode_button.disabled, "a tee alone")
	b.place_cup(1, CUP)
	assert_false(m.mode_button.disabled, "a tee and a cup: Play hole")
	assert_ne(m.mode_button.tooltip_text, Main.NO_HOLE_TIP)
	m._unhandled_input(tab)
	assert_eq(m.mode, Main.Mode.PLAY, "and Tab plays it")
	assert_false(m.mode_button.disabled, "Back to Build always works")
	m._unhandled_input(tab)
	assert_eq(m.mode, Main.Mode.BUILD)


func test_the_panel_fits_the_left_column_clear_of_the_free_view() -> void:
	var m := _main()
	m.camera.view_size_override = Vector2(1280, 720)
	await wait_frames(2)
	var r: Rect2 = m._hud_rect(m.goals_panel)
	var fee: Rect2 = m._hud_rect(m.fee_panel)
	assert_true(m.goals_panel in m.hud_controls(), "the free view counts it")
	assert_lte(r.end.x, fee.end.x + 0.5, "no wider than the fee panel: the free view keeps its left edge")
	assert_gte(r.position.y, fee.end.y, "under the fee")
	var palette: Rect2 = m._hud_rect(m.build_palette)
	assert_lte(r.end.y, palette.position.y, "above the bottom bar")
	for ctl: Control in m.hud_controls():
		if ctl != m.goals_panel:
			assert_false(r.intersects(m._hud_rect(ctl)), "it misses %s" % ctl.name)
	for strip: Rect2 in m.free_view_rects():
		assert_false(strip.intersects(r), "the free view misses it")
	gut.p("E10-S1: goals panel at %s, %d px tall" % [r, roundi(r.size.y)])


func test_with_no_room_the_panel_shows_its_line() -> void:
	var m := _main()
	var panel: GoalsPanel = m.goals_panel
	panel.set_room(40.0)
	assert_true(panel.shows_line(), "squeezed to one line")
	assert_false(m.goals.collapsed, "without folding the player's choice")
	assert_false(panel.show_button.visible, "Goals would open nothing")
	panel.set_room(INF)
	assert_false(panel.shows_line())


func test_f6_reaches_the_panel() -> void:
	var m := _main()
	assert_true(m.goals_panel in m.hud_focus.stops)
	assert_true(m.goals_panel in m.hud_focus.shown_stops(), "shown in Build")
	assert_true(m.hud_focus.enter(m.goals_panel))
	assert_same(m.get_viewport().gui_get_focus_owner(), m.goals_panel.hide_button)
	m.hud_focus.set_active(false)


func test_the_clubhouse_tool_says_what_the_clubhouse_does() -> void:
	var m := _main()
	var tip: String = m.build_palette.clubhouse_button.tooltip_text
	assert_string_contains(tip, "guests arrive")
	assert_string_contains(tip, "leave")
