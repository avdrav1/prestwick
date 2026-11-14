class_name ReactionFeed
extends RefCounted
## The guests' reactions as the player reads them (E3-S7; docs/design.md Guests and reactions,
## Feed): the feed's lines, newest last, and each hole's tally for its map tag. Pure data, fed
## by GuestSim from GuestBrain.reacted across days; it never reads a clock or draws a random
## number, so the same seed gives the same feed.
##
## Lines: praise and complaints only (D39: a neutral is quiet). Each line is one reaction's
## text ("Hole N: ..."), with the day and simulated second it came and the hole it names, so a
## click can jump there. Several guests finishing at once (a group holing out in one step)
## give their lines in the brain's fixed order; a line identical to one already given in the
## same second (same hole, verdict and text: a pair that both loved it, 3 on a par 3) folds
## into it as a count ("x2") instead of a second row. The feed keeps the newest `max_entries`.
##
## Tags: each hole's praise and complaint count among the last `window` hole reactions, the
## neutrals included in the window: the reactions E4-S5's rating averages (`rating_window`,
## D39), so a tag says what the course's rating is made of, hole by hole. A tally belongs to
## the hole guests played, by its slot (slot_tallies); tally() and tallies() go by the number
## a reaction named.
##
## Edits (E3-S17): a verdict is about the hole as guests played it. When Build changes a
## hole's tee, cup or par, or the terrain on its line (a tile in its D11 footprint, as the
## builder's close rule reads it), its reactions so far are cleared from its tally
## (holes_edited, cells_edited; GuestSim.watch feeds them from the builder): they keep their
## place in the window, but count for no hole (CLEARED). Undoing the edit is an edit too, so
## the old verdicts do not come back. A renumber, a swap or an open flag keeps the tally. A
## slot that goes away (a new hole undone) is cleared and its lines unlinked, so a hole placed
## later at the same slot starts with none and an old line never jumps to it. A guest playing
## the hole when it is edited gives a verdict on the old version: GuestSim pushes it
## uncounted (slot_edited, push's `counted`), so it too counts for no hole. Cleared reactions
## keep their window place and count as neutral in the course rating (rating, D58).
##
## History (E3-S68): a line given before its hole's last edit is marked `edited` (clear_slot),
## and so is a line pushed uncounted (a verdict on the version before the edit); the feed draws
## those dimmed. They still link. A line given after the edit is not marked.

## A line was added (or, folded, its count grew); `entry` is the line.
signal added(entry: Entry)
## The feed was emptied (a new course).
signal cleared
## The reactions about the hole in slot `slot` were cleared from its tally (E3-S17).
signal slot_cleared(slot: int)
## The hole in slot `slot` was edited (or went away): emitted on every clear_slot, whether or
## not the window held a reaction for it, so GuestSim can drop the plays under way there.
signal slot_edited(slot: int)
## E12-S1 (D68): cart path the walk to the tee of the hole in slot `slot` can reach was laid or
## taken up: its walk complaints were cleared (walks_edited), so GuestSim can drop the verdicts
## of guests that walked there before the edit.
signal walk_edited(slot: int)
## E4-S5: the window changed (a push, neutrals included, a clear, a clear_slot that cleared a
## reaction, a copy_from), so the course rating (rating) may have moved.
signal changed

## The slot of a reaction or a line whose hole was edited or removed since (E3-S17): it counts
## for no hole and links to none.
const CLEARED: int = -2

## One line of the feed.
class Entry:
	## Arrival order, from 1; a folded line keeps its first id.
	var id: int = 0
	var day: int = 0
	var second: int = 0
	## The hole's number when the guest named it (the text says it).
	var hole_number: int = 0
	## The hole's slot in CourseData.holes when the guest named it, -1 when unknown, CLEARED
	## once that hole is gone (E3-S17).
	var slot: int = -1
	var kind: GuestReaction.Kind = GuestReaction.Kind.NEUTRAL
	var text: String = ""
	## E3-S44: the checks the reaction failed, in the player's words ("Failed: sight line and
	## pace.", GuestReaction.failed_line), or "" for a praise. The feed row's hover shows it.
	var failed_text: String = ""
	## How many guests gave this exact line in this second.
	var count: int = 1
	## E3-S68: its hole has been edited since the line was given (or it judged the version
	## before an edit): the feed draws it dimmed, as history.
	var edited: bool = false
	## E12-S1: the reaction failed its walk (a cart path edit the walk can reach dims it).
	var walk_failed: bool = false

	func is_praise() -> bool:
		return kind == GuestReaction.Kind.PRAISE

	## The line as the feed shows it: the reaction's text, then "x n" when folded. With
	## `number` above 0 (the hole's number now) the leading "Hole N" says that number, so a
	## hole renumbered since the guest spoke reads as the hole the line links to.
	func display_text(number: int = 0) -> String:
		var t := text
		var named := "Hole %d" % hole_number
		if number > 0 and number != hole_number and t.begins_with(named):
			t = "Hole %d" % number + t.substr(named.length())
		return t if count <= 1 else "%s (x%d)" % [t, count]


