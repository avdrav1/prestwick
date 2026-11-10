class_name HudFocus
extends Node
## E5-S6: the HUD in the keyboard's reach, with a focus ring you can see. F6 (hud_focus_next)
## puts the keyboard on the HUD: the first stop shown (`stops`, in order: the build palette or the
## swing panel, the hole panel, the feed, the left column's buttons, the speed panel, the fee, the
## save notice), on its picked button where it has one; F6 again moves to the next stop, Shift+F6
## (hud_focus_prev) back. Inside a stop the arrows move between controls (Godot's focus
## neighbours) and Space or Enter presses a button; a focused slider takes Left and Right. Esc,
## Tab (which still switches Build and Play) or any mouse click hands the keys back to the map:
## the swing, the aim and the Build cursor.
##
## While a `blockers` control is shown (the main menu, E5-S5, and the sound panel, E5-S4, which
## hold their own focus), F6 and Esc are theirs: HudFocus lets go and takes no key.
##
## The HUD's buttons and sliders take no focus otherwise (focus_mode NONE, as they always had),
## so a mouse click never leaves a button holding Space; `active` turns focus on for every button
## and slider in the stops (FOCUS_ALL, with `focus_color`'s ring) and off again.

const NEXT_ACTION: StringName = &"hud_focus_next"
const PREV_ACTION: StringName = &"hud_focus_prev"
const LEAVE_ACTION: StringName = &"ui_cancel"
const TOGGLE_ACTION: StringName = &"toggle_mode"

## The focus ring (art/palette.gpl `sun_yellow`), drawn round the focused control.
@export var focus_color: Color = Color8(240, 200, 58)
## The ring's width, px.
@export var focus_width: int = 3

## The HUD's stops, in F6 order. Each is a Control whose buttons and sliders take focus.
var stops: Array[Control] = []
## True while the keyboard is on the HUD.
var active: bool = false
## Controls with their own focus (the main menu, the sound panel): while one is shown, HudFocus
## takes no key.
var blockers: Array[Control] = []

var _ring: StyleBoxFlat


func _ready() -> void:
	_ring = StyleBoxFlat.new()
	_ring.draw_center = false
	_ring.border_color = focus_color
	_ring.set_border_width_all(focus_width)
	_ring.set_corner_radius_all(2)
	_ring.set_expand_margin_all(1)
	get_tree().node_added.connect(_on_node_added)


## Puts `p_stops` in the keyboard's reach, in F6 order; while one of `p_blockers` is shown it
## takes no key.
func bind(p_stops: Array[Control], p_blockers: Array[Control] = []) -> void:
	stops = p_stops
	blockers = p_blockers


## True while a blocker (the main menu, the sound panel) is shown.
func blocked() -> bool:
	for b: Control in blockers:
		if is_instance_valid(b) and b.is_visible_in_tree():
			return true
	return false


## The stops shown now that hold something to focus.
func shown_stops() -> Array[Control]:
	return stops.filter(func(s: Control) -> bool: return s.is_visible_in_tree() and not _targets(s, true).is_empty())


## The control the keyboard is on, when it is in one of the stops; else null.
func focused() -> Control:
	var vp := get_viewport()
	var c: Control = vp.gui_get_focus_owner() if vp != null else null
	return c if c != null and _stop_of(c) != null else null


## Moves the keyboard to the next stop shown (`dir` 1) or the one before (-1), wrapping; from the
## map, to the first (or, going back, the last). False when no stop is shown.
func step(dir: int) -> bool:
	var shown: Array[Control] = shown_stops()
	if shown.is_empty():
		return false
	set_active(true)
	var at: int = shown.find(_stop_of(focused()))
	var next: int = (0 if dir > 0 else shown.size() - 1) if at < 0 else posmod(at + dir, shown.size())
	return enter(shown[next])


## Focuses `stop`'s picked button (a pressed toggle, such as the tool or the speed), else its
## first enabled control. False when it has none.
func enter(stop: Control) -> bool:
	set_active(true)
	var targets: Array[Control] = _targets(stop, true)
	if targets.is_empty():
		return false
	var pick: Control = targets[0]
	for c: Control in targets:
		var b := c as BaseButton
		if b != null and b.toggle_mode and b.button_pressed and not b.disabled:
			pick = c
			break
	if pick is BaseButton and (pick as BaseButton).disabled:
		for c: Control in targets:
			if not (c is BaseButton and (c as BaseButton).disabled):
				pick = c
				break
	pick.grab_focus()
	return true


## Turns the HUD's focus on (every button and slider in the stops takes it, with the ring) or off
## (they take none, and the one focused lets go).
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	var held: Control = focused()
	if not on and held != null:
		held.release_focus()
	for stop: Control in stops:
		for c: Control in _targets(stop, false):
			_set_focusable(c, on)


func _set_focusable(c: Control, on: bool) -> void:
	c.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	if not on:
		return
	c.add_theme_stylebox_override(&"focus", _ring)
	if c is Slider and c.get_node_or_null(^"FocusRing") == null:
		# A slider draws no focus box of its own, only a lit grabber: it wears the ring on a
		# panel over it, shown while it has the keys.
		var ring := Panel.new()
		ring.name = "FocusRing"
		ring.add_theme_stylebox_override(&"panel", _ring)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		ring.visible = c.has_focus()
		c.add_child(ring)
		c.focus_entered.connect(func() -> void: ring.visible = true)
		c.focus_exited.connect(func() -> void: ring.visible = false)


## A button or slider made while the keyboard is on the HUD (a new hole's row) takes focus too.
func _on_node_added(n: Node) -> void:
	if not active or not _is_target(n):
		return
	var c := n as Control
	if _stop_of(c) != null:
		_set_focusable(c, true)


## Every button and slider in `stop` (itself included), in tree order (the hole list's rows before
## the par buttons under them); with `shown_only`, those shown.
func _targets(stop: Control, shown_only: bool) -> Array[Control]:
	var out: Array[Control] = []
	_collect(stop, shown_only, out)
	return out


func _collect(n: Node, shown_only: bool, out: Array[Control]) -> void:
	if _is_target(n) and (not shown_only or (n as Control).is_visible_in_tree()):
		out.append(n as Control)
	for child: Node in n.get_children():
		_collect(child, shown_only, out)


static func _is_target(n: Node) -> bool:
	return n is BaseButton or n is Slider


## The stop holding `c`, or null.
func _stop_of(c: Control) -> Control:
	if c == null:
		return null
	for stop: Control in stops:
		if stop == c or stop.is_ancestor_of(c):
			return stop
	return null


func _input(event: InputEvent) -> void:
	if blocked():
		# The menu or the sound panel has the keys and its own focus.
		set_active(false)
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# The mouse is back: no button keeps the keys (a click would leave it holding Space).
		set_active(false)
		return
	if event.is_action_pressed(PREV_ACTION):
		step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(NEXT_ACTION):
		step(1)
		get_viewport().set_input_as_handled()
	elif not active:
		return
	elif event.is_action_pressed(LEAVE_ACTION) and focused() != null:
		set_active(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(TOGGLE_ACTION):
		# Tab switches Build and Play from the HUD too: the keys go back to the map and the
		# event goes on to Main.
		set_active(false)
