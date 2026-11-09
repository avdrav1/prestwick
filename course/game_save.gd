class_name GameSave
extends RefCounted
## The game save (E4-S7, docs/design.md Save and load): one versioned JSON file in `user://`
## holding the course (course format v2, through CourseSave, so the land owned and the land
## budget come with it), the guests' seed, the day to resume at the morning of, the money, the
## rating history, the green fee (E4-S6), the guest feed, and (E4-S11) what the saved day's
## morning drew and its guests paid so far, so its replay is the day the player saved. Only course/ save code writes CourseData on load
## (CLAUDE.md): the course is read by CourseSave.from_dict and nothing here writes it.
##
## Guests out on the course are not saved (D38: none stays overnight), so a load resumes at the
## morning of the saved day and the day plays again from its seed; the feed is saved as it stood
## that morning (ReactionFeed.to_save).
##
## A file that is not a game save, of an unknown version, or with any field wrong loads as null
## with every reason in `errors`, and the caller leaves its game alone.

## The save format's version. A new field with a default reads under the same version.
const FORMAT_VERSION: int = 1
## Where the game saves (one slot until E5's menus).
const PATH: String = "user://save.json"


## Everything a save holds. `money` and `rating_history` are the economy's, filled by
## Main.economy_to_save and read by Main.economy_from_save: E4-S2 (money) and E4-S5 (rating
## history) fill those two functions; the format already carries both.
class State:
	extends RefCounted
	var course: CourseData
	## The guests' days' seed (GuestSim.base_seed; Main.land_seed on a New course).
	var seed_value: int = 0
	## The day to resume at the morning of, from 1 (GuestSim.morning_day).
	var day: int = 1
	## The balance in dollars (E4-S2; below 0 when upkeep took it there), unless
	## `unlimited_money` (null in the file: New sandbox). The course carries a balance too
	## (land_budget); a load takes this one (Main.economy_from_save).
	var money: int = 0
	var unlimited_money: bool = false
	## The course rating at the end of each day so far, oldest first (E4-S5 fills it).
	var rating_history: Array[float] = []
	## E4-S6: the green fee a round (GuestSim.fee); -1 in a save from before it (the start fee).
	var fee: int = -1
	## E4-S11: the guests the saved day's morning drew (GuestSim.morning_arrivals); -1 when its
	## morning has not come, or in a save from before it: the load's morning draws them.
	var arrivals: int = -1
	## E4-S11: what each guest of the saved day paid before the save, in arrival order
	## (DayLedger.paid): the replay's first guests pay these, the rest the fee.
	var fees_paid: Array[int] = []
	## E4-S11: the second of the saved day the save was made at (GuestSim.save_second): the load
	## holds `fee` against a falling ceiling until the replay reaches it. 0 at a morning.
	var second: int = 0
	## The feed as ReactionFeed.to_save keeps it; on load, a ReactionFeed (from_save).
	var feed_data: Dictionary = {}
	var feed: ReactionFeed


## Writes `state` to `path` as JSON, replacing any save there only once the new one is written
## whole (a temp file renamed over it), so a failed write never spoils the last save. Half-placed
## holes are dropped (CourseSave.to_json) and their numbers appended to `dropped`.
static func save_file(state: State, path: String = PATH, dropped: Array[int] = []) -> Error:
	var text := to_json(state, dropped)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return DirAccess.rename_absolute(tmp, path)


## The save JSON text of `state`; half-placed holes' numbers are appended to `dropped`.
static func to_json(state: State, dropped: Array[int] = []) -> String:
	var course_json: Variant = JSON.parse_string(CourseSave.to_json(state.course, dropped))
	var data := {
		"save_version": FORMAT_VERSION,
		"seed": state.seed_value,
		"day": state.day,
		"money": null if state.unlimited_money else state.money,
		"rating_history": state.rating_history.duplicate(),
		"feed": state.feed_data,
		"course": course_json,
	}
	if state.fee >= 0:
		data["fee"] = state.fee
	if state.arrivals >= 0:
		data["arrivals"] = state.arrivals
	if not state.fees_paid.is_empty():
		data["fees_paid"] = state.fees_paid.duplicate()
	if state.second > 0:
		data["second"] = state.second
	return JSON.stringify(data, "  ", false)


