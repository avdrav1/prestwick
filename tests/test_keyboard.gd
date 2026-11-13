extends GutTest
## E5-S6: every Build and Play action by keyboard, with a focus you can see. These tests drive the
## main scene with key events alone, through the viewport as the keyboard would
## (Viewport.push_input: the HUD's focus, then the unhandled keys), never a mouse event or a
## builder call: one hole is built, opened, played out and the game taken back to Build. Time
## passing for the swing bar (SwingControl.advance) and the ball (ShotView.advance) is the only
## thing they do besides keys. The by-hand check with the mouse unplugged stays the user's.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FLAT_PATH := "res://tests/fixtures/flat_20x20.json"
## Hole 1 of the keyboard build: a 70 yd par 3 along y = 10 of the flat 20 x 20 rough.
const TEE := Vector2i(3, 10)
const CUP := Vector2i(17, 10)
## Strokes before the play-out gives up (double par picks the ball up at 6 anyway).
const MAX_STROKES: int = 10
const GuestCourse := preload("res://tests/fixtures/guest_course.gd")

## E8-S4: the manual save these tests write, not the player's.
const SAVE_PATH := "user://test_keyboard_save.json"

var _m: Main


func before_each() -> void:
	_m = MAIN_SCENE.instantiate() as Main
	_m.course_path = FLAT_PATH
	add_child_autofree(_m)
	# Time passes only where a test says so.
	_m.shot_view.set_process(false)
	_m.swing_control.set_process(false)
	_m.camera.set_process(false)
	_m.guest_sim.set_process(false)
	_m.feed_panel.set_process(false)
	_m.save_path = SAVE_PATH


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


# --- keys ---

