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


# E1-S10: an edge cue on rises that face away from the camera (toward x - 1 or y - 1).

func test_edge_cue_on_a_tile_higher_than_its_back_neighbours() -> void:
	var c := CourseData.create(3, 3, Surface.Type.ROUGH, 0)
	c.set_tile(1, 1, 1, Surface.Type.GREEN)
	assert_eq(CourseView.edge_cue_frame(c, 1, 1), &"l1r1", "one step up from both back neighbours")
	c.set_tile(1, 1, 3, Surface.Type.GREEN)
	assert_eq(CourseView.edge_cue_frame(c, 1, 1), &"l2r2", "two or more steps read as 2")
	c.set_tile(0, 1, 2, Surface.Type.GREEN)  # back-left neighbour (x - 1), one step lower
	assert_eq(CourseView.edge_cue_frame(c, 1, 1), &"l1r2")
	c.set_tile(1, 0, 3, Surface.Type.GREEN)  # back-right neighbour (y - 1), as tall
	assert_eq(CourseView.edge_cue_frame(c, 1, 1), &"l1")
	_view.show_course(c)
	var layer: TileMapLayer = _view.edge_layer(3)
	assert_eq(layer.get_cell_source_id(Vector2i(1, 1)), CourseView.EDGE_SOURCE, "drawn on the tile's height")
	assert_eq(layer.get_cell_atlas_coords(Vector2i(1, 1)),
			Vector2i(TileArt.load_default().edges.frame_index(&"l1"), 0))
	for h: int in CourseData.MAX_HEIGHT + 1:
		if h != 3:
			assert_eq(_view.edge_layer(h).get_cell_source_id(Vector2i(1, 1)), -1, "only at height 3, not %d" % h)


func test_no_edge_cue_on_flat_ground_or_the_map_edge() -> void:
	var c := CourseData.create(4, 4, Surface.Type.ROUGH, 2)
	_view.show_course(c)
	for y: int in c.height:
		for x: int in c.width:
			assert_eq(CourseView.edge_cue_frame(c, x, y), &"", "flat at (%d, %d)" % [x, y])
			for h: int in CourseData.MAX_HEIGHT + 1:
				assert_eq(_view.edge_layer(h).get_cell_source_id(Vector2i(x, y)), -1)


func test_no_edge_cue_where_the_back_neighbour_is_higher() -> void:
	# The higher neighbour's riser faces the camera and already shows that step.
	var c := CourseData.create(3, 3, Surface.Type.ROUGH, 0)
	c.set_tile(1, 1, 3, Surface.Type.GREEN)
	_view.show_course(c)
	assert_eq(CourseView.edge_cue_frame(c, 2, 1), &"", "x - 1 neighbour is higher")
	assert_eq(CourseView.edge_cue_frame(c, 1, 2), &"", "y - 1 neighbour is higher")
	assert_eq(CourseView.riser_frame(c, 1, 1, 0), &"both", "its riser shows the step instead")
	assert_eq(_view.edge_layer(0).get_cell_source_id(Vector2i(2, 1)), -1)
	assert_eq(_view.edge_layer(0).get_cell_source_id(Vector2i(1, 2)), -1)


