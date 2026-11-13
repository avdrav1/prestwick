class_name BuildTool
extends Node2D
## The Build-mode terrain tool: turns the mouse into CourseBuilder edits and outlines the brush
## under the cursor. Active only in Build mode (Main toggles `active`). It never writes the
## course itself; every edit goes through the builder.
##
## Left click applies the tool at the tile under the cursor (TilePicker, so raised ground and
## tiles half behind a hill pick right). Dragging keeps applying it as one undo step, to every
## tile on the grid line between successive cursor tiles (fast mouse motion skips tiles), and
## picks against the ground as it was when the stroke began (so a Lower drag does not creep
## onto the tile behind the one it just dug).
## The tee and cup tools (E2-S3) place hole `hole_number`'s tee or cup on the tile clicked,
## through the builder, creating the hole with `par` when it has none; a drag does not move
## them. select_par sets `par` and the existing hole's par. The hole list (E3-S2) picks the
## hole with select_hole, starts the next one with new_hole, and opens, closes and renumbers
## holes through the tool, which goes through the builder.
## Land (E6-S5): the Buy land tool does not buy on a click; it emits buy_requested with the
## parcel under the cursor, and the HUD's confirm calls buy(). hover_hint gives, before the
## click, why the current tool would do nothing on the hovered tile (CourseBuilder's
## edit_refusal, place_refusal or buy_refusal), and the outline draws in refuse_color then.
## With Buy land the outline is the whole hovered parcel, in buy_color when it can be bought.
## While a purchase waits on the HUD's confirm, the HUD pins that parcel (pinned_parcel) and
## it stays outlined in buy_color wherever the cursor goes (a buyable hovered parcel draws in
## outline_color meanwhile), so the map shows what Buy buys. An owned parcel under Buy land
## draws in outline_color too (E6-S17): owning it is no error (parcel_outline_color).
## stroke_count counts presses, so the HUD can tell one drag's refusals from the next's.
## The Clubhouse tool (E5-S9, D60) moves the clubhouse, centred on the tile clicked, keeping its
## facing, through CourseBuilder.move_clubhouse; turn_clubhouse (a right-click with the tool)
## turns it a quarter in place. Its
## hover_hint is CourseBuilder.clubhouse_refusal. Its outline (E5-S10) is the 3x3 footprint a
## click would move it to, in refuse_color when refused, with its door tile outlined beside it.
## ui_undo (Ctrl+Z) undoes. Sits at the same origin as the CourseView, so local points are
## course screen space.
##
## E5-S6, the keyboard: the arrows move the hovered tile one tile along the grid (Right +x, Left
## -x, Down +y, Up -y; the outline is the cursor), starting from the tile at the middle of the
## view; Space or Enter applies the tool there as a click does, and held while the arrows move
## it drags (one undo step). Q and E step through the tools in the palette's order (cycle_tool),
## [ and ] through the brush sizes (step_brush), R turns the clubhouse (as the right-click does);
## with the Decor tool R takes the hovered decor away (E5-S3).
## cursor_moved tells Main, which keeps the cursor in view.
##
## E8-S5: `ruler`, a BuildRuler child, shows how long the hole is while it is built: the line
## from the tee to the Cup tool's cursor with its yardage and par, and rings round the tee
## (scenes/build_ruler.gd). The tee and cup tools place with auto par (CourseBuilder.place_cup):
## once the hole has both, its par is the one its yardage makes, unless the par buttons picked
## it (select_par marks the hole's par as picked by hand; pressed before a new hole's first tee
## or cup, the hole is created so marked).
## E12-S1 (D68): `walks`, a WalkOverlay child, draws every walk a round takes while the Cart path
## brush is in hand (scenes/walk_overlay.gd); the tool, surface and active setters tell it.

enum Tool { PAINT, RAISE, LOWER, TEE, CUP, BUY, CLUBHOUSE, DECOR }

## Emitted when the tool, surface or brush changes, so the palette can follow.
signal settings_changed
## Emitted when the tile under the cursor changes (TilePicker.NONE when it left the map).
signal hover_changed
## Emitted when the Buy land tool is clicked on parcel `parcel`; nothing is bought yet.
signal buy_requested(parcel: Vector2i)
## E5-S6: the keyboard moved the cursor to `cell`.
signal cursor_moved(cell: Vector2i)

