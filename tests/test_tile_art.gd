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
	for sheet: TileSheet in [_art.surfaces, _art.risers, _art.edges, _art.land]:
		assert_eq(sheet.frame_size, Vector2i(64, 32))
		assert_eq(sheet.gutter, 1)
		var n: int = sheet.frame_count()
		var expected := Vector2i(n * 64 + (n - 1), 32)
		assert_eq(Vector2i(sheet.texture.get_size()), expected, "one row, 1 px gutter, no padding")
		assert_eq(sheet.region(1), Rect2i(65, 0, 64, 32))


func test_gutters_are_transparent() -> void:
	for sheet: TileSheet in [_art.surfaces, _art.risers, _art.edges, _art.land]:
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
	for tex: Texture2D in [_art.surfaces.texture, _art.risers.texture, _art.edges.texture,
			_art.land.texture, _art.surfaces.play_texture, _art.risers.play_texture]:
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


# E1-S10: edge cue frames for rises that face away from the camera (art/specs/edge_cue.md).

const EDGE_FRAMES: PackedStringArray = ["l1", "l2", "r1", "r2", "l1r1", "l1r2", "l2r1", "l2r2"]


func _light_runs(img: Image, x: int, dark: bool = false) -> int:
	# Bright (or dark) runs down one column: lip lines, counted without looking at hue.
	var runs: int = 0
	var inside: bool = false
	for y: int in img.get_height():
		var c: Color = img.get_pixel(x, y)
		var lum: float = c.get_luminance()
		var lit: bool = c.a == 1.0 and (lum < 0.2 if dark else lum > 0.8)
		if lit and not inside:
			runs += 1
		inside = lit
	return runs


func test_edge_frames_and_anchor() -> void:
	assert_eq(_art.edges.frames, EDGE_FRAMES)
	assert_eq(_art.edges.anchor, Vector2i(32, 18), "2 px of headroom for the shadow over the top corner")


func test_edge_frames_mark_one_step_versus_more_by_line_count() -> void:
	# The pattern, not only the color: one dark-and-bright lip for one step, two for two or
	# more, so the count reads on light and dark ground and in grayscale.
	for frame: String in EDGE_FRAMES:
		var img: Image = _frame_image(_art.edges, _art.edges.frame_index(StringName(frame)))
		var left: int = 0 if not frame.contains("l") else (2 if frame.contains("l2") else 1)
		var right: int = 0 if not frame.contains("r") else (2 if frame.contains("r2") else 1)
		for x: int in [12, 20]:
			assert_eq(_light_runs(img, x), left, "%s back-left lines at x=%d" % [frame, x])
			assert_eq(_light_runs(img, x, true), left, "%s back-left dark lines at x=%d" % [frame, x])
		for x: int in [43, 51]:
			assert_eq(_light_runs(img, x), right, "%s back-right lines at x=%d" % [frame, x])
			assert_eq(_light_runs(img, x, true), right, "%s back-right dark lines at x=%d" % [frame, x])
		assert_eq(img.get_pixel(32, 30).a, 0.0, "%s leaves the front half clear" % frame)


func test_edge_shadow_sits_outside_the_top_and_the_highlight_inside() -> void:
	var img: Image = _frame_image(_art.edges, _art.edges.frame_index(&"l1r1"))
	# Back-left edge at x = 16 runs through y = 18 - 16 + 8 = 10 (anchor y 18).
	assert_lt(img.get_pixel(16, 9).get_luminance(), 0.2, "dark shadow just outside the edge")
	assert_gt(img.get_pixel(16, 10).get_luminance(), 0.8, "bright lip just inside")


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


