class_name CourseView
extends Node2D
## Draws a CourseData isometrically (E1-S4). A reader only: it never writes the course.
##
## One TileMapLayer per height for surface tops (0 to 7) and one per step for risers (the wall
## between height k and k + 1, k = 0 to 6). Each layer sits at its height's screen offset, so
## every cell lands where Iso.tile_to_screen says. All layers are Y-sorted together under this
## node. Each layer's y_sort_origin moves its sort key back to the tile's ground point plus a
## small per-layer bias, so every cell sorts at Iso.riser_sort_key / Iso.top_sort_key. That is
## the painter's order of art/specs/risers.md: tiles back to front by depth (i + j), and within
## one tile the risers bottom up, then the top. Objects use Iso.object_sort_key to join it.
##
## Faces hidden by a neighbor at equal or greater height are skipped (`left` / `right` frames).
## Off-map neighbors read as height 0, so the map edge shows its walls.
##
## Edge cues (E1-S10, D5, art/specs/edge_cue.md): a rise toward x - 1 or y - 1 faces away
## from the camera and has no riser, so the higher tile draws a lip line along that back edge
## instead, one line for one step and two for two or more. One cue layer per height, at the
## same sort key as that height's tops; Y-sort breaks the tie by tree order, so the cue layers
## are added after every top and draw over their tile's top, still under objects on it.
## A back edge on the map border gets no cue.
##
## Hole markers (E2-S2): a HoleMarker tee marker and pin for every placed tee and cup in
## CourseData, under one Y-sorted child at the origin, so each sorts with the terrain at
## Iso.object_sort_key on its tile's top (course/hole_marker.gd).
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
## Unowned land (E6-S5, D26, art/specs/land.md): every top, riser and edge cue of a tile on a
## parcel the player does not own draws through the DIM_ALT alternative tile, modulated by
## BuilderTuning.unowned_tint (the shade), and one Land layer per height lays the land sheet's
## hatch and parcel lines over its top (the pattern; land_frame), at the top's sort key and
## after the cue layers, so it draws over the top and cue and a hill in front hides it. Fully
## owned land (New sandbox, every older file) draws exactly as before. Shown in Build and Play:
## the line is the OB boundary (D29). refresh_parcel redraws a parcel after a purchase or its
## undo.
##
## Height shade (E6-S18, art/specs/surfaces.md): every surface top draws through the
## alternative tile top_alt(h, owned). On the land surfaces in BuilderTuning.height_shaded
## (rough, water, trees, oob) it is modulated by the grey BuilderTuning.height_shade[h] (times
## unowned_tint off owned land), a value step per height: low ground darker, high ground
## lighter. So a plateau reads from a lowland, and across a rise that faces away from the
## camera, where no riser shows, the lighter side is the higher one. Course surfaces (fairway,
## green, tee, bunker, cart path) keep shade 1 at every height so their colour still names the
## lie. Above 1 a frame's shade is capped at its frame_headroom, so no coloured pixel clips
## and the shade stays value, not hue. Risers and edge cues keep their own values. The shade
## at the D10 plot's height is 1, so a New sandbox draws as before. A modulate, not new
## frames: the draw count and the tile sheet do not change.

## Atlas source ids in the shared TileSet.
const SURFACE_SOURCE: int = 0
const RISER_SOURCE: int = 1
const EDGE_SOURCE: int = 2
const LAND_SOURCE: int = 3
## The alternative tile id of every riser and edge frame drawn on unowned land, and the bit
## that marks unowned land in a surface top's alternative id (top_alt).
const DIM_ALT: int = 1
## frame_headroom: a pixel less saturated than this counts as grey (label chalk and ink), and
## may clip toward white without a hue shift.
const HUE_MIN_SAT: float = 0.1
## land_frame bits: the tile's edge toward x - 1, y - 1, x + 1, y + 1 lies on a parcel edge.
const LAND_EDGE_W: int = 1
const LAND_EDGE_N: int = 2
const LAND_EDGE_E: int = 4
const LAND_EDGE_S: int = 8
## Rises of this many steps or more share one cue (two lines). Matches the art's frame names.
const EDGE_MAX_STEPS: int = 2
## Screen px left between two issue text boxes when one is pushed up past the other.
const ISSUE_BOX_GAP: float = 4.0
## _drawn's value for a tile not drawn since the layers were cleared.
const NOT_DRAWN: int = 255

