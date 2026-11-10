extends GutTest
## E5-S9 (D60): every course has one clubhouse, a 3x3 footprint with a facing, on owned land.
## A new course gets one by rule in its starting block; a course file from before format
## version 3 gets one by the same rule, else beside hole 1's tee. The Clubhouse tool moves it
## to any allowed spot, refusing water, tees, greens, holes' lines and unowned land with a
## one-line reason; undo moves it back; save and load keep it.

## The starting block of the 128 x 128 map (D26): tiles 48 to 79 on both axes.
const BLOCK := Rect2i(48, 48, 32, 32)
## The rule's spot in that block: the middle of its +y edge, the door on its last row.
const BLOCK_SPOT := Vector2i(64, 77)
const PLUS_Y: int = 1
const TMP_PATH := "user://test_clubhouse_%d.json"
const V1_SAVE := "res://tests/fixtures/save_v1_short_par4.json"

var _refusals: Array[String] = []
var _moves: int = 0


func before_each() -> void:
	_refusals.clear()
	_moves = 0


func _builder(c: CourseData) -> CourseBuilder:
	var b := CourseBuilder.new(c)
	b.refused.connect(func(reason: String) -> void: _refusals.append(reason))
	b.clubhouse_changed.connect(func() -> void: _moves += 1)
	return b


## The 128 x 128 map, flat rough at height 2, owning only the starting block, as a New
## course's land would be with no trees or ponds, with its clubhouse by rule.
func _land_course() -> CourseData:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), BLOCK.encloses(c.parcel_rect(Vector2i(p, q))))
	c.set_land_budget(5000)
	CourseBuilder.place_clubhouse_by_rule(c)
	return c


## `c`'s content as a format version 2 file: no clubhouse field.
func _as_v2(c: CourseData) -> Dictionary:
	var d := c.to_dict()
	d["version"] = 2
	d.erase("clubhouse")
	return d


# --- the rule ---

func test_the_format_is_version_3_and_saves_the_clubhouse() -> void:
	assert_eq(CourseData.FORMAT_VERSION, 3)
	var c := _land_course()
	var d := c.to_dict()
	assert_eq(d["version"], 3)
	assert_eq(d["clubhouse"], {"x": BLOCK_SPOT.x, "y": BLOCK_SPOT.y, "facing": "+y"})


func test_a_new_sandbox_gets_one_at_the_middle_of_the_blocks_near_edge() -> void:
	var c := CourseBuilder.new_sandbox()
	assert_true(c.has_clubhouse())
	assert_eq(c.clubhouse, BLOCK_SPOT)
	assert_eq(c.clubhouse_facing, PLUS_Y)
	assert_eq(c.clubhouse_door(), Vector2i(64, 79), "the door on the block's last row")
	assert_eq(c.clubhouse_cells().size(), 9)


func test_a_new_course_gets_one_in_its_starting_block_on_allowed_ground() -> void:
	for land_seed: int in [1, 7, 42]:
		var c := CourseBuilder.new_course(land_seed)
		assert_true(c.has_clubhouse(), "seed %d has a clubhouse" % land_seed)
		for cell: Vector2i in c.clubhouse_cells():
			assert_true(BLOCK.has_point(cell), "seed %d: %s in the starting block" % [land_seed, cell])
			assert_true(c.is_owned(cell.x, cell.y))
		assert_true(BLOCK.has_point(c.clubhouse_door()), "its door too")
		assert_eq(ClubhouseRule.refusal(c, c.clubhouse, c.clubhouse_facing, []), "")


func test_a_spot_in_the_block_nearest_the_middle_when_the_middle_is_water() -> void:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	c.set_tile(BLOCK_SPOT.x, BLOCK_SPOT.y, 2, Surface.Type.WATER)
	var spot: Array = ClubhouseRule.default_spot(c)
	assert_ne(spot[0], BLOCK_SPOT)
	assert_true(BLOCK.has_point(spot[0]))
	assert_eq((spot[0] as Vector2i).distance_to(BLOCK_SPOT), 2.0, "two tiles over, clear of the water")


func test_an_old_file_gets_one_by_the_same_rule() -> void:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	var errors: Array[String] = []
	var loaded := CourseSave.from_dict(_as_v2(c), errors)
	assert_not_null(loaded, "loads: %s" % [errors])
	if loaded == null:
		return
	assert_eq(loaded.clubhouse, BLOCK_SPOT)
	assert_eq(loaded.clubhouse_facing, PLUS_Y)
	assert_eq(loaded.to_dict()["version"], 3, "and saves as version 3")


