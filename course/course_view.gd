class_name CourseView
extends Node2D
## Draws a CourseData isometrically (E1-S4). A reader only: it never writes the course.
##
## The ground (E3-S58, D50) is a mesh over the bilinear surface the ball rolls on, textured
## from the surface sheets and lit by its slope (course/terrain_mesh.gd, TerrainMesh, numbers
## in course/terrain_tuning.tres): a hill reads as a hill, not a cliff, and no risers are
## drawn. CourseData does not change: heights stay whole steps. The mesh is cut into chunks,
## a depth row (i + j) and chunk_tiles tiles along it each, every one a Y-sorted child at its
## row's Iso.depth_key, so the ground draws back to front and every object on a tile
## (Iso.object_sort_key) draws over its row and under the rows in front: a hill in front hides
## what stands behind it. It is built once per course (show_course); an edit rebuilds only the
## chunks round the tiles it changed (refresh_cells), a purchase its parcel's (refresh_parcel).
##
## Hole markers (E2-S2): a HoleMarker tee marker and pin for every placed tee and cup in
## CourseData, under one Y-sorted child at the origin, so each sorts with the terrain at
## Iso.object_sort_key on its tile (course/hole_marker.gd).
##
## Issue highlights (E2-S3): an IssueMarker on every tile where a hole rule fails, with its
## one-line reasons (course/issue_marker.gd), from show_issues, under a Y-sorted child at the
## origin. The diamond on the tile sorts with the terrain like a HoleMarker, so a hill in front
## hides it; the badge, leader line and text box draw over everything (z_index), so a fault
## behind a hill still shows without reading as being on the hill. The text boxes keep their
## screen size, so they are laid out in screen space at the current zoom (layout_issue_labels):
## nearest the camera first, each pushed up clear of the boxes already placed, but never more
## than BuilderTuning.issue_box_max_stack; past that it moves sideways instead, at most
## issue_box_max_side, and past both it collapses to its badge (E2-S17). A
## leader foot covered by a tile in front draws dashed and faded (IssueMarker.foot_hidden).
## Main shows them in Build only.
##
## Unowned land (E6-S5, D26, art/specs/land.md): the ground of a tile on a parcel the player
## does not own is modulated by BuilderTuning.unowned_tint (the shade), and the land sheet's
## hatch and parcel lines are drawn over it (the pattern; land_frame), following the slope.
## Fully owned land (New sandbox, every older file) draws without either. Shown in Build and
## Play: the line is the OB boundary (D29). refresh_parcel redraws a parcel after a purchase or
## its undo.
##
## Height shade (E6-S18, art/specs/surfaces.md): the land surfaces in BuilderTuning.height_shaded
## (rough, water, trees, oob) take the grey BuilderTuning.height_shade for their height, low
## ground darker, high ground lighter; between whole steps the ground's height blends the two
## (TerrainMesh.shade). Course surfaces (fairway, green, tee, bunker, cart path) keep 1 so their
## colour still names the lie. Above 1 a frame's shade is capped at its frame_headroom, so no
## coloured pixel clips and the shade stays value, not hue. The slope light multiplies it, under
## the same cap.
##
## Play art (E3-S55): with play_art on (Main sets it in Play) the ground draws its sheets'
## TileSheet.texture_for(true), the placeholder's label-free sheets, so the two-letter labels
## show in Build only. Only the chunks' textures change, not their geometry.
##
## Contours (E3-S57): `topo`, a TopoOverlay, draws contour lines Y-sorted into the terrain in
## Play (course/topo_overlay.gd); it traces again when a height changes.

## land_frame bits: the tile's edge toward x - 1, y - 1, x + 1, y + 1 lies on a parcel edge.
const LAND_EDGE_W: int = 1
const LAND_EDGE_N: int = 2
const LAND_EDGE_E: int = 4
const LAND_EDGE_S: int = 8
## frame_headroom: a pixel less saturated than this counts as grey (label chalk and ink), and
## may clip toward white without a hue shift.
const HUE_MIN_SAT: float = 0.1
## Screen px left between two issue text boxes when one is pushed up past the other.
const ISSUE_BOX_GAP: float = 4.0
## A changed tile's chunks are rebuilt this many tiles round it: its height moves the ground of
## the tiles beside it, and whether those are sloped moves the fans of the tiles beside them.
const REBUILD_REACH: int = 2

var course: CourseData:
	get:
		return _course

