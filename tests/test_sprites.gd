extends GutTest
## E5-S3: the final sprite sheets (scripts/art_sprites.py, D62) keep their specs (art/specs/):
## sizes, frame order, anchors, palette-only opaque pixels; the trees stand 10 yd tall and sort
## with guests; the ball and the hole markers draw from their sheets.

const PALETTE_PATH: String = "res://art/palette.gpl"


func _palette() -> Dictionary:
	var colors: Dictionary = {}
	for line: String in FileAccess.get_file_as_string(PALETTE_PATH).split("\n"):
		var t: String = line.strip_edges()
		if t.is_empty() or t.begins_with("#") or t.begins_with("GIMP") or t.begins_with("Name:") \
				or t.begins_with("Columns:"):
			continue
		var parts: PackedStringArray = t.replace("\t", " ").split(" ", false)
		colors[Color8(parts[0].to_int(), parts[1].to_int(), parts[2].to_int()).to_html(false)] = parts[3]
	return colors


func test_every_sprite_sheet_is_palette_only_and_opaque_or_clear() -> void:
	var palette := _palette()
	for path: String in ["res://art/sprites/golfer_idle.png", "res://art/sprites/golfer_walk.png",
			"res://art/sprites/golfer_swing.png", "res://art/sprites/trees.png",
			"res://art/sprites/decor.png", "res://art/sprites/ball.png",
			"res://art/sprites/hole_markers.png", "res://art/sprites/clubhouse.png"]:
		var img: Image = (load(path) as Texture2D).get_image()
		var bad: Dictionary = {}
		for y: int in img.get_height():
			for x: int in img.get_width():
				var c: Color = img.get_pixel(x, y)
				if c.a == 0.0:
					continue
				if c.a != 1.0 or not palette.has(c.to_html(false)):
					bad[c.to_html()] = true
		assert_eq(bad.size(), 0, "%s: off-palette %s" % [path, bad.keys()])


func test_no_placeholder_sprites_remain() -> void:
	for res: Resource in [load("res://art/sprites/golfer.tres"), load(ClubhouseView.PATH),
			load(TreeView.PATH), load(DecorView.PATH), load(BallArt.PATH)]:
		var sheets: Array = [res] if res is TileSheet else [(res as GolferArt).idle, (res as GolferArt).walk, (res as GolferArt).swing]
		for s: TileSheet in sheets:
			assert_false(s.texture.resource_path.contains("placeholder"), s.texture.resource_path)
	assert_false(HoleMarker.SHEET_PATH.contains("placeholder"))


func test_trees_are_ten_yards_tall() -> void:
	var sheet := load(TreeView.PATH) as TileSheet
	assert_eq(sheet.frames, PackedStringArray(["a", "b", "c"]))
	assert_eq(sheet.frame_size, Vector2i(64, 96))
	assert_eq(sheet.anchor, Vector2i(32, 88))
	var img: Image = sheet.texture.get_image()
	for i: int in sheet.frame_count():
		var f: Image = img.get_region(sheet.region(i))
		var top: int = -1
		var foot: int = -1
		for y: int in 96:
			for x: int in 64:
				if f.get_pixel(x, y).a > 0.0:
					if top < 0:
						top = y
					foot = y
		# block_height: 10 yd, 5 height steps, 80 px at 1x (E5-S3).
		assert_eq(sheet.anchor.y - top, 5 * Iso.STEP_PX, "%s: 80 px from the foot to the crown" % sheet.frames[i])
		assert_eq(foot, sheet.anchor.y, "%s: the trunk's foot on the anchor row" % sheet.frames[i])


func test_a_tree_stands_on_every_trees_tile_and_sorts_with_guests() -> void:
	var c := CourseData.create(10, 10, Surface.Type.ROUGH, 1)
	for cell: Vector2i in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(2, 7)]:
		c.set_tile(cell.x, cell.y, 3, Surface.Type.TREES)
	var view := CourseView.new()
	add_child_autofree(view)
	view.show_course(c)
	assert_eq(view.trees.tree_count(), 3)
	var row: TreeView.Row = view.trees.row_of(Vector2i(4, 4))
	assert_not_null(row)
	# A guest stands on ground; its sort key is Iso.object_sort_key (GuestView). One a tile
	# behind the tree (smaller depth row) sorts under it, so the crown hides it; one in front sorts
	# over the trunk.
	var behind: float = Iso.object_sort_key(Vector2(3.6, 3.6), 1)
	var beside_behind: float = Iso.object_sort_key(Vector2(4.0, 3.0), 2)
	var in_front: float = Iso.object_sort_key(Vector2(4.6, 4.6), 1)
	assert_lt(behind, row.position.y, "a guest behind the tree draws first: the crown covers it")
	assert_lt(beside_behind, row.position.y)
	assert_gt(in_front, row.position.y, "a guest in front draws over it")
	# Painting the trees away takes the tree with it.
	c.set_tile(4, 4, 3, Surface.Type.ROUGH)
	view.refresh_cell(Vector2i(4, 4))
	assert_eq(view.trees.tree_count(), 2)
	assert_null(view.trees.row_of(Vector2i(4, 4)))


func test_tree_variants_are_fixed_per_tile() -> void:
	var seen: Dictionary = {}
	for y: int in 8:
		for x: int in 8:
			var v: int = TreeView.variant(Vector2i(x, y), 3)
			assert_eq(v, TreeView.variant(Vector2i(x, y), 3), "the same on every load")
			seen[v] = true
	assert_eq(seen.size(), 3, "all three crowns appear")


func test_the_guest_ball_differs_from_the_players_by_more_than_size() -> void:
	var sheet := BallArt.sheet()
	assert_eq(sheet.frames, PackedStringArray(["player", "player_spin", "guest", "guest_spin"]))
	var img: Image = sheet.texture.get_image()
	var player: Image = img.get_region(sheet.region_named(&"player"))
	var guest: Image = img.get_region(sheet.region_named(&"guest"))
	var lum := func(f: Image) -> float:
		var s: float = 0.0
		var n: int = 0
		for y: int in 8:
			for x: int in 8:
				if f.get_pixel(x, y).a > 0.0:
					s += f.get_pixel(x, y).get_luminance()
					n += 1
		return s / n
	assert_gt(lum.call(player) - lum.call(guest), 0.1, "the player's ball is the lighter, in grayscale too")
	assert_ne(img.get_region(sheet.region_named(&"player_spin")).get_data(), player.get_data(), "a spin frame")
	assert_true(BallArt.spin_at(0.1) != BallArt.spin_at(0.0), "the flight alternates")


func test_hole_marker_frames_keep_their_spec() -> void:
	var img: Image = (load(HoleMarker.SHEET_PATH) as Texture2D).get_image()
	assert_eq(img.get_size(), Vector2i(72, 36), "tee_block 8, cup 12, three pins 16, 1 px gutters")
	var pin: Array = HoleMarker.SHEET_FRAMES[&"pin_0"]
	var r: Rect2 = pin[0]
	var foot: Vector2 = pin[1]
	var top: int = 99
	for y: int in int(r.size.y):
		if img.get_pixel(int(r.position.x + foot.x), y).a > 0.0:
			top = mini(top, y)
	assert_eq(int(foot.y) - top, 31, "the pole stands 30 px over the cup, its ink cap on top")
	for f: StringName in HoleMarker.SHEET_FRAMES:
		var rr: Rect2 = HoleMarker.SHEET_FRAMES[f][0]
		assert_true(Rect2(Vector2.ZERO, Vector2(img.get_size())).encloses(rr), "%s inside the sheet" % f)
