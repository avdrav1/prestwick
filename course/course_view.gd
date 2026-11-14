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
## issue_box_max_side, and past both it collapses to its badge (E2-S17). Since E3-S40 the boxes
## also keep clear of every tee's hole number and every issue badge, and of the framed hole's
## line of play where they can (`framed_slot`), so at the farther zooms crowded boxes collapse to
## their badges rather than cover a label; a badge on a tee stands past its number. A
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
##
## The clubhouse (E5-S10, D60): `clubhouse`, a Y-sorted ClubhouseView child of this view,
## drawn over its footprint and sorted with the terrain, markers and guests at its front
## tile (course/clubhouse_view.gd). show_course places it and refresh_clubhouse moves it (Main
## calls it on CourseBuilder.clubhouse_changed). Below marker_min_screen_scale (0.175x) it draws
## at z 1 like the grown markers and the guests (lifted_z), so it still sorts with the guests.
##
## Trees (E5-S3): `trees`, a Y-sorted TreeView child, stands a tree 80 px tall on every trees
## tile, sorted with guests and markers by its row (course/tree_view.gd); show_course,
## refresh_cells and refresh_parcel keep it in step.
##
## Line of play (E3-S46, D47): `play_lines`, a LineOfPlay, draws each hole's tee -> turn -> cup
## line on the ground, Y-sorted into the terrain, in Build (course/line_of_play.gd). Main hands
## it the builder's lines after every check (show_play_lines); a height change redraws it then.

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
## Screen px between a tee's hole number and an issue badge on the same tile (E3-S40).
const BADGE_GAP: float = 2.0
## Screen px an issue box keeps from the framed hole's line of play (E3-S40).
const LINE_CLEAR: float = 2.0
## A changed tile's chunks are rebuilt this many tiles round it: its height moves the ground of
## the tiles beside it, and whether those are sloped moves the fans of the tiles beside them.
const REBUILD_REACH: int = 2
## E3-S16: a tile that turned to or from water, its height unmoved, rebuilds only this far: its
## own ground changes (flat at its level, or sloped), so the fans beside it (their edge points)
## and the bank faces of the tiles behind it (-x, -y), but no neighbour's slope.
const WATER_REACH: int = 1
## E3-S16: edited tiles _drain sorts (_classify) for each tile of its budget.
const CLASSIFY_PER_TILE: int = 4
## E3-S74: the bit _heights_marked sets on a water tile (heights take the three below it).
const WATER_MARK: int = 8
## E3-S74: how far a tile's moved height or water reaches what a marker reads. A marker's own
## ground (its tile's, its tee blocks', its diamond's) reads the 3 x 3 heights round its tile
## (TerrainMesh.ground_in). An issue box's foot is covered by ground drawn in front of it on its
## screen point, which lies on tiles (x + d, y + d) for d up to (MAX_HEIGHT + 0.5) / 2, each
## drawn from its own 3 x 3: so 2 tiles behind to 6 in front.
const MARK_NEAR: int = 1
const MARK_BEHIND: int = 2
const MARK_FRONT: int = 6
## E3-S74: spare issue boxes kept at most (_spare_issues).
const SPARE_ISSUES_MAX: int = 32

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
## E3-S16: ground work a big batch left for the next frames (chunk key -> {tile: true}): chunks
## to emit again (a height or water moved near those tiles) and tiles to repaint in place (their
## surface alone changed). At most TerrainTuning.refresh_tiles_per_frame tiles are drawn a frame
## (_drain); chunk_at and terrain_digest finish it first.
var _pending_build: Dictionary = {}
var _pending_paint: Dictionary = {}
## The edited tiles not yet sorted into that work (_classify), and how far the sorting has got.
var _pending_cells: Array[Vector2i] = []
## Each tile's shape as the markers last followed it (refresh_cells, at once): its height, plus
## WATER_MARK when it is water (a water tile's ground lies flat at its level, E3-S74).
var _heights_marked: PackedByteArray = PackedByteArray()
var _pending_at: int = 0
## The tiles _drain has drawn since this node's last _process ended (a frame's share of the
## budget), and in the frame before.
var _drained: int = 0
var _last_drained: int = 0
var _ground_root: Node2D
var _holes_root: Node2D
var _markers: Array[HoleMarker] = []
var _issues_root: Node2D
var _issue_markers: Array[IssueMarker] = []
## E3-S74: issue boxes a check dropped, hidden under _issues_root (tile -> IssueMarker), kept
## while the ground they were placed on stands (_follow_shape frees one a shape change reaches),
## so a box wanted on that tile again is filled, not placed again (an IssueMarker's placing, its
## foot's ray and its two rings on the ground, is most of a check's issue boxes: a breaking
## drag's release built nine, 0.3 ms each, the very ones its undo had just dropped).
var _spare_issues: Dictionary = {}
## The zoom (screen px per local unit) the issue boxes were last laid out at; 0 forces a layout.
var _issue_layout_scale: float = 0.0
## The zoom the tee markers' hole numbers were last sized for (layout_hole_labels).
var _hole_label_scale: float = 0.0
## The slot (CourseData.holes index) of the hole framed in Build (Main.frame_hole), whose line of
## play the issue boxes keep off where they can (E3-S40); -1 for none.
var framed_slot: int = -1:
	set(value):
		if value != framed_slot:
			framed_slot = value
			_issue_layout_scale = 0.0
