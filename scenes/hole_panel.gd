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
##
## The list collapses in one click (E3-S10, collapse_button): collapsed, it shows only the
## picked hole's row (its status and buttons with it), which stands in for the title and status
## lines. Collapsed, the panel stays under HolePanelTuning.max_height whatever the hole fails:
## its issue text is cut to the room left and scrolls (issues_scroll). Main.free_view_rects
## follows the panel's height, so framing can use the map under it. Collapsing never moves the
## pick.
##
## Duplicate numbers (E3-S11): the list has one row per hole (per slot of CourseData.holes,
## CourseBuilder.hole_slots), so two holes sharing a number from a loaded file each get a row,
## marked as a duplicate with validator rule 1's text under it (duplicate_label). Each row's
## pick, Play, up and down act on its own hole through its slot; a duplicate's up and down move
## it to the nearest free number that way (CourseBuilder.free_number), which parts the pair.

## Emitted when a row's Play is pressed: Main plays hole `number`, slot `slot`.
signal play_requested(number: int, slot: int)


## One hole's row in the list. Display only; its buttons go through the panel's BuildTool.
class HoleRow:
	extends HBoxContainer
	## The hole this row shows: its number and its slot in CourseData.holes.
	var number: int = 0
	var slot: int = -1
	## True when another hole shares this row's number (rule 1 fails both).
	var duplicate: bool = false
	## Under the row, shown for a duplicate: "Duplicate number. rule 1: <reason>". Added to the
	## list by the panel.
	var duplicate_label: Label
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
		duplicate_label = Label.new()
		duplicate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		duplicate_label.add_theme_color_override("font_color", Color8(240, 160, 150))
		duplicate_label.visible = false

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
## Holds issues_label: as tall as its text, except with the list collapsed, when it is cut to
## what keeps the panel under HolePanelTuning.max_height and scrolls the rest (E3-S10).
var issues_scroll: ScrollContainer
## Picks the next hole in build order (BuildTool.new_hole); disabled when the course is full.
var new_hole_button: Button
## The list's rows, in number order; the first shown_rows().size() hold a hole, and of those
## listed_rows() are visible.
var rows: Array[HoleRow] = []
## Collapses or expands the list in one click (set_collapsed).
var collapse_button: Button
## True while the list shows only the picked hole's row.
var collapsed: bool = false
## Null loads scenes/hole_panel_tuning.tres.
@export var tuning: HolePanelTuning

## Width of the issues text before it wraps, screen px.
@export var text_width: float = 340.0
## Width of a list row's number, par, yardage and status button, screen px.
@export var pick_width: float = 196.0

var _tool: BuildTool
var _par_group := ButtonGroup.new()
var _list: VBoxContainer
var _shown: int = 0


func _ready() -> void:
	if tuning == null:
		tuning = HolePanelTuning.load_default()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	box.add_child(_list)
	var list_row := HBoxContainer.new()
	box.add_child(list_row)
	new_hole_button = Button.new()
	new_hole_button.text = "New hole"
	new_hole_button.tooltip_text = "Start the next hole: the Tee tool places its tee"
	new_hole_button.focus_mode = Control.FOCUS_NONE
	new_hole_button.pressed.connect(func() -> void: _tool.new_hole())
	list_row.add_child(new_hole_button)
	collapse_button = Button.new()
	collapse_button.focus_mode = Control.FOCUS_NONE
	collapse_button.pressed.connect(func() -> void: set_collapsed(not collapsed))
	list_row.add_child(collapse_button)
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
	issues_scroll = ScrollContainer.new()
	issues_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(issues_scroll)
	issues_label = Label.new()
	issues_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	issues_label.custom_minimum_size = Vector2(text_width, 0)
	issues_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	issues_label.add_theme_color_override("font_color", Color8(240, 160, 150))
	issues_scroll.add_child(issues_label)


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
	var slot: int = _tool.picked_slot()
	var h: HoleData = _tool.picked_hole()
	var c: CourseData = b.course if b != null else null
	var line: String = "Hole %d" % number
	if h != null and c.in_bounds(h.tee.x, h.tee.y) and c.in_bounds(h.cup.x, h.cup.y):
		line += ", %d yd" % b.yardage_at(slot)
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
		var own: Array[CourseValidator.Issue] = b.issues_at(slot) if slot >= 0 else b.issues_for(number)
		for issue: CourseValidator.Issue in own:
			var at: String = "" if not c.in_bounds(issue.tile.x, issue.tile.y) \
					else " at (%d, %d)" % [issue.tile.x, issue.tile.y]
			text.append("rule %d%s: %s" % [issue.rule, at, issue.reason])
	issues_label.text = "\n".join(text)
	issues_scroll.visible = not text.is_empty()
	_refresh_list(b)
	new_hole_button.disabled = b == null or b.next_hole_number() == 0
	# Collapsed, the picked hole's row is its one-line summary: the title and status would
	# say it again.
	var summarised: bool = collapsed and not listed_rows().is_empty()
	title_label.visible = not summarised
	status_label.visible = not summarised
	_fit_issues()


## Sizes issues_scroll: its text's full height, or with the list collapsed no more than the
## room max_height leaves beside the rest of the panel, the rest scrolling. However many rules
## the hole fails, and however their text wraps, a collapsed panel stays under max_height.
func _fit_issues() -> void:
	issues_scroll.custom_minimum_size = Vector2.ZERO
	var full: float = issues_label.get_combined_minimum_size().y
	var room: float = full
	if collapsed and issues_scroll.visible:
		room = maxf(tuning.max_height - get_combined_minimum_size().y, 0.0)
	issues_scroll.custom_minimum_size = Vector2(0, minf(full, room))
	if room >= full:
		issues_scroll.scroll_vertical = 0


