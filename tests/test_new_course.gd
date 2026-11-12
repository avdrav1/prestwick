extends GutTest
## E6-S6: a New course starts on generated land (D19, D26, D28), owning only the starting
## block with the full land budget; New sandbox stays the D10 plot, every parcel owned, an
## unlimited budget, and buying hidden. The main scene starts on a New course.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## The starting block of the 8 x 8 parcel map (D67, 4 x 4; D26's was 2 x 2): parcels 2 to 5 on
## each axis.
const BLOCK: Rect2i = Rect2i(2, 2, 4, 4)
## Its tiles: 32 to 95 on each axis.
const BLOCK_TILES: Rect2i = Rect2i(32, 32, 64, 64)


func _owned(c: CourseData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			if c.is_parcel_owned(Vector2i(p, q)):
				out.append(Vector2i(p, q))
	return out


func _block_parcels() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q: int in range(BLOCK.position.y, BLOCK.end.y):
		for p: int in range(BLOCK.position.x, BLOCK.end.x):
			out.append(Vector2i(p, q))
	return out


func _main(seed_value: int = 7) -> Main:
	var m := MAIN_SCENE.instantiate() as Main
	m.start_seed = seed_value
	add_child_autofree(m)
	return m


# --- CourseBuilder.new_course ---

func test_new_course_owns_only_the_starting_block_with_the_full_budget() -> void:
	var c := CourseBuilder.new_course(7)
	assert_eq(Vector2i(c.width, c.height), Vector2i(128, 128))
	assert_eq(_owned(c), _block_parcels(), "only the 4 x 4 block at the centre (D67)")
	assert_false(c.has_unlimited_budget())
	assert_eq(c.land_budget, LandPrices.load_default().land_budget, "the full budget (D28)")
	assert_eq(c.land_budget, 5000)
	assert_eq(c.holes.size(), 0, "no holes yet")


func test_new_course_block_is_rough_and_dry_with_the_clubhouse_by_its_rule() -> void:
	# D67: tiles 32 to 95 each way, no water, at least start_block_min_rough rough (the rest tree
	# stands), on every seed; the clubhouse against the middle of its +y edge (D60).
	var t := LandTuning.load_default()
	assert_eq(LandGenerator.start_block(128, 128), BLOCK_TILES)
	for land_seed: int in [1, 7, 42]:
		var c := CourseBuilder.new_course(land_seed)
		var rough := 0
		var water := 0
		for y: int in range(BLOCK_TILES.position.y, BLOCK_TILES.end.y):
			for x: int in range(BLOCK_TILES.position.x, BLOCK_TILES.end.x):
				assert_true(c.is_owned(x, y))
				match c.get_surface(x, y):
					Surface.Type.ROUGH:
						rough += 1
					Surface.Type.WATER:
						water += 1
		assert_eq(water, 0, "seed %d: no water in the block" % land_seed)
		assert_gte(rough, ceili(t.start_block_min_rough * BLOCK_TILES.get_area()),
				"seed %d: the block is mostly rough" % land_seed)
		assert_false(c.is_owned(31, 64), "seed %d: one tile west of the block is not owned" % land_seed)
		assert_false(c.is_owned(64, 96), "seed %d: one tile south of it" % land_seed)
		assert_eq(c.clubhouse, Vector2i(64, 93), "seed %d: the clubhouse by its rule" % land_seed)
		assert_eq(c.clubhouse_door(), Vector2i(64, 95), "its door on the block's last row")


func test_new_course_block_holds_a_long_par_3_and_a_par_4_but_no_par_5() -> void:
	# D67: 64 tiles a side, so 315 yd along an edge and 445 yd corner to corner: a par 3 up to
	# 300 yd and a par 4 fit with no purchase; the shortest par 5 (471 yd) does not.
	var c := CourseBuilder.new_course(7)
	var vt := ValidatorTuning.load_default()
	var span := BalanceSim.owned_span_yd(c)
	assert_almost_eq(span, 445.5, 0.1, "corner to corner of the 4 x 4 block")
	assert_gt(span, float(vt.par4_min_yd), "a par 4 fits")
	assert_lt(span, float(vt.par5_min_yd), "a par 5 needs land")
	assert_eq(CourseValidator.yardage(Vector2i(32, 40), Vector2i(92, 40)), 300, "a 300 yd par 3 along an edge")


func test_new_course_is_the_generated_land_of_its_seed() -> void:
	var c := CourseBuilder.new_course(7)
	var land := LandGenerator.generate(7)
	assert_eq(c.surface_grid(), land.surface_grid(), "the seed's land, tile for tile")
	var same_heights: bool = true
	for y: int in c.height:
		for x: int in c.width:
			if c.get_height(x, y) != land.get_height(x, y):
				same_heights = false
	assert_true(same_heights, "and its heights")
	assert_eq(CourseBuilder.new_course(7).content_hash(), c.content_hash(), "same seed, same course")
	assert_ne(CourseBuilder.new_course(8).content_hash(), c.content_hash(), "another seed, other land")


func test_new_course_is_not_flat() -> void:
	var c := CourseBuilder.new_course(7)
	var heights := {}
	var surfaces := {}
	for y: int in c.height:
		for x: int in c.width:
			heights[c.get_height(x, y)] = true
			surfaces[c.get_surface(x, y)] = true
	assert_gt(heights.size(), 1, "hills")
	assert_true(surfaces.has(Surface.Type.TREES), "tree stands")
	assert_true(surfaces.has(Surface.Type.WATER), "ponds")


func test_new_course_buys_next_to_the_block() -> void:
	var b := CourseBuilder.new(CourseBuilder.new_course(7))
	assert_eq(b.buy_refusal(Vector2i(1, 3)), "", "a parcel beside the block is for sale")
	assert_eq(b.buy_refusal(Vector2i(0, 0)), "not next to your land")
	assert_false(b.can_undo(), "a fresh course has nothing to undo")


func test_new_sandbox_owns_everything_with_no_limit() -> void:
	var c := CourseBuilder.new_sandbox()
	assert_eq(_owned(c).size(), c.parcels_wide * c.parcels_high, "every parcel")
	assert_eq(c.parcels_wide * c.parcels_high, 64)
	assert_true(c.has_unlimited_budget())
	var wrong: int = 0
	for y: int in c.height:
		for x: int in c.width:
			if c.get_surface(x, y) != Surface.Type.ROUGH or c.get_height(x, y) != 2:
				wrong += 1
	assert_eq(wrong, 0, "flat rough at height 2 (D10)")


# --- main ---

func test_main_starts_on_a_new_course() -> void:
	var m := _main(7)
	assert_eq(m.course_path, "", "no startup course file")
	assert_eq(m.course.content_hash(), CourseBuilder.new_course(7).content_hash(), "the seed's new course")
	assert_eq(_owned(m.course), _block_parcels())
	assert_eq(m.course.land_budget, 5000)
	assert_same(m.build_tool.builder.course, m.course)
	assert_eq(m.money_panel.balance_label.text, "Balance: $5,000")
	assert_true(m.build_palette.buy_button.visible, "buying shows on a New course")


func test_main_start_seed_picks_one_when_unset() -> void:
	var m := MAIN_SCENE.instantiate() as Main
	assert_eq(m.start_seed, -1, "a random seed by default")
	add_child_autofree(m)
	assert_eq(_owned(m.course), _block_parcels(), "still a New course")
	assert_eq(m.course.content_hash(), CourseBuilder.new_course(m.land_seed).content_hash(),
			"land_seed says which land it is")


func test_new_course_button_starts_fresh_land() -> void:
	var m := _main(7)
	assert_true(m.new_course_button.visible, "New course is on the Build HUD")
	assert_true(m.build_tool.builder.buy_parcel(Vector2i(1, 3)))
	m.new_course(11)
	assert_eq(m.land_seed, 11)
	assert_eq(m.course.content_hash(), CourseBuilder.new_course(11).content_hash())
	assert_eq(m.course.land_budget, 5000, "the full budget again")
	assert_false(m.build_tool.builder.can_undo(), "a fresh builder")
	m.new_course_button.pressed.emit()
	assert_eq(_owned(m.course), _block_parcels(), "the button makes a New course too")
	m.set_mode(Main.Mode.PLAY)
	assert_false(m.new_course_button.visible, "Build only")


func test_main_new_sandbox_hides_buying() -> void:
	var m := _main(7)
	m.build_tool.select_tool(BuildTool.Tool.BUY)
	m.new_sandbox()
	assert_true(m.course.has_unlimited_budget())
	assert_eq(_owned(m.course).size(), 64, "every parcel owned")
	assert_false(m.build_palette.buy_button.visible, "no Buy land tool in New sandbox")
	assert_ne(m.build_tool.tool, BuildTool.Tool.BUY, "a selected Buy land tool steps back to paint")
	assert_eq(m.money_panel.balance_label.text, "Balance: unlimited")
	m.new_course(7)
	assert_true(m.build_palette.buy_button.visible, "back on a New course")


func test_play_on_a_new_course_rests_the_ball_on_owned_land() -> void:
	for seed_value: int in [7, 11, 123]:
		var m := _main(seed_value)
		m.set_mode(Main.Mode.PLAY)
		var at: Vector2 = m.swing_control.ball_at
		var ypt: float = m.swing_control.field.yards_per_tile
		var tile := Vector2i(floori(at.x / ypt), floori(at.y / ypt))
		assert_true(m.course.is_owned(tile.x, tile.y), "seed %d: the ball sits on the player's land" % seed_value)
		assert_eq(tile, Vector2i(64, 64), "seed %d: the centre of the starting block" % seed_value)
		assert_eq(m.score_card.title_label.text, "No hole")


func test_play_on_a_sandbox_with_no_hole_keeps_the_debug_tile() -> void:
	var m := _main(7)
	m.new_sandbox()
	assert_eq(m.no_hole_tile(), m.debug_shot.start_tile, "owned there, so unchanged")


# --- E6-S21: the debug shot starts on owned land ---

func test_debug_shot_on_a_new_course_fires_from_owned_land_and_stays_in_bounds() -> void:
	for seed_value: int in [7, 11, 123]:
		var m := _main(seed_value)
		m.set_mode(Main.Mode.PLAY)
		var start_tile := m.debug_shot_tile()
		assert_false(m.course.is_owned(m.debug_shot.start_tile.x, m.debug_shot.start_tile.y),
				"seed %d: the resource's tile is unowned on a New course" % seed_value)
		assert_true(m.course.is_owned(start_tile.x, start_tile.y),
				"seed %d: the debug shot starts on the player's land" % seed_value)
		assert_eq(start_tile, m.no_hole_tile(), "seed %d: the no-hole tile" % seed_value)
		m.fire_debug_shot()
		assert_true(m.shot_view.playing, "seed %d: it flies" % seed_value)
		var field := m.shot_view.ball.field
		var launched := m.shot_view.ball.path[0] if not m.shot_view.ball.path.is_empty() \
				else m.shot_view.ball.position
		assert_eq(field.tile_at(launched.x, launched.y), start_tile,
				"seed %d: struck from that tile" % seed_value)
		m.shot_view.advance(60.0)
		assert_false(m.shot_view.playing, "seed %d: and rests" % seed_value)
		assert_ne(m.shot_view.ball.hazard, Ball.Hazard.OB, "seed %d: not out of bounds" % seed_value)
		var rest := m.shot_view.ball.position
		var rest_tile := field.tile_at(rest.x, rest.y)
		assert_true(m.course.is_owned(rest_tile.x, rest_tile.y),
				"seed %d: it rests on owned land" % seed_value)


func test_debug_shot_on_a_sandbox_and_a_fixture_keeps_its_own_tile() -> void:
	var m := _main(7)
	m.new_sandbox()
	assert_eq(m.debug_shot_tile(), m.debug_shot.start_tile, "New sandbox owns it")
	var heights := CourseSave.load_file("res://courses/heights_20x20.json")
	m.show_course(heights)
	assert_eq(m.debug_shot_tile(), m.debug_shot.start_tile, "a v1 fixture owns it")
	m.set_mode(Main.Mode.PLAY)
	m.fire_debug_shot()
	var field := HeightField.new(heights, BallParams.load_default())
	var expected := Ball.new(heights, m.debug_shot.rng_seed)
	expected.launch(m.debug_shot.start_position(field), m.debug_shot.velocity())
	m.shot_view.advance(60.0)
	while not expected.is_at_rest():
		expected.step()
	assert_eq(m.shot_view.ball.steps, expected.steps, "tick for tick as before")
	assert_eq(m.shot_view.ball.position, expected.position, "the same rest")
