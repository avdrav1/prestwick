extends GutTest
## E1-S4: CourseView draws surfaces and risers per height step on Y-sorted TileMapLayers,
## in the painter's order of art/specs/risers.md.

var _view: CourseView


func before_each() -> void:
	_view = CourseView.new()
	add_child_autofree(_view)


func _sort_key(layer: TileMapLayer, cell: Vector2i) -> float:
	return layer.position.y + layer.map_to_local(cell).y + layer.y_sort_origin


func test_layers_are_y_sorted_tile_map_layers() -> void:
	assert_true(_view.y_sort_enabled, "parent sorts its layers together")
	for h: int in CourseData.MAX_HEIGHT + 1:
		assert_is(_view.top_layer(h), TileMapLayer)
		assert_true(_view.top_layer(h).y_sort_enabled, "top %d" % h)
	for k: int in CourseData.MAX_HEIGHT:
		assert_true(_view.riser_layer(k).y_sort_enabled, "riser %d" % k)


func test_tops_show_each_tile_once_at_its_height() -> void:
	var c := HeightsFixture.build()
	_view.show_course(c)
	var wrong: int = 0
	for y: int in c.height:
		for x: int in c.width:
			var cell := Vector2i(x, y)
			for h: int in CourseData.MAX_HEIGHT + 1:
				var source: int = _view.top_layer(h).get_cell_source_id(cell)
				if h == c.get_height(x, y):
					if source != CourseView.SURFACE_SOURCE \
							or _view.top_layer(h).get_cell_atlas_coords(cell) != Vector2i(c.get_surface(x, y), 0):
						wrong += 1
				elif source != -1:
					wrong += 1
	assert_eq(wrong, 0, "one top per tile, frame == surface")


func test_risers_fill_every_visible_step() -> void:
	var c := CourseData.create(3, 3, Surface.Type.ROUGH, 0)
	c.set_tile(1, 1, 3, Surface.Type.GREEN)
	_view.show_course(c)
	for k: int in 3:
		assert_eq(_view.riser_layer(k).get_cell_source_id(Vector2i(1, 1)), CourseView.RISER_SOURCE, "step %d" % k)
		assert_eq(_view.riser_layer(k).get_cell_atlas_coords(Vector2i(1, 1)), Vector2i(0, 0), "both faces")
	assert_eq(_view.riser_layer(3).get_cell_source_id(Vector2i(1, 1)), -1, "no wall above the top")
	assert_eq(_view.riser_layer(0).get_cell_source_id(Vector2i(0, 0)), -1, "flat ground has no wall")


func test_hidden_faces_are_skipped() -> void:
	var c := CourseData.create(3, 3, Surface.Type.ROUGH, 0)
	c.set_tile(1, 1, 4, Surface.Type.GREEN)
	c.set_tile(1, 2, 2, Surface.Type.GREEN)  # in front of the left face
	c.set_tile(2, 1, 4, Surface.Type.GREEN)  # in front of the right face, as tall
	assert_eq(CourseView.riser_frame(c, 1, 1, 0), &"", "both faces hidden at step 0")
	assert_eq(CourseView.riser_frame(c, 1, 1, 1), &"", "both faces hidden at step 1")
	assert_eq(CourseView.riser_frame(c, 1, 1, 2), &"left", "left shows above the shorter neighbor")
	assert_eq(CourseView.riser_frame(c, 1, 1, 4), &"", "not that tall")
	assert_eq(CourseView.riser_frame(c, 2, 1, 0), &"both", "map edge shows its wall")
	assert_eq(CourseView.riser_frame(c, 1, 2, 0), &"both")


func test_painter_order_back_to_front_then_bottom_up() -> void:
	_view.show_course(HeightsFixture.build())
	var cell := Vector2i(6, 7)
	var keys: Array[float] = []
	for k: int in CourseData.MAX_HEIGHT:
		keys.append(_sort_key(_view.riser_layer(k), cell))
		keys.append(_sort_key(_view.top_layer(k), cell))
	keys.append(_sort_key(_view.top_layer(CourseData.MAX_HEIGHT), cell))
	for n: int in range(1, keys.size()):
		assert_gt(keys[n], keys[n - 1], "within a tile: riser k < top k < riser k + 1")
	# Everything in the tile sorts before anything in the next depth row, at any height.
	var nearer: float = _sort_key(_view.riser_layer(0), cell + Vector2i(1, 0))
	assert_lt(keys.max(), nearer, "a nearer tile always draws later")
	assert_gt(_sort_key(_view.riser_layer(0), cell), _sort_key(_view.top_layer(7), cell - Vector2i(0, 1)),
			"a farther tile always draws earlier")