func test_an_old_file_with_a_full_block_gets_one_beside_hole_1s_tee() -> void:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	for y: int in range(BLOCK.position.y, BLOCK.end.y):
		for x: int in range(BLOCK.position.x, BLOCK.end.x):
			c.set_tile(x, y, 1, Surface.Type.WATER)
	var tee := Vector2i(20, 100)
	for y: int in range(tee.y - 1, tee.y + 2):
		for x: int in range(tee.x - 1, tee.x + 2):
			c.set_tile(x, y, 2, Surface.Type.TEE)
	c.set_holes([HoleData.new(2, 3, Vector2i(100, 10), Vector2i(100, 40), false),
			HoleData.new(1, 3, tee, Vector2i(52 + 0, 100), false)])
	var loaded := CourseSave.from_dict(_as_v2(c))
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_true(loaded.has_clubhouse())
	var at: Vector2i = loaded.clubhouse
	assert_lte(maxi(absi(at.x - tee.x), absi(at.y - tee.y)), 4, "beside hole 1's tee, not hole 2's")
	assert_eq(loaded.clubhouse_facing, ClubhouseRule.facing_toward(at, tee), "its door toward the tee")
	assert_false(ClubhouseRule.crosses(PackedVector2Array([Vector2(tee), Vector2(52, 100)]), at),
			"off hole 1's line")
	assert_eq(ClubhouseRule.refusal(loaded, at, loaded.clubhouse_facing,
			ClubhouseRule.lines_of_play(loaded)), "")


func test_an_old_file_with_no_room_has_none() -> void:
	var c := CourseData.create(20, 20, Surface.Type.WATER, 1)
	var loaded := CourseSave.from_dict(_as_v2(c))
	assert_not_null(loaded)
	if loaded:
		assert_false(loaded.has_clubhouse())
		assert_eq(loaded.to_dict()["clubhouse"], null)


func test_an_old_game_save_loads_with_a_clubhouse() -> void:
	var errors: Array[String] = []
	var s := GameSave.from_json(FileAccess.get_file_as_string(V1_SAVE), errors)
	assert_not_null(s, "loads: %s" % [errors])
	if s:
		assert_true(s.course.has_clubhouse(), "a save from before E5-S9 gets one by rule")


# --- the tool ---

func test_a_move_is_free_and_undo_moves_it_back() -> void:
	var c := _land_course()
	var b := _builder(c)
	var money: int = b.balance()
	var to := Vector2i(55, 55)
	assert_eq(b.clubhouse_refusal(to, PLUS_Y), "")
	assert_true(b.move_clubhouse(to, 2))
	assert_eq(c.clubhouse, to)
	assert_eq(c.clubhouse_facing, 2)
	assert_eq(b.balance(), money, "free (D60)")
	assert_eq(_moves, 1)
	assert_false(b.move_clubhouse(to, 2), "already there")
	assert_true(b.undo())
	assert_eq(c.clubhouse, BLOCK_SPOT, "undo moves it back")
	assert_eq(c.clubhouse_facing, PLUS_Y)
	assert_eq(_moves, 2)
	assert_eq(_refusals, [] as Array[String])


func test_moves_are_refused_with_a_one_line_reason() -> void:
	var c := _land_course()
	c.set_tile(60, 60, 1, Surface.Type.WATER)
	c.set_tile(70, 60, 2, Surface.Type.TEE)
	c.set_tile(70, 70, 2, Surface.Type.GREEN)
	c.set_holes([HoleData.new(1, 3, Vector2i(50, 52), Vector2i(76, 52), false),
			HoleData.new(2, 3, Vector2i(52, 70), Vector2i(52, 66), false)])
	var b := _builder(c)
	var before := c.content_hash()
	var cases: Array = [
		[Vector2i(60, 61), "not on water"],
		[Vector2i(71, 60), "not on a tee"],
		[Vector2i(70, 71), "not on a green"],
		[Vector2i(52, 69), "not on a tee"],  # hole 2's tee marker on rough
		[Vector2i(52, 65), "not on a green"],  # hole 2's cup
		[Vector2i(48, 60), "not your land"],  # its west column off the block
		[Vector2i(64, 52), "in the way of hole 1"],
		[Vector2i(1, 1), "not your land"],
		[Vector2i(0, 60), "off the map"],
		[Vector2i(64, 126), "off the map"],  # the door below the map's last row
	]
	for k: Array in cases:
		var why: String = b.clubhouse_refusal(k[0], PLUS_Y)
		assert_eq(why, k[1], "at %s" % k[0])
		assert_false(b.move_clubhouse(k[0], PLUS_Y))
	assert_eq(_refusals.size(), cases.size(), "each refusal said once")
	assert_eq(c.content_hash(), before, "nothing changed")
	assert_false(b.can_undo())


