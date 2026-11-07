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
## its issue text is one line, a summary (issues_summary: the one rule and its reason, or "Fails
## rules 2 and 4"), cut with an ellipsis at text_width and in full on hover (E3-S27), so with
## two failing rules the panel is short enough for the strip under it to win, and a long text
## never widens it. Main.free_view_rects follows the panel's height, so framing can use the map
## under it. Collapsing never moves the pick.
##
## Duplicate numbers (E3-S11): the list has one row per hole (per slot of CourseData.holes,
## CourseBuilder.hole_slots), so two holes sharing a number from a loaded file each get a row,
## marked as a duplicate with validator rule 1's text under it (duplicate_label). Each row's
## pick, Play, up and down act on its own hole through its slot; a duplicate's up and down move
## it to the nearest free number that way (CourseBuilder.free_number), which parts the pair.
## A duplicate is named as the map names it (CourseData.hole_label, E3-S27): "4a" and "4b", in
## its row, the details' title, its tee marker and its issue boxes.
##
## Why guests complained (E3-S18): under the status, the picked hole's latest complaint among
## the feed's counted reactions, or its latest praise when the window holds no complaint about it
## (latest_reaction: the window the map tag counts, less what an edit cleared, E3-S17; a neutral
## is quiet, D39), led by the check that failed ("Complaint: blind from the tee, could not see
## the flag."). Expanded, the whole line; collapsed, its lead sentence alone, the rest and every
## failed check (in the player's words, CHECK_LABELS) on hover, so it stays inside max_height
## beside the one-line issue summary.

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
## The picked hole's failing rules: one per line expanded; collapsed, one line (issues_summary)
## cut at text_width with an ellipsis, every rule on hover (E3-S27). Its width is text_width
## either way, so no text widens the panel.
var issues_label: Label
## Picks the next hole in build order (BuildTool.new_hole); disabled when the course is full.
var new_hole_button: Button
## The list's rows, in number order; the first shown_rows().size() hold a hole, and of those
## listed_rows() are visible.
var rows: Array[HoleRow] = []
## Collapses or expands the list in one click (set_collapsed).
var collapse_button: Button
## True while the list shows only the picked hole's row.
var collapsed: bool = false
## The picked hole's latest praise or complaint, led by its failed check (E3-S18); hidden when
## guests have given it none since its last edit.
var reaction_label: Label
## The guests' reactions (bind_feed); null shows none.
var feed: ReactionFeed
## Null loads scenes/hole_panel_tuning.tres.
@export var tuning: HolePanelTuning

## Width of the issues text before it wraps, screen px.
@export var text_width: float = 340.0
## Width of a list row's number, par, yardage and status button, screen px.
@export var pick_width: float = 196.0
## The reaction line's colours, as the feed draws praise and complaints (FeedPanel).
@export var praise_color: Color = Color8(240, 200, 58)
@export var complaint_color: Color = Color8(240, 160, 150)

var _tool: BuildTool
var _par_group := ButtonGroup.new()
var _list: VBoxContainer
var _shown: int = 0


func _ready() -> void:
	if tuning == null:
		tuning = HolePanelTuning.load_default()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	# One width whatever the hole fails or whether it fails anything (E3-S27).
	box.custom_minimum_size.x = text_width
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
	reaction_label = Label.new()
	reaction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reaction_label.custom_minimum_size = Vector2(text_width, 0)
	reaction_label.mouse_filter = Control.MOUSE_FILTER_PASS
	reaction_label.visible = false
	box.add_child(reaction_label)
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
	issues_label.mouse_filter = Control.MOUSE_FILTER_PASS
	issues_label.add_theme_color_override("font_color", Color8(240, 160, 150))
	box.add_child(issues_label)


## Follows `tool` from now on.
func bind(tool: BuildTool) -> void:
	_tool = tool
	_tool.settings_changed.connect(refresh)
	refresh()


## Shows the picked hole's latest guest verdict from `p_feed` from now on (E3-S18).
func bind_feed(p_feed: ReactionFeed) -> void:
	feed = p_feed
	feed.added.connect(func(_e: ReactionFeed.Entry) -> void: refresh())
	feed.cleared.connect(refresh)
	feed.slot_cleared.connect(func(_slot: int) -> void: refresh())
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
	var line: String = "Hole %s" % (c.hole_label(slot) if c != null and slot >= 0 else str(number))
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
	var own: Array[CourseValidator.Issue] = []
	if b != null:
		own = b.issues_at(slot) if slot >= 0 else b.issues_for(number)
		for issue: CourseValidator.Issue in own:
			var at: String = "" if not c.in_bounds(issue.tile.x, issue.tile.y) \
					else " at (%d, %d)" % [issue.tile.x, issue.tile.y]
			text.append("rule %d%s: %s" % [issue.rule, at, issue.reason])
	var full: String = "\n".join(text)
	# Collapsed, one line that never wraps and never widens the panel (E3-S27).
	issues_label.autowrap_mode = TextServer.AUTOWRAP_OFF if collapsed else TextServer.AUTOWRAP_WORD_SMART
	issues_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if collapsed \
			else TextServer.OVERRUN_NO_TRIMMING
	issues_label.text = issues_summary(own) if collapsed else full
	issues_label.tooltip_text = full if collapsed else ""
	issues_label.visible = not text.is_empty()
	_refresh_reaction(c, slot)
	_refresh_list(b)
	new_hole_button.disabled = b == null or b.next_hole_number() == 0
	# Collapsed, the picked hole's row is its one-line summary: the title and status would
	# say it again.
	var summarised: bool = collapsed and not listed_rows().is_empty()
	title_label.visible = not summarised
	status_label.visible = not summarised