var course: CourseData:
	get:
		return _course

var _course: CourseData
var _art: TileArt
var _tile_set: TileSet
var _tops: Array[TileMapLayer] = []
var _risers: Array[TileMapLayer] = []
var _edges: Array[TileMapLayer] = []
var _lands: Array[TileMapLayer] = []
var _riser_atlas: Dictionary = {}
## The height each tile was last drawn at (NOT_DRAWN after a clear), so a redraw erases only
## the layers that hold it (E3-S16).
var _drawn: PackedByteArray = PackedByteArray()
## The height each tile had when its four neighbours were last drawn for it (show_course or
## refresh_cells on that tile), so a surface-only change skips them (E3-S16). Drawing a tile
## as another's neighbour leaves its entry, so its own refresh still reaches its neighbours.
var _neighbours_saw: PackedByteArray = PackedByteArray()
var _edge_atlas: Dictionary = {}
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
	_art = TileArt.load_default()
	_tile_set = _make_tile_set(_art, tuning.unowned_tint, top_shades(_art.surfaces, tuning.height_shade, tuning.height_shaded))
	for k: int in CourseData.MAX_HEIGHT + 1:
		if k < CourseData.MAX_HEIGHT:
			_risers.append(_make_layer("Risers%d" % k, k, Iso.riser_sort_key(Vector2i.ZERO, k)))
		_tops.append(_make_layer("Tops%d" % k, k, Iso.top_sort_key(Vector2i.ZERO, k)))
	# After every top, so a cue wins its sort-key tie with its own top.
	var edge_shift: int = _art.edges.anchor.y - _art.edges.frame_size.y / 2
	for k: int in CourseData.MAX_HEIGHT + 1:
		_edges.append(_make_layer("Edges%d" % k, k, Iso.top_sort_key(Vector2i.ZERO, k), edge_shift))
	# After every cue, so the hatch and parcel lines draw over their own top and cue.
	for k: int in CourseData.MAX_HEIGHT + 1:
		_lands.append(_make_layer("Land%d" % k, k, Iso.top_sort_key(Vector2i.ZERO, k)))
	_holes_root = Node2D.new()
	_holes_root.name = "Holes"
	_holes_root.y_sort_enabled = true
	add_child(_holes_root)
	_issues_root = Node2D.new()
	_issues_root.name = "Issues"
	_issues_root.y_sort_enabled = true
	add_child(_issues_root)
	for frame: String in _art.risers.frames:
		_riser_atlas[StringName(frame)] = Vector2i(_art.risers.frame_index(StringName(frame)), 0)
	for frame: String in _art.edges.frames:
		_edge_atlas[StringName(frame)] = Vector2i(_art.edges.frame_index(StringName(frame)), 0)


