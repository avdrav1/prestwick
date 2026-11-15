class_name HelpOverlay
extends Control
## E5-S6: the key map, where a player finds it. A small "F1: keys" line at the top of the screen
## says it is there; F1 (help_toggle) opens a panel over the map listing every key of Build and
## Play, and F1 or Esc closes it. The keys are read from the InputMap (key_text), so the panel
## says what project.godot binds, never a copy of it; SECTIONS says what each action does.
## E8-S5: under the keys, how far each club goes (club_text, from golf/clubs.tres), so a player
## can size a hole. E20-S1 (D74): under them, the shot shapes and how far each bends
## (shape_text, from golf/shot_shapes.tres and the clubs' shape_scale).

const TOGGLE_ACTION: StringName = &"help_toggle"
const CLOSE_ACTION: StringName = &"ui_cancel"

## [title, [[actions, what they do], ...]] in the panel's order. Actions joined by "/" share a
## line ("Left / Right").
const SECTIONS: Array = [
	["Anywhere", [
		[[&"toggle_mode"], "Switch Build and Play"],
		[[&"hud_focus_next", &"hud_focus_prev"], "Keys to the next / previous panel of buttons. There: arrows move, Space or Enter presses, Left / Right move a slider, Esc goes back to the map"],
		[[&"help_toggle"], "This help (Esc closes it)"],
		[[&"menu"], "Main menu: new course, load, save, import, export, sound, goals, quit (Esc again closes it; a key map, notice or parcel asked about takes Esc first)"],
		[[&"audio_settings"], "Sound volumes (Esc closes them)"],
		[[&"save_game", &"load_game"], "Save / load the game (each asks first; Esc closes the notice)"],
		[[&"sim_pause", &"sim_speed_1", &"sim_speed_3"], "Pause / run the guests' day at 1x / 3x"],
		[[&"sim_skip"], "Skip to morning"],
		[[&"pan_up", &"pan_left", &"pan_down", &"pan_right"], "Pan the view"],
		[[&"zoom_in", &"zoom_out"], "Zoom in / out"],
		[[&"snap_camera"], "Back to the ball"],
	]],
	["Build", [
		[[&"build_cursor_up", &"build_cursor_left", &"build_cursor_down", &"build_cursor_right"], "Move the cursor a tile"],
		[[&"build_apply"], "Use the tool at the cursor; hold it while moving to drag"],
		[[&"build_tool_prev", &"build_tool_next"], "Previous / next tool"],
		[[&"brush_smaller", &"brush_larger"], "Smaller / larger brush"],
		[[&"clubhouse_turn"], "Turn the clubhouse door (with Decor: take decor away)"],
		[[&"ui_undo"], "Undo"],
		[[&"buy_confirm", &"buy_cancel"], "Buy / cancel the parcel asked about"],
	]],
	["Play", [
		[[&"swing"], "Swing: start, power, accuracy"],
		[[&"aim_left", &"aim_right"], "Aim left / right"],
		[[&"club_prev", &"club_next"], "Longer / shorter club"],
		[[&"shape_prev", &"shape_next"], "Shot shape: bend more left / more right (Hook, Draw, Straight, Fade, Slice), before the swing"],
		[[&"toggle_green_view"], "Green view"],
		[[&"toggle_topo"], "Contours on / off"],
	]],
]

## E20-S1: the two columns' widths, px: the keys, what they do, and the gap between columns.
const KEYS_WIDTH: float = 170.0
const WHAT_WIDTH: float = 340.0
const COLUMN_GAP: int = 28

## Godot's key names a player would not read as the key cap, and what the panel says instead.
const KEY_NAMES: Dictionary = {
	"BracketLeft": "[", "BracketRight": "]", "Kp Add": "keypad +", "Kp Subtract": "keypad -",
	"Kp Enter": "keypad Enter", "Equal": "=", "Minus": "-",
}

## The panel with the key map (hidden until F1).
var panel: PanelContainer
## The "F1: keys" line, always shown.
var hint_label: Label
## The panel's rows, [keys, what] as shown, for tests.
var lines: Array[PackedStringArray] = []
## E8-S5: the club line as shown (club_text).
var clubs_label: Label
## E20-S1: the shot shape line as shown (shape_text).
var shapes_label: Label


