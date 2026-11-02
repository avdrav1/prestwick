class_name CourseSave
extends RefCounted
## Course JSON load and save, course format version 1. One of the two writers of
## CourseData (with course/builder.gd). Version migrations go here (course-file skill).


## Writes `course` as format v1 JSON. Returns OK or the FileAccess error.
static func save_file(course: CourseData, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json(course))
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


## Pretty-printed format v1 JSON text.
static func to_json(course: CourseData) -> String:
	return JSON.stringify(course.to_dict(), "  ", false)


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
