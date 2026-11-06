extends GutTest
## E1-S4: CourseView draws the course isometrically. Since E3-S58 (D50) the ground is a mesh over
## the bilinear surface (tests/test_terrain_mesh.gd has the mesh, light and picker); these tests
## cover what the view draws per tile, its markers, land, shades and Play art.

var _view: CourseView


func before_each() -> void:
	_view = CourseView.new()
	add_child_autofree(_view)


## What tile `cell` draws now in the view (TerrainMesh.emit_tile, as its chunk holds it).
func _part(cell: Vector2i) -> Array:
	return _view.chunk_at(cell).parts[cell]


## The colour of the vertex at `cell`'s centre (every tile has one: a fan's first point, a
## grid's middle one).
func _centre_colour(cell: Vector2i) -> Color:
	var pts: PackedVector3Array = _view.terrain.tile_geometry(cell)[0]
	for i: int in pts.size():
		if Vector2(pts[i].x, pts[i].y) == Vector2(cell):
			return (_part(cell)[2] as PackedColorArray)[i]
	return Color.TRANSPARENT


## The surface frame `cell` is textured from: the frame whose region holds its UVs.
func _frame_of(cell: Vector2i) -> int:
	var sheet: TileSheet = TileArt.load_default().surfaces
	var uv: Vector2 = (_part(cell)[1] as PackedVector2Array)[0] * Vector2(sheet.texture.get_size())
	for i: int in sheet.frame_count():
		if Rect2(sheet.region(i)).grow(0.01).has_point(uv):
			return i
	return -1


## The land frame `cell`'s hatch is drawn from, or -1 when it has none.
func _land_frame_of(cell: Vector2i) -> int:
	var uvs: PackedVector2Array = _part(cell)[4]
	if uvs.is_empty():
		return -1
	var sheet: TileSheet = TileArt.load_default().land
	var uv: Vector2 = uvs[0] * Vector2(sheet.texture.get_size())
	for i: int in sheet.frame_count():
		if Rect2(sheet.region(i)).grow(0.01).has_point(uv):
			return i
	return -2


func test_every_tile_is_drawn_once_with_its_surface() -> void:
	var c := HeightsFixture.build()
	_view.show_course(c)
	var wrong: int = 0
	for y: int in c.height:
		for x: int in c.width:
			if _frame_of(Vector2i(x, y)) != c.get_surface(x, y):
				wrong += 1
	assert_eq(wrong, 0, "each tile textured from its surface's frame")


func test_refresh_cell_redraws_the_edited_tile_and_its_neighbours() -> void:
	var c := CourseData.create(6, 6, Surface.Type.ROUGH, 2)
	_view.show_course(c)
	c.set_tile(2, 2, 0, Surface.Type.WATER)
	_view.refresh_cell(Vector2i(2, 2))
	assert_eq(_frame_of(Vector2i(2, 2)), Surface.Type.WATER)
	for p: Vector3 in _view.terrain.tile_geometry(Vector2i(2, 2))[0] as PackedVector3Array:
		assert_eq(p.z, 0.0, "the water lies at its new level")
	assert_true(_view.terrain.sloped(Vector2i(1, 2)), "the land beside it now slopes down to it")
	var fresh := CourseView.new()
	add_child_autofree(fresh)
	fresh.show_course(c)
	assert_eq(_view.terrain_digest(), fresh.terrain_digest(), "as a fresh draw")


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


# E2-S2: a tee marker and a pin for every hole, on its tile, Y-sorted with the ground.

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
	assert_eq(m.draw_point(), Iso.tile_to_screen(Vector2(cell), h), "drawn on the tile's centre")
	assert_almost_eq(m.position.x, Iso.tile_to_screen(Vector2(cell), h).x, 0.001)
	assert_almost_eq(m.sort_key(), Iso.object_sort_key(Vector2(cell), h), 0.001, "sorts as an object on its tile")
	assert_gt(m.sort_key(), _view.chunk_at(cell).position.y, "over its own row of ground")
	assert_lt(m.sort_key(), _view.chunk_at(cell).position.y + Iso.HALF_H, "under the next row")


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
	assert_true(parent.y_sort_enabled, "the holes node sorts with the ground")
	assert_eq(parent.get_parent(), _view, "a direct child of the view")
	assert_eq(parent.position, Vector2.ZERO, "so a marker's y is its sort key in view space")
	# Ground nearer the camera hides the marker; ground farther away does not.
	var tee := Vector2i(2, 3)
	assert_lt(_view.chunk_at(tee - Vector2i(1, 0)).position.y, m.sort_key(), "farther ground draws first")
	assert_gt(_view.chunk_at(tee + Vector2i(0, 1)).position.y, m.sort_key(), "nearer ground draws later")


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


