class_name LandPanel
extends PanelContainer
## The Build-mode land panel (E6-S5, D26 to D29, docs/design.md Land): the land budget, always;
## the hovered parcel's price and whether it can be bought; a tool's hint before the click
## when it would do nothing on the hovered tile ("Paint: not your land"); the builder's
## refusal after a click that did nothing; and the confirm for a purchase. A view onto a
## BuildTool and its builder: it never writes the course, and a confirmed purchase goes
## through BuildTool.buy, which calls CourseBuilder.buy_parcel.
##
## Main binds the tool once (bind) and hands every fresh builder to watch (show_course).
##
## E6-S17: the builder refuses every unowned dab of a drag, but the panel says it once per
## stroke (BuildTool.stroke_count). The confirm floats by the clicked parcel, just above the
## tile that was clicked (below it, or beside it, when there is no room above or the HUD is
## there; kept on screen and clear of the HUD, opaque), and Enter (buy_confirm) buys while
## Esc (buy_cancel) cancels. Parcels are named by parcel_name, a compass point and a distance from the map's
## centre, where the starting block is, never by grid coordinates.

const NONE: Vector2i = TilePicker.NONE
## Keys for a pending purchase (project.godot: Enter and keypad Enter, Esc).
const CONFIRM_ACTION: StringName = &"buy_confirm"
const CANCEL_ACTION: StringName = &"buy_cancel"
## Sixteen compass points, clockwise from north, which is up the screen.
const COMPASS: Array[String] = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
		"S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
## A parcel name's distance is rounded to this many yards (display format, not a tunable).
const NAME_ROUND_YD: int = 10
## Hint names for each BuildTool.Tool.
const TOOL_NAMES: Dictionary = {
	BuildTool.Tool.PAINT: "Paint", BuildTool.Tool.RAISE: "Raise", BuildTool.Tool.LOWER: "Lower",
	BuildTool.Tool.TEE: "Tee", BuildTool.Tool.CUP: "Cup", BuildTool.Tool.BUY: "Buy",
}

var budget_label: Label
## The hovered parcel: "NW parcel, 130 yd out: $1,150, click to buy".
var parcel_label: Label
## The current tool's refusal on the hovered tile, before the click.
var hint_label: Label
## The builder's refusal after a click, shown for BuilderTuning.refusal_show_s.
var message_label: Label
## The floating confirm by the clicked parcel (top_level, placed in viewport space).
var confirm_box: PanelContainer
var confirm_label: Label
var confirm_button: Button
var cancel_button: Button
## The parcel waiting on the confirm, or NONE.
var pending_parcel: Vector2i = NONE
## The tile of pending_parcel the confirm sits by: the one clicked, else the parcel's centre.
var pending_tile: Vector2i = NONE
## Refusal messages shown so far (one per stroke at most for the builder's refusals).
var messages_shown: int = 0

## Color of a hint or a refusal.
@export var refuse_font_color: Color = Color8(240, 160, 150)
## Pixels between the confirm and the clicked tile on screen.
@export var confirm_gap: float = 12.0
## Pixels the confirm keeps from the viewport's edge when the corner is near or past it.
@export var confirm_margin: float = 8.0

var _tool: BuildTool
var _message_left: float = 0.0
var _refusal_show_s: float = 3.0
## The stroke and the reason of the latest builder refusal shown.
var _message_stroke: int = -1
var _message_reason: String = ""


func _ready() -> void:
	_refusal_show_s = BuilderTuning.load_default().refusal_show_s
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	budget_label = Label.new()
	box.add_child(budget_label)
	parcel_label = Label.new()
	box.add_child(parcel_label)
	hint_label = _warning_label(box)
	message_label = _warning_label(box)
	confirm_box = PanelContainer.new()
	confirm_box.top_level = true
	confirm_box.visible = false
	add_child(confirm_box)
	# Opaque, so the HUD or the map under it never shows through the price.
	var style: StyleBox = confirm_box.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var opaque := style.duplicate() as StyleBoxFlat
		opaque.bg_color.a = 1.0
		confirm_box.add_theme_stylebox_override("panel", opaque)
	var confirm_rows := VBoxContainer.new()
	confirm_rows.add_theme_constant_override("separation", 4)
	confirm_box.add_child(confirm_rows)
	confirm_label = Label.new()
	confirm_rows.add_child(confirm_label)
	var row := HBoxContainer.new()
	confirm_rows.add_child(row)
	confirm_button = Button.new()
	confirm_button.text = "Buy (Enter)"
	confirm_button.focus_mode = Control.FOCUS_NONE
	confirm_button.pressed.connect(confirm_buy)
	row.add_child(confirm_button)
	cancel_button = Button.new()
	cancel_button.text = "Cancel (Esc)"
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.pressed.connect(cancel_buy)
	row.add_child(cancel_button)
	visibility_changed.connect(func() -> void:
		if not visible:
			cancel_buy())
	refresh()


