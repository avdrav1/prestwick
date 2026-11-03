class_name LandPanel
extends PanelContainer
## The Build-mode land panel (E6-S5, D26 to D29, docs/design.md Land): the land budget, always;
## the hovered parcel's price and whether it can be bought; a tool's hint before the click
## when it would do nothing on the hovered tile ("Paint: not your land"); the builder's
## refusal after a click that did nothing; and the confirm for a purchase. A view onto a
## BuildTool and its builder: it never writes the course, and a confirmed purchase goes
## through BuildTool.buy, which calls CourseBuilder.buy_parcel.
##
## Main binds the tool once (bind) and hands every fresh builder to watch (show_course).

const NONE: Vector2i = TilePicker.NONE
## Hint names for each BuildTool.Tool.
const TOOL_NAMES: Dictionary = {
	BuildTool.Tool.PAINT: "Paint", BuildTool.Tool.RAISE: "Raise", BuildTool.Tool.LOWER: "Lower",
	BuildTool.Tool.TEE: "Tee", BuildTool.Tool.CUP: "Cup", BuildTool.Tool.BUY: "Buy",
}

var budget_label: Label
## The hovered parcel: "Parcel 4, 2: $1,150, click to buy".
var parcel_label: Label
## The current tool's refusal on the hovered tile, before the click.
var hint_label: Label
## The builder's refusal after a click, shown for BuilderTuning.refusal_show_s.
var message_label: Label
var confirm_box: VBoxContainer
var confirm_label: Label
var confirm_button: Button
var cancel_button: Button
## The parcel waiting on the confirm, or NONE.
var pending_parcel: Vector2i = NONE

## Color of a hint or a refusal.
@export var refuse_font_color: Color = Color8(240, 160, 150)

var _tool: BuildTool
var _message_left: float = 0.0
var _refusal_show_s: float = 3.0


func _ready() -> void:
	_refusal_show_s = BuilderTuning.load_default().refusal_show_s
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	budget_label = Label.new()
	box.add_child(budget_label)
	parcel_label = Label.new()
	box.add_child(parcel_label)
	hint_label = _warning_label(box)
	message_label = _warning_label(box)
	confirm_box = VBoxContainer.new()
	confirm_box.visible = false
	box.add_child(confirm_box)
	confirm_label = Label.new()
	confirm_box.add_child(confirm_label)
	var row := HBoxContainer.new()
	confirm_box.add_child(row)
	confirm_button = Button.new()
	confirm_button.text = "Buy"
	confirm_button.focus_mode = Control.FOCUS_NONE
	confirm_button.pressed.connect(confirm_buy)
	row.add_child(confirm_button)
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.pressed.connect(cancel_buy)
	row.add_child(cancel_button)
	visibility_changed.connect(func() -> void:
		if not visible:
			cancel_buy())
	refresh()


## Follows `tool` from now on.
func bind(tool: BuildTool) -> void:
	_tool = tool
	_tool.settings_changed.connect(_on_settings_changed)
	_tool.hover_changed.connect(refresh)
	_tool.buy_requested.connect(ask_buy)
	refresh()


## Follows `builder` (the tool's new one, after Main.show_course): its refusals and land.
func watch(builder: CourseBuilder) -> void:
	cancel_buy()
	_message_left = 0.0
	builder.refused.connect(show_refusal)
	builder.land_changed.connect(func(_p: Vector2i) -> void: refresh())
	refresh()


## Shows the builder's refusal of a click, `reason`, for BuilderTuning.refusal_show_s.
func show_refusal(reason: String) -> void:
	message_label.text = "Can't: %s" % reason
	_message_left = _refusal_show_s
	refresh()


