extends GutTest
## E3-S58 (D50): the ground is drawn as a mesh over the bilinear surface the ball rolls on
## (course/terrain_mesh.gd), lit by its slope, with water flat at its level, side faces on the
## map's front edges, no cracks between tiles, and a picker that reads the drawn ground.

var _view: CourseView


func before_each() -> void:
	_view = CourseView.new()
	add_child_autofree(_view)


func _mesh(c: CourseData) -> TerrainMesh:
	var m := TerrainMesh.new()
	m.course = c
	m.sync()
	return m


## A ramp along x: column x stands at min(x / 2, 7) steps (a rise every 2 tiles), or falling
## along x when `down`.
func _ramp(down: bool = false) -> CourseData:
	var c := CourseData.create(16, 6, Surface.Type.ROUGH, 0)
	for y: int in c.height:
		for x: int in c.width:
			var h: int = mini(x / 2, CourseData.MAX_HEIGHT)
			c.set_tile(x, y, CourseData.MAX_HEIGHT - h if down else h, Surface.Type.FAIRWAY)
	return c


func test_every_vertex_sits_on_the_ground_the_ball_rolls_on() -> void:
	var c := HeightsFixture.build()
	var m := _mesh(c)
	var field := HeightField.new(c, BallParams.load_default())
	var off: int = 0
	var checked: int = 0
	for y: int in c.height:
		for x: int in c.width:
			var cell := Vector2i(x, y)
			if c.get_surface(x, y) == Surface.Type.WATER:
				continue
			var pts: PackedVector3Array = m.tile_geometry(cell)[0]
			for p: Vector3 in pts:
				var want: float = field.height_at((p.x + 0.5) * field.yards_per_tile,
						(p.y + 0.5) * field.yards_per_tile) / field.yards_per_step
				checked += 1
				if absf(p.z - want) > 0.0001:
					off += 1
	assert_gt(checked, 400 * 5, "every land tile's points")
	assert_eq(off, 0, "every vertex at height_at")


func test_drawn_points_are_the_iso_projection_of_the_vertices() -> void:
	var c := HeightsFixture.build()
	var m := _mesh(c)
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(4, 5), Vector2i(8, 14), Vector2i(0, 19)]:
		var pts: PackedVector3Array = m.tile_geometry(cell)[0]
		var part: Array = m.emit_tile(cell, 32.0)
		var screen: PackedVector2Array = part[0]
		assert_eq(screen.size(), pts.size())
		for i: int in pts.size():
			var want: Vector2 = Iso.tile_to_screen(Vector2(pts[i].x, pts[i].y), pts[i].z) - Vector2(0, 32)
			assert_almost_eq(screen[i], want, Vector2(0.001, 0.001), "%s point %d" % [cell, i])


func test_ground_at_samples_match_height_at_on_the_grid_and_between() -> void:
	var c := HeightsFixture.build()
	var field := HeightField.new(c, BallParams.load_default())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var worst: float = 0.0
	for n: int in 400:
		var t := Vector2(rng.randf_range(-0.5, 19.5), rng.randf_range(-0.5, 19.5))
		var cell := Vector2i(floori(t.x + 0.5), floori(t.y + 0.5))
		if c.get_surface(cell.x, cell.y) == Surface.Type.WATER:
			continue
		var want: float = field.height_at((t.x + 0.5) * 5.0, (t.y + 0.5) * 5.0) / field.yards_per_step
		assert_almost_eq(TerrainMesh.bilinear(c, t), want, 0.0001, "bilinear at %s" % t)
		worst = maxf(worst, absf(TerrainMesh.ground_at(c, t) - want))
	# Between grid points the drawn triangles cut the bilinear ground's twist: within a quarter
	# step at the default subdiv on this stress course (a 7-step pillar and a walled pit).
	assert_lt(worst, 0.5, "the drawn ground stays near height_at between its points")


