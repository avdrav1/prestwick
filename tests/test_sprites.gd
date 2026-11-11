extends GutTest
## E5-S3: the final sprite sheets (scripts/art_sprites.py, D62) keep their specs (art/specs/):
## sizes, frame order, anchors, palette-only opaque pixels; the trees stand 10 yd tall and sort
## with guests; the ball and the hole markers draw from their sheets.

const PALETTE_PATH: String = "res://art/palette.gpl"
const NineHoles := preload("res://tests/fixtures/nine_holes.gd")


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


## The trees as [row key y, foot, tint] per tile, for comparing two views.
func _trees_of(view: CourseView) -> Dictionary:
	var out: Dictionary = {}
	for row: Node in view.trees.get_children():
		var r := row as TreeView.Row
		for cell: Vector2i in r.trees:
			var t: Array = r.trees[cell]
			out[cell] = [r.position.y, t[0], t[1], t[2]]
	return out


func test_tree_edits_redraw_only_what_they_change_and_match_a_fresh_view() -> void:
	# E5-S15: refresh_cells works tile by tile. A paint that neither adds nor removes trees nor
	# moves a height redraws no row; one that does leaves the trees as a fresh show_course would.
	var c := CourseData.create(16, 16, Surface.Type.ROUGH, 2)
	for y: int in range(3, 12):
		for x: int in range(3, 12):
			if (x + 2 * y) % 3 != 0:
				c.set_tile(x, y, 2, Surface.Type.TREES)
	var view := CourseView.new()
	add_child_autofree(view)
	view.show_course(c)
	var rows: Array[Node] = view.trees.get_children()
	# Fairway painted over rough: no tree changes, every Row node is the same object.
	var fair: Array[Vector2i] = []
	for x: int in 16:
		if c.get_surface(x, 14) == Surface.Type.ROUGH:
			c.set_tile(x, 14, 2, Surface.Type.FAIRWAY)
			fair.append(Vector2i(x, 14))
	view.refresh_cells(fair)
	assert_eq(view.trees.get_children(), rows, "a paint off the trees keeps every row")
	# Trees in and out, and heights moved under and beside trees.
	var edits: Array[Vector2i] = []
	for cell: Vector2i in [Vector2i(4, 4), Vector2i(5, 5), Vector2i(6, 7), Vector2i(10, 3)]:
		c.set_tile(cell.x, cell.y, 2, Surface.Type.ROUGH)
		edits.append(cell)
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(13, 13)]:
		c.set_tile(cell.x, cell.y, 2, Surface.Type.TREES)
		edits.append(cell)
	for cell: Vector2i in [Vector2i(7, 7), Vector2i(8, 9), Vector2i(2, 2)]:
		c.set_tile(cell.x, cell.y, 5, c.get_surface(cell.x, cell.y))
		edits.append(cell)
	view.refresh_cells(edits)
	var fresh := CourseView.new()
	add_child_autofree(fresh)
	fresh.show_course(c)
	assert_eq(view.trees.tree_count(), fresh.trees.tree_count())
	assert_eq(_trees_of(view), _trees_of(fresh), "every tree's row, frame, foot and tint as a fresh view's")
	assert_eq(view.trees.get_child_count(), fresh.trees.get_child_count(), "no empty row left behind")


func test_a_trees_foot_is_the_drawn_ground_at_its_tile_centre() -> void:
	# E5-S15: TreeView stands a tree at its tile's own height, reading no neighbour; that holds
	# only while the drawn ground at a land tile's centre is its height.
	var c: CourseData = NineHoles.land()
	for y: int in range(0, c.height, 3):
		for x: int in range(0, c.width, 3):
			if c.get_surface(x, y) != Surface.Type.WATER:
				assert_almost_eq(TerrainMesh.ground_at(c, Vector2(x, y)), float(c.get_height(x, y)), 1e-6,
						"tile (%d, %d)" % [x, y])


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
