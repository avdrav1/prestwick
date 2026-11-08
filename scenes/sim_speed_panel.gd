class_name SimSpeedPanel
extends PanelContainer
## The guests' day controls in Build and Play (E3-S5, D53; docs/design.md Economy and time): Pause, 1x and
## 3x (keys P, 1 and 3), and a line with the day, its simulated time and the guests out on the
## course. Skip to morning waits for E4, which settles what a day's end pays and costs.

const ACTIONS: Dictionary = {&"sim_pause": 0.0, &"sim_speed_1": 1.0, &"sim_speed_3": 3.0}

var sim: GuestSim
## Speed -> its button.
var buttons: Dictionary = {}
var status_label: Label


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	status_label = Label.new()
	status_label.name = "Status"
	box.add_child(status_label)
	var row := HBoxContainer.new()
	box.add_child(row)
	var group := ButtonGroup.new()
	for s: float in GuestSim.SPEEDS:
		var b := Button.new()
		b.text = "Pause (P)" if s <= 0.0 else "%dx (%d)" % [int(s), int(s)]
		b.name = "Pause" if s <= 0.0 else "Speed%d" % int(s)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Pause the guests' day" if s <= 0.0 else "Run the guests' day at %dx" % int(s)
		b.pressed.connect(_on_pressed.bind(s))
		row.add_child(b)
		buttons[s] = b
	if sim != null:
		_sync()


func bind(p_sim: GuestSim) -> void:
	sim = p_sim
	sim.speed_changed.connect(func(_s: float) -> void: _sync())
	if is_node_ready():
		_sync()


func _on_pressed(s: float) -> void:
	if sim != null:
		sim.set_speed(s)


func _process(_delta: float) -> void:
	if visible and sim != null:
		status_label.text = status_text()


## "Day 2  1:05 / 3:00  6 guests out" (simulated minutes and seconds).
func status_text() -> String:
	var t := int(sim.clock_s())
	var day_s := int(sim.tuning.day_s) if sim.tuning != null else 180
	var n := sim.guests_on_course()
	return "Day %d  %d:%02d / %d:%02d  %d guest%s out" % [maxi(sim.day, 1), t / 60, t % 60,
			day_s / 60, day_s % 60, n, "" if n == 1 else "s"]


func _unhandled_input(event: InputEvent) -> void:
	if not visible or sim == null:
		return
	for action: StringName in ACTIONS:
		if event.is_action_pressed(action):
			sim.set_speed(ACTIONS[action])
			get_viewport().set_input_as_handled()
			return


func _sync() -> void:
	for s: float in buttons:
		(buttons[s] as Button).set_pressed_no_signal(is_equal_approx(s, sim.speed))