## The ground's mesh builder (E3-S58).
var terrain: TerrainMesh

var _course: CourseData
## Chunk key (TerrainMesh.chunk_key) -> TerrainMesh.Chunk.
var _chunks: Dictionary = {}
## Every tile's height when its chunks were last built, so an edit knows whether a height moved.
var _heights_seen: PackedByteArray = PackedByteArray()
var _ground_root: Node2D
var _holes_root: Node2D
var _markers: Array[HoleMarker] = []
var _issues_root: Node2D
var _issue_markers: Array[IssueMarker] = []
## The zoom (screen px per local unit) the issue boxes were last laid out at; 0 forces a layout.
var _issue_layout_scale: float = 0.0
## The zoom the tee markers' hole numbers were last sized for (layout_hole_labels).
var _hole_label_scale: float = 0.0
## How far past its resting height a text box may be pushed up, screen px
## (BuilderTuning.issue_box_max_stack).
var issue_max_stack: float = 0.0
## How far sideways off centre a text box may move, screen px (BuilderTuning.issue_box_max_side).
var issue_max_side: float = 0.0
## The smallest a hole marker shows on screen, times its 1x size (BuilderTuning
## marker_min_screen_scale, D45).
var marker_min_screen_scale: float = 0.5

## Whether the ground draws its sheets' Play textures (TileSheet.texture_for, E3-S55).
var play_art: bool = false:
	set(value):
		play_art = value
		terrain.play = value
		for ch: TerrainMesh.Chunk in _chunks.values():
			ch.texture = terrain.surface_texture()
			ch.land_texture = terrain.land_texture()
			ch.queue_redraw()

## The contour overlay (E3-S57): Main enables it in Play.
var topo: TopoOverlay

## Whether the issue highlights show (Build mode).
var issues_visible: bool = true:
	set(value):
		issues_visible = value
		_issues_root.visible = value


func _init() -> void:
	y_sort_enabled = true
	var tuning := BuilderTuning.load_default()
	issue_max_stack = tuning.issue_box_max_stack
	issue_max_side = tuning.issue_box_max_side
	marker_min_screen_scale = tuning.marker_min_screen_scale
	terrain = TerrainMesh.new(TerrainTuning.load_default(), TileArt.load_default(), tuning)
	# The ground's chunks Y-sort with everything else through this Y-sorted child at the origin.
	_ground_root = Node2D.new()
	_ground_root.name = "Ground"
	_ground_root.y_sort_enabled = true
	add_child(_ground_root)
	_holes_root = Node2D.new()
	_holes_root.name = "Holes"
	_holes_root.y_sort_enabled = true
	add_child(_holes_root)
	topo = TopoOverlay.new()
	add_child(topo)
	_issues_root = Node2D.new()
	_issues_root.name = "Issues"
	_issues_root.y_sort_enabled = true
	add_child(_issues_root)


## Draws `c` from scratch. Pass null to clear.
func show_course(c: CourseData) -> void:
	_course = c
	terrain.course = c
	for ch: TerrainMesh.Chunk in _chunks.values():
		_ground_root.remove_child(ch)
		ch.free()
	_chunks.clear()
	_heights_seen = PackedByteArray()
	if c != null:
		_heights_seen.resize(c.width * c.height)
		for y: int in c.height:
			for x: int in c.width:
				_heights_seen[y * c.width + x] = c.get_height(x, y)
		terrain.sync()
		for key: Vector2i in terrain.all_chunk_keys():
			var ch := terrain.make_chunk(key)
			_ground_root.add_child(ch)
			_chunks[key] = ch
	topo.show_course(c)
	refresh_holes()
	show_issues({})


## Rebuilds the tee marker and pin of every hole from CourseData. Call after holes change
## (E2-S3's tee and cup tools). A tee or cup not placed yet has no marker.
func refresh_holes() -> void:
	for m: HoleMarker in _markers:
		_holes_root.remove_child(m)
		m.free()
	_markers.clear()
	if _course == null:
		return
	for slot: int in _course.holes.size():
		var hole: HoleData = _course.holes[slot]
		for pair: Array in [[HoleMarker.Kind.TEE, hole.tee], [HoleMarker.Kind.PIN, hole.cup]]:
			var at: Vector2i = pair[1]
			if not _course.in_bounds(at.x, at.y):
				continue
			var m := HoleMarker.new(pair[0], hole.number, at)
			m.hole_label = _course.hole_label(slot)
			m.place(_course)
			m.text_scale = 1.0 / _view_scale()
			m.shape_scale = marker_shape_scale(_view_scale())
			_holes_root.add_child(m)
			_markers.append(m)


