extends GutTest
## E1-S4: one shared isometric projection (course/iso.gd), and the renderer agrees with it.

const EPS: float = 0.0001


func test_constants_match_the_art() -> void:
	var art := TileArt.load_default()
	assert_eq(Vector2i(Iso.TILE_W, Iso.TILE_H), art.surfaces.frame_size, "footprint 64x32")
	assert_eq(Iso.STEP_PX, art.riser_px, "16 px per height step")
	assert_eq(art.surfaces.anchor, art.surfaces.frame_size / 2, "tiles anchor at the diamond center")
	assert_eq(art.risers.anchor, art.risers.frame_size / 2, "risers anchor like tiles")


func test_known_points() -> void:
	assert_eq(Iso.tile_to_screen(Vector2(0, 0), 0), Vector2(0, 0))
	assert_eq(Iso.tile_to_screen(Vector2(1, 0), 0), Vector2(32, 16), "+i goes down-right")
	assert_eq(Iso.tile_to_screen(Vector2(0, 1), 0), Vector2(-32, 16), "+j goes down-left")
	assert_eq(Iso.tile_to_screen(Vector2(0, 0), 7), Vector2(0, -112), "7 steps up")
	assert_eq(Iso.tile_to_screen(Vector2(3, 2), 2), Vector2(32, 48))
	assert_eq(Iso.point_to_screen(Vector3(3, 2, 2)), Vector2(32, 48))


func test_round_trip_every_tile_at_every_height() -> void:
	var misses: int = 0
	for h: int in CourseData.MAX_HEIGHT + 1:
		for j: int in range(-2, 22):
			for i: int in range(-2, 22):
				var cell := Vector2i(i, j)
				var screen: Vector2 = Iso.tile_to_screen(Vector2(cell), h)
				var back: Vector2 = Iso.screen_to_tile(screen, h)
				if not back.is_equal_approx(Vector2(cell)) or Iso.screen_to_cell(screen, h) != cell:
					misses += 1
	assert_eq(misses, 0, "tile -> screen -> tile at heights 0..7")


func test_round_trip_fractional_positions_and_heights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for n: int in 500:
		var t := Vector2(rng.randf_range(-5, 25), rng.randf_range(-5, 25))
		var h: float = rng.randf_range(0, 7)
		var back: Vector2 = Iso.screen_to_tile(Iso.tile_to_screen(t, h), h)
		assert_almost_eq(back.x, t.x, EPS)
		assert_almost_eq(back.y, t.y, EPS)


func test_screen_to_cell_covers_the_whole_diamond() -> void:
	# Points just inside each corner of tile (4, 6)'s diamond at height 3 pick that tile.
	var cell := Vector2i(4, 6)
	for h: int in [0, 3, 7]:
		var c: Vector2 = Iso.tile_to_screen(Vector2(cell), h)
		for offset: Vector2 in [Vector2(0, 0), Vector2(-31, 0), Vector2(31, 0), Vector2(0, -15),
				Vector2(0, 15), Vector2(15, 7), Vector2(-15, -7)]:
			assert_eq(Iso.screen_to_cell(c + offset, h), cell, "offset %s at h %d" % [offset, h])
		assert_eq(Iso.screen_to_cell(c + Vector2(33, 0), h), cell + Vector2i(1, -1), "past the right tip")
		assert_eq(Iso.screen_to_cell(c + Vector2(0, 17), h), cell + Vector2i(1, 1), "past the bottom tip")


func test_height_shifts_the_tile_under_a_screen_point() -> void:
	# One step up moves the picture 16 px up, so tile (5, 5) at height 2 covers the screen
	# point of tile (4, 4) at height 0. Picking needs the height, which E1-S5 resolves.
	var screen: Vector2 = Iso.tile_to_screen(Vector2(5, 5), 2)
	assert_eq(Iso.screen_to_cell(screen, 0), Vector2i(4, 4))


func test_renderer_places_cells_where_the_helper_says() -> void:
	var view := CourseView.new()
	add_child_autofree(view)
	view.show_course(HeightsFixture.build())
	for h: int in CourseData.MAX_HEIGHT + 1:
		var layer: TileMapLayer = view.top_layer(h)
		for cell: Vector2i in [Vector2i(0, 0), Vector2i(7, 3), Vector2i(19, 19)]:
			var drawn: Vector2 = layer.position + layer.map_to_local(cell)
			assert_eq(drawn, Iso.tile_to_screen(Vector2(cell), h), "top %s at h %d" % [cell, h])
	for k: int in CourseData.MAX_HEIGHT:
		var layer: TileMapLayer = view.riser_layer(k)
		assert_eq(layer.position + layer.map_to_local(Vector2i(2, 9)),
				Iso.tile_to_screen(Vector2(2, 9), k), "riser step %d shares the tile anchor" % k)
