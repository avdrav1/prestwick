class_name SaveNotice
extends PanelContainer
## The one notice a save or a load gives (E4-S7): what was saved and any hole left out, what was
## loaded and every hole the validator closed with its one-line reason (D35, D47), or why a load
## failed and that the game was left alone. Hidden until shown; OK (or the next save or load)
## dismisses it. Centred at the top of the screen, over the map, only while shown.

## The text's width, px: centred at 1280 x 720 it ends left of the hole panel (340 px from the
## right edge).
const TEXT_WIDTH: float = 480.0

var label: Label
var ok_button: Button


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	label = Label.new()
	label.name = "Text"
	# One width whatever the reasons, wrapping, so it stays clear of the hole panel at 1280 px.
	label.custom_minimum_size.x = TEXT_WIDTH
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	ok_button = Button.new()
	ok_button.name = "OK"
	ok_button.text = "OK"
	ok_button.focus_mode = Control.FOCUS_NONE
	ok_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok_button.pressed.connect(hide)
	box.add_child(ok_button)


## Shows `lines`, one a row.
func show_lines(lines: PackedStringArray) -> void:
	label.text = "\n".join(lines)
	show()
	reset_size()
	size = get_combined_minimum_size()
	position.x = (get_viewport_rect().size.x - size.x) * 0.5


## The lines of the notice a save gives: "Saved day 3." or why it failed, then one line per hole
## left out of the file because its tee or cup is not placed (CourseSave drops it, E2-S12).
static func save_lines(err: Error, day: int, dropped: Array[int], c: CourseData) -> PackedStringArray:
	var out := PackedStringArray()
	if err != OK:
		out.append("Could not save: %s." % error_string(err))
		return out
	out.append("Saved day %d (F9 loads it)." % day)
	for n: int in dropped:
		out.append("Hole %d not saved: %s." % [n, _missing(c, n)])
	return out


## The lines of the notice a load gives: "Loaded day 3." then every hole the builder closed on
## load (CourseBuilder.closed_on_load); or, when it failed, why and that nothing changed.
static func load_lines(errors: Array[String], day: int, closed: Array[String]) -> PackedStringArray:
	var out := PackedStringArray()
	if not errors.is_empty():
		out.append("Could not load the saved game: %s." % errors[0])
		if errors.size() > 1:
			out.append("(and %d more)" % (errors.size() - 1))
		out.append("Your game is unchanged.")
		return out
	out.append("Loaded day %d." % day)
	out.append_array(closed)
	return out


## E5-S5: the lines of the notice an import gives: "Imported "Name" by Author: 9 holes, par 36,
## 3,240 yd." then every hole the builder closed on import with its reason (D35, as a load);
## or, when the file was refused, which file, why, and that nothing changed.
static func import_lines(path: String, errors: Array[String], c: CourseData,
		closed: Array[String]) -> PackedStringArray:
	var out := PackedStringArray()
	if not errors.is_empty() or c == null:
		var why: String = errors[0] if not errors.is_empty() else "cannot read it"
		out.append("Could not import %s: %s." % [path.get_file(), why])
		if errors.size() > 1:
			out.append("(and %d more)" % (errors.size() - 1))
		out.append("Your game is unchanged.")
		return out
	out.append("Imported %s: %s." % [CourseExport.title(c, path), CourseExport.summary(c)])
	out.append_array(closed)
	return out


## E5-S5: the lines of the notice an export gives: what was exported and where (the full path,
## to find the file and send it), then one line per half-placed hole the file leaves out.
static func export_lines(err: Error, c: CourseData, path: String,
		dropped: Array[int]) -> PackedStringArray:
	var out := PackedStringArray()
	if err != OK:
		out.append("Could not export: %s." % error_string(err))
		return out
	out.append("Exported %s: %s." % [CourseExport.title(c, path), CourseExport.summary(c)])
	out.append("File: %s" % ProjectSettings.globalize_path(path))
	for n: int in dropped:
		out.append("Hole %d not exported: %s." % [n, _missing(c, n)])
	return out


static func _missing(c: CourseData, number: int) -> String:
	for h: HoleData in c.holes:
		if h.number != number:
			continue
		var tee := c.in_bounds(h.tee.x, h.tee.y)
		var cup := c.in_bounds(h.cup.x, h.cup.y)
		if tee and not cup:
			return "it has no cup yet"
		if cup and not tee:
			return "it has no tee yet"
	return "its tee or cup is not placed"