func _key(code: Key, pressed: bool = true, shift: bool = false, ctrl: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	return e


func _push(e: InputEvent) -> void:
	_m.get_viewport().push_input(e)


## One key pressed and let go.
func _tap(code: Key, shift: bool = false, ctrl: bool = false) -> void:
	_push(_key(code, true, shift, ctrl))
	_push(_key(code, false, shift, ctrl))


func _focus() -> Control:
	return _m.get_viewport().gui_get_focus_owner()


## Arrows until the Build cursor is on `cell` (the first arrow puts it on the map).
func _cursor_to(cell: Vector2i) -> void:
	var t: BuildTool = _m.build_tool
	if t.hover == TilePicker.NONE:
		_tap(KEY_RIGHT)
	var guard: int = 0
	while t.hover != cell and guard < 400:
		var d: Vector2i = cell - t.hover
		if d.x != 0:
			_tap(KEY_RIGHT if d.x > 0 else KEY_LEFT)
		else:
			_tap(KEY_DOWN if d.y > 0 else KEY_UP)
		guard += 1
	assert_eq(t.hover, cell, "the cursor reaches %s by arrows" % cell)


## E (next tool) until `done` holds, at most once round the palette.
func _tool_until(done: Callable) -> void:
	for i: int in 20:
		if done.call():
			return
		_tap(KEY_E)
	assert_true(done.call(), "E reaches the tool")


func _paint_tool(s: Surface.Type) -> Callable:
	return func() -> bool: return _m.build_tool.tool == BuildTool.Tool.PAINT and _m.build_tool.surface == s


## Two frames, so the HUD's containers lay out (focus moves by where controls are drawn).
func _layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## F6 until the keyboard is in `stop`, at most once round the stops (after a layout).
func _f6_to(stop: Control) -> void:
	await _layout()
	for i: int in 12:
		_tap(KEY_F6)
		if _focus() != null and (stop == _focus() or stop.is_ancestor_of(_focus())):
			return
	fail_test("F6 never reached %s" % stop.name)


# --- build and play one hole ---

func test_one_hole_built_opened_and_played_out_with_keys_alone() -> void:
	var t: BuildTool = _m.build_tool
	var c: CourseData = _m.course
	assert_true(c.holes.is_empty(), "the flat plot starts with no hole")
	# The hole panel: F6 to it, Up to New hole, Enter.
	await _f6_to(_m.hole_panel)
	for i: int in 4:
		if _focus() == _m.hole_panel.new_hole_button:
			break
		_tap(KEY_UP)
	assert_eq(_focus(), _m.hole_panel.new_hole_button, "Up reaches New hole")
	_tap(KEY_ENTER)
	assert_eq(t.tool, BuildTool.Tool.TEE, "New hole picks the Tee tool")
	_tap(KEY_ESCAPE)
	assert_null(_focus(), "Esc hands the keys back to the map")
	# The tee and the cup, placed with the cursor.
	_cursor_to(TEE)
	_tap(KEY_SPACE)
	assert_eq(c.holes.size(), 1, "Space placed the tee: hole 1")
	assert_eq(c.holes[0].tee, TEE)
	_tool_until(func() -> bool: return t.tool == BuildTool.Tool.CUP)
	_cursor_to(CUP)
	# E8-S5: the ruler follows the keyboard cursor from the tee.
	t.ruler.refresh()
	assert_true(t.ruler.ruler_shown, "the Cup tool's ruler shows at the keyboard cursor")
	assert_eq(t.ruler.ruler_line[t.ruler.ruler_line.size() - 1], Vector2(CUP), "it ends on the cursor")
	assert_eq(t.ruler.ruler_text(), "70 yd: par 3")
	_tap(KEY_LEFT)
	t.ruler.refresh()
	assert_eq(t.ruler.ruler_line[t.ruler.ruler_line.size() - 1], Vector2(CUP - Vector2i(1, 0)), "an arrow moves it")
	assert_eq(t.ruler.ruler_text(), "65 yd: par 3")
	_tap(KEY_RIGHT)
	_tap(KEY_ENTER)
	assert_eq(c.holes[0].cup, CUP, "Enter placed the cup")
	# A green round the cup with the 3 brush, and a fairway dragged with Space held.
	_tool_until(_paint_tool(Surface.Type.GREEN))
	_tap(KEY_BRACKETRIGHT)
	assert_eq(t.brush_size, 3, "] steps the brush up")
	_tap(KEY_SPACE)
	for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, 0), Vector2i(1, 1)]:
		assert_eq(c.get_surface(CUP.x + d.x, CUP.y + d.y), Surface.Type.GREEN, "green at %s" % (CUP + d))
	_tap(KEY_BRACKETLEFT)
	assert_eq(t.brush_size, 1, "[ steps it down")
	_tool_until(_paint_tool(Surface.Type.FAIRWAY))
	_cursor_to(Vector2i(6, 10))
	_push(_key(KEY_SPACE))
	for i: int in 6:
		_tap(KEY_RIGHT)
	_push(_key(KEY_SPACE, false))
	for x: int in range(6, 13):
		assert_eq(c.get_surface(x, 10), Surface.Type.FAIRWAY, "the held drag painted (%d, 10)" % x)
	assert_eq(c.get_surface(13, 10), Surface.Type.ROUGH, "and stopped at the key's release")
	assert_eq(c.get_surface(6, 9), Surface.Type.ROUGH, "one tile wide")
	# Ctrl+Z takes the drag back as one step, and E/Q round again to paint it once more.
	_tap(KEY_Z, false, true)
	assert_eq(c.get_surface(8, 10), Surface.Type.ROUGH, "Ctrl+Z undid the whole drag")
	_tap(KEY_Q)
	_tap(KEY_E)
	assert_eq(t.surface, Surface.Type.FAIRWAY, "Q then E come back to fairway")
	# Open it and play it from its row: F6 to the hole panel lands on the picked row.
	await _f6_to(_m.hole_panel)
	var row: HolePanel.HoleRow = _m.hole_panel.row_for(1)
	assert_eq(_focus(), row.pick_button, "F6 lands on the picked hole's row")
	_tap(KEY_RIGHT)
	assert_eq(_focus(), row.open_button, "Right reaches its Open")
	_tap(KEY_ENTER)
	assert_true(c.holes[0].open, "Enter opened the hole (every rule passes)")
	_tap(KEY_RIGHT)
	assert_eq(_focus(), row.play_button, "Right reaches its Play")
	_tap(KEY_SPACE)
	assert_eq(_m.mode, Main.Mode.PLAY, "Space on Play plays the hole")
	assert_null(_focus(), "the hole panel hid: the keys are on the map")
	# The bar speed, by keyboard: F6 to the swing panel, Right to the slider, Left twice.
	var sc: SwingControl = _m.swing_control
	var speed: float = sc.swing.bar_speed
	await _f6_to(_m.swing_panel)
	for i: int in 4:
		if _focus() == _m.swing_panel.speed_slider:
			break
		_tap(KEY_RIGHT)
	assert_eq(_focus(), _m.swing_panel.speed_slider, "Right reaches the bar speed")
	_tap(KEY_LEFT)
	_tap(KEY_LEFT)
	assert_almost_eq(sc.swing.bar_speed, speed - 0.1, 0.001, "Left slows the bar")
	_tap(KEY_ESCAPE)
	assert_null(_focus())
	# Play it out: aim with Left/Right, club with Up/Down, Space three times.
	var n: int = 0
	while not sc.is_finished() and n < MAX_STROKES:
		_aim_at_cup(sc)
		var plan: Array = _plan(sc)
		assert_false(plan.is_empty(), "stroke %d can be planned" % (n + 1))
		if plan.is_empty():
			break
		_club_to(sc, plan[0])
		_swing(sc, plan[1])
		assert_true(_m.shot_view.playing, "stroke %d is struck by Space" % (n + 1))
		_finish_shot()
		n += 1
	assert_true(sc.is_finished(), "the hole is finished")
	assert_true(sc.score.holed, "holed out, not picked up (%d strokes)" % sc.score.strokes)
	assert_lte(sc.score.strokes, 5, "in a sensible score")
	_tap(KEY_TAB)
	assert_eq(_m.mode, Main.Mode.BUILD, "Tab goes back to Build")


