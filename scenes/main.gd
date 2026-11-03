class_name Main
extends Node2D
## The one main scene. Build and Play are states on it, never separate scenes (D2).

enum Mode { BUILD, PLAY }

signal mode_changed(new_mode: Mode)

const TOGGLE_ACTION: StringName = &"toggle_mode"
## Fires the debug shot in Play, in debug builds only (E2-S8; F3).
const DEBUG_SHOT_ACTION: StringName = &"debug_shot"

## Course loaded at start (E2-S8). Empty, the default, starts on the D10 blank plot
## (CourseBuilder.new_sandbox), as New sandbox does; a failed load warns and does the same.
@export_file("*.json") var course_path: String = ""
## The fixed shot the debug key fires (E1-S7, E2-S8). Null loads golf/debug_shot.tres.
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
@onready var mode_button: Button = $HUD/ModeButton
@onready var score_card: ScoreCard = $HUD/ScoreCard
@onready var new_sandbox_button: Button = $HUD/NewSandboxButton
@onready var hole_panel: HolePanel = $HUD/HolePanel
@onready var swing_control: SwingControl = $SwingControl
@onready var aim_view: AimView = $AimView
@onready var swing_panel: SwingPanel = $HUD/SwingPanel


func _ready() -> void:
	if debug_shot == null:
		debug_shot = DebugShot.load_default()
	mode_button.pressed.connect(toggle_mode)
	new_sandbox_button.pressed.connect(new_sandbox)
	_refresh_label()
	build_palette.bind(build_tool)
	hole_panel.bind(build_tool)
	swing_control.bind(shot_view, aim_view)
	swing_panel.bind(swing_control)
	swing_control.changed.connect(_refresh_label)
	swing_control.struck.connect(_on_struck)
	swing_control.hole_finished.connect(_on_hole_finished)
	shot_view.came_to_rest.connect(_on_came_to_rest)
	score_card.bind(swing_control)
	_apply_mode()
	var errors: Array[String] = []
	var loaded: CourseData = null
	if not course_path.is_empty():
		loaded = CourseSave.load_file(course_path, errors)
	if loaded == null:
		if not errors.is_empty():
			push_warning("main: %s" % "; ".join(errors))
		loaded = CourseBuilder.new_sandbox()
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
	if mode == Mode.PLAY:
		_begin_play()


## Starts a new course on the blank plot (D10, BuilderTuning), with a fresh builder.
func new_sandbox() -> void:
	show_course(CourseBuilder.new_sandbox())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(DEBUG_SHOT_ACTION) and mode == Mode.PLAY and OS.is_debug_build():
		fire_debug_shot()
		get_viewport().set_input_as_handled()


## Keeps the camera on a moving ball (E2-S8), unless the player panned away to scout.
func _process(_delta: float) -> void:
	if mode == Mode.PLAY and shot_view.playing:
		camera.set_focus(_ball_world())


func toggle_mode() -> void:
	set_mode(Mode.PLAY if mode == Mode.BUILD else Mode.BUILD)


func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	_apply_mode()
	if mode == Mode.PLAY:
		_begin_play()
	else:
		shot_view.clear()
	_refresh_label()
	mode_changed.emit(mode)


## Puts the ball on hole 1's tee aimed at its cup (or on the debug shot's tile when the
## course has no tee yet) for the swing (E2-S7), with a fresh score, and centres the camera
## on it (E2-S8).
func _begin_play() -> void:
	swing_control.begin(course, debug_shot.start_tile, debug_shot.heading_deg)
	camera.centre_on(_ball_world())


## The ball's drawn point in the camera's space.
func _ball_world() -> Vector2:
	var p := shot_view.get_parent() as Node2D
	return camera.get_parent().to_local(p.to_global(shot_view.ball_screen())) \
			if shot_view.ball != null else camera.position


## A shot starts: centre on the ball (E2-S8), even after a pan.
func _on_struck(_shot: ShotLaunch) -> void:
	camera.centre_on(_ball_world())


## Holed or picked up: no more swings, so the swing panel goes until Play starts again.
func _on_hole_finished(_score: HoleScore) -> void:
	swing_panel.visible = false


## The ball rests (or was dropped): centre on it for the next shot (E2-S8).
func _on_came_to_rest(_at: Vector3) -> void:
	if mode == Mode.PLAY:
		camera.centre_on(_ball_world())


## The build tool, its palette, the hole panel, New sandbox and the issue highlights exist
## only in Build mode. Play never waits for the validator (pillar 1): a hole that fails a rule
## is still played; the rules only decide whether guests may play it (Open).
func _apply_mode() -> void:
	var building: bool = mode == Mode.BUILD
	build_tool.active = building
	swing_control.active = not building
	swing_panel.visible = not building
	build_palette.visible = building
	hole_panel.visible = building
	new_sandbox_button.visible = building
	score_card.visible = not building
	mode_button.text = "Back to Build (Tab)" if not building else "Play hole (Tab)"
	course_view.issues_visible = building


func _on_tiles_changed(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		course_view.refresh_cell(cell)


## After every builder check: highlight each failing rule and update the hole panel.
func _on_checked(issues: Dictionary) -> void:
	course_view.show_issues(issues)
	hole_panel.refresh()


## True when the debug shot may fire: in Play, with no swing in progress and no ball moving.
func can_fire_debug_shot() -> bool:
	return (course != null and mode == Mode.PLAY and not swing_control.swing.in_progress()
			and not swing_control.is_ball_moving())


## Fires the debug shot at its fixed power and angle, predicting the landing first (the
## debug key, E2-S8). Only when can_fire_debug_shot, so it never replaces the player's ball
## in flight; and it never moves the swing ball or counts a stroke (SwingControl rests only
## its own strokes).
func fire_debug_shot() -> void:
	if not can_fire_debug_shot():
		return
	var field := HeightField.new(course, BallParams.load_default())
	aim_view.clear()
	shot_view.fire(course, debug_shot.start_position(field), debug_shot.velocity(), debug_shot.rng_seed)
	_refresh_label()


func _refresh_label() -> void:
	mode_label.text = Mode.keys()[mode]