## The lines kept, oldest first.
var entries: Array[Entry] = []
## The newest `window` hole reactions, oldest first (neutrals included).
var recent: Array[GuestReaction] = []
## The slot each of `recent` was given at (-1 when unknown, CLEARED after an edit), by index.
var recent_slots: Array[int] = []
## The day each of `recent` was given on, by index (E4-S7: a save keeps the window as it stood at
## the morning of the saved day, to_save).
var recent_days: Array[int] = []
## E4-S11: the window reactions of earlier days that reactions of day `spill_day` pushed out,
## oldest first, with their slots and days (parallel, like `recent`). to_save puts them back, so
## a save keeps the window whole as it stood that morning: the stars its arrivals were drawn at.
## An edit clears them as it clears the window (clear_slot). A new day's first push-out drops them.
var spilled: Array[GuestReaction] = []
var spilled_slots: Array[int] = []
var spilled_days: Array[int] = []
var spill_day: int = 0
## How many reactions a tag counts (GuestTuning.rating_window).
var window: int = 50
## How many lines the feed keeps.
var max_entries: int = 100
## Every reaction pushed, neutrals included.
var total: int = 0
## E4-S12: `total` as it stood at the morning of each day a reaction was pushed on (before the
## day's first push), by day. to_save keeps the saved day's morning total, so a load that replays
## the day counts its reactions once, even those the day itself pushed out of the window.
var morning_totals: Dictionary = {}

var _next_id: int = 1


func _init(p_window: int = 50, p_max_entries: int = 100) -> void:
	window = maxi(p_window, 1)
	max_entries = maxi(p_max_entries, 1)


## Takes `reaction`, given on day `day` at simulated second `second`, about the hole in slot
## `slot` of CourseData.holes (-1 when unknown: resolve_slot then goes by the number). Not
## `counted` (a verdict on a version of the hole Build has edited since the guest started it,
## E3-S17 review): it takes its window place CLEARED, its line still linking to `slot`. Returns
## the line it made or grew, or null for a neutral (counted in the tags' window, not shown).
func push(reaction: GuestReaction, day: int, second: int, slot: int = -1, counted: bool = true) -> Entry:
	if not morning_totals.has(day):
		morning_totals[day] = total
	total += 1
	recent.append(reaction)
	recent_slots.append(slot if counted else CLEARED)
	recent_days.append(day)
	if recent.size() > window:
		_spill(recent.size() - window, day)
		recent = recent.slice(recent.size() - window)
		recent_slots = recent_slots.slice(recent_slots.size() - window)
		recent_days = recent_days.slice(recent_days.size() - window)
	changed.emit()
	if reaction.kind == GuestReaction.Kind.NEUTRAL:
		return null
	for i: int in range(entries.size() - 1, -1, -1):
		var e: Entry = entries[i]
		if e.day != day or e.second != second:
			break
		if e.hole_number == reaction.hole_number and e.slot == slot and e.kind == reaction.kind \
				and e.text == reaction.text and e.edited == not counted:
			e.count += 1
			added.emit(e)
			return e
	var entry := Entry.new()
	entry.id = _next_id
	_next_id += 1
	entry.day = day
	entry.second = second
	entry.hole_number = reaction.hole_number
	entry.slot = slot
	entry.kind = reaction.kind
	entry.text = reaction.text
	entry.failed_text = "" if reaction.is_praise() else reaction.failed_line()
	entry.edited = not counted
	entry.walk_failed = not reaction.passed[GuestReaction.Check.WALK]
	entries.append(entry)
	if entries.size() > max_entries:
		entries = entries.slice(entries.size() - max_entries)
	added.emit(entry)
	return entry