## Left or Right until the aim is within half a step of the cup.
func _aim_at_cup(sc: SwingControl) -> void:
	var cup: Vector2 = sc.field.tile_center(sc.cup_tile())
	var want: float = rad_to_deg((cup - sc.ball_at).angle())
	var d: float = wrapf(want - sc.aim_deg, -180.0, 180.0)
	var steps: int = roundi(absf(d) / sc.tuning.aim_key_step_deg)
	for i: int in steps:
		_tap(KEY_RIGHT if d > 0.0 else KEY_LEFT)
	assert_lte(absf(wrapf(want - sc.aim_deg, -180.0, 180.0)), sc.tuning.aim_key_step_deg * 0.5 + 0.001,
			"the aim keys point at the cup")


## [club, ticks]: the scripted player's pick at the aim the keys set (ScriptedRound.predict):
## one that holes, else the one resting nearest the cup.
func _plan(sc: SwingControl) -> Array:
	var target: Vector2 = sc.field.tile_center(sc.cup_tile())
	var best: Array = []
	var best_d: float = INF
	for club: Club in sc.legal:
		var options: Array = range(1, ScriptedRound.ticks_for(sc, 1.0) + 1) if club.is_putter() \
				else ScriptedRound.FULL_TICKS
		for ticks: int in options:
			var p: ShotPrediction = ScriptedRound.predict(sc, club, sc.aim_deg, ticks)
			if p.holed:
				return [club, ticks]
			if p.penalty_strokes > 0:
				continue
			var d: float = Vector2(p.rest.x, p.rest.y).distance_to(target)
			if d < best_d:
				best_d = d
				best = [club, ticks]
	return best


## Up (longer) or Down (shorter) until `club` is in hand.
func _club_to(sc: SwingControl, club: Club) -> void:
	for i: int in sc.legal.size():
		if sc.club == club:
			break
		_tap(KEY_DOWN if sc.legal.find(club) > sc.legal.find(sc.club) else KEY_UP)
	assert_eq(sc.club, club, "Up and Down reach the %s" % club.id)


## Space to start, Space at `ticks` for the power, Space `ticks` later at the centre.
func _swing(sc: SwingControl, ticks: int) -> void:
	_tap(KEY_SPACE)
	for i: int in ticks:
		sc.advance(Ball.DT)
	_tap(KEY_SPACE)
	for i: int in ticks:
		sc.advance(Ball.DT)
	_tap(KEY_SPACE)