## Every hole marker drawn, tee and pin per hole in CourseData order.
func hole_markers() -> Array[HoleMarker]:
	return _markers.duplicate()


## The tee marker (or pin) of hole `number`, or null when it has none.
func hole_marker(number: int, kind: HoleMarker.Kind) -> HoleMarker:
	for m: HoleMarker in _markers:
		if m.hole_number == number and m.kind == kind:
			return m
	return null


## Highlights every failing rule in `issues` (CourseBuilder.issues: hole number -> Array of
## CourseValidator.Issue) on its tile, one IssueMarker per tile with a line per rule. An issue
## with no tile on the map (a hole with no tee and no cup) has no highlight. A marker whose
## tile shows the same rules as before is kept, not rebuilt (E3-S2 review: with nine holes
## failing, rebuilding every box on every check cost a frame), and the boxes are laid out again.
##
## `slot_issues` (CourseBuilder.slot_issues: each slot's own issues, in CourseData.holes order),
## when given, names each line's hole as the map does (CourseData.hole_label), so two holes
## sharing a number read "hole 4a" and "hole 4b" (E3-S27).
func show_issues(issues: Dictionary, slot_issues: Array = []) -> void:
	# Each tile's lines, in the validator's order: [rules, reasons, holes, names].
	var wanted := {}
	var order: Array[Vector2i] = []
	var name_of := {}
	var reason_of := {}
	if _course != null and slot_issues.size() == _course.holes.size():
		for slot: int in slot_issues.size():
			for issue: CourseValidator.Issue in slot_issues[slot]:
				name_of[issue] = _course.hole_label(slot)
				# Rule 1 puts a duplicate's issue on its twin's tee (CourseValidator._rule1). The
				# box stands on that tee, so it is named by the hole whose tee it is, and says
				# which hole it shares the number with (E3-S27 review: "hole 4b" on 4a's tee).
				var twin: int = _tee_slot(issue, slot)
				if twin >= 0:
					name_of[issue] = _course.hole_label(twin)
					reason_of[issue] = "shares number %d with hole %s" % [
							_course.holes[twin].number, _course.hole_label(slot)]
	if _course != null:
		for number: int in issues:
			for issue: CourseValidator.Issue in issues[number]:
				if not _course.in_bounds(issue.tile.x, issue.tile.y):
					continue
				if not wanted.has(issue.tile):
					wanted[issue.tile] = [PackedInt32Array(), PackedStringArray(), PackedInt32Array(),
							PackedStringArray()]
					order.append(issue.tile)
				# Packed arrays are values: append to a copy and store it back.
				var w: Array = wanted[issue.tile]
				var rules: PackedInt32Array = w[0]
				var reasons: PackedStringArray = w[1]
				var holes: PackedInt32Array = w[2]
				var names: PackedStringArray = w[3]
				rules.append(issue.rule)
				reasons.append(reason_of.get(issue, issue.reason))
				holes.append(number)
				names.append(name_of.get(issue, ""))
				wanted[issue.tile] = [rules, reasons, holes, names]
	var kept := {}
	for m: IssueMarker in _issue_markers:
		var w: Array = wanted.get(m.cell, [])
		if not w.is_empty() and not kept.has(m.cell) and m.shows(w[0], w[1], w[2], w[3]):
			kept[m.cell] = m
		else:
			_issues_root.remove_child(m)
			m.free()
	_issue_markers.clear()
	for cell: Vector2i in order:
		var m: IssueMarker = kept.get(cell)
		if m == null:
			m = IssueMarker.new(cell)
			m.place(_course)
			var w: Array = wanted[cell]
			for i: int in (w[0] as PackedInt32Array).size():
				m.add(w[0][i], w[1][i], w[2][i], w[3][i])
			_issues_root.add_child(m)
		_issue_markers.append(m)
	layout_issue_labels(_view_scale())


## The slot other than `own` whose tee a rule-1 `issue` of slot `own` stands on, or -1 for any
## other issue (a tee-on-cup rule 1 stands on its own tee).
func _tee_slot(issue: CourseValidator.Issue, own: int) -> int:
	if issue.rule != 1:
		return -1
	var number: int = _course.holes[own].number
	for i: int in _course.holes.size():
		if i != own and _course.holes[i].number == number and _course.holes[i].tee == issue.tile:
			return i
	return -1


