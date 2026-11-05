class_name HolePanel
extends PanelContainer
## The Build-mode hole panel (E2-S3): the hole the tee and cup tools build, its yardage and
## status, par 3/4/5, the Open button and every failing rule with its tile and reason. A view
## onto a BuildTool and its builder: buttons go through the tool, and refresh() (on the tool's
## settings_changed and after every builder check, from Main) shows the builder's state.
## Open is enabled only when the hole is closed and all six rules pass (D11, D30).
##
## The hole list (E3-S2) sits above: one row per hole in number order, up to
## BuilderTuning.max_holes. A row's number button picks the hole for the tee and cup tools
## (BuildTool.select_hole) and shows its par, yardage and status; its Open or Close button
## opens or closes it in one click; Play emits play_requested, which Main answers by playing
## that hole; up and down give it the number above or below (BuildTool.renumber_hole, swapping
## with the hole there). New hole picks the next number in build order and the Tee tool.

## Emitted when a row's Play is pressed: Main plays hole `number`.
signal play_requested(number: int)


## One hole's row in the list. Display only; its buttons go through the panel's BuildTool.
class HoleRow:
	extends HBoxContainer
	## The hole this row shows.
	var number: int = 0
	var up_button: Button
	var down_button: Button
	var pick_button: Button
	var open_button: Button
	var play_button: Button

	func _init(pick_width: float) -> void:
		add_theme_constant_override("separation", 2)
		up_button = _button("↑", "Move the hole up: it takes the number above")
		down_button = _button("↓", "Move the hole down: it takes the number below")
		pick_button = _button("", "Build this hole: the Tee and Cup tools place its tee and cup")
		pick_button.toggle_mode = true
		pick_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick_button.custom_minimum_size = Vector2(pick_width, 0)
		open_button = _button("Open", "")
		open_button.custom_minimum_size = Vector2(56, 0)
		play_button = _button("Play", "Play this hole")

	func _button(text: String, tip: String) -> Button:
		var b := Button.new()
		b.text = text
		b.tooltip_text = tip
		b.focus_mode = Control.FOCUS_NONE
		add_child(b)
		return b


## Par buttons in CourseBuilder.PARS order.
var par_buttons: Array[Button] = []
var open_button: Button
var title_label: Label
var status_label: Label
var issues_label: Label
## Picks the next hole in build order (BuildTool.new_hole); disabled when the course is full.
var new_hole_button: Button
## The list's rows, in number order; only the first shown_rows().size() are visible.
var rows: Array[HoleRow] = []

## Width of the issues text before it wraps, screen px.
@export var text_width: float = 340.0
## Width of a list row's number, par, yardage and status button, screen px.
@export var pick_width: float = 196.0

var _tool: BuildTool
var _par_group := ButtonGroup.new()
var _list: VBoxContainer
var _shown: int = 0


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	box.add_child(_list)
	new_hole_button = Button.new()
	new_hole_button.text = "New hole"
	new_hole_button.tooltip_text = "Start the next hole: the Tee tool places its tee"
	new_hole_button.focus_mode = Control.FOCUS_NONE
	new_hole_button.pressed.connect(func() -> void: _tool.new_hole())
	box.add_child(new_hole_button)
	box.add_child(HSeparator.new())
	title_label = Label.new()
	box.add_child(title_label)
	status_label = Label.new()
	box.add_child(status_label)
	var row := HBoxContainer.new()
	box.add_child(row)
	var par_label := Label.new()
	par_label.text = "Par"
	row.add_child(par_label)
	for p: int in CourseBuilder.PARS:
		var b := Button.new()
		b.text = str(p)
		b.toggle_mode = true
		b.button_group = _par_group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(32, 0)
		b.tooltip_text = "Par %d" % p
		b.pressed.connect(func() -> void: _tool.select_par(p))
		row.add_child(b)
		par_buttons.append(b)
	open_button = Button.new()
	open_button.text = "Open"
	open_button.tooltip_text = "Open the hole to guests (every rule must pass)"
	open_button.focus_mode = Control.FOCUS_NONE
	open_button.pressed.connect(func() -> void: _tool.open_hole())
	row.add_child(open_button)
	issues_label = Label.new()
	issues_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	issues_label.custom_minimum_size = Vector2(text_width, 0)
	issues_label.add_theme_color_override("font_color", Color8(240, 160, 150))
	box.add_child(issues_label)


