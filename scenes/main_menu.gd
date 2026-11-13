class_name MainMenu
extends Control
## The main menu (E5-S5): Back to the course, New course, Famous courses (E15-S1), Load game, Save game, Import course,
## Export course, Sound settings (E5-S4: Main opens the AudioPanel and comes back here when it
## closes), Goals (E10-S1, on a game with the goal checklist), Quit, over a dimmed course. Main opens it at start when it is the running
## scene and on Esc (`menu`); Esc on a page goes back to the menu, on the menu closes it. Every
## control takes keyboard focus (arrows or Tab move it, Enter or Space presses) and the focused
## one draws a thick outline. The menu only asks: Main does each action (its signals) and the
## menu closes so the notice shows.
##
## Export course: a name and an author (a file carries both; the name is required), the course's
## par and yardage (CourseExport.summary), and Export, which writes CourseExport.path_for(name).
## Import course: every .json file in CourseExport.FOLDER (its full path shown, with Open folder
## to drop a friend's file in), each a button labelled with its name, author, par and yardage,
## or with why it cannot be read; pressing one imports it (Main.import_course, which refuses a
## bad file with its reason and leaves the game alone).
##
## E15-S1 (D70): Famous courses opens a page listing the courses built into the game
## (FamousCourses, res://courses/, the latest version each update brings): each a button with its
## name, a style line, its holes, par and yardage, and under it "A newer version of Cliffside is
## available" when a save is of an older version of it. Pressing one asks Main for a new game on
## it (`famous_requested`), which asks first when a game is under way.
##
## E8-S4: Load game opens the Load page: the manual save and each autosave (GameSave.list_saves),
## each a button with its day, balance and real date and time, or why it cannot be read; pressing
## one asks Main to load it (`load_requested`), which asks before it replaces the game. Save game
## asks Main to save, which asks before it writes over the saved game.

signal new_course_requested
## E15-S1: the famous course picked on the Famous courses page (FamousCourses id).
signal famous_requested(id: String)
## E8-S4: the save picked on the Load page.
signal load_requested(path: String)
signal save_requested
signal import_requested(path: String)
signal export_requested(course_name: String, author: String)
signal quit_requested
## E5-S4: Sound settings.
signal sound_requested
## E10-S1: Goals, shown while the game has the New course goal checklist (set_goals).
signal goals_requested

## The same key as LandPanel's buy_cancel (Esc): a pending buy takes it first.
const MENU_ACTION: StringName = &"menu"
## The longest name or author a file carries, in characters.
const TEXT_MAX: int = 40
## The panel's width, px.
const PANEL_WIDTH: float = 520.0
## The import list's height, px, before it scrolls.
const LIST_HEIGHT: float = 260.0
## The dim over the course while the menu is open.
const BACKDROP := Color(0.0, 0.0, 0.0, 0.55)
## The focused control's outline: thick and bright, so it reads over any button state.
const FOCUS_COLOR := Color(1.0, 0.84, 0.3)
const FOCUS_WIDTH: int = 3
## The buttons' places on the menu page (show_main's index): E15-S1's Famous courses third.
const FAMOUS_INDEX: int = 2
## E8-S4: the Load game and Save game buttons' places on the menu page.
const LOAD_INDEX: int = 3
const SAVE_INDEX: int = 4
const IMPORT_INDEX: int = 5
const EXPORT_INDEX: int = 6
## The Sound settings button's place.
const SOUND_INDEX: int = 7

## E8-S4: where the Load page reads the saves (Main sets them to its own).
var save_path: String = GameSave.PATH
var autosave_folder: String = GameSave.AUTOSAVE_FOLDER
var autosave_slots: int = 3

var main_page: VBoxContainer
var export_page: VBoxContainer
var import_page: VBoxContainer
var name_edit: LineEdit
var author_edit: LineEdit
var summary_label: Label
var export_button: Button
var export_back_button: Button
var folder_label: Label
var import_list: VBoxContainer
var import_back_button: Button
var empty_label: Label
var load_page: VBoxContainer
var load_list: VBoxContainer
var load_back_button: Button
var load_empty_label: Label
## E10-S1: Goals, hidden unless the game has the goal checklist.
var goals_button: Button
## E15-S1: the Famous courses page.
var famous_page: VBoxContainer
var famous_list: VBoxContainer
var famous_back_button: Button

var _course: CourseData
## E15-S1: each famous course's summary line, read from res://courses/ once (the files do not
## change while the game runs).
var _famous_lines: Dictionary = {}
var _main_buttons: Array[Button] = []
var _focus_style: StyleBoxFlat


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_focus_style = StyleBoxFlat.new()
	_focus_style.draw_center = false
	_focus_style.border_color = FOCUS_COLOR
	_focus_style.set_border_width_all(FOCUS_WIDTH)
	_focus_style.set_corner_radius_all(3)
	_focus_style.set_expand_margin_all(2)
	var dim := ColorRect.new()
	dim.color = BACKDROP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var pages := VBoxContainer.new()
	margin.add_child(pages)
	var title := Label.new()
	title.text = "Prestwick"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	pages.add_child(title)
	_build_main(pages)
	_build_export(pages)
	_build_import(pages)
	_build_load(pages)
	_build_famous(pages)
	hide()


func _build_main(parent: Control) -> void:
	main_page = VBoxContainer.new()
	main_page.add_theme_constant_override("separation", 6)
	parent.add_child(main_page)
	var close_button := _button(main_page, "Back to the course", close)
	close_button.tooltip_text = "Esc"
	_button(main_page, "New course", func() -> void: _do(new_course_requested))
	var famous := _button(main_page, "Famous courses", show_famous)
	famous.tooltip_text = "The courses built into the game, always the latest version"
	_button(main_page, "Load game", show_load)
	_button(main_page, "Save game", func() -> void: _do(save_requested))
	_button(main_page, "Import course", show_import)
	_button(main_page, "Export course", show_export)
	# Asks before it closes, so Main sees the sound panel open from the menu as the menu hides
	# and keeps the guests' day paused (Main._hold_day_for_menu).
	_button(main_page, "Sound settings", func() -> void:
		sound_requested.emit()
		close())
	goals_button = _button(main_page, "Goals", func() -> void: _do(goals_requested))
	goals_button.tooltip_text = "Open the goal checklist: what to do next and how"
	goals_button.visible = false
	_button(main_page, "Quit", func() -> void: _do(quit_requested))
	for c: Node in main_page.get_children():
		_main_buttons.append(c as Button)


func _build_export(parent: Control) -> void:
	export_page = VBoxContainer.new()
	parent.add_child(export_page)
	var head := Label.new()
	head.text = "Export course"
	export_page.add_child(head)
	name_edit = _field(export_page, "Course name")
	author_edit = _field(export_page, "Author")
	summary_label = Label.new()
	summary_label.name = "Summary"
	export_page.add_child(summary_label)
	var where := Label.new()
	where.text = "Writes one file to send to a friend."
	export_page.add_child(where)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	export_page.add_child(row)
	export_back_button = _button(row, "Back", show_main.bind(EXPORT_INDEX))
	export_button = _button(row, "Export", _export)
	name_edit.text_changed.connect(func(_t: String) -> void: refresh_export())
	author_edit.text_changed.connect(func(_t: String) -> void: refresh_export())
	# Enter moves on: name to author, author to Export.
	name_edit.text_submitted.connect(func(_t: String) -> void: author_edit.grab_focus())
	author_edit.text_submitted.connect(func(_t: String) -> void:
		if not export_button.disabled:
			_export())


func _build_import(parent: Control) -> void:
	import_page = VBoxContainer.new()
	parent.add_child(import_page)
	var head := Label.new()
	head.text = "Import course"
	import_page.add_child(head)
	folder_label = Label.new()
	folder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	folder_label.custom_minimum_size.x = PANEL_WIDTH - 32.0
	import_page.add_child(folder_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = LIST_HEIGHT
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	import_page.add_child(scroll)
	import_list = VBoxContainer.new()
	import_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(import_list)
	empty_label = Label.new()
	empty_label.text = "No course files yet. Put a friend's .json course file in that folder."
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.custom_minimum_size.x = PANEL_WIDTH - 48.0
	import_list.add_child(empty_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	import_page.add_child(row)
	_button(row, "Open folder", _open_folder)
	import_back_button = _button(row, "Back", show_main.bind(IMPORT_INDEX))


func _build_load(parent: Control) -> void:
	load_page = VBoxContainer.new()
	parent.add_child(load_page)
	var head := Label.new()
	head.text = "Load game"
	load_page.add_child(head)
	var note := Label.new()
	note.text = "Your saved game, and the game as it stood each of the last mornings."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = PANEL_WIDTH - 32.0
	load_page.add_child(note)
	load_list = VBoxContainer.new()
	load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_page.add_child(load_list)
	load_empty_label = Label.new()
	load_empty_label.text = "No saved games yet. F5 saves; the game saves itself each morning."
	load_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	load_empty_label.custom_minimum_size.x = PANEL_WIDTH - 48.0
	load_list.add_child(load_empty_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	load_page.add_child(row)
	load_back_button = _button(row, "Back", show_main.bind(LOAD_INDEX))


## E15-S1: the Famous courses page: a note, the list (show_famous fills it) and Back.
func _build_famous(parent: Control) -> void:
	famous_page = VBoxContainer.new()
	parent.add_child(famous_page)
	var head := Label.new()
	head.text = "Famous courses"
	famous_page.add_child(head)
	var note := Label.new()
	note.text = "Built into the game: each update brings the latest version. Picking one starts a new game on it."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = PANEL_WIDTH - 32.0
	famous_page.add_child(note)
	famous_list = VBoxContainer.new()
	famous_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	famous_list.add_theme_constant_override("separation", 6)
	famous_page.add_child(famous_list)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	famous_page.add_child(row)
	famous_back_button = _button(row, "Back", show_main.bind(FAMOUS_INDEX))


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("focus", _focus_style)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _field(parent: Control, label_text: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 130.0
	row.add_child(l)
	var e := LineEdit.new()
	e.max_length = TEXT_MAX
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_stylebox_override("focus", _focus_style)
	row.add_child(e)
	return e


## E10-S1: shows Goals while the game has the goal checklist.
func set_goals(on: bool) -> void:
	goals_button.visible = on


## The menu's own buttons, top to bottom (Goals among them, shown or not).
func main_buttons() -> Array[Button]:
	return _main_buttons.duplicate()


## The Import page's file buttons, in list order.
func import_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c: Node in import_list.get_children():
		if c is Button:
			out.append(c as Button)
	return out


## E15-S1: the Famous courses page's course buttons, in list order (FamousCourses.COURSES).
func famous_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c: Node in famous_list.get_children():
		if c is Button:
			out.append(c as Button)
	return out


## E15-S1: the Famous courses page's newer-version notes, by course id (only those shown).
func famous_notes() -> Dictionary:
	var out := {}
	for c: Node in famous_list.get_children():
		if c is Label and c.has_meta(&"course_id"):
			out[c.get_meta(&"course_id")] = (c as Label).text
	return out


## E8-S4: the Load page's save buttons, in list order (the manual save, then the autosaves,
## newest first).
func load_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c: Node in load_list.get_children():
		if c is Button:
			out.append(c as Button)
	return out


## Opens the menu on its first page for `course` (the Export page names and measures it).
func open(course: CourseData) -> void:
	_course = course
	show()
	show_main(0)


func close() -> void:
	hide()


## Shows `page` alone of the menu's pages.
func _show_page(page: Control) -> void:
	for p: Control in [main_page, export_page, import_page, load_page, famous_page]:
		p.visible = p == page


## The menu page, focus on its button `index`.
func show_main(index: int = 0) -> void:
	_show_page(main_page)
	_main_buttons[clampi(index, 0, _main_buttons.size() - 1)].grab_focus()


## E15-S1: the Famous courses page: each built-in course, the latest version, with a note under
## it when a save (GameSave.list_saves, newest first) is of an older version; focus on the first.
func show_famous() -> void:
	_show_page(famous_page)
	for c: Node in famous_list.get_children():
		famous_list.remove_child(c)
		c.queue_free()
	var notes := {}
	for e: GameSave.Entry in GameSave.list_saves(save_path, autosave_folder, autosave_slots):
		var note := e.newer_note()
		if note.is_empty() or notes.has(e.state.course.course_id):
			continue
		var kind: String = "Your autosave" if e.is_autosave else "Your saved game"
		notes[e.state.course.course_id] = "%s %s from Day %d keeps the version it was saved with." \
				% [note, kind, e.state.day]
	for id: String in FamousCourses.ids():
		var b := _button(famous_list, famous_text(id), _famous.bind(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = b.text
		if notes.has(id):
			var l := Label.new()
			l.text = notes[id]
			l.set_meta(&"course_id", id)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = PANEL_WIDTH - 48.0
			l.add_theme_color_override("font_color", FOCUS_COLOR)
			famous_list.add_child(l)
	var picks := famous_buttons()
	if picks.is_empty():
		famous_back_button.grab_focus()
	else:
		picks[0].grab_focus()


## E15-S1: a famous course's button text: "Cliffside: 9 holes, par 36, 3,353 yd" and its style
## line under it; the name and why when its file does not load.
func famous_text(id: String) -> String:
	if not _famous_lines.has(id):
		var errors: Array[String] = []
		var c := FamousCourses.load_course(id, errors)
		_famous_lines[id] = CourseExport.summary(c) if c != null else \
				"can't be read (%s)" % (errors[0] if not errors.is_empty() else "cannot read it")
	return "%s: %s\n%s" % [FamousCourses.display_name(id), _famous_lines[id],
			FamousCourses.spec(id).get("style", "")]


## The Export page: the course's name and author to edit, its par and yardage.
func show_export() -> void:
	_show_page(export_page)
	name_edit.text = _course.course_name if _course != null else ""
	author_edit.text = _course.author if _course != null else ""
	summary_label.text = CourseExport.summary(_course) if _course != null else ""
	refresh_export()
	name_edit.grab_focus()
	name_edit.caret_column = name_edit.text.length()


## Export takes a name: a course file carries one.
func refresh_export() -> void:
	export_button.disabled = name_edit.text.strip_edges().is_empty()
	export_button.tooltip_text = "Give the course a name first." if export_button.disabled else ""


## The Import page: the course folder's files, read now.
func show_import() -> void:
	_show_page(import_page)
	folder_label.text = "Course files in %s" % ProjectSettings.globalize_path(CourseExport.FOLDER)
	for b: Button in import_buttons():
		import_list.remove_child(b)
		b.queue_free()
	var entries := CourseExport.list_folder()
	empty_label.visible = entries.is_empty()
	for e: CourseExport.Entry in entries:
		var b := _button(import_list, e.label(), _import.bind(e.path))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = e.label()
	var picks := import_buttons()
	if picks.is_empty():
		import_back_button.grab_focus()
	else:
		picks[0].grab_focus()


## E8-S4: the Load page: the saves as they are on disk now, focus on the first.
func show_load() -> void:
	_show_page(load_page)
	for b: Button in load_buttons():
		load_list.remove_child(b)
		b.queue_free()
	var entries := GameSave.list_saves(save_path, autosave_folder, autosave_slots)
	load_empty_label.visible = entries.is_empty()
	for e: GameSave.Entry in entries:
		# E15-S1: a save of an older famous course says so on a line of its own.
		var note := e.newer_note()
		var text := e.label() if note.is_empty() else "%s\n%s" % [e.label(), note]
		var b := _button(load_list, text, _load.bind(e.path))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = text
	var picks := load_buttons()
	if picks.is_empty():
		load_back_button.grab_focus()
	else:
		picks[0].grab_focus()


## Esc before the focused control sees it: a LineEdit would take it to stop editing.
func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(MENU_ACTION):
		return
	if main_page.visible:
		close()
	elif export_page.visible:
		show_main(EXPORT_INDEX)
	elif load_page.visible:
		show_main(LOAD_INDEX)
	elif famous_page.visible:
		show_main(FAMOUS_INDEX)
	else:
		show_main(IMPORT_INDEX)
	get_viewport().set_input_as_handled()


## Nothing behind the menu takes a key while it is open (the map's keys, F5, Tab).
func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey:
		get_viewport().set_input_as_handled()


func _do(sig: Signal) -> void:
	close()
	sig.emit()


func _export() -> void:
	var n := name_edit.text.strip_edges()
	if n.is_empty():
		return
	close()
	export_requested.emit(n, author_edit.text.strip_edges())


func _import(path: String) -> void:
	close()
	import_requested.emit(path)


func _load(path: String) -> void:
	close()
	load_requested.emit(path)


func _famous(id: String) -> void:
	close()
	famous_requested.emit(id)


func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(CourseExport.FOLDER)
	OS.shell_open(ProjectSettings.globalize_path(CourseExport.FOLDER))