func test_a_flat_course_gives_a_flat_mesh() -> void:
	var c := CourseData.create(12, 12, Surface.Type.ROUGH, 2)
	_view.show_course(c)
	var colors := {}
	for ch: TerrainMesh.Chunk in _view.chunks():
		assert_eq(ch.land_idx.size(), 0, "owned: no hatch")
		for col: Color in ch.cols:
			colors[col] = true
	assert_eq(colors.keys(), [Color.WHITE], "one shade everywhere: rough at the plot's height, unlit")
	var m := _view.terrain
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(5, 6), Vector2i(11, 11)]:
		assert_false(m.sloped(cell))
		var geo: Array = m.tile_geometry(cell)
		for p: Vector3 in geo[0] as PackedVector3Array:
			assert_eq(p.z, 2.0, "flat at 2")
		assert_eq((geo[1] as PackedInt32Array).size(), 4 * 3, "a fan of four triangles")
	# Only the two front edges show a side face, down to the base.
	assert_eq(m.tile_faces(Vector2i(5, 5)).size(), 0)
	assert_eq(m.tile_faces(Vector2i(11, 5)).size(), 1, "+x edge")
	assert_eq(m.tile_faces(Vector2i(11, 11)).size(), 2, "corner: both")
	var face: Array = m.tile_faces(Vector2i(5, 11))[0]
	assert_eq((face[1] as PackedVector3Array)[0].z, m.tuning.base_steps, "down to the base")
	assert_eq((face[0] as PackedVector3Array)[0].z, 2.0, "from the ground")


func test_a_one_step_rise_is_a_slope_across_the_two_half_tiles() -> void:
	var c := CourseData.create(8, 3, Surface.Type.ROUGH, 0)
	for y: int in 3:
		for x: int in range(4, 8):
			c.set_tile(x, y, 1, Surface.Type.ROUGH)
	var m := _mesh(c)
	assert_true(m.sloped(Vector2i(3, 1)) and m.sloped(Vector2i(4, 1)), "both tiles at the edge slope")
	assert_false(m.sloped(Vector2i(1, 1)) or m.sloped(Vector2i(6, 1)), "the rest is flat")
	assert_almost_eq(TerrainMesh.ground_at(c, Vector2(3.0, 1.0)), 0.0, 0.0001, "the low centre")
	assert_almost_eq(TerrainMesh.ground_at(c, Vector2(3.5, 1.0)), 0.5, 0.0001, "half way at the edge")
	assert_almost_eq(TerrainMesh.ground_at(c, Vector2(4.0, 1.0)), 1.0, 0.0001, "the high centre")
	assert_almost_eq(TerrainMesh.ground_at(c, Vector2(3.75, 1.2)), 0.75, 0.0001, "a ramp, not a step")
	for y: int in c.height:
		for x: int in c.width:
			var faces: int = m.tile_faces(Vector2i(x, y)).size()
			var edge: bool = x == c.width - 1 or y == c.height - 1
			if faces > 0:
				assert_true(edge, "no riser at (%d, %d): faces only on the map's edge" % [x, y])
			elif edge:
				assert_eq(c.get_height(x, y), 0, "the map's raised edge shows its side at (%d, %d)" % [x, y])


func test_neighbouring_tiles_meet_without_a_crack() -> void:
	var c := HeightsFixture.build()
	var m := _mesh(c)
	var gaps: Array[String] = []
	for y: int in c.height:
		for x: int in c.width:
			var cell := Vector2i(x, y)
			for side: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var next := cell + side
				if not c.in_bounds(next.x, next.y):
					continue
				var mine := _edge(m, cell, side, 0.5)
				var theirs := _edge(m, next, side, -0.5)
				if mine.keys() != theirs.keys():
					gaps.append("%s|%s: %s against %s" % [cell, next, mine.keys(), theirs.keys()])
					continue
				# Land on both sides meets at the same height; at water a bank face closes it.
				var water: bool = c.get_surface(x, y) == Surface.Type.WATER or c.get_surface(next.x, next.y) == Surface.Type.WATER
				for k: Vector2 in mine:
					if not water and absf(float(mine[k]) - float(theirs[k])) > 0.0001:
						gaps.append("%s|%s at %s: %.3f against %.3f" % [cell, next, k, mine[k], theirs[k]])
	assert_eq(gaps.size(), 0, "\n".join(gaps.slice(0, 5)))


## The points of `cell`'s mesh on its edge at `along` (+-0.5) on the axis of `side`: position
## (rounded) -> height.
func _edge(m: TerrainMesh, cell: Vector2i, side: Vector2i, along: float) -> Dictionary:
	var out := {}
	for p: Vector3 in m.tile_geometry(cell)[0] as PackedVector3Array:
		var d: float = (p.x - cell.x) if side.x == 1 else (p.y - cell.y)
		if absf(d - along) < 0.0001:
			out[Vector2(snappedf(p.x, 0.0001), snappedf(p.y, 0.0001))] = p.z
	var keys: Array = out.keys()
	keys.sort()
	var sorted := {}
	for k: Vector2 in keys:
		sorted[k] = out[k]
	return sorted


