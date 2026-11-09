class_name SimSpeedPanel
extends PanelContainer
## The guests' day controls in Build and Play (E3-S5, D53; docs/design.md Economy and time): Pause, 1x and
## 3x (keys P, 1 and 3), skip to morning (key M, E4-S3: GuestSim.skip_to_morning), and a line
## with the day, its simulated time and the guests out on the course, or that it is skipping.

const ACTIONS: Dictionary = {&"sim_pause": 0.0, &"sim_speed_1": 1.0, &"sim_speed_3": 3.0}
const SKIP_ACTION: StringName = &"sim_skip"

var sim: GuestSim
## Speed -> its button.
var buttons: Dictionary = {}
## E4-S3: skip to morning ("Morning (M)"); disabled while a skip runs.
var skip_button: Button
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
	skip_button = Button.new()
	skip_button.name = "SkipToMorning"
	# In the speeds' row, so the panel keeps its height and the feed under it in Play stays put.
	skip_button.text = "Morning (M)"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.tooltip_text = "Skip to morning: run the rest of the day at once"
	skip_button.pressed.connect(_on_skip)
	row.add_child(skip_button)
	if sim != null:
		_sync()


func bind(p_sim: GuestSim) -> void:
	sim = p_sim
	sim.speed_changed.connect(func(_s: float) -> void: _sync())
	sim.skip_changed.connect(func(_on: bool) -> void: _sync())
	if is_node_ready():
		_sync()


func _on_pressed(s: float) -> void:
	if sim != null:
		sim.set_speed(s)


func _on_skip() -> void:
	if sim != null:
		sim.skip_to_morning()


func _process(_delta: float) -> void:
	if visible and sim != null:
		status_label.text = status_text()


## "Day 2  1:05 / 9:00  6 guests out" (simulated minutes and seconds); while a skip runs,
## "Day 2  4:12 / 9:00  skipping".
func status_text() -> String:
	var t := int(sim.clock_s())
	var day_s := int(sim.tuning.day_s) if sim.tuning != null else 540
	var n := sim.guests_on_course()
	var tail := "skipping" if sim.skipping else "%d guest%s out" % [n, "" if n == 1 else "s"]
	return "Day %d  %d:%02d / %d:%02d  %s" % [maxi(sim.day, 1), t / 60, t % 60,
			day_s / 60, day_s % 60, tail]


func _unhandled_input(event: InputEvent) -> void:
	if not visible or sim == null:
		return
	for action: StringName in ACTIONS:
		if event.is_action_pressed(action):
			sim.set_speed(ACTIONS[action])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(SKIP_ACTION):
		sim.skip_to_morning()
		get_viewport().set_input_as_handled()


func _sync() -> void:
	for s: float in buttons:
		(buttons[s] as Button).set_pressed_no_signal(is_equal_approx(s, sim.speed))
	if skip_button != null:
		skip_button.disabled = sim.skipping