func test_refresh_cell_updates_the_edge_cues_in_front() -> void:
	var c := CourseData.create(3, 3, Surface.Type.ROUGH, 0)
	c.set_tile(2, 1, 2, Surface.Type.GREEN)
	c.set_tile(1, 2, 2, Surface.Type.GREEN)
	_view.show_course(c)
	assert_eq(_view.edge_layer(2).get_cell_source_id(Vector2i(2, 1)), CourseView.EDGE_SOURCE)
	assert_eq(_view.edge_layer(2).get_cell_source_id(Vector2i(1, 2)), CourseView.EDGE_SOURCE)
	var edges: TileSheet = TileArt.load_default().edges
	# Raise (1, 1) to 1: the rise in front of it drops from 2 steps to 1.
	c.set_tile(1, 1, 1, Surface.Type.ROUGH)
	_view.refresh_cell(Vector2i(1, 1))
	assert_eq(_view.edge_layer(1).get_cell_source_id(Vector2i(1, 1)), CourseView.EDGE_SOURCE, "its own cue")
	assert_eq(_view.edge_layer(2).get_cell_atlas_coords(Vector2i(2, 1)),
			Vector2i(edges.frame_index(&"l1r2"), 0), "front-right neighbour (x + 1) redrawn")
	assert_eq(_view.edge_layer(2).get_cell_atlas_coords(Vector2i(1, 2)),
			Vector2i(edges.frame_index(&"l2r1"), 0), "front-left neighbour (y + 1) redrawn")
	# Raise it to 2: level with them, so their cue on that edge goes.
	c.set_tile(1, 1, 2, Surface.Type.ROUGH)
	_view.refresh_cell(Vector2i(1, 1))
	assert_eq(_view.edge_layer(2).get_cell_atlas_coords(Vector2i(2, 1)), Vector2i(edges.frame_index(&"r2"), 0))
	assert_eq(_view.edge_layer(2).get_cell_atlas_coords(Vector2i(1, 2)), Vector2i(edges.frame_index(&"l2"), 0))
	# Raise a flat front neighbour's back tile from scratch: a flat 3x3 gains cues in front.
	var flat := CourseData.create(3, 3, Surface.Type.ROUGH, 1)
	_view.show_course(flat)
	flat.set_tile(1, 1, 0, Surface.Type.ROUGH)
	_view.refresh_cell(Vector2i(1, 1))
	assert_eq(_view.edge_layer(1).get_cell_atlas_coords(Vector2i(2, 1)), Vector2i(edges.frame_index(&"l1"), 0),
			"cue added on the x + 1 neighbour")
	assert_eq(_view.edge_layer(1).get_cell_atlas_coords(Vector2i(1, 2)), Vector2i(edges.frame_index(&"r1"), 0),
			"cue added on the y + 1 neighbour")


func test_edge_cue_draws_over_its_top_and_under_objects() -> void:
	_view.show_course(HeightsFixture.build())
	var cell := Vector2i(6, 7)
	for h: int in CourseData.MAX_HEIGHT + 1:
		var key: float = _sort_key(_view.edge_layer(h), cell)
		assert_almost_eq(key, float(Iso.top_sort_key(cell, h)), 0.001, "ties with its top at %d" % h)
		assert_lt(key, Iso.object_sort_key(Vector2(cell), h), "a ball on the tile draws over the cue")
		# Ties break by tree order, so the cue layer must come after its top.
		assert_gt(_view.edge_layer(h).get_index(), _view.top_layer(h).get_index(), "after top %d" % h)
	var edges: TileSheet = TileArt.load_default().edges
	var shift: int = edges.anchor.y - edges.frame_size.y / 2
	assert_almost_eq(_view.edge_layer(3).position.y, _view.top_layer(3).position.y - shift, 0.001,
			"the frame's anchor lands on the tile center")


# E2-S2: a tee marker and a pin for every hole, on its tile's top, Y-sorted with the terrain.

## Two holes on uneven ground: hole 1's tee on a 5-step pillar, its cup on a 3-step green;
## hole 2 on flat ground at height 0.
func _two_hole_course() -> CourseData:
	var c := CourseData.create(12, 12, Surface.Type.ROUGH, 0)
	c.set_tile(2, 3, 5, Surface.Type.TEE)
	c.set_tile(9, 4, 3, Surface.Type.GREEN)
	c.set_tile(8, 10, 0, Surface.Type.GREEN)
	c.set_holes([HoleData.new(1, 3, Vector2i(2, 3), Vector2i(9, 4)),
			HoleData.new(2, 3, Vector2i(1, 10), Vector2i(8, 10))])
	return c


func _assert_marker_on_top(m: HoleMarker, cell: Vector2i, h: int) -> void:
	assert_not_null(m)
	if m == null:
		return
	assert_eq(m.cell, cell)
	assert_eq(m.ground, h, "stands on the tile's whole height")
	assert_eq(m.draw_point(), Iso.tile_to_screen(Vector2(cell), h), "drawn on the tile's top centre")
	assert_almost_eq(m.position.x, Iso.tile_to_screen(Vector2(cell), h).x, 0.001)
	assert_almost_eq(m.sort_key(), Iso.object_sort_key(Vector2(cell), h), 0.001, "sorts as an object on its top")
	assert_gt(m.sort_key(), float(Iso.top_sort_key(cell, h)), "over its own top")
	assert_lt(m.sort_key(), float(Iso.riser_sort_key(cell + Vector2i(1, 0), 0)), "under the next row")
	if h < CourseData.MAX_HEIGHT:
		assert_lt(m.sort_key(), float(Iso.riser_sort_key(cell, h + 1)), "under a step above it")


