class_name SwingPanel
extends PanelContainer
## The Play-mode swing panel (E2-S7): the club picker (the clubs the lie and stroke allow,
## D13), the swing bar, and the bar speed setting (accessibility). A view onto a
## SwingControl: buttons and the slider go through it, and refresh() follows its `changed`.

var club_label: Label
var prev_button: Button
var next_button: Button
var bar: SwingBar
var speed_slider: HSlider
var speed_label: Label
var hint_label: Label
## flag_red (art/palette.gpl): the club label's colour when the club is blocked (D20).
var blocked_color: Color = Color8(216, 58, 58)

var _control: SwingControl


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	prev_button = _button("<", "Longer club (Up)", func() -> void: _control.cycle_club(-1))
	row.add_child(prev_button)
	club_label = Label.new()
	club_label.custom_minimum_size = Vector2(190, 0)
	club_label.mouse_filter = Control.MOUSE_FILTER_PASS
	club_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(club_label)
	next_button = _button(">", "Shorter club (Down)", func() -> void: _control.cycle_club(1))
	row.add_child(next_button)
	var speed_title := Label.new()
	speed_title.text = "  Bar speed"
	row.add_child(speed_title)
	speed_slider = HSlider.new()
	speed_slider.custom_minimum_size = Vector2(110, 0)
	speed_slider.step = 0.05
	speed_slider.focus_mode = Control.FOCUS_NONE
	speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_slider.tooltip_text = "How fast the swing bar moves (accessibility)"
	row.add_child(speed_slider)
	speed_label = Label.new()
	speed_label.custom_minimum_size = Vector2(44, 0)
	row.add_child(speed_label)
	bar = SwingBar.new()
	box.add_child(bar)
	hint_label = Label.new()
	hint_label.text = "Space or click: start, power, accuracy.  Mouse or Left/Right: aim.  WASD: pan, C: back to ball."
	hint_label.add_theme_font_size_override("font_size", 12)
	box.add_child(hint_label)


## Follows `control` from now on.
func bind(control: SwingControl) -> void:
	_control = control
	bar.swing = control.swing
	var t := control.tuning
	speed_slider.min_value = t.bar_speed_min
	speed_slider.max_value = t.bar_speed_max
	speed_slider.set_value_no_signal(control.swing.bar_speed)
	# Connected only now: setting the range clamps the value and would emit.
	speed_slider.value_changed.connect(_on_speed_changed)
	_control.changed.connect(refresh)
	refresh()


## Shows the control's club, legal clubs and swing as they are now.
func refresh() -> void:
	if _control == null or club_label == null:
		return
	var c := _control.club
	club_label.text = "Club: %s" % (_club_name(c) if c != null else "none")
	if _control.aim_blocked:
		club_label.text += " (blocked)"
		club_label.add_theme_color_override("font_color", blocked_color)
		club_label.tooltip_text = "The slope or trees ahead stop this club before it peaks. Try a club with more loft, or aim elsewhere."
	else:
		club_label.remove_theme_color_override("font_color")
		club_label.tooltip_text = ""
	var i := _control.legal.find(c)
	var busy := _control.swing.in_progress()
	prev_button.disabled = busy or i <= 0
	next_button.disabled = busy or i < 0 or i >= _control.legal.size() - 1
	speed_label.text = "%.2fx" % _control.swing.bar_speed
	bar.queue_redraw()


func _on_speed_changed(value: float) -> void:
	_control.swing.bar_speed = value
	refresh()


func _button(text: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28, 0)
	b.pressed.connect(fn)
	return b


static func _club_name(c: Club) -> String:
	match c.id:
		"driver", "putter":
			return c.id.capitalize()
		"pw":
			return "PW"
		"sw":
			return "SW"
	return c.id