func test_its_tiles_take_no_paint_no_ground_and_no_tee_or_cup() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_eq(b.edit_refusal(BLOCK_SPOT, 3), "the clubhouse is here")
	assert_false(b.paint(BLOCK_SPOT, Surface.Type.FAIRWAY, 3))
	assert_false(b.raise(BLOCK_SPOT, 3))
	assert_eq(_refusals, ["the clubhouse is here", "the clubhouse is here"] as Array[String])
	assert_true(b.paint(BLOCK_SPOT, Surface.Type.FAIRWAY, 5), "a bigger brush paints round it")
	for cell: Vector2i in c.clubhouse_cells():
		assert_eq(c.get_surface(cell.x, cell.y), Surface.Type.ROUGH, "%s untouched" % cell)
	assert_eq(c.get_surface(BLOCK_SPOT.x + 2, BLOCK_SPOT.y), Surface.Type.FAIRWAY)
	_refusals.clear()
	assert_eq(b.place_refusal(BLOCK_SPOT + Vector2i(1, 1), 1, true), "the clubhouse is here")
	assert_false(b.place_tee(1, BLOCK_SPOT + Vector2i(1, 1)))
	assert_eq(b.hole(1), null, "no hole made")
	assert_eq(_refusals, ["the clubhouse is here"] as Array[String])


func test_a_tee_or_cup_whose_line_runs_through_it_is_refused() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_true(b.place_tee(1, Vector2i(55, BLOCK_SPOT.y)))
	_refusals.clear()
	var across := Vector2i(75, BLOCK_SPOT.y)
	assert_eq(b.place_refusal(across, 1, false), "the clubhouse is in the way")
	assert_false(b.place_cup(1, across))
	assert_eq(_refusals, ["the clubhouse is in the way"] as Array[String])
	assert_true(b.place_cup(1, Vector2i(75, 60)), "a cup off the line is fine")


func test_the_tool_moves_it_and_turns_it_in_place() -> void:
	var c := _land_course()
	var b := _builder(c)
	var tool := BuildTool.new()
	add_child_autofree(tool)
	tool.builder = b
	tool.select_tool(BuildTool.Tool.CLUBHOUSE)
	tool._apply(Vector2i(58, 58))
	assert_eq(c.clubhouse, Vector2i(58, 58), "a click moves it there")
	assert_eq(c.clubhouse_facing, PLUS_Y, "keeping its facing")
	assert_true(tool.turn_clubhouse())
	assert_eq(c.clubhouse_facing, 2, "a quarter turn")
	assert_eq(c.clubhouse, Vector2i(58, 58))
	assert_true(tool.undo())
	assert_eq(c.clubhouse_facing, PLUS_Y)


# --- save and load ---

func test_save_and_load_keep_it() -> void:
	var c := _land_course()
	var b := _builder(c)
	b.move_clubhouse(Vector2i(70, 56), 3)
	var path := TMP_PATH % OS.get_process_id()
	assert_eq(CourseSave.save_file(c, path), OK)
	var errors: Array[String] = []
	var loaded := CourseSave.load_file(path, errors)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_not_null(loaded, "loads: %s" % [errors])
	if loaded == null:
		return
	assert_eq(loaded.clubhouse, Vector2i(70, 56))
	assert_eq(loaded.clubhouse_facing, 3)
	assert_eq(loaded.content_hash(), c.content_hash())
	assert_eq(c.copy().clubhouse, Vector2i(70, 56), "copy keeps it")


func test_a_malformed_clubhouse_does_not_load() -> void:
	var d := _land_course().to_dict()
	var bad: Array = [
		[{"x": 64, "y": 77, "facing": "up"}, "facing"],
		[{"x": 64, "facing": "+y"}, "clubhouse: y"],
		[{"x": 0, "y": 77, "facing": "+y"}, "not on the"],
		[{"x": 64, "y": 126, "facing": "+y"}, "not on the"],
		["here", "clubhouse must be"],
	]
	for k: Array in bad:
		var e := d.duplicate()
		e["clubhouse"] = k[0]
		var errors: Array[String] = []
		assert_null(CourseData.from_dict(e, errors), "%s refused" % [k[0]])
		assert_true(errors.size() == 1 and errors[0].contains(k[1]), "%s: %s" % [k[0], errors])
	var missing := d.duplicate()
	missing.erase("clubhouse")
	var errors: Array[String] = []
	assert_null(CourseData.from_dict(missing, errors), "a version 3 file names its clubhouse, or null")
	var none := d.duplicate()
	none["clubhouse"] = null
	var c := CourseData.from_dict(none)
	assert_not_null(c)
	if c:
		assert_false(c.has_clubhouse())