func test_every_hole_gets_a_tee_marker_and_a_pin_on_its_top() -> void:
	var c := _two_hole_course()
	_view.show_course(c)
	assert_eq(_view.hole_markers().size(), 4, "two holes, two markers each")
	_assert_marker_on_top(_view.hole_marker(1, HoleMarker.Kind.TEE), Vector2i(2, 3), 5)
	_assert_marker_on_top(_view.hole_marker(1, HoleMarker.Kind.PIN), Vector2i(9, 4), 3)
	_assert_marker_on_top(_view.hole_marker(2, HoleMarker.Kind.TEE), Vector2i(1, 10), 0)
	_assert_marker_on_top(_view.hole_marker(2, HoleMarker.Kind.PIN), Vector2i(8, 10), 0)


func test_markers_y_sort_in_the_course_view_space() -> void:
	_view.show_course(_two_hole_course())
	var m: HoleMarker = _view.hole_marker(1, HoleMarker.Kind.TEE)
	var parent := m.get_parent() as Node2D
	assert_true(parent.y_sort_enabled, "the holes node sorts with the layers")
	assert_eq(parent.get_parent(), _view, "a direct child of the view")
	assert_eq(parent.position, Vector2.ZERO, "so a marker's y is its sort key in view space")
	# A nearer, taller tile's riser hides the marker; a farther one does not.
	var tee := Vector2i(2, 3)
	assert_lt(_sort_key(_view.riser_layer(0), tee - Vector2i(1, 0)), m.sort_key(), "farther tile draws first")
	assert_gt(_sort_key(_view.riser_layer(0), tee + Vector2i(0, 1)), m.sort_key(), "nearer tile draws later")


func test_example_par3_shows_its_hole() -> void:
	var c := CourseSave.load_file("res://courses/example_par3.json")
	assert_not_null(c)
	if c == null:
		return
	_view.show_course(c)
	var hole: HoleData = c.holes[0]
	_assert_marker_on_top(_view.hole_marker(1, HoleMarker.Kind.TEE), hole.tee, c.get_height(hole.tee.x, hole.tee.y))
	_assert_marker_on_top(_view.hole_marker(1, HoleMarker.Kind.PIN), hole.cup, c.get_height(hole.cup.x, hole.cup.y))


func test_refresh_cell_moves_a_marker_to_its_new_top() -> void:
	var c := _two_hole_course()
	_view.show_course(c)
	c.set_tile(9, 4, 6, Surface.Type.GREEN)
	_view.refresh_cell(Vector2i(9, 4))
	_assert_marker_on_top(_view.hole_marker(1, HoleMarker.Kind.PIN), Vector2i(9, 4), 6)
	_assert_marker_on_top(_view.hole_marker(1, HoleMarker.Kind.TEE), Vector2i(2, 3), 5)


func test_markers_follow_the_holes_list() -> void:
	var c := _two_hole_course()
	_view.show_course(c)
	c.set_holes([HoleData.new(1, 3, Vector2i(2, 3), HoleData.UNPLACED)])
	_view.refresh_holes()
	assert_eq(_view.hole_markers().size(), 1, "an unplaced cup has no pin")
	assert_null(_view.hole_marker(1, HoleMarker.Kind.PIN))
	assert_eq(_view.find_child("Holes", false, false).get_child_count(), 1, "old markers are gone")
	_view.show_course(null)
	assert_eq(_view.hole_markers().size(), 0, "clearing the view clears the markers")


# --- E6-S5: unowned land draws dimmed, hatched, with parcel lines (art/specs/land.md) ---

## 40 x 20 tiles (parcels 3 x 2, the last column partial), height 1, owning only parcel (0, 0).
func _land_course() -> CourseData:
	var c := CourseData.create(40, 20, Surface.Type.ROUGH, 1)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			c.set_parcel_owned(Vector2i(p, q), Vector2i(p, q) == Vector2i.ZERO)
	c.set_tile(20, 4, 3, Surface.Type.GREEN)
	return c