## How far past its resting height a text box may be pushed up, screen px
## (BuilderTuning.issue_box_max_stack).
var issue_max_stack: float = 0.0
## How far sideways off centre a text box may move, screen px (BuilderTuning.issue_box_max_side).
var issue_max_side: float = 0.0
## The smallest a hole marker shows on screen, times its 1x size (BuilderTuning
## marker_min_screen_scale, D45).
var marker_min_screen_scale: float = 0.5
## The pins' pennant wave (E7-S1): seconds a frame (BuilderTuning.pennant_frame_s) and how long
## it has waved. One clock for every pin, in Build and Play, at every zoom.
var pennant_frame_s: float = 0.18
var pennant_time: float = 0.0

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
## The clubhouse (E5-S10).
var clubhouse: ClubhouseView
## The trees standing on trees tiles (E5-S3).
var trees: TreeView
## Benches, flags and signs (E5-S3).
var decor: DecorView
## Footbridges over water (E14-S1).
var bridges: BridgeView
## The line of play (E3-S46): Main enables it in Build.
var play_lines: LineOfPlay

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
	pennant_frame_s = tuning.pennant_frame_s
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
	clubhouse = ClubhouseView.new()
	add_child(clubhouse)
	trees = TreeView.new()
	add_child(trees)
	decor = DecorView.new()
	add_child(decor)
	bridges = BridgeView.new()
	add_child(bridges)
	topo = TopoOverlay.new()
	add_child(topo)
	play_lines = LineOfPlay.new()
	add_child(play_lines)
	_issues_root = Node2D.new()
	_issues_root.name = "Issues"
	_issues_root.y_sort_enabled = true
	add_child(_issues_root)


## Draws `c` from scratch. Pass null to clear.
func show_course(c: CourseData) -> void:
	_course = c
	terrain.course = c
	framed_slot = -1
	for ch: TerrainMesh.Chunk in _chunks.values():
		_ground_root.remove_child(ch)
		ch.free()
	_chunks.clear()
	_pending_build.clear()
	_pending_paint.clear()
	_pending_cells.clear()
	_pending_at = 0
	_heights_seen = PackedByteArray()
	if c != null:
		_heights_seen.resize(c.width * c.height)
		_heights_marked.resize(c.width * c.height)
		# E18-S5: the packed tiles read in place (get_height, _marked_shape), not calls a tile.
		var tiles: PackedByteArray = c.packed_tiles()
		var water: int = Surface.Type.WATER
		for i: int in tiles.size():
			var t: int = tiles[i]
			_heights_seen[i] = t >> 4
			_heights_marked[i] = (t >> 4) | (WATER_MARK if (t & 0x0F) == water else 0)
		terrain.sync()
		for key: Vector2i in terrain.all_chunk_keys():
			var ch := terrain.make_chunk(key)
			_ground_root.add_child(ch)
			_chunks[key] = ch
	topo.show_course(c)
	play_lines.show_course(c)
	# Another course: every marker afresh (refresh_holes keeps those it would draw the same, and
	# show_issues fills a spare box).
	for m: HoleMarker in _markers:
		_holes_root.remove_child(m)
		m.free()
	_markers.clear()
	for m: IssueMarker in _spare_issues.values():
		_free_issue(m)
	_spare_issues.clear()
	refresh_holes()
	refresh_clubhouse()
	trees.show_course(c)
	decor.show_course(c)
	bridges.show_course(c)
	show_issues({})