## Reads the save at `path`. Null, with the reasons in `errors`, when there is none or it is
## not a whole, valid save. `feed_window` and `feed_lines` as from_json.
static func load_file(path: String = PATH, errors: Array[String] = [], feed_window: int = 50,
		feed_lines: int = 100) -> State:
	if not FileAccess.file_exists(path):
		errors.append("no saved game")
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		errors.append("cannot read the save (%s)" % error_string(FileAccess.get_open_error()))
		return null
	return from_json(text, errors, feed_window, feed_lines)


## Parses save JSON text. Null, with the reasons in `errors`, on any fault. `feed_window` and
## `feed_lines` size the loaded feed (GuestTuning.rating_window, FeedTuning.max_entries).
static func from_json(text: String, errors: Array[String] = [], feed_window: int = 50,
		feed_lines: int = 100) -> State:
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("not readable: JSON line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("not a saved game")
		return null
	var data: Dictionary = json.data
	if not data.has("save_version"):
		errors.append("not a saved game (a course file has no save_version)")
		return null
	var start := errors.size()
	var version := CourseData.read_int(data, "save_version", errors)
	if errors.size() == start and version != FORMAT_VERSION:
		errors.append("save_version: expected %d, got %d" % [FORMAT_VERSION, version])
	if errors.size() > start:
		return null
	var s := State.new()
	s.seed_value = CourseData.read_int(data, "seed", errors)
	s.day = CourseData.read_int(data, "day", errors)
	if s.day < 1 and errors.size() == start:
		errors.append("day must be 1 or more, got %d" % s.day)
	if not data.has("money"):
		errors.append("money is missing (null for unlimited)")
	elif data["money"] == null:
		s.unlimited_money = true
	else:
		s.money = CourseData.read_int(data, "money", errors)
	var history: Variant = data.get("rating_history")
	if typeof(history) != TYPE_ARRAY:
		errors.append("rating_history must be a list")
	else:
		for v: Variant in history:
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				errors.append("rating_history must hold numbers")
				break
			s.rating_history.append(float(v))
	# E4-S6: a new field with a default (FORMAT_VERSION): an E4-S7 save has no fee.
	if data.has("fee"):
		s.fee = CourseData.read_int(data, "fee", errors)
		if s.fee < 0:
			errors.append("fee must be 0 or more, got %d" % s.fee)
	# E4-S11: new fields with defaults, as `fee`.
	if data.has("arrivals"):
		s.arrivals = CourseData.read_int(data, "arrivals", errors)
		if s.arrivals < 0:
			errors.append("arrivals must be 0 or more, got %d" % s.arrivals)
	if data.has("fees_paid"):
		var paid: Variant = data["fees_paid"]
		if typeof(paid) != TYPE_ARRAY:
			errors.append("fees_paid must be a list")
		else:
			for v: Variant in paid:
				if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or v != floorf(v) or v < 0:
					errors.append("fees_paid must hold whole dollars, 0 or more")
					break
				s.fees_paid.append(int(v))
	if data.has("second"):
		s.second = CourseData.read_int(data, "second", errors)
		if s.second < 0:
			errors.append("second must be 0 or more, got %d" % s.second)
	s.feed = ReactionFeed.from_save(data.get("feed"), feed_window, feed_lines, errors)
	if typeof(data.get("course")) != TYPE_DICTIONARY:
		errors.append("course must be an object")
	else:
		var course_errors: Array[String] = []
		s.course = CourseSave.from_dict(data["course"], course_errors)
		for e: String in course_errors:
			errors.append("course: %s" % e)
	if errors.size() > start or s.course == null or s.feed == null:
		return null
	s.feed_data = data["feed"]
	return s