func test_owned_land_draws_as_before() -> void:
	var c := CourseData.create(20, 20, Surface.Type.ROUGH, 1)
	_view.show_course(c)
	for h: int in CourseData.MAX_HEIGHT + 1:
		assert_eq(_view.land_layer(h).get_used_cells().size(), 0, "no overlay at height %d" % h)
	assert_eq(_view.top_layer(1).get_cell_alternative_tile(Vector2i(5, 5)), CourseView.top_alt(1, true), "not dimmed")
	assert_eq(_view.riser_layer(0).get_cell_alternative_tile(Vector2i(5, 19)), 0, "riser not dimmed")


func test_unowned_tiles_are_dimmed_and_hatched_at_their_height() -> void:
	var c := _land_course()
	_view.show_course(c)
	assert_eq(_view.land_layer(1).get_cell_source_id(Vector2i(5, 5)), -1, "owned: no hatch")
	assert_eq(_view.top_layer(1).get_cell_alternative_tile(Vector2i(5, 5)), CourseView.top_alt(1, true), "owned: no dim")
	var cell := Vector2i(20, 4)
	assert_eq(_view.land_layer(3).get_cell_source_id(cell), CourseView.LAND_SOURCE, "hatch on the raised top")
	assert_eq(_view.land_layer(1).get_cell_source_id(cell), -1, "only at its own height")
	assert_eq(_view.top_layer(3).get_cell_alternative_tile(cell), CourseView.top_alt(3, false), "top dimmed")
	assert_eq(_view.riser_layer(1).get_cell_alternative_tile(cell), CourseView.DIM_ALT, "riser dimmed")
	var tuning := BuilderTuning.load_default()
	var data: TileData = _view.riser_layer(1).get_cell_tile_data(cell)
	assert_eq(data.modulate, tuning.unowned_tint, "riser shade is the tuned tint")
	data = _view.top_layer(3).get_cell_tile_data(cell)
	assert_eq(data.modulate, tuning.unowned_tint, "green top: the tint alone (course surfaces take no height shade)")
	var shade: float = tuning.height_shade[1]
	data = _view.top_layer(1).get_cell_tile_data(Vector2i(20, 5))
	assert_eq(data.modulate, Color(shade, shade, shade) * tuning.unowned_tint, "rough top: the tint times its height's shade")
	var unowned: int = 0
	for h: int in CourseData.MAX_HEIGHT + 1:
		unowned += _view.land_layer(h).get_used_cells().size()
	assert_eq(unowned, 40 * 20 - 16 * 16, "every unowned tile, once")


func test_land_frame_marks_parcel_edges() -> void:
	var c := _land_course()
	assert_eq(CourseView.land_frame(c, 3, 3), -1, "owned")
	assert_eq(CourseView.land_frame(c, 20, 5), 0, "inside a parcel: hatch alone")
	assert_eq(CourseView.land_frame(c, 16, 5), CourseView.LAND_EDGE_W, "west edge, toward owned land")
	assert_eq(CourseView.land_frame(c, 31, 15), CourseView.LAND_EDGE_E | CourseView.LAND_EDGE_S, "corner")
	assert_eq(CourseView.land_frame(c, 20, 0), CourseView.LAND_EDGE_N, "map border")
	assert_eq(CourseView.land_frame(c, 39, 19), CourseView.LAND_EDGE_E | CourseView.LAND_EDGE_S,
			"partial parcel: the map's edge is its edge")
	_view.show_course(c)
	assert_eq(_view.land_layer(1).get_cell_atlas_coords(Vector2i(31, 15)), Vector2i(12, 0), "frame index is the mask")


func test_refresh_parcel_after_a_purchase() -> void:
	var c := _land_course()
	_view.show_course(c)
	var b := CourseBuilder.new(c)
	b.land_changed.connect(_view.refresh_parcel)
	assert_true(b.buy_parcel(Vector2i(1, 0)))
	assert_eq(_view.land_layer(3).get_cell_source_id(Vector2i(20, 4)), -1, "bought: no hatch")
	assert_eq(_view.top_layer(3).get_cell_alternative_tile(Vector2i(20, 4)), CourseView.top_alt(3, true), "bought: no dim")
	assert_eq(_view.land_layer(1).get_cell_atlas_coords(Vector2i(32, 5)), Vector2i(CourseView.LAND_EDGE_W, 0),
			"the line moves to the next parcel's side")
	assert_true(b.undo())
	assert_eq(_view.land_layer(3).get_cell_source_id(Vector2i(20, 4)), CourseView.LAND_SOURCE, "undone: hatched again")