## Lays the issue text boxes out in screen space at a zoom of `scale` screen px per local unit:
## the box nearest the camera (lowest on screen) stays just above its tile, and each one
## further back is pushed up until it overlaps no box already placed. A box that would be
## pushed more than issue_max_stack tries again moved sideways, to just past the edge of a box
## in its way, nearest first, but never more than issue_max_side. A box that fits nowhere
## within both limits collapses (IssueMarker.collapsed): its badge and diamond still show, and
## the hole panel lists its reasons. Sets every marker's text_scale, stack, shift and
## collapsed. CourseView reruns it when the zoom changes or a marker moves.
func layout_issue_labels(scale: float) -> void:
	_issue_layout_scale = scale
	var order: Array[IssueMarker] = _issue_markers.duplicate()
	order.sort_custom(func(a: IssueMarker, b: IssueMarker) -> bool:
		return a.draw_point().y > b.draw_point().y)
	var placed: Array[Rect2] = []
	for m: IssueMarker in order:
		m.text_scale = 1.0 / scale
		var anchor: Vector2 = m.draw_point() * scale
		var rest: Rect2 = m.box_rect(scale, 0.0)
		rest.position += anchor
		# Only boxes within reach of every allowed position can be in the way.
		var reach: Rect2 = rest.grow_individual(issue_max_side + ISSUE_BOX_GAP,
			issue_max_stack + rest.size.y + ISSUE_BOX_GAP, issue_max_side + ISSUE_BOX_GAP, 0.0)
		var near: Array[Rect2] = []
		var sides: Array[float] = [0.0]
		for r: Rect2 in placed:
			if r.intersects(reach):
				near.append(r)
				# Just right of r, or just left of it.
				sides.append(r.end.x + ISSUE_BOX_GAP - rest.position.x)
				sides.append(r.position.x - ISSUE_BOX_GAP - rest.end.x)
		sides.sort_custom(func(a: float, b: float) -> bool: return absf(a) < absf(b))
		var done: bool = false
		for side: float in sides:
			if absf(side) > issue_max_side:
				break
			var push: float = _clear_push(m, scale, anchor, side, near)
			if push <= issue_max_stack:
				var rect: Rect2 = m.box_rect(scale, push, side)
				rect.position += anchor
				placed.append(rect)
				m.stack = push
				m.shift = side
				m.collapsed = false
				done = true
				break
		if not done:
			m.stack = 0.0
			m.shift = 0.0
			m.collapsed = true


## How far `m`'s box, `side` px sideways, must be pushed up to clear every box in `placed`,
## or a value past issue_max_stack as soon as it would go that far.
func _clear_push(m: IssueMarker, scale: float, anchor: Vector2, side: float, placed: Array[Rect2]) -> float:
	var push: float = 0.0
	var rect: Rect2 = m.box_rect(scale, push, side)
	rect.position += anchor
	var moved: bool = true
	while moved and push <= issue_max_stack:
		moved = false
		for r: Rect2 in placed:
			if rect.intersects(r):
				push += rect.end.y - r.position.y + ISSUE_BOX_GAP
				rect = m.box_rect(scale, push, side)
				rect.position += anchor
				moved = true
				break
	return push


## Every issue text box as laid out, in screen px at the last layout's zoom (one per marker,
## in issue_markers() order; an empty Rect2 for a collapsed one).
func issue_label_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for m: IssueMarker in _issue_markers:
		if m.collapsed:
			out.append(Rect2())
			continue
		var r: Rect2 = m.box_rect(_issue_layout_scale, m.stack, m.shift)
		r.position += m.draw_point() * _issue_layout_scale
		out.append(r)
	return out


func _process(_delta: float) -> void:
	var s: float = _view_scale()
	if not is_equal_approx(s, _hole_label_scale):
		layout_hole_labels(s)
	# The text boxes keep their screen size, so a zoom change needs a fresh layout.
	if _issue_markers.is_empty():
		return
	if not is_equal_approx(s, _issue_layout_scale):
		layout_issue_labels(s)


## Keeps every tee marker's hole number at its screen size at a zoom of `scale` screen px per
## local unit (HoleMarker.text_scale). CourseView reruns it when the zoom changes.
func layout_hole_labels(scale: float) -> void:
	_hole_label_scale = scale
	var k: float = marker_shape_scale(scale)
	for m: HoleMarker in _markers:
		m.text_scale = 1.0 / scale
		m.shape_scale = k


