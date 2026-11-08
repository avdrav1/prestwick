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
## open_hole, and only while every rule of course/validator.gd passes. An open hole closes
## when a surface or height edit touches a tile of its footprint, or when its own tee or cup
## moves. After every edit (a stroke counts as one, checked when it ends) and every undo the
## validator reruns for every hole: `issues` holds the result, and any open hole that now
## fails a rule closes. Undo puts the holes back as the step found them, open flags included.
## The same check runs when the builder is made, so a course that comes in with a failing open
## hole has it closed at once (no undo step, no signal: nothing is connected yet).
##
## The hole list (E3-S2): a course holds at most BuilderTuning.max_holes holes (9), numbered 1
## to that. A tee or cup for a number with no hole creates it; next_hole_number gives the
## lowest free number, so holes are numbered in build order. A number outside 1 to max_holes,
## or a new hole past max_holes, is refused (TOO_MANY_HOLES). renumber_hole moves a hole to
## another number, swapping with the hole that had it; close_hole closes an open hole. Both
## are undo steps, keep the course's hole order (course/save.gd writes it as it is) and leave
## every other hole's open flag alone.
##
## Duplicate numbers (E3-S11): a loaded file may hold two holes sharing a number (validator rule
## 1 fails them). Each entry of CourseData.holes is a slot, its index there; the hole list shows
## one row per slot. hole(number) is the first slot with that number; place_tee, place_cup,
## set_par and renumber_hole take an optional `slot` that points them at one entry, so each
## duplicate is built and renumbered on its own. issues_at(slot) is that entry's own rules.
##
## Land (E6-S3, D26 to D28, docs/design.md Land): buy_parcel is the only way a parcel becomes
## owned in play. A parcel may be bought when it is not owned yet, shares an edge with an owned
## parcel, and its price (LandPrices, data/land.json) is no more than the land budget left
## (no limit when the budget is unlimited). buy_refusal names the rule that fails. A purchase
## takes the price from the budget and is one undo step; undoing it gives the parcel up and
## the price back, and reruns the validator. Land is never sold back (D27).
##
## Rule 3's graph (E3-S12): the builder keeps the validator's CourseValidator.Reach between
## checks and hands it the tiles written since the last one, so a check after an edit that
## changes no crossing (most paint, every raise and lower) reuses what rule 3 found. A write the
## builder did not make (CourseData.revision moved past the builder's own writes) or a parcel
## bought or given up drops the graph, and the next check builds it afresh.
##
## Owned land only (E6-S4, D30): paint, raise and lower write only tiles on owned parcels, so
## a brush that straddles the line edits its owned tiles and leaves the rest. A brush with
## tiles on the map but none owned, or a tee or cup placed on an unowned tile, changes
## nothing and emits `refused` with the reason (edit_refusal, place_refusal: "not your
## land"). New sandbox owns every parcel, so nothing is refused there.

## Emitted after tiles are written (by an edit or an undo), with every tile that changed.
signal tiles_changed(cells: Array[Vector2i])
## Emitted after the holes list changed: a tee or cup placed or moved, a par set, a hole
## opened or closed, or an undo of any of those.
signal holes_changed
## Emitted after the validator reran (every edit and undo), with `issues`.
signal checked(issues: Dictionary)
## Emitted after a parcel was bought, or a purchase undone, with that parcel.
signal land_changed(parcel: Vector2i)
## Emitted when an edit or a tee or cup placement did nothing because of a rule the player
## can act on (E6-S4: "not your land"), with that one-line reason.
signal refused(reason: String)

## The 9 surfaces a player paints, in palette order (docs/design.md surface table); `oob` is
## OB ground from E2-S3 (D9).
const PALETTE: Array[Surface.Type] = [
	Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.GREEN, Surface.Type.TEE,
	Surface.Type.BUNKER, Surface.Type.WATER, Surface.Type.TREES, Surface.Type.CART_PATH,
	Surface.Type.OOB,
]
## The pars a hole may have.
const PARS: PackedInt32Array = [3, 4, 5]
## The reason an edit or placement on land the player does not own is refused (E6-S4).
const NOT_YOUR_LAND: String = "not your land"
## The reason a new hole past BuilderTuning.max_holes is refused (E3-S2), with that number.
const TOO_MANY_HOLES: String = "a course has at most %d holes"


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
	## E3-S61: a stroke's kept lines of play as they stood when it began (the builder's
	## _lines_now and _lines_reads), so its undo, which puts the course back as it was then,
	## need not measure the turns its tiles moved again. Empty when none were kept.
	var lines: Dictionary = {}
	var lines_reads: Dictionary = {}

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
## One line per open hole the course brought in that the builder closed when it was made,
## "Hole 3 closed: <its first failing rule's reason>", in course order: what the load (E4-S7)
## and import (E5-S5) notice lists (D35), for example a dogleg saved as a straight-line par 4
## before rule 4 measured the line of play (D47). Later edits never add to it. Read-only.
var closed_on_load: Array[String]:
	get:
		return _closed_on_load.duplicate()