## Follows `tool` from now on.
func bind(tool: BuildTool) -> void:
	_tool = tool
	_tool.settings_changed.connect(_on_settings_changed)
	_tool.hover_changed.connect(refresh)
	_tool.buy_requested.connect(ask_buy)
	refresh()


## Follows `builder` (the tool's new one, after Main.show_course): its refusals and land.
func watch(builder: CourseBuilder) -> void:
	cancel_buy()
	_message_left = 0.0
	_message_stroke = -1
	builder.refused.connect(_on_builder_refused)
	builder.land_changed.connect(func(_p: Vector2i) -> void: refresh())
	refresh()


## Shows the builder's refusal of a click, `reason`, for BuilderTuning.refusal_show_s.
func show_refusal(reason: String) -> void:
	message_label.text = "Can't: %s" % reason
	_message_left = _refusal_show_s
	messages_shown += 1
	refresh()


## The builder refused a click or a dab: show it once per stroke. A repeat in the same drag
## only keeps the message up.
func _on_builder_refused(reason: String) -> void:
	var stroke: int = _tool.stroke_count if _tool != null else -1
	if stroke == _message_stroke and reason == _message_reason and _message_left > 0.0:
		_message_left = _refusal_show_s
		return
	_message_stroke = stroke
	_message_reason = reason
	show_refusal(reason)


## The Buy land tool was clicked on `parcel`: ask to confirm, or say why it cannot be bought.
func ask_buy(parcel: Vector2i) -> void:
	var b: CourseBuilder = _builder()
	if b == null:
		return
	var why: String = b.buy_refusal(parcel)
	if not why.is_empty():
		cancel_buy()
		show_refusal(why)
		return
	pending_parcel = parcel
	var clicked: Vector2i = _tool.hover
	pending_tile = clicked if clicked != NONE and b.course.parcel_of(clicked.x, clicked.y) == parcel \
			else b.course.parcel_rect(parcel).get_center()
	_tool.pinned_parcel = parcel
	var c: CourseData = b.course
	var name: String = parcel_name(c, parcel)
	if c.has_unlimited_budget():
		confirm_label.text = "Buy the %s?" % name
	else:
		var cost: int = b.parcel_price(parcel)
		confirm_label.text = "Buy the %s, for %s?\n%s left after." % [name,
				LandPrices.money(cost), LandPrices.money(c.land_budget - cost)]
	confirm_box.visible = true
	_place_confirm()
	refresh()


## Viewport point of tile `cell`'s top centre on screen, at its height: where the confirm
## sits for a purchase clicked there (pending_tile).
func confirm_anchor(cell: Vector2i) -> Vector2:
	var c: CourseData = _builder().course
	var local: Vector2 = Iso.tile_to_screen(Vector2(cell), c.get_height(cell.x, cell.y))
	return _tool.get_global_transform_with_canvas() * local


