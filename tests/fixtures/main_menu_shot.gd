class_name MainMenuShot
extends Node2D
## Screenshot fixture for E5-S5: the main menu over PlaytestNine, one page a scene
## (main_menu_shot*.tscn): the menu with Import course focused, the Export page, the Import
## page listing an exported course and a file of a newer format, the notice an import of
## tests/fixtures/course_v1_short_par4.json gives (both holes closed, each with its reason), and
## the notice a refused (newer format) file gives. E15-S1 (D70): the Famous courses page
## (main_menu_shot_famous.tscn), and with a save on an older Cliffside the note on it
## (main_menu_shot_famous_newer.tscn) and on the Load page (main_menu_shot_load_newer.tscn).
## E19-S3: on the Famous courses page FAMOUS_FOCUS=last puts the focus on the last course (the
## list scrolls to it), FAMOUS_COUNT=12 lists twelve (the seven, then five again) and
## FAMOUS_PLAY=1 opens it over Play (its taller toolbar).
##   FAMOUS_FOCUS=last scripts/screenshot.sh tests/fixtures/main_menu_shot_famous.tscn
## Run: scripts/screenshot.sh tests/fixtures/main_menu_shot.tscn

enum Page { MENU, EXPORT, IMPORT, IMPORT_NOTICE, REFUSED_NOTICE, FAMOUS, FAMOUS_NEWER, LOAD_NEWER }

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
			_main.main_menu.main_buttons()[MainMenu.IMPORT_INDEX].grab_focus()
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
		Page.FAMOUS:
			if OS.get_environment("FAMOUS_PLAY") == "1":
				_main.set_mode(Main.Mode.PLAY)
			_main.open_menu()
			var ids := FamousCourses.ids()
			if OS.get_environment("FAMOUS_COUNT") == "12":
				for i: int in 5:
					ids.append(FamousCourses.ids()[i])
			_main.main_menu.show_famous(ids)
			if OS.get_environment("FAMOUS_FOCUS") == "last":
				# Once the page is laid out, as a key press would, so the list follows it.
				await get_tree().process_frame
				await get_tree().process_frame
				_main.main_menu.famous_buttons()[-1].grab_focus()
		Page.FAMOUS_NEWER, Page.LOAD_NEWER:
			_save_older_cliffside()
			_main.open_menu()
			if page == Page.FAMOUS_NEWER:
				_main.main_menu.show_famous()
				await get_tree().process_frame
				await get_tree().process_frame
				_main.main_menu.famous_button("cliffside").grab_focus()
			else:
				_main.main_menu.show_load()


## A saved game from Day 4 on the version of Cliffside before the shipped one.
func _save_older_cliffside() -> void:
	_main.start_famous("cliffside")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FamousCourses.path("cliffside")))
	data["course_version"] = FamousCourses.latest_version("cliffside") - 1
	var s := _main.save_state()
	s.course = CourseSave.from_dict(data)
	s.day = 4
	GameSave.save_file(s, _main.save_path)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
