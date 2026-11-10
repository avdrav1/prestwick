class_name KeyboardShot
extends Node2D
## Screenshot fixture for E5-S6: the keyboard's focus states, reached with key events alone
## (Viewport.push_input). KEY_SHOT picks one:
##   palette  a New course (seed 7): the Build cursor moved by the arrows with the 3 brush, then
##            F6: the ring on the tool in hand (the default)
##   hole     the playtest nine in Build: F6 to the hole list, Right to hole 1's Open
##   fee      the same, F6 on to the fee slider
##   play     the playtest nine in Play: F6 to the swing panel, Right to the bar speed
##   help     F1's key map over Build
##   KEY_SHOT=hole scripts/screenshot.sh tests/fixtures/keyboard_shot.tscn out.png 20

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _main: Main


func _ready() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	var shot := OS.get_environment("KEY_SHOT")
	_main.course_path = PlaytestNine.PATH if shot in ["hole", "fee", "play"] else ""
	_main.start_seed = 7
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	match shot:
		"hole":
			_tap(KEY_F6)
			_tap(KEY_F6)
			await get_tree().process_frame
			_tap(KEY_RIGHT)
		"fee":
			for i: int in 12:
				_tap(KEY_F6)
				if _main.get_viewport().gui_get_focus_owner() == _main.fee_panel.slider:
					break
		"play":
			_tap(KEY_TAB)
			await get_tree().process_frame
			await get_tree().process_frame
			_tap(KEY_F6)
			await get_tree().process_frame
			for i: int in 3:
				if _main.get_viewport().gui_get_focus_owner() == _main.swing_panel.speed_slider:
					break
				_tap(KEY_RIGHT)
		"help":
			_tap(KEY_F1)
		_:
			_tap(KEY_BRACKETRIGHT)
			for i: int in 4:
				_tap(KEY_DOWN)
			for i: int in 3:
				_tap(KEY_RIGHT)
			_tap(KEY_F6)


func _tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		_main.get_viewport().push_input(e)
