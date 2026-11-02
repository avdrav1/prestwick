class_name Main
extends Node2D
## The one main scene. Build and Play are states on it, never separate scenes (D2).

enum Mode { BUILD, PLAY }

signal mode_changed(new_mode: Mode)

const TOGGLE_ACTION: StringName = &"toggle_mode"

## Course loaded at start. Until a plot exists (E2-S1 sets the blank plot), this is the
## 20x20 heights fixture. An empty path or a failed load gives a flat 20x20 rough plot.
@export_file("*.json") var course_path: String = "res://courses/heights_20x20.json"
## The fixed shot the Play-mode debug button fires (E1-S7). Null loads golf/debug_shot.tres.
@export var debug_shot: DebugShot

var mode: Mode = Mode.BUILD
## The course being built and played. Only course/builder.gd and course/save.gd write it.
var course: CourseData

@onready var mode_label: Label = $HUD/ModeLabel
@onready var course_view: CourseView = $CourseView
@onready var camera: CourseCamera = $Camera
@onready var build_tool: BuildTool = $BuildTool
@onready var build_palette: BuildPalette = $HUD/BuildPalette
@onready var shot_view: ShotView = $CourseView/ShotView
@onready var fire_button: Button = $HUD/FireButton


func _ready() -> void:
	if debug_shot == null:
		debug_shot = DebugShot.load_default()
	fire_button.pressed.connect(fire_debug_shot)
	_refresh_label()
	build_palette.bind(build_tool)
	_apply_mode()
	var errors: Array[String] = []
	var loaded: CourseData = null
	if not course_path.is_empty():
		loaded = CourseSave.load_file(course_path, errors)
	if loaded == null:
		if not errors.is_empty():
			push_warning("main: %s" % "; ".join(errors))
		loaded = CourseData.create(20, 20)
	show_course(loaded)


## Shows `c`, frames the camera on it and hands it to a fresh builder (empty undo stack).
func show_course(c: CourseData) -> void:
	course = c
	shot_view.clear()
	course_view.show_course(c)
	camera.frame(course_view.screen_bounds())
	var builder := CourseBuilder.new(c)
	builder.tiles_changed.connect(_on_tiles_changed)
	build_tool.builder = builder


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
	_apply_mode()
	if mode != Mode.PLAY:
		shot_view.clear()
	mode_changed.emit(mode)


## The build tool and its palette exist only in Build mode.
func _apply_mode() -> void:
	build_tool.active = mode == Mode.BUILD
	build_palette.visible = mode == Mode.BUILD


func _on_tiles_changed(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		course_view.refresh_cell(cell)


## Fires the debug shot at its fixed power and angle, predicting the landing first.
func fire_debug_shot() -> void:
	if course == null:
		return
	var field := HeightField.new(course, BallParams.load_default())
	shot_view.fire(course, debug_shot.start_position(field), debug_shot.velocity(), debug_shot.rng_seed)


func _refresh_label() -> void:
	mode_label.text = Mode.keys()[mode]
	fire_button.visible = mode == Mode.PLAY
