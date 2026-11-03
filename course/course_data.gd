class_name CourseData
extends Resource
## The single source of truth for a course: a width x height grid of tiles
## (height 0 to MAX_HEIGHT, Surface.Type) and a list of holes.
##
## Land (D26, E6-S3): the map is split into parcels of PARCEL_TILES x PARCEL_TILES tiles,
## parcel (p, q) holding tiles x 16p to 16p + 15 and y 16q to 16q + 15, clipped to the map.
## Each parcel has one owned flag, and next to the flags the course holds the land budget left
## in whole dollars, or UNLIMITED_BUDGET (New sandbox, and every version 1 file).
##
## Readers (renderer, ball, guests, validator) use only the getters:
##   width, height, in_bounds(x, y), get_height(x, y), get_surface(x, y) (off-map
##   reads give height 0 and Surface.Type.OOB), surface_grid(), holes,
##   course_name, author, thumbnail, to_dict(), content_hash(), copy(),
##   parcels_wide, parcels_high, parcel_in_bounds(p), parcel_of(x, y), parcel_rect(p),
##   is_parcel_owned(p), is_owned(x, y) (off-map tiles are never owned), land_budget,
##   has_unlimited_budget().
##
## WRITERS: only course/builder.gd and course/save.gd may call set_tile, set_holes,
## set_info, set_parcel_owned and set_land_budget (CLAUDE.md Architecture). Tests may call
## them to build fixtures.
##
## Serialised as course format version 2 (.claude/skills/course-file/SKILL.md):
## tiles are row-major (index = y * width + x), one byte each, (height << 4) | surface,
## base64 encoded; "owned" is one string per parcel row (q), one "1" or "0" per parcel (p);
## "land_budget" is the dollars left, or null for unlimited. from_dict reads version 2 only:
## course/save.gd migrates a version 1 file first (CourseSave.migrate).

const FORMAT_VERSION: int = 2
const MAX_HEIGHT: int = 7
## Tiles along a parcel's edge (D26). A format constant, not a tunable: the saved owned flags
## are indexed by it, so changing it needs a new format version and a migration.
const PARCEL_TILES: int = 16
## land_budget when there is no limit (New sandbox, version 1 files): null in a file.
const UNLIMITED_BUDGET: int = -1

var width: int:
	get:
		return _width
var height: int:
	get:
		return _height
## Read-only array. Replace through set_holes.
var holes: Array[HoleData]:
	get:
		return _holes
var course_name: String:
	get:
		return _course_name
var author: String:
	get:
		return _author
var thumbnail: String:
	get:
		return _thumbnail
## Parcels along x and along y: ceil(width / PARCEL_TILES), ceil(height / PARCEL_TILES).
var parcels_wide: int:
	get:
		return ceili(_width / float(PARCEL_TILES))
var parcels_high: int:
	get:
		return ceili(_height / float(PARCEL_TILES))
## Dollars left to buy parcels with, or UNLIMITED_BUDGET.
var land_budget: int:
	get:
		return _land_budget

var _width: int = 0
var _height: int = 0
var _tiles: PackedByteArray = PackedByteArray()
var _holes: Array[HoleData] = []
var _course_name: String = ""
var _author: String = ""
var _thumbnail: String = ""
## One byte per parcel, row-major (index = q * parcels_wide + p): 1 owned, 0 not.
var _owned: PackedByteArray = PackedByteArray()
var _land_budget: int = UNLIMITED_BUDGET


func _init() -> void:
	_holes.make_read_only()


## A new course filled with one surface at one height, every parcel owned and an unlimited
## land budget (as New sandbox, D10). Not a write to an existing course.
static func create(p_width: int, p_height: int, fill_surface: Surface.Type = Surface.Type.ROUGH,
		fill_height: int = 0) -> CourseData:
	assert(p_width > 0 and p_height > 0, "course size must be positive")
	var c := CourseData.new()
	c._width = p_width
	c._height = p_height
	c._tiles.resize(p_width * p_height)
	c._tiles.fill(_pack(clampi(fill_height, 0, MAX_HEIGHT), fill_surface))
	c._owned.resize(c.parcels_wide * c.parcels_high)
	c._owned.fill(1)
	return c


