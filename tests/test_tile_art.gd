extends GutTest
## E1-S3: terrain art loads by name, matches the art-spec constants, and stays inside
## art/palette.gpl. Final art since E5-S2 (D62): regenerate the sheets with
## `python3 scripts/art_terrain.py`.

const SURFACE_ORDER: PackedStringArray = [
	"fairway", "rough", "green", "tee", "bunker", "water", "trees", "cart_path", "oob",
]
const PALETTE_PATH: String = "res://art/palette.gpl"

var _art: TileArt


func before_each() -> void:
	_art = TileArt.load_default()


func _palette() -> Dictionary:
	var colors: Dictionary = {}
	var text: String = FileAccess.get_file_as_string(PALETTE_PATH)
	for line: String in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#") or stripped.begins_with("GIMP") \
				or stripped.begins_with("Name:") or stripped.begins_with("Columns:"):
			continue
		var parts: PackedStringArray = stripped.replace("\t", " ").split(" ", false)
		var key: Color = Color8(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())
		colors[key.to_html(false)] = parts[3]
	return colors


func _frame_image(sheet: TileSheet, index: int) -> Image:
	return sheet.texture.get_image().get_region(sheet.region(index))


func test_loads_by_name() -> void:
	assert_not_null(_art, "surfaces.tres loads as TileArt")
	assert_not_null(_art.surfaces.texture)
	assert_not_null(_art.land.texture)
	assert_not_null(_art.surface_texture(&"green"))


func test_surface_frames_follow_the_surface_enum() -> void:
	assert_eq(_art.surfaces.frames, SURFACE_ORDER)
	for i: int in SURFACE_ORDER.size():
		assert_eq(_art.surfaces.frame_index(StringName(SURFACE_ORDER[i])), i)


func test_riser_px_is_one_height_step() -> void:
	assert_eq(_art.riser_px, 16)


func test_sheet_layout_matches_art_spec() -> void:
	for sheet: TileSheet in [_art.surfaces, _art.land]:
		assert_eq(sheet.frame_size, Vector2i(64, 32))
		assert_eq(sheet.gutter, 1)
		var n: int = sheet.frame_count() * sheet.macro * sheet.macro
		var expected := Vector2i(n * 64 + (n - 1), 32)
		assert_eq(Vector2i(sheet.texture.get_size()), expected, "one row, 1 px gutter, no padding")
		assert_eq(sheet.region(1), Rect2i(65, 0, 64, 32))


func test_gutters_are_transparent() -> void:
	for sheet: TileSheet in [_art.surfaces, _art.land]:
		var img: Image = sheet.texture.get_image()
		for i: int in range(1, sheet.frame_count() * sheet.macro * sheet.macro):
			var x: int = i * (sheet.frame_size.x + sheet.gutter) - 1
			for y: int in sheet.frame_size.y:
				assert_eq(img.get_pixel(x, y).a, 0.0, "gutter at x=%d y=%d" % [x, y])


func test_surfaces_are_diamonds() -> void:
	var sheet: TileSheet = _art.surfaces
	for i: int in sheet.frame_count() * sheet.macro * sheet.macro:
		var img: Image = _frame_image(sheet, i)
		var n: String = "%s variant %d" % [SURFACE_ORDER[i % sheet.frame_count()], i / sheet.frame_count()]
		assert_eq(img.get_pixel(0, 0).a, 0.0, "%s corner clear" % n)
		assert_eq(img.get_pixel(63, 31).a, 0.0, "%s corner clear" % n)
		assert_eq(img.get_pixel(32, 16).a, 1.0, "%s center filled" % n)
		assert_eq(img.get_pixel(1, 16).a, 1.0, "%s left tip filled" % n)
		assert_eq(img.get_pixel(31, 0).a, 1.0, "%s top tip filled" % n)


## The colours a surface draws across every variant of its repeat, with their pixel counts.
func _surface_colours(i: int) -> Dictionary:
	var img: Image = _art.surfaces.texture.get_image()
	var counts: Dictionary = {}
	for r: Rect2i in _art.surfaces.variant_regions(i):
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.0:
					counts[c.to_html()] = int(counts.get(c.to_html(), 0)) + 1
	return counts


func test_every_surface_has_its_own_pattern() -> void:
	# Colorblind rule: a pattern as well as a color (art/specs/surfaces.md). Since E5-S2 the
	# fairway is striped too, with stripes a tile or two wide, so every surface draws at least
	# two colours over its repeat, the second at least 2% of it, and no two surfaces draw the
	# same set of colours.
	var seen: Dictionary = {}
	for i: int in _art.surfaces.frame_count():
		var counts: Dictionary = _surface_colours(i)
		var total: int = 0
		for k: String in counts:
			total += int(counts[k])
		var shares: Array = counts.values()
		shares.sort()
		assert_gt(counts.size(), 1, "%s has a pattern" % SURFACE_ORDER[i])
		assert_gt(float(shares[shares.size() - 2]) / total, 0.02, "%s's pattern shows" % SURFACE_ORDER[i])
		var keys: Array = counts.keys()
		keys.sort()
		var key: String = ",".join(PackedStringArray(keys))
		assert_false(seen.has(key), "%s differs from every other surface" % SURFACE_ORDER[i])
		seen[key] = true