const UNDO_ACTION: StringName = &"ui_undo"
## E5-S6: the keyboard cursor and the tool keys (project.godot; the help overlay lists them).
const CURSOR_ACTIONS: Dictionary = {
	&"build_cursor_left": Vector2i(-1, 0), &"build_cursor_right": Vector2i(1, 0),
	&"build_cursor_up": Vector2i(0, -1), &"build_cursor_down": Vector2i(0, 1),
}
const APPLY_ACTION: StringName = &"build_apply"
const TOOL_PREV_ACTION: StringName = &"build_tool_prev"
const TOOL_NEXT_ACTION: StringName = &"build_tool_next"
const BRUSH_SMALLER_ACTION: StringName = &"brush_smaller"
const BRUSH_LARGER_ACTION: StringName = &"brush_larger"
const TURN_ACTION: StringName = &"clubhouse_turn"
## Points along each tile edge of a parcel outline, so it lies on the sloped ground (E3-S59).
const PARCEL_EDGE_POINTS: int = 4

## Brush outline colors (art/palette.gpl `ink` and `sand_light` would be the final pick).
@export var outline_color: Color = Color(1.0, 0.97, 0.8, 0.95)
@export var fill_color: Color = Color(1.0, 0.97, 0.8, 0.18)
## Outline of a brush, tee or cup that would be refused, and of a parcel that cannot be
## bought (art/palette.gpl `flag_red`).
@export var refuse_color: Color = Color8(216, 58, 58, 242)
## Outline of a parcel the Buy land tool can buy (art/palette.gpl `sun_yellow`).
@export var buy_color: Color = Color8(240, 200, 58, 242)

var builder: CourseBuilder
var tool: Tool = Tool.PAINT:
	set(value):
		tool = value
		_follow_walks()
## E5-S3: the decor kind the Decor tool places (CourseData.DECOR_KINDS); a click on decor steps it
## to the next kind, and this follows.
var decor_kind: int = 0
var surface: Surface.Type = Surface.Type.FAIRWAY:
	set(value):
		surface = value
		_follow_walks()
## The hole the tee and cup tools build, picked in the hole list (select_hole, E3-S2).
var hole_number: int = 1
## Which of several holes sharing hole_number is picked: its slot in CourseData.holes (E3-S11,
## CourseBuilder.slot_of), or -1 for the first. A stale slot falls back to the first.
var hole_slot: int = -1
## The par a new hole gets, and the one the par buttons last picked.
var par: int = 3
var brush_size: int = 1:
	set(value):
		brush_size = maxi(value, 1)
		queue_redraw()
		settings_changed.emit()
var active: bool = true:
	set(value):
		active = value
		if not active:
			release()
			_hover = TilePicker.NONE
		queue_redraw()
		_follow_walks()
## The parcel waiting on the HUD's buy confirm, outlined in buy_color until it is cleared to
## TilePicker.NONE. Display state only (LandPanel sets it); it never writes the course.
var pinned_parcel: Vector2i = TilePicker.NONE:
	set(value):
		pinned_parcel = value
		queue_redraw()
## E5-S6: whether Buy land is in the palette (BuildPalette.set_buying), so cycle_tool skips it
## when it is hidden.
var buying: bool = true
## E5-S6: true while the apply key is held (a keyboard stroke).
var key_held: bool = false
## Presses so far: each starts a stroke (one click or drag). The HUD says a refusal once per
## stroke (E6-S17), however many dabs of a drag the builder refuses.
var stroke_count: int = 0
## E8-S5: the ruler and the rings round the tee (scenes/build_ruler.gd).
var ruler: BuildRuler
## E12-S1 (D68): the walks a round takes, drawn while the Cart path brush is in hand
## (scenes/walk_overlay.gd).
var walks: WalkOverlay
## Tile under the cursor, or TilePicker.NONE.
var hover: Vector2i:
	get:
		return _hover

var _hover: Vector2i = TilePicker.NONE
var _dragging: bool = false
var _last_cell: Vector2i = TilePicker.NONE
## E8-S5: the par buttons were pressed since the picked hole was picked and before it existed,
## so the hole its first tee or cup creates has its par picked by hand.
var _new_par_by_hand: bool = false


