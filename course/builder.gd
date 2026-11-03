class_name CourseBuilder
extends RefCounted
## The course builder: paint surfaces, raise and lower ground, place a hole's tee and cup, set
## its par, open it, undo. With course/save.gd it is one of the two writers of CourseData
## (CLAUDE.md Architecture); the build tool, HUD and anything else go through it.
##
## A brush of size n (1, 3 or 5, from BuilderTuning) is the n x n square of tiles centered on
## the cursor tile, clipped to the map. Heights clamp at 0 and CourseData.MAX_HEIGHT.
##
## Every edit that changes the course pushes one undo step holding the old height and surface
## of each tile it wrote, and the holes as they were when it changed them. Terrain and hole
## edits share the one stack. An edit that changes nothing pushes nothing. Between
## begin_stroke() and end_stroke() (one mouse drag) all edits share one undo step, and raise
## or lower moves each tile at most once, so a drag lifts ground one step, not one per frame.
##
## Holes (E2-S3, D11, docs/design.md Hole validation rules): place_tee and place_cup create
## the hole with that number, closed, or move its tee or cup. A hole opens only through
## open_hole, and only while all five rules of course/validator.gd pass. An open hole closes
## when a surface or height edit touches a tile of its footprint, or when its own tee or cup
## moves. After every edit (a stroke counts as one, checked when it ends) and every undo the
## validator reruns for every hole: `issues` holds the result, and any open hole that now
## fails a rule closes. Undo puts the holes back as the step found them, open flags included.
## The same check runs when the builder is made, so a course that comes in with a failing open
## hole has it closed at once (no undo step, no signal: nothing is connected yet).
##
## Land (E6-S3, D26 to D28, docs/design.md Land): buy_parcel is the only way a parcel becomes
## owned in play. A parcel may be bought when it is not owned yet, shares an edge with an owned
## parcel, and its price (LandPrices, data/land.json) is no more than the land budget left
## (no limit when the budget is unlimited). buy_refusal names the rule that fails. A purchase
## takes the price from the budget and is one undo step; undoing it gives the parcel up and
## the price back, and reruns the validator. Land is never sold back (D27).

## Emitted after tiles are written (by an edit or an undo), with every tile that changed.
signal tiles_changed(cells: Array[Vector2i])
## Emitted after the holes list changed: a tee or cup placed or moved, a par set, a hole
## opened or closed, or an undo of any of those.
signal holes_changed
## Emitted after the validator reran (every edit and undo), with `issues`.
signal checked(issues: Dictionary)
## Emitted after a parcel was bought, or a purchase undone, with that parcel.
signal land_changed(parcel: Vector2i)

## The 9 surfaces a player paints, in palette order (docs/design.md surface table); `oob` is
## OB ground from E2-S3 (D9).
const PALETTE: Array[Surface.Type] = [
	Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.GREEN, Surface.Type.TEE,
	Surface.Type.BUNKER, Surface.Type.WATER, Surface.Type.TREES, Surface.Type.CART_PATH,
	Surface.Type.OOB,
]
## The pars a hole may have.
const PARS: PackedInt32Array = [3, 4, 5]


## One undo step: each tile's packed (height << 4 | surface) before the step, the holes
## before the step when it changed them (null when it did not), and for a purchase the parcel
## bought and the land budget before it (land_parcel NO_PARCEL when the step bought none).
class Step:
	extends RefCounted
	const NO_PARCEL: Vector2i = Vector2i(-1, -1)
	var tiles: Dictionary = {}
	var holes: Variant = null
	var land_parcel: Vector2i = NO_PARCEL
	var land_budget: int = 0

	func is_empty() -> bool:
		return tiles.is_empty() and holes == null and land_parcel == NO_PARCEL


var course: CourseData:
	get:
		return _course
var tuning: BuilderTuning:
	get:
		return _tuning
var validator: CourseValidator:
	get:
		return _validator
var prices: LandPrices:
	get:
		return _prices
## The latest validator run: every hole's failing rules, keyed by hole number
## (CourseValidator.check_course). Read-only.
var issues: Dictionary:
	get:
		return _issues

var _course: CourseData
var _tuning: BuilderTuning
var _validator: CourseValidator
var _prices: LandPrices
var _issues: Dictionary = {}
## Undo steps, oldest first.
var _undo: Array[Step] = []
## The open stroke's step, or null when no stroke is open.
var _stroke: Step = null
## Tiles the open stroke has already raised or lowered.
var _stroke_lifted: Dictionary = {}
## The holes changed since holes_changed was last emitted.
var _holes_dirty: bool = false