## The side colour of a face looking along `n`.
func _side(n: Vector3, tint: Color = Color.WHITE) -> Color:
	var t := TerrainTuning.load_default()
	var col: Color = t.side_color * _view.terrain.light_of(n) * tint
	col.a = 1.0
	return col


func test_owned_land_draws_as_before() -> void:
	var c := CourseData.create(20, 20, Surface.Type.ROUGH, 1)
	_view.show_course(c)
	for ch: TerrainMesh.Chunk in _view.chunks():
		assert_eq(ch.land_idx.size(), 0, "no hatch")
	var shade: float = BuilderTuning.load_default().height_shade[1]
	assert_eq(_centre_colour(Vector2i(5, 5)), Color(shade, shade, shade), "not dimmed: its height shade alone")
	var face: Array = _part(Vector2i(5, 19))
	assert_eq((face[6] as PackedColorArray)[0], _side(Vector3(0, 1, 0)), "side face not dimmed")


func test_unowned_tiles_are_dimmed_and_hatched() -> void:
	var c := _land_course()
	_view.show_course(c)
	assert_eq(_land_frame_of(Vector2i(5, 5)), -1, "owned: no hatch")
	var tuning := BuilderTuning.load_default()
	var shade: float = tuning.height_shade[1]
	assert_eq(_centre_colour(Vector2i(5, 5)), Color(shade, shade, shade), "owned: no dim")
	var cell := Vector2i(20, 4)
	assert_eq(_land_frame_of(cell), 0, "hatch on the raised green")
	assert_eq(_centre_colour(cell), Color.WHITE * tuning.unowned_tint,
			"green: the tint alone (course surfaces take no height shade)")
	assert_eq(_centre_colour(Vector2i(25, 10)), Color(shade, shade, shade) * tuning.unowned_tint,
			"rough: the tint times its height's shade")
	var hatch: PackedVector2Array = _part(cell)[4]
	assert_eq(hatch.size(), (_part(cell)[0] as PackedVector2Array).size(), "the hatch follows the ground's points")
	var face: Array = _part(Vector2i(25, 19))
	assert_eq((face[6] as PackedColorArray)[0], _side(Vector3(0, 1, 0), tuning.unowned_tint), "side face dimmed")
	var unowned: int = 0
	for y: int in c.height:
		for x: int in c.width:
			if _land_frame_of(Vector2i(x, y)) >= 0:
				unowned += 1
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
	assert_eq(_land_frame_of(Vector2i(31, 15)), 12, "frame index is the mask")


func test_refresh_parcel_after_a_purchase() -> void:
	var c := _land_course()
	_view.show_course(c)
	var b := CourseBuilder.new(c)
	b.land_changed.connect(_view.refresh_parcel)
	assert_true(b.buy_parcel(Vector2i(1, 0)))
	assert_eq(_land_frame_of(Vector2i(20, 4)), -1, "bought: no hatch")
	assert_eq(_centre_colour(Vector2i(20, 4)), Color.WHITE, "bought: no dim")
	assert_eq(_land_frame_of(Vector2i(32, 5)), CourseView.LAND_EDGE_W, "the line moves to the next parcel's side")
	assert_true(b.undo())
	assert_eq(_land_frame_of(Vector2i(20, 4)), 0, "undone: hatched again")
	var fresh := CourseView.new()
	add_child_autofree(fresh)
	fresh.show_course(c)
	assert_eq(_view.terrain_digest(), fresh.terrain_digest(), "as a fresh draw")


# --- E6-S18: a grey shade step per height on the ground (art/specs/surfaces.md) ---

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