func test_water_lies_flat_at_its_level_with_a_bank_where_land_behind_stands_higher() -> void:
	var c := CourseData.create(8, 8, Surface.Type.ROUGH, 2)
	for y: int in range(3, 6):
		for x: int in range(3, 6):
			c.set_tile(x, y, 1, Surface.Type.WATER)
	var m := _mesh(c)
	for cell: Vector2i in [Vector2i(3, 3), Vector2i(4, 4), Vector2i(5, 5)]:
		for p: Vector3 in m.tile_geometry(cell)[0] as PackedVector3Array:
			assert_eq(p.z, 1.0, "water at its level at %s" % cell)
	assert_almost_eq(TerrainMesh.ground_at(c, Vector2(4.3, 3.6)), 1.0, 0.0001)
	# The land behind the pond (x 2) is higher: a bank face on its +x edge toward the camera.
	var bank: Array = m.tile_faces(Vector2i(2, 4))
	assert_eq(bank.size(), 1, "a bank on the land behind the water")
	for p: Vector3 in bank[0][1] as PackedVector3Array:
		assert_almost_eq(p.z, 1.0, 0.0001, "down to the water")
	for p: Vector3 in bank[0][0] as PackedVector3Array:
		assert_gt(p.z, 1.0, "from the land's edge")
	# In front of the pond the land is higher too: that face looks away and is not drawn.
	assert_eq(m.tile_faces(Vector2i(5, 4)).size(), 0, "water's front edge, land higher: hidden")


func test_a_slope_is_shaded_by_the_lighting_rule() -> void:
	var t := TerrainTuning.load_default()
	var m := _mesh(_ramp())
	var flat: float = m.light_for(Vector2.ZERO)
	assert_eq(flat, 1.0, "flat ground is unlit")
	# The ramp rises along +x: it faces -x, toward the light (behind the hills), so lighter.
	var g := Vector2(0.5, 0.0)
	var n := Vector3(-g.x * m.rise_per_step, 0.0, 1.0).normalized()
	var want: float = 1.0 + t.light_strength * Vector2(n.x, n.y).dot(t.light_dir.normalized())
	assert_almost_eq(m.light_for(g), want, 0.0001, "1 + strength * n.xy . L")
	assert_gt(m.light_for(g), flat, "a slope facing away from the camera is lighter")
	assert_lt(m.light_for(-g), flat, "one facing the camera darker")
	assert_almost_eq(m.light_for(g) - flat, flat - m.light_for(-g), 0.0001, "by the same amount")
	assert_gt(absf(m.light_for(Vector2(0.0, 0.5)) - flat), 0.02, "a rise along y reads too")
	# On the drawn ramp: a mid-slope vertex's colour is its height shade times that light.
	var c := _ramp()
	m = _mesh(c)
	var cell := Vector2i(5, 3)
	var geo: Array = m.tile_geometry(cell)
	var part: Array = m.emit_tile(cell, 0.0)
	var pts: PackedVector3Array = geo[0]
	var slopes: PackedVector2Array = geo[2]
	var cols: PackedColorArray = part[2]
	var lit: int = 0
	for i: int in pts.size():
		if slopes[i] == Vector2.ZERO:
			continue
		var shade: Color = m.shade(Surface.Type.FAIRWAY, pts[i].z, slopes[i], true)
		assert_almost_eq(cols[i].r, shade.r, 0.0001, "point %d" % i)
		assert_almost_eq(cols[i].r, minf(m.light_for(slopes[i]), m.caps[Surface.Type.FAIRWAY]), 0.0001,
				"fairway takes no height shade, only the light")
		lit += 1
	assert_gt(lit, 0, "the ramp's points are lit")


func test_light_is_held_in_its_band_and_under_the_frame_cap() -> void:
	var t := TerrainTuning.load_default()
	var m := _mesh(_ramp())
	for g: Vector2 in [Vector2(7, 7), Vector2(-7, -7), Vector2(7, -7), Vector2(0, -7)]:
		var l: float = m.light_for(g)
		assert_true(l >= t.light_min - 0.0001 and l <= t.light_max + 0.0001, "%s: %.3f" % [g, l])
	for f: int in Surface.COUNT:
		var col: Color = m.shade(f, 7.0, Vector2(-7, -7), true)
		assert_true(col.r <= m.caps[f] + 0.0001, "%s capped" % Surface.name_of(f))
		assert_true(col.r == col.g and col.g == col.b, "grey: value, not hue")


