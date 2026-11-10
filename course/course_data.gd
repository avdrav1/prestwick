class_name CourseData
extends Resource
## The single source of truth for a course: a width x height grid of tiles
## (height 0 to MAX_HEIGHT, Surface.Type) and a list of holes.
##
## Land (D26, E6-S3): the map is split into parcels of PARCEL_TILES x PARCEL_TILES tiles,
## parcel (p, q) holding tiles x 16p to 16p + 15 and y 16q to 16q + 15, clipped to the map.
## Each parcel has one owned flag, and next to the flags the course holds the balance (E4-S2,
## D57: the one balance, still named land_budget, which building and parcels both come out of)
## in whole dollars, below 0 when upkeep took it there, or UNLIMITED_BUDGET (New sandbox, and
## every version 1 file).
##
## Readers (renderer, ball, guests, validator) use only the getters:
##   width, height, in_bounds(x, y), get_height(x, y), get_surface(x, y) (off-map
##   reads give height 0 and Surface.Type.OOB), surface_grid(), holes,
##   course_name, author, thumbnail, to_dict(), content_hash(), copy(),
##   parcels_wide, parcels_high, parcel_in_bounds(p), parcel_of(x, y), parcel_rect(p),
##   is_parcel_owned(p), is_owned(x, y) (off-map tiles are never owned), land_budget,
##   has_unlimited_budget(), revision, height_revision, land_revision, surface_revision(s),
##   has_clubhouse(), clubhouse, clubhouse_facing, clubhouse_cells(), is_clubhouse(x, y),
##   clubhouse_door(), clubhouse_revision, decor_at(x, y), decor_cells(), decor_revision.
##
## Decor (E5-S3, art/specs/decor.md): benches, flags and signs placed on tiles, one per tile, by
## kind (an index into DECOR_KINDS, the decor sheet's frame order). Decor is scenery only: the
## ball, the validator and guests never read it. It is an optional field of version 3 ("decor",
## a list of [x, y, kind]; absent when there is none), so a course without decor writes the
## same file as before and an older game reading a file with decor only drops the scenery.
##
## The clubhouse (D60, E5-S9): one 3x3 building, where guests arrive and leave, stored as its
## centre tile and a facing, one of FACINGS (the side its door is on). The door is the tile just
## outside the middle of that side (clubhouse_door). NO_CLUBHOUSE when the course has none (no
## room was found for it): then no guests come.
##
## WRITERS: only course/builder.gd and course/save.gd may call set_tile, set_holes,
## set_info, set_parcel_owned, set_land_budget, set_clubhouse and set_decor (CLAUDE.md Architecture). Tests may call
## them to build fixtures.
##
## Serialised as course format version 3 (.claude/skills/course-file/SKILL.md):
## tiles are row-major (index = y * width + x), one byte each, (height << 4) | surface,
## base64 encoded; "owned" is one string per parcel row (q), one "1" or "0" per parcel (p);
## "land_budget" is the balance in dollars (below 0 allowed, E4-S2), or null for unlimited;
## "clubhouse" (version 3, E5-S9) is {"x", "y", "facing"} (its centre tile and one of
## FACING_NAMES), or null for none. from_dict reads version 3 only: course/save.gd migrates a
## version 1 or 2 file first (CourseSave.migrate) and places its clubhouse by rule.

const FORMAT_VERSION: int = 3
## E5-S3: decor kinds by index, the decor sheet's frame order (art/sprites/decor.png). A format
## constant: files store the index, so new kinds are appended, never reordered.
const DECOR_KINDS: PackedStringArray = ["bench_x", "bench_y", "flag", "sign"]
## decor_at when a tile has none.
const NO_DECOR: int = -1
## The clubhouse's footprint is CLUBHOUSE_SIZE x CLUBHOUSE_SIZE tiles round its centre (D60).
## A format constant: the file stores the centre.
const CLUBHOUSE_SIZE: int = 3
## Tiles from the clubhouse's centre to its edge: (CLUBHOUSE_SIZE - 1) / 2.
const CLUBHOUSE_REACH: int = 1
## The clubhouse centre when there is none.
const NO_CLUBHOUSE: Vector2i = Vector2i(-1, -1)
## The four facings, the side the door is on, by index: +x, +y, -x, -y. On screen (Iso, 2:1) +x
## runs down and right, +y down and left, so facings 0 and 1 show their door to the camera.
const FACINGS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
## Each facing's name in a file, by the same index.
const FACING_NAMES: PackedStringArray = ["+x", "+y", "-x", "-y"]
const MAX_HEIGHT: int = 7
## Tiles along a parcel's edge (D26). A format constant, not a tunable: the saved owned flags
## are indexed by it, so changing it needs a new format version and a migration.
const PARCEL_TILES: int = 16
## land_budget when there is no limit (New sandbox, version 1 files): null in a file. Far below
## any balance, since a balance may go below 0 (E4-S2: negative balance pauses building).
const UNLIMITED_BUDGET: int = -(1 << 62)

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
## The balance (E4-S2, D57): dollars left to build and buy parcels with, below 0 when upkeep
## took it there, or UNLIMITED_BUDGET.
var land_budget: int:
	get:
		return _land_budget