## The rows showing a hole now, in number order, whether or not the list is collapsed.
func shown_rows() -> Array[HoleRow]:
	return rows.slice(0, _shown)


## The rows visible now: every shown row, or with the list collapsed the picked hole's alone
## (none when the picked hole has no tee or cup yet).
func listed_rows() -> Array[HoleRow]:
	return shown_rows().filter(func(r: HoleRow) -> bool: return r.visible)


## Collapses the list to the picked hole's row, or expands it to every hole (E3-S10). The pick
## stays. The panel shrinks at once, so Main.free_view_rects sees its new height.
func set_collapsed(value: bool) -> void:
	collapsed = value
	refresh()


## The row showing hole `number` (the first, when holes share it), or null.
func row_for(number: int) -> HoleRow:
	for r: HoleRow in shown_rows():
		if r.number == number:
			return r
	return null


## Every row showing hole `number`, in course order: two or more when holes share it (E3-S11).
func rows_for(number: int) -> Array[HoleRow]:
	return shown_rows().filter(func(r: HoleRow) -> bool: return r.number == number)


## The text under a duplicate's row: rule 1's reason for slot `slot`, from the builder's latest
## run (it names the other hole's tee).
static func duplicate_text(b: CourseBuilder, slot: int) -> String:
	for issue: CourseValidator.Issue in b.issues_at(slot):
		if issue.rule == 1:
			return "Duplicate number. rule 1: %s" % issue.reason
	return "Duplicate number. rule 1: hole %d has a second tee and cup" % b.hole_at(slot).number


## One line for a hole in the list: number, par, yardage (once tee and cup are on the map; the
## line of play, D47: `yards` as the builder's latest run measured it, or measured here by a
## fresh CourseValidator when negative) and status.
static func row_text(c: CourseData, h: HoleData, yards: int = -1) -> String:
	var parts := PackedStringArray([str(h.number), "Par %d" % h.par])
	if not c.in_bounds(h.tee.x, h.tee.y):
		parts.append("no tee")
	elif not c.in_bounds(h.cup.x, h.cup.y):
		parts.append("no cup")
	else:
		parts.append("%d yd" % (yards if yards >= 0 else CourseValidator.new().hole_yardage(c, h)))
	parts.append("open" if h.open else "closed")
	return "  ".join(parts)


## Shows one row per hole (per slot, so holes sharing a number each have one), reusing rows (a
## row's own button may be what changed the holes).
func _refresh_list(b: CourseBuilder) -> void:
	var slots: Array[int] = []
	if b != null:
		slots = b.hole_slots()
	while rows.size() < slots.size():
		rows.append(_make_row())
	_shown = slots.size()
	var picked: int = _tool.picked_slot()
	for i: int in rows.size():
		var r: HoleRow = rows[i]
		var h: HoleData = b.hole_at(slots[i]) if i < _shown else null
		r.visible = h != null and (not collapsed or slots[i] == picked)
		r.duplicate = h != null and b.is_duplicate(slots[i])
		r.duplicate_label.visible = r.visible and r.duplicate
		r.duplicate_label.text = duplicate_text(b, slots[i]) if r.duplicate else ""
		if h == null:
			continue
		r.number = h.number
		r.slot = slots[i]
		r.pick_button.text = row_text(b.course, h, b.yardage_at(slots[i]))
		r.pick_button.tooltip_text = r.duplicate_label.text if r.duplicate \
				else "Build this hole: the Tee and Cup tools place its tee and cup"
		r.pick_button.set_pressed_no_signal(slots[i] == picked)
		r.open_button.text = "Close" if h.open else "Open"
		r.open_button.disabled = not h.open and not b.can_open(h.number)
		r.open_button.tooltip_text = "Close the hole to guests" if h.open \
				else "Open the hole to guests (every rule must pass)"
		if r.duplicate:
			r.up_button.disabled = b.free_number(h.number, -1) == 0
			r.down_button.disabled = b.free_number(h.number, 1) == 0
		else:
			r.up_button.disabled = h.number <= 1
			r.down_button.disabled = i == _shown - 1
	collapse_button.text = ("Show all %d holes" if collapsed else "Hide the list (%d holes)") % _shown
	collapse_button.tooltip_text = "Show every hole in the list" if collapsed \
			else "Show only the picked hole, to free the map"
	collapse_button.visible = _shown > 0 or collapsed


func _make_row() -> HoleRow:
	var r := HoleRow.new(pick_width)
	r.pick_button.pressed.connect(func() -> void: _tool.select_hole(r.number, r.slot))
	r.open_button.pressed.connect(func() -> void:
		var h: HoleData = _tool.builder.hole_at(r.slot) if _tool.builder != null else null
		if h != null:
			_tool.set_hole_open(r.number, not h.open))
	r.play_button.pressed.connect(func() -> void: play_requested.emit(r.number, r.slot))
	r.up_button.pressed.connect(func() -> void: _renumber(r, -1))
	r.down_button.pressed.connect(func() -> void: _renumber(r, 1))
	_list.add_child(r)
	r.duplicate_label.custom_minimum_size = Vector2(text_width, 0)
	_list.add_child(r.duplicate_label)
	return r


## Row `r`'s up (dir -1) or down (+1): the number above or below, swapping with the hole there;
## for a duplicate, the nearest free number that way, so it parts from its twin (E3-S11).
func _renumber(r: HoleRow, dir: int) -> void:
	var b: CourseBuilder = _tool.builder
	if b == null:
		return
	var to: int = b.free_number(r.number, dir) if r.duplicate else r.number + dir
	if to != 0:
		_tool.renumber_hole(r.number, to, r.slot)
