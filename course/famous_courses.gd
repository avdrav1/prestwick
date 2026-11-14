class_name FamousCourses
extends RefCounted
## The famous courses (E15-S1, D70): the four example courses of E13, E16-S1's Dogleg Hollow,
## E18-S6's Old Grey Links (Championship), the first eighteen, and E19-S1's Dogleg Hollow
## (Championship)
## (docs/courses.md), built into the game in res://courses/ (the export presets' include_filter packs courses/*.json)
## and played from there, so each update brings their latest version. The main menu's Famous
## courses page lists them and starts a new game on one (Main.start_famous).
##
## Each course file carries its id and its version ("course_id", "course_version", optional
## fields of course format 3, CourseData). Versions count the files that shipped: version n's
## file is the one whose SHA-256 is the n-th in its course's "versions" below, 1 being rc8's (the
## first release with the four). tests/test_example_courses.gd checks that each file's hash is
## its version's, so a fixture change that changes the file fails until the next version and the
## new file's hash are added here. The same hashes tell migrate_copies an unchanged copy from an
## edited one.
##
## E13-S5 (rc8 to rc10) copied the four into user://courses/ at start; migrate_copies, run once
## by the game, removes those copies when they are a shipped file byte for byte and keeps an
## edited one as "<name> (my copy)".

const FROM: String = "res://courses"
## Where the game records that migrate_copies ran, so it runs once per user folder.
const MIGRATION_PATH: String = "user://famous_courses.cfg"
const MIGRATION_SECTION: String = "copies"
const MIGRATION_KEY: String = "migrated"
## What an edited copy's name gains.
const MY_COPY: String = " (my copy)"

## In the page's order. "versions": the SHA-256 of each shipped version's file, oldest first
## (git show v0.6.0-rc8:courses/<file>, and so on).
const COURSES: Array[Dictionary] = [
	{
		"id": "harbor_links",
		"file": "harbor_links.json",
		"name": "Harbor Links",
		"style": "Holes over water: creeks, ponds and an island green to finish.",
		"versions": [
			"8e26e75b69b9fff1c4c21e6a961f63a2a1f10793655dd45bcd1f5b58d408d432",  # 1: rc8
			"0a10cf33817f3306f08bb298846016ead0016ec7512dc524f4d6b3a289b218cb",  # 2: rc9, rc10
			"0ab2936f37723c05500490e1296806774722a7074dc8cb8c229124a19dcbe030",  # 3: rc11, id
		],
	},
	{
		"id": "old_grey_links",
		"file": "old_grey_links.json",
		"name": "Old Grey Links",
		"style": "Seaside links: dunes, pot bunkers and two burns.",
		"versions": [
			"9bcde7ea84a22fb3ecadfbe3beb10439de76209427e9e708993a154288b8f523",  # 1: rc8
			"53dcf7ef4fea2ede4cf4994a0b207821973f46556c4252cec2aeec5fdab7bb83",  # 2: rc9
			"30d6ed5a84d63cf8d892c09313330c915f76e04c86a1b88557709f08c0ce9e18",  # 3: rc10
			"8f6445e64e244cf8d4c8c1b0ff4fb66581069e1c5ac02fc6d2f6e905c4abcc2a",  # 4: rc11, id
		],
	},
	{
		"id": "pine_ridge",
		"file": "pine_ridge.json",
		"name": "Pine Ridge",
		"style": "Tree-lined parkland: pine corridors, doglegs and creeks.",
		"versions": [
			"47402aae711e7e28afc8a33b06e3533fc459db0ee7b2a0448e5f28cbc55e335b",  # 1: rc8
			"77d11e2a21da87f5fa154afc2cf5312f69dbda9f2a52c8ad15c0d861ff059851",  # 2: rc9, rc10
			"dcf5fb406b726a99995e7c16a9f8be93d2569c8327869eef4021715355707948",  # 3: rc11, id
		],
	},
	{
		"id": "cliffside",
		"file": "cliffside.json",
		"name": "Cliffside",
		"style": "Clifftop holes round an island, across coves and chasms.",
		"versions": [
			"ea8c5f20440a3aac6255146e7efedb4b406989b5928f1beaea716f260581fc58",  # 1: rc8
			"59b84ddd79f781450ce72423a98b9c1f7fa247ddb52972e09a052dba063c304f",  # 2: rc9
			"edc064fdc93d4746da5574d1212a400f6cc12eceb24456d14d61e81588a801cb",  # 3: rc10
			"ee21cf769e659ad7291a6c31764de7703f5db1d696773a0526cf95ab6f4c1b34",  # 4: rc11, id
		],
	},
	{
		# E16-S1: first shipped in rc12, so its version 1 is that file (never copied by E13-S5).
		"id": "dogleg_hollow",
		"file": "dogleg_hollow.json",
		"name": "Dogleg Hollow",
		"style": "Nine famous doglegs: every hole bends round a lake, woods or sand.",
		"versions": [
			"80d73c51fd0bdd969988a12a50c2e1156df83692217a72ac9a0b9e4d17f91cdf",  # 1: rc12
		],
	},
	{
		# E18-S6: the first famous eighteen, on D71's 192 x 192 map: Old Grey Links' nine out and
		# nine more famous links holes home. First shipped in 0.7.0, so its version 1 is that file.
		"id": "old_grey_championship",
		"file": "old_grey_championship.json",
		"name": "Old Grey Links (Championship)",
		"style": "Eighteen holes of links: Old Grey Links out, nine famous holes home.",
		"versions": [
			"b6bee726fcd99f14e41eb3fcfecc4a86f6cc0c267f08a9a586be437d2d22614b",  # 1: 0.7.0
		],
	},
	{
		# E19-S1: the second famous eighteen: Dogleg Hollow's nine out and nine more famous
		# doglegs home. First shipped in 0.7.1, so its version 1 is that file.
		"id": "dogleg_hollow_championship",
		"file": "dogleg_hollow_championship.json",
		"name": "Dogleg Hollow (Championship)",
		"style": "Eighteen famous doglegs: Dogleg Hollow out, nine more bends home.",
		"versions": [
			"e2e2d161e658b212b0dff746248ede0493662454cb0022a5bfdc04c3c7f992fe",  # 1: 0.7.1
		],
	},
]


