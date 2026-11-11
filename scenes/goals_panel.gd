class_name GoalsPanel
extends PanelContainer
## E10-S1: the goal checklist (GoalList) in Build's left column, under the fee. Expanded, it lists
## every goal with a tick box, the next one lit with its one-line "how" under it (each goal's how
## is its tooltip too); "Hide" folds it to one line, "Next: <goal>", with "Goals" to open it again
## (the menu's Goals does the same). With too little room above the bottom bar (the land list
## open) it shows the one line without folding the player's choice. F6 reaches its button.

## sun_yellow (art/palette.gpl): the next goal and the ticks.
const NEXT_COLOR := Color8(240, 200, 58)
## A done goal's text, dimmed.
const DONE_COLOR := Color(1, 1, 1, 0.55)
## The panel's width, px: the left column's widest control (the fee panel, main.tscn).
const WIDTH: float = 294.0
const TICK_SIZE: float = 13.0

var list: GoalList
var tuning: GoalsTuning
## The expanded list and its header.
var expanded_box: VBoxContainer
var title_label: Label
var hide_button: Button
var rows_box: VBoxContainer
## The one line: "Next: ..." and Goals.
var line_box: HBoxContainer
var next_label: Label
var show_button: Button

## The height the panel may take, px (Main._place_speed_panel); INF until told.
var _room: float = INF
var _squeezed: bool = false


## A goal's tick box: an outline, with a check when done.
class Tick:
	extends Control
	var done: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(TICK_SIZE, TICK_SIZE)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(0.5, 0.5), size - Vector2.ONE)
		draw_rect(r, Color(1, 1, 1, 0.7), false, 1.0)
		if done:
			var s: Vector2 = size
			draw_polyline(PackedVector2Array([Vector2(s.x * 0.2, s.y * 0.5), Vector2(s.x * 0.42, s.y * 0.75),
					Vector2(s.x * 0.85, s.y * 0.22)]), NEXT_COLOR, 2.0, true)


func _ready() -> void:
	if tuning == null:
		tuning = GoalsTuning.load_default()
	custom_minimum_size.x = WIDTH
	# Near opaque, as the key map (HelpOverlay): the clubhouse and trees under it would blur its
	# small text.
	var style: StyleBox = get_theme_stylebox(&"panel")
	if style is StyleBoxFlat:
		var opaque := style.duplicate() as StyleBoxFlat
		opaque.bg_color = Color(0.1, 0.1, 0.12, 0.9)
		add_theme_stylebox_override(&"panel", opaque)
	var box := VBoxContainer.new()
	add_child(box)
	expanded_box = VBoxContainer.new()
	expanded_box.name = "Expanded"
	expanded_box.add_theme_constant_override("separation", 2)
	box.add_child(expanded_box)
	var head := HBoxContainer.new()
	expanded_box.add_child(head)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	hide_button = _button(head, "Hide", "Fold the goals to one line (the menu's Goals opens them again)")
	hide_button.pressed.connect(func() -> void: set_collapsed(true))
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 1)
	expanded_box.add_child(rows_box)
	line_box = HBoxContainer.new()
	line_box.name = "Line"
	box.add_child(line_box)
	next_label = Label.new()
	next_label.name = "Next"
	next_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	next_label.clip_text = true
	next_label.mouse_filter = Control.MOUSE_FILTER_STOP
	line_box.add_child(next_label)
	show_button = _button(line_box, "Goals", "Show every goal and how to do it")
	show_button.pressed.connect(func() -> void: set_collapsed(false))
	refresh()


func _button(parent: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", tuning.font_size)
	parent.add_child(b)
	return b


func bind(p_list: GoalList) -> void:
	if list != null and list.changed.is_connected(refresh):
		list.changed.disconnect(refresh)
	list = p_list
	if list != null:
		list.changed.connect(refresh)
	refresh()


## Folds the panel to its one line (true) or opens it (false); the game save keeps it.
func set_collapsed(on: bool) -> void:
	if list == null or list.collapsed == on:
		return
	list.collapsed = on
	list.changed.emit()


## The height the panel may take: with less than the expanded list needs it shows its one line.
func set_room(height: float) -> void:
	if is_equal_approx(height, _room):
		return
	_room = height
	refresh()


## True while it shows the one line ("Next: ..."), folded or squeezed.
func shows_line() -> bool:
	return line_box != null and line_box.visible


## The one line's text: "Next: Place a tee", or "Goals: all done".
func line_text() -> String:
	if list == null:
		return ""
	var g: GoalList.Goal = list.next_goal()
	return "Goals: all done" if g == null else "Next: %s" % g.title


## The goal rows' texts, in order (for tests and the playtest).
func row_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	if rows_box == null:
		return out
	for row: Node in rows_box.get_children():
		var l := row.get_node_or_null(^"Title") as Label
		if l != null:
			out.append(l.text)
	return out


## Rebuilds the rows and picks the expanded list or the one line.
func refresh() -> void:
	if rows_box == null or list == null:
		return
	title_label.text = "Goals  %d of %d" % [list.done_count(), list.goals().size()]
	title_label.add_theme_font_size_override("font_size", tuning.font_size)
	for c: Node in rows_box.get_children():
		rows_box.remove_child(c)
		c.queue_free()
	var next: GoalList.Goal = list.next_goal()
	for g: GoalList.Goal in list.goals():
		var row := HBoxContainer.new()
		row.name = g.id
		row.tooltip_text = g.how
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var tick := Tick.new()
		tick.done = list.is_done(g.id)
		row.add_child(tick)
		var l := Label.new()
		l.name = "Title"
		l.text = g.title
		l.add_theme_font_size_override("font_size", tuning.font_size)
		if tick.done:
			l.add_theme_color_override("font_color", DONE_COLOR)
		elif g == next:
			l.add_theme_color_override("font_color", NEXT_COLOR)
		row.add_child(l)
		rows_box.add_child(row)
		if g == next:
			var how := Label.new()
			how.name = "How"
			how.text = g.how
			how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			how.custom_minimum_size.x = WIDTH - 2.0 * TICK_SIZE
			how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			how.add_theme_font_size_override("font_size", tuning.font_size - 1)
			var pad := MarginContainer.new()
			pad.name = "HowRow"
			pad.add_theme_constant_override("margin_left", int(TICK_SIZE) + 4)
			pad.add_child(how)
			rows_box.add_child(pad)
	next_label.text = line_text()
	next_label.tooltip_text = next.how if next != null else "Every goal is done."
	next_label.add_theme_font_size_override("font_size", tuning.font_size)
	if next != null:
		next_label.add_theme_color_override("font_color", NEXT_COLOR)
	else:
		next_label.remove_theme_color_override("font_color")
	# Room: the expanded list's height with the panel's own margins.
	var margins: float = get_theme_stylebox(&"panel").get_minimum_size().y if has_theme_stylebox(&"panel") else 0.0
	_squeezed = not list.collapsed and expanded_box.get_combined_minimum_size().y + margins > _room
	var line: bool = list.collapsed or _squeezed
	expanded_box.visible = not line
	line_box.visible = line
	# Squeezed, Goals would open nothing: the land list holds the room.
	show_button.visible = list.collapsed
	reset_size()
