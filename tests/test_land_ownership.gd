extends GutTest
## E6-S3: CourseData holds parcel ownership and the land budget (D26), course format version 2
## saves them, course/save.gd loads a version 1 file fully owned, and only the builder buys a
## parcel: it must share an edge with owned land and fit the budget, a refusal names the rule,
## and a purchase is an undo step (D27, D28; docs/design.md Land).

const TMP_PATH := "user://test_land_ownership_%d.json"
const EXAMPLE_PATH := "res://courses/example_par3.json"
## The starting block of the 8 x 8 parcel map (D67, 4 x 4; D26's was parcels 3 and 4): parcels
## 2 to 5 on each axis.
const BLOCK: Rect2i = Rect2i(2, 2, 4, 4)


## The 128 x 128 map, flat rough at height 2 (every parcel $800 at D67's money scale 0.78; $650
## at E4-S8's 0.63, $600 at D57's 0.61), owning only the starting block, with the $5,000 land
## budget. Built with CourseData's setters, as a fixture.
func _land_course() -> CourseData:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), BLOCK.has_point(Vector2i(p, q)))
	c.set_land_budget(5000)
	return c


func _owned_parcels(c: CourseData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			if c.is_parcel_owned(Vector2i(p, q)):
				out.append(Vector2i(p, q))
	return out


func _all_owned(c: CourseData) -> bool:
	return _owned_parcels(c).size() == c.parcels_wide * c.parcels_high


# --- the parcel grid in CourseData ---

func test_the_128_map_is_8_by_8_parcels_of_16_tiles() -> void:
	var c := CourseData.create(128, 128)
	assert_eq(CourseData.PARCEL_TILES, 16, "D26")
	assert_eq(c.parcels_wide, 8)
	assert_eq(c.parcels_high, 8)
	assert_eq(c.parcel_of(0, 0), Vector2i(0, 0))
	assert_eq(c.parcel_of(15, 16), Vector2i(0, 1))
	assert_eq(c.parcel_of(32, 95), Vector2i(2, 5), "the starting block's tiles 32 to 95 (D67)")
	assert_eq(c.parcel_rect(Vector2i(2, 5)), Rect2i(32, 80, 16, 16))


func test_a_map_off_the_16_grid_has_partial_parcels() -> void:
	var c := CourseData.create(20, 40)
	assert_eq(c.parcels_wide, 2)
	assert_eq(c.parcels_high, 3)
	assert_eq(c.parcel_rect(Vector2i(1, 2)), Rect2i(16, 32, 4, 8), "clipped to the map")
	assert_eq(c.parcel_rect(Vector2i(2, 0)), Rect2i(), "off the map")
	assert_false(c.parcel_in_bounds(Vector2i(-1, 0)))


func test_a_new_course_owns_every_parcel_with_no_budget_limit() -> void:
	var c := CourseData.create(40, 40)
	assert_true(_all_owned(c), "as New sandbox (D10)")
	assert_true(c.has_unlimited_budget())
	assert_eq(c.land_budget, CourseData.UNLIMITED_BUDGET)
	assert_true(c.is_owned(39, 39))
	assert_false(c.is_owned(40, 0), "off the map is never owned")
	assert_false(c.is_owned(-1, 5))


func test_tile_ownership_follows_its_parcel() -> void:
	var c := _land_course()
	assert_true(c.is_owned(32, 32))
	assert_true(c.is_owned(95, 95))
	assert_false(c.is_owned(31, 32), "one tile west of the block")
	assert_false(c.is_owned(96, 60))
	assert_false(c.is_parcel_owned(Vector2i(8, 0)), "a parcel off the map is not owned")
	assert_eq(c.land_budget, 5000)
	assert_false(c.has_unlimited_budget())


func test_ownership_and_budget_are_in_the_hash_and_the_copy() -> void:
	var a := _land_course()
	var b := a.copy()
	assert_eq(b.content_hash(), a.content_hash())
	assert_eq(_owned_parcels(b).size(), 16)
	b.set_parcel_owned(Vector2i(0, 0), true)
	assert_ne(b.content_hash(), a.content_hash(), "ownership changes the hash")
	assert_false(a.is_parcel_owned(Vector2i(0, 0)), "the copy is independent")
	var d := a.copy()
	d.set_land_budget(4999)
	assert_ne(d.content_hash(), a.content_hash(), "the budget changes the hash")


# --- prices (data/land.json, D28) ---

func test_prices_come_from_data_land_json() -> void:
	var lp := LandPrices.load_default()
	assert_eq(lp.land_budget, 5000, "D28")
	assert_eq(lp.base_price, 1000)
	assert_eq(lp.relief_step_price, 100)
	assert_eq(lp.tree_tile_price, -2, "a tree cleared to rough (D57)")
	assert_eq(lp.water_tile_price, -12, "a pond tile filled: rough and a step (D57)")
	assert_eq([lp.min_price, lp.max_price, lp.price_round], [500, 2000, 50])
	assert_almost_eq(lp.price_scale, 0.78, 1e-9, "the money scale (D56, D57, E4-S8 0.63, D67 0.78)")


func test_price_reads_relief_trees_and_water() -> void:
	var lp := LandPrices.load_default()
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	# Every price is D28's formula times price_scale 0.78 (D57, D67), clamped, then rounded to $50.
	assert_eq(lp.price(c, Vector2i(0, 0)), 800, "flat open rough: 1000 x 0.78 = 780")
	# The design's typical parcel: relief 2, 31 trees, 10 water: 1000 + 200 - 62 - 120 = 1018,
	# x 0.78 = 794, $800.
	c.set_tile(16, 0, 4, Surface.Type.ROUGH)
	for i: int in 31:
		c.set_tile(17 + i % 14, 1 + i / 14, 2, Surface.Type.TREES)
	for i: int in 10:
		c.set_tile(17 + i, 10, 2, Surface.Type.WATER)
	assert_eq(lp.price(c, Vector2i(1, 0)), 800)
	# A hill parcel: relief 5, 20 trees: 1460, x 0.78 = 1139, $1,150.
	c.set_tile(32, 0, 7, Surface.Type.ROUGH)
	for i: int in 20:
		c.set_tile(33 + i % 10, 2 + i / 10, 2, Surface.Type.TREES)
	assert_eq(lp.price(c, Vector2i(2, 0)), 1150)
	# All water clamps at the floor, 500 x 0.78 = 390, $400.
	for y: int in 16:
		for x: int in 16:
			c.set_tile(48 + x, y, 2, Surface.Type.WATER)
	assert_eq(lp.price(c, Vector2i(3, 0)), 400)


func test_money_is_written_with_thousands() -> void:
	assert_eq(LandPrices.money(5000), "$5,000")
	assert_eq(LandPrices.money(950), "$950")
	assert_eq(LandPrices.money(1234567), "$1,234,567")


# --- buying through the builder ---

func test_buy_a_parcel_next_to_owned_land() -> void:
	var c := _land_course()
	var b := CourseBuilder.new(c)
	watch_signals(b)
	assert_eq(b.parcel_price(Vector2i(6, 3)), 800)
	assert_eq(b.buy_refusal(Vector2i(6, 3)), "")
	assert_true(b.buy_parcel(Vector2i(6, 3)))
	assert_true(c.is_parcel_owned(Vector2i(6, 3)))
	assert_true(c.is_owned(96, 48), "its tiles are owned")
	assert_eq(c.land_budget, 4200, "the price comes off the budget")
	assert_signal_emitted_with_parameters(b, "land_changed", [Vector2i(6, 3)])
	assert_eq(b.undo_depth(), 1, "one undo step")
	assert_eq(b.buy_refusal(Vector2i(6, 3)), "already yours")
	assert_false(b.buy_parcel(Vector2i(6, 3)))
	assert_eq(c.land_budget, 4200, "buying an owned parcel again changes nothing")
	assert_true(b.buy_parcel(Vector2i(7, 3)), "the bought parcel is now land to grow from")


func test_refuse_a_parcel_not_next_to_owned_land() -> void:
	var c := _land_course()
	var b := CourseBuilder.new(c)
	var before := c.content_hash()
	for p: Vector2i in [Vector2i(7, 3), Vector2i(0, 0), Vector2i(6, 6), Vector2i(1, 1)]:
		assert_eq(b.buy_refusal(p), "not next to your land", "%s (a shared corner is not enough)" % p)
		assert_false(b.buy_parcel(p))
	assert_eq(c.content_hash(), before, "a refusal changes nothing")
	assert_eq(b.undo_depth(), 0, "and records nothing")
	assert_eq(b.buy_refusal(Vector2i(8, 3)), "no such parcel")
	assert_false(b.buy_parcel(Vector2i(-1, 3)))


func test_refuse_a_parcel_the_budget_cannot_pay_for() -> void:
	var c := _land_course()
	c.set_land_budget(750)
	var b := CourseBuilder.new(c)
	var before := c.content_hash()
	assert_eq(b.buy_refusal(Vector2i(1, 3)), "costs $800, you have $750")
	assert_false(b.buy_parcel(Vector2i(1, 3)))
	assert_eq(c.content_hash(), before)
	c.set_land_budget(800)
	assert_true(b.buy_parcel(Vector2i(1, 3)), "exactly the price is enough")
	assert_eq(c.land_budget, 0)
	assert_eq(b.buy_refusal(Vector2i(0, 3)), "costs $800, you have $0")


func test_five_thousand_buys_six_flat_parcels_and_no_more() -> void:
	# D67: $800 a flat parcel at the money scale 0.78 (seven at $650 before).
	var c := _land_course()
	var b := CourseBuilder.new(c)
	for p: Vector2i in [Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(1, 2),
			Vector2i(1, 3)]:
		assert_true(b.buy_parcel(p), str(p))
	assert_eq(c.land_budget, 200)
	assert_eq(b.buy_refusal(Vector2i(1, 4)), "costs $800, you have $200")


func test_undo_gives_the_parcel_up_and_the_price_back() -> void:
	var c := _land_course()
	var b := CourseBuilder.new(c)
	var before := c.content_hash()
	b.paint(Vector2i(50, 50), Surface.Type.FAIRWAY, 1)
	var after_paint := c.content_hash()
	assert_true(b.buy_parcel(Vector2i(4, 6)))
	watch_signals(b)
	assert_true(b.undo())
	assert_false(c.is_parcel_owned(Vector2i(4, 6)))
	assert_eq(c.land_budget, 5000 - b.economy.price_of(Surface.Type.FAIRWAY),
			"the price back; the paint stays paid for (E4-S2)")
	assert_eq(c.content_hash(), after_paint, "the purchase alone is undone")
	assert_signal_emitted_with_parameters(b, "land_changed", [Vector2i(4, 6)])
	assert_true(b.undo())
	assert_eq(c.content_hash(), before, "then the paint")


func test_an_unlimited_budget_buys_without_paying() -> void:
	var c := _land_course()
	c.set_land_budget(CourseData.UNLIMITED_BUDGET)
	var b := CourseBuilder.new(c)
	assert_true(b.buy_parcel(Vector2i(3, 1)))
	assert_true(c.has_unlimited_budget())
	assert_eq(b.buy_refusal(Vector2i(0, 0)), "not next to your land", "adjacency still holds")
	b.undo()
	assert_true(c.has_unlimited_budget())
	assert_false(c.is_parcel_owned(Vector2i(3, 1)))


# --- course format version 2, and version 1 files ---

func test_a_v1_file_loads_fully_owned() -> void:
	var text := FileAccess.get_file_as_string(EXAMPLE_PATH)
	var raw: Dictionary = JSON.parse_string(text)
	assert_eq(int(raw["version"]), 1, "courses/example_par3.json is a version 1 file")
	assert_false(raw.has("owned"))
	var errors: Array[String] = []
	var c := CourseSave.load_file(EXAMPLE_PATH, errors)
	assert_not_null(c, "loads: %s" % [errors])
	if c == null:
		return
	assert_true(_all_owned(c), "every parcel owned")
	assert_true(c.has_unlimited_budget(), "no budget limit, as New sandbox")
	assert_eq(c.to_dict()["version"], CourseData.FORMAT_VERSION, "it saves as the current version (3 since E5-S9)")


func test_a_v1_dictionary_migrates_and_v2_passes_through() -> void:
	var v1 := {"version": 1, "name": "", "author": "", "width": 20, "height": 33,
			"tiles": CourseData.create(20, 33).to_dict()["tiles"], "holes": [], "thumbnail": ""}
	var m := CourseSave.migrate(v1)
	assert_eq(m["version"], CourseData.FORMAT_VERSION, "on to the current version (3, E5-S9)")
	assert_eq(m["owned"], ["11", "11", "11"])
	assert_eq(m["land_budget"], null)
	assert_false(v1.has("owned"), "the input is not changed")
	var c := CourseSave.from_dict(v1)
	assert_not_null(c)
	if c:
		assert_true(_all_owned(c))
	var v3 := _land_course().to_dict()
	assert_eq(CourseSave.migrate(v3), v3, "the current version is unchanged")


func test_a_v2_round_trip_keeps_ownership_and_the_hash() -> void:
	var a := _land_course()
	var b := CourseBuilder.new(a)
	b.buy_parcel(Vector2i(6, 3))
	b.buy_parcel(Vector2i(4, 1))
	a.set_info("Land", "tests", "")
	var path := TMP_PATH % OS.get_process_id()
	assert_eq(CourseSave.save_file(a, path), OK)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var errors: Array[String] = []
	var loaded := CourseSave.load_file(path, errors)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(int(raw["version"]), CourseData.FORMAT_VERSION)
	assert_eq(raw["owned"][1], "00001000", "parcel row 1: only parcel 4")
	assert_eq(raw["owned"][3], "00111110")
	assert_eq(int(raw["land_budget"]), 3400, "what was left, not a fresh $5,000 (two $800 parcels)")
	assert_not_null(loaded, "loads: %s" % [errors])
	if loaded == null:
		return
	assert_eq(_owned_parcels(loaded), _owned_parcels(a))
	assert_eq(loaded.land_budget, 3400)
	assert_eq(loaded.content_hash(), a.content_hash())


func test_a_v2_sandbox_round_trip_keeps_the_unlimited_budget() -> void:
	var a := CourseData.create(30, 30)
	var text := CourseSave.to_json(a)
	assert_eq(JSON.parse_string(text)["land_budget"], null)
	var loaded := CourseSave.from_json(text)
	assert_not_null(loaded)
	if loaded:
		assert_true(loaded.has_unlimited_budget())
		assert_true(_all_owned(loaded))
		assert_eq(loaded.content_hash(), a.content_hash())


func _rejected(d: Dictionary, needle: String) -> void:
	var errors: Array[String] = []
	assert_null(CourseData.from_dict(d, errors), "rejected: %s" % needle)
	assert_string_contains(" ".join(errors), needle)


func test_v2_rejects_bad_ownership_and_budget() -> void:
	var good := CourseData.create(20, 20).to_dict()
	var d := good.duplicate(true)
	d["owned"] = ["11"]
	_rejected(d, "parcel rows")
	d = good.duplicate(true)
	d["owned"] = ["11", "1"]
	_rejected(d, "owned row 1")
	d = good.duplicate(true)
	d["owned"] = ["11", "1x"]
	_rejected(d, "owned row 1")
	d = good.duplicate(true)
	d.erase("owned")
	_rejected(d, "owned")
	d = good.duplicate(true)
	d["land_budget"] = CourseData.UNLIMITED_BUDGET
	_rejected(d, "land_budget")
	d = good.duplicate(true)
	d["land_budget"] = 10.5
	_rejected(d, "land_budget")
	d = good.duplicate(true)
	d.erase("land_budget")
	_rejected(d, "land_budget")
	d = good.duplicate(true)
	d["land_budget"] = -120
	var owing := CourseData.from_dict(d, [] as Array[String])
	assert_true(owing != null and owing.land_budget == -120, "a balance below 0 loads (E4-S2)")
	d = good.duplicate(true)
	d["land_budget"] = 2500.0
	var errors: Array[String] = []
	var c := CourseData.from_dict(d, errors)
	assert_not_null(c, "a JSON float budget is fine: %s" % [errors])
	if c:
		assert_eq(c.land_budget, 2500)


## D67: a save or course file from before the 4 x 4 block keeps exactly the land it owns: D26's
## 2 x 2 block (and what was bought) loads as owned, and nothing of the bigger block is added,
## whether the file is format version 2 or 3.
func test_an_old_file_keeps_the_land_it_owns() -> void:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	var d26 := Rect2i(3, 3, 2, 2)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), d26.has_point(Vector2i(p, q)) or Vector2i(p, q) == Vector2i(5, 3))
	c.set_land_budget(4350)
	var want := _owned_parcels(c)
	assert_eq(want.size(), 5)
	var v3 := c.to_dict()
	var v2 := v3.duplicate(true)
	v2["version"] = 2
	v2.erase("clubhouse")
	for d: Dictionary in [v2, v3]:
		var errors: Array[String] = []
		var loaded := CourseSave.from_dict(d, errors)
		assert_not_null(loaded, "version %d loads: %s" % [d["version"], errors])
		if loaded == null:
			continue
		assert_eq(_owned_parcels(loaded), want, "version %d: the same five parcels" % d["version"])
		assert_eq(loaded.land_budget, 4350, "and the balance")
		assert_false(loaded.is_owned(32, 32), "none of the 4 x 4 block is added")
