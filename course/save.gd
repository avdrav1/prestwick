class_name CourseSave
extends RefCounted
## Course JSON load and save, course format version 2 (CourseData.FORMAT_VERSION). One of the
## two writers of CourseData (with course/builder.gd). Version migrations go here (course-file
## skill): migrate() brings an older file's data up to the current version before
## CourseData.from_dict reads it.
##
## Version 1 to 2 (E6-S3, D26): a version 1 file predates land, so it loads with every parcel
## owned and an unlimited land budget, the same as New sandbox, and every course and fixture
## made before E6 plays as before.


## Writes `course` as format v2 JSON. Returns OK or the FileAccess error.
## A half-placed hole (tee or cup off the map, as HoleData.UNPLACED is) is DROPPED from the file,
## not refused and not written: CourseData.from_dict rejects an off-map tee or cup, so writing it
## would give a file that does not load. The rest of the course is saved, and the dropped holes'
## numbers are appended to `dropped` so the caller can say so (E2-S12, docs/design.md Holes in
## Build). `course` itself is not changed.
static func save_file(course: CourseData, path: String, dropped: Array[int] = []) -> Error:
	var text := to_json(course, dropped)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


## Reads a course JSON file of any supported version (1 or 2). Returns null and appends reasons to `errors` on failure.
static func load_file(path: String, errors: Array[String] = []) -> CourseData:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		errors.append("%s: cannot read (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	return from_json(text, errors)


## Pretty-printed format v2 JSON text, with half-placed holes dropped (see save_file); their
## numbers are appended to `dropped`.
static func to_json(course: CourseData, dropped: Array[int] = []) -> String:
	var data := course.to_dict()
	var whole: Array = []
	for h: HoleData in course.holes:
		if is_half_placed(course, h):
			dropped.append(h.number)
		else:
			whole.append(h.to_dict())
	data["holes"] = whole
	return JSON.stringify(data, "  ", false)


## True when the hole's tee or cup is off the map (HoleData.UNPLACED or any other off-map
## tile, as course/validator.gd rule 1 counts it). Such a hole cannot be written to a file.
static func is_half_placed(course: CourseData, hole: HoleData) -> bool:
	return not (course.in_bounds(hole.tee.x, hole.tee.y) and course.in_bounds(hole.cup.x, hole.cup.y))


## Parses course JSON text of version 1 or 2. Returns null and appends reasons to `errors` on
## failure.
static func from_json(text: String, errors: Array[String] = []) -> CourseData:
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("JSON line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("course file must be a JSON object")
		return null
	return from_dict(json.data, errors)


## Migrates `data` (version 1 or 2) and parses it. Returns null and appends reasons to
## `errors` on failure. A file may hold at most BuilderTuning.max_holes holes (9), numbered 1 to
## that (E3-S2, docs/design.md Hole list): the builder cannot make any other, so a file that has
## one is refused. Two holes sharing a number load, and validator rule 1 fails them.
static func from_dict(data: Dictionary, errors: Array[String] = []) -> CourseData:
	var c := CourseData.from_dict(migrate(data), errors)
	if c == null:
		return null
	var start := errors.size()
	var max_holes: int = BuilderTuning.load_default().max_holes
	if c.holes.size() > max_holes:
		errors.append("a course has at most %d holes, this one has %d" % [max_holes, c.holes.size()])
	for h: HoleData in c.holes:
		if h.number < 1 or h.number > max_holes:
			errors.append("hole %d: holes are numbered 1 to %d" % [h.number, max_holes])
	return null if errors.size() > start else c


## `data` brought up to CourseData.FORMAT_VERSION, as a new dictionary; data of the current
## version, or of a version this cannot migrate (CourseData.from_dict then reports it), comes
## back unchanged. Version 1 gains "owned" with every parcel owned and "land_budget" null
## (unlimited). A version 1 file whose size is not two whole numbers gains no "owned", and
## CourseData.from_dict reports the size.
static func migrate(data: Dictionary) -> Dictionary:
	var ignored: Array[String] = []
	if not data.has("version") or CourseData.read_int(data, "version", ignored) != 1:
		return data
	var out := data.duplicate()
	out["version"] = 2
	var w := CourseData.read_int(data, "width", ignored)
	var h := CourseData.read_int(data, "height", ignored)
	if ignored.is_empty() and w > 0 and h > 0:
		out["owned"] = CourseData.all_owned_rows(w, h)
	out["land_budget"] = null
	return out