## What migrate_copies did.
class Migration:
	extends RefCounted
	## False when it had run before (the record was there) and did nothing.
	var ran: bool = false
	## Copies removed: each a shipped file byte for byte.
	var removed: Array[String] = []
	## Edited copies, old path -> new path.
	var renamed: Dictionary = {}
	## Files of a famous course's name left as they were: not a course file, or one that could
	## not be written as the player's copy.
	var kept: Array[String] = []


## The ids, in the page's order.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Dictionary in COURSES:
		out.append(c["id"])
	return out


## The course `id`'s entry of COURSES; empty when there is none.
static func spec(id: String) -> Dictionary:
	for c: Dictionary in COURSES:
		if c["id"] == id:
			return c
	return {}


## The file names, in the page's order.
static func files() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Dictionary in COURSES:
		out.append(c["file"])
	return out


## The built-in file of course `id`; empty for an unknown id.
static func path(id: String, from: String = FROM) -> String:
	var s := spec(id)
	return from.path_join(s["file"]) if not s.is_empty() else ""


## The name the game gives course `id` ("Cliffside"); the id itself when unknown.
static func display_name(id: String) -> String:
	var s := spec(id)
	return s["name"] if not s.is_empty() else id


## The version this game ships of course `id`: its count of versions; 0 for an unknown id.
static func latest_version(id: String) -> int:
	var s := spec(id)
	return (s["versions"] as Array).size() if not s.is_empty() else 0


## The SHA-256 of every file of course `id` that shipped, oldest first.
static func shipped_hashes(id: String) -> PackedStringArray:
	var s := spec(id)
	return PackedStringArray(s["versions"]) if not s.is_empty() else PackedStringArray()