## How large a tee marker or pin is drawn at a zoom of `scale` screen px per local unit (D45):
## its own size, or grown so it is never under marker_min_screen_scale of its 1x size on screen
## (BuilderTuning, 0.5: at the farthest step, 0.175x, it shows as at 0.5x).
func marker_shape_scale(scale: float) -> float:
	return maxf(1.0, marker_min_screen_scale / maxf(scale, 0.0001))


## The z_index of a piece standing on the map (the player's ball, a guest's figure and ball)
## at a zoom of `scale` screen px per local unit (D45, E3-S9 review): 1 where the hole markers
## grow over the terrain (under `min_screen_scale`, BuilderTuning marker_min_screen_scale), so
## those pieces still Y-sort with the grown markers (a ball on its tee draws over the tee's
## blocks and number, a guest in front of a pin over the pin); 0 at that zoom and nearer, where
## everything sorts with the terrain as before.
static func lifted_z(scale: float, min_screen_scale: float) -> int:
	return 1 if min_screen_scale / maxf(scale, 0.0001) > 1.0 + 0.0001 else 0


## Screen px per local unit (the camera zoom), 1 outside the tree.
func _view_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var s: float = get_global_transform_with_canvas().get_scale().x
	return s if s > 0.0 else 1.0


## Every issue highlight drawn, one per tile at fault.
func issue_markers() -> Array[IssueMarker]:
	return _issue_markers.duplicate()


## Every ground chunk drawn, in no set order.
func chunks() -> Array[TerrainMesh.Chunk]:
	var out: Array[TerrainMesh.Chunk] = []
	for ch: TerrainMesh.Chunk in _chunks.values():
		out.append(ch)
	return out


## The chunk drawing `cell`'s ground, or null.
func chunk_at(cell: Vector2i) -> TerrainMesh.Chunk:
	if _course == null or not _course.in_bounds(cell.x, cell.y):
		return null
	return _chunks.get(terrain.chunk_key(cell))


## What the ground draws now, chunk by chunk in key order: [key, sort y, points, colours, uvs,
## triangles, land points, land uvs, land triangles, face points, face colours, face
## triangles]. Two views drawing the same course give equal digests (tests compare an edited
## view against one drawn from scratch).
func terrain_digest() -> Array:
	var keys: Array = _chunks.keys()
	keys.sort()
	var out: Array = []
	for key: Vector2i in keys:
		var ch: TerrainMesh.Chunk = _chunks[key]
		out.append([key, ch.position.y, ch.pts, ch.cols, ch.uvs, ch.idx, ch.land_pts, ch.land_uvs,
				ch.land_idx, ch.face_pts, ch.face_cols, ch.face_idx])
	return out


## Redraws one tile after an edit (E1-S5). A hole marker on the tile moves to its new ground.
func refresh_cell(cell: Vector2i) -> void:
	refresh_cells([cell])


## refresh_cell for a batch of tiles written together (one builder tiles_changed, E3-S16): every
## chunk within REBUILD_REACH tiles of a changed tile is rebuilt once however many changed tiles
## share it, and each hole marker and issue box is tested once per batch, so an undo of a big
## drag costs in proportion to its tiles. Leaves the view as show_course would. Main calls it
## with each tiles_changed.
func refresh_cells(cells: Array[Vector2i]) -> void:
	if _course == null or cells.is_empty():
		return
	var changed := {}
	var dirty := {}
	var moved: bool = false
	for cell: Vector2i in cells:
		changed[cell] = true
		if not _course.in_bounds(cell.x, cell.y):
			continue
		var i: int = cell.y * _course.width + cell.x
		var h: int = _course.get_height(cell.x, cell.y)
		if _heights_seen[i] != h:
			_heights_seen[i] = h
			moved = true
		for dy: int in range(-REBUILD_REACH, REBUILD_REACH + 1):
			for dx: int in range(-REBUILD_REACH, REBUILD_REACH + 1):
				var c := cell + Vector2i(dx, dy)
				if _course.in_bounds(c.x, c.y):
					var key := terrain.chunk_key(c)
					if not dirty.has(key):
						dirty[key] = {}
					dirty[key][c] = true
	terrain.sync(cells)
	for key: Vector2i in dirty:
		terrain.build_chunk(_chunks[key], dirty[key])
	if moved:
		topo.mark_dirty()
	for m: HoleMarker in _markers:
		if changed.has(m.cell):
			m.place(_course)
	# An edit in front of a fault may cover or uncover its leader's foot.
	for m: IssueMarker in _issue_markers:
		if changed.has(m.cell):
			m.place(_course)
			_issue_layout_scale = 0.0
		elif moved:
			m.foot_hidden = IssueMarker.covered(_course, m.cell)