## Counts tile and ownership writes (set_tile, set_parcel_owned) since this object was made,
## so a reader keeping something derived from the tiles can tell when someone else wrote
## (the builder's rule 3 graph, E3-S12). Not saved, not part of the content.
var revision: int:
	get:
		return _revision
## E3-S74: counts the writes that changed a tile's height, so a reader keeping something
## derived from the heights alone (HoleChecks' statics) can tell whether it still stands.
## Like `revision`, not saved and not part of the content; a fresh object starts at 0.
var height_revision: int:
	get:
		return _height_revision
## E3-S74: counts the writes that changed a parcel's owned flag.
var land_revision: int:
	get:
		return _land_revision
## E5-S9: the clubhouse's centre tile, NO_CLUBHOUSE when there is none.
var clubhouse: Vector2i:
	get:
		return _clubhouse
## E5-S9: the clubhouse's facing, an index into FACINGS.
var clubhouse_facing: int:
	get:
		return _clubhouse_facing
## E5-S9: counts clubhouse writes (set_clubhouse). Not saved, not part of the content.
var clubhouse_revision: int:
	get:
		return _clubhouse_revision

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
var _revision: int = 0
var _height_revision: int = 0
var _land_revision: int = 0
var _clubhouse: Vector2i = NO_CLUBHOUSE
var _clubhouse_facing: int = 1
var _clubhouse_revision: int = 0
## E5-S3: tile -> decor kind.
var _decor: Dictionary = {}
var _decor_revision: int = 0
## One counter per Surface.Type (surface_revision).
var _surface_revisions := PackedInt32Array()


func _init() -> void:
	_holes.make_read_only()
	_surface_revisions.resize(Surface.COUNT)