## The parcel's name for the player: the compass point from the map's centre (the starting
## block's centre, D26), north up the screen, and the distance to the parcel's centre in yards,
## rounded to NAME_ROUND_YD: "NW parcel, 130 yd out". Every parcel on the map has its own
## name: when other parcels share the point and the distance (mirror images about the map's
## centre do, a few parcels out), they are told apart by the neighbouring point each leans
## toward, the most anticlockwise and the most clockwise of them: "ENE parcel, 280 yd out,
## toward NE" and "..., toward E" (any between, on a large map, count clockwise: "2 of 4";
## the middle one of three keeps the plain name). Leans in a group never tie: equal bearings
## mean parcel centres on one ray from the centre, at least 40 yd apart, so a different rounded
## distance. tests/test_land_hud.gd checks every map from 16 x 16 to 256 x 256 in parcel steps,
## square (E6-S26) and not (E6-S32).
static func parcel_name(c: CourseData, parcel: Vector2i) -> String:
	var mine: Vector3 = _compass(c, parcel)
	if mine.x < 0.0:
		return "centre parcel"
	var point: int = int(mine.x)
	var base: String = "%s parcel, %d yd out" % [COMPASS[point], int(mine.y)]
	# The parcels sharing the name, by their lean from the point, anticlockwise first.
	var leans: Array[float] = []
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			var other: Vector3 = _compass(c, Vector2i(p, q))
			if other.x == mine.x and other.y == mine.y:
				leans.append(other.z)
	if leans.size() < 2:
		return base
	leans.sort()
	var k: int = leans.find(mine.z)
	var n: int = COMPASS.size()
	if k == 0:
		return "%s, toward %s" % [base, COMPASS[(point + n - 1) % n]]
	if k == leans.size() - 1:
		return "%s, toward %s" % [base, COMPASS[(point + 1) % n]]
	if leans.size() == 3:
		return base
	return "%s, %d of %d" % [base, k + 1, leans.size()]


## Parcel `parcel`'s compass point from the map's centre (x, -1 for the centre itself), its
## distance in yards rounded to NAME_ROUND_YD (y), and its bearing's lean from that point in
## radians, clockwise positive (z).
static func _compass(c: CourseData, parcel: Vector2i) -> Vector3:
	var r: Rect2i = c.parcel_rect(parcel)
	var d: Vector2 = Vector2(r.get_center()) - Vector2(c.width, c.height) * 0.5
	var screen: Vector2 = Iso.tile_to_screen(d)
	var yd: int = roundi(d.length() * CourseValidator.YARDS_PER_TILE / NAME_ROUND_YD) * NAME_ROUND_YD
	if screen.length() < 0.001:
		return Vector3(-1.0, yd, 0.0)
	# Clockwise from screen up.
	var bearing: float = fposmod(atan2(screen.x, -screen.y), TAU)
	var step: float = TAU / COMPASS.size()
	var point: int = roundi(bearing / step) % COMPASS.size()
	return Vector3(point, yd, wrapf(bearing - point * step, -PI, PI))


func _unhandled_input(event: InputEvent) -> void:
	if pending_parcel == NONE or not is_visible_in_tree():
		return
	if event.is_action_pressed(CONFIRM_ACTION):
		confirm_buy()
	elif event.is_action_pressed(CANCEL_ACTION):
		cancel_buy()
	else:
		return
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()


## Buys the pending parcel (the confirm's Buy). False when none is pending or it was refused.
func confirm_buy() -> bool:
	if pending_parcel == NONE or _tool == null:
		return false
	var parcel: Vector2i = pending_parcel
	cancel_buy()
	var ok: bool = _tool.buy(parcel)
	if not ok:
		show_refusal(_builder().buy_refusal(parcel))
	refresh()
	return ok


func cancel_buy() -> void:
	var was: Vector2i = pending_parcel
	pending_parcel = NONE
	pending_tile = NONE
	if _tool != null:
		_tool.pinned_parcel = NONE
	if confirm_box != null:
		confirm_box.visible = false
	if was != NONE:
		refresh()


## Shows the budget, the hovered parcel and the hints as the builder has them now.
func refresh() -> void:
	if budget_label == null:
		return
	var b: CourseBuilder = _builder()
	if b == null:
		budget_label.text = ""
		parcel_label.visible = false
		hint_label.visible = false
		message_label.visible = false
		return
	var c: CourseData = b.course
	budget_label.text = "Land budget: %s" % ("unlimited" if c.has_unlimited_budget()
			else LandPrices.money(c.land_budget))
	parcel_label.text = _parcel_line(b)
	parcel_label.visible = not parcel_label.text.is_empty()
	var hint: String = "" if _tool.tool == BuildTool.Tool.BUY else _tool.hover_hint()
	hint_label.text = "" if hint.is_empty() else "%s: %s" % [TOOL_NAMES[_tool.tool], hint]
	hint_label.visible = not hint.is_empty()
	message_label.visible = _message_left > 0.0


func _process(delta: float) -> void:
	if pending_parcel != NONE:
		_place_confirm()  # the camera may pan or zoom under it
	if _message_left <= 0.0:
		return
	_message_left -= delta
	if _message_left <= 0.0:
		message_label.visible = false