## E4-S11: keeps the oldest `n` window reactions, which a reaction of day `day` is pushing out,
## when they were given on an earlier day (spilled).
func _spill(n: int, day: int) -> void:
	if day != spill_day:
		_clear_spill()
		spill_day = day
	for i: int in n:
		if recent_days[i] < day:
			spilled.append(recent[i])
			spilled_slots.append(recent_slots[i])
			spilled_days.append(recent_days[i])


func _clear_spill() -> void:
	spilled.clear()
	spilled_slots.clear()
	spilled_days.clear()
	spill_day = 0


## Empties the feed and the tags (a new course).
func clear() -> void:
	entries.clear()
	recent.clear()
	recent_slots.clear()
	recent_days.clear()
	_clear_spill()
	total = 0
	morning_totals.clear()
	_next_id = 1
	cleared.emit()
	changed.emit()


## E4-S7: the feed as the game save keeps it (GameSave), as it stood at the morning of day
## `before_day`: the lines and window reactions of earlier days only. A load resumes at that
## morning and the day plays again from its seed, so its own lines come in again rather than
## twice (E4-S12: its total too, morning_total). E4-S11: a reaction of that day that pushed an older one out of the window puts it back
## (spilled), so the window is the morning's whole and the load's morning has its stars.
func to_save(before_day: int) -> Dictionary:
	var lines: Array = []
	for e: Entry in entries:
		if e.day < before_day:
			lines.append({"id": e.id, "day": e.day, "second": e.second, "hole": e.hole_number,
					"slot": e.slot, "kind": int(e.kind), "text": e.text, "failed": e.failed_text,
					"count": e.count, "edited": e.edited, "walk": e.walk_failed})
	var window_out: Array = []
	if spill_day >= before_day:
		for i: int in spilled.size():
			if spilled_days[i] < before_day:
				var sr: Dictionary = spilled[i].to_save()
				sr["slot"] = spilled_slots[i]
				sr["day"] = spilled_days[i]
				window_out.append(sr)
	for i: int in recent.size():
		var d: int = recent_days[i] if i < recent_days.size() else 0
		if d >= before_day:
			continue
		var r: Dictionary = recent[i].to_save()
		r["slot"] = recent_slots[i]
		r["day"] = d
		window_out.append(r)
	var next_id: int = 1 if lines.is_empty() else int(lines[lines.size() - 1]["id"]) + 1
	return {"lines": lines, "window": window_out, "total": morning_total(before_day), "next_id": next_id}


## E4-S12: `total` as it stood at the morning of day `day`: before the first reaction pushed on
## that day or a later one, every reaction pushed when none has been since.
func morning_total(day: int) -> int:
	var first := -1
	for d: int in morning_totals:
		if d >= day and (first < 0 or d < first):
			first = d
	return total if first < 0 else int(morning_totals[first])


