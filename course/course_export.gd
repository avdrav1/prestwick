class_name CourseExport
extends RefCounted
## Course files friends swap (E5-S5, docs/design.md Export and import): one course JSON file in
## the course format (CourseSave, version 3), written to CourseExport.FOLDER by the main menu's
## Export course and read back by its Import course. The file carries the course's name and
## author; par and yardage are not fields of the format, so they are derived from the holes
## (summary: each whole hole's par, and its rule 4 yardage along the line of play, D47). D60
## moved the thumbnail to the Icebox: the format's "thumbnail" stays an empty string.
##
## Reading checks what kind of file it is before CourseSave parses it, so the reason is one a
## player can act on: not JSON or not an object ("not a course file"), a saved game ("use Load
## game"), no version, a version newer than this game reads, or a version below 1. Writing goes
## through CourseSave.to_data, so only course/save.gd and course/builder.gd write CourseData; this
## class writes files, never a course.
##
## 2026-11-10 (the user): an exported file starts its importer on the starting balance
## (LandPrices.land_budget, $5,000 in data/land.json, D57), not the exporter's money, so the file
## is fair to share; the land owned is kept (the holes stand on it), and a sandbox course's
## unlimited money (null) stays unlimited. The file itself holds the reset balance; the
## exporter's own course keeps its money.

## Where exports go and Import course looks, under the user data folder.
const FOLDER: String = "user://courses"
## The longest file name stem path_for makes, in characters.
const STEM_MAX: int = 40
## E13-S5: the example courses the game ships (docs/courses.md), in EXAMPLES_FROM (the export
## presets' include_filter packs courses/*.json). install_examples copies them into FOLDER at
## start, so the Import page lists them with no step of the player's.
const EXAMPLES: PackedStringArray = ["harbor_links.json", "old_grey_links.json",
		"pine_ridge.json", "cliffside.json"]
const EXAMPLES_FROM: String = "res://courses"


## A file in the course folder: the course it holds, or why it cannot be read.
class Entry:
	extends RefCounted
	var path: String = ""
	## Null when the file cannot be read; `error` then says why.
	var course: CourseData = null
	var error: String = ""

	## The line the Import page shows: "\"Name\" by Author: 9 holes, par 36, 3,240 yd", or the
	## file's name and why it cannot be read.
	func label() -> String:
		if course == null:
			return "%s: %s" % [path.get_file(), error]
		return "%s: %s" % [CourseExport.title(course, path), CourseExport.summary(course)]


## Writes `course` to `path` as course JSON (export_json: the starting balance, not the
## course's), making the folder if need be; the new file replaces any there only once it is
## written whole (a temp file renamed over it). Half-placed holes are left out
## (CourseSave.to_data) and their numbers appended to `dropped`. `prices` gives the starting
## balance (data/land.json when null).
static func write_file(course: CourseData, path: String, dropped: Array[int] = [],
		prices: LandPrices = null) -> Error:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return made
	var text := export_json(course, dropped, prices)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return DirAccess.rename_absolute(tmp, path)


## The text an export writes: the course format, with the balance reset to the starting balance
## (`prices.land_budget`, data/land.json when null) unless the course's money is unlimited
## (null, which stays null). The land owned is kept. `course` is not changed.
static func export_json(course: CourseData, dropped: Array[int] = [],
		prices: LandPrices = null) -> String:
	var data := CourseSave.to_data(course, dropped)
	if not course.has_unlimited_budget():
		var lp := prices if prices != null else LandPrices.load_default()
		data["land_budget"] = maxi(lp.land_budget, 0)
	return CourseSave.stringify(data)


## Reads the course file at `path`. Null, with the reason in `errors`, when it is missing or is
## not a course file this game reads (read_text).
static func read_file(path: String, errors: Array[String] = []) -> CourseData:
	if not FileAccess.file_exists(path):
		errors.append("file not found")
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		errors.append("cannot read it (%s)" % error_string(FileAccess.get_open_error()))
		return null
	return read_text(text, errors)


