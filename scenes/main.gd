class_name Main
extends Node2D
## The one main scene. Build and Play are states on it, never separate scenes (D2).

enum Mode { BUILD, PLAY }

signal mode_changed(new_mode: Mode)

const TOGGLE_ACTION: StringName = &"toggle_mode"

## Course loaded at start. Until E2-S8 the main scene starts on the 20x20 heights fixture;
## New sandbox (E2-S3) starts the D10 blank plot. An empty path or a failed load gives a flat
## 20x20 rough plot.
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
@onready var new_sandbox_button: Button = $HUD/NewSandboxButton
@onready var hole_panel: HolePanel = $HUD/HolePanel


func _ready() -> void:
	if debug_shot == null:
		debug_shot = DebugShot.load_default()
	fire_button.pressed.connect(fire_debug_shot)
	new_sandbox_button.pressed.connect(new_sandbox)
	_refresh_label()
	build_palette.bind(build_tool)
	hole_panel.bind(build_tool)
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
	# The builder first: it closes any open hole the course brought in failing a rule, and the
	# view then draws the holes as they are.
	var builder := CourseBuilder.new(c)
	course_view.show_course(c)
	camera.frame(course_view.screen_bounds())
	builder.tiles_changed.connect(_on_tiles_changed)
	builder.holes_changed.connect(course_view.refresh_holes)
	builder.checked.connect(_on_checked)
	build_tool.builder = builder
	_on_checked(builder.issues)


## Starts a new course on the blank plot (D10, BuilderTuning), with a fresh builder.
func new_sandbox() -> void:
	show_course(CourseBuilder.new_sandbox())


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


## The build tool, its palette, the hole panel, New sandbox and the issue highlights exist
## only in Build mode. Play never waits for the validator (pillar 1): a hole that fails a rule
## is still played; the rules only decide whether guests may play it (Open).
func _apply_mode() -> void:
	var building: bool = mode == Mode.BUILD
	build_tool.active = building
	build_palette.visible = building
	hole_panel.visible = building
	new_sandbox_button.visible = building
	course_view.issues_visible = building


func _on_tiles_changed(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		course_view.refresh_cell(cell)


## After every builder check: highlight each failing rule and update the hole panel.
func _on_checked(issues: Dictionary) -> void:
	course_view.show_issues(issues)
	hole_panel.refresh()


## Fires the debug shot at its fixed power and angle, predicting the landing first.
func fire_debug_shot() -> void:
	if course == null:
		return
	var field := HeightField.new(course, BallParams.load_default())
	shot_view.fire(course, debug_shot.start_position(field), debug_shot.velocity(), debug_shot.rng_seed)


func _refresh_label() -> void:
	mode_label.text = Mode.keys()[mode]
	fire_button.visible = mode == Mode.PLAY