## Draws the decor as the course has it now (E5-S3): Main calls it on CourseBuilder.decor_changed.
func refresh_decor(_cell: Vector2i = Vector2i.ZERO) -> void:
	decor.refresh()


## Draws the clubhouse where the course has it now (E5-S10): after a move, a turn or its undo.
func refresh_clubhouse() -> void:
	clubhouse.show_clubhouse(_course)
	clubhouse.z_index = lifted_z(_view_scale(), marker_min_screen_scale)


## Rebuilds the tee marker and pin of every hole from CourseData. Call after holes change
## (E2-S3's tee and cup tools). A tee or cup not placed yet has no marker. A marker that would
## be drawn the same (its kind, hole number, name, tile and label side) is kept as it stands
## (refresh_cells keeps it on its ground), the others made afresh, and the tee numbers laid out
## again only when a marker was made or removed (E3-S74: a breaking drag's release and its undo
## change only which holes are open, and freeing and rebuilding all eighteen markers cost their
## frames 1.6 ms).
func refresh_holes() -> void:
	var spare := {}
	for m: HoleMarker in _markers:
		var k := _marker_key(m.kind, m.hole_number, m.hole_label, m.cell, m.label_side)
		if not spare.has(k):
			spare[k] = []
		(spare[k] as Array).append(m)
	var kept: Array[HoleMarker] = []
	var changed: bool = false
	if _course != null:
		for slot: int in _course.holes.size():
			var hole: HoleData = _course.holes[slot]
			var label: String = _course.hole_label(slot)
			for pair: Array in [[HoleMarker.Kind.TEE, hole.tee], [HoleMarker.Kind.PIN, hole.cup]]:
				var at: Vector2i = pair[1]
				if not _course.in_bounds(at.x, at.y):
					continue
				# The tee's number stands beside the block away from its cup (E3-S66).
				var side: float = 1.0
				if pair[0] == HoleMarker.Kind.TEE and _course.in_bounds(hole.cup.x, hole.cup.y):
					side = HoleMarker.side_away_from(hole.tee, hole.cup)
				var k := _marker_key(pair[0], hole.number, label, at, side)
				var same: Array = spare.get(k, [])
				if not same.is_empty():
					kept.append(same.pop_back())
					continue
				var m := HoleMarker.new(pair[0], hole.number, at)
				m.hole_label = label
				m.label_side = side
				m.place(_course)
				m.text_scale = 1.0 / _view_scale()
				m.shape_scale = marker_shape_scale(_view_scale())
				_holes_root.add_child(m)
				kept.append(m)
				changed = true
	for k: String in spare:
		for m: HoleMarker in spare[k]:
			_holes_root.remove_child(m)
			m.free()
			changed = true
	_markers = kept
	if changed:
		layout_hole_labels(_view_scale())


## What refresh_holes compares to keep a marker: everything it is made from.
static func _marker_key(kind: HoleMarker.Kind, number: int, label: String, cell: Vector2i,
		side: float) -> String:
	return "%d:%d:%s:%d:%d:%d" % [kind, number, label, cell.x, cell.y, signi(int(side))]


