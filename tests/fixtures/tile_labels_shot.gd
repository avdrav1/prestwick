class_name TileLabelsShot
extends Node2D
## Screenshot fixture for E3-S55: courses/example_par3.json in the main scene, in Play (the
## label-free tile sheets) or Build (the labelled ones, and the palette's labelled icons), at
## `zoom_level`. Run: scripts/screenshot.sh tests/fixtures/tile_labels_shot_play_0_5x.tscn,
## tile_labels_shot_play_1x.tscn or tile_labels_shot_build_1x.tscn.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COURSE_PATH: String = "res://courses/example_par3.json"

@export var play: bool = true
## The camera zoom (one of CameraTuning.zoom_levels).
@export var zoom_level: float = 1.0


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = COURSE_PATH
	add_child(main)
	if play:
		main.mode_button.pressed.emit()
	main.camera.set_zoom_level(zoom_level)
	# The player's own zoom (as a zoom key sets it), so Play's aim fit does not step it out.
	main.camera.step_zoom(0)
	if play:
		main.camera.centre_on(main._ball_world())
	main.camera.position = main.camera._clamped(main.camera.goal())
	print("tile labels shot: play %s, play_art %s, zoom %s" % [play, main.course_view.play_art, zoom_level])