## A feed of `window` and `max_entries` holding what `d` (to_save) holds, or null with the
## reasons appended to `errors`. Nothing is emitted: copy_from hands it to the feed on show.
static func from_save(d: Variant, p_window: int, p_max_entries: int, errors: Array[String]) -> ReactionFeed:
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("feed must be an object")
		return null
	var data: Dictionary = d
	var start := errors.size()
	var f := ReactionFeed.new(p_window, p_max_entries)
	var lines: Variant = data.get("lines")
	var win: Variant = data.get("window")
	if typeof(lines) != TYPE_ARRAY or typeof(win) != TYPE_ARRAY:
		errors.append("feed: lines and window must be lists")
		return null
	for i: int in (lines as Array).size():
		var l: Variant = lines[i]
		var ctx := "feed line %d" % (i + 1)
		if typeof(l) != TYPE_DICTIONARY:
			errors.append("%s must be an object" % ctx)
			continue
		var ld: Dictionary = l
		var e := Entry.new()
		e.id = CourseData.read_int(ld, "id", errors, ctx)
		e.day = CourseData.read_int(ld, "day", errors, ctx)
		e.second = CourseData.read_int(ld, "second", errors, ctx)
		e.hole_number = CourseData.read_int(ld, "hole", errors, ctx)
		e.slot = CourseData.read_int(ld, "slot", errors, ctx)
		var k := CourseData.read_int(ld, "kind", errors, ctx)
		if k < 0 or k >= GuestReaction.Kind.size():
			errors.append("%s: kind %d is not a kind" % [ctx, k])
		e.kind = k as GuestReaction.Kind
		e.text = str(ld.get("text", ""))
		e.failed_text = str(ld.get("failed", ""))
		e.count = maxi(CourseData.read_int(ld, "count", errors, ctx), 1)
		e.edited = bool(ld.get("edited", false))
		e.walk_failed = bool(ld.get("walk", false))  # E12-S1; false in older saves
		f.entries.append(e)
	for i: int in (win as Array).size():
		var ctx := "feed reaction %d" % (i + 1)
		var r := GuestReaction.from_save(win[i], errors, ctx)
		if r == null:
			continue
		var rd: Dictionary = win[i]
		f.recent.append(r)
		f.recent_slots.append(CourseData.read_int(rd, "slot", errors, ctx))
		f.recent_days.append(CourseData.read_int(rd, "day", errors, ctx))
	f.total = CourseData.read_int(data, "total", errors, "feed")
	f._next_id = maxi(CourseData.read_int(data, "next_id", errors, "feed"), 1)
	if errors.size() > start:
		return null
	if f.entries.size() > f.max_entries:
		f.entries = f.entries.slice(f.entries.size() - f.max_entries)
	if f.recent.size() > f.window:
		var cut := f.recent.size() - f.window
		f.recent = f.recent.slice(cut)
		f.recent_slots = f.recent_slots.slice(cut)
		f.recent_days = f.recent_days.slice(cut)
	return f


## Takes `other`'s lines, window and counts (a loaded game, E4-S7) and tells the views:
## `cleared`, then `added` for the newest line, so each redraws from what it now holds.
func copy_from(other: ReactionFeed) -> void:
	entries = other.entries.duplicate()
	recent = other.recent.duplicate()
	recent_slots = other.recent_slots.duplicate()
	recent_days = other.recent_days.duplicate()
	_clear_spill()
	total = other.total
	morning_totals = other.morning_totals.duplicate()
	_next_id = other._next_id
	cleared.emit()
	if not entries.is_empty():
		added.emit(entries[entries.size() - 1])
	changed.emit()


## The newest `n` lines, newest first.
func newest(n: int) -> Array[Entry]:
	var out: Array[Entry] = []
	for i: int in range(entries.size() - 1, maxi(entries.size() - n, 0) - 1, -1):
		out.append(entries[i])
	return out


## The id of the newest line, 0 with none.
func newest_id() -> int:
	return 0 if entries.is_empty() else entries[entries.size() - 1].id


## The slot of `c.holes` a reaction given at slot `slot` about hole `number` stands for now:
## `slot` while the course still has it, else the first hole numbered `number`, else -1. A
## CLEARED slot stands for none.
static func resolve_slot(c: CourseData, slot: int, number: int) -> int:
	return -1 if c == null else _resolve_in(c.holes, slot, number)


static func _resolve_in(holes: Array[HoleData], slot: int, number: int) -> int:
	if slot == CLEARED:
		return -1
	if slot >= 0 and slot < holes.size():
		return slot
	for i: int in holes.size():
		if holes[i].number == number:
			return i
	return -1


## Clears the tally of the hole in slot `slot` of `holes` (the course's holes when the
## reactions were given): every reaction in the window given at that slot, or slotless and
## standing for it by its number, counts for no hole from now on (CLEARED), and every line about
## it so far is marked `edited` (E3-S68). With `unlink`, the lines that link to it link to none
## (the hole is gone). Emits slot_cleared when anything changed.
func clear_slot(holes: Array[HoleData], slot: int, unlink: bool = false) -> void:
	slot_edited.emit(slot)
	var any: bool = false
	var rated_changed: bool = false
	for i: int in recent.size():
		var at: int = recent_slots[i]
		if at != slot and (at != -1 or _resolve_in(holes, -1, recent[i].hole_number) != slot):
			continue
		recent_slots[i] = CLEARED
		any = true
		rated_changed = true
	# E4-S11: the morning's reactions already pushed out are about the hole as it was too.
	for i: int in spilled.size():
		var at: int = spilled_slots[i]
		if at == slot or (at == -1 and _resolve_in(holes, -1, spilled[i].hole_number) == slot):
			spilled_slots[i] = CLEARED
	for e: Entry in entries:
		if e.slot == slot or (e.slot == -1 and _resolve_in(holes, -1, e.hole_number) == slot):
			if not e.edited:
				e.edited = true
				any = true
			if unlink:
				e.slot = CLEARED
				any = true
	if any:
		slot_cleared.emit(slot)
	if rated_changed:
		changed.emit()


