class_name ConfirmDialog
extends Control
## E8-S4: the question a save over the saved game, or a load over the game in play, asks first
## ("Save over your saved game from Day 4?", "Load Day 4 and lose today's progress?"), over a
## dimmed course. It takes the keyboard's focus on its yes button: Enter (or Space) answers yes,
## Esc no, the arrows or Tab move between the two, and no other key reaches the game while it is
## open. It is the first thing Esc closes (before HudFocus's hand-back, the key map, the notice,
## the land buy and the menu), and while it is open HudFocus takes no key (Main lists it as a
## blocker). The dialog only asks: whoever opened it does the action (`ask`'s callables).

const CANCEL_ACTION: StringName = &"ui_cancel"
## Keys the focused button takes (press, move between the two); every other key is held back.
const PASS_ACTIONS: Array[StringName] = [&"ui_accept", &"ui_left", &"ui_right", &"ui_up",
		&"ui_down", &"ui_focus_next", &"ui_focus_prev"]
## The question's width, px.
const TEXT_WIDTH: float = 420.0
const BACKDROP := Color(0.0, 0.0, 0.0, 0.55)
## The focused button's outline, as the main menu's.
const FOCUS_COLOR := MainMenu.FOCUS_COLOR
const FOCUS_WIDTH: int = MainMenu.FOCUS_WIDTH

var label: Label
var yes_button: Button
var no_button: Button

var _on_yes: Callable
var _on_no: Callable


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = FOCUS_COLOR
	focus.set_border_width_all(FOCUS_WIDTH)
	focus.set_corner_radius_all(3)
	focus.set_expand_margin_all(2)
	var dim := ColorRect.new()
	dim.color = BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	# Opaque, as the land buy's confirm (E6-S17): nothing under the question shows through.
	var style := panel.get_theme_stylebox(&"panel")
	if style is StyleBoxFlat:
		var opaque := style.duplicate() as StyleBoxFlat
		opaque.bg_color.a = 1.0
		panel.add_theme_stylebox_override(&"panel", opaque)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	label = Label.new()
	label.name = "Question"
	label.custom_minimum_size.x = TEXT_WIDTH
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	yes_button = Button.new()
	no_button = Button.new()
	for b: Button in [yes_button, no_button]:
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_stylebox_override("focus", focus)
		b.custom_minimum_size.x = 140.0
		row.add_child(b)
	# The arrows move between the two whatever the layout has placed yet.
	for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		yes_button.set_focus_neighbor(side, yes_button.get_path_to(no_button))
		no_button.set_focus_neighbor(side, no_button.get_path_to(yes_button))
	yes_button.pressed.connect(answer.bind(true))
	no_button.pressed.connect(answer.bind(false))
	hide()


## Asks `question`; yes (`yes_text`, Enter) calls `on_yes`, no (Esc) `on_no` when it is valid.
## The yes button takes the focus.
func ask(question: String, yes_text: String, on_yes: Callable, on_no: Callable = Callable()) -> void:
	label.text = question
	yes_button.text = "%s (Enter)" % yes_text
	no_button.text = "Cancel (Esc)"
	_on_yes = on_yes
	_on_no = on_no
	show()
	yes_button.grab_focus()


## Closes the dialog and does what the answer calls for.
func answer(yes: bool) -> void:
	if not visible:
		return
	hide()
	var call: Callable = _on_yes if yes else _on_no
	_on_yes = Callable()
	_on_no = Callable()
	if call.is_valid():
		call.call()


## Esc before anything else sees it; every key but the buttons' own stays here.
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	if event.is_action_pressed(CANCEL_ACTION):
		answer(false)
		get_viewport().set_input_as_handled()
		return
	for a: StringName in PASS_ACTIONS:
		if event.is_action(a):
			return
	get_viewport().set_input_as_handled()