func _ready() -> void:
	z_index = 1  # over the course layers
	par = BuilderTuning.load_default().default_par
	ruler = BuildRuler.new()
	ruler.tool = self
	add_child(ruler)
	walks = WalkOverlay.new()
	walks.tool = self
	add_child(walks)


## E12-S1: the tool, its surface or Build's active flag changed: the walk overlay shows and
## runs only with the Cart path brush in hand (WalkOverlay.follow).
func _follow_walks() -> void:
	if walks != null:
		walks.follow()


func select_surface(s: Surface.Type) -> void:
	surface = s
	tool = Tool.PAINT
	settings_changed.emit()


func select_tool(t: Tool) -> void:
	tool = t
	queue_redraw()
	settings_changed.emit()


## Picks par 3, 4 or 5: for the next new hole, and for hole `hole_number` when it exists. Either
## way the par is picked by hand (E8-S5): placing a tee or cup keeps it.
func select_par(p: int) -> void:
	if not p in CourseBuilder.PARS:
		return
	par = p
	if builder != null and active:
		if picked_slot() >= 0:
			builder.set_par(hole_number, p, hole_slot, true)
		else:
			_new_par_by_hand = true
	settings_changed.emit()


## Opens hole `hole_number` (the HUD's Open). False unless it passes every rule.
func open_hole() -> bool:
	return set_hole_open(hole_number, true)


## Points the tee and cup tools at hole `number` (the hole list's pick). It need not exist yet:
## the first tee or cup creates it. `slot` picks one of several holes sharing `number`
## (E3-S11, a duplicate's row); -1 picks the first.
func select_hole(number: int, slot: int = -1) -> void:
	hole_number = number
	hole_slot = slot
	_new_par_by_hand = false
	queue_redraw()
	settings_changed.emit()


## Picks the next hole in build order (CourseBuilder.next_hole_number) and the Tee tool, so
## the next click places its tee. Returns its number, or 0, changing nothing, when the course
## is full.
func new_hole() -> int:
	if builder == null:
		return 0
	var n: int = builder.next_hole_number()
	if n == 0:
		return 0
	hole_number = n
	hole_slot = -1
	_new_par_by_hand = false
	select_tool(Tool.TEE)
	return n


## Opens (open_hole's rules apply) or closes hole `number` through the builder. False when
## nothing changed.
func set_hole_open(number: int, open: bool) -> bool:
	if builder == null or not active:
		return false
	return builder.open_hole(number) if open else builder.close_hole(number)


## Gives hole `number` the number `to` through the builder (CourseBuilder.renumber_hole). The
## pick stays on the same hole: it follows the hole that moved, or, when the picked hole is the
## one swapped out of `to`, goes with it to `number`. `slot` picks one of several holes
## sharing `number` (E3-S11): only it moves, and the pick stays on whichever slot it was on.
## False when nothing changed.
func renumber_hole(number: int, to: int, slot: int = -1) -> bool:
	if builder == null or not active:
		return false
	var picked: int = picked_slot()
	var picked_number: int = hole_number
	if not builder.renumber_hole(number, to, slot):
		return false
	if picked >= 0:
		# Renumbering keeps the course's hole order, so the picked slot holds the same hole.
		select_hole(builder.hole_at(picked).number, picked)
	elif picked_number == to:
		select_hole(number)
	return true


## The slot of the picked hole (CourseBuilder.slot_of), or -1 when it has none yet.
func picked_slot() -> int:
	return builder.slot_of(hole_number, hole_slot) if builder != null else -1


## The picked hole (read it, do not change it), or null when it has no tee or cup yet.
func picked_hole() -> HoleData:
	return builder.hole_at(picked_slot()) if builder != null else null


## The par to show: the hole's own when it exists, else the one picked for a new hole.
func shown_par() -> int:
	var h: HoleData = picked_hole()
	return h.par if h != null else par


## The parcel under the cursor, or TilePicker.NONE.
func hover_parcel() -> Vector2i:
	if builder == null or _hover == TilePicker.NONE:
		return TilePicker.NONE
	return builder.course.parcel_of(_hover.x, _hover.y)


