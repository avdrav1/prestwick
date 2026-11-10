extends GutTest
## E5-S3: decor (benches, flags, signs; art/specs/decor.md) is scenery. It is placed through the
## builder (one undo step, refused on water, unowned land and the clubhouse), saved as an
## optional field of the course file, drawn by DecorView, and read by nothing that plays: a
## seeded shot and the validator give the same result with decor on every tile they cross.


## A par 4 strip: rough with a fairway down the middle, tee at x 2, cup on a green at x 46.
func _strip() -> CourseData:
	var c := CourseData.create(52, 12, Surface.Type.ROUGH, 2)
	for x: int in range(4, 44):
		for y: int in range(4, 8):
			c.set_tile(x, y, 2 + (x / 10) % 2, Surface.Type.FAIRWAY)
	for x: int in range(43, 50):
		for y: int in range(3, 9):
			c.set_tile(x, y, 3, Surface.Type.GREEN)
	c.set_tile(2, 6, 2, Surface.Type.TEE)
	c.set_holes([HoleData.new(1, 4, Vector2i(2, 6), Vector2i(46, 6))])
	return c


## Decor of every kind on every tile but water.
func _decorated(c: CourseData) -> CourseData:
	var d := c.copy()
	for y: int in d.height:
		for x: int in d.width:
			if d.get_surface(x, y) != Surface.Type.WATER:
				d.set_decor(Vector2i(x, y), (x + y) % CourseData.DECOR_KINDS.size())
	return d


## Where a seeded drive and its roll end, and every 10th tick on the way.
func _shot(c: CourseData, rng_seed: int) -> Array:
	var ball := Ball.new(c, rng_seed)
	ball.set_cup(c.holes[0].cup)
	ball.launch(Vector3(2, 6, 2), Ball.launch_velocity(62.0, 13.0, 2.0))
	var trace: Array = []
	var n: int = 0
	while not ball.is_at_rest() and n < 6000:
		ball.step()
		if n % 10 == 0:
			trace.append(ball.position)
		n += 1
	trace.append(ball.position)
	return trace


func test_decor_has_no_effect_on_a_seeded_shot() -> void:
	var plain := _strip()
	var decorated := _decorated(plain)
	assert_gt(decorated.decor_cells().size(), 500, "decor on every tile")
	for rng_seed: int in [1, 7, 42]:
		var a: Array = _shot(plain, rng_seed)
		var b: Array = _shot(decorated, rng_seed)
		assert_eq(b, a, "seed %d: the same flight, bounces and roll" % rng_seed)
		assert_gt((a.back() as Vector3).x, 20.0, "seed %d: a real drive" % rng_seed)


func test_decor_has_no_effect_on_the_validator() -> void:
	var plain := _strip()
	var decorated := _decorated(plain)
	var v := CourseValidator.new()
	assert_eq(str(v.check_course(decorated)), str(v.check_course(plain)), "the same issues")


func test_the_builder_places_changes_and_removes_decor_with_undo() -> void:
	var c := _strip()
	var b := CourseBuilder.new(c)
	var changed: Array[Vector2i] = []
	b.decor_changed.connect(func(cell: Vector2i) -> void: changed.append(cell))
	var cell := Vector2i(10, 2)
	var balance: int = c.land_budget
	assert_true(b.set_decor(cell, 2), "a flag on rough")
	assert_eq(c.decor_at(cell.x, cell.y), 2)
	assert_eq(c.land_budget, balance, "free")
	assert_false(b.set_decor(cell, 2), "already there")
	assert_true(b.set_decor(cell, 3), "now a sign")
	assert_true(b.set_decor(cell, CourseData.NO_DECOR), "taken away")
	assert_eq(c.decor_at(cell.x, cell.y), CourseData.NO_DECOR)
	assert_eq(changed.size(), 3)
	assert_true(b.undo(), "undo the removal")
	assert_eq(c.decor_at(cell.x, cell.y), 3)
	assert_true(b.undo())
	assert_eq(c.decor_at(cell.x, cell.y), 2)
	assert_true(b.undo())
	assert_eq(c.decor_at(cell.x, cell.y), CourseData.NO_DECOR, "back to none")
	assert_true(b.set_decor(c.holes[0].tee, 0), "a bench on the tee: decor plays no part")