func test_every_height_draws_with_its_height_shade() -> void:
	var tuning := BuilderTuning.load_default()
	var shades := CourseView.top_shades(TileArt.load_default().surfaces, tuning.height_shade, tuning.height_shaded)
	for h: int in CourseData.MAX_HEIGHT + 1:
		for s: Surface.Type in [Surface.Type.ROUGH, Surface.Type.TREES]:
			_view.show_course(CourseData.create(3, 3, s, h))
			var m: Color = _centre_colour(Vector2i(1, 1))
			assert_almost_eq(m.r, shades[s][h], 0.0001, "value at %d" % h)
			assert_almost_eq(shades[s][h], tuning.height_shade[h], 0.0001, "rough and trees take the ramp at %d" % h)
			assert_true(m.r == m.g and m.g == m.b, "grey at %d: value, not hue (colorblind rule)" % h)


func test_refresh_cell_reshades_a_raised_plateau() -> void:
	var c := CourseData.create(7, 7, Surface.Type.ROUGH, 2)
	_view.show_course(c)
	for y: int in range(1, 6):
		for x: int in range(1, 6):
			c.set_tile(x, y, 5, Surface.Type.ROUGH)
	var cells: Array[Vector2i] = []
	for y: int in 7:
		for x: int in 7:
			cells.append(Vector2i(x, y))
	_view.refresh_cells(cells)
	var shade: float = BuilderTuning.load_default().height_shade[5]
	assert_almost_eq(_centre_colour(Vector2i(3, 3)).r, shade, 0.0001, "the plateau's top at 5")


# E6-S18 review: course surfaces keep their colour, no channel clips, grass bands stay apart.

func test_course_surfaces_are_unshaded_at_every_height() -> void:
	for h: int in CourseData.MAX_HEIGHT + 1:
		for s: Surface.Type in [Surface.Type.FAIRWAY, Surface.Type.GREEN]:
			_view.show_course(CourseData.create(3, 3, s, h))
			assert_eq(_centre_colour(Vector2i(1, 1)), Color.WHITE, "%s at %d" % [Surface.name_of(s), h])
	var tuning := BuilderTuning.load_default()
	var shades := CourseView.top_shades(TileArt.load_default().surfaces, tuning.height_shade, tuning.height_shaded)
	for t: int in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE, Surface.Type.BUNKER, Surface.Type.CART_PATH]:
		for h: int in CourseData.MAX_HEIGHT + 1:
			assert_eq(shades[t][h], 1.0, "%s unshaded at %d" % [Surface.name_of(t), h])


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
	assert_eq(_centre_colour(Vector2i(1, 1)), Color.WHITE, "bunker unshaded at 7")
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


# E3-S55: Play draws the sheets' label-free textures, Build the labelled ones, by swapping the
# ground's textures: its geometry stays as it is.
func test_play_art_swaps_the_ground_textures_without_rebuilding() -> void:
	var art := TileArt.load_default()
	assert_not_null(art.surfaces.play_texture, "the placeholder surfaces name a label-free sheet")
	var c := HeightsFixture.build()
	_view.show_course(c)
	for ch: TerrainMesh.Chunk in _view.chunks():
		assert_eq(ch.texture, art.surfaces.texture, "Build: the labelled sheet")
		assert_eq(ch.land_texture, art.land.texture)
	var before: Array = _view.terrain_digest()
	_view.play_art = true
	for ch: TerrainMesh.Chunk in _view.chunks():
		assert_eq(ch.texture, art.surfaces.play_texture, "Play: the label-free sheet")
		assert_eq(ch.land_texture, art.land.texture, "no play sheet: the one sheet")
	assert_eq(_view.terrain_digest(), before, "the ground's geometry and colours stay as drawn")
	_view.play_art = false
	for ch: TerrainMesh.Chunk in _view.chunks():
		assert_eq(ch.texture, art.surfaces.texture, "Build again: labelled")


func test_a_sheet_without_a_play_texture_draws_the_same_in_both_modes() -> void:
	var sheet := TileSheet.new()
	sheet.texture = TileArt.load_default().edges.texture
	assert_eq(sheet.texture_for(true), sheet.texture, "final art: no play sheet, the one sheet in Play")
	assert_eq(sheet.texture_for(false), sheet.texture)
	sheet.play_texture = TileArt.load_default().surfaces.play_texture
	assert_eq(sheet.texture_for(true), sheet.play_texture)
	assert_eq(sheet.texture_for(false), sheet.texture)