## Why a click with the current tool on the hovered tile would do nothing, or "" when it
## would act (or nothing is hovered): the builder's edit_refusal for paint, raise and lower,
## place_refusal for the tee and cup, buy_refusal for Buy land.
func hover_hint() -> String:
	if builder == null or _hover == TilePicker.NONE:
		return ""
	match tool:
		Tool.TEE, Tool.CUP:
			return builder.place_refusal(_hover, hole_number, tool == Tool.TEE, hole_slot)
		Tool.BUY:
			return builder.buy_refusal(hover_parcel())
		Tool.CLUBHOUSE:
			if _hover == builder.course.clubhouse:
				return ""
			return builder.clubhouse_refusal(_hover, clubhouse_facing())
		Tool.DECOR:
			if builder.course.decor_at(_hover.x, _hover.y) != CourseData.NO_DECOR:
				return ""
			return builder.decor_refusal(_hover)
	return builder.edit_refusal(_hover, brush_size)


## The facing the Clubhouse tool moves the clubhouse with: the one it has (CourseData.FACINGS
## index), or the rule's +y when the course has none.
func clubhouse_facing() -> int:
	if builder == null or not builder.course.has_clubhouse():
		return ClubhouseRule.BLOCK_FACING
	return builder.course.clubhouse_facing


## Turns the clubhouse a quarter in place (`dir` 1 one way, -1 the other), through the builder:
## the first facing round from its own whose door is allowed. False when there is no clubhouse,
## or no other facing is allowed.
func turn_clubhouse(dir: int = 1) -> bool:
	if builder == null or not active or not builder.course.has_clubhouse():
		return false
	var c: CourseData = builder.course
	for k: int in range(1, CourseData.FACINGS.size()):
		var f: int = posmod(c.clubhouse_facing + k * signi(dir if dir != 0 else 1), CourseData.FACINGS.size())
		if builder.clubhouse_refusal(c.clubhouse, f).is_empty():
			var ok: bool = builder.move_clubhouse(c.clubhouse, f)
			queue_redraw()
			return ok
	return false


## E5-S3: removes the decor on `cell` (the hovered tile when NONE), through the builder. False
## when there is none.
func remove_decor(cell: Vector2i = TilePicker.NONE) -> bool:
	if builder == null or not active:
		return false
	var at: Vector2i = _hover if cell == TilePicker.NONE else cell
	if at == TilePicker.NONE:
		return false
	var ok: bool = builder.set_decor(at, CourseData.NO_DECOR)
	queue_redraw()
	return ok


## The Buy land tool's outline for the hovered parcel: outline_color when it is already owned
## (neutral, not an error) or while another purchase is pinned, refuse_color when it cannot
## be bought, else buy_color.
func parcel_outline_color() -> Color:
	var parcel: Vector2i = hover_parcel()
	if parcel != TilePicker.NONE and builder.course.is_parcel_owned(parcel):
		return outline_color
	if not hover_hint().is_empty():
		return refuse_color
	return buy_color if pinned_parcel == TilePicker.NONE else outline_color


## Buys parcel `parcel` through the builder (the HUD's confirm). False, buying nothing,
## when the builder refuses it.
func buy(parcel: Vector2i) -> bool:
	if builder == null or not active:
		return false
	var ok: bool = builder.buy_parcel(parcel)
	queue_redraw()
	return ok


## Undoes the builder's latest step (Ctrl+Z). The pick stays on the same hole: when the undo
## gives the picked hole another number (an undone renumber), the pick goes to that number.
func undo() -> bool:
	if builder == null or not active:
		return false
	_dragging = false
	var h: HoleData = picked_hole()
	var tee: Vector2i = h.tee if h != null else HoleData.UNPLACED
	var cup: Vector2i = h.cup if h != null else HoleData.UNPLACED
	var ok: bool = builder.undo()
	if ok and h != null:
		_follow_hole(tee, cup)
	queue_redraw()
	return ok


## After an undo: when hole `hole_number` no longer has tee `tee` and cup `cup` and another
## hole has both, picks that hole. A hole whose tee or cup the undo moved keeps its number.
func _follow_hole(tee: Vector2i, cup: Vector2i) -> void:
	var now: HoleData = picked_hole()
	if now != null and now.tee == tee and now.cup == cup:
		return
	var hs: Array[HoleData] = builder.course.holes
	for i: int in hs.size():
		if hs[i].tee == tee and hs[i].cup == cup:
			select_hole(hs[i].number, i)
			return