## The Buy land tool was clicked on `parcel`: ask to confirm, or say why it cannot be bought.
func ask_buy(parcel: Vector2i) -> void:
	var b: CourseBuilder = _builder()
	if b == null:
		return
	var why: String = b.buy_refusal(parcel)
	if not why.is_empty():
		cancel_buy()
		show_refusal(why)
		return
	pending_parcel = parcel
	_tool.pinned_parcel = parcel
	var c: CourseData = b.course
	if c.has_unlimited_budget():
		confirm_label.text = "Buy parcel %d, %d?" % [parcel.x, parcel.y]
	else:
		var cost: int = b.parcel_price(parcel)
		confirm_label.text = "Buy parcel %d, %d for %s?\n%s left after." % [parcel.x, parcel.y,
				LandPrices.money(cost), LandPrices.money(c.land_budget - cost)]
	confirm_box.visible = true
	refresh()


## Buys the pending parcel (the confirm's Buy). False when none is pending or it was refused.
func confirm_buy() -> bool:
	if pending_parcel == NONE or _tool == null:
		return false
	var parcel: Vector2i = pending_parcel
	cancel_buy()
	var ok: bool = _tool.buy(parcel)
	if not ok:
		show_refusal(_builder().buy_refusal(parcel))
	refresh()
	return ok


func cancel_buy() -> void:
	var was: Vector2i = pending_parcel
	pending_parcel = NONE
	if _tool != null:
		_tool.pinned_parcel = NONE
	if confirm_box != null:
		confirm_box.visible = false
	if was != NONE:
		refresh()


## Shows the budget, the hovered parcel and the hints as the builder has them now.
func refresh() -> void:
	if budget_label == null:
		return
	var b: CourseBuilder = _builder()
	if b == null:
		budget_label.text = ""
		parcel_label.visible = false
		hint_label.visible = false
		message_label.visible = false
		return
	var c: CourseData = b.course
	budget_label.text = "Land budget: %s" % ("unlimited" if c.has_unlimited_budget()
			else LandPrices.money(c.land_budget))
	parcel_label.text = _parcel_line(b)
	parcel_label.visible = not parcel_label.text.is_empty()
	var hint: String = "" if _tool.tool == BuildTool.Tool.BUY else _tool.hover_hint()
	hint_label.text = "" if hint.is_empty() else "%s: %s" % [TOOL_NAMES[_tool.tool], hint]
	hint_label.visible = not hint.is_empty()
	message_label.visible = _message_left > 0.0


func _process(delta: float) -> void:
	if _message_left <= 0.0:
		return
	_message_left -= delta
	if _message_left <= 0.0:
		message_label.visible = false


## The hovered parcel's line: its price and whether it can be bought, for an unowned parcel
## (and with the Buy land tool, "yours" on an owned one); "" when nothing is hovered. While
## a purchase waits on the confirm it describes that parcel instead, which the map outlines
## (BuildTool.pinned_parcel), so the line and the outline never name another parcel.
func _parcel_line(b: CourseBuilder) -> String:
	var parcel: Vector2i = _tool.hover_parcel() if pending_parcel == NONE else pending_parcel
	if parcel == NONE:
		return ""
	var c: CourseData = b.course
	var buying: bool = _tool.tool == BuildTool.Tool.BUY
	if c.is_parcel_owned(parcel):
		return "Parcel %d, %d: yours" % [parcel.x, parcel.y] if buying else ""
	var line: String = "Parcel %d, %d: %s" % [parcel.x, parcel.y, LandPrices.money(b.parcel_price(parcel))]
	var why: String = b.buy_refusal(parcel)
	if not why.is_empty():
		return "%s, can't buy: %s" % [line, why]
	return "%s, %s" % [line, "click to buy" if buying else "for sale (Buy land)"]


func _on_settings_changed() -> void:
	if _tool.tool != BuildTool.Tool.BUY:
		cancel_buy()
	refresh()


func _builder() -> CourseBuilder:
	return _tool.builder if _tool != null else null


func _warning_label(parent: Control) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", refuse_font_color)
	l.visible = false
	parent.add_child(l)
	return l
