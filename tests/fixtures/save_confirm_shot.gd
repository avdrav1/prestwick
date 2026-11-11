class_name SaveConfirmShot
extends Node2D
## Screenshot fixture for E8-S4: over PlaytestNine, F5's question over a saved game, F9's question
## before a load, and the menu's Load page listing the manual save, two autosaves and a broken
## one; one page a scene (save_confirm_shot*.tscn). The saves go to a folder of their own, never
## the player's.
## Run: scripts/screenshot.sh tests/fixtures/save_confirm_shot.tscn

enum Page { SAVE_QUESTION, LOAD_QUESTION, LOAD_PAGE }

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FOLDER := "user://e8_s4_shot/"

@export var page: Page = Page.SAVE_QUESTION

var _main: Main


func _ready() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://courses/playtest_nine.json"
	add_child(_main)
	DirAccess.make_dir_recursive_absolute(FOLDER)
	_main.save_path = FOLDER.path_join("save.json")
	_main.autosave_folder = FOLDER
	var now: int = int(Time.get_unix_time_from_system())
	var s := _main.save_state()
	s.day = 4
	s.saved_at = now - 3600
	GameSave.save_file(s, _main.save_path)
	match page:
		Page.SAVE_QUESTION:
			_main.request_save()
		Page.LOAD_QUESTION:
			_main.request_load()
		Page.LOAD_PAGE:
			for n: int in range(1, 4):
				if FileAccess.file_exists(GameSave.autosave_path(n, FOLDER)):
					DirAccess.remove_absolute(GameSave.autosave_path(n, FOLDER))
			for day: int in [6, 7]:
				var a := _main.save_state()
				a.day = day
				a.money += 450 * (day - 5)
				a.saved_at = now - (8 - day) * 540
				GameSave.autosave_file(a, FOLDER, 3)
			var f := FileAccess.open(GameSave.autosave_path(3, FOLDER), FileAccess.WRITE)
			f.store_string("{\"save_version\": 1, \"course\": {")
			f.close()
			_main.open_menu()
			_main.main_menu.show_load()