func test_the_height_shade_blends_between_whole_steps() -> void:
	var tuning := BuilderTuning.load_default()
	var m := _mesh(_ramp())
	var rough: int = Surface.Type.ROUGH
	for h: int in CourseData.MAX_HEIGHT:
		var lo: float = m.shade(rough, h, Vector2.ZERO, true).r
		var hi: float = m.shade(rough, h + 1, Vector2.ZERO, true).r
		var mid: float = m.shade(rough, h + 0.5, Vector2.ZERO, true).r
		assert_almost_eq(lo, minf(tuning.height_shade[h], m.caps[rough]), 0.0001)
		assert_almost_eq(mid, (lo + hi) * 0.5, 0.0001, "half way at %d.5" % h)
	var tinted: Color = m.shade(rough, 2.0, Vector2.ZERO, false)
	assert_eq(tinted, Color.WHITE * tuning.unowned_tint, "off owned land: times the tint")


func test_chunks_draw_back_to_front_and_objects_between_their_rows() -> void:
	var c := HeightsFixture.build()
	_view.show_course(c)
	var seen := {}
	for ch: TerrainMesh.Chunk in _view.chunks():
		assert_eq(ch.get_parent().get_parent(), _view, "under one Y-sorted child of the view")
		assert_true((ch.get_parent() as Node2D).y_sort_enabled)
		assert_eq(ch.position.y, float(Iso.depth_key(Vector2i(ch.row, 0))), "sorts at its row's key")
		for cell: Vector2i in _view.terrain.chunk_cells(Vector2i(ch.row, ch.index)):
			assert_eq(cell.x + cell.y, ch.row)
			assert_false(seen.has(cell), "each tile drawn once")
			seen[cell] = true
	assert_eq(seen.size(), c.width * c.height, "every tile")
	# An object on a tile draws over its row and under the next, at any height and offset.
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(0, 0), Vector2i(19, 19)]:
		var row_key: float = _view.chunk_at(cell).position.y
		var next_key: float = row_key + Iso.HALF_H
		for h: float in [0.0, 3.5, 7.0]:
			for offset: Vector2 in [Vector2.ZERO, Vector2(-0.49, -0.49), Vector2(0.49, 0.49), Vector2(0.49, -0.49)]:
				var key: float = Iso.object_sort_key(Vector2(cell) + offset, h)
				assert_gt(key, row_key, "over its row at %s %s" % [h, offset])
				assert_lt(key, next_key, "under the next row at %s %s" % [h, offset])


func test_an_edit_redraws_as_a_fresh_draw_would() -> void:
	var c := HeightsFixture.build()
	_view.show_course(c)
	var b := CourseBuilder.new(c)
	b.tiles_changed.connect(_view.refresh_cells)
	b.raise(Vector2i(10, 10), 3)
	b.paint(Vector2i(12, 9), Surface.Type.WATER, 1)
	b.lower(Vector2i(5, 5), 1)
	b.paint(Vector2i(19, 19), Surface.Type.BUNKER, 3)
	var fresh := CourseView.new()
	add_child_autofree(fresh)
	fresh.show_course(c)
	assert_eq(_view.terrain_digest(), fresh.terrain_digest(), "edited view equals a fresh one")
	b.undo()
	b.undo()
	b.undo()
	b.undo()
	fresh.show_course(c)
	assert_eq(_view.terrain_digest(), fresh.terrain_digest(), "and after the undos")