## The course's holes went from `before` to `after` (copies, by slot): a slot whose tee, cup or
## par changed has its tally cleared; a slot either side lacks is cleared and unlinked. A
## renumber or an open flag changes nothing here.
func holes_edited(before: Array[HoleData], after: Array[HoleData]) -> void:
	for i: int in maxi(before.size(), after.size()):
		if i >= before.size() or i >= after.size():
			clear_slot(before, i, true)
			continue
		var was: HoleData = before[i]
		var now: HoleData = after[i]
		if was.tee != now.tee or was.cup != now.cup or was.par != now.par:
			clear_slot(before, i)


## Tiles `cells` of `c` were written: every hole with one of them in its footprint
## (`validator`, D11) has its tally cleared. The footprint follows the line of play (D51) now
## and, when `before` holds it by slot, the line as it stood before the edit (the builder's
## latest check, CourseBuilder.slot_lines), so an edit that moves or removes a dogleg's turn
## clears the hole either way (E3-S61: the cells of a drag come in batches, once a frame).
## `now`, when it holds every slot, is the lines now as the caller has them
## (CourseBuilder.lines_now, kept between edits), else they are measured here.
func cells_edited(c: CourseData, cells: Array[Vector2i], validator: CourseValidator,
		before: Array[PackedVector2Array] = [], now: Array[PackedVector2Array] = []) -> void:
	# E3-S16: a cell outside the footprint's bounding box is no nearer the line than its
	# half width, so it is passed over without the segment tests (an undo of a big drag off
	# every line tested each of its tiles against each hole's whole line).
	var pad: float = validator.tuning.footprint_half_width_yd / CourseValidator.YARDS_PER_TILE + 1.0
	for i: int in c.holes.size():
		var lines: Array[PackedVector2Array] = [now[i] if now.size() == c.holes.size()
				else validator.line_of_play(c, c.holes[i])]
		if i < before.size() and before[i] != lines[0]:
			lines.append(before[i])
		for line: PackedVector2Array in lines:
			if not line.is_empty() and _touches(line, cells, validator, pad):
				clear_slot(c.holes, i)
				break


## E12-S1 (D68): tiles `cells` of `c` turned to or from cart path. Each walk of a round
## (GuestWalk.round_walks) the change can reach (GuestWalk.path_edit_reaches: a tile within
## `cart_path_reach_yd` of its ends, or on or beside a path piece that is) has its walk
## complaints cleared from the tally of the hole it leads to (clear_walk), so the next guests'
## verdict on the walk shows. Returns the slots cleared. E18-S5: `grid`, when given, is
## GuestWalk.path_grid(c) as it is now (GuestSim has just read it), else it is read here.
func walks_edited(c: CourseData, cells: Array[Vector2i], tuning: GuestTuning,
		ypt: float = 5.0, grid: PackedByteArray = PackedByteArray()) -> Array[int]:
	var out: Array[int] = []
	if cells.is_empty():
		return out
	if grid.is_empty():
		grid = GuestWalk.path_grid(c)
	for w: Dictionary in GuestWalk.round_walks(c, ypt):
		if GuestWalk.path_edit_reaches(c, w.from, w.to, cells, tuning, ypt, grid):
			clear_walk(c.holes, int(w.to_slot))
			out.append(int(w.to_slot))
	return out