func _finish_shot() -> void:
	var i: int = 0
	while _m.shot_view.playing and i < 10000:
		_m.shot_view.advance(0.25)
		i += 1


# --- the rest of the HUD ---

func test_f6_shows_a_focus_ring_and_a_click_takes_it_away() -> void:
	var fairway: Button = _m.build_palette.surface_buttons[0]
	assert_eq(fairway.focus_mode, Control.FOCUS_NONE, "no focus before F6: a click never leaves a button holding Space")
	await _layout()
	_tap(KEY_F6)
	assert_eq(_focus(), fairway, "F6 lands on the tool in hand")
	var ring := fairway.get_theme_stylebox(&"focus") as StyleBoxFlat
	assert_not_null(ring)
	assert_eq(ring.border_color, _m.hud_focus.focus_color, "the ring is the focus colour")
	assert_eq(ring.border_width_left, _m.hud_focus.focus_width)
	_tap(KEY_RIGHT)
	_tap(KEY_SPACE)
	assert_eq(_m.build_tool.surface, CourseBuilder.PALETTE[1], "Right then Space picks the next surface")
	_tap(KEY_F6, true)
	var shown: Array[Control] = _m.hud_focus.shown_stops()
	assert_eq(_m.hud_focus._stop_of(_focus()), shown[shown.size() - 1], "Shift+F6 from the first stop goes round to the last")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(640, 360)
	_m.hud_focus._input(click)
	assert_false(_m.hud_focus.active)
	assert_null(_focus(), "a click hands the keys back")
	assert_eq(fairway.focus_mode, Control.FOCUS_NONE, "and the buttons take no focus again")


func test_tab_from_the_hud_still_switches_build_and_play() -> void:
	# E10-S1: Tab plays only a hole with a tee and a cup.
	_m.build_tool.builder.place_tee(1, Vector2i(3, 10), 3)
	_m.build_tool.builder.place_cup(1, Vector2i(15, 10))
	_tap(KEY_F6)
	assert_not_null(_focus())
	_tap(KEY_TAB)
	assert_eq(_m.mode, Main.Mode.PLAY, "Tab is Build and Play, never focus")
	assert_null(_focus())


func test_every_build_tool_is_in_reach_of_q_and_e() -> void:
	var seen: Array = []
	for i: int in _m.build_tool.tool_order().size():
		seen.append([_m.build_tool.tool, _m.build_tool.surface if _m.build_tool.tool == BuildTool.Tool.PAINT else -1])
		_tap(KEY_E)
	assert_eq(_m.build_tool.tool, BuildTool.Tool.PAINT, "E wraps round to the first surface")
	for s: Surface.Type in CourseBuilder.PALETTE:
		assert_has(seen, [BuildTool.Tool.PAINT, s], Surface.name_of(s))
	for tool: BuildTool.Tool in [BuildTool.Tool.RAISE, BuildTool.Tool.LOWER, BuildTool.Tool.TEE,
			BuildTool.Tool.CUP, BuildTool.Tool.CLUBHOUSE, BuildTool.Tool.DECOR]:
		assert_has(seen, [tool, -1], BuildTool.Tool.keys()[tool])
	assert_false(seen.has([BuildTool.Tool.BUY, -1]), "no Buy land in a sandbox, where it is hidden")
	_tap(KEY_Q)
	assert_eq(_m.build_tool.tool, BuildTool.Tool.DECOR, "Q goes back round (E5-S3: Decor is last)")


func test_raise_lower_and_the_clubhouse_and_its_turn_by_keys() -> void:
	var c: CourseData = _m.course
	var t: BuildTool = _m.build_tool
	_tool_until(func() -> bool: return t.tool == BuildTool.Tool.RAISE)
	_cursor_to(Vector2i(4, 4))
	_tap(KEY_SPACE)
	assert_eq(c.get_height(4, 4), 1, "Raise by Space")
	_tool_until(func() -> bool: return t.tool == BuildTool.Tool.LOWER)
	_tap(KEY_SPACE)
	assert_eq(c.get_height(4, 4), 0, "Lower by Space")
	_tool_until(func() -> bool: return t.tool == BuildTool.Tool.CLUBHOUSE)
	_cursor_to(Vector2i(10, 6))
	_tap(KEY_SPACE)
	assert_eq(c.clubhouse, Vector2i(10, 6), "Space moves the clubhouse to the cursor")
	var facing: int = c.clubhouse_facing
	_tap(KEY_R)
	assert_ne(c.clubhouse_facing, facing, "R turns its door")
	assert_eq(c.clubhouse, Vector2i(10, 6), "in place")


