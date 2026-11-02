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

## Atlas source ids in the shared TileSet.
const SURFACE_SOURCE: int = 0
const RISER_SOURCE: int = 1
const EDGE_SOURCE: int = 2
## Rises of this many steps or more share one cue (two lines). Matches the art's frame names.
const EDGE_MAX_STEPS: int = 2

var course: CourseData:
	get:
		return _course

var _course: CourseData
var _art: TileArt
var _tile_set: TileSet
var _tops: Array[TileMapLayer] = []
var _risers: Array[TileMapLayer] = []
var _edges: Array[TileMapLayer] = []
var _riser_atlas: Dictionary = {}
var _edge_atlas: Dictionary = {}


func _init() -> void:
	y_sort_enabled = true
	_art = TileArt.load_default()
	_tile_set = _make_tile_set(_art)
	for k: int in CourseData.MAX_HEIGHT + 1:
		if k < CourseData.MAX_HEIGHT:
			_risers.append(_make_layer("Risers%d" % k, k, Iso.riser_sort_key(Vector2i.ZERO, k)))
		_tops.append(_make_layer("Tops%d" % k, k, Iso.top_sort_key(Vector2i.ZERO, k)))
	# After every top, so a cue wins its sort-key tie with its own top.
	var edge_shift: int = _art.edges.anchor.y - _art.edges.frame_size.y / 2
	for k: int in CourseData.MAX_HEIGHT + 1:
		_edges.append(_make_layer("Edges%d" % k, k, Iso.top_sort_key(Vector2i.ZERO, k), edge_shift))
	for frame: String in _art.risers.frames:
		_riser_atlas[StringName(frame)] = Vector2i(_art.risers.frame_index(StringName(frame)), 0)
	for frame: String in _art.edges.frames:
		_edge_atlas[StringName(frame)] = Vector2i(_art.edges.frame_index(StringName(frame)), 0)


## Draws `c` from scratch. Pass null to clear.
func show_course(c: CourseData) -> void:
	_course = c
	for layer: TileMapLayer in _tops + _risers + _edges:
		layer.clear()
	if c == null:
		return
	for y: int in c.height:
		for x: int in c.width:
			_draw_cell(Vector2i(x, y))


## Redraws one tile after an edit, plus the two back neighbors whose walls it may now hide
## or reveal, and the two front neighbors whose edge cues depend on its height. Call from
## the builder after it writes a tile (E1-S5).
func refresh_cell(cell: Vector2i) -> void:
	if _course == null:
		return
	for c: Vector2i in [cell, cell + Vector2i(-1, 0), cell + Vector2i(0, -1),
			cell + Vector2i(1, 0), cell + Vector2i(0, 1)]:
		if _course.in_bounds(c.x, c.y):
			_draw_cell(c)


## The layer holding surface tops at height `h`.
func top_layer(h: int) -> TileMapLayer:
	return _tops[h]


## The layer holding riser step `k` (the wall between height k and k + 1).
func riser_layer(k: int) -> TileMapLayer:
	return _risers[k]


## The layer holding edge cues on tiles at height `h`.
func edge_layer(h: int) -> TileMapLayer:
	return _edges[h]


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


static func _rise(c: CourseData, h: int, x: int, y: int) -> int:
	if not c.in_bounds(x, y):
		return 0
	return clampi(h - c.get_height(x, y), 0, EDGE_MAX_STEPS)


func _draw_cell(cell: Vector2i) -> void:
	var h: int = _course.get_height(cell.x, cell.y)
	for layer_h: int in _tops.size():
		if layer_h == h:
			_tops[layer_h].set_cell(cell, SURFACE_SOURCE, Vector2i(_course.get_surface(cell.x, cell.y), 0))
		else:
			_tops[layer_h].erase_cell(cell)
	for k: int in _risers.size():
		var frame: StringName = riser_frame(_course, cell.x, cell.y, k)
		if frame.is_empty():
			_risers[k].erase_cell(cell)
		else:
			_risers[k].set_cell(cell, RISER_SOURCE, _riser_atlas[frame])
	var cue: StringName = edge_cue_frame(_course, cell.x, cell.y)
	for layer_h: int in _edges.size():
		if layer_h == h and not cue.is_empty():
			_edges[layer_h].set_cell(cell, EDGE_SOURCE, _edge_atlas[cue])
		else:
			_edges[layer_h].erase_cell(cell)


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


static func _make_tile_set(art: TileArt) -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(Iso.TILE_W, Iso.TILE_H)
	ts.add_source(_make_source(art.surfaces), SURFACE_SOURCE)
	ts.add_source(_make_source(art.risers), RISER_SOURCE)
	ts.add_source(_make_source(art.edges), EDGE_SOURCE)
	return ts


static func _make_source(sheet: TileSheet) -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = sheet.texture
	src.texture_region_size = sheet.frame_size
	src.separation = Vector2i(sheet.gutter, 0)
	for i: int in sheet.frame_count():
		src.create_tile(Vector2i(i, 0))
	return src