## The collapsed panel's one line for `own` (a hole's failing rules, E3-S27): the rule and its
## reason when it fails one, else the rules it fails ("Fails rules 2, 4 and 6: hover for why").
## The label cuts it at text_width; the whole list is its tooltip.
static func issues_summary(own: Array[CourseValidator.Issue]) -> String:
	if own.is_empty():
		return ""
	if own.size() == 1:
		return "rule %d: %s" % [own[0].rule, own[0].reason]
	var numbers := PackedStringArray()
	for issue: CourseValidator.Issue in own:
		if not numbers.has(str(issue.rule)):
			numbers.append(str(issue.rule))
	var said: String = numbers[0]
	if numbers.size() > 1:
		said = ", ".join(numbers.slice(0, numbers.size() - 1)) + " and " + numbers[numbers.size() - 1]
	return "Fails %s %s: hover for why" % ["rule" if numbers.size() == 1 else "rules", said]


## Shows the latest verdict on slot `slot` of `c` (E3-S18), or hides the line.
func _refresh_reaction(c: CourseData, slot: int) -> void:
	var r: GuestReaction = latest_reaction(feed, c, slot)
	reaction_label.visible = r != null
	if r == null:
		reaction_label.text = ""
		reaction_label.tooltip_text = ""
		return
	reaction_label.text = reaction_text(r, collapsed)
	reaction_label.tooltip_text = reaction_tip(r)
	reaction_label.add_theme_color_override("font_color",
			praise_color if r.is_praise() else complaint_color)


## The newest complaint in `p_feed`'s window about the hole in slot `slot` of `c`, as the map
## tag counts it (ReactionFeed.resolve_slot; a reaction cleared by an edit counts for no hole),
## else its newest praise, else null. A complaint wins over a newer praise: while the tag shows
## a "!n" the panel says what to fix (E3-S18 review).
static func latest_reaction(p_feed: ReactionFeed, c: CourseData, slot: int) -> GuestReaction:
	if p_feed == null or c == null or slot < 0:
		return null
	var praise: GuestReaction = null
	for i: int in range(p_feed.recent.size() - 1, -1, -1):
		var r: GuestReaction = p_feed.recent[i]
		if r.kind == GuestReaction.Kind.NEUTRAL:
			continue
		if ReactionFeed.resolve_slot(c, p_feed.recent_slots[i], r.hole_number) != slot:
			continue
		if r.is_complaint():
			return r
		if praise == null:
			praise = r
	return praise


## `r`'s line without its "Hole N: " (the panel names the hole).
static func reaction_body(r: GuestReaction) -> String:
	var head := r.text.find(": ")
	return r.text.substr(head + 2) if r.text.begins_with("Hole ") and head >= 0 else r.text


## `r`'s lead sentence: its body up to the first full stop (a praise is one sentence).
static func reaction_lead(r: GuestReaction) -> String:
	var body := reaction_body(r)
	var stop := body.find(". ")
	return body if stop < 0 else body.substr(0, stop + 1)


## The panel's line for `r`: "Praise: ..." or "Complaint: ...", the whole body, or with
## `lead_only` its lead sentence. A complaint's body leads with the check that failed, in the
## guest's words, so no check name is put in front of it (E3-S18 review).
static func reaction_text(r: GuestReaction, lead_only: bool) -> String:
	var said := reaction_lead(r) if lead_only else reaction_body(r)
	return ("Praise: " if r.is_praise() else "Complaint: ") + said


## The four checks as the player reads them, in GuestReaction.Check order.
const CHECK_LABELS: PackedStringArray = ["sight line", "risk and reward", "pace", "difficulty"]


## The hover text for `r`: its whole line and every check it failed, in CHECK_LABELS' words.
static func reaction_tip(r: GuestReaction) -> String:
	var tip := r.text
	if r.is_praise():
		return tip
	var fails := PackedStringArray()
	for c: int in GuestReaction.Check.size():
		if not r.passed[c]:
			fails.append(CHECK_LABELS[c])
	if not fails.is_empty():
		tip += "\nFailed: %s." % GuestReaction._and_list(fails)
	return tip


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
## run (it names the other hole as the map labels it, E3-S41).
static func duplicate_text(b: CourseBuilder, slot: int) -> String:
	for issue: CourseValidator.Issue in b.issues_at(slot):
		if issue.rule == 1:
			return "Duplicate number. rule 1: %s" % issue.reason
	return "Duplicate number. rule 1: shares number %d with another hole" % b.hole_at(slot).number


## One line for a hole in the list: number, par, yardage (once tee and cup are on the map; the
## line of play, D47: `yards` as the builder's latest run measured it, or measured here by a
## fresh CourseValidator when negative) and status. Given its `slot`, a hole sharing its number
## is named "4a" or "4b" (CourseData.hole_label, E3-S27).
static func row_text(c: CourseData, h: HoleData, yards: int = -1, slot: int = -1) -> String:
	var label: String = c.hole_label(slot) if slot >= 0 else str(h.number)
	var parts := PackedStringArray([label, "Par %d" % h.par])
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
		r.pick_button.text = row_text(b.course, h, b.yardage_at(slots[i]), slots[i])
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
