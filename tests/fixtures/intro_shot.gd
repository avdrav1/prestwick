class_name IntroShot
extends Node2D
## Screenshot fixture for E21-S1 (D77): the opening flyover at a moment of its clock. The main
## scene (a small fixture course; the intro shows its own) plays the intro and steps it to
## INTRO_AT seconds (default 2), or to a moment named by INTRO_BEAT: "strike" (the ball's
## launch) plus INTRO_AFTER seconds, "rest" (the ball resting) plus INTRO_AFTER, or "title"
## plus INTRO_AFTER. The clock is run ahead at once to just short of the moment, then a frame
## at a time for its last LAST_FRAMES steps so the camera and the sprites have drawn it, and
## then it holds.
##   INTRO_BEAT=strike INTRO_AFTER=3 scripts/screenshot.sh tests/fixtures/intro_shot.tscn out.png 40

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const STEP: float = 1.0 / 60.0
const LAST_FRAMES: int = 12

var _main: Main
var _at: float = 0.0


func _ready() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://tests/fixtures/flat_20x20.json"
	_main.intro_settings_path = "user://intro_shot_hints.cfg"
	add_child(_main)
	_main.intro.auto_advance = false
	_main.play_intro()
	var intro := _main.intro
	var after := _env_float("INTRO_AFTER", 0.0)
	match OS.get_environment("INTRO_BEAT"):
		"strike":
			_at = intro.strike_time() + after
		"rest":
			_at = intro.rest_time() + after
		"title":
			_at = intro.title_time() + after
		_:
			_at = _env_float("INTRO_AT", 2.0)
	while intro.playing and intro.time < _at - LAST_FRAMES * STEP:
		intro.advance(STEP)
	print("intro shot: %.2f s of %.2f (strike %.2f, rest %.2f, title %.2f)" % [_at,
			intro.duration(), intro.strike_time(), intro.rest_time(), intro.title_time()])


func _process(_delta: float) -> void:
	var intro := _main.intro
	if intro.playing and intro.time < _at:
		intro.advance(STEP)
		if not intro.playing or intro.time >= _at:
			print("intro shot: beat %s, camera zoom %.2f, bend drawn %.1f yd" % [
					OpeningFlyover.Beat.keys()[intro.beat()],
					intro.camera.zoom.x if intro.camera != null else 0.0,
					intro.trail.bend_yd() if intro.trail != null else 0.0])


static func _env_float(name: String, fallback: float) -> float:
	var s := OS.get_environment(name)
	return s.to_float() if s != "" else fallback