## Redraws every tile of parcel `parcel` after it was bought or a purchase was undone (the
## builder's land_changed). Its tiles change shade and overlay; no neighbour's does, since a
## parcel line depends only on where the parcels meet.
func refresh_parcel(parcel: Vector2i) -> void:
	if _course == null:
		return
	var r: Rect2i = _course.parcel_rect(parcel)
	var dirty := {}
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var key := terrain.chunk_key(Vector2i(x, y))
			if not dirty.has(key):
				dirty[key] = {}
			dirty[key][Vector2i(x, y)] = true
	for key: Vector2i in dirty:
		terrain.build_chunk(_chunks[key], dirty[key])


## Screen rectangle (local to this node) covering every tile at every height.
func screen_bounds() -> Rect2:
	if _course == null:
		return Rect2()
	var w: float = _course.width - 0.5
	var h: float = _course.height - 0.5
	var r := Rect2(Iso.tile_to_screen(Vector2(-0.5, -0.5), 0.0), Vector2.ZERO)
	for corner: Vector2 in [Vector2(w, -0.5), Vector2(-0.5, h), Vector2(w, h)]:
		r = r.expand(Iso.tile_to_screen(corner, 0.0))
	r = r.expand(Iso.tile_to_screen(Vector2(-0.5, -0.5), CourseData.MAX_HEIGHT))
	return r


## Which land frame tile (x, y) shows: -1 on an owned tile, else the mask of its edges that
## lie on a parcel edge (LAND_EDGE_W toward x - 1, _N y - 1, _E x + 1, _S y + 1), the map
## border included, which is also the frame's index in the land sheet (art/specs/land.md).
static func land_frame(c: CourseData, x: int, y: int) -> int:
	if c.is_owned(x, y):
		return -1
	var p: Vector2i = c.parcel_of(x, y)
	var mask: int = 0
	if c.parcel_of(x - 1, y) != p or not c.in_bounds(x - 1, y):
		mask |= LAND_EDGE_W
	if c.parcel_of(x, y - 1) != p or not c.in_bounds(x, y - 1):
		mask |= LAND_EDGE_N
	if c.parcel_of(x + 1, y) != p or not c.in_bounds(x + 1, y):
		mask |= LAND_EDGE_E
	if c.parcel_of(x, y + 1) != p or not c.in_bounds(x, y + 1):
		mask |= LAND_EDGE_S
	return mask


## The grey shade each surface frame's top draws with at height 0 to 7, indexed [frame][h]:
## `shades` for a frame named in `shaded`, capped at its frame_headroom; 1 at every height
## for any other frame.
static func top_shades(sheet: TileSheet, shades: PackedFloat32Array, shaded: PackedStringArray) -> Array[PackedFloat32Array]:
	assert(shades.size() == CourseData.MAX_HEIGHT + 1, "height_shade needs one entry per height")
	var out: Array[PackedFloat32Array] = []
	for i: int in sheet.frame_count():
		var row := PackedFloat32Array()
		var on: bool = sheet.frames[i] in shaded
		var cap: float = frame_headroom(sheet, i) if on else 1.0
		for h: int in CourseData.MAX_HEIGHT + 1:
			row.append(minf(shades[h], maxf(cap, 1.0)) if on else 1.0)
		out.append(row)
	return out


## The largest modulate frame `i` takes before a coloured pixel's brightest channel passes 1:
## 1 / that channel over the frame's opaque pixels with saturation at least HUE_MIN_SAT.
## Near-grey pixels (the chalk and ink of the 2-letter labels) are left out: clipping them only
## moves them toward white, not to another hue.
static func frame_headroom(sheet: TileSheet, i: int) -> float:
	var img: Image = sheet.texture.get_image()
	var r: Rect2i = sheet.region(i)
	var top: float = 0.0
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.0 and c.s >= HUE_MIN_SAT:
				top = maxf(top, maxf(c.r, maxf(c.g, c.b)))
	return INF if top <= 0.0 else 1.0 / top