## E12-S1 (D68): the reactions in the window about the hole in slot `slot` of `holes` that failed
## their walk count for no hole from now on (CLEARED, as clear_slot clears them, the other
## reactions kept), and their lines are marked `edited` (dimmed, E3-S68). Emits walk_edited
## always, and slot_cleared and changed when it cleared one.
func clear_walk(holes: Array[HoleData], slot: int) -> void:
	walk_edited.emit(slot)
	var any: bool = false
	for i: int in recent.size():
		if recent_slots[i] == CLEARED or recent[i].passed[GuestReaction.Check.WALK]:
			continue
		var at: int = recent_slots[i]
		if at != slot and (at != -1 or _resolve_in(holes, -1, recent[i].hole_number) != slot):
			continue
		recent_slots[i] = CLEARED
		any = true
	for i: int in spilled.size():
		var at: int = spilled_slots[i]
		if spilled[i].passed[GuestReaction.Check.WALK]:
			continue
		if at == slot or (at == -1 and _resolve_in(holes, -1, spilled[i].hole_number) == slot):
			spilled_slots[i] = CLEARED
	for e: Entry in entries:
		if not e.walk_failed or e.edited:
			continue
		if e.slot == slot or (e.slot == -1 and _resolve_in(holes, -1, e.hole_number) == slot):
			e.edited = true
			any = true
	if any:
		slot_cleared.emit(slot)
		changed.emit()


## True when one of `cells` is near `line` (CourseValidator.near_line), testing only the cells
## inside the line's bounding box grown by `pad` tiles.
static func _touches(line: PackedVector2Array, cells: Array[Vector2i], validator: CourseValidator,
		pad: float) -> bool:
	var box := Rect2(line[0], Vector2.ZERO)
	for pt: Vector2 in line:
		box = box.expand(pt)
	box = box.grow(pad)
	for cell: Vector2i in cells:
		if box.has_point(Vector2(cell)) and validator.near_line(line, cell):
			return true
	return false


## {slot of `c.holes`: Vector2i(praise, complaints)} for every hole of `c` with a praise or a
## complaint in the window, each reaction on the hole it was given about (resolve_slot).
func slot_tallies(c: CourseData) -> Dictionary:
	var out := {}
	for i: int in recent.size():
		var r: GuestReaction = recent[i]
		if r.kind == GuestReaction.Kind.NEUTRAL:
			continue
		var at: int = resolve_slot(c, recent_slots[i], r.hole_number)
		if at < 0:
			continue
		var t: Vector2i = out.get(at, Vector2i.ZERO)
		if r.kind == GuestReaction.Kind.PRAISE:
			t.x += 1
		else:
			t.y += 1
		out[at] = t
	return out


## The reactions in the window that still count (not CLEARED), oldest first, neutrals
## included. A cleared reaction holds its window place until newer ones push it out; the
## course rating (rating) counts it as neutral (D58).
func rated() -> Array[GuestReaction]:
	var out: Array[GuestReaction] = []
	for i: int in recent.size():
		if recent_slots[i] != CLEARED:
			out.append(recent[i])
	return out


## E4-S5 (D58): the course rating, the mean of `points` (praise, neutral and complaint, in
## GuestReaction.Kind order: EconomyTuning.rating_points) over the full window of `window`
## reactions. A window short of `window` is filled with neutrals, so a new course rates the
## neutral's points (3 stars), and a reaction cleared by an edit counts as neutral, so the
## mean always divides by `window`.
func rating(points: PackedFloat32Array) -> float:
	var neutral: float = points[GuestReaction.Kind.NEUTRAL]
	var sum: float = neutral * maxi(window - recent.size(), 0)
	for i: int in recent.size():
		sum += neutral if recent_slots[i] == CLEARED else points[recent[i].kind]
	return sum / window


## Hole `number`'s tally in the window, by the number guests named: Vector2i(praise, complaints),
## less the reactions cleared by an edit.
func tally(number: int) -> Vector2i:
	var t := Vector2i.ZERO
	for i: int in recent.size():
		var r: GuestReaction = recent[i]
		if r.hole_number != number or recent_slots[i] == CLEARED:
			continue
		if r.kind == GuestReaction.Kind.PRAISE:
			t.x += 1
		elif r.kind == GuestReaction.Kind.COMPLAINT:
			t.y += 1
	return t


## {hole number: Vector2i(praise, complaints)} for every hole with a praise or a complaint in
## the window, by the number guests named (the map tags go by slot: slot_tallies).
func tallies() -> Dictionary:
	var out := {}
	for i: int in recent.size():
		var r: GuestReaction = recent[i]
		if r.kind == GuestReaction.Kind.NEUTRAL or recent_slots[i] == CLEARED:
			continue
		var t: Vector2i = out.get(r.hole_number, Vector2i.ZERO)
		if r.kind == GuestReaction.Kind.PRAISE:
			t.x += 1
		else:
			t.y += 1
		out[r.hole_number] = t
	return out
