class_name CourseData
extends Resource
## The single source of truth for a course: a width x height grid of tiles
## (height 0 to MAX_HEIGHT, Surface.Type) and a list of holes.
##
## Readers (renderer, ball, guests, validator) use only the getters:
##   width, height, in_bounds(x, y), get_height(x, y), get_surface(x, y) (off-map
##   reads give height 0 and Surface.Type.OOB), holes,
##   course_name, author, thumbnail, to_dict(), content_hash(), copy().
##
## WRITERS: only course/builder.gd and course/save.gd may call set_tile, set_holes
## and set_info (CLAUDE.md Architecture). Tests may call them to build fixtures.
##
## Serialised as course format version 1 (.claude/skills/course-file/SKILL.md):
## tiles are row-major (index = y * width + x), one byte each, (height << 4) | surface,
## base64 encoded.

const FORMAT_VERSION: int = 1
const MAX_HEIGHT: int = 7

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

var _width: int = 0
var _height: int = 0
var _tiles: PackedByteArray = PackedByteArray()
var _holes: Array[HoleData] = []
var _course_name: String = ""
var _author: String = ""
var _thumbnail: String = ""


func _init() -> void:
	_holes.make_read_only()


## A new course filled with one surface at one height. Not a write to an existing course.
static func create(p_width: int, p_height: int, fill_surface: Surface.Type = Surface.Type.ROUGH,
		fill_height: int = 0) -> CourseData:
	assert(p_width > 0 and p_height > 0, "course size must be positive")
	var c := CourseData.new()
	c._width = p_width
	c._height = p_height
	c._tiles.resize(p_width * p_height)
	c._tiles.fill(_pack(clampi(fill_height, 0, MAX_HEIGHT), fill_surface))
	return c


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


## Hex SHA-256 of the full serialised content (tiles, holes, name, author, thumbnail).
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
	c._replace_holes(_holes)
	return c


## Course format version 1 dictionary, ready for JSON.stringify.
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


# --- load ---

## Parses a course format version 1 dictionary (as from JSON.parse_string).
## Returns null and appends a reason per problem to `errors` when the data is malformed:
## wrong version, bad size, tiles not width*height bytes, height above MAX_HEIGHT,
## unknown surface, malformed hole, or a tee/cup off the map.
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


static func _pack(tile_height: int, surface: int) -> int:
	return (tile_height << 4) | surface


func _replace_holes(source: Array) -> void:
	var fresh: Array[HoleData] = []
	for h: HoleData in source:
		fresh.append(h.copy())
	fresh.make_read_only()
	_holes = fresh