# --- E6-S18: a grey shade step per height on every top (art/specs/surfaces.md) ---

func test_height_shade_is_grey_and_rises_with_height() -> void:
	var tuning := BuilderTuning.load_default()
	var shades: PackedFloat32Array = tuning.height_shade
	assert_eq(shades.size(), CourseData.MAX_HEIGHT + 1, "one shade per height")
	assert_eq(shades[tuning.plot_ground], 1.0, "the D10 plot's height is unshaded, so a New sandbox draws as before")
	for h: int in range(1, shades.size()):
		assert_gt(shades[h], shades[h - 1], "height %d lighter than %d" % [h, h - 1])
	# A height-6 plateau tells from a height-2 lowland by value (E6-S18's note).
	# E6-S28 brought the top down (shaded rough clear of tee by its fill), so 0.08, not 0.1.
	assert_gt(shades[6] - shades[2], 0.08, "plateau against lowland")
	assert_gt(shades[2] - shades[0], 0.15, "valley against lowland")


func test_every_top_draws_with_its_height_shade() -> void:
	var tuning := BuilderTuning.load_default()
	var c := CourseData.create(8, 8, Surface.Type.ROUGH, 0)
	for h: int in CourseData.MAX_HEIGHT + 1:
		c.set_tile(h, 3, h, Surface.Type.ROUGH if h % 2 == 0 else Surface.Type.TREES)
	_view.show_course(c)
	for h: int in CourseData.MAX_HEIGHT + 1:
		var cell := Vector2i(h, 3)
		assert_eq(_view.top_layer(h).get_cell_alternative_tile(cell), CourseView.top_alt(h, true), "alt at %d" % h)
		var m: Color = _view.top_layer(h).get_cell_tile_data(cell).modulate
		var want: float = CourseView.top_shades(TileArt.load_default().surfaces, tuning.height_shade,
				tuning.height_shaded)[c.get_surface(h, 3)][h]
		assert_almost_eq(m.r, want, 0.0001, "value at %d" % h)
		assert_almost_eq(want, tuning.height_shade[h], 0.0001, "rough and trees take the ramp at %d" % h)
		assert_true(m.r == m.g and m.g == m.b, "grey at %d: value, not hue (colorblind rule)" % h)
	# Risers and edge cues keep their own values.
	assert_eq(_view.riser_layer(4).get_cell_alternative_tile(Vector2i(7, 3)), 0, "riser unshaded")
	assert_eq(_view.edge_layer(1).get_cell_alternative_tile(Vector2i(1, 3)), 0, "cue unshaded")


func test_refresh_cell_reshades_a_raised_top() -> void:
	var c := CourseData.create(6, 6, Surface.Type.ROUGH, 2)
	_view.show_course(c)
	c.set_tile(2, 2, 5, Surface.Type.ROUGH)
	_view.refresh_cell(Vector2i(2, 2))
	assert_eq(_view.top_layer(5).get_cell_alternative_tile(Vector2i(2, 2)), CourseView.top_alt(5, true))
	assert_eq(_view.top_layer(2).get_cell_source_id(Vector2i(2, 2)), -1, "old top gone")


# E6-S18 review: course surfaces keep their colour, no channel clips, grass bands stay apart.

func test_course_surfaces_are_unshaded_at_every_height() -> void:
	var c := CourseData.create(8, 8, Surface.Type.ROUGH, 0)
	for h: int in CourseData.MAX_HEIGHT + 1:
		c.set_tile(h, 3, h, Surface.Type.FAIRWAY)
		c.set_tile(h, 5, h, Surface.Type.GREEN)
	_view.show_course(c)
	for h: int in CourseData.MAX_HEIGHT + 1:
		assert_eq(_view.top_layer(h).get_cell_tile_data(Vector2i(h, 3)).modulate, Color.WHITE, "fairway at %d" % h)
		assert_eq(_view.top_layer(h).get_cell_tile_data(Vector2i(h, 5)).modulate, Color.WHITE, "green at %d" % h)
	var tuning := BuilderTuning.load_default()
	var shades := CourseView.top_shades(TileArt.load_default().surfaces, tuning.height_shade, tuning.height_shaded)
	for t: int in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE, Surface.Type.BUNKER, Surface.Type.CART_PATH]:
		for h: int in CourseData.MAX_HEIGHT + 1:
			assert_eq(shades[t][h], 1.0, "%s unshaded at %d" % [Surface.name_of(t), h])


