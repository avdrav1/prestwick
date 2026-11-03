class_name CourseSave
extends RefCounted
## Course JSON load and save, course format version 1. One of the two writers of
## CourseData (with course/builder.gd). Version migrations go here (course-file skill).


## Writes `course` as format v1 JSON. Returns OK or the FileAccess error.
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


## Reads a format v1 JSON file. Returns null and appends reasons to `errors` on failure.
static func load_file(path: String, errors: Array[String] = []) -> CourseData:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		errors.append("%s: cannot read (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	return from_json(text, errors)


## Pretty-printed format v1 JSON text, with half-placed holes dropped (see save_file); their
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


## Parses format v1 JSON text. Returns null and appends reasons to `errors` on failure.
static func from_json(text: String, errors: Array[String] = []) -> CourseData:
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("JSON line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("course file must be a JSON object")
		return null
	return CourseData.from_dict(json.data, errors)