func test_buy_land_by_keys() -> void:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	var block: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), Vector2i(p, q) in block)
	c.set_land_budget(5000)
	_m.show_course(c)
	var t: BuildTool = _m.build_tool
	_tool_until(func() -> bool: return t.tool == BuildTool.Tool.BUY)
	var parcel := Vector2i(2, 3)
	_cursor_to(parcel * CourseData.PARCEL_TILES + Vector2i(8, 8))
	_tap(KEY_SPACE)
	assert_eq(_m.land_panel.pending_parcel, parcel, "Space asks to buy the parcel under the cursor")
	_tap(KEY_ENTER)
	assert_true(c.is_parcel_owned(parcel), "Enter buys it")


func test_hole_panel_par_and_close_by_keys() -> void:
	_m.show_course(_course_with_hole())
	await _f6_to(_m.hole_panel)
	var row: HolePanel.HoleRow = _m.hole_panel.row_for(1)
	assert_eq(_focus(), row.pick_button)
	# Down from the row to the par row (its Open), Left to 4.
	var panel: HolePanel = _m.hole_panel
	for i: int in 4:
		if _focus() == panel.open_button or panel.par_buttons.has(_focus()):
			break
		_tap(KEY_DOWN)
	assert_true(_focus() == panel.open_button or panel.par_buttons.has(_focus()), "Down reaches the par row")
	assert_eq(_focus(), panel.open_button, "on its Open")
	_tap(KEY_ENTER)
	assert_true(_m.course.holes[0].open, "Enter on the panel's Open opens the hole")
	# Up to the row, Right to its Close.
	await _layout()
	for i: int in 6:
		if _focus() == row.open_button:
			break
		_tap(KEY_UP if _row_of(_focus()) == null else KEY_RIGHT)
	assert_eq(_focus(), row.open_button)
	assert_eq(row.open_button.text, "Close")
	_tap(KEY_ENTER)
	assert_false(_m.course.holes[0].open, "Enter on the row's Close closes it")
	await _layout()
	for i: int in 6:
		if _focus() == panel.open_button or panel.par_buttons.has(_focus()):
			break
		_tap(KEY_DOWN)
	for i: int in 4:
		if _focus() == panel.par_buttons[1]:
			break
		_tap(KEY_LEFT if _focus() == panel.open_button or panel.par_buttons.find(_focus()) > 1 else KEY_RIGHT)
	assert_eq(_focus(), panel.par_buttons[1], "Left reaches par 4")
	_tap(KEY_ENTER)
	assert_eq(_m.course.holes[0].par, 4, "Enter on 4 sets par 4")


func test_speed_buttons_and_fee_slider_by_keys() -> void:
	var sim: GuestSim = _m.guest_sim
	await _f6_to(_m.sim_speed_panel)
	assert_eq(_focus(), _m.sim_speed_panel.buttons[sim.speed], "F6 lands on the speed in force")
	_tap(KEY_LEFT)
	_tap(KEY_ENTER)
	assert_eq(sim.speed, 0.0, "Left then Enter pauses")
	await _f6_to(_m.fee_panel)
	assert_eq(_focus(), _m.fee_panel.slider)
	var fee: int = sim.fee
	_tap(KEY_LEFT)
	assert_eq(sim.fee, fee - 1, "Left lowers the fee")


