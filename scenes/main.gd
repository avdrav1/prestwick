class_name Main
extends Node2D
## The one main scene. Build and Play are states on it, never separate scenes (D2).

enum Mode { BUILD, PLAY }

signal mode_changed(new_mode: Mode)

const TOGGLE_ACTION: StringName = &"toggle_mode"

var mode: Mode = Mode.BUILD

@onready var mode_label: Label = $HUD/ModeLabel


func _ready() -> void:
	_refresh_label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle_mode()
		get_viewport().set_input_as_handled()


func toggle_mode() -> void:
	set_mode(Mode.PLAY if mode == Mode.BUILD else Mode.BUILD)


func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	_refresh_label()
	mode_changed.emit(mode)


func _refresh_label() -> void:
	mode_label.text = Mode.keys()[mode]