func _ready() -> void:
	# The hint's own size at the top centre, so the HUD round it (LandPanel.hud_rects) counts
	# only the hint; the key map is top_level, placed in the middle of the viewport when opened.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label = Label.new()
	hint_label.name = "Hint"
	hint_label.text = "%s: keys" % key_text(TOGGLE_ACTION)
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	add_child(hint_label)
	var hint_size: Vector2 = hint_label.get_combined_minimum_size()
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -hint_size.x * 0.5
	offset_right = hint_size.x * 0.5
	offset_top = 0.0
	offset_bottom = hint_size.y
	panel = PanelContainer.new()
	panel.name = "Keys"
	panel.visible = false
	panel.top_level = true
	var style: StyleBox = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var opaque := style.duplicate() as StyleBoxFlat
		opaque.bg_color = Color(0.1, 0.1, 0.12, 0.96)
		opaque.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", opaque)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	# E20-S1: two columns, Anywhere on the left and Build then Play on the right, each one grid
	# so its keys and what they do line up, so the map and its notes fit a 1280 x 720 window
	# (one column of every section ran past its foot once the clubs and shapes were added).
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	box.add_child(columns)
	var grid: GridContainer = null
	for i: int in SECTIONS.size():
		var section: Array = SECTIONS[i]
		if i == 0 or i == 1:
			grid = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 12)
			columns.add_child(grid)
		var title := Label.new()
		title.text = section[0]
		title.add_theme_color_override("font_color", Color8(240, 200, 58))
		grid.add_child(title)
		grid.add_child(Control.new())
		for row: Array in section[1]:
			var keys := PackedStringArray()
			for action: StringName in row[0]:
				keys.append(key_text(action))
			var k := Label.new()
			k.text = " / ".join(keys)
			k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			k.custom_minimum_size = Vector2(KEYS_WIDTH, 0)
			k.add_theme_font_size_override("font_size", 13)
			grid.add_child(k)
			var what := Label.new()
			what.text = row[1]
			what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			what.custom_minimum_size = Vector2(WHAT_WIDTH, 0)
			what.add_theme_font_size_override("font_size", 13)
			grid.add_child(what)
			lines.append(PackedStringArray([k.text, what.text]))
	var notes_width := 2.0 * (KEYS_WIDTH + 12.0 + WHAT_WIDTH) + COLUMN_GAP
	var mouse := Label.new()
	mouse.text = "The hole list, its par, Open, Play and tag buttons, the fee slider, the speed buttons, the goals and the feed's lines are all reached with F6."
	mouse.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse.custom_minimum_size = Vector2(notes_width, 0)
	mouse.add_theme_font_size_override("font_size", 13)
	box.add_child(mouse)
	clubs_label = Label.new()
	clubs_label.text = club_text(ClubSet.load_default())
	clubs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clubs_label.custom_minimum_size = Vector2(notes_width, 0)
	clubs_label.add_theme_font_size_override("font_size", 13)
	box.add_child(clubs_label)
	shapes_label = Label.new()
	shapes_label.text = shape_text(ShotShapes.load_default(), ClubSet.load_default())
	shapes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shapes_label.custom_minimum_size = Vector2(notes_width, 0)
	shapes_label.add_theme_font_size_override("font_size", 13)
	box.add_child(shapes_label)


## E8-S5: each full club's carry and total on flat fairway from a perfect swing (Club.carry_yd,
## Club.total_yd), longest first: "Clubs, carry / total on flat fairway: driver 235 / 282 yd, ...".
static func club_text(set: ClubSet) -> String:
	var parts := PackedStringArray()
	for c: Club in set.clubs:
		if not c.is_putter():
			parts.append("%s %d / %d" % [c.id, roundi(c.carry_yd), roundi(c.total_yd)])
	return "Clubs, carry / total in yd on flat fairway from a perfect swing: " + ", ".join(parts) \
			+ ". The Cup tool's ruler measures a hole as you place it."


## E20-S1 (D74): the shot shapes in picker order with each one's bend at a driver's carry and
## at the shortest full club's (ShotShapes.bend_of), named for a right-hander: "Shot shapes
## (Q / E), bend at a driver's carry: Hook 35 yd left, Draw 12 yd left, Straight, ...".
static func shape_text(shapes: ShotShapes, set: ClubSet) -> String:
	var driver: Club = null
	var shortest: Club = null
	for c: Club in set.clubs:
		if c.is_putter():
			continue
		if driver == null:
			driver = c
		shortest = c
	var parts := PackedStringArray()
	for s: ShotShape in shapes.shapes:
		if not s.bends():
			parts.append(s.title)
			continue
		parts.append("%s %d yd %s" % [s.title, roundi(ShotShapes.bend_of(driver, s)),
				"left" if s.side < 0 else "right"])
	var keys := "%s / %s" % [key_text(&"shape_prev"), key_text(&"shape_next")]
	var short_bends := PackedStringArray()
	for s: ShotShape in shapes.shapes:
		if s.bends() and s.side > 0:
			short_bends.append("%s %d" % [s.title.to_lower(), roundi(ShotShapes.bend_of(shortest, s))])
	return ("Shot shapes (%s), for a right-hander, bend at a driver's carry: %s. A shaped ball " 			+ "starts to the other side of the aim and curves back across it; shorter clubs bend " 			+ "less (%s yd with the %s), the putter never. Draws run on, fades sit down, and a " 			+ "shape narrows the accuracy zone.") % [keys, ", ".join(parts), ", ".join(short_bends),
			shortest.id]


## Opens or closes the key map.
func toggle() -> void:
	set_open(not panel.visible)


func set_open(on: bool) -> void:
	panel.visible = on
	if on:
		panel.reset_size()
		panel.size = panel.get_combined_minimum_size()
		panel.position = ((get_viewport_rect().size - panel.size) * 0.5).max(Vector2.ZERO)


func is_open() -> bool:
	return panel != null and panel.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed(CLOSE_ACTION):
		set_open(false)
		get_viewport().set_input_as_handled()


## The keys bound to `action` in the InputMap ("F6", "Shift+F6", "Ctrl+Z"; several joined with
## " or "), or "" when it has none.
static func key_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var out := PackedStringArray()
	for e: InputEvent in InputMap.action_get_events(action):
		var k := e as InputEventKey
		if k == null:
			continue
		var t: String = k.as_text_physical_keycode() if k.physical_keycode != KEY_NONE else k.as_text_keycode()
		for name: String in KEY_NAMES:
			t = t.replace(name, KEY_NAMES[name])
		if not out.has(t):
			out.append(t)
	return " or ".join(out)


## Every action the panel names.
static func listed_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for section: Array in SECTIONS:
		for row: Array in section[1]:
			for action: StringName in row[0]:
				out.append(action)
	return out