## E3-S16: a tile whose surface alone changed is written in place in its chunk
## (TerrainMesh.repaint_tile), not its chunk and its neighbours' rebuilt. On hilly, part-unowned
## land, batches of surface paint on slopes and flats, beside a height moved in the same batch,
## to and from water (rebuilt, since water changes the shape), and their undos, leave the view
## as a fresh draw would; a surface-only batch rebuilds no chunk.
func test_a_surface_only_batch_is_repainted_in_place_as_a_fresh_draw() -> void:
	var c := HeightsFixture.build()
	c.set_parcel_owned(Vector2i(0, 0), false)
	_view.show_course(c)
	var b := CourseBuilder.new(c)
	b.tiles_changed.connect(_view.refresh_cells)
	var fresh := CourseView.new()
	add_child_autofree(fresh)
	var kinds: Array[Surface.Type] = [Surface.Type.FAIRWAY, Surface.Type.BUNKER, Surface.Type.GREEN,
			Surface.Type.TREES, Surface.Type.ROUGH]
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	var strokes := 0
	for round: int in 6:
		b.begin_stroke()
		for i: int in 40:
			b.paint(Vector2i(rng.randi() % c.width, rng.randi() % c.height), kinds[rng.randi() % kinds.size()], 1)
		if round % 3 == 1:
			b.raise(Vector2i(rng.randi() % c.width, rng.randi() % c.height), 1)
		if round % 3 == 2:
			b.paint(Vector2i(rng.randi() % c.width, rng.randi() % c.height), Surface.Type.WATER, 1)
		b.end_stroke()
		strokes += 1
		fresh.show_course(c)
		assert_eq(_view.terrain_digest(), fresh.terrain_digest(), "after stroke %d" % round)
	for i: int in strokes:
		b.undo()
		fresh.show_course(c)
		assert_eq(_view.terrain_digest(), fresh.terrain_digest(), "after undo %d" % i)
	# Surface alone: no chunk is joined again, only written in place.
	var ch: TerrainMesh.Chunk = _view.chunk_at(Vector2i(10, 10))
	var before: Array = ch.parts[Vector2i(9, 11)]
	var at: int = ch.starts[Vector2i(10, 10)]
	b.paint(Vector2i(10, 10), Surface.Type.BUNKER, 1)
	assert_same(ch.parts[Vector2i(9, 11)], before, "the chunk's other tiles kept what they emitted")
	assert_eq(ch.starts[Vector2i(10, 10)], at, "the tile's points where they were")
	fresh.show_course(c)
	assert_eq(_view.terrain_digest(), fresh.terrain_digest(), "a bunker painted in place")


## E3-S16: a batch bigger than `refresh_tiles_per_frame` (an undo of a long drag) is drawn over
## the next frames, at most that many tiles a frame (one chunk past it at most), and ends as a
## fresh draw; a small batch is drawn at once.
func test_a_big_batch_is_drawn_over_frames_within_the_frame_budget() -> void:
	var c := CourseData.create(64, 64, Surface.Type.ROUGH, 0)
	for y: int in c.height:
		for x: int in c.width:
			c.set_tile(x, y, (x / 5 + y / 7) % 4, Surface.Type.ROUGH)
	_view.show_course(c)
	var b := CourseBuilder.new(c)
	b.tiles_changed.connect(_view.refresh_cells)
	var budget: int = _view.terrain.tuning.refresh_tiles_per_frame
	var m: TerrainMesh = _view.terrain
	var before: int = m.repainted + m.emitted
	b.paint(Vector2i(10, 10), Surface.Type.BUNKER, 1)
	assert_false(_view.drawing_pending(), "a one-tile paint is drawn at once")
	b.begin_stroke()
	for y: int in range(8, 30):
		for x: int in range(4, 60):
			b.paint(Vector2i(x, y), Surface.Type.FAIRWAY, 1)
	b.end_stroke()
	# Painted in one frame, the stroke's own tiles go over the budget too, and wait.
	assert_true(_view.drawing_pending(), "a frame's paints share its budget")
	_view.finish_drawing()
	before = m.repainted + m.emitted
	b.undo()
	var first: int = m.repainted + m.emitted - before
	assert_true(_view.drawing_pending(), "the undo's %d tiles wait for the next frames" % (22 * 56))
	assert_lte(first, budget + _view.terrain.tuning.chunk_tiles, "the undo's frame drew at most the budget")
	var frames := 0
	while _view.drawing_pending() and frames < 100:
		await wait_frames(1)
		assert_lte(_view.drawn_this_frame(), budget + _view.terrain.tuning.chunk_tiles, "frame %d" % frames)
		frames += 1
	assert_gt(frames, 2, "spread over several frames")
	assert_false(_view.drawing_pending())
	var fresh := CourseView.new()
	add_child_autofree(fresh)
	fresh.show_course(c)
	assert_eq(_view.terrain_digest(), fresh.terrain_digest(), "drawn over frames as a fresh draw")


# --- picking on the drawn ground ---