## Draws every hole's line of play (D47, D51): `lines` one per slot, [tee, cup] or [tee, turn,
## cup] in tile coordinates (CourseBuilder.slot_lines). Main calls it after every check, so a
## tee, cup or corner edit moves the line.
func show_play_lines(lines: Array[PackedVector2Array]) -> void:
	play_lines.show_lines(lines)


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
## A box dropped is kept hidden as its tile's spare while the ground it stands on does not move
## (_spare_issues), and a box wanted there again is that spare filled with its new lines.
##
## `slot_issues` (CourseBuilder.slot_issues: each slot's own issues, in CourseData.holes order),
## when given, names each line's hole as the map does (CourseData.hole_label), so two holes
## sharing a number read "hole 4a" and "hole 4b" (E3-S27).
func show_issues(issues: Dictionary, slot_issues: Array = []) -> void:
	# Each tile's lines, in the validator's order: [rules, reasons, holes, names].
	var wanted := {}
	var order: Array[Vector2i] = []
	var name_of := {}
	if _course != null and slot_issues.size() == _course.holes.size():
		for slot: int in slot_issues.size():
			for issue: CourseValidator.Issue in slot_issues[slot]:
				# A duplicate's rule 1 stands on its own tee and names its twin (E3-S41).
				name_of[issue] = _course.hole_label(slot)
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
				reasons.append(issue.reason)
				holes.append(number)
				names.append(name_of.get(issue, ""))
				wanted[issue.tile] = [rules, reasons, holes, names]
	var kept := {}
	for m: IssueMarker in _issue_markers:
		var w: Array = wanted.get(m.cell, [])
		if not w.is_empty() and not kept.has(m.cell) and m.shows(w[0], w[1], w[2], w[3]):
			kept[m.cell] = m
		else:
			_spare_issue(m)
	_issue_markers.clear()
	for cell: Vector2i in order:
		var m: IssueMarker = kept.get(cell)
		if m == null:
			var w: Array = wanted[cell]
			m = _spare_issues.get(cell)
			if m != null:
				_spare_issues.erase(cell)
				m.visible = true
				if m.shows(w[0], w[1], w[2], w[3]):
					_issue_markers.append(m)
					continue  # its lines too, and their wrapped box
				m.clear()
			else:
				m = IssueMarker.new(cell)
				m.place(_course)
				_issues_root.add_child(m)
			for i: int in (w[0] as PackedInt32Array).size():
				m.add(w[0][i], w[1][i], w[2][i], w[3][i])
		_issue_markers.append(m)
	layout_issue_labels(_view_scale())


## Hides issue box `m`, dropped by a check, as the spare on its tile (one a tile, at most
## SPARE_ISSUES_MAX, the oldest freed first).
func _spare_issue(m: IssueMarker) -> void:
	var old: IssueMarker = _spare_issues.get(m.cell)
	if old != null:
		_spare_issues.erase(m.cell)
		_free_issue(old)
	if _spare_issues.size() >= SPARE_ISSUES_MAX:
		var first: Vector2i = _spare_issues.keys()[0]
		_free_issue(_spare_issues[first])
		_spare_issues.erase(first)
	m.visible = false
	_spare_issues[m.cell] = m


func _free_issue(m: IssueMarker) -> void:
	_issues_root.remove_child(m)
	m.free()


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
	if _issue_markers.is_empty():
		return  # E3-S16: nothing to lay out (an undo reran show_issues with no faults)
	var order: Array[IssueMarker] = _issue_markers.duplicate()
	order.sort_custom(func(a: IssueMarker, b: IssueMarker) -> bool:
		return a.draw_point().y > b.draw_point().y)
	# Labels a box must not cover (E3-S40): every tee's hole number and every issue badge. A
	# badge on a tee stands past its number.
	var labels: Array[Rect2] = []
	var tee_label := {}
	for hm: HoleMarker in _markers:
		var r: Rect2 = hm.label_rect(scale)
		if r.size != Vector2.ZERO:
			tee_label[hm.cell] = maxf(tee_label.get(hm.cell, 0.0), r.end.x)
			r.position += hm.draw_point() * scale
			labels.append(r)
	for m: IssueMarker in _issue_markers:
		m.badge_clear = tee_label[m.cell] + BADGE_GAP if tee_label.has(m.cell) else 0.0
		var r: Rect2 = m.badge_rect(scale)
		r.position += m.draw_point() * scale
		labels.append(r)
	var line: Array[Rect2] = framed_line_rects(scale)
	var placed: Array[Rect2] = []
	for m: IssueMarker in order:
		m.text_scale = 1.0 / scale
		var anchor: Vector2 = m.draw_point() * scale
		var rest: Rect2 = m.box_rect(scale, 0.0)
		rest.position += anchor
		# Only rects within reach of every allowed position can be in the way.
		var reach: Rect2 = rest.grow_individual(issue_max_side + ISSUE_BOX_GAP,
			issue_max_stack + rest.size.y + ISSUE_BOX_GAP, issue_max_side + ISSUE_BOX_GAP, 0.0)
		var near: Array[Rect2] = []
		# Sideways tries start just past a box in the way; a label only blocks (a tee number or
		# badge is small, and a try past each of them costs more than it finds).
		var sides_from: int = 0
		for r: Rect2 in placed:
			if r.intersects(reach):
				near.append(r)
		sides_from = near.size()
		for r: Rect2 in labels:
			if r.intersects(reach):
				near.append(r)
		var near_line: Array[Rect2] = []
		for r: Rect2 in line:
			if r.intersects(reach):
				near_line.append(r)
		# Off the framed hole's line where it can (E3-S40), else as before.
		var spot: Array = []
		if not near_line.is_empty():
			# Boxes and the line both offer sideways tries: just past the line is off it.
			var with_line: Array[Rect2] = near.slice(0, sides_from)
			with_line.append_array(near_line)
			with_line.append_array(near.slice(sides_from))
			spot = _find_spot(m, scale, anchor, rest, with_line, sides_from + near_line.size())
		if spot.is_empty():
			spot = _find_spot(m, scale, anchor, rest, near, sides_from)
		if spot.is_empty():
			m.stack = 0.0
			m.shift = 0.0
			m.collapsed = true
			continue
		var rect: Rect2 = m.box_rect(scale, spot[0], spot[1])
		rect.position += anchor
		placed.append(rect)
		m.stack = spot[0]
		m.shift = spot[1]
		m.collapsed = false


