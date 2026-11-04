class_name HolePanel
extends PanelContainer
## The Build-mode hole panel (E2-S3): the hole the tee and cup tools build, its yardage and
## status, par 3/4/5, the Open button and every failing rule with its tile and reason. A view
## onto a BuildTool and its builder: buttons go through the tool, and refresh() (on the tool's
## settings_changed and after every builder check, from Main) shows the builder's state.
## Open is enabled only when the hole is closed and all six rules pass (D11, D30).

## Par buttons in CourseBuilder.PARS order.
var par_buttons: Array[Button] = []
var open_button: Button
var title_label: Label
var status_label: Label
var issues_label: Label

## Width of the issues text before it wraps, screen px.
@export var text_width: float = 340.0

var _tool: BuildTool
var _par_group := ButtonGroup.new()


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
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