## Draws `c` from scratch. Pass null to clear.
func show_course(c: CourseData) -> void:
	_course = c
	for layer: TileMapLayer in _tops + _risers + _edges + _lands:
		layer.clear()
	_drawn = PackedByteArray()
	_neighbours_saw = PackedByteArray()
	if c != null:
		_drawn.resize(c.width * c.height)
		_drawn.fill(NOT_DRAWN)
		for y: int in c.height:
			for x: int in c.width:
				_draw_cell(Vector2i(x, y))
		_neighbours_saw = _drawn.duplicate()
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
	for hole: HoleData in _course.holes:
		for pair: Array in [[HoleMarker.Kind.TEE, hole.tee], [HoleMarker.Kind.PIN, hole.cup]]:
			var at: Vector2i = pair[1]
			if not _course.in_bounds(at.x, at.y):
				continue
			var m := HoleMarker.new(pair[0], hole.number, at)
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
func show_issues(issues: Dictionary) -> void:
	# Each tile's lines, in the validator's order: [rules, reasons, holes].
	var wanted := {}
	var order: Array[Vector2i] = []
	if _course != null:
		for number: int in issues:
			for issue: CourseValidator.Issue in issues[number]:
				if not _course.in_bounds(issue.tile.x, issue.tile.y):
					continue
				if not wanted.has(issue.tile):
					wanted[issue.tile] = [PackedInt32Array(), PackedStringArray(), PackedInt32Array()]
					order.append(issue.tile)
				# Packed arrays are values: append to a copy and store it back.
				var w: Array = wanted[issue.tile]
				var rules: PackedInt32Array = w[0]
				var reasons: PackedStringArray = w[1]
				var holes: PackedInt32Array = w[2]
				rules.append(issue.rule)
				reasons.append(issue.reason)
				holes.append(number)
				wanted[issue.tile] = [rules, reasons, holes]
	var kept := {}
	for m: IssueMarker in _issue_markers:
		var w: Array = wanted.get(m.cell, [])
		if not w.is_empty() and not kept.has(m.cell) and m.shows(w[0], w[1], w[2]):
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
				m.add(w[0][i], w[1][i], w[2][i])
			_issues_root.add_child(m)
		_issue_markers.append(m)
	layout_issue_labels(_view_scale())


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


## Redraws one tile after an edit, plus, when its height changed, the two back neighbors whose
## walls it may now hide or reveal and the two front neighbors whose edge cues depend on its
## height. Call from
## the builder after it writes a tile (E1-S5). A hole marker on the tile moves to its new top.
func refresh_cell(cell: Vector2i) -> void:
	refresh_cells([cell])


## refresh_cell for a batch of tiles written together (one builder tiles_changed, E3-S16):
## each tile is drawn once however many changed tiles share it, its neighbours only when its
## height changed, a surface-only change sets just its top, and each hole marker and issue box
## is tested once per batch, not once per tile, so an undo of a big drag costs in proportion to
## its tiles. Leaves the view as
## refresh_cell on each tile would. Main calls it with each tiles_changed.
func refresh_cells(cells: Array[Vector2i]) -> void:
	if _course == null or cells.is_empty():
		return
	# A neighbour's walls and cues read only this tile's height, so a tile whose height its
	# neighbours were last drawn with (a surface-only change) redraws alone.
	var changed := {}
	var draw := {}
	var moved: bool = false
	for cell: Vector2i in cells:
		changed[cell] = true
		if not _course.in_bounds(cell.x, cell.y):
			continue
		var i: int = cell.y * _course.width + cell.x
		var h: int = _course.get_height(cell.x, cell.y)
		if _drawn[i] != h:
			draw[cell] = true
		if _neighbours_saw[i] != h:
			_neighbours_saw[i] = h
			moved = true
			for c: Vector2i in [cell + Vector2i(-1, 0), cell + Vector2i(0, -1),
					cell + Vector2i(1, 0), cell + Vector2i(0, 1)]:
				if _course.in_bounds(c.x, c.y):
					draw[c] = true
	for c: Vector2i in draw:
		_draw_cell(c)
	# A changed tile still at the height it was drawn at, with no neighbour's height moved in
	# this batch, has risers, edge cue and land frame as drawn (they read only heights and
	# parcels, and refresh_parcel redraws a parcel): only its surface top is set (E3-S16 review).
	for cell: Vector2i in changed:
		if not draw.has(cell) and _course.in_bounds(cell.x, cell.y):
			_draw_top(cell)
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
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			_draw_cell(Vector2i(x, y))