func test_a_feed_line_jumps_to_its_hole_by_keys() -> void:
	_m.show_course(GuestCourse.course())
	_m.set_mode(Main.Mode.PLAY)
	var r := GuestReaction.new()
	r.hole_number = 2
	r.kind = GuestReaction.Kind.COMPLAINT
	r.text = "Hole 2: too hard."
	_m.guest_sim.feed.push(r, 1, 10)
	_m.feed_panel.tick(30.0)
	await _f6_to(_m.feed_panel)
	_tap(KEY_ENTER)
	assert_eq(_m.mode, Main.Mode.BUILD, "Enter on a line jumps to Build")
	assert_eq(_m.build_tool.hole_number, 2, "and picks its hole")


func test_a_hole_row_tag_jumps_by_keys() -> void:
	_m.show_course(GuestCourse.course())
	var r := GuestReaction.new()
	r.hole_number = 2
	r.kind = GuestReaction.Kind.PRAISE
	r.text = "Hole 2: loved it."
	_m.guest_sim.feed.push(r, 1, 10)
	_m.hole_panel.set_collapsed(false)
	var row: HolePanel.HoleRow = _m.hole_panel.row_for(2)
	assert_true(row.tag_button.visible, "hole 2 has a map tag")
	await _f6_to(_m.hole_panel)
	for i: int in 12:
		if _focus() == row.tag_button:
			break
		var at: HolePanel.HoleRow = _row_of(_focus())
		if at == null or at.number < 2:
			_tap(KEY_DOWN)
		else:
			_tap(KEY_RIGHT)
	assert_eq(_focus(), row.tag_button, "the arrows reach hole 2's tag")
	_tap(KEY_ENTER)
	assert_eq(_m.build_tool.hole_number, 2, "Enter on the tag picks and frames its hole, as the map tag does")


func _row_of(c: Control) -> HolePanel.HoleRow:
	for r: HolePanel.HoleRow in _m.hole_panel.shown_rows():
		if r.is_ancestor_of(c):
			return r
	return null


func test_save_notice_closes_by_esc_and_its_ok_is_in_reach() -> void:
	_tap(KEY_F5)
	assert_true(_m.save_notice.visible, "F5 saves and says so")
	_tap(KEY_ESCAPE)
	assert_false(_m.save_notice.visible, "Esc closes the notice")
	_tap(KEY_F5)
	_tap(KEY_ENTER)  # E8-S4: over the saved game F5 asks first
	_tap(KEY_F6, true)
	assert_eq(_focus(), _m.save_notice.ok_button, "Shift+F6 from the map reaches the notice's OK last in the round")
	_tap(KEY_ENTER)
	assert_false(_m.save_notice.visible)


func test_f1_opens_the_key_map_and_esc_closes_it() -> void:
	assert_true(_m.help_overlay.hint_label.visible)
	assert_eq(_m.help_overlay.hint_label.text, "F1: keys", "the way in is on screen")
	_tap(KEY_F1)
	assert_true(_m.help_overlay.is_open())
	_tap(KEY_ESCAPE)
	assert_false(_m.help_overlay.is_open())
	_tap(KEY_F1)
	_tap(KEY_F1)
	assert_false(_m.help_overlay.is_open(), "F1 closes it too")


func test_the_key_map_names_every_action_and_its_keys() -> void:
	var listed: Array[StringName] = HelpOverlay.listed_actions()
	for action: StringName in InputMap.get_actions():
		var a := String(action)
		if a.begins_with("ui_") or a == "debug_shot" or a.begins_with("gut_"):
			continue
		assert_has(listed, action, "%s is in the key map" % a)
	for action: StringName in listed:
		assert_ne(HelpOverlay.key_text(action), "", "%s has a key" % action)
	assert_eq(HelpOverlay.key_text(&"hud_focus_prev"), "Shift+F6")
	assert_eq(HelpOverlay.key_text(&"brush_larger"), "]", "named as the key cap")
	assert_eq(HelpOverlay.key_text(&"build_apply"), "Space or Enter or keypad Enter")


## Hole 1, a passing par 3 (TEE to CUP on the flat plot, a green round the cup), closed.
func _course_with_hole() -> CourseData:
	var c := CourseData.create(20, 20, Surface.Type.ROUGH, 0)
	for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0),
			Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		c.set_tile(CUP.x + d.x, CUP.y + d.y, 0, Surface.Type.GREEN)
	c.set_holes([HoleData.new(1, 3, TEE, CUP, false)])
	return c