## Mouse moved to `local` (course screen space) with no button held.
func hover_at(local: Vector2) -> void:
	var cell: Vector2i = _pick(local)
	if cell != _hover:
		_hover = cell
		queue_redraw()
		hover_changed.emit()


## Left button went down at `local`: start a stroke and apply the tool there.
func press_at(local: Vector2) -> void:
	if builder == null or not active:
		return
	hover_at(local)
	_dragging = true
	stroke_count += 1
	builder.begin_stroke()
	_last_cell = TilePicker.NONE
	_apply(_hover)


## Mouse moved to `local` with the left button held: apply along the drag.
func drag_to(local: Vector2) -> void:
	hover_at(local)
	_drag_over()


## Applies the stroke under way along the grid line to the hovered tile (drag_to, move_cursor).
func _drag_over() -> void:
	if not _dragging or not active or _single_click():
		return
	if _hover == TilePicker.NONE:
		_last_cell = TilePicker.NONE  # left the map: do not join across the gap
		return
	if _last_cell == TilePicker.NONE:
		_apply(_hover)
		return
	var from: Vector2i = _last_cell
	for cell: Vector2i in grid_line(from, _hover):
		if cell != from:
			_apply(cell)


## Tiles on the 8-connected grid line from `a` to `b`, both included (Bresenham).
static func grid_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var d := Vector2i(absi(b.x - a.x), -absi(b.y - a.y))
	var s := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var err: int = d.x + d.y
	var p := a
	while true:
		cells.append(p)
		if p == b:
			break
		var e2: int = 2 * err
		if e2 >= d.y:
			err += d.y
			p.x += s.x
		if e2 <= d.x:
			err += d.x
			p.y += s.y
	return cells


## Left button released: close the stroke (one undo step).
func release() -> void:
	_dragging = false
	key_held = false
	_last_cell = TilePicker.NONE
	if builder != null:
		builder.end_stroke()


func _unhandled_input(event: InputEvent) -> void:
	if not active or builder == null:
		return
	if event.is_action_pressed(UNDO_ACTION):
		undo()
		get_viewport().set_input_as_handled()
		return
	if _key_input(event):
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and tool == Tool.CLUBHOUSE:
		turn_clubhouse()  # E5-S10: right-click turns its door
		get_viewport().set_input_as_handled()
		return
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and tool == Tool.DECOR:
		remove_decor()  # E5-S3: right-click takes it away
		get_viewport().set_input_as_handled()
		return
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = _to_local(mb.position)
		if mb.pressed:
			press_at(local)
		else:
			release()
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var local: Vector2 = _to_local(motion.position)
		if _dragging and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			drag_to(local)
		else:
			if _dragging and not key_held:
				release()
			hover_at(local)


## E5-S6: the keys of the Build cursor and tools. True when `event` was one of them.
func _key_input(event: InputEvent) -> bool:
	for action: StringName in CURSOR_ACTIONS:
		if event.is_action_pressed(action, true):
			move_cursor(CURSOR_ACTIONS[action])
			return true
	if event.is_action_pressed(APPLY_ACTION):
		key_press()
		return true
	if event.is_action_released(APPLY_ACTION):
		if key_held:
			release()
		return true
	if event.is_action_pressed(TOOL_PREV_ACTION, true):
		cycle_tool(-1)
		return true
	if event.is_action_pressed(TOOL_NEXT_ACTION, true):
		cycle_tool(1)
		return true
	if event.is_action_pressed(BRUSH_SMALLER_ACTION):
		step_brush(-1)
		return true
	if event.is_action_pressed(BRUSH_LARGER_ACTION):
		step_brush(1)
		return true
	if event.is_action_pressed(TURN_ACTION):
		if tool == Tool.DECOR:
			remove_decor()  # E5-S3: with the Decor tool, R takes the decor away
		else:
			turn_clubhouse()
		return true
	return false