func _init(p_course: CourseData, p_tuning: BuilderTuning = null, p_validator: CourseValidator = null,
		p_prices: LandPrices = null) -> void:
	_course = p_course
	_tuning = p_tuning if p_tuning != null else BuilderTuning.load_default()
	_validator = p_validator if p_validator != null else CourseValidator.new()
	_prices = p_prices if p_prices != null else LandPrices.load_default()
	# A loaded course may bring in an open hole that fails a rule (a hand-edited or older
	# file): close it now, before anyone reads the open flag. Not an undo step.
	_rerun(Step.new())
	_holes_dirty = false


## A new course on the blank plot (D10): BuilderTuning's size, every tile its surface and
## height, no holes. A fresh course, not a write to one; hand it to a new builder.
static func new_sandbox(p_tuning: BuilderTuning = null) -> CourseData:
	var t: BuilderTuning = p_tuning if p_tuning != null else BuilderTuning.load_default()
	return CourseData.create(t.plot_size.x, t.plot_size.y, t.plot_surface, t.plot_ground)


# --- terrain ---

## In-bounds tiles under a brush of `size` centered on `center`.
func brush_cells(center: Vector2i, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var lo: int = -(maxi(size, 1) - 1) / 2
	var hi: int = lo + maxi(size, 1) - 1
	for dy: int in range(lo, hi + 1):
		for dx: int in range(lo, hi + 1):
			var c := center + Vector2i(dx, dy)
			if _course.in_bounds(c.x, c.y):
				cells.append(c)
	return cells


## Paints `surface` under the brush. Returns true when any tile changed.
func paint(center: Vector2i, surface: Surface.Type, size: int) -> bool:
	assert(Surface.is_valid(surface), "surface out of range")
	var tiles := {}
	for c: Vector2i in brush_cells(center, size):
		if _course.get_surface(c.x, c.y) != surface:
			_write(tiles, c, _course.get_height(c.x, c.y), surface)
	return _commit(tiles)


## Raises the ground under the brush one step, clamped at MAX_HEIGHT. True when any tile changed.
func raise(center: Vector2i, size: int) -> bool:
	return _lift(center, size, 1)


## Lowers the ground under the brush one step, clamped at 0. True when any tile changed.
func lower(center: Vector2i, size: int) -> bool:
	return _lift(center, size, -1)


## Starts grouping edits into one undo step (a mouse drag). Ends any open stroke first.
func begin_stroke() -> void:
	end_stroke()
	_stroke = Step.new()
	_stroke_lifted = {}


## Closes the open stroke, reruns the validator and pushes its undo step if it changed anything.
func end_stroke() -> void:
	if _stroke == null:
		return
	var step: Step = _stroke
	_stroke = null
	_stroke_lifted = {}
	if not step.is_empty():
		_finish(step)


## Heights the open stroke has changed, as they were when it began (tile -> height). Empty when
## no stroke is open. The build tool picks against these so a drag does not chase ground it
## just moved.
func stroke_start_heights() -> Dictionary:
	var out := {}
	if _stroke == null:
		return out
	for c: Vector2i in _stroke.tiles:
		var packed: int = _stroke.tiles[c]
		out[c] = packed >> 4
	return out


# --- holes ---

## Hole `number` as stored in CourseData (read it, do not change it), or null.
func hole(number: int) -> HoleData:
	for h: HoleData in _course.holes:
		if h.number == number:
			return h
	return null


## Hole `number`'s failing rules from the latest validator run; empty when it passes or
## does not exist.
func issues_for(number: int) -> Array[CourseValidator.Issue]:
	var out: Array[CourseValidator.Issue] = []
	if _issues.has(number):
		out.assign(_issues[number])
	return out


## True when hole `number` exists, is closed and passes all five rules.
func can_open(number: int) -> bool:
	var h: HoleData = hole(number)
	return h != null and not h.open and _issues.has(number) and (_issues[number] as Array).is_empty()


## Puts hole `number`'s tee on `cell`, creating the hole (closed, with `par`, or the tuning's
## default par when `par` is not 3, 4 or 5) when there is none. Moving the tee closes it.
## False when `cell` is off the map or the tee is already there.
func place_tee(number: int, cell: Vector2i, par: int = 0) -> bool:
	return _place(number, cell, true, par)


## Puts hole `number`'s cup on `cell`, as place_tee does for the tee.
func place_cup(number: int, cell: Vector2i, par: int = 0) -> bool:
	return _place(number, cell, false, par)


## Sets hole `number`'s par to 3, 4 or 5. False when there is no such hole, the par is not
## one of those, or it is already that par. The rerun closes the hole if rule 4 now fails.
func set_par(number: int, par: int) -> bool:
	if not par in PARS:
		return false
	var hs: Array[HoleData] = _holes_copy()
	var i: int = _find(hs, number)
	if i < 0 or hs[i].par == par:
		return false
	end_stroke()
	hs[i].par = par
	var step := Step.new()
	_write_holes(step, hs)
	_finish(step)
	return true


## Opens hole `number` (Open in the HUD). False unless can_open: guests play only holes that
## pass every rule. Pressing Open is an undo step like any other edit.
func open_hole(number: int) -> bool:
	if not can_open(number):
		return false
	end_stroke()
	var hs: Array[HoleData] = _holes_copy()
	hs[_find(hs, number)].open = true
	var step := Step.new()
	_write_holes(step, hs)
	_finish(step)
	return true


# --- land ---

## What parcel `parcel` costs (LandPrices), in dollars.
func parcel_price(parcel: Vector2i) -> int:
	return _prices.price(_course, parcel)


## Why parcel `parcel` cannot be bought now, or "" when it can: "no such parcel", "already
## yours", "not next to your land" (no owned parcel shares an edge with it; a corner is not
## enough), or "costs $X, you have $Y" (D27). Checked in that order.
func buy_refusal(parcel: Vector2i) -> String:
	if not _course.parcel_in_bounds(parcel):
		return "no such parcel"
	if _course.is_parcel_owned(parcel):
		return "already yours"
	var next_to_owned: bool = false
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _course.is_parcel_owned(parcel + d):
			next_to_owned = true
			break
	if not next_to_owned:
		return "not next to your land"
	if not _course.has_unlimited_budget():
		var cost: int = parcel_price(parcel)
		if cost > _course.land_budget:
			return "costs %s, you have %s" % [LandPrices.money(cost), LandPrices.money(_course.land_budget)]
	return ""


## Buys parcel `parcel`: owns it and takes its price from the land budget (nothing when the
## budget is unlimited), as one undo step. False, changing nothing, when buy_refusal names a
## rule; read it to say why.
func buy_parcel(parcel: Vector2i) -> bool:
	if not buy_refusal(parcel).is_empty():
		return false
	end_stroke()
	var step := Step.new()
	step.land_parcel = parcel
	step.land_budget = _course.land_budget
	if not _course.has_unlimited_budget():
		_course.set_land_budget(_course.land_budget - parcel_price(parcel))
	_course.set_parcel_owned(parcel, true)
	land_changed.emit(parcel)
	_finish(step)
	return true


# --- undo ---

func can_undo() -> bool:
	return not _undo.is_empty() or (_stroke != null and not _stroke.is_empty())


## Undo steps available (an open stroke counts once it changes something).
func undo_depth() -> int:
	return _undo.size() + (1 if _stroke != null and not _stroke.is_empty() else 0)


## Reverts the latest step (closing an open stroke first), then reruns the validator.
## Returns false when there is none.
func undo() -> bool:
	end_stroke()
	if _undo.is_empty():
		return false
	var step: Step = _undo.pop_back()
	var cells: Array[Vector2i] = []
	for c: Vector2i in step.tiles:
		var packed: int = step.tiles[c]
		_course.set_tile(c.x, c.y, packed >> 4, (packed & 0x0F) as Surface.Type)
		cells.append(c)
	if not cells.is_empty():
		tiles_changed.emit(cells)
	if step.holes != null:
		_course.set_holes(step.holes)
		_holes_dirty = true
	if step.land_parcel != Step.NO_PARCEL:
		_course.set_parcel_owned(step.land_parcel, false)
		_course.set_land_budget(step.land_budget)
		land_changed.emit(step.land_parcel)
	# The course is back as it was before the edit, when every open hole passed (_init closed
	# any that came in failing), so this rerun refreshes `issues` and closes nothing. Once
	# rule 6 reads ownership (E6-S4), an undone purchase may close a hole that stands on the
	# land given up; that close is not itself an undo step.
	_rerun(Step.new())
	_announce()
	return true


# --- internals ---

func _lift(center: Vector2i, size: int, delta: int) -> bool:
	var tiles := {}
	for c: Vector2i in brush_cells(center, size):
		if _stroke != null and _stroke_lifted.has(c):
			continue
		var h: int = _course.get_height(c.x, c.y)
		var to: int = clampi(h + delta, 0, CourseData.MAX_HEIGHT)
		if to != h:
			_write(tiles, c, to, _course.get_surface(c.x, c.y))
			if _stroke != null:
				_stroke_lifted[c] = true
	return _commit(tiles)


## Records the tile's old value in `tiles` (first write wins) and writes the new one.
func _write(tiles: Dictionary, c: Vector2i, h: int, s: Surface.Type) -> void:
	if not tiles.has(c):
		tiles[c] = (_course.get_height(c.x, c.y) << 4) | _course.get_surface(c.x, c.y)
	_course.set_tile(c.x, c.y, h, s)


## Files the tiles one terrain edit wrote into its step (the open stroke's, or a new one),
## closes every open hole whose footprint they touch, and announces them. Outside a stroke
## the step is finished at once; a stroke's is finished when it ends. False when empty.
func _commit(tiles: Dictionary) -> bool:
	if tiles.is_empty():
		return false
	var step: Step = _stroke if _stroke != null else Step.new()
	for c: Vector2i in tiles:
		if not step.tiles.has(c):
			step.tiles[c] = tiles[c]
	var cells: Array[Vector2i] = []
	cells.assign(tiles.keys())
	_close_footprints(step, cells)
	tiles_changed.emit(cells)
	if _stroke == null:
		_finish(step)
	return true


## Closes every open hole with a footprint tile among `cells` (D11), even if it still passes.
func _close_footprints(step: Step, cells: Array[Vector2i]) -> void:
	var hs: Array[HoleData] = _holes_copy()
	var closed: bool = false
	for h: HoleData in hs:
		if not h.open:
			continue
		for c: Vector2i in cells:
			if _validator.in_footprint(_course, h, c):
				h.open = false
				closed = true
				break
	if closed:
		_write_holes(step, hs)


func _place(number: int, cell: Vector2i, is_tee: bool, par: int) -> bool:
	if not _course.in_bounds(cell.x, cell.y):
		return false
	var hs: Array[HoleData] = _holes_copy()
	var i: int = _find(hs, number)
	if i < 0:
		var p: int = par if par in PARS else _tuning.default_par
		var tee: Vector2i = cell if is_tee else HoleData.UNPLACED
		var cup: Vector2i = HoleData.UNPLACED if is_tee else cell
		hs.append(HoleData.new(number, p, tee, cup, false))
	else:
		var h: HoleData = hs[i]
		if (h.tee if is_tee else h.cup) == cell:
			return false
		if is_tee:
			h.tee = cell
		else:
			h.cup = cell
		h.open = false
	end_stroke()
	var step := Step.new()
	_write_holes(step, hs)
	_finish(step)
	return true


## Reruns the validator, closes failing open holes, files the step and announces the change.
func _finish(step: Step) -> void:
	_rerun(step)
	_push(step)
	_announce()


## Reruns the validator for every hole and closes each open one that now fails a rule,
## recording the holes in `step` first.
func _rerun(step: Step) -> void:
	_issues = _check()
	var hs: Array[HoleData] = _holes_copy()
	var closed: bool = false
	for h: HoleData in hs:
		if h.open and not (_issues.get(h.number, []) as Array).is_empty():
			h.open = false
			closed = true
	if closed:
		_write_holes(step, hs)


func _check() -> Dictionary:
	if _course.holes.is_empty():
		return {}
	return _validator.check_course(_course)


func _announce() -> void:
	if _holes_dirty:
		_holes_dirty = false
		holes_changed.emit()
	checked.emit(_issues)


## Writes `hs` as the course's holes, saving the holes as they were into `step` the first time.
func _write_holes(step: Step, hs: Array[HoleData]) -> void:
	if step.holes == null:
		step.holes = _holes_copy()
	_course.set_holes(hs)
	_holes_dirty = true


func _holes_copy() -> Array[HoleData]:
	var out: Array[HoleData] = []
	for h: HoleData in _course.holes:
		out.append(h.copy())
	return out


static func _find(hs: Array[HoleData], number: int) -> int:
	for i: int in hs.size():
		if hs[i].number == number:
			return i
	return -1


func _push(step: Step) -> void:
	_undo.append(step)
	while _undo.size() > maxi(_tuning.undo_limit, 1):
		_undo.pop_front()