## The layer holding surface tops at height `h`.
func top_layer(h: int) -> TileMapLayer:
	return _tops[h]


## The layer holding riser step `k` (the wall between height k and k + 1).
func riser_layer(k: int) -> TileMapLayer:
	return _risers[k]


## The layer holding edge cues on tiles at height `h`.
func edge_layer(h: int) -> TileMapLayer:
	return _edges[h]


## The layer holding the unowned-land hatch and parcel lines on tiles at height `h`.
func land_layer(h: int) -> TileMapLayer:
	return _lands[h]


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


## Which riser frame tile (x, y) shows at step k: &"both", &"left", &"right", or &"" when
## both faces are hidden or the tile is not that tall. Left face looks at (x, y + 1),
## right face at (x + 1, y).
static func riser_frame(c: CourseData, x: int, y: int, k: int) -> StringName:
	if k >= c.get_height(x, y):
		return &""
	var left: bool = c.get_height(x, y + 1) <= k
	var right: bool = c.get_height(x + 1, y) <= k
	if left and right:
		return &"both"
	if left:
		return &"left"
	if right:
		return &"right"
	return &""


## Which edge cue frame tile (x, y) shows: &"" for none, else "l<n>" for a rise from its
## back-left neighbor (x - 1, y), "r<n>" from its back-right neighbor (x, y - 1), or both
## ("l1r2"). n is the rise in steps, capped at EDGE_MAX_STEPS. Lower or level neighbors and
## off-map ones give no cue; a higher neighbor's riser already shows that step.
static func edge_cue_frame(c: CourseData, x: int, y: int) -> StringName:
	var h: int = c.get_height(x, y)
	var frame: String = ""
	var left: int = _rise(c, h, x - 1, y)
	var right: int = _rise(c, h, x, y - 1)
	if left > 0:
		frame += "l%d" % left
	if right > 0:
		frame += "r%d" % right
	return StringName(frame)


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


## The alternative tile id of a surface top at height `h`, on owned land or not: one per
## height and ownership, each modulated by its height's shade (and the unowned tint).
static func top_alt(h: int, owned: bool) -> int:
	return h * 2 + (0 if owned else DIM_ALT)


static func _rise(c: CourseData, h: int, x: int, y: int) -> int:
	if not c.in_bounds(x, y):
		return 0
	return clampi(h - c.get_height(x, y), 0, EDGE_MAX_STEPS)


## Sets only the surface top of `cell`, drawn at its current height (refresh_cells).
func _draw_top(cell: Vector2i) -> void:
	var h: int = _course.get_height(cell.x, cell.y)
	_tops[h].set_cell(cell, SURFACE_SOURCE, Vector2i(_course.get_surface(cell.x, cell.y), 0),
			top_alt(h, _course.is_owned(cell.x, cell.y)))


func _draw_cell(cell: Vector2i) -> void:
	var h: int = _course.get_height(cell.x, cell.y)
	var land: int = land_frame(_course, cell.x, cell.y)
	var alt: int = 0 if land < 0 else DIM_ALT
	# Only the layers this cell was last drawn on can hold it (E3-S16): its old height's top,
	# cue and land layers, and its risers below the old height.
	var i: int = cell.y * _course.width + cell.x
	var old: int = _drawn[i]
	_drawn[i] = h
	if old != NOT_DRAWN and old != h:
		_tops[old].erase_cell(cell)
		_edges[old].erase_cell(cell)
		_lands[old].erase_cell(cell)
	_tops[h].set_cell(cell, SURFACE_SOURCE, Vector2i(_course.get_surface(cell.x, cell.y), 0),
			top_alt(h, land < 0))
	# riser_frame for every step below h, from the two front neighbours read once.
	var left_h: int = _course.get_height(cell.x, cell.y + 1)
	var right_h: int = _course.get_height(cell.x + 1, cell.y)
	for k: int in h:
		var frame: StringName = (&"both" if left_h <= k and right_h <= k else &"left" if left_h <= k
				else &"right" if right_h <= k else &"")
		if frame.is_empty():
			if old != NOT_DRAWN:
				_risers[k].erase_cell(cell)
		else:
			_risers[k].set_cell(cell, RISER_SOURCE, _riser_atlas[frame], alt)
	if old != NOT_DRAWN:
		for k: int in range(h, mini(old, _risers.size())):
			_risers[k].erase_cell(cell)
	var cue: StringName = edge_cue_frame(_course, cell.x, cell.y)
	if not cue.is_empty():
		_edges[h].set_cell(cell, EDGE_SOURCE, _edge_atlas[cue], alt)
	elif old != NOT_DRAWN:
		_edges[h].erase_cell(cell)
	if land >= 0:
		_lands[h].set_cell(cell, LAND_SOURCE, Vector2i(land, 0))
	elif old != NOT_DRAWN:
		_lands[h].erase_cell(cell)


