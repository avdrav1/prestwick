extends GutTest
## E6-S4: the builder edits only owned land (D26, D30; docs/design.md Land). Painting,
## raising, lowering and placing a tee or cup on a tile the player does not own does nothing
## and says why; a brush that straddles the line edits only the owned tiles. A hole whose tee
## or cup stands on unowned land fails rule 6 and closes; rule 3 counts unowned land as OB.

## The starting block of the 8 x 8 parcel map (D26): parcels 3 and 4 on each axis, tiles 48
## to 79.
const BLOCK: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]
## A tile on each side of the block's west edge (x 47 | 48).
const OUTSIDE := Vector2i(47, 60)
const INSIDE := Vector2i(48, 60)
## The 160 yd par 3 of docs/design.md Land's hand calculation, block tiles (0, 12) to (31, 20).
const TEE := Vector2i(48, 60)
const CUP := Vector2i(79, 68)

var _refusals: Array[String] = []


func before_each() -> void:
	_refusals.clear()


## The 128 x 128 map, flat rough at height 2, owning only the starting block, $5,000 left.
func _land_course() -> CourseData:
	var c := CourseData.create(128, 128, Surface.Type.ROUGH, 2)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), Vector2i(p, q) in BLOCK)
	c.set_land_budget(5000)
	return c


func _builder(c: CourseData) -> CourseBuilder:
	var b := CourseBuilder.new(c)
	b.refused.connect(func(reason: String) -> void: _refusals.append(reason))
	return b


func _rules(issues: Array) -> Array[int]:
	var out: Array[int] = []
	for i: CourseValidator.Issue in issues:
		out.append(i.rule)
	return out


# --- terrain edits ---

func test_painting_unowned_land_does_nothing_and_says_why() -> void:
	var c := _land_course()
	var b := _builder(c)
	var before := c.content_hash()
	assert_eq(b.edit_refusal(OUTSIDE, 1), "not your land")
	assert_false(b.paint(OUTSIDE, Surface.Type.FAIRWAY, 1))
	assert_eq(c.content_hash(), before, "nothing changed")
	assert_false(b.can_undo(), "no undo step")
	assert_eq(_refusals, ["not your land"] as Array[String], "the builder says why")


func test_raising_and_lowering_unowned_land_do_nothing_and_say_why() -> void:
	var c := _land_course()
	var b := _builder(c)
	# Far enough out that a 5 x 5 brush (x 38 to 42) is all unowned.
	var far := Vector2i(40, 60)
	assert_false(b.raise(far, 3))
	assert_false(b.lower(far, 5))
	assert_eq(c.get_height(far.x, far.y), 2)
	assert_false(b.can_undo())
	assert_eq(_refusals.size(), 2)
	for r: String in _refusals:
		assert_eq(r, "not your land")


func test_editing_owned_land_says_nothing() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_eq(b.edit_refusal(INSIDE, 1), "")
	assert_true(b.paint(INSIDE, Surface.Type.FAIRWAY, 1))
	assert_true(b.raise(INSIDE, 1))
	assert_eq(_refusals, [] as Array[String])


func test_a_brush_straddling_the_line_edits_only_owned_tiles() -> void:
	var c := _land_course()
	var b := _builder(c)
	# A 5 x 5 brush on x 46..50: columns 46 and 47 are unowned, 48 to 50 owned.
	var at := Vector2i(48, 60)
	assert_eq(b.edit_refusal(at, 5), "", "some of it is owned")
	assert_true(b.paint(at, Surface.Type.BUNKER, 5))
	assert_true(b.raise(at, 5))
	for y: int in range(58, 63):
		for x: int in range(46, 51):
			var owned: bool = x >= 48
			assert_eq(c.get_surface(x, y), Surface.Type.BUNKER if owned else Surface.Type.ROUGH,
					"surface at (%d, %d)" % [x, y])
			assert_eq(c.get_height(x, y), 3 if owned else 2, "height at (%d, %d)" % [x, y])
	assert_eq(_refusals, [] as Array[String], "a straddling brush is not refused")
	b.undo()
	b.undo()
	assert_eq(c.content_hash(), _land_course().content_hash(), "undo puts the owned tiles back")


func test_a_brush_straddling_a_corner_edits_only_the_owned_quarter() -> void:
	var c := _land_course()
	var b := _builder(c)
	# The block's north-west corner tile (48, 48); a 3 x 3 brush there covers 47..49.
	assert_true(b.lower(Vector2i(48, 48), 3))
	var lowered: int = 0
	for y: int in range(47, 50):
		for x: int in range(47, 50):
			if c.get_height(x, y) == 1:
				lowered += 1
				assert_true(c.is_owned(x, y))
	assert_eq(lowered, 4, "the 2 x 2 owned quarter")