## Follows `tool` from now on.
func bind(tool: BuildTool) -> void:
	_tool = tool
	_tool.settings_changed.connect(refresh)
	refresh()


## Shows the hole as the builder has it now.
func refresh() -> void:
	if _tool == null or title_label == null:
		return
	var b: CourseBuilder = _tool.builder
	var number: int = _tool.hole_number
	var h: HoleData = b.hole(number) if b != null else null
	var c: CourseData = b.course if b != null else null
	var line: String = "Hole %d" % number
	if h != null and c.in_bounds(h.tee.x, h.tee.y) and c.in_bounds(h.cup.x, h.cup.y):
		line += ", %d yd" % CourseValidator.yardage(h.tee, h.cup)
	title_label.text = line
	if h == null:
		status_label.text = "Status: no tee or cup yet"
	elif h.open:
		status_label.text = "Status: open"
	else:
		status_label.text = "Status: closed"
	var shown: int = _tool.shown_par()
	for i: int in par_buttons.size():
		par_buttons[i].set_pressed_no_signal(CourseBuilder.PARS[i] == shown)
	open_button.disabled = b == null or not b.can_open(number)
	var text := PackedStringArray()
	if b != null:
		for issue: CourseValidator.Issue in b.issues_for(number):
			var at: String = "" if not c.in_bounds(issue.tile.x, issue.tile.y) \
					else " at (%d, %d)" % [issue.tile.x, issue.tile.y]
			text.append("rule %d%s: %s" % [issue.rule, at, issue.reason])
	issues_label.text = "\n".join(text)
	issues_label.visible = not text.is_empty()
	_refresh_list(b)
	new_hole_button.disabled = b == null or b.next_hole_number() == 0


## The rows showing a hole now, in number order.
func shown_rows() -> Array[HoleRow]:
	return rows.slice(0, _shown)


## The row showing hole `number`, or null.
func row_for(number: int) -> HoleRow:
	for r: HoleRow in shown_rows():
		if r.number == number:
			return r
	return null


## One line for a hole in the list: number, par, yardage (once tee and cup are on the map) and
## status.
static func row_text(c: CourseData, h: HoleData) -> String:
	var parts := PackedStringArray([str(h.number), "Par %d" % h.par])
	if not c.in_bounds(h.tee.x, h.tee.y):
		parts.append("no tee")
	elif not c.in_bounds(h.cup.x, h.cup.y):
		parts.append("no cup")
	else:
		parts.append("%d yd" % CourseValidator.yardage(h.tee, h.cup))
	parts.append("open" if h.open else "closed")
	return "  ".join(parts)


## Shows one row per hole, reusing rows (a row's own button may be what changed the holes).
func _refresh_list(b: CourseBuilder) -> void:
	var numbers: Array[int] = []
	if b != null:
		numbers = b.hole_numbers()
	while rows.size() < numbers.size():
		rows.append(_make_row())
	_shown = numbers.size()
	for i: int in rows.size():
		var r: HoleRow = rows[i]
		r.visible = i < _shown
		if i >= _shown:
			continue
		var h: HoleData = b.hole(numbers[i])
		r.number = h.number
		r.pick_button.text = row_text(b.course, h)
		r.pick_button.set_pressed_no_signal(h.number == _tool.hole_number)
		r.open_button.text = "Close" if h.open else "Open"
		r.open_button.disabled = not h.open and not b.can_open(h.number)
		r.open_button.tooltip_text = "Close the hole to guests" if h.open \
				else "Open the hole to guests (every rule must pass)"
		r.up_button.disabled = h.number <= 1
		r.down_button.disabled = i == _shown - 1


func _make_row() -> HoleRow:
	var r := HoleRow.new(pick_width)
	r.pick_button.pressed.connect(func() -> void: _tool.select_hole(r.number))
	r.open_button.pressed.connect(func() -> void:
		var h: HoleData = _tool.builder.hole(r.number) if _tool.builder != null else null
		if h != null:
			_tool.set_hole_open(r.number, not h.open))
	r.play_button.pressed.connect(func() -> void: play_requested.emit(r.number))
	r.up_button.pressed.connect(func() -> void: _tool.renumber_hole(r.number, r.number - 1))
	r.down_button.pressed.connect(func() -> void: _tool.renumber_hole(r.number, r.number + 1))
	_list.add_child(r)
	return r