## The hovered parcel's line: its price and whether it can be bought, for an unowned parcel
## (and with the Buy land tool, "yours" on an owned one); "" when nothing is hovered. While
## a purchase waits on the confirm it describes that parcel instead, which the map outlines
## (BuildTool.pinned_parcel), so the line and the outline never name another parcel.
func _parcel_line(b: CourseBuilder) -> String:
	var parcel: Vector2i = _tool.hover_parcel() if pending_parcel == NONE else pending_parcel
	if parcel == NONE:
		return ""
	var c: CourseData = b.course
	var buying: bool = _tool.tool == BuildTool.Tool.BUY
	var name: String = parcel_name(c, parcel)
	if c.is_parcel_owned(parcel):
		return "%s: yours" % name if buying else ""
	var line: String = "%s: %s" % [name, LandPrices.money(b.parcel_price(parcel))]
	var why: String = b.buy_refusal(parcel)
	if not why.is_empty():
		return "%s, can't buy: %s" % [line, why]
	return "%s, %s" % [line, "click to buy" if buying else "for sale (Buy land)"]


## Puts the confirm by the clicked tile, inside the viewport and clear of the HUD (hud_rects):
## just above the tile, else just below it, else to its right or left, else right of the HUD
## beside it.
## Of those, the first that covers no HUD and needs no clamping to stay on screen wins; else
## the one covering the least HUD, then moved least by the clamp.
func _place_confirm() -> void:
	if pending_parcel == NONE or _builder() == null:
		return
	confirm_box.reset_size()
	var size: Vector2 = confirm_box.get_combined_minimum_size()
	var anchor: Vector2 = confirm_anchor(pending_tile)
	var view: Rect2 = get_viewport_rect()
	var wants: Array[Vector2] = [
		Vector2(anchor.x - size.x * 0.5, anchor.y - confirm_gap - size.y),
		Vector2(anchor.x - size.x * 0.5, anchor.y + confirm_gap),
		Vector2(anchor.x + confirm_gap, anchor.y - size.y * 0.5),
		Vector2(anchor.x - confirm_gap - size.x, anchor.y - size.y * 0.5),
	]
	var hud: Array[Rect2] = hud_rects()
	# E3-S62: the left column runs deeper in Build since the guests' speed panel stands under the
	# land panel, so a tile beside it may have no clear side: also try right of the column.
	var past := wants[2]
	for _pass: int in 2:
		for r: Rect2 in hud:
			if Rect2(past, size).intersects(r):
				past.x = maxf(past.x, r.end.x + confirm_gap)
	wants.append(past)
	var best := Vector2.ZERO
	var best_cost := Vector3(INF, INF, INF)
	for i: int in wants.size():
		var pos := Vector2(
				clampf(wants[i].x, view.position.x + confirm_margin, view.end.x - confirm_margin - size.x),
				clampf(wants[i].y, view.position.y + confirm_margin, view.end.y - confirm_margin - size.y))
		var covered: float = 0.0
		for r: Rect2 in hud:
			covered += Rect2(pos, size).intersection(r).get_area()
		var cost := Vector3(covered, pos.distance_to(wants[i]), i)
		if cost < best_cost:
			best_cost = cost
			best = pos
	confirm_box.global_position = best


## Viewport rects of the HUD the confirm keeps clear of, each grown by confirm_margin: this
## panel and every other visible Control beside it on the HUD (its parent; main.tscn's HUD
## CanvasLayer), looked up on each call, so a control added to the HUD later is avoided with
## no list to keep (E6-S26). Hidden ones (the Play HUD, in Build) are not.
func hud_rects() -> Array[Rect2]:
	var out: Array[Rect2] = [get_global_rect().grow(confirm_margin)]
	var hud: Node = get_parent()
	if hud == null:
		return out
	for child: Node in hud.get_children():
		var control := child as Control
		if control != null and control != self and control.is_visible_in_tree():
			out.append(control.get_global_rect().grow(confirm_margin))
	return out


func _on_settings_changed() -> void:
	if _tool.tool != BuildTool.Tool.BUY:
		cancel_buy()
	refresh()


func _builder() -> CourseBuilder:
	return _tool.builder if _tool != null else null


func _warning_label(parent: Control) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", refuse_font_color)
	l.visible = false
	parent.add_child(l)
	return l