## The built-in course `id`, the latest version. Null, with the reasons in `errors`, when it
## is unknown or its file does not load.
static func load_course(id: String, errors: Array[String] = [], from: String = FROM) -> CourseData:
	var p := path(id, from)
	if p.is_empty():
		errors.append("no famous course \"%s\"" % id)
		return null
	return CourseSave.load_file(p, errors)


## "A newer version of Cliffside is available." when `course` is a famous course of an older
## version than this game ships; empty otherwise (no course, not famous, current, or an id this
## game does not know).
static func newer_note(course: CourseData) -> String:
	if course == null or not course.is_famous():
		return ""
	var latest := latest_version(course.course_id)
	if latest == 0 or course.course_version >= latest:
		return ""
	return "A newer version of %s is available." % display_name(course.course_id)


## Once per user folder (the record at `record`): goes through the files of a famous course's
## name in `folder` (E13-S5's copies). One whose bytes are any shipped version's is removed. One
## that reads as a course but matches none is the player's: it is written whole as "<name> (my
## copy)" (the name field, and the file CourseExport.path_for names, "_2" and on when taken,
## with no famous id, so it is the player's course), then the old file is removed. One that
## does not read as a course is left. The record is written at the end, folder or not.
static func migrate_copies(folder: String = CourseExport.FOLDER,
		record: String = MIGRATION_PATH) -> Migration:
	var m := Migration.new()
	var cfg := ConfigFile.new()
	if cfg.load(record) == OK and cfg.get_value(MIGRATION_SECTION, MIGRATION_KEY, false):
		return m
	m.ran = true
	for c: Dictionary in COURSES:
		var at: String = folder.path_join(c["file"])
		if not FileAccess.file_exists(at):
			continue
		if FileAccess.get_sha256(at) in PackedStringArray(c["versions"]):
			if DirAccess.remove_absolute(at) == OK:
				m.removed.append(at)
			else:
				m.kept.append(at)
			continue
		var to := _keep_as_mine(at, c, folder)
		if to.is_empty():
			m.kept.append(at)
		else:
			m.renamed[at] = to
	DirAccess.make_dir_recursive_absolute(record.get_base_dir())
	cfg.set_value(MIGRATION_SECTION, MIGRATION_KEY, true)
	var err := cfg.save(record)
	if err != OK:
		push_warning("famous courses: could not record the migration (%s)" % error_string(err))
	return m


## Writes the course file at `at` as the player's copy (my_copy_name, no famous id) in
## `folder` and removes `at`. The new path, or empty when `at` is not a course file or the copy
## could not be written (then `at` stays).
static func _keep_as_mine(at: String, c: Dictionary, folder: String) -> String:
	var errors: Array[String] = []
	var course := CourseExport.read_file(at, errors)
	if course == null:
		return ""
	var n := my_copy_name(course.course_name if not course.course_name.is_empty() else c["name"])
	var data := CourseSave.to_data(course)
	data["name"] = n
	data.erase("course_id")
	data.erase("course_version")
	var to := free_path(CourseExport.path_for(n, folder))
	var tmp := to + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(CourseSave.stringify(data))
	f.close()
	if DirAccess.rename_absolute(tmp, to) != OK:
		DirAccess.remove_absolute(tmp)
		return ""
	DirAccess.remove_absolute(at)
	return to


## "Cliffside (my copy)"; a name that already ends so is kept.
static func my_copy_name(course_name: String) -> String:
	return course_name if course_name.ends_with(MY_COPY) else course_name + MY_COPY


## `p`, or the first of "<stem>_2.json", "<stem>_3.json", ... that is free.
static func free_path(p: String) -> String:
	if not FileAccess.file_exists(p):
		return p
	var stem := p.get_basename()
	var ext := p.get_extension()
	var n := 2
	while FileAccess.file_exists("%s_%d.%s" % [stem, n, ext]):
		n += 1
	return "%s_%d.%s" % [stem, n, ext]
