extends GutTest
## E1-S3: placeholder terrain art loads by name, matches the art-spec constants, and stays
## inside art/palette.gpl. Regenerate the sheets with `python3 scripts/placeholder.py all`.

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
	assert_not_null(_art.risers.texture)
	assert_not_null(_art.surface_texture(&"green"))
	assert_not_null(_art.riser_texture(&"left"))


func test_surface_frames_follow_the_surface_enum() -> void:
	assert_eq(_art.surfaces.frames, SURFACE_ORDER)
	for i: int in SURFACE_ORDER.size():
		assert_eq(_art.surfaces.frame_index(StringName(SURFACE_ORDER[i])), i)


func test_riser_frames() -> void:
	assert_eq(_art.risers.frames, PackedStringArray(["both", "left", "right"]))
	assert_eq(_art.riser_px, 16)


func test_sheet_layout_matches_art_spec() -> void:
	for sheet: TileSheet in [_art.surfaces, _art.risers]:
		assert_eq(sheet.frame_size, Vector2i(64, 32))
		assert_eq(sheet.gutter, 1)
		var n: int = sheet.frame_count()
		var expected := Vector2i(n * 64 + (n - 1), 32)
		assert_eq(Vector2i(sheet.texture.get_size()), expected, "one row, 1 px gutter, no padding")
		assert_eq(sheet.region(1), Rect2i(65, 0, 64, 32))


func test_gutters_are_transparent() -> void:
	for sheet: TileSheet in [_art.surfaces, _art.risers]:
		var img: Image = sheet.texture.get_image()
		for i: int in range(1, sheet.frame_count()):
			var x: int = i * (sheet.frame_size.x + sheet.gutter) - 1
			for y: int in sheet.frame_size.y:
				assert_eq(img.get_pixel(x, y).a, 0.0, "gutter at x=%d y=%d" % [x, y])


func test_surfaces_are_diamonds() -> void:
	for i: int in _art.surfaces.frame_count():
		var img: Image = _frame_image(_art.surfaces, i)
		assert_eq(img.get_pixel(0, 0).a, 0.0, "%s corner clear" % SURFACE_ORDER[i])
		assert_eq(img.get_pixel(63, 31).a, 0.0, "%s corner clear" % SURFACE_ORDER[i])
		assert_eq(img.get_pixel(32, 16).a, 1.0, "%s center filled" % SURFACE_ORDER[i])
		assert_eq(img.get_pixel(1, 16).a, 1.0, "%s left tip filled" % SURFACE_ORDER[i])
		assert_eq(img.get_pixel(31, 0).a, 1.0, "%s top tip filled" % SURFACE_ORDER[i])


func test_risers_fill_one_step_under_a_tile() -> void:
	var both: Image = _frame_image(_art.risers, 0)
	assert_eq(both.get_pixel(32, 8).a, 0.0, "raised top sits above the band")
	assert_eq(both.get_pixel(32, 24).a, 1.0, "front corner of the wall")
	assert_eq(both.get_pixel(2, 16).a, 1.0, "left face")
	assert_eq(both.get_pixel(61, 16).a, 1.0, "right face")
	var left: Image = _frame_image(_art.risers, 1)
	assert_eq(left.get_pixel(61, 16).a, 0.0, "left frame has no right face")
	var right: Image = _frame_image(_art.risers, 2)
	assert_eq(right.get_pixel(2, 16).a, 0.0, "right frame has no left face")


func test_every_surface_has_its_own_pattern() -> void:
	# Colorblind rule: a pattern as well as a color. Fairway is the one plain surface.
	var seen: Dictionary = {}
	for i: int in _art.surfaces.frame_count():
		var img: Image = _frame_image(_art.surfaces, i)
		var colors: Dictionary = {}
		# Middle of the diamond: clear of the edge line and the corner label.
		for y: int in range(12, 20):
			for x: int in range(24, 40):
				colors[img.get_pixel(x, y).to_html()] = true
		if SURFACE_ORDER[i] == "fairway":
			assert_eq(colors.size(), 1, "fairway is plain")
		else:
			assert_gt(colors.size(), 1, "%s has a pattern" % SURFACE_ORDER[i])
		var key: String = Marshalls.raw_to_base64(img.get_data())
		assert_false(seen.has(key), "%s differs from every other surface" % SURFACE_ORDER[i])
		seen[key] = true


func test_sheets_use_only_palette_colors() -> void:
	var palette: Dictionary = _palette()
	assert_eq(palette.size(), 32, "palette has 32 colors")
	for sheet: TileSheet in [_art.surfaces, _art.risers]:
		var img: Image = sheet.texture.get_image()
		var bad: Dictionary = {}
		for y: int in img.get_height():
			for x: int in img.get_width():
				var c: Color = img.get_pixel(x, y)
				if c.a == 0.0:
					continue
				if c.a != 1.0 or not palette.has(c.to_html(false)):
					bad[c.to_html()] = true
		assert_eq(bad.size(), 0, "off-palette colors in %s: %s" % [sheet.texture.resource_path, bad.keys()])


func test_riser_faces_reach_the_corner_columns() -> void:
	# Walls of neighboring tiles repeat every 32 px, so each face must own all 32 columns,
	# including the vertical corner edge (column 0 left, 63 right), or a 1 px seam shows (E1-S4).
	var left: Image = _frame_image(_art.risers, 1)
	var right: Image = _frame_image(_art.risers, 2)
	for y: int in 16:
		assert_eq(left.get_pixel(0, y).a, 1.0, "left face corner column at y=%d" % y)
		assert_eq(right.get_pixel(63, y).a, 1.0, "right face corner column at y=%d" % y)
	assert_eq(left.get_pixel(0, 16).a, 0.0, "corner column stops at the left tip")
	assert_eq(left.get_pixel(31, 31).a, 1.0, "left face reaches the front corner")
	assert_eq(right.get_pixel(32, 31).a, 1.0, "right face reaches the front corner")
