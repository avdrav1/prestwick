class_name AudioPanel
extends PanelContainer
## The sound panel (E5-S4): a slider per bus (Master, Music, Ambient, SFX), 0 to 100. F2
## (`audio_settings`) opens and closes it in Build and Play; Escape or Close closes it. Opened,
## it takes the keyboard focus on its first slider: up and down move between sliders, left and
## right change one by AudioPanel.STEP. Every change applies at once and is saved
## (GameAudio.set_volume, user://audio_settings.cfg). While it is open the swing key does
## not swing behind it. Centred over the map, shown only while open.

## Emitted when the panel closes.
signal closed

const ACTION: StringName = &"audio_settings"
const STEP: float = 5.0
const LABELS: Dictionary = {
	&"Master": "Master", &"Music": "Music", &"Ambient": "Ambient", &"SFX": "Effects",
}

var sliders: Dictionary = {}
var values: Dictionary = {}
var close_button: Button

var _audio: GameAudio


func _ready() -> void:
	visible = false
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Sound (F2)"
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for bus: StringName in AudioSettings.BUSES:
		var label := Label.new()
		label.text = LABELS[bus]
		grid.add_child(label)
		var slider := HSlider.new()
		slider.name = String(bus)
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = STEP
		slider.custom_minimum_size = Vector2(200.0, 0.0)
		slider.focus_mode = Control.FOCUS_ALL
		slider.value_changed.connect(_on_changed.bind(bus))
		grid.add_child(slider)
		sliders[bus] = slider
		var value := Label.new()
		value.custom_minimum_size = Vector2(36.0, 0.0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		values[bus] = value
	close_button = Button.new()
	close_button.text = "Close"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(close)
	box.add_child(close_button)
	# Up and down walk the sliders, then Close, round and round.
	var order: Array[Control] = []
	for bus: StringName in AudioSettings.BUSES:
		order.append(sliders[bus])
	order.append(close_button)
	for i in order.size():
		var c := order[i]
		c.focus_neighbor_top = c.get_path_to(order[(i - 1 + order.size()) % order.size()])
		c.focus_neighbor_bottom = c.get_path_to(order[(i + 1) % order.size()])
		c.focus_previous = c.focus_neighbor_top
		c.focus_next = c.focus_neighbor_bottom


## Reads and sets volumes through `audio` from now on.
func bind(audio: GameAudio) -> void:
	_audio = audio


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	for bus: StringName in AudioSettings.BUSES:
		var v := roundf(_audio.volume(bus) * 100.0) if _audio != null else 100.0
		(sliders[bus] as HSlider).set_value_no_signal(v)
		_show_value(bus, v)
	show()
	reset_size()
	size = get_combined_minimum_size()
	position = (get_viewport_rect().size - size) * 0.5
	(sliders[AudioSettings.BUSES[0]] as HSlider).grab_focus()


func close() -> void:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f != null and is_ancestor_of(f):
		f.release_focus()
	var was := visible
	hide()
	if was:
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action(&"swing"):
		get_viewport().set_input_as_handled()


func _on_changed(v: float, bus: StringName) -> void:
	_show_value(bus, v)
	if _audio != null:
		_audio.set_volume(bus, v / 100.0)


func _show_value(bus: StringName, v: float) -> void:
	(values[bus] as Label).text = "%d" % int(v)