## The shade never pushes a coloured pixel's channel past 1, so it changes value, not hue.
func test_no_coloured_pixel_clips_at_any_height() -> void:
	var tuning := BuilderTuning.load_default()
	var sheet: TileSheet = TileArt.load_default().surfaces
	var shades := CourseView.top_shades(sheet, tuning.height_shade, tuning.height_shaded)
	var img: Image = sheet.texture.get_image()
	for i: int in sheet.frame_count():
		var top: float = 0.0
		var r: Rect2i = sheet.region(i)
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var p: Color = img.get_pixel(x, y)
				if p.a > 0.0 and p.s >= CourseView.HUE_MIN_SAT:
					top = maxf(top, maxf(p.r, maxf(p.g, p.b)))
		for h: int in CourseData.MAX_HEIGHT + 1:
			assert_true(top * shades[i][h] <= 1.0 + 0.0001,
					"%s at %d: %.3f x %.3f" % [sheet.frames[i], h, top, shades[i][h]])
	# Water's light ramp is the tight one: its top heights are capped, not clipped.
	var water: int = sheet.frame_index(&"water")
	assert_lt(shades[water][CourseData.MAX_HEIGHT], tuning.height_shade[CourseData.MAX_HEIGHT], "water capped")


## Over heights 0 to 7 the shaded value band of each grass lie (rough, fairway, tee, green,
## and trees) stays at least BAND_GAP apart from every other one's, so the lie still reads by
## value at 0.5x where labels and stipple are gone. Two unshaded surfaces keep the art's own
## gap (fairway and tee are close in value and told apart by pattern, art/specs/surfaces.md).
const BAND_GAP: float = 0.05

func test_grass_value_bands_do_not_overlap() -> void:
	var tuning := BuilderTuning.load_default()
	var sheet: TileSheet = TileArt.load_default().surfaces
	var shades := CourseView.top_shades(sheet, tuning.height_shade, tuning.height_shaded)
	var img: Image = sheet.texture.get_image()
	var names: PackedStringArray = ["rough", "fairway", "tee", "green", "trees"]
	var lo: Dictionary = {}
	var hi: Dictionary = {}
	for n: String in names:
		var i: int = sheet.frame_index(StringName(n))
		var r: Rect2i = sheet.region(i)
		var sum: float = 0.0
		var count: int = 0
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var p: Color = img.get_pixel(x, y)
				if p.a > 0.0:
					sum += p.get_luminance()
					count += 1
		var base: float = sum / count
		lo[n] = base * Array(shades[i]).min()
		hi[n] = base * Array(shades[i]).max()
	for a: int in names.size():
		for b: int in range(a + 1, names.size()):
			var na: String = names[a]
			var nb: String = names[b]
			if lo[na] == hi[na] and lo[nb] == hi[nb]:
				continue
			var under: String = na if hi[na] <= hi[nb] else nb
			var over: String = nb if under == na else na
			assert_true(lo[over] >= hi[under] * (1.0 + BAND_GAP),
					"%s %.3f..%.3f against %s %.3f..%.3f" % [under, lo[under], hi[under], over, lo[over], hi[over]])


# --- E6-S28: shaded land stays apart from the course lies by value ---

## A frame's value two ways, as Rec. 709 luminance: [mean over its opaque pixels, its fill].
## The fill is the frame's most common colour, the ground with the speckle, stipple and label
## left out, which is what is left of rough at 0.5x (E6-S28's note: rough at the top of the
## ramp read close to fairway once its speckle was gone).
func _frame_values(sheet: TileSheet, i: int) -> PackedFloat32Array:
	var img: Image = sheet.texture.get_image()
	var r: Rect2i = sheet.region(i)
	var sum: float = 0.0
	var count: int = 0
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var p: Color = img.get_pixel(x, y)
			if p.a > 0.0:
				sum += p.get_luminance()
				count += 1
	return PackedFloat32Array([sum / count, _fill(sheet, i).get_luminance()])