## Parses course file text of version 1 to CourseData.FORMAT_VERSION. Null, with the reasons in
## `errors`, for anything else; the first reason says what kind of file it is.
static func read_text(text: String, errors: Array[String] = []) -> CourseData:
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("not a course file (JSON line %d: %s)" % [json.get_error_line(),
				json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("not a course file (not a JSON object)")
		return null
	var data: Dictionary = json.data
	if data.has("save_version"):
		errors.append("a saved game, not a course file (Load game opens it)")
		return null
	if not data.has("version"):
		errors.append("not a course file (it has no version)")
		return null
	var start := errors.size()
	var version := CourseData.read_int(data, "version", errors)
	if errors.size() > start:
		return null
	if version > CourseData.FORMAT_VERSION:
		errors.append("made by a newer Prestwick (course format %d; this game reads 1 to %d)"
				% [version, CourseData.FORMAT_VERSION])
		return null
	if version < 1:
		errors.append("unknown course format version %d" % version)
		return null
	return CourseSave.from_dict(data, errors)


## E13-S5: copies each of `names` from `from` (res://, read-only in an export) into `to`,
## making the folder if need be, unless `to` already has a file of that name (a player's own
## copy, edited or not, is never written over). Each is written whole before it takes its name
## (a temp file renamed), and copied byte for byte. Returns the paths written; a file missing
## from `from` or one that cannot be written is skipped.
static func install_examples(to: String = FOLDER, from: String = EXAMPLES_FROM,
		names: PackedStringArray = EXAMPLES) -> Array[String]:
	var out: Array[String] = []
	for f: String in names:
		var dest := to.path_join(f)
		var src := from.path_join(f)
		if FileAccess.file_exists(dest) or not FileAccess.file_exists(src):
			continue
		var bytes := FileAccess.get_file_as_bytes(src)
		if bytes.is_empty():
			continue
		if not DirAccess.dir_exists_absolute(to) and DirAccess.make_dir_recursive_absolute(to) != OK:
			return out
		var tmp := dest + ".tmp"
		var w := FileAccess.open(tmp, FileAccess.WRITE)
		if w == null:
			continue
		w.store_buffer(bytes)
		w.close()
		if DirAccess.rename_absolute(tmp, dest) == OK:
			out.append(dest)
		else:
			DirAccess.remove_absolute(tmp)
	return out


## Every .json file in `folder`, by file name, each with its course or why it cannot be read.
## No folder, no entries.
static func list_folder(folder: String = FOLDER) -> Array[Entry]:
	var out: Array[Entry] = []
	if not DirAccess.dir_exists_absolute(folder):
		return out
	var names := Array(DirAccess.get_files_at(folder))
	names.sort()
	for f: String in names:
		if f.get_extension().to_lower() != "json":
			continue
		var e := Entry.new()
		e.path = folder.path_join(f)
		var errors: Array[String] = []
		e.course = read_file(e.path, errors)
		if e.course == null:
			e.error = errors[0] if not errors.is_empty() else "cannot read it"
		out.append(e)
	return out


## The file an export of a course named `course_name` writes: its name in lower case, every run
## of other characters than letters and digits one "_", in `folder`; "course" when nothing is
## left.
static func path_for(course_name: String, folder: String = FOLDER) -> String:
	var stem := ""
	var gap := false
	for ch: String in course_name.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			if gap and not stem.is_empty():
				stem += "_"
			stem += ch
			gap = false
		else:
			gap = true
	stem = stem.left(STEM_MAX)
	if stem.is_empty():
		stem = "course"
	return folder.path_join(stem + ".json")


## The course's par: its whole holes' pars added up.
static func par(course: CourseData) -> int:
	var total := 0
	for h: HoleData in course.holes:
		if not CourseSave.is_half_placed(course, h):
			total += h.par
	return total


## The course's yardage: its whole holes' rule 4 yardage added up (the line of play, D47, as the
## card and the hole list show it).
static func yards(course: CourseData, validator: CourseValidator = null) -> int:
	var v := validator if validator != null else CourseValidator.new()
	var total := 0
	for h: HoleData in course.holes:
		if not CourseSave.is_half_placed(course, h):
			total += v.hole_yardage(course, h)
	return total


## "9 holes, par 36, 3,240 yd" (whole holes only), or "no holes yet".
static func summary(course: CourseData) -> String:
	var n := 0
	for h: HoleData in course.holes:
		if not CourseSave.is_half_placed(course, h):
			n += 1
	if n == 0:
		return "no holes yet"
	return "%d %s, par %d, %s yd" % [n, "hole" if n == 1 else "holes", par(course),
			group_digits(yards(course))]


## "\"Name\" by Author": the file name stands in for a missing name, "unknown" for a missing
## author.
static func title(course: CourseData, path: String = "") -> String:
	var n := course.course_name
	if n.is_empty():
		n = path.get_file().get_basename() if not path.is_empty() else "Untitled"
	var a := course.author if not course.author.is_empty() else "unknown"
	return "\"%s\" by %s" % [n, a]


## `n` with a comma between each three digits: 3240 is "3,240".
static func group_digits(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