var _closed_on_load: Array[String] = []
var _course: CourseData
var _tuning: BuilderTuning
var _validator: CourseValidator
var _prices: LandPrices
var _issues: Dictionary = {}
## The latest validator run per slot (CourseValidator.check_slots), in CourseData.holes order.
var _slot_issues: Array = []
## Each slot's rule 4 yardage from the same run (the line of play, D47), in the same order.
var _slot_yards: Array[int] = []
## Each slot's line of play from the same run (CourseValidator.line_of_play, D51), so an edit
## that moves or removes a dogleg's turn is still judged against the line it was checked on.
var _slot_lines: Array[PackedVector2Array] = []
## Each slot's hints from the same run (CourseValidator.hint_slots, E3-S39): never close a hole.
var _slot_hints: Array = []
## Undo steps, oldest first.
var _undo: Array[Step] = []
## The open stroke's step, or null when no stroke is open.
var _stroke: Step = null
## Tiles the open stroke has already raised or lowered.
var _stroke_lifted: Dictionary = {}
## The holes changed since holes_changed was last emitted.
var _holes_dirty: bool = false
## Rule 3's graph as of the last check (E3-S12), or null to build it afresh at the next.
var _reach: CourseValidator.Reach = null
## Tiles the builder wrote since the last check.
var _reach_dirty: Dictionary = {}
## CourseData.revision the graph stands for once _reach_dirty is applied.
var _reach_revision: int = 0
## E3-S33: each placed hole's line of play now, by its tee and cup (Vector4i), for
## _close_footprints. A dogleg's turn (CourseValidator.turn_point) reads only where fairway
## lies, so the lines stand until a write turns a tile to or from fairway (_set_tile drops
## them) or the course is written by someone else (CourseData.revision moved past
## `_lines_revision`). Before, every brush paint measured every open hole's line again, a
## search through its fairway, so a drag on doglegs held 50 ms frames.
## E3-S61: each line is kept with the tiles its turn read (turn_point's `reads`), and a write
## turning a tile to or from fairway drops only the lines that read it: a drag across one
## hole's fairway no longer measures every other hole's line again.
var _lines_now: Dictionary = {}
## The tiles each kept line's turn read ({tile: true}), by the same key.
var _lines_reads: Dictionary = {}
var _lines_revision: int = -1


func _init(p_course: CourseData, p_tuning: BuilderTuning = null, p_validator: CourseValidator = null,
		p_prices: LandPrices = null) -> void:
	_course = p_course
	_tuning = p_tuning if p_tuning != null else BuilderTuning.load_default()
	_validator = p_validator if p_validator != null else CourseValidator.new()
	_prices = p_prices if p_prices != null else LandPrices.load_default()
	# A loaded course may bring in an open hole that fails a rule (a hand-edited or older
	# file): close it now, before anyone reads the open flag. Not an undo step.
	var was_open: Array[bool] = []
	for h: HoleData in _course.holes:
		was_open.append(h.open)
	_rerun(Step.new())
	_holes_dirty = false
	for i: int in _course.holes.size():
		var own: Array = _slot_issues[i]
		if was_open[i] and not _course.holes[i].open and not own.is_empty():
			_closed_on_load.append("Hole %d closed: %s" % [_course.holes[i].number,
					(own[0] as CourseValidator.Issue).reason])


## A new course on the blank plot (D10): BuilderTuning's size, every tile its surface and
## height, no holes. A fresh course, not a write to one; hand it to a new builder.
static func new_sandbox(p_tuning: BuilderTuning = null) -> CourseData:
	var t: BuilderTuning = p_tuning if p_tuning != null else BuilderTuning.load_default()
	return CourseData.create(t.plot_size.x, t.plot_size.y, t.plot_surface, t.plot_ground)