## E5-S6: the tile the keyboard cursor starts on when none is hovered: the one at the middle of
## the view, else the middle of the map.
func cursor_start() -> Vector2i:
	if builder == null:
		return TilePicker.NONE
	if is_inside_tree():
		var cell: Vector2i = _pick(_to_local(get_viewport_rect().size * 0.5))
		if cell != TilePicker.NONE:
			return cell
	return Vector2i(builder.course.width / 2, builder.course.height / 2)


## E5-S6: moves the hovered tile `step` tiles along the grid, staying on the map (from
## cursor_start when none is hovered). While the apply key is held it drags, as the mouse does.
func move_cursor(step: Vector2i) -> void:
	if builder == null or not active:
		return
	var c: CourseData = builder.course
	var cell: Vector2i = cursor_start() if _hover == TilePicker.NONE else _hover + step
	cell = Vector2i(clampi(cell.x, 0, c.width - 1), clampi(cell.y, 0, c.height - 1))
	if cell != _hover:
		_hover = cell
		queue_redraw()
		hover_changed.emit()
		_drag_over()
	cursor_moved.emit(_hover)


## E5-S6: the apply key went down: a click at the cursor (put at cursor_start when none is
## hovered). It stays one stroke until the key comes up.
func key_press() -> void:
	if builder == null or not active:
		return
	if _hover == TilePicker.NONE:
		move_cursor(Vector2i.ZERO)
	key_held = true
	_dragging = true
	stroke_count += 1
	builder.begin_stroke()
	_last_cell = TilePicker.NONE
	_apply(_hover)


## E5-S6: the tools in the palette's order (CourseBuilder.PALETTE's surfaces, Raise, Lower, Tee,
## Cup, Buy land while shown, Clubhouse), as [tool, surface] pairs.
func tool_order() -> Array:
	var out: Array = []
	for s: Surface.Type in CourseBuilder.PALETTE:
		out.append([Tool.PAINT, s])
	for t: Tool in [Tool.RAISE, Tool.LOWER, Tool.TEE, Tool.CUP, Tool.BUY, Tool.CLUBHOUSE, Tool.DECOR]:
		if t != Tool.BUY or buying:
			out.append([t, surface])
	return out


## E5-S6: steps `dir` (+1 or -1) through tool_order, wrapping round.
func cycle_tool(dir: int) -> void:
	var order: Array = tool_order()
	var at: int = 0
	for i: int in order.size():
		if order[i][0] == tool and (tool != Tool.PAINT or order[i][1] == surface):
			at = i
			break
	var next: Array = order[posmod(at + dir, order.size())]
	if next[0] == Tool.PAINT:
		select_surface(next[1])
	else:
		select_tool(next[0])


## E5-S6: steps `dir` through BuilderTuning.brush_sizes, stopping at the ends.
func step_brush(dir: int) -> void:
	var sizes: PackedInt32Array = BuilderTuning.load_default().brush_sizes
	var at: int = maxi(sizes.find(brush_size), 0)
	brush_size = sizes[clampi(at + dir, 0, sizes.size() - 1)]


func _draw() -> void:
	if not active or builder == null:
		return
	var c: CourseData = builder.course
	if pinned_parcel != TilePicker.NONE:
		_draw_parcel(c, pinned_parcel, buy_color)
	if _hover == TilePicker.NONE:
		return
	if tool == Tool.BUY:
		# While a parcel is pinned, buy_color is its alone: the hovered one draws pale.
		if hover_parcel() != pinned_parcel:
			_draw_parcel(c, hover_parcel(), parcel_outline_color())
		return
	var refused: bool = not hover_hint().is_empty()
	var line: Color = refuse_color if refused else outline_color
	var fill: Color = Color(refuse_color, fill_color.a) if refused else fill_color
	for cell: Vector2i in outline_cells():
		if c.in_bounds(cell.x, cell.y):
			_draw_tile(c, cell, fill, line)
	if tool == Tool.CLUBHOUSE:
		var door: Vector2i = CourseData.door_of(_hover, clubhouse_facing())
		if c.in_bounds(door.x, door.y):
			draw_polyline(TerrainMesh.ring_screen(c, door), line, 2.0)