func test_decor_is_refused_on_water_unowned_land_and_the_clubhouse() -> void:
	var c := _strip()
	c.set_tile(20, 1, 0, Surface.Type.WATER)
	var b := CourseBuilder.new(c)
	assert_eq(b.decor_refusal(Vector2i(20, 1)), "not on water")
	assert_false(b.set_decor(Vector2i(20, 1), 0))
	assert_eq(b.decor_refusal(Vector2i(-1, 3)), "off the map")
	if c.has_clubhouse():
		assert_eq(b.decor_refusal(c.clubhouse), "the clubhouse is here")
	var land := CourseData.create(40, 40, Surface.Type.ROUGH, 2)
	land.set_parcel_owned(Vector2i(1, 1), false)
	var lb := CourseBuilder.new(land)
	assert_eq(lb.decor_refusal(Vector2i(20, 20)), "not your land")
	assert_true(lb.set_decor(Vector2i(3, 3), 1))


func test_decor_saves_and_loads_and_a_course_without_it_writes_no_field() -> void:
	var c := _strip()
	assert_false(c.to_dict().has("decor"), "no decor, no field: older files stay byte-identical")
	c.set_decor(Vector2i(5, 2), 0)
	c.set_decor(Vector2i(9, 9), 3)
	var text: String = CourseSave.to_json(c)
	var errors: Array[String] = []
	var back := CourseSave.from_json(text, errors)
	assert_not_null(back, "loads: %s" % [errors])
	assert_eq(back.decor_cells(), [Vector2i(5, 2), Vector2i(9, 9)] as Array[Vector2i])
	assert_eq(back.decor_at(9, 9), 3)
	assert_eq(back.content_hash(), c.content_hash())
	assert_ne(back.content_hash(), _strip().content_hash(), "decor is part of the content")


func test_bad_decor_in_a_file_is_refused_with_a_reason() -> void:
	var d := _strip().to_dict()
	for bad: Variant in [{"x": 1}, [[1, 2]], [[99, 2, 0]], [[1, 2, 9]], [[1, 2, 0], [1, 2, 1]]]:
		d["decor"] = bad
		var errors: Array[String] = []
		assert_null(CourseData.from_dict(d, errors), "refused: %s" % [bad])
		assert_false(errors.is_empty())
		assert_true(errors[0].begins_with("decor"), errors[0] if not errors.is_empty() else "")


func test_the_view_draws_each_piece_on_its_tile() -> void:
	var c := _strip()
	c.set_decor(Vector2i(6, 2), 1)
	c.set_decor(Vector2i(12, 9), 2)
	var view := CourseView.new()
	add_child_autofree(view)
	view.show_course(c)
	var pieces: Array[Node] = view.decor.pieces()
	assert_eq(pieces.size(), 2)
	var p := pieces[0] as DecorView.Piece
	assert_eq(p.region, Rect2(view.decor.sheet.region(1)), "the bench along y")
	assert_almost_eq(p.position.y, Iso.object_sort_key(Vector2(6, 2), 2), 0.001, "sorted on its tile")
	c.set_decor(Vector2i(6, 2), CourseData.NO_DECOR)
	view.refresh_decor()
	assert_eq(view.decor.pieces().size(), 1)


func test_the_decor_tool_places_cycles_and_removes() -> void:
	var c := _strip()
	var b := CourseBuilder.new(c)
	var tool := BuildTool.new()
	add_child_autofree(tool)
	tool.builder = b
	tool.active = true
	tool.select_tool(BuildTool.Tool.DECOR)
	var cell := Vector2i(8, 1)
	tool._apply(cell)
	assert_eq(c.decor_at(8, 1), 0, "a click places the current kind")
	tool._last_cell = TilePicker.NONE  # a new click (press_at clears it)
	tool._apply(cell)
	assert_eq(c.decor_at(8, 1), 1, "a click on decor steps its kind")
	assert_eq(tool.decor_kind, 1, "and the tool follows")
	assert_true(tool.remove_decor(cell), "right-click or R takes it away")
	assert_eq(c.decor_at(8, 1), CourseData.NO_DECOR)
	assert_true(BuildTool.Tool.DECOR in tool.tool_order().map(func(t: Array) -> int: return t[0]),
			"the keyboard reaches it")


func test_the_decor_sheet_matches_its_spec() -> void:
	var sheet := load(DecorView.PATH) as TileSheet
	assert_eq(sheet.frames, CourseData.DECOR_KINDS, "frame order is the file's kind index")
	assert_eq(sheet.frame_size, Vector2i(48, 48))
	assert_eq(sheet.anchor, Vector2i(24, 40))
	assert_eq(sheet.texture.get_size(), Vector2(4 * 48 + 3, 48))
	var img: Image = sheet.texture.get_image()
	var flag: Image = img.get_region(sheet.region(2))
	var red := 0
	for y: int in 48:
		for x: int in 48:
			if flag.get_pixel(x, y).is_equal_approx(Color8(216, 58, 58)):
				red += 1
	assert_eq(red, 0, "the decor flag is never flag_red, so it is not taken for a pin")