## A New course (E6-S6, D19, D26, D28): the generated land of `land_seed` (LandGenerator),
## owning only the starting block (LandGenerator.start_block, free) with the land budget
## from data/land.json (LandPrices.land_budget). No holes. A fresh course, as new_sandbox
## makes one; hand it to a new builder. The same seed gives the same course.
static func new_course(land_seed: int, p_prices: LandPrices = null,
		p_land: LandTuning = null) -> CourseData:
	var lp: LandPrices = p_prices if p_prices != null else LandPrices.load_default()
	var c: CourseData = LandGenerator.generate(land_seed, p_land)
	var block: Rect2i = LandGenerator.start_block(c.width, c.height)
	for q: int in c.parcels_high:
		for p: int in c.parcels_wide:
			var parcel := Vector2i(p, q)
			c.set_parcel_owned(parcel, block.encloses(c.parcel_rect(parcel)))
	c.set_land_budget(maxi(lp.land_budget, 0))
	return c


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


## Why a brush of `size` on `center` would edit nothing because of land, or "" when it may:
## NOT_YOUR_LAND when it covers tiles on the map and none of them is owned (E6-S4). A brush
## with any owned tile is not refused; it edits only those.
func edit_refusal(center: Vector2i, size: int) -> String:
	var cells: Array[Vector2i] = brush_cells(center, size)
	if cells.is_empty() or not _owned_cells(cells).is_empty():
		return ""
	return NOT_YOUR_LAND


## Why a tee or cup on `cell` would be refused because of land, or "" when it may go there:
## NOT_YOUR_LAND for a tile on the map that is not owned (E6-S4, D30).
func place_refusal(cell: Vector2i) -> String:
	if _course.in_bounds(cell.x, cell.y) and not _course.is_owned(cell.x, cell.y):
		return NOT_YOUR_LAND
	return ""


## Paints `surface` on the owned tiles under the brush. Returns true when any tile changed;
## false, emitting `refused`, when none of the brush is owned (edit_refusal).
func paint(center: Vector2i, surface: Surface.Type, size: int) -> bool:
	assert(Surface.is_valid(surface), "surface out of range")
	if _refuse(edit_refusal(center, size)):
		return false
	var tiles := {}
	for c: Vector2i in _owned_cells(brush_cells(center, size)):
		if _course.get_surface(c.x, c.y) != surface:
			_write(tiles, c, _course.get_height(c.x, c.y), surface)
	return _commit(tiles)


## Raises the owned ground under the brush one step, clamped at MAX_HEIGHT. True when any
## tile changed; refused as paint is.
func raise(center: Vector2i, size: int) -> bool:
	return _lift(center, size, 1)


## Lowers the owned ground under the brush one step, clamped at 0. True when any tile
## changed; refused as paint is.
func lower(center: Vector2i, size: int) -> bool:
	return _lift(center, size, -1)


## Starts grouping edits into one undo step (a mouse drag). Ends any open stroke first.
func begin_stroke() -> void:
	end_stroke()
	_stroke = Step.new()
	_stroke_lifted = {}
	if _course.revision == _lines_revision:
		_stroke.lines = _lines_now.duplicate()
		_stroke.lines_reads = _lines_reads.duplicate()


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


## The hole in slot `slot` (its index in CourseData.holes; read it, do not change it), or null.
func hole_at(slot: int) -> HoleData:
	if slot < 0 or slot >= _course.holes.size():
		return null
	return _course.holes[slot]


## The slot of hole `number`: `slot` itself when it holds that number, else the first slot that
## does, else -1. A stale slot (the holes changed under it) falls back to the number.
func slot_of(number: int, slot: int = -1) -> int:
	var h: HoleData = hole_at(slot)
	if h != null and h.number == number:
		return slot
	return _find(_course.holes, number)


## Every slot, by hole number, then course order for holes sharing a number (the hole list).
func hole_slots() -> Array[int]:
	var out: Array[int] = []
	out.assign(range(_course.holes.size()))
	out.sort_custom(func(a: int, b: int) -> bool:
		var na: int = _course.holes[a].number
		var nb: int = _course.holes[b].number
		return na < nb or (na == nb and a < b))
	return out


## True when another hole shares slot `slot`'s number (E3-S11; rule 1 fails both).
func is_duplicate(slot: int) -> bool:
	var h: HoleData = hole_at(slot)
	if h == null:
		return false
	for i: int in _course.holes.size():
		if i != slot and _course.holes[i].number == h.number:
			return true
	return false