## The first spot for `m`'s box clear of every rect in `near`: [push, side], trying sideways
## offsets nearest first (just past each of the first `side_count` rects of `near`, the boxes in
## its way), each pushed up as far as needed, within issue_max_side and issue_max_stack; [] when
## none fits.
func _find_spot(m: IssueMarker, scale: float, anchor: Vector2, rest: Rect2, near: Array[Rect2],
		side_count: int) -> Array:
	var sides: Array[float] = [0.0]
	for i: int in side_count:
		var r: Rect2 = near[i]
		# Just right of r, or just left of it.
		sides.append(r.end.x + ISSUE_BOX_GAP - rest.position.x)
		sides.append(r.position.x - ISSUE_BOX_GAP - rest.end.x)
	sides.sort_custom(func(a: float, b: float) -> bool: return absf(a) < absf(b))
	for side: float in sides:
		if absf(side) > issue_max_side:
			break
		var push: float = _clear_push(m, scale, anchor, side, near)
		if push <= issue_max_stack:
			return [push, side]
	return []


## The framed hole's line of play (framed_slot) as small screen rects at a zoom of `scale`, one
## per half tile along it on the ground, for the issue boxes to keep off; [] with no framed hole
## or no line.
func framed_line_rects(scale: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if framed_slot < 0 or framed_slot >= play_lines.lines.size():
		return out
	var line: PackedVector2Array = play_lines.lines[framed_slot]
	for i: int in range(1, line.size()):
		var a: Vector2 = line[i - 1]
		var b: Vector2 = line[i]
		var n: int = maxi(1, ceili(a.distance_to(b) / 0.5))
		var prev: Vector2 = play_lines.ground_point(a) * scale
		for k: int in range(1, n + 1):
			var q: Vector2 = play_lines.ground_point(a.lerp(b, float(k) / n)) * scale
			out.append(Rect2(prev, Vector2.ZERO).expand(q).grow(LINE_CLEAR))
			prev = q
	return out


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


func _process(delta: float) -> void:
	tick_pennant(delta)
	# The frame's budget counts what edits drew before this (input runs first), and starts
	# again after it.
	if drawing_pending():
		_drain(terrain.tuning.refresh_tiles_per_frame)
	_last_drained = _drained
	_drained = 0
	var s: float = _view_scale()
	if not is_equal_approx(s, _hole_label_scale):
		layout_hole_labels(s)
	# The text boxes keep their screen size, so a zoom change needs a fresh layout.
	if _issue_markers.is_empty():
		return
	if not is_equal_approx(s, _issue_layout_scale):
		layout_issue_labels(s)


## Moves the pins' pennant wave on by `delta` seconds (E7-S1): a new frame goes into the one
## texture every pin draws (HoleMarker.show_pennant), so no pin redraws.
func tick_pennant(delta: float) -> void:
	pennant_time += delta
	HoleMarker.show_pennant(HoleMarker.pennant_frame(pennant_time, pennant_frame_s))


## Keeps every tee marker's hole number at its screen size at a zoom of `scale` screen px per
## local unit (HoleMarker.text_scale). CourseView reruns it when the zoom changes.
func layout_hole_labels(scale: float) -> void:
	_hole_label_scale = scale
	clubhouse.z_index = lifted_z(scale, marker_min_screen_scale)
	var k: float = marker_shape_scale(scale)
	for m: HoleMarker in _markers:
		m.text_scale = 1.0 / scale
		m.shape_scale = k
		# A grown marker already draws over the terrain; at 0.5x and nearer the number rises over
		# it only where ground in front would cover it (E3-S40).
		m.label_lifted = k <= 1.0 + 0.0001 and m.label_covered(_course, scale)
	# The issue boxes keep off the numbers, which moved.
	_issue_layout_scale = 0.0


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
	finish_drawing()
	var out: Array[TerrainMesh.Chunk] = []
	for ch: TerrainMesh.Chunk in _chunks.values():
		out.append(ch)
	return out


## The chunk drawing `cell`'s ground, or null.
func chunk_at(cell: Vector2i) -> TerrainMesh.Chunk:
	finish_drawing()
	if _course == null or not _course.in_bounds(cell.x, cell.y):
		return null
	return _chunks.get(terrain.chunk_key(cell))


## What the ground draws now, chunk by chunk in key order: [key, sort y, points, colours, uvs,
## triangles, land points, land uvs, land triangles, face points, face colours, face
## triangles]. Two views drawing the same course give equal digests (tests compare an edited
## view against one drawn from scratch).
func terrain_digest() -> Array:
	finish_drawing()
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


## refresh_cell for a batch of tiles written together (one builder tiles_changed, E3-S16): when
## a height in it moved or a tile turned to or from water, each hole marker and issue box on one
## of its tiles is placed again at once (they read only the heights and water, so a batch that
## changed surfaces alone leaves them standing, E3-S74: an undo of a breaking drag placed
## every issue box again just before the check freed them); the ground is drawn
## again within the frame's budget (_drain, TerrainTuning.refresh_tiles_per_frame), the rest over
## the next frames: a tile whose surface alone changed is written in place in its chunk, and the
## chunks within REBUILD_REACH tiles of a tile whose height moved (WATER_REACH of one that turned
## to or from water) are emitted again, once however many of the batch's tiles share them. So
## an undo of a big drag costs its frame a bounded share. Leaves the view as show_course would,
## once drawn (finish_drawing). Main calls it with each tiles_changed.
func refresh_cells(cells: Array[Vector2i]) -> void:
	if _course == null or cells.is_empty():
		return
	_pending_cells.append_array(cells)
	trees.refresh_cells(cells)
	# The markers read the course, not the drawn ground, so they follow the batch at once: a
	# height moved in it may cover or uncover an issue box's foot.
	var shaped := {}
	var w: int = _course.width
	var hgt: int = _course.height
	# E7-S5: the packed tiles read in place, not three calls a tile (an undo of 585 tiles).
	var tiles: PackedByteArray = _course.packed_tiles()
	for cell: Vector2i in cells:
		if cell.x >= 0 and cell.y >= 0 and cell.x < w and cell.y < hgt:
			var i: int = cell.y * w + cell.x
			var t: int = tiles[i]
			var h: int = (t >> 4) | (WATER_MARK if (t & 0x0F) == Surface.Type.WATER else 0)
			if _heights_marked[i] != h:
				_heights_marked[i] = h
				shaped[cell] = true
	if not shaped.is_empty():
		_follow_shape(shaped)
		# E5-S15: the decor stands on the drawn ground, which only a height or water moves.
		if _course.decor_cells().size() > 0:
			decor.refresh()
		# E14-S1: a bridge stands on the water's level, and its rails read the water beside it.
		if _course.has_bridges():
			bridges.refresh()
	bridges.refresh(false)  # E14-S1: only when a bridge was built or taken away
	_drain(terrain.tuning.refresh_tiles_per_frame)


## The markers after a batch whose tiles `shaped` (tile -> true) moved a height or water: a
## marker whose tile's ground they can move (MARK_NEAR) is placed again, an issue box whose foot
## they can cover or uncover (MARK_BEHIND to MARK_FRONT) has it read again, and the tee numbers
## are laid out again (they read the ground in front as far as the zoom puts them).
func _follow_shape(shaped: Dictionary) -> void:
	var first: Vector2i = shaped.keys()[0]
	var bounds := Rect2i(first, Vector2i.ONE)
	for cell: Vector2i in shaped:
		bounds = bounds.expand(cell).expand(cell + Vector2i.ONE)
	for m: HoleMarker in _markers:
		if _near(shaped, bounds, m.cell, MARK_NEAR, MARK_NEAR):
			m.place(_course)
	_hole_label_scale = 0.0
	for m: IssueMarker in _issue_markers:
		if _near(shaped, bounds, m.cell, MARK_NEAR, MARK_NEAR):
			m.place(_course)
			_issue_layout_scale = 0.0
		elif _near(shaped, bounds, m.cell, MARK_BEHIND, MARK_FRONT):
			m.foot_hidden = IssueMarker.covered(_course, m.cell)
	for cell: Vector2i in _spare_issues.keys():
		if _near(shaped, bounds, cell, MARK_BEHIND, MARK_FRONT):
			_free_issue(_spare_issues[cell])
			_spare_issues.erase(cell)


## True when a tile of `shaped` (within `bounds`) lies `back` tiles behind `cell` to `front` in
## front of it (x and y alike: the camera looks from +x +y).
static func _near(shaped: Dictionary, bounds: Rect2i, cell: Vector2i, back: int, front: int) -> bool:
	var reach := Rect2i(cell - Vector2i(back, back), Vector2i.ONE * (back + front + 1))
	if not reach.intersects(bounds):
		return false
	for dy: int in range(-back, front + 1):
		for dx: int in range(-back, front + 1):
			if shaped.has(cell + Vector2i(dx, dy)):
				return true
	return false


## What the markers read of tile (x, y): its height, plus WATER_MARK on water.
static func _marked_shape(c: CourseData, x: int, y: int) -> int:
	return c.get_height(x, y) | (WATER_MARK if c.get_surface(x, y) == Surface.Type.WATER else 0)


## E3-S16: sorts up to `limit` of the pending edited tiles (_pending_cells, oldest first) into
## ground work against what is drawn (_heights_seen, the terrain's water cache): a tile whose
## surface alone changed is repainted in place, one whose height or water moved has the chunks
## round it emitted again (its slope flags read again first, TerrainMesh.sync). A height moved
## also redraws the contours and lines of play.
func _classify(limit: int) -> int:
	var end: int = mini(_pending_at + limit, _pending_cells.size())
	var done: int = end - _pending_at
	var reshaped: Array[Vector2i] = []
	var moved: Array[Vector2i] = []
	var w: int = _course.width
	var hgt: int = _course.height
	# E7-S5: the packed tiles read in place, as refresh_cells does.
	var tiles: PackedByteArray = _course.packed_tiles()
	for n: int in range(_pending_at, end):
		var cell: Vector2i = _pending_cells[n]
		if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= hgt:
			continue
		var i: int = cell.y * w + cell.x
		var t: int = tiles[i]
		var h: int = t >> 4
		var here_moved: bool = _heights_seen[i] != h
		if here_moved:
			_heights_seen[i] = h
			moved.append(cell)
		var water: bool = (t & 0x0F) == Surface.Type.WATER
		if not here_moved and water == terrain.water_seen(cell):
			var k := terrain.chunk_key(cell)
			if not _pending_paint.has(k):
				_pending_paint[k] = {}
			_pending_paint[k][cell] = true
			continue
		reshaped.append(cell)
		var reach: int = REBUILD_REACH if here_moved else WATER_REACH
		for dy: int in range(-reach, reach + 1):
			for dx: int in range(-reach, reach + 1):
				var c := cell + Vector2i(dx, dy)
				if _course.in_bounds(c.x, c.y):
					var key := terrain.chunk_key(c)
					if not _pending_build.has(key):
						_pending_build[key] = {}
					_pending_build[key][c] = true
	_pending_at = end
	if _pending_at >= _pending_cells.size():
		_pending_cells.clear()
		_pending_at = 0
	if not reshaped.is_empty():
		terrain.sync(reshaped)
	if not moved.is_empty():
		topo.mark_dirty()
		play_lines.mark_dirty(moved)
	return done


## E3-S16: draws the ground work pending (_pending_build, _pending_paint), at most `budget`
## tiles in this frame, counting what earlier calls since the last _process drew (below 0: all
## of it). A chunk is done whole once begun, so a frame may pass the budget by one chunk's tiles.
func _drain(budget: int) -> void:
	# Sorting a tile costs about a quarter of drawing one.
	while _pending_at < _pending_cells.size():
		if budget >= 0 and _drained >= budget:
			return
		var room: int = (budget - _drained) * CLASSIFY_PER_TILE if budget >= 0 else _pending_cells.size()
		_drained += ceili(float(_classify(room)) / CLASSIFY_PER_TILE)
	for key: Vector2i in _pending_build.keys():
		if budget >= 0 and _drained >= budget:
			return
		var cells: Dictionary = _pending_build[key]
		_pending_build.erase(key)
		if _pending_paint.has(key):
			cells.merge(_pending_paint[key])
			_pending_paint.erase(key)
		_drained += terrain.build_chunk(_chunks[key], cells)
	for key: Vector2i in _pending_paint.keys():
		if budget >= 0 and _drained >= budget:
			return
		var cells: Dictionary = _pending_paint[key]
		_pending_paint.erase(key)
		var ch: TerrainMesh.Chunk = _chunks[key]
		var whole: bool = false
		for cell: Vector2i in cells:
			if not terrain.repaint_tile(ch, cell):
				whole = true
				break
		if whole:
			_drained += terrain.build_chunk(ch, cells)
		else:
			ch.queue_redraw()
			_drained += cells.size()


## The ground tiles drawn in the last frame, its edits' and _process's (tests read the budget held).
func drawn_this_frame() -> int:
	return _last_drained


## True while a big batch's ground is still being drawn over the next frames (_drain).
func drawing_pending() -> bool:
	return not _pending_cells.is_empty() or not _pending_build.is_empty() or not _pending_paint.is_empty()


## Draws all the ground work still pending now (tests, and anything that reads the chunks).
func finish_drawing() -> void:
	if not drawing_pending():
		return
	var kept: int = _drained
	_drain(-1)
	_drained = kept  # a forced finish is no frame's budget


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
	trees.refresh_rect(r)


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
	# E18-S5: a tile beside another parcel or the map's edge, by its place in its parcel (an
	# unowned tile is on the map: is_owned is false off it, and the caller draws on-map tiles).
	# The same as parcel_of on each neighbour, without four calls a tile.
	if not c.in_bounds(x, y):
		return _land_frame_off_map(c, x, y)
	var n: int = CourseData.PARCEL_TILES
	var mask: int = 0
	if x % n == 0:
		mask |= LAND_EDGE_W
	if y % n == 0:
		mask |= LAND_EDGE_N
	if x % n == n - 1 or x == c.width - 1:
		mask |= LAND_EDGE_E
	if y % n == n - 1 or y == c.height - 1:
		mask |= LAND_EDGE_S
	return mask


## land_frame's edges of an off-map tile, by parcel_of as before E18-S5.
static func _land_frame_off_map(c: CourseData, x: int, y: int) -> int:
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
## 1 / that channel over the frame's opaque pixels with saturation at least HUE_MIN_SAT, in
## every variant of it (TileSheet.macro, E5-S2).
## Near-grey pixels (the chalk and ink of the 2-letter labels) are left out: clipping them only
## moves them toward white, not to another hue.
static func frame_headroom(sheet: TileSheet, i: int) -> float:
	var img: Image = sheet.texture.get_image()
	var top: float = 0.0
	for r: Rect2i in sheet.variant_regions(i):
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.0 and c.s >= HUE_MIN_SAT:
					top = maxf(top, maxf(c.r, maxf(c.g, c.b)))
	return INF if top <= 0.0 else 1.0 / top