func test_the_camera_follows_the_build_cursor_off_the_free_view() -> void:
	_m.new_sandbox()
	_m.camera.view_size_override = Vector2(1280, 720)
	var t: BuildTool = _m.build_tool
	_tap(KEY_RIGHT)
	var start: Vector2 = _m.camera.focus
	var inside: bool = _m.free_view_rect().has_point(_m.camera.screen_point(_m.tile_world(t.hover)))
	assert_true(inside, "the cursor starts in the free view, at the middle of the screen")
	for i: int in 40:
		_tap(KEY_RIGHT)
	assert_true(_m.camera.tracking, "the camera took the cursor up")
	assert_ne(_m.camera.focus, start)
	assert_eq(_m.camera.focus, _m.tile_world(t.hover), "centred on the cursor once it neared the edge")


func test_the_main_menu_keeps_its_focus_from_f6_and_esc_goes_in_order() -> void:
	_tap(KEY_F6)
	assert_not_null(_focus())
	_tap(KEY_ESCAPE)
	assert_false(_m.main_menu.visible, "the first Esc only hands the HUD's keys back to the map")
	_tap(KEY_F1)
	_tap(KEY_ESCAPE)
	assert_false(_m.help_overlay.is_open(), "Esc closes the key map first")
	assert_false(_m.main_menu.visible, "and does not open the menu with it")
	_tap(KEY_ESCAPE)
	assert_true(_m.main_menu.visible, "then Esc opens the menu")
	var menu_focus: Control = _focus()
	assert_true(menu_focus != null and _m.main_menu.is_ancestor_of(menu_focus), "the menu holds the focus")
	_tap(KEY_F6)
	_tap(KEY_F6, true)
	assert_eq(_focus(), menu_focus, "F6 never takes it while the menu is open")
	assert_false(_m.hud_focus.active)
	_tap(KEY_ESCAPE)
	assert_false(_m.main_menu.visible, "Esc on the menu closes it")
	_tap(KEY_F2)
	assert_true(_m.audio_panel.visible, "F2 opens the sound panel")
	var sound_focus: Control = _focus()
	_tap(KEY_F6)
	assert_eq(_focus(), sound_focus, "nor while the sound panel is open")
	_tap(KEY_ESCAPE)
	assert_false(_m.audio_panel.visible)


# --- E8-S4: the save and load questions ---

func test_f5_over_a_saved_game_asks_and_esc_leaves_it() -> void:
	_tap(KEY_F5)
	assert_false(_m.confirm_dialog.visible, "no saved game yet: F5 saves straight away")
	assert_true(FileAccess.file_exists(SAVE_PATH))
	_tap(KEY_ESCAPE)
	var saved := FileAccess.get_file_as_string(SAVE_PATH)
	_m.build_tool.builder.paint(Vector2i(5, 5), Surface.Type.FAIRWAY, 1)
	_tap(KEY_F5)
	assert_true(_m.confirm_dialog.visible, "now F5 asks")
	assert_eq(_m.confirm_dialog.label.text, "Save over your saved game from Day 1?")
	assert_eq(_focus(), _m.confirm_dialog.yes_button, "the question has the keys, on yes")
	# While it asks, no other key reaches the game.
	_tap(KEY_TAB)
	assert_eq(_m.mode, Main.Mode.BUILD, "Tab moves between the answers, not Build and Play")
	assert_true(_m.confirm_dialog.is_ancestor_of(_focus()))
	_tap(KEY_F6)
	assert_false(_m.hud_focus.active, "F6 does not take the keys from it")
	_tap(KEY_F9)
	assert_eq(_m.confirm_dialog.label.text, "Save over your saved game from Day 1?", "nor F9")
	_tap(KEY_ESCAPE)
	assert_false(_m.confirm_dialog.visible, "Esc answers no")
	assert_false(_m.main_menu.visible, "and does not open the menu with it")
	assert_eq(FileAccess.get_file_as_string(SAVE_PATH), saved, "the saved game is as it was")
	_tap(KEY_F5)
	_tap(KEY_ENTER)
	assert_false(_m.confirm_dialog.visible)
	assert_ne(FileAccess.get_file_as_string(SAVE_PATH), saved, "Enter saves over it")
	assert_string_starts_with(_m.save_notice.label.text, "Saved day 1")