## The nearest number to `number` in direction `dir` (-1 up, +1 down), within 1 to max_holes,
## that no hole has, or 0 when there is none. A duplicate's up and down move it there, so a
## renumber parts it from its twin instead of swapping a third hole onto its old number.
func free_number(number: int, dir: int) -> int:
	var used: Array[int] = hole_numbers()
	var n: int = number + signi(dir)
	while dir != 0 and n >= 1 and n <= _tuning.max_holes:
		if not n in used:
			return n
		n += signi(dir)
	return 0


## Every hole number on the course, lowest first, each once.
func hole_numbers() -> Array[int]:
	var out: Array[int] = []
	for h: HoleData in _course.holes:
		if not h.number in out:
			out.append(h.number)
	out.sort()
	return out


## The number a new hole gets (E3-S2, build order): the lowest of 1 to max_holes with no hole,
## or 0 when the course already holds max_holes holes.
func next_hole_number() -> int:
	if _course.holes.size() >= _tuning.max_holes:
		return 0
	var used: Array[int] = hole_numbers()
	for n: int in range(1, _tuning.max_holes + 1):
		if not n in used:
			return n
	return 0


## Why a tee or cup for hole `number` would not create it, or "" when it may (or the hole
## exists): TOO_MANY_HOLES when `number` is outside 1 to max_holes or the course is full.
func new_hole_refusal(number: int) -> String:
	if hole(number) != null:
		return ""
	if number < 1 or number > _tuning.max_holes or _course.holes.size() >= _tuning.max_holes:
		return TOO_MANY_HOLES % _tuning.max_holes
	return ""


## Hole `number`'s failing rules from the latest validator run; empty when it passes or
## does not exist.
func issues_for(number: int) -> Array[CourseValidator.Issue]:
	var out: Array[CourseValidator.Issue] = []
	if _issues.has(number):
		out.assign(_issues[number])
	return out


## Every slot's own failing rules from the latest validator run, in CourseData.holes order: an
## Array of Arrays of CourseValidator.Issue, the same objects `issues` holds (CourseView names a
## duplicate's lines by slot from it, E3-S27). A fresh outer array; read-only.
func slot_issues() -> Array:
	return _slot_issues.duplicate()


## Slot `slot`'s own failing rules from the latest validator run (E3-S11): for a hole sharing
## its number, rule 1 stands on its own tee and names the other. Empty when it passes or there is no such slot.
func issues_at(slot: int) -> Array[CourseValidator.Issue]:
	var out: Array[CourseValidator.Issue] = []
	if slot >= 0 and slot < _slot_issues.size():
		out.assign(_slot_issues[slot])
	return out


## Every slot's line of play (CourseValidator.line_of_play, D47, D51) as the latest validator run
## measured it, in CourseData.holes order: [tee, cup], [tee, turn, cup], or empty when its tee or
## cup is not placed (E3-S46: Build draws them). Measured afresh when that run did not see the
## current holes.
func slot_lines() -> Array[PackedVector2Array]:
	if _slot_lines.size() == _course.holes.size():
		return _slot_lines.duplicate()
	var out: Array[PackedVector2Array] = []
	for h: HoleData in _course.holes:
		out.append(_validator.line_of_play(_course, h))
	return out


## Slot `slot`'s hints from the latest validator run (CourseValidator.hint_slots, E3-S39):
## advice for Build that never closes the hole. Empty when it has none or there is no slot.
func hints_at(slot: int) -> Array[CourseValidator.Issue]:
	var out: Array[CourseValidator.Issue] = []
	if slot >= 0 and slot < _slot_hints.size():
		out.assign(_slot_hints[slot])
	return out


## Slot `slot`'s yardage along its line of play (D47) as the latest validator run measured
## it, what the card and the hole list show; 0 when its tee or cup is not placed. Measured
## afresh for a slot the latest run did not see.
func yardage_at(slot: int) -> int:
	if slot >= 0 and slot < _slot_yards.size() and _slot_yards.size() == _course.holes.size():
		return _slot_yards[slot]
	if slot < 0 or slot >= _course.holes.size():
		return 0
	return _validator.hole_yardage(_course, _course.holes[slot])


## True when hole `number` exists, is closed and passes every rule.
func can_open(number: int) -> bool:
	var h: HoleData = hole(number)
	return h != null and not h.open and _issues.has(number) and (_issues[number] as Array).is_empty()