## The "owned" field of a format version 2 file for a width x height map with every parcel
## owned: one string of "1"s per parcel row. course/save.gd's version 1 migration and
## course/course_generator.gd use it.
static func all_owned_rows(p_width: int, p_height: int) -> Array:
	var rows: Array = []
	var row := "1".repeat(ceili(p_width / float(PARCEL_TILES)))
	for q: int in ceili(p_height / float(PARCEL_TILES)):
		rows.append(row)
	return rows


# --- read ---

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < _width and y < _height


## Height step 0 to MAX_HEIGHT. Off-map tiles read as height 0.
func get_height(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return _tiles[_index(x, y)] >> 4


## Surface.Type value. Off-map tiles read as Surface.Type.OOB, so edge sampling
## (cursor picking, ball stepping) never wraps into a neighbouring row.
func get_surface(x: int, y: int) -> Surface.Type:
	if not in_bounds(x, y):
		return Surface.Type.OOB
	return (_tiles[_index(x, y)] & 0x0F) as Surface.Type


## True when parcel `p` (in parcel coordinates) is on the map.
func parcel_in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < parcels_wide and p.y < parcels_high


## The parcel holding tile (x, y). An off-map tile gives the parcel it would be in.
func parcel_of(x: int, y: int) -> Vector2i:
	return Vector2i(floori(x / float(PARCEL_TILES)), floori(y / float(PARCEL_TILES)))


## The tiles of parcel `p`, clipped to the map (empty for a parcel off the map).
func parcel_rect(p: Vector2i) -> Rect2i:
	if not parcel_in_bounds(p):
		return Rect2i()
	var r := Rect2i(p * PARCEL_TILES, Vector2i(PARCEL_TILES, PARCEL_TILES))
	return r.intersection(Rect2i(0, 0, _width, _height))


## True when parcel `p` is owned. Parcels off the map are not.
func is_parcel_owned(p: Vector2i) -> bool:
	if not parcel_in_bounds(p):
		return false
	return _owned[_parcel_index(p)] != 0


## True when tile (x, y) is on an owned parcel. Off-map tiles are never owned.
func is_owned(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return _owned[_parcel_index(parcel_of(x, y))] != 0


## True when buying land has no budget limit (New sandbox, version 1 files).
func has_unlimited_budget() -> bool:
	return _land_budget == UNLIMITED_BUDGET


## Every tile's Surface.Type value, row-major (index = y * width + x), as a fresh copy.
## For whole-map readers (the validator's rule 3 flood) that would otherwise call
## get_surface once per tile.
func surface_grid() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(_tiles.size())
	for i in _tiles.size():
		out[i] = _tiles[i] & 0x0F
	return out


## Hex SHA-256 of the full serialised content (tiles, holes, name, author, thumbnail, parcel
## ownership and land budget).
## Equal content gives an equal hash; any edit changes it.
func content_hash() -> String:
	return JSON.stringify(to_dict(), "", true).sha256_text()


## A deep, independent copy.
func copy() -> CourseData:
	var c := CourseData.new()
	c._width = _width
	c._height = _height
	c._tiles = _tiles.duplicate()
	c._course_name = _course_name
	c._author = _author
	c._thumbnail = _thumbnail
	c._owned = _owned.duplicate()
	c._land_budget = _land_budget
	c._replace_holes(_holes)
	return c


## Course format version 2 dictionary, ready for JSON.stringify.
func to_dict() -> Dictionary:
	var hole_dicts: Array = []
	for h in _holes:
		hole_dicts.append(h.to_dict())
	return {
		"version": FORMAT_VERSION,
		"name": _course_name,
		"author": _author,
		"width": _width,
		"height": _height,
		"tiles": Marshalls.raw_to_base64(_tiles),
		"holes": hole_dicts,
		"thumbnail": _thumbnail,
		"owned": _owned_rows(),
		"land_budget": null if has_unlimited_budget() else _land_budget,
	}


# --- write (course/builder.gd and course/save.gd only) ---

func set_tile(x: int, y: int, tile_height: int, surface: Surface.Type) -> void:
	assert(in_bounds(x, y), "tile out of bounds")
	assert(tile_height >= 0 and tile_height <= MAX_HEIGHT, "height out of range")
	assert(Surface.is_valid(surface), "surface out of range")
	_tiles[_index(x, y)] = _pack(tile_height, surface)


## Replaces the holes list with copies of `new_holes`.
func set_holes(new_holes: Array) -> void:
	_replace_holes(new_holes)


func set_info(p_name: String, p_author: String, p_thumbnail: String) -> void:
	_course_name = p_name
	_author = p_author
	_thumbnail = p_thumbnail


## Marks parcel `p` owned or not.
func set_parcel_owned(p: Vector2i, owned: bool) -> void:
	assert(parcel_in_bounds(p), "parcel out of bounds")
	_owned[_parcel_index(p)] = 1 if owned else 0


## Sets the land budget left: whole dollars, 0 or more, or UNLIMITED_BUDGET.
func set_land_budget(budget: int) -> void:
	assert(budget >= 0 or budget == UNLIMITED_BUDGET, "budget must be 0 or more, or unlimited")
	_land_budget = budget


# --- load ---

## Parses a course format version 2 dictionary (as from JSON.parse_string; course/save.gd
## migrates older versions first). Returns null and appends a reason per problem to `errors`
## when the data is malformed: wrong version, bad size, tiles not width*height bytes, height
## above MAX_HEIGHT, unknown surface, owned rows not one "0" or "1" per parcel, a land budget
## that is not null or a whole number of 0 or more, malformed hole, or a tee/cup off the map.
## Gameplay rules (one tee, cup on green, yardage vs par) belong to course/validator.gd.
static func from_dict(data: Dictionary, errors: Array[String] = []) -> CourseData:
	var start := errors.size()
	var version := read_int(data, "version", errors)
	if errors.size() == start and version != FORMAT_VERSION:
		errors.append("version: expected %d, got %d" % [FORMAT_VERSION, version])
	var w := read_int(data, "width", errors)
	var h := read_int(data, "height", errors)
	if errors.size() > start:
		return null
	if w <= 0:
		errors.append("width must be positive, got %d" % w)
	if h <= 0:
		errors.append("height must be positive, got %d" % h)
	var texts := {}
	for key in ["name", "author", "thumbnail", "tiles"]:
		var v: Variant = data.get(key, "")
		if typeof(v) != TYPE_STRING:
			errors.append("%s must be a string" % key)
			v = ""
		texts[key] = v
	if errors.size() > start:
		return null

	# Godot logs an engine error when decoding "", so treat empty as zero bytes.
	var tiles := PackedByteArray()
	if not (texts["tiles"] as String).is_empty():
		tiles = Marshalls.base64_to_raw(texts["tiles"])
	if tiles.size() != w * h:
		errors.append("tiles: expected %d bytes for %dx%d, got %d" % [w * h, w, h, tiles.size()])
		return null
	for i in tiles.size():
		var b := tiles[i]
		var at := "(%d, %d)" % [i % w, i / w]
		if (b >> 4) > MAX_HEIGHT:
			errors.append("tile %s: height %d above %d" % [at, b >> 4, MAX_HEIGHT])
		if not Surface.is_valid(b & 0x0F):
			errors.append("tile %s: surface %d unknown" % [at, b & 0x0F])
	if errors.size() > start:
		return null

	var owned := _read_owned(data.get("owned"), ceili(w / float(PARCEL_TILES)),
			ceili(h / float(PARCEL_TILES)), errors)
	var budget := UNLIMITED_BUDGET
	if not data.has("land_budget"):
		errors.append("land_budget is missing (null for unlimited)")
	elif data["land_budget"] != null:
		budget = read_int(data, "land_budget", errors)
		if errors.size() == start and budget < 0:
			errors.append("land_budget must be 0 or more, or null, got %d" % budget)
	if errors.size() > start:
		return null

	var parsed_holes: Array[HoleData] = []
	var raw_holes: Variant = data.get("holes", [])
	if typeof(raw_holes) != TYPE_ARRAY:
		errors.append("holes must be a list")
		return null
	for raw: Variant in raw_holes:
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("hole must be an object")
			continue
		var hole := HoleData.from_dict(raw, errors)
		if hole == null:
			continue
		if not (hole.tee.x >= 0 and hole.tee.y >= 0 and hole.tee.x < w and hole.tee.y < h):
			errors.append("hole %d: tee %s off the %dx%d map" % [hole.number, hole.tee, w, h])
		if not (hole.cup.x >= 0 and hole.cup.y >= 0 and hole.cup.x < w and hole.cup.y < h):
			errors.append("hole %d: cup %s off the %dx%d map" % [hole.number, hole.cup, w, h])
		parsed_holes.append(hole)
	if errors.size() > start:
		return null

	var c := CourseData.new()
	c._width = w
	c._height = h
	c._tiles = tiles
	c._course_name = texts["name"]
	c._author = texts["author"]
	c._thumbnail = texts["thumbnail"]
	c._owned = owned
	c._land_budget = budget
	c._replace_holes(parsed_holes)
	return c


## Reads data[key] as an integer. JSON gives floats, so integral floats are accepted.
## Appends to `errors` and returns 0 when missing or fractional. Shared with HoleData.
static func read_int(data: Dictionary, key: String, errors: Array[String], context: String = "") -> int:
	var label := key if context.is_empty() else "%s: %s" % [context, key]
	var v: Variant = data.get(key)
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			if is_finite(v) and float(v) == floorf(v):
				return int(v)
			errors.append("%s must be a whole number, got %s" % [label, v])
		TYPE_NIL:
			errors.append("%s is missing" % label)
		_:
			errors.append("%s must be a number" % label)
	return 0


# --- internals ---

func _index(x: int, y: int) -> int:
	return y * _width + x


func _parcel_index(p: Vector2i) -> int:
	return p.y * parcels_wide + p.x


func _owned_rows() -> Array:
	var rows: Array = []
	for q: int in parcels_high:
		var row := ""
		for p: int in parcels_wide:
			row += "1" if _owned[q * parcels_wide + p] != 0 else "0"
		rows.append(row)
	return rows


## Reads the "owned" field: `rows` strings of `cols` characters, each "0" or "1".
static func _read_owned(v: Variant, cols: int, rows: int, errors: Array[String]) -> PackedByteArray:
	var out := PackedByteArray()
	if typeof(v) != TYPE_ARRAY:
		errors.append("owned must be a list of %d parcel rows" % rows)
		return out
	var list: Array = v
	if list.size() != rows:
		errors.append("owned: expected %d parcel rows, got %d" % [rows, list.size()])
		return out
	for q: int in rows:
		var row: Variant = list[q]
		if typeof(row) != TYPE_STRING or (row as String).length() != cols:
			errors.append("owned row %d must be a string of %d \"0\" or \"1\"" % [q, cols])
			continue
		for ch: String in (row as String):
			if ch != "0" and ch != "1":
				errors.append("owned row %d: \"%s\" is not \"0\" or \"1\"" % [q, ch])
				break
			out.append(1 if ch == "1" else 0)
	return out


static func _pack(tile_height: int, surface: int) -> int:
	return (tile_height << 4) | surface


func _replace_holes(source: Array) -> void:
	var fresh: Array[HoleData] = []
	for h: HoleData in source:
		fresh.append(h.copy())
	fresh.make_read_only()
	_holes = fresh