## A frame's most common opaque colour.
func _fill(sheet: TileSheet, i: int) -> Color:
	var img: Image = sheet.texture.get_image()
	var r: Rect2i = sheet.region(i)
	var seen: Dictionary = {}
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var p: Color = img.get_pixel(x, y)
			if p.a > 0.0:
				seen[p] = int(seen.get(p, 0)) + 1
	var fill := Color.BLACK
	var best: int = 0
	for p: Color in seen:
		if int(seen[p]) > best:
			best = int(seen[p])
			fill = p
	return fill


## Every shaded land surface (rough above all) at every height stays at least BAND_GAP in
## value from fairway, tee and green at the plot's height, by its mean and by its fill.
func test_shaded_land_stays_clear_of_course_lies_at_every_height() -> void:
	var tuning := BuilderTuning.load_default()
	var sheet: TileSheet = TileArt.load_default().surfaces
	var shades := CourseView.top_shades(sheet, tuning.height_shade, tuning.height_shaded)
	var plot: int = tuning.plot_ground
	assert_true("rough" in tuning.height_shaded, "rough takes the ramp")
	for land: String in tuning.height_shaded:
		var li: int = sheet.frame_index(StringName(land))
		var lv := _frame_values(sheet, li)
		for lie: String in ["fairway", "tee", "green"]:
			var ci: int = sheet.frame_index(StringName(lie))
			var cv := _frame_values(sheet, ci)
			for m: int in 2:
				var course_value: float = cv[m] * shades[ci][plot]
				for h: int in CourseData.MAX_HEIGHT + 1:
					var v: float = lv[m] * shades[li][h]
					var lo: float = minf(v, course_value)
					var hi: float = maxf(v, course_value)
					assert_true(hi >= lo * (1.0 + BAND_GAP), "%s at %d (%.1f) against %s (%.1f), %s" % [
							land, h, v * 255.0, lie, course_value * 255.0, ["mean", "fill"][m]])


## Bunker sand is the lightest surface: at height 7 it keeps its own colour, not white. It is a
## course surface, so unshaded; and if it were ever shaded the headroom cap holds it short of
## clipping with its hue (its fill keeps a sand tint, not a near-white).
func test_bunker_at_height_7_does_not_clip_to_white() -> void:
	var tuning := BuilderTuning.load_default()
	var sheet: TileSheet = TileArt.load_default().surfaces
	var bunker: int = sheet.frame_index(&"bunker")
	var top: int = CourseData.MAX_HEIGHT
	var c := CourseData.create(4, 4, Surface.Type.ROUGH, 0)
	c.set_tile(1, 1, top, Surface.Type.BUNKER)
	_view.show_course(c)
	assert_eq(_view.top_layer(top).get_cell_tile_data(Vector2i(1, 1)).modulate, Color.WHITE, "bunker unshaded at 7")
	var shaded_too: PackedStringArray = tuning.height_shaded.duplicate()
	shaded_too.append("bunker")
	var img: Image = sheet.texture.get_image()
	var r: Rect2i = sheet.region(bunker)
	for shades: Array[PackedFloat32Array] in [
			CourseView.top_shades(sheet, tuning.height_shade, tuning.height_shaded),
			CourseView.top_shades(sheet, tuning.height_shade, shaded_too)]:
		var s: float = shades[bunker][top]
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var p: Color = img.get_pixel(x, y)
				if p.a > 0.0 and p.s >= CourseView.HUE_MIN_SAT:
					assert_true(maxf(p.r, maxf(p.g, p.b)) * s <= 1.0 + 0.0001, "no channel clips at (%d, %d)" % [x, y])
		var fill: Color = _fill(sheet, bunker) * s
		assert_lt(minf(fill.r, minf(fill.g, fill.b)), 0.8, "sand keeps its tint at 7, shade %.3f" % s)
		assert_gt(maxf(fill.r, maxf(fill.g, fill.b)) - minf(fill.r, minf(fill.g, fill.b)), 0.2, "sand, not white")