func test_renderer_sorts_at_the_iso_keys() -> void:
	_view.show_course(HeightsFixture.build())
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(6, 7), Vector2i(19, 19)]:
		for k: int in CourseData.MAX_HEIGHT:
			assert_almost_eq(_sort_key(_view.riser_layer(k), cell), float(Iso.riser_sort_key(cell, k)), 0.001,
					"riser %d at %s" % [k, cell])
		for h: int in CourseData.MAX_HEIGHT + 1:
			assert_almost_eq(_sort_key(_view.top_layer(h), cell), float(Iso.top_sort_key(cell, h)), 0.001,
					"top %d at %s" % [h, cell])


func test_object_on_a_tall_top_sorts_over_it_and_under_the_next_row() -> void:
	# The pyramid green at (5, 5), height 7: a ball anywhere on its diamond must draw over the
	# green and under every piece of the next depth row.
	_view.show_course(HeightsFixture.build())
	var cell := Vector2i(5, 5)
	var top: float = _sort_key(_view.top_layer(7), cell)
	var next_row: float = _sort_key(_view.riser_layer(0), cell + Vector2i(1, 0))
	for offset: Vector2 in [Vector2.ZERO, Vector2(-0.49, -0.49), Vector2(0.49, 0.49), Vector2(0.49, -0.49)]:
		var key: float = Iso.object_sort_key(Vector2(cell) + offset, 7)
		assert_gt(key, top, "ball at %s draws over the green" % offset)
		assert_lt(key, next_row, "ball at %s draws under the next row" % offset)
	for h: int in CourseData.MAX_HEIGHT + 1:
		var key: float = Iso.object_sort_key(Vector2(cell), h)
		assert_gt(key, float(Iso.top_sort_key(cell, h)), "over its own top at h %d" % h)
		if h < CourseData.MAX_HEIGHT:
			assert_lt(key, float(Iso.riser_sort_key(cell, h + 1)), "under the next step up at h %d" % h)


func test_refresh_cell_redraws_the_tile_and_back_walls() -> void:
	var c := CourseData.create(3, 3, Surface.Type.ROUGH, 2)
	_view.show_course(c)
	assert_eq(_view.riser_layer(0).get_cell_source_id(Vector2i(0, 1)), -1, "flat plateau hides inner walls")
	c.set_tile(1, 1, 0, Surface.Type.WATER)
	_view.refresh_cell(Vector2i(1, 1))
	assert_eq(_view.top_layer(0).get_cell_atlas_coords(Vector2i(1, 1)), Vector2i(Surface.Type.WATER, 0))
	assert_eq(_view.top_layer(2).get_cell_source_id(Vector2i(1, 1)), -1, "old top gone")
	assert_eq(CourseView.riser_frame(c, 0, 1, 0), &"right")
	assert_eq(_view.riser_layer(0).get_cell_atlas_coords(Vector2i(0, 1)), Vector2i(2, 0), "back-left wall revealed")
	assert_eq(_view.riser_layer(0).get_cell_atlas_coords(Vector2i(1, 0)), Vector2i(1, 0), "back-right wall revealed")


func test_screen_bounds_cover_every_corner() -> void:
	var c := HeightsFixture.build()
	_view.show_course(c)
	var r: Rect2 = _view.screen_bounds()
	for corner: Vector2 in [Vector2(-0.5, -0.5), Vector2(19.5, -0.5), Vector2(-0.5, 19.5), Vector2(19.5, 19.5)]:
		for h: int in [0, 7]:
			assert_true(r.grow(0.01).has_point(Iso.tile_to_screen(corner, h)), "%s at %d" % [corner, h])


func test_fixture_file_matches_its_generator() -> void:
	var errors: Array[String] = []
	var loaded := CourseSave.load_file(HeightsFixture.PATH, errors)
	assert_not_null(loaded, "loads: %s" % [errors])
	if loaded:
		assert_eq(loaded.content_hash(), HeightsFixture.build().content_hash(),
				"regenerate courses/heights_20x20.json with tests/fixtures/heights_fixture.gd")
	var c := HeightsFixture.build()
	var heights: Dictionary = {}
	var surfaces: Dictionary = {}
	for y: int in c.height:
		for x: int in c.width:
			heights[c.get_height(x, y)] = true
			surfaces[c.get_surface(x, y)] = true
	assert_eq(c.width, 20)
	assert_eq(heights.size(), CourseData.MAX_HEIGHT + 1, "every height 0..7")
	assert_eq(surfaces.size(), Surface.COUNT, "every surface")
