class_name SwingExplainShot
extends Node2D
## Screenshot fixture for E10-S3: the main scene in Play on courses/example_par3.json with the
## 7-iron. `stage` "bar": before a swing, the hint already seen, the bar's yard labels and
## the zone's label; "hint": before the first swing, the bar's yard labels and the practice hint
## (read from a fresh settings file, so it shows whatever the player's own settings say);
## "power": the power being set at 60%, the readout and the live landing marker over the faded
## 100% marker. Run: scripts/screenshot.sh tests/fixtures/swing_explain_hint.tscn (or _bar, _power).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COURSE_PATH: String = "res://courses/example_par3.json"
const HINT_PATH: String = "user://swing_explain_shot_hints.cfg"

@export var stage: String = "hint"


func _ready() -> void:
	var main := MAIN_SCENE.instantiate() as Main
	main.course_path = COURSE_PATH
	add_child(main)
	main.set_mode(Main.Mode.PLAY)
	var sc := main.swing_control
	sc.set_process(false)
	sc.select_club(sc.model.clubs.club("7i"))
	sc._refresh_aim()
	if FileAccess.file_exists(HINT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HINT_PATH))
	main.swing_panel.load_hint(HINT_PATH)
	if stage != "hint":
		main.swing_panel.hint_panel.visible = false
	if stage == "power":
		sc.press()
		sc.advance(0.6 / sc.swing.rate())
	main.swing_panel.refresh()
	main.camera.set_zoom_level(0.5)