func test_f9_asks_before_it_replaces_the_game() -> void:
	_tap(KEY_F5)
	_tap(KEY_ESCAPE)
	var c: CourseData = _m.course
	_tap(KEY_F9)
	assert_true(_m.confirm_dialog.visible)
	assert_eq(_m.confirm_dialog.label.text, "Load Day 1 and lose today's progress?")
	assert_eq(_focus(), _m.confirm_dialog.yes_button)
	_tap(KEY_ESCAPE)
	assert_same(_m.course, c, "Esc keeps the game in play")
	_tap(KEY_F9)
	_tap(KEY_RIGHT)
	assert_eq(_focus(), _m.confirm_dialog.no_button, "the arrows move to Cancel")
	_tap(KEY_ENTER)
	assert_same(_m.course, c, "Enter on Cancel answers no")
	_tap(KEY_F9)
	_tap(KEY_ENTER)
	assert_not_same(_m.course, c, "Enter on yes loads")
	assert_eq(_m.save_notice.label.text, "Loaded day 1.")


func test_the_question_comes_first_in_the_esc_order() -> void:
	_tap(KEY_F5)  # the notice is up
	_tap(KEY_F1)
	assert_true(_m.help_overlay.is_open())
	_tap(KEY_F9)
	assert_true(_m.confirm_dialog.visible)
	_tap(KEY_ESCAPE)
	assert_false(_m.confirm_dialog.visible, "Esc closes the question first")
	assert_true(_m.help_overlay.is_open(), "then the key map")
	assert_true(_m.save_notice.visible, "and the notice are still up")
	_tap(KEY_ESCAPE)
	assert_false(_m.help_overlay.is_open())
	_tap(KEY_ESCAPE)
	assert_false(_m.save_notice.visible)
	_tap(KEY_ESCAPE)
	assert_true(_m.main_menu.visible, "the menu last")


func test_the_menus_load_page_lists_the_saves_and_asks_before_loading() -> void:
	_tap(KEY_F5)
	_tap(KEY_ESCAPE)
	var c: CourseData = _m.course
	_tap(KEY_ESCAPE)
	assert_true(_m.main_menu.visible)
	for i in MainMenu.LOAD_INDEX:
		_tap(KEY_TAB)
	assert_eq(_focus(), _m.main_menu.main_buttons()[MainMenu.LOAD_INDEX])
	_tap(KEY_ENTER)
	assert_true(_m.main_menu.load_page.visible, "Load game opens the Load page")
	var picks := _m.main_menu.load_buttons()
	assert_eq(picks.size(), 1, "the saved game (no autosave yet)")
	assert_string_starts_with(picks[0].text, "Saved game: Day 1, ")
	assert_eq(_focus(), picks[0])
	_tap(KEY_ENTER)
	assert_true(_m.confirm_dialog.visible, "picking it asks")
	assert_eq(_focus(), _m.confirm_dialog.yes_button)
	_tap(KEY_ESCAPE)
	assert_true(_m.main_menu.load_page.visible, "no goes back to the Load page")
	assert_same(_m.course, c)
	_tap(KEY_ENTER)
	_tap(KEY_ENTER)
	assert_false(_m.main_menu.visible)
	assert_not_same(_m.course, c, "yes loads it")
	_tap(KEY_ESCAPE)  # the notice
	_tap(KEY_ESCAPE)
	for i in MainMenu.SAVE_INDEX:
		_tap(KEY_TAB)
	assert_eq(_focus(), _m.main_menu.main_buttons()[MainMenu.SAVE_INDEX])
	_tap(KEY_ENTER)
	assert_true(_m.confirm_dialog.visible, "Save game asks too, over the saved game")
	_tap(KEY_ESCAPE)
	assert_true(_m.main_menu.visible, "and no goes back to the menu")
	assert_eq(_focus(), _m.main_menu.main_buttons()[MainMenu.SAVE_INDEX])