## Puts hole `number`'s tee on `cell`, creating the hole (closed, with `par`, or the tuning's
## default par when `par` is not 3, 4 or 5) when there is none. Moving the tee closes it.
## False when `cell` is off the map or the tee is already there, and false, emitting
## `refused`, when `cell` is not owned (place_refusal) or a new hole `number` is not allowed
## (new_hole_refusal). `slot` picks one of several holes sharing `number` (slot_of, E3-S11).
func place_tee(number: int, cell: Vector2i, par: int = 0, slot: int = -1) -> bool:
	return _place(number, cell, true, par, slot)


## Puts hole `number`'s cup on `cell`, as place_tee does for the tee.
func place_cup(number: int, cell: Vector2i, par: int = 0, slot: int = -1) -> bool:
	return _place(number, cell, false, par, slot)


## Sets hole `number`'s par to 3, 4 or 5. False when there is no such hole, the par is not
## one of those, or it is already that par. The rerun closes the hole if rule 4 now fails.
## `slot` picks one of several holes sharing `number` (slot_of).
func set_par(number: int, par: int, slot: int = -1) -> bool:
	if not par in PARS:
		return false
	var hs: Array[HoleData] = _holes_copy()
	var i: int = slot_of(number, slot)
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


## Closes open hole `number` (the hole list's Close), an undo step. False when there is no
## such hole or it is closed already.
func close_hole(number: int) -> bool:
	var h: HoleData = hole(number)
	if h == null or not h.open:
		return false
	end_stroke()
	var hs: Array[HoleData] = _holes_copy()
	hs[_find(hs, number)].open = false
	var step := Step.new()
	_write_holes(step, hs)
	_finish(step)
	return true


## Gives hole `number` the number `to` (1 to max_holes), and any hole that had `to` the number
## `number`, as one undo step (E3-S2). Open flags, tees and cups stay; guests play open holes
## in number order (E3-S4). False when there is no hole `number`, `to` is the same or out of
## range. `slot` picks one of several holes sharing `number` (slot_of, E3-S11): only that
## one moves, and its twin keeps `number`.
func renumber_hole(number: int, to: int, slot: int = -1) -> bool:
	var moved: int = slot_of(number, slot)
	if to == number or to < 1 or to > _tuning.max_holes or moved < 0:
		return false
	end_stroke()
	var hs: Array[HoleData] = _holes_copy()
	for i: int in hs.size():
		if hs[i].number == to:
			hs[i].number = number
	hs[moved].number = to
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
	_reach = null
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
		_set_tile(c, packed >> 4, (packed & 0x0F) as Surface.Type)
		cells.append(c)
	if not cells.is_empty():
		tiles_changed.emit(cells)
	if step.holes != null:
		_course.set_holes(step.holes)
		_holes_dirty = true
	if step.land_parcel != Step.NO_PARCEL:
		_course.set_parcel_owned(step.land_parcel, false)
		_reach = null
		_course.set_land_budget(step.land_budget)
		land_changed.emit(step.land_parcel)
	if not step.lines.is_empty():
		# The course is as it was when the stroke began: so are the lines kept then.
		_lines_now = step.lines.duplicate()
		_lines_reads = step.lines_reads.duplicate()
		_lines_revision = _course.revision
	# The course is back as it was before the edit, when every open hole passed (_init closed
	# any that came in failing), so this rerun refreshes `issues` and usually closes nothing.
	# An undone purchase may close a hole whose tee or cup (rule 6) or path (rule 3) stands
	# on the land given up; that close is not itself an undo step.
	_rerun(Step.new())
	_announce()
	return true


# --- internals ---

func _lift(center: Vector2i, size: int, delta: int) -> bool:
	if _refuse(edit_refusal(center, size)):
		return false
	var tiles := {}
	for c: Vector2i in _owned_cells(brush_cells(center, size)):
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
	_set_tile(c, h, s)


## Writes one tile and notes it for rule 3's graph and the lines of play (_lines_now).
func _set_tile(c: Vector2i, h: int, s: Surface.Type) -> void:
	if (_course.get_surface(c.x, c.y) == Surface.Type.FAIRWAY) != (s == Surface.Type.FAIRWAY):
		for k: Vector4i in _lines_reads.keys():
			if (_lines_reads[k] as Dictionary).has(c):
				_lines_now.erase(k)
				_lines_reads.erase(k)
	_course.set_tile(c.x, c.y, h, s)
	_reach_dirty[c] = true
	_reach_revision += 1
	_lines_revision += 1