## E3-S74: counts the writes that turned a tile to or from surface `s` (one write that turns
## rough to fairway moves both counters). With height_revision and land_revision, a reader
## that reads only some surfaces keys on those surfaces' counters, not on every tile.
func surface_revision(s: Surface.Type) -> int:
	return _surface_revisions[s]


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
## E3-S75: get_height, get_surface and is_owned spell out in_bounds and the index rather than
## call them: a Ball tick reads them dozens of times, and each GDScript call costs about as much
## as the read (the same answers, a guest frame's ticks about a quarter cheaper).
func get_height(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return 0
	return _tiles[y * _width + x] >> 4


## Surface.Type value. Off-map tiles read as Surface.Type.OOB, so edge sampling
## (cursor picking, ball stepping) never wraps into a neighbouring row.
func get_surface(x: int, y: int) -> Surface.Type:
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return Surface.Type.OOB
	return (_tiles[y * _width + x] & 0x0F) as Surface.Type


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
@warning_ignore("integer_division")
func is_owned(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return false
	# On the map x and y are 0 or more, so integer division is parcel_of's floor (and, rounded
	# up, parcels_wide's ceiling).
	return _owned[(y / PARCEL_TILES) * ((_width + PARCEL_TILES - 1) / PARCEL_TILES)
			+ x / PARCEL_TILES] != 0


## True when buying land has no budget limit (New sandbox, version 1 files).
func has_unlimited_budget() -> bool:
	return _land_budget == UNLIMITED_BUDGET


## E5-S3: counts decor writes (set_decor). Not saved, not part of the content.
var decor_revision: int:
	get:
		return _decor_revision


## E5-S3: the decor kind on tile (x, y), NO_DECOR when none.
func decor_at(x: int, y: int) -> int:
	return int(_decor.get(Vector2i(x, y), NO_DECOR))


## E5-S3: every tile with decor, sorted by y then x.
func decor_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in _decor:
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## True when the course has a clubhouse (D60).
func has_clubhouse() -> bool:
	return _clubhouse != NO_CLUBHOUSE


## The clubhouse's tiles, row-major (empty when there is none). They may run off the map only
## in a hand-made file; the builder and the placement rule keep them on it.
func clubhouse_cells() -> Array[Vector2i]:
	return footprint_cells(_clubhouse) if has_clubhouse() else [] as Array[Vector2i]


## The CLUBHOUSE_SIZE x CLUBHOUSE_SIZE tiles round `centre`, row-major.
static func footprint_cells(centre: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r: int = CLUBHOUSE_REACH
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			out.append(centre + Vector2i(dx, dy))
	return out


## True when tile (x, y) is under the clubhouse.
func is_clubhouse(x: int, y: int) -> bool:
	if not has_clubhouse():
		return false
	var r: int = CLUBHOUSE_REACH
	return absi(x - _clubhouse.x) <= r and absi(y - _clubhouse.y) <= r


## The tile just outside the clubhouse's door, where guests come out and go in (D60);
## NO_CLUBHOUSE when there is none.
func clubhouse_door() -> Vector2i:
	if not has_clubhouse():
		return NO_CLUBHOUSE
	return door_of(_clubhouse, _clubhouse_facing)


## The door tile of a clubhouse centred on `centre` facing `facing`.
static func door_of(centre: Vector2i, facing: int) -> Vector2i:
	return centre + FACINGS[posmod(facing, FACINGS.size())] * (CLUBHOUSE_REACH + 1)


## The name the map and the hole list give the hole in slot `slot` (E3-S27): its number, or
## when other holes share it (a loaded file; validator rule 1 fails them) its number and a
## letter by course order, "4a", "4b", so two tees marked 4 are told apart. "" for no slot.
func hole_label(slot: int) -> String:
	if slot < 0 or slot >= _holes.size():
		return ""
	var number: int = _holes[slot].number
	var before: int = 0
	var shared: bool = false
	for i: int in _holes.size():
		if i != slot and _holes[i].number == number:
			shared = true
			if i < slot:
				before += 1
	if not shared:
		return str(number)
	return "%d%s" % [number, char("a".unicode_at(0) + mini(before, 25))]


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
	c._clubhouse = _clubhouse
	c._clubhouse_facing = _clubhouse_facing
	c._decor = _decor.duplicate()
	c._replace_holes(_holes)
	return c


## Course format version 3 dictionary, ready for JSON.stringify.
func to_dict() -> Dictionary:
	var hole_dicts: Array = []
	for h in _holes:
		hole_dicts.append(h.to_dict())
	var out := {
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
		"clubhouse": null if not has_clubhouse() else {
			"x": _clubhouse.x, "y": _clubhouse.y, "facing": FACING_NAMES[_clubhouse_facing],
		},
	}
	if not _decor.is_empty():
		var items: Array = []
		for cell: Vector2i in decor_cells():
			items.append([cell.x, cell.y, _decor[cell]])
		out["decor"] = items
	return out


# --- write (course/builder.gd and course/save.gd only) ---

func set_tile(x: int, y: int, tile_height: int, surface: Surface.Type) -> void:
	assert(in_bounds(x, y), "tile out of bounds")
	assert(tile_height >= 0 and tile_height <= MAX_HEIGHT, "height out of range")
	assert(Surface.is_valid(surface), "surface out of range")
	var i: int = _index(x, y)
	var was: int = _tiles[i]
	if (was >> 4) != tile_height:
		_height_revision += 1
	if (was & 0x0F) != surface:
		_surface_revisions[was & 0x0F] += 1
		_surface_revisions[surface] += 1
	_tiles[i] = _pack(tile_height, surface)
	_revision += 1


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
	var v: int = 1 if owned else 0
	if _owned[_parcel_index(p)] != v:
		_land_revision += 1
	_owned[_parcel_index(p)] = v
	_revision += 1


## Sets the balance (the land budget, D57): whole dollars, below 0 allowed (E4-S2), or
## UNLIMITED_BUDGET.
func set_land_budget(budget: int) -> void:
	assert(budget > UNLIMITED_BUDGET or budget == UNLIMITED_BUDGET, "balance out of range")
	_land_budget = budget


## Puts the clubhouse's centre on `centre` facing `facing` (an index into FACINGS), or removes
## it with NO_CLUBHOUSE. Where it may stand is the builder's rule (CourseBuilder.clubhouse_refusal).
func set_clubhouse(centre: Vector2i, facing: int) -> void:
	assert(facing >= 0 and facing < FACINGS.size(), "facing out of range")
	if centre == _clubhouse and facing == _clubhouse_facing:
		return
	_clubhouse = centre
	_clubhouse_facing = facing
	_clubhouse_revision += 1


## E5-S3: puts decor of `kind` (an index into DECOR_KINDS) on `cell`, or clears it with
## NO_DECOR. Where it may stand is the builder's rule (CourseBuilder.decor_refusal).
func set_decor(cell: Vector2i, kind: int) -> void:
	assert(in_bounds(cell.x, cell.y), "decor off the map")
	assert(kind == NO_DECOR or (kind >= 0 and kind < DECOR_KINDS.size()), "decor kind out of range")
	if decor_at(cell.x, cell.y) == kind:
		return
	if kind == NO_DECOR:
		_decor.erase(cell)
	else:
		_decor[cell] = kind
	_decor_revision += 1


# --- load ---

## Parses a course format version 3 dictionary (as from JSON.parse_string; course/save.gd
## migrates older versions first). Returns null and appends a reason per problem to `errors`
## when the data is malformed: wrong version, bad size, tiles not width*height bytes, height
## above MAX_HEIGHT, unknown surface, owned rows not one "0" or "1" per parcel, a land budget
## that is not null or a whole number of 0 or more, a clubhouse that is not null or
## {"x", "y", "facing"} with its footprint and door on the map, malformed hole, or a tee/cup
## off the map.
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
		# A balance may be below 0 (E4-S2), never as low as the unlimited marker.
		if errors.size() == start and budget <= UNLIMITED_BUDGET:
			errors.append("land_budget must be whole dollars, or null, got %d" % budget)
	if errors.size() > start:
		return null
	var house := _read_clubhouse(data, w, h, errors)
	var decor := _read_decor(data, w, h, errors)
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
	c._clubhouse = house[0]
	c._clubhouse_facing = house[1]
	c._decor = decor
	c._replace_holes(parsed_holes)
	return c


## Reads the optional "decor" field (E5-S3): a list of [x, y, kind] on the map, one per tile.
static func _read_decor(data: Dictionary, w: int, h: int, errors: Array[String]) -> Dictionary:
	var out := {}
	if not data.has("decor"):
		return out
	var v: Variant = data["decor"]
	if typeof(v) != TYPE_ARRAY:
		errors.append("decor must be a list of [x, y, kind]")
		return out
	for item: Variant in v:
		if typeof(item) != TYPE_ARRAY or (item as Array).size() != 3:
			errors.append("decor: each item must be [x, y, kind]")
			continue
		var a: Array = item
		var nums: Array[int] = []
		for k: int in 3:
			if typeof(a[k]) == TYPE_INT or (typeof(a[k]) == TYPE_FLOAT and float(a[k]) == floorf(a[k])):
				nums.append(int(a[k]))
		if nums.size() != 3:
			errors.append("decor: %s must be three whole numbers" % [a])
			continue
		if nums[0] < 0 or nums[1] < 0 or nums[0] >= w or nums[1] >= h:
			errors.append("decor: (%d, %d) off the %dx%d map" % [nums[0], nums[1], w, h])
		elif nums[2] < 0 or nums[2] >= DECOR_KINDS.size():
			errors.append("decor: kind %d unknown (0 to %d)" % [nums[2], DECOR_KINDS.size() - 1])
		elif out.has(Vector2i(nums[0], nums[1])):
			errors.append("decor: two on (%d, %d)" % [nums[0], nums[1]])
		else:
			out[Vector2i(nums[0], nums[1])] = nums[2]
	return out


## Reads the "clubhouse" field (version 3): [centre, facing], [NO_CLUBHOUSE, 1] for null.
static func _read_clubhouse(data: Dictionary, w: int, h: int, errors: Array[String]) -> Array:
	if not data.has("clubhouse"):
		errors.append("clubhouse is missing (null for none)")
		return [NO_CLUBHOUSE, 1]
	var v: Variant = data["clubhouse"]
	if v == null:
		return [NO_CLUBHOUSE, 1]
	if typeof(v) != TYPE_DICTIONARY:
		errors.append("clubhouse must be an object or null")
		return [NO_CLUBHOUSE, 1]
	var d: Dictionary = v
	var start := errors.size()
	var x := read_int(d, "x", errors, "clubhouse")
	var y := read_int(d, "y", errors, "clubhouse")
	var facing: int = FACING_NAMES.find(str(d.get("facing", "")))
	if facing < 0:
		errors.append("clubhouse: facing must be one of %s" % ", ".join(FACING_NAMES))
	if errors.size() > start:
		return [NO_CLUBHOUSE, 1]
	var r: int = CLUBHOUSE_REACH
	var door := door_of(Vector2i(x, y), facing)
	if x - r < 0 or y - r < 0 or x + r >= w or y + r >= h or door.x < 0 or door.y < 0 \
			or door.x >= w or door.y >= h:
		errors.append("clubhouse: (%d, %d) facing %s is not on the %dx%d map with its door"
				% [x, y, FACING_NAMES[facing], w, h])
		return [NO_CLUBHOUSE, 1]
	return [Vector2i(x, y), facing]


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
