extends GutTest
## E1-S2: CourseData is the single source of truth, in course format version 1
## (.claude/skills/course-file/SKILL.md): base64 tiles, byte = (height << 4) | surface, 8 = oob.

const TMP_PATH := "user://test_course_data_roundtrip_%d.json"


## A 20x20 course that uses every surface and every height, plus two holes.
func _make_course() -> CourseData:
	var c := CourseData.create(20, 20)
	for y in 20:
		for x in 20:
			c.set_tile(x, y, (x + y) % (CourseData.MAX_HEIGHT + 1), ((x * 3 + y) % Surface.COUNT) as Surface.Type)
	c.set_info("Round Trip", "tests", "")
	var h1 := HoleData.new(1, 3, Vector2i(2, 2), Vector2i(17, 3), true)
	var h2 := HoleData.new(2, 4, Vector2i(1, 18), Vector2i(19, 0), false)
	c.set_holes([h1, h2])
	return c


func _assert_same_course(a: CourseData, b: CourseData) -> void:
	assert_eq(b.width, a.width, "width")
	assert_eq(b.height, a.height, "height")
	var mismatches := 0
	for y in a.height:
		for x in a.width:
			if a.get_height(x, y) != b.get_height(x, y) or a.get_surface(x, y) != b.get_surface(x, y):
				mismatches += 1
	assert_eq(mismatches, 0, "every tile survives")
	assert_eq(b.holes.size(), a.holes.size(), "hole count")
	for i in a.holes.size():
		assert_eq(b.holes[i].to_dict(), a.holes[i].to_dict(), "hole %d" % i)
	assert_eq(b.course_name, a.course_name)
	assert_eq(b.author, a.author)
	assert_eq(b.content_hash(), a.content_hash(), "hash")


func _decode(dict: Dictionary) -> CourseData:
	var errors: Array[String] = []
	var c := CourseData.from_dict(dict, errors)
	assert_not_null(c, "loads: %s" % [errors])
	return c


func _rejected(dict: Dictionary, needle: String) -> void:
	var errors: Array[String] = []
	var c := CourseData.from_dict(dict, errors)
	assert_null(c, "rejected")
	assert_gt(errors.size(), 0, "says why")
	assert_string_contains(" ".join(errors), needle)


func _tiles_dict(width: int, height: int, bytes: PackedByteArray) -> Dictionary:
	return {
		"version": 1, "name": "", "author": "", "width": width, "height": height,
		"tiles": Marshalls.raw_to_base64(bytes), "holes": [], "thumbnail": "",
	}


# --- shape and packing ---

func test_create_fills_and_reports_size() -> void:
	var c := CourseData.create(7, 5, Surface.Type.FAIRWAY, 2)
	assert_eq(c.width, 7)
	assert_eq(c.height, 5)
	assert_eq(c.get_surface(6, 4), Surface.Type.FAIRWAY)
	assert_eq(c.get_height(0, 0), 2)
	assert_eq(c.holes.size(), 0)


func test_set_tile_is_read_back() -> void:
	var c := CourseData.create(4, 4)
	c.set_tile(3, 1, 6, Surface.Type.BUNKER)
	assert_eq(c.get_height(3, 1), 6)
	assert_eq(c.get_surface(3, 1), Surface.Type.BUNKER)
	assert_eq(c.get_surface(1, 3), Surface.Type.ROUGH, "neighbour untouched")


func test_byte_packing_matches_format() -> void:
	var c := CourseData.create(2, 1)
	c.set_tile(0, 0, 3, Surface.Type.OOB)
	c.set_tile(1, 0, 7, Surface.Type.WATER)
	var bytes := Marshalls.base64_to_raw(c.to_dict()["tiles"])
	assert_eq(bytes.size(), 2)
	assert_eq(bytes[0], (3 << 4) | 8, "oob is surface 8")
	assert_eq(bytes[1], (7 << 4) | 5)


func test_tiles_are_row_major() -> void:
	var bytes := PackedByteArray([0, 1, 2, 3, 4, 5])  # 3 wide, 2 tall
	var c := _decode(_tiles_dict(3, 2, bytes))
	assert_eq(c.get_surface(2, 0), 2)
	assert_eq(c.get_surface(0, 1), 3)


func test_surface_enum_matches_format() -> void:
	assert_eq(Surface.COUNT, 9)
	assert_eq(Surface.Type.FAIRWAY, 0)
	assert_eq(Surface.Type.CART_PATH, 7)
	assert_eq(Surface.Type.OOB, 8)
	assert_eq(Surface.name_of(Surface.Type.CART_PATH), "cart_path")
	assert_eq(Surface.from_name("oob"), Surface.Type.OOB)
	assert_eq(Surface.from_name("lava"), -1)


func test_in_bounds() -> void:
	var c := CourseData.create(3, 2)
	assert_true(c.in_bounds(2, 1))
	assert_false(c.in_bounds(3, 0))
	assert_false(c.in_bounds(0, -1))


