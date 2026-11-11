class_name GameSave
extends RefCounted
## The game save (E4-S7, docs/design.md Save and load): one versioned JSON file in `user://`
## holding the course (course format v2, through CourseSave, so the land owned and the land
## budget come with it), the guests' seed, the day to resume at the morning of, the money, the
## rating history, the green fee (E4-S6), the guest feed, and (E4-S11) what the saved day's
## morning drew and its guests paid so far, and (E8-S2) when the first hole's opening sent out the
## groups a closed course had turned away, so its replay is the day the player saved, and (E10-S1)
## the New course goal checklist's done goals and fold. Only course/ save code writes CourseData on load
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
## Where the game saves: the manual save (F5, the menu's Save game).
const PATH: String = "user://save.json"
## E8-S4: where the morning autosaves go, `AUTOSAVE_NAME` % slot (1 to the slot count) in this
## folder, apart from the manual save, which an autosave never touches.
const AUTOSAVE_FOLDER: String = "user://"
const AUTOSAVE_NAME: String = "autosave_%d.json"
const MONTHS: PackedStringArray = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
		"Oct", "Nov", "Dec"]


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
	## E8-S2 (D64): the saved day's late starts so far (GuestSim.morning_late_starts), each
	## Vector3i(first group, second, groups sent), so the replay sends the groups a closed
	## course turned away at the seconds the uninterrupted day did. Empty in a save without them.
	var late_starts: Array[Vector3i] = []
	## The feed as ReactionFeed.to_save keeps it; on load, a ReactionFeed (from_save).
	var feed_data: Dictionary = {}
	var feed: ReactionFeed
	## E8-S4: the game this save is of (Main.save_id): a New course, New sandbox or import starts
	## a new one and a load takes the file's. Autosaves rotate among the game's own. Empty in a
	## save from before it (a load gives the game a new id).
	var save_id: String = ""
	## E8-S4: when it was written, Unix seconds (real time); 0 in a save from before it.
	var saved_at: int = 0
	## E8-S4: an autosave's number within its game, from 1, one up on each autosave (the newest
	## is the highest); 0 in a manual save.
	var autosave: int = 0
	## E10-S1: the game has the New course goal checklist (Main.goals): false for a sandbox, an
	## import, or a save from before it. In the file, the optional "goals" object.
	var goals_on: bool = false
	## E10-S1: the done goals' ids (GoalList.ORDER) and whether the panel is folded to one line.
	var goals_done: PackedStringArray = []
	var goals_collapsed: bool = false


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
	if not state.save_id.is_empty():
		data["save_id"] = state.save_id
	if state.saved_at > 0:
		data["saved_at"] = state.saved_at
	if state.autosave > 0:
		data["autosave"] = state.autosave
	if not state.late_starts.is_empty():
		var late: Array = []
		for ls: Vector3i in state.late_starts:
			late.append([ls.x, ls.y, ls.z])
		data["late_starts"] = late
	if state.goals_on:
		data["goals"] = {"done": Array(state.goals_done), "collapsed": state.goals_collapsed}
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
	# E8-S2: a new field with a default, as `fee`: [[first group, second, groups sent], ...].
	if data.has("late_starts"):
		var late: Variant = data["late_starts"]
		if typeof(late) != TYPE_ARRAY:
			errors.append("late_starts must be a list")
		else:
			for v: Variant in late:
				if not _is_late_start(v):
					errors.append("late_starts must hold [group, second, count], whole numbers 0 or more")
					break
				s.late_starts.append(Vector3i(int(v[0]), int(v[1]), int(v[2])))
	# E8-S4: new fields with defaults, as `fee`.
	if data.has("save_id"):
		if typeof(data["save_id"]) != TYPE_STRING:
			errors.append("save_id must be text")
		else:
			s.save_id = data["save_id"]
	if data.has("saved_at"):
		s.saved_at = CourseData.read_int(data, "saved_at", errors)
	if data.has("autosave"):
		s.autosave = CourseData.read_int(data, "autosave", errors)
	# E10-S1: a new field with a default, as `fee`: {"done": [ids], "collapsed": bool}.
	if data.has("goals"):
		_read_goals(data["goals"], s, errors)
	# E4-S13: an E4-S11 save's "second" held the fee over the morning's ceiling; the ceiling no
	# longer moves within a day (D59), so it is ignored.
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


## E10-S1: reads the "goals" object into `s`: "done", a list of goal ids (texts), and "collapsed",
## true or false.
static func _read_goals(v: Variant, s: State, errors: Array[String]) -> void:
	if typeof(v) != TYPE_DICTIONARY:
		errors.append("goals must be an object")
		return
	var g: Dictionary = v
	var done: Variant = g.get("done", [])
	if typeof(done) != TYPE_ARRAY:
		errors.append("goals.done must be a list")
		return
	for id: Variant in done:
		if typeof(id) != TYPE_STRING:
			errors.append("goals.done must hold goal names")
			return
		s.goals_done.append(id)
	var folded: Variant = g.get("collapsed", false)
	if typeof(folded) != TYPE_BOOL:
		errors.append("goals.collapsed must be true or false")
		return
	s.goals_collapsed = folded
	s.goals_on = true


