class_name MainMenuShot
extends Node2D
## Screenshot fixture for E5-S5: the main menu over PlaytestNine, one page a scene
## (main_menu_shot*.tscn): the menu with Import course focused, the Export page, the Import
## page listing an exported course and a file of a newer format, the notice an import of
## tests/fixtures/course_v1_short_par4.json gives (both holes closed, each with its reason), and
## the notice a refused (newer format) file gives. E13-S5: the Import page on a first start, the
## example courses copied in as the game copies them (main_menu_shot_import_examples.tscn).
## Run: scripts/screenshot.sh tests/fixtures/main_menu_shot.tscn

enum Page { MENU, EXPORT, IMPORT, IMPORT_NOTICE, REFUSED_NOTICE, EXAMPLES }

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

@export var page: Page = Page.MENU

var _main: Main


func _ready() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	_main.course_path = "res://courses/playtest_nine.json"
	add_child(_main)
	match page:
		Page.MENU:
			_main.open_menu()
			_main.main_menu.main_buttons()[4].grab_focus()
		Page.EXPORT:
			_main.open_menu()
			_main.main_menu.show_export()
			_main.main_menu.author_edit.text = "Avniel"
			_main.main_menu.name_edit.text = "Playtest Nine"
			_main.main_menu.refresh_export()
		Page.IMPORT:
			CourseExport.write_file(_main.course, CourseExport.path_for("Playtest Nine"))
			_write(CourseExport.FOLDER.path_join("from_a_friend.json"),
					JSON.stringify({"version": CourseData.FORMAT_VERSION + 1}))
			_main.open_menu()
			_main.main_menu.show_import()
		Page.IMPORT_NOTICE:
			_main.import_course("res://tests/fixtures/course_v1_short_par4.json")
		Page.REFUSED_NOTICE:
			_write("user://future.json", JSON.stringify({"version": CourseData.FORMAT_VERSION + 1}))
			_main.import_course("user://future.json")
		Page.EXAMPLES:
			CourseExport.install_examples()
			_main.open_menu()
			_main.main_menu.show_import()


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