func test_off_map_reads_are_oob_and_do_not_wrap() -> void:
	var c := CourseData.create(3, 2, Surface.Type.ROUGH, 2)
	c.set_tile(0, 1, 5, Surface.Type.WATER)
	c.set_tile(2, 0, 4, Surface.Type.BUNKER)
	# (3, 0) would wrap to (0, 1); (-1, 1) would wrap to (2, 0).
	for p: Vector2i in [Vector2i(3, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(0, 2),
			Vector2i(3, 1), Vector2i(-1, 0)]:
		assert_eq(c.get_height(p.x, p.y), 0, "height at %s" % p)
		assert_eq(c.get_surface(p.x, p.y), Surface.Type.OOB, "surface at %s" % p)


# --- round trip ---

func test_20x20_round_trips_through_json_text() -> void:
	var a := _make_course()
	var text := JSON.stringify(a.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_typeof(parsed, TYPE_DICTIONARY)
	var b := _decode(parsed)
	if b:
		_assert_same_course(a, b)


func test_to_dict_has_format_v1_keys() -> void:
	var d := _make_course().to_dict()
	for key in ["version", "name", "author", "width", "height", "tiles", "holes", "thumbnail"]:
		assert_has(d, key)
	assert_eq(d["version"], 1)
	assert_eq(d["holes"][0], {"number": 1, "par": 3, "tee": [2, 2], "cup": [17, 3], "open": true})


func test_round_trips_through_save_file() -> void:
	var a := _make_course()
	var path := TMP_PATH % OS.get_process_id()
	assert_eq(CourseSave.save_file(a, path), OK)
	var errors: Array[String] = []
	var b := CourseSave.load_file(path, errors)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_not_null(b, "loads: %s" % [errors])
	if b:
		_assert_same_course(a, b)


func test_load_missing_file_reports_error() -> void:
	var errors: Array[String] = []
	assert_null(CourseSave.load_file("user://no_such_course.json", errors))
	assert_gt(errors.size(), 0)


func test_copy_is_independent() -> void:
	var a := _make_course()
	var b := a.copy()
	assert_eq(b.content_hash(), a.content_hash())
	b.set_tile(0, 0, 7, Surface.Type.GREEN)
	assert_ne(b.content_hash(), a.content_hash())
	assert_eq(a.get_height(0, 0), 0, "original untouched")


# --- hash ---

func test_hash_is_stable_and_sensitive() -> void:
	var a := _make_course()
	var b := _make_course()
	assert_eq(a.content_hash(), b.content_hash(), "same content, same hash")
	b.set_tile(5, 5, (b.get_height(5, 5) + 1) % 8, b.get_surface(5, 5))
	assert_ne(a.content_hash(), b.content_hash(), "height change")
	var c := _make_course()
	c.set_holes([HoleData.new(1, 3, Vector2i(2, 2), Vector2i(17, 4), true)])
	assert_ne(a.content_hash(), c.content_hash(), "hole change")


# --- rejection on load ---

func test_rejects_height_above_seven() -> void:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes[2] = (8 << 4) | Surface.Type.FAIRWAY
	_rejected(_tiles_dict(2, 2, bytes), "height 8")


func test_rejects_height_fifteen() -> void:
	var bytes := PackedByteArray([0, 0xF0, 0, 0])
	_rejected(_tiles_dict(2, 2, bytes), "height 15")


func test_rejects_unknown_surface() -> void:
	var bytes := PackedByteArray([0, 0, 9, 0])
	_rejected(_tiles_dict(2, 2, bytes), "surface 9")


func test_rejects_wrong_tile_count() -> void:
	_rejected(_tiles_dict(3, 3, PackedByteArray([0, 0, 0, 0])), "tiles")


func test_rejects_empty_tiles() -> void:
	var d := _tiles_dict(1, 1, PackedByteArray([0]))
	d["tiles"] = ""
	_rejected(d, "tiles")


func test_rejects_wrong_version() -> void:
	var d := _tiles_dict(1, 1, PackedByteArray([0]))
	d["version"] = 2
	_rejected(d, "version")


func test_rejects_bad_size() -> void:
	_rejected(_tiles_dict(0, 1, PackedByteArray([0])), "width")


func test_rejects_hole_off_the_map() -> void:
	var d := _tiles_dict(2, 2, PackedByteArray([0, 0, 0, 0]))
	d["holes"] = [{"number": 1, "par": 3, "tee": [0, 0], "cup": [2, 0], "open": true}]
	_rejected(d, "cup")


func test_rejects_fractional_numbers() -> void:
	var d := _tiles_dict(2, 2, PackedByteArray([0, 0, 0, 0]))
	d["width"] = 2.5
	_rejected(d, "width")


func test_accepts_json_floats_for_integers() -> void:
	var d := _tiles_dict(2, 2, PackedByteArray([0x12, 0, 0, 0]))
	d["width"] = 2.0
	d["holes"] = [{"number": 1.0, "par": 3.0, "tee": [0.0, 0.0], "cup": [1.0, 1.0], "open": true}]
	var c := _decode(d)
	if c:
		assert_eq(c.get_height(0, 0), 1)
		assert_eq(c.get_surface(0, 0), Surface.Type.GREEN)
		assert_eq(c.holes[0].cup, Vector2i(1, 1))


func test_holes_list_is_read_only_to_readers() -> void:
	var c := _make_course()
	assert_true(c.holes.is_read_only())