func test_a_stroke_across_the_line_edits_the_owned_side() -> void:
	var c := _land_course()
	var b := _builder(c)
	b.begin_stroke()
	for x: int in range(44, 52):
		b.paint(Vector2i(x, 60), Surface.Type.CART_PATH, 1)
	b.end_stroke()
	for x: int in range(44, 52):
		assert_eq(c.get_surface(x, 60), Surface.Type.CART_PATH if x >= 48 else Surface.Type.ROUGH)
	assert_eq(b.undo_depth(), 1, "one step for the drag")
	assert_eq(_refusals.size(), 4, "each unowned dab says why")


func test_bought_land_can_be_edited() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_true(b.buy_parcel(c.parcel_of(OUTSIDE.x, OUTSIDE.y)))
	assert_eq(b.edit_refusal(OUTSIDE, 1), "")
	assert_true(b.paint(OUTSIDE, Surface.Type.FAIRWAY, 1))
	assert_eq(_refusals, [] as Array[String])


func test_the_sandbox_edits_everywhere() -> void:
	var c := CourseBuilder.new_sandbox()
	var b := _builder(c)
	b.level_water = false  # D66: water as a plain paint here, not a flood
	assert_true(b.paint(Vector2i(0, 0), Surface.Type.WATER, 3))
	assert_true(b.place_tee(1, Vector2i(127, 127), 3))
	assert_eq(_refusals, [] as Array[String])


func test_an_off_map_brush_is_not_a_land_refusal() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_eq(b.edit_refusal(Vector2i(-10, -10), 1), "", "nothing under the brush to refuse")
	assert_false(b.paint(Vector2i(-10, -10), Surface.Type.FAIRWAY, 1))
	assert_eq(_refusals, [] as Array[String])


# --- tee and cup ---

func test_placing_a_tee_or_cup_on_unowned_land_does_nothing_and_says_why() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_eq(b.place_refusal(OUTSIDE), "not your land")
	assert_eq(b.place_refusal(INSIDE), "")
	assert_false(b.place_tee(1, OUTSIDE, 3))
	assert_false(b.place_cup(1, OUTSIDE, 3))
	assert_eq(c.holes.size(), 0, "no hole made")
	assert_false(b.can_undo())
	assert_eq(_refusals, ["not your land", "not your land"] as Array[String])


func test_moving_a_tee_onto_unowned_land_leaves_it_where_it_was() -> void:
	var c := _land_course()
	var b := _builder(c)
	assert_true(b.place_tee(1, TEE, 3))
	assert_false(b.place_tee(1, OUTSIDE))
	assert_eq(b.hole(1).tee, TEE)
	assert_eq(b.undo_depth(), 1)


func test_the_160_yd_par3_fits_the_starting_block() -> void:
	var c := _land_course()
	var b := _builder(c)
	b.paint(CUP, Surface.Type.GREEN, 3)
	assert_true(b.place_tee(1, TEE, 3))
	assert_true(b.place_cup(1, CUP))
	assert_eq(CourseValidator.yardage(TEE, CUP), 160)
	assert_eq(b.issues_for(1), [] as Array[CourseValidator.Issue], "D30: the footprint need not be owned")
	assert_true(b.hole(1).open, "it opens itself (E8-S1)")


# --- rule 6 and rule 3 through the builder ---

func test_a_loaded_open_hole_on_unowned_land_closes_with_rule_6() -> void:
	var c := _land_course()
	c.set_tile(60, 60, 2, Surface.Type.GREEN)
	c.set_holes([HoleData.new(1, 3, OUTSIDE + Vector2i(-10, 0), Vector2i(60, 60), true)])
	var b := _builder(c)
	assert_false(b.hole(1).open, "closed at once")
	var rules := _rules(b.issues_for(1))
	assert_true(6 in rules, "tee on unowned land: %s" % [rules])
	assert_true(3 in rules, "and its path starts on unowned land")
	for i: CourseValidator.Issue in b.issues_for(1):
		if i.rule == 6:
			assert_eq(i.tile, OUTSIDE + Vector2i(-10, 0), "the tee tile is highlighted")


func test_undoing_the_purchase_under_a_hole_fails_rule_6() -> void:
	var c := _land_course()
	var b := _builder(c)
	var parcel: Vector2i = c.parcel_of(OUTSIDE.x, OUTSIDE.y)
	assert_true(b.buy_parcel(parcel))
	# A hole placed on the bought land by a file edit after the purchase (the builder's own
	# tee would be undone first): the purchase's undo gives the land up under it.
	c.set_tile(60, 60, 2, Surface.Type.GREEN)
	c.set_holes([HoleData.new(1, 3, Vector2i(40, 60), Vector2i(60, 60), true)])
	assert_true(b.undo())
	assert_false(c.is_parcel_owned(parcel))
	assert_false(b.hole(1).open, "the hole on given-up land closes")
	assert_true(6 in _rules(b.issues_for(1)))
