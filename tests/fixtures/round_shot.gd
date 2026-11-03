class_name RoundShot
extends Node2D
## Screenshot fixture for E2-S8: courses/example_par3.json played in the main scene by the
## scripted player (scripts/scripted_round.gd) up to `strokes` strokes, the last ball at rest
## and the camera centred on it, so the scorecard and the next shot show.
## Run: scripts/screenshot.sh tests/fixtures/round_shot.tscn (holed), or
## tests/fixtures/round_shot_tee.tscn for the first click from Build (on the tee).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COURSE_PATH: String = "res://courses/example_par3.json"

## Strokes to play before the capture; more than the hole needs plays it out.
@export var strokes: int = 9


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = COURSE_PATH
	add_child(main)
	main.mode_button.pressed.emit()
	var sc := main.swing_control
	main.shot_view.set_process(false)
	for i in strokes:
		if sc.is_finished():
			break
		ScriptedRound.swing(sc, ScriptedRound.plan(sc))
		while main.shot_view.playing:
			main.shot_view.advance(0.25)
	main.shot_view.set_process(true)
	print("round shot: %d strokes, holed %s, total %d" % [sc.score.strokes, sc.score.holed,
			sc.score.total()])