## Every slot's line of play on the course as it is now (CourseValidator.line_of_play), in
## CourseData.holes order: slot_lines as it would read if the validator ran now, kept per
## hole while no fairway write lands on a tile its turn reads (_lines_now, E3-S61).
func lines_now() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for h: HoleData in _course.holes:
		out.append(_line_now(h))
	return out


## Hole `h`'s line of play on the course as it is now (CourseValidator.line_of_play), kept in
## _lines_now while no tile its turn read turned to or from fairway.
func _line_now(h: HoleData) -> PackedVector2Array:
	if _course.revision != _lines_revision:
		_lines_now.clear()
		_lines_reads.clear()
		_lines_revision = _course.revision
	var k := Vector4i(h.tee.x, h.tee.y, h.cup.x, h.cup.y)
	if not _lines_now.has(k):
		var reads := {}
		_lines_now[k] = _validator.line_of_play(_course, h, reads)
		_lines_reads[k] = reads
	return _lines_now[k]


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
## The footprint follows the line of play (D51): the line as the last check measured it and the
## line now, so an edit that moves or removes a dogleg's turn closes it either way.
func _close_footprints(step: Step, cells: Array[Vector2i]) -> void:
	var hs: Array[HoleData] = _holes_copy()
	var closed: bool = false
	var kept: bool = _slot_lines.size() == hs.size()
	for i: int in hs.size():
		var h: HoleData = hs[i]
		if not h.open:
			continue
		var lines: Array[PackedVector2Array] = [_line_now(h)]
		if kept and _slot_lines[i] != lines[0]:
			lines.append(_slot_lines[i])
		for c: Vector2i in cells:
			if _validator.near_line(lines[0], c) or (lines.size() > 1 and _validator.near_line(lines[1], c)):
				h.open = false
				closed = true
				break
	if closed:
		_write_holes(step, hs)


## The tiles of `cells` on owned parcels, in order.
func _owned_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in cells:
		if _course.is_owned(c.x, c.y):
			out.append(c)
	return out


## Emits `refused` and returns true when `reason` is not empty.
func _refuse(reason: String) -> bool:
	if reason.is_empty():
		return false
	refused.emit(reason)
	return true


func _place(number: int, cell: Vector2i, is_tee: bool, par: int, slot: int = -1) -> bool:
	if not _course.in_bounds(cell.x, cell.y):
		return false
	if _refuse(place_refusal(cell)) or _refuse(new_hole_refusal(number)):
		return false
	var hs: Array[HoleData] = _holes_copy()
	var i: int = slot_of(number, slot)
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
	_slot_yards = []
	_slot_lines = []
	var turns: Array = []
	# E3-S61: each hole's turn from its kept line of play (_line_now), measured only where an
	# edit could have moved it.
	var known: Array = []
	for line: PackedVector2Array in lines_now():
		known.append(line[1] if line.size() == 3 else null)
	_slot_issues = [] if _course.holes.is_empty() \
			else _validator.check_slots(_course, _current_reach(), _slot_yards, turns, known)
	_slot_hints = _validator.hint_slots(_course)
	for i: int in turns.size():
		var h: HoleData = _course.holes[i]
		_slot_lines.append(PackedVector2Array() if not _course.in_bounds(h.tee.x, h.tee.y)
				or not _course.in_bounds(h.cup.x, h.cup.y) else _validator.line_of_play_through(h, turns[i]))
	_issues = CourseValidator.by_number(_course, _slot_issues)
	var hs: Array[HoleData] = _holes_copy()
	var closed: bool = false
	for h: HoleData in hs:
		if h.open and not (_issues.get(h.number, []) as Array).is_empty():
			h.open = false
			closed = true
	if closed:
		_write_holes(step, hs)


## Rule 3's graph for the course as it is now: the kept one with the tiles written since the
## last check reread, or a fresh one when it was dropped or someone else wrote the course.
func _current_reach() -> CourseValidator.Reach:
	if _reach == null or _course.revision != _reach_revision:
		_reach = CourseValidator.Reach.new(_course)
	else:
		var cells: Array[Vector2i] = []
		cells.assign(_reach_dirty.keys())
		_reach.update(_course, cells)
	_reach_dirty.clear()
	_reach_revision = _course.revision
	return _reach


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
