class_name SwingPanel
extends PanelContainer
## The Play-mode swing panel (E2-S7): the club picker (the clubs the lie and stroke allow,
## D13), the swing bar, and the bar speed setting (accessibility). A view onto a
## SwingControl: buttons and the slider go through it, and refresh() follows its `changed`.
##
## E10-S3, the bar explains itself (the rc4 tester could not tell how the bar relates to the
## distance): the bar carries the club's yards at 50%, 100% and max and labels the accuracy
## zone (SwingBar.marks, from SwingControl.carry_at: ShotModel with the club and the lie); the
## readout beside the club says the carry the power gives ("Carry 124 yd at 85%": a full
## swing's before click 1, the bar's while it fills, the locked power's after click 2), while
## SwingControl moves the landing marker with it; the putter's readout is the distance to the
## cup, in feet under SwingReadoutTuning.putt_feet_below_yd, else yards. The first swing shows a
## practice hint above the panel (hint_panel) until a swing strikes; then it is saved as seen in
## user settings (HintSettings, user://, not the save) and never shows again. The hint is the
## panel's top row while it shows and takes no clicks.

var club_label: Label
var prev_button: Button
var next_button: Button
var bar: SwingBar
var speed_slider: HSlider
var speed_label: Label
var hint_label: Label
## E10-S3: the live readout, and the one-time practice hint (a panel floating above this one).
var readout_label: Label
var hint_panel: PanelContainer
var hint_text_label: Label
## sun_yellow: the readout while the power is live.
var live_color: Color = Color8(240, 200, 58)
## Where the hint's seen flag is kept (HintSettings); load_hint changes it.
var hint_settings_path: String = HintSettings.PATH
var readout_tuning: SwingReadoutTuning = SwingReadoutTuning.load_default()
var _hint_settings: HintSettings
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
	club_label.custom_minimum_size = Vector2(140, 0)
	club_label.mouse_filter = Control.MOUSE_FILTER_PASS
	club_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(club_label)
	next_button = _button(">", "Shorter club (Down)", func() -> void: _control.cycle_club(1))
	row.add_child(next_button)
	readout_label = Label.new()
	readout_label.custom_minimum_size = Vector2(175, 0)
	readout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout_label.mouse_filter = Control.MOUSE_FILTER_PASS
	readout_label.tooltip_text = "How far the ball carries at this power, from this lie"
	row.add_child(readout_label)
	var speed_title := Label.new()
	speed_title.text = " Speed"
	speed_title.tooltip_text = "Bar speed"
	speed_title.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(speed_title)
	speed_slider = HSlider.new()
	speed_slider.custom_minimum_size = Vector2(90, 0)
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
	_build_practice_hint(box)


## E10-S3: the practice hint, the panel's top row while it shows (so hole framing keeps the
## map clear of it, as of the rest of the panel).
func _build_practice_hint(box: VBoxContainer) -> void:
	hint_panel = PanelContainer.new()
	hint_panel.visible = false
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(26, 28, 34)
	style.border_color = live_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	style.content_margin_left = 10
	hint_panel.add_theme_stylebox_override("panel", style)
	box.add_child(hint_panel)
	box.move_child(hint_panel, 0)
	hint_text_label = Label.new()
	hint_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_text_label.add_theme_font_size_override("font_size", 14)
	hint_text_label.text = "First swing: Click 1 starts the bar.\n" \
			+ "Click 2 sets the distance: the yards and the landing marker follow the bar.\n" \
			+ "Click 3 as it comes back through the green zone keeps the shot straight."
	hint_panel.add_child(hint_text_label)


## Loads the hint's seen flag from `path` (HintSettings) and shows the hint if it is unseen.
func load_hint(path: String = hint_settings_path) -> void:
	hint_settings_path = path
	_hint_settings = HintSettings.load_from(path)
	hint_panel.visible = not _hint_settings.swing_seen


## A swing struck: the hint has done its job; saved as seen, never shown again.
func _on_struck(_shot: ShotLaunch) -> void:
	if _hint_settings == null or _hint_settings.swing_seen:
		return
	_hint_settings.swing_seen = true
	_hint_settings.save_to(hint_settings_path)
	hint_panel.visible = false


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
	_control.struck.connect(_on_struck)
	load_hint()
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
	_refresh_marks()
	refresh_readout()
	bar.queue_redraw()


## E10-S3: the bar's yard marks for the selected club from where the ball lies (none for the
## putter): SwingReadoutTuning.label_powers and SwingTuning.max_power.
func _refresh_marks() -> void:
	var marks: Array[Dictionary] = []
	var c := _control.club
	if c != null and not c.is_putter() and _control.field != null:
		var powers: Array[float] = []
		for p: float in readout_tuning.label_powers:
			if p < _control.tuning.max_power:
				powers.append(p)
		powers.append(_control.tuning.max_power)
		for p: float in powers:
			marks.append({power = p, yards = _control.carry_at(p)})
	bar.marks = marks


## E10-S3: the readout: the carry at the swing's power (a full swing's before click 1), or for
## the putter the distance to the cup. Once a frame while the bar runs.
func refresh_readout() -> void:
	if _control == null or readout_label == null:
		return
	var c := _control.club
	var text := ""
	var live := false
	if c != null and c.is_putter():
		var d := _control.cup_distance_yd()
		text = "" if is_nan(d) else cup_text(d, readout_tuning.putt_feet_below_yd)
	elif c != null and _control.field != null:
		var p := _control.live_power()
		live = not is_nan(p)
		if not live:
			p = 1.0
		text = "Carry %d yd at %d%%" % [roundi(_control.carry_at(p)), roundi(p * 100.0)]
	if readout_label.text != text:
		readout_label.text = text
	if live:
		readout_label.add_theme_color_override("font_color", live_color)
	else:
		readout_label.remove_theme_color_override("font_color")


## A putt's distance `yards` to the cup as the readout says it: feet under `feet_below` yards.
static func cup_text(yards: float, feet_below: float) -> String:
	if yards < feet_below:
		return "%d ft to the cup" % roundi(yards * 3.0)
	return "%d yd to the cup" % roundi(yards)


func _process(_delta: float) -> void:
	follow_pace()
	if _control != null and _control.swing.in_progress():
		refresh_readout()


## E3-S73: puts the marker's pace (pace_of) on the bar, redrawing it when it moves. Once a
## frame: the putter's solve refines over frames without a `changed` signal.
func follow_pace() -> void:
	if bar == null:
		return
	var p := pace_of(_control)
	if is_nan(p) and is_nan(bar.pace) or p == bar.pace:
		return
	bar.pace = p
	bar.queue_redraw()


## The bar position of the putt the marker shows (the PuttAim solve's power, SwingControl's
## aim_power), or NAN: a full club, no putt solved yet, the ball moving, or not in Play.
static func pace_of(c: SwingControl) -> float:
	if c == null or not c.active or c.club == null or not c.club.is_putter():
		return NAN
	if c.aim_putt == null or c.aim_prediction == null or not c.aim_prediction_is_putt \
			or c.is_ball_moving() or c.is_finished():
		return NAN
	return c.aim_power


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