func test_the_picker_picks_the_tile_under_the_cursor_on_a_slope() -> void:
	var c := _ramp()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for n: int in 300:
		var t := Vector2(rng.randf_range(-0.45, 15.45), rng.randf_range(-0.45, 5.45))
		var want := Vector2i(floori(t.x + 0.5), floori(t.y + 0.5))
		# Keep clear of the tile edges, where either tile is a fair pick.
		if absf(t.x - want.x) > 0.48 or absf(t.y - want.y) > 0.48:
			continue
		var screen: Vector2 = Iso.tile_to_screen(t, TerrainMesh.ground_at(c, t))
		assert_eq(TilePicker.pick(c, screen), want, "the point at %s" % t)
		var hit: Vector3 = TilePicker.ground_point(c, screen)
		assert_almost_eq(Vector2(hit.x, hit.y), t, Vector2(0.01, 0.01), "the ground point at %s" % t)
	# Off the map, nothing.
	assert_eq(TilePicker.pick(c, Iso.tile_to_screen(Vector2(-3, 2), 0)), TilePicker.NONE)


func test_a_hill_in_front_hides_the_ground_behind_it() -> void:
	var c := CourseData.create(12, 12, Surface.Type.ROUGH, 0)
	c.set_tile(6, 6, 6, Surface.Type.GREEN)
	var behind: Vector2 = Iso.tile_to_screen(Vector2(4.2, 4.2), 0.0)
	assert_eq(Iso.screen_to_cell(behind, 0), Vector2i(4, 4), "a height-0 pick would take the tile behind")
	assert_eq(TilePicker.pick(c, behind), Vector2i(6, 6), "the hill in front is picked")
	var hidden: Vector2 = Iso.tile_to_screen(Vector2(5.0, 5.0), 0.0)
	assert_ne(TilePicker.pick(c, hidden), Vector2i(5, 5), "the foot behind the hill is hidden")


func test_a_side_face_picks_its_border_tile() -> void:
	var c := CourseData.create(6, 6, Surface.Type.ROUGH, 4)
	var p: Vector2 = Iso.tile_to_screen(Vector2(5.5, 2.0), 2.0)
	assert_eq(TilePicker.pick(c, p), Vector2i(5, 2), "the +x side, half way down")
	p = Iso.tile_to_screen(Vector2(3.0, 5.5), 1.0)
	assert_eq(TilePicker.pick(c, p), Vector2i(3, 5), "the +y side")
	assert_eq(TilePicker.pick(c, Iso.tile_to_screen(Vector2(3.0, 5.5), -1.0)), TilePicker.NONE, "under the base")


## What the view draws frontmost at `p`: every tile's triangles and faces as CourseView emits
## them, the last row drawn wins. Independent of TilePicker's ray.
func _reference_pick(m: TerrainMesh, c: CourseData, p: Vector2) -> Vector2i:
	var best := TilePicker.NONE
	var best_row: int = -1
	for y: int in c.height:
		for x: int in c.width:
			var cell := Vector2i(x, y)
			if x + y <= best_row:
				continue
			var part: Array = m.emit_tile(cell, 0.0)
			if _in_triangles(p, part[0], part[3]) or _in_triangles(p, part[5], part[7]):
				best = cell
				best_row = x + y
	return best


func _in_triangles(p: Vector2, pts: PackedVector2Array, tris: PackedInt32Array) -> bool:
	for i: int in range(0, tris.size(), 3):
		if Geometry2D.point_is_inside_triangle(p, pts[tris[i]], pts[tris[i + 1]], pts[tris[i + 2]]):
			return true
	return false


func test_pick_matches_what_is_drawn_frontmost() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var c := CourseData.create(8, 8)
	for y: int in 8:
		for x: int in 8:
			c.set_tile(x, y, rng.randi_range(0, 7), Surface.Type.WATER if rng.randf() < 0.15 else Surface.Type.ROUGH)
	var m := _mesh(c)
	var r := Rect2(Iso.tile_to_screen(Vector2(-0.5, 7.5), 7), Vector2.ZERO)
	r = r.expand(Iso.tile_to_screen(Vector2(7.5, -0.5), 7)).expand(Iso.tile_to_screen(Vector2(7.5, 7.5), 0))
	var misses: Array[String] = []
	var hits: int = 0
	for n: int in 800:
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
		var want: Vector2i = _reference_pick(m, c, p)
		var got: Vector2i = TilePicker.pick(c, p)
		if want != TilePicker.NONE:
			hits += 1
		if want != got:
			misses.append("%s: drawn %s, picked %s" % [p, want, got])
	assert_gt(hits, 400, "most samples land on the course")
	assert_eq(misses.size(), 0, "\n".join(misses.slice(0, 5)))