## E5-S2: the fairway's mowing stripes are a tile or more wide (the E5-S1 sample's lesson): the
## sheet repeats every `macro` tiles, and down the y axis some tiles are mostly the light stripe
## and some mostly plain fairway.
func test_fairway_stripes_span_several_tiles() -> void:
	var sheet: TileSheet = _art.surfaces
	assert_gt(sheet.macro, 1, "a repeat wider than a tile")
	var img: Image = sheet.texture.get_image()
	var light := Color8(120, 184, 88)
	var shares: Array[float] = []
	for b: int in sheet.macro:
		var r: Rect2i = sheet.region(sheet.variant_of(0, Vector2i(0, b)))
		var n: int = 0
		var lit: int = 0
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.0:
					n += 1
					lit += 1 if c.is_equal_approx(light) else 0
		shares.append(float(lit) / n)
	# Along y the stripes alternate: some tiles mostly light, some mostly plain.
	assert_gt(shares.max() - shares.min(), 0.4, "stripes across tiles: %s" % [shares])


func test_sheets_use_only_palette_colors() -> void:
	var palette: Dictionary = _palette()
	assert_eq(palette.size(), 32, "palette has 32 colors")
	for tex: Texture2D in [_art.surfaces.texture, _art.land.texture]:
		var img: Image = tex.get_image()
		var bad: Dictionary = {}
		for y: int in img.get_height():
			for x: int in img.get_width():
				var c: Color = img.get_pixel(x, y)
				if c.a == 0.0:
					continue
				if c.a != 1.0 or not palette.has(c.to_html(false)):
					bad[c.to_html()] = true
		assert_eq(bad.size(), 0, "off-palette colors in %s: %s" % [tex.resource_path, bad.keys()])


# E6-S5: the unowned-land hatch and parcel lines (art/specs/land.md).
func test_land_frames_are_edge_masks() -> void:
	assert_eq(_art.land.frame_count(), 16)
	assert_eq(_art.land.frames[0], "hatch")
	assert_eq(_art.land.frames[CourseView.LAND_EDGE_W | CourseView.LAND_EDGE_S], "hatch_ws")
	assert_eq(_art.land.frames[15], "hatch_wnes")
	assert_eq(_art.land.anchor, Vector2i(32, 16))
	var chalk := Color8(240, 236, 224)
	# Just inside the middle of each edge, on a chalk dash: w up-left, n up-right, e down-right,
	# s down-left.
	var probes: Array[Vector2i] = [Vector2i(16, 9), Vector2i(48, 9), Vector2i(48, 22), Vector2i(16, 22)]
	for m: int in 16:
		var img: Image = _frame_image(_art.land, m)
		assert_eq(img.get_pixel(0, 0).a, 0.0, "%s: outside the top is clear" % _art.land.frames[m])
		for b: int in 4:
			var on: bool = img.get_pixel(probes[b].x, probes[b].y).is_equal_approx(chalk)
			assert_eq(on, (m >> b) & 1 == 1, "%s: edge %d line" % [_art.land.frames[m], b])
	var hatch: Image = _frame_image(_art.land, 0)
	var ink: int = 0
	for x: int in range(24, 40):
		if hatch.get_pixel(x, 16).a == 1.0:
			ink += 1
	assert_eq(ink, 4, "a 2 px hatch line every 8 px across the middle")


# E6-S5 review: the parcel line must not read as a one-step rise (the retired edge cue was one
# solid chalk line just inside a higher top's back edge, art/specs/edge_cue.md). The parcel line
# is dashed chalk and ink along the edge.
func test_land_edge_band_is_dashed() -> void:
	var chalk := Color8(240, 236, 224)
	var ink := Color8(26, 28, 34)
	var land: Image = _frame_image(_art.land, CourseView.LAND_EDGE_W)
	var land_chalk: int = 0
	var land_ink: int = 0
	# The back-left edge runs from (0, 16) to (32, 0) in a land frame (anchor 16). The band is
	# the first 2 px inside the top.
	for x: int in range(4, 28):
		var edge_y: float = 16.0 - (x + 0.5) / 2.0
		for y: int in 32:
			var v: float = y + 0.5 - edge_y
			if v >= 0.0 and v < 2.0:
				var c: Color = land.get_pixel(x, y)
				land_chalk += 1 if c.is_equal_approx(chalk) else 0
				land_ink += 1 if c.is_equal_approx(ink) else 0
	assert_gt(land_chalk, 0, "the parcel line has chalk dashes")
	assert_gt(land_ink, land_chalk / 2, "and ink dashes between them, so it is not solid")


# E3-S55: a sheet's play_texture is drawn in Play when set. The final sheets (E5-S2) have no
# labels, so neither names one and one sheet draws in both modes.
func test_final_sheets_have_no_play_copy() -> void:
	assert_null(_art.surfaces.play_texture, "no labels on the final surfaces, so one sheet")
	assert_null(_art.land.play_texture, "the land sheet has no labels, so one sheet")