## `shift` moves the layer up by that many pixels and its sort origin down by as many, for a
## sheet whose anchor sits below its frame's center; the sort key stays the same.
func _make_layer(layer_name: String, h: int, bias: int, shift: int = 0) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = _tile_set
	layer.y_sort_enabled = true
	# Godot puts cell (0, 0)'s center at (HALF_W, HALF_H); shift it onto Iso's origin, then up
	# by the height. The sort origin undoes the height shift and adds the bias.
	layer.position = Vector2(-Iso.HALF_W, -Iso.HALF_H - h * Iso.STEP_PX - shift)
	layer.y_sort_origin = h * Iso.STEP_PX + bias + shift
	add_child(layer)
	return layer


## `tint` is the modulate of the DIM_ALT alternative of every riser and edge frame; each
## surface frame gets a top_alt alternative per height and ownership, modulated by that
## frame's `shades` entry for the height (top_shades; times `tint` off owned land).
static func _make_tile_set(art: TileArt, tint: Color, shades: Array[PackedFloat32Array]) -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(Iso.TILE_W, Iso.TILE_H)
	ts.add_source(_make_surface_source(art.surfaces, tint, shades), SURFACE_SOURCE)
	ts.add_source(_make_source(art.risers, tint), RISER_SOURCE)
	ts.add_source(_make_source(art.edges, tint), EDGE_SOURCE)
	ts.add_source(_make_source(art.land), LAND_SOURCE)
	return ts


## One atlas source per sheet, a tile per frame; with a `tint`, each frame also gets the
## DIM_ALT alternative modulated by it.
static func _make_source(sheet: TileSheet, tint: Variant = null) -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = sheet.texture
	src.texture_region_size = sheet.frame_size
	src.separation = Vector2i(sheet.gutter, 0)
	for i: int in sheet.frame_count():
		src.create_tile(Vector2i(i, 0))
		if tint != null:
			src.create_alternative_tile(Vector2i(i, 0), DIM_ALT)
			src.get_tile_data(Vector2i(i, 0), DIM_ALT).modulate = tint
	return src


## The surface sheet's source: every frame i gets top_alt(h, owned) for each height h,
## modulated by the grey shades[i][h], times `tint` when not owned.
static func _make_surface_source(sheet: TileSheet, tint: Color, shades: Array[PackedFloat32Array]) -> TileSetAtlasSource:
	var src := _make_source(sheet)
	for i: int in sheet.frame_count():
		var coords := Vector2i(i, 0)
		for h: int in CourseData.MAX_HEIGHT + 1:
			var shade := Color(shades[i][h], shades[i][h], shades[i][h])
			for owned: bool in [true, false]:
				var alt: int = top_alt(h, owned)
				if alt != 0:
					src.create_alternative_tile(coords, alt)
				src.get_tile_data(coords, alt).modulate = shade if owned else shade * tint
	return src


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