# E6-S5 review: the parcel line must not read as an edge cue (art/specs/edge_cue.md), whose
# lip is one solid chalk line just inside the higher top's back edge. The parcel line is
# dashed chalk and ink along the edge, so a boundary is never taken for a one-step rise.
func test_land_edge_band_is_not_an_edge_cue_band() -> void:
	var chalk := Color8(240, 236, 224)
	var ink := Color8(26, 28, 34)
	var land: Image = _frame_image(_art.land, CourseView.LAND_EDGE_W)
	var cue: Image = _frame_image(_art.edges, _art.edges.frames.find("l1"))
	var land_chalk: int = 0
	var land_ink: int = 0
	var cue_chalk: int = 0
	var cue_total: int = 0
	# The back-left edge runs from (0, 16) to (32, 0) in a land frame (anchor 16), and 2 px
	# lower in an edge cue frame (anchor 18). The band is the first 2 px inside the top.
	for x: int in range(4, 28):
		var edge_y: float = 16.0 - (x + 0.5) / 2.0
		for y: int in 32:
			var v: float = y + 0.5 - edge_y
			if v >= 0.0 and v < 2.0:
				var c: Color = land.get_pixel(x, y)
				land_chalk += 1 if c.is_equal_approx(chalk) else 0
				land_ink += 1 if c.is_equal_approx(ink) else 0
			if v >= 2.0 and v < 4.0:
				cue_total += 1
				cue_chalk += 1 if cue.get_pixel(x, y).is_equal_approx(chalk) else 0
	assert_gt(cue_total, 0)
	assert_eq(cue_chalk, cue_total, "the edge cue lip is one solid chalk line")
	assert_gt(land_chalk, 0, "the parcel line has chalk dashes")
	assert_gt(land_ink, land_chalk / 2, "and ink dashes between them, so it is not solid")


# E3-S55: the label-free play sheets (scripts/placeholder.py). Same size and frame layout as the
# labelled sheet, and the same pixels everywhere but where the label was drawn: the label box in
# a surface frame's left corner, the 3x5 glyphs in a riser frame's upper corner.
const SURFACE_LABEL_BOX := Rect2i(7, 13, 9, 7)
const RISER_LABEL_LEFT := Rect2i(6, 9, 7, 5)
const RISER_LABEL_RIGHT := Rect2i(50, 9, 7, 5)


func _label_rect(sheet: TileSheet, frame: String) -> Rect2i:
	if sheet == _art.surfaces:
		return SURFACE_LABEL_BOX
	return RISER_LABEL_RIGHT if frame == "right" else RISER_LABEL_LEFT


func test_play_sheets_differ_only_where_the_labels_were() -> void:
	for sheet: TileSheet in [_art.surfaces, _art.risers]:
		assert_not_null(sheet.play_texture, "%s has a play sheet" % sheet.texture.resource_path)
		assert_eq(sheet.play_texture.get_size(), sheet.texture.get_size(), "same size and layout")
		var labelled: Image = sheet.texture.get_image()
		var play: Image = sheet.play_texture.get_image()
		for i: int in sheet.frame_count():
			var r: Rect2i = sheet.region(i)
			var box: Rect2i = _label_rect(sheet, sheet.frames[i])
			box.position += r.position
			var inside: int = 0
			var outside: int = 0
			var face: Dictionary = {}
			for y: int in range(r.position.y, r.end.y):
				for x: int in range(r.position.x, r.end.x):
					var p: Color = play.get_pixel(x, y)
					var l: Color = labelled.get_pixel(x, y)
					if not box.has_point(Vector2i(x, y)):
						face[p.to_html()] = true
					# Two clear pixels are the same pixel: the importer's fix_alpha_border bleeds
					# neighbouring colour into clear ones, so their RGB may differ.
					if p == l or (p.a == 0.0 and l.a == 0.0):
						continue
					if box.has_point(Vector2i(x, y)):
						inside += 1
					else:
						outside += 1
			assert_gt(inside, 0, "%s %s: the label is gone" % [sheet.texture.resource_path, sheet.frames[i]])
			assert_eq(outside, 0, "%s %s: nothing else changed" % [sheet.texture.resource_path, sheet.frames[i]])
			# Where the label was, only the frame's own pattern colours: no leftover label box.
			var stray: int = 0
			for y: int in range(box.position.y, box.end.y):
				for x: int in range(box.position.x, box.end.x):
					if not face.has(play.get_pixel(x, y).to_html()):
						stray += 1
			assert_eq(stray, 0, "%s %s: the pattern runs under the label" % [sheet.texture.resource_path, sheet.frames[i]])
		# The gutters stay clear.
		for i: int in range(1, sheet.frame_count()):
			var gx: int = i * (sheet.frame_size.x + sheet.gutter) - 1
			for y: int in sheet.frame_size.y:
				assert_eq(play.get_pixel(gx, y).a, 0.0, "play gutter at x=%d y=%d" % [gx, y])


func test_label_free_sheets_only_for_the_labelled_ones() -> void:
	assert_null(_art.edges.play_texture, "the edge cues have no labels, so one sheet")
	assert_null(_art.land.play_texture, "the land sheet has no labels, so one sheet")