static func _is_late_start(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 3:
		return false
	for x: Variant in v:
		if (typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT) or x != floorf(x) or x < 0:
			return false
	return true


# --- E8-S4: autosaves and the Load page's list ---

## One save the Load page lists: the manual save or an autosave, read whole (so one that would
## not load is listed as unreadable, with why).
class Entry:
	extends RefCounted
	var path: String = ""
	## True for an autosave, false for the manual save.
	var is_autosave: bool = false
	## The save as read; null when it cannot be read.
	var state: State
	## Why it cannot be read (the first reason); empty when it can.
	var error: String = ""
	## When it was written, Unix seconds: the file's `saved_at`, else the file's own time.
	var saved_at: int = 0

	func readable() -> bool:
		return state != null

	## "Saved game: Day 5, $3,200, 11 Nov 2026 14:32", "Autosave: Day 7, ..." or
	## "Autosave: can't be read (reason)".
	func label() -> String:
		var kind: String = "Autosave" if is_autosave else "Saved game"
		if state == null:
			return "%s: can't be read (%s)" % [kind, error]
		var money: String = "unlimited money" if state.unlimited_money else LandPrices.money(state.money)
		return "%s: Day %d, %s, %s" % [kind, state.day, money, GameSave.date_text(saved_at)]


## The autosave file of `slot` (from 1) in `folder`.
static func autosave_path(slot: int, folder: String = AUTOSAVE_FOLDER) -> String:
	return folder.path_join(AUTOSAVE_NAME % slot)


## Reads the save at `path` for the Load page. Null when there is no file.
static func read_entry(path: String, is_autosave: bool) -> Entry:
	if not FileAccess.file_exists(path):
		return null
	var e := Entry.new()
	e.path = path
	e.is_autosave = is_autosave
	var errors: Array[String] = []
	e.state = load_file(path, errors)
	if e.state == null:
		e.error = errors[0] if not errors.is_empty() else "cannot read it"
	e.saved_at = e.state.saved_at if e.state != null and e.state.saved_at > 0 else \
			FileAccess.get_modified_time(path)
	return e


## Every save the Load page lists: the manual save at `manual_path` first, when there is one, then
## the autosaves in `folder`'s `slots` slots, newest first (unreadable ones last).
static func list_saves(manual_path: String = PATH, folder: String = AUTOSAVE_FOLDER,
		slots: int = 3) -> Array[Entry]:
	var out: Array[Entry] = []
	var manual := read_entry(manual_path, false)
	if manual != null:
		out.append(manual)
	var autos: Array[Entry] = []
	for n: int in range(1, slots + 1):
		var e := read_entry(autosave_path(n, folder), true)
		if e != null:
			autos.append(e)
	autos.sort_custom(_newer)
	out.append_array(autos)
	return out


static func _newer(a: Entry, b: Entry) -> bool:
	if a.readable() != b.readable():
		return a.readable()
	if a.saved_at != b.saved_at:
		return a.saved_at > b.saved_at
	var an: int = a.state.autosave if a.state != null else 0
	var bn: int = b.state.autosave if b.state != null else 0
	return an > bn


## Writes `state` as an autosave in `folder` (E8-S4). The slots hold one game's autosaves, its
## newest `slots`: the new one takes an empty slot, or one holding another game's or an
## unreadable file, else this game's oldest; once it is written, any slot still holding another
## game's autosave or an unreadable one is cleared. So a new game leaves an old game's autosaves
## alone until it writes its own. Sets `state.autosave` to one above the game's newest. The
## manual save is never touched. Half-placed holes go to `dropped` as save_file.
static func autosave_file(state: State, folder: String = AUTOSAVE_FOLDER, slots: int = 3,
		dropped: Array[int] = []) -> Error:
	DirAccess.make_dir_recursive_absolute(folder)
	var mine: Dictionary = {}  # slot -> its autosave number, this game's readable slots
	var others: Array[int] = []  # slots holding another game's or an unreadable file
	var empty: Array[int] = []
	for n: int in range(1, slots + 1):
		var path := autosave_path(n, folder)
		if not FileAccess.file_exists(path):
			empty.append(n)
			continue
		var head: Dictionary = _head(path)
		if head.is_empty() or String(head.get("save_id", "")) != state.save_id or state.save_id.is_empty():
			others.append(n)
		else:
			mine[n] = int(head.get("autosave", 0))
	var newest: int = 0
	var oldest_slot: int = -1
	for n: int in mine:
		newest = maxi(newest, mine[n])
		if oldest_slot < 0 or mine[n] < mine[oldest_slot]:
			oldest_slot = n
	var target: int = oldest_slot
	if not empty.is_empty():
		target = empty[0]
	elif not others.is_empty():
		target = others[0]
	state.autosave = newest + 1
	var err := save_file(state, autosave_path(target, folder), dropped)
	if err != OK:
		return err
	for n: int in others:
		if n != target:
			DirAccess.remove_absolute(autosave_path(n, folder))
	return OK


## The fields of the save at `path` the slots are kept by (save_id, autosave), without reading its
## course; empty when it is not a readable save.
static func _head(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("save_version"):
		return {}
	var d: Dictionary = data
	if typeof(d.get("save_id")) != TYPE_STRING or typeof(d.get("autosave")) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	return d


## A real date and time, local: "11 Nov 2026 14:32".
static func date_text(unix: int) -> String:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%d %s %d %02d:%02d" % [t.day, MONTHS[int(t.month) - 1], t.year, t.hour, t.minute]
