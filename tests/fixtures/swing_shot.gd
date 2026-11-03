class_name SwingShot
extends Node2D
## Screenshot fixture for E2-S7: the main scene in Play on courses/example_par3.json, the
## 7-iron picked, the aim turned a little off the pin, and a swing frozen mid-bar (power
## locked at 85%, the bar on its way back), so the aim line, marker and swing bar all show.
## Run: scripts/screenshot.sh tests/fixtures/swing_shot.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COURSE_PATH: String = "res://courses/example_par3.json"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = COURSE_PATH
	add_child(main)
	main.set_mode(Main.Mode.PLAY)
	var sc := main.swing_control
	sc.set_process(false)
	sc.select_club(sc.model.clubs.club("7i"))
	sc.rotate_aim(-3.0)
	sc._refresh_aim()
	sc.press()
	sc.advance(0.85 / sc.swing.rate())
	sc.press()
	sc.advance(0.6 / sc.swing.rate())
	main.swing_panel.refresh()
	main.camera.set_zoom_index(0)