## The tiles the hover outline covers (E5-S10): the 3x3 footprint the Clubhouse tool would move
## the clubhouse to, the tee or cup tile, else the brush.
func outline_cells() -> Array[Vector2i]:
	if builder == null or _hover == TilePicker.NONE:
		return [] as Array[Vector2i]
	if tool == Tool.CLUBHOUSE:
		return CourseData.footprint_cells(_hover)
	return builder.brush_cells(_hover, 1 if _places_hole() or tool == Tool.DECOR else brush_size)


## One outlined tile, on the drawn ground round it (E3-S59), filled as a fan from its centre: the
## ring may fold where the ground climbs steeply away from the camera, which a polygon fill would
## refuse.
func _draw_tile(c: CourseData, cell: Vector2i, fill: Color, line: Color) -> void:
	var ring := TerrainMesh.ring_screen(c, cell)
	var pts := PackedVector2Array([Iso.tile_to_screen(Vector2(cell), c.get_height(cell.x, cell.y))])
	pts.append_array(ring)
	var idx := PackedInt32Array()
	for i: int in ring.size() - 1:
		idx.append_array([0, 1 + i, 2 + i])
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(fill)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)
	draw_polyline(ring, line, 1.0)


## Outlines parcel `parcel`: each border tile's outer edges, on its drawn ground, 3 px.
func _draw_parcel(c: CourseData, parcel: Vector2i, color: Color) -> void:
	var r: Rect2i = c.parcel_rect(parcel)
	# Each side: the neighbour step, and the two corners of the tile on that side.
	var sides: Array = [
		[Vector2i.LEFT, Vector2(-0.5, -0.5), Vector2(-0.5, 0.5)],
		[Vector2i.UP, Vector2(-0.5, -0.5), Vector2(0.5, -0.5)],
		[Vector2i.RIGHT, Vector2(0.5, -0.5), Vector2(0.5, 0.5)],
		[Vector2i.DOWN, Vector2(-0.5, 0.5), Vector2(0.5, 0.5)],
	]
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var cell := Vector2i(x, y)
			for side: Array in sides:
				if r.has_point(cell + (side[0] as Vector2i)):
					continue
				var line := PackedVector2Array()
				for i: int in PARCEL_EDGE_POINTS + 1:
					var t: Vector2 = Vector2(cell) + (side[1] as Vector2).lerp(side[2], float(i) / PARCEL_EDGE_POINTS)
					line.append(Iso.tile_to_screen(t, TerrainMesh.ground_in(c, cell, t)))
				draw_polyline(line, color, 3.0)


func _apply(cell: Vector2i) -> void:
	if cell == TilePicker.NONE or cell == _last_cell:
		return
	_last_cell = cell
	match tool:
		Tool.PAINT:
			builder.paint(cell, surface, brush_size)
		Tool.RAISE:
			builder.raise(cell, brush_size)
		Tool.LOWER:
			builder.lower(cell, brush_size)
		Tool.TEE:
			builder.place_tee(hole_number, cell, par, hole_slot, true, _new_par_by_hand)
		Tool.CUP:
			builder.place_cup(hole_number, cell, par, hole_slot, true, _new_par_by_hand)
		Tool.BUY:
			buy_requested.emit(builder.course.parcel_of(cell.x, cell.y))
		Tool.CLUBHOUSE:
			builder.move_clubhouse(cell, clubhouse_facing())
		Tool.DECOR:
			var k: int = builder.course.decor_at(cell.x, cell.y) if builder.course.in_bounds(cell.x, cell.y) else CourseData.NO_DECOR
			if k != CourseData.NO_DECOR:
				decor_kind = (k + 1) % CourseData.DECOR_KINDS.size()
			builder.set_decor(cell, decor_kind)
	queue_redraw()


func _places_hole() -> bool:
	return tool == Tool.TEE or tool == Tool.CUP


## Tools that act once per click, never along a drag.
func _single_click() -> bool:
	return _places_hole() or tool == Tool.BUY or tool == Tool.CLUBHOUSE or tool == Tool.DECOR


func _pick(local: Vector2) -> Vector2i:
	if builder == null:
		return TilePicker.NONE
	# Inside a stroke, pick against the ground as the stroke found it.
	var frozen: Dictionary = builder.stroke_start_heights() if _dragging else {}
	return TilePicker.pick(builder.course, local, frozen)


## Viewport (event) position to this node's local space, through the camera.
func _to_local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos
