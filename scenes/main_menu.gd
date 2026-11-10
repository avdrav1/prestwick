class_name MainMenu
extends Control
## The main menu (E5-S5): Back to the course, New course, Load game, Save game, Import course,
## Export course, Quit, over a dimmed course. Main opens it at start when it is the running
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

signal new_course_requested
signal load_requested
signal save_requested
signal import_requested(path: String)
signal export_requested(course_name: String, author: String)
signal quit_requested

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

var _course: CourseData
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
	hide()


func _build_main(parent: Control) -> void:
	main_page = VBoxContainer.new()
	main_page.add_theme_constant_override("separation", 6)
	parent.add_child(main_page)
	var close_button := _button(main_page, "Back to the course", close)
	close_button.tooltip_text = "Esc"
	_button(main_page, "New course", func() -> void: _do(new_course_requested))
	_button(main_page, "Load game", func() -> void: _do(load_requested))
	_button(main_page, "Save game", func() -> void: _do(save_requested))
	_button(main_page, "Import course", show_import)
	_button(main_page, "Export course", show_export)
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
	export_back_button = _button(row, "Back", show_main.bind(5))
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
	import_back_button = _button(row, "Back", show_main.bind(4))


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


## The menu's own buttons, top to bottom.
func main_buttons() -> Array[Button]:
	return _main_buttons.duplicate()


## The Import page's file buttons, in list order.
func import_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c: Node in import_list.get_children():
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


## The menu page, focus on its button `index`.
func show_main(index: int = 0) -> void:
	main_page.show()
	export_page.hide()
	import_page.hide()
	_main_buttons[clampi(index, 0, _main_buttons.size() - 1)].grab_focus()


## The Export page: the course's name and author to edit, its par and yardage.
func show_export() -> void:
	main_page.hide()
	import_page.hide()
	export_page.show()
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
	main_page.hide()
	export_page.hide()
	import_page.show()
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


## Esc before the focused control sees it: a LineEdit would take it to stop editing.
func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(MENU_ACTION):
		return
	if main_page.visible:
		close()
	elif export_page.visible:
		show_main(5)
	else:
		show_main(4)
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


func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(CourseExport.FOLDER)
	OS.shell_open(ProjectSettings.globalize_path(CourseExport.FOLDER))
