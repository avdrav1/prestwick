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
## keep their window place for E4-S5's rating but are left out of its average (rated).

## A line was added (or, folded, its count grew); `entry` is the line.
signal added(entry: Entry)
## The feed was emptied (a new course).
signal cleared
## The reactions about the hole in slot `slot` were cleared from its tally (E3-S17).
signal slot_cleared(slot: int)
## The hole in slot `slot` was edited (or went away): emitted on every clear_slot, whether or
## not the window held a reaction for it, so GuestSim can drop the plays under way there.
signal slot_edited(slot: int)

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
## How many reactions a tag counts (GuestTuning.rating_window).
var window: int = 50
## How many lines the feed keeps.
var max_entries: int = 100
## Every reaction pushed, neutrals included.
var total: int = 0

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
	total += 1
	recent.append(reaction)
	recent_slots.append(slot if counted else CLEARED)
	if recent.size() > window:
		recent = recent.slice(recent.size() - window)
		recent_slots = recent_slots.slice(recent_slots.size() - window)
	if reaction.kind == GuestReaction.Kind.NEUTRAL:
		return null
	for i: int in range(entries.size() - 1, -1, -1):
		var e: Entry = entries[i]
		if e.day != day or e.second != second:
			break
		if e.hole_number == reaction.hole_number and e.slot == slot and e.kind == reaction.kind and e.text == reaction.text:
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
	entries.append(entry)
	if entries.size() > max_entries:
		entries = entries.slice(entries.size() - max_entries)
	added.emit(entry)
	return entry


## Empties the feed and the tags (a new course).
func clear() -> void:
	entries.clear()
	recent.clear()
	recent_slots.clear()
	total = 0
	_next_id = 1
	cleared.emit()


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
## standing for it by its number, counts for no hole from now on (CLEARED). With `unlink`, the lines that link to
## it link to none (the hole is gone). Emits slot_cleared when anything changed.
func clear_slot(holes: Array[HoleData], slot: int, unlink: bool = false) -> void:
	slot_edited.emit(slot)
	var changed: bool = false
	for i: int in recent.size():
		var at: int = recent_slots[i]
		if at != slot and (at != -1 or _resolve_in(holes, -1, recent[i].hole_number) != slot):
			continue
		recent_slots[i] = CLEARED
		changed = true
	if unlink:
		for e: Entry in entries:
			if e.slot == slot or (e.slot == -1 and _resolve_in(holes, -1, e.hole_number) == slot):
				e.slot = CLEARED
				changed = true
	if changed:
		slot_cleared.emit(slot)


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
## (`validator`, D11) has its tally cleared.
func cells_edited(c: CourseData, cells: Array[Vector2i], validator: CourseValidator) -> void:
	# E3-S16: a cell outside the footprint's bounding box is no nearer the line than its
	# half width, so it is passed over without the segment tests (an undo of a big drag off
	# every line tested each of its tiles against each hole's whole line).
	var pad: float = validator.tuning.footprint_half_width_yd / CourseValidator.YARDS_PER_TILE + 1.0
	for i: int in c.holes.size():
		var line: PackedVector2Array = validator.line_of_play(c, c.holes[i])
		if line.is_empty():
			continue
		var box := Rect2(line[0], Vector2.ZERO)
		for pt: Vector2 in line:
			box = box.expand(pt)
		box = box.grow(pad)
		for cell: Vector2i in cells:
			if box.has_point(Vector2(cell)) and validator.near_line(line, cell):
				clear_slot(c.holes, i)
				break


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
## included: the ones E4-S5's course rating averages. A cleared reaction holds its window
## place, so the average reads fewer than `window` until newer ones push it out.
func rated() -> Array[GuestReaction]:
	var out: Array[GuestReaction] = []
	for i: int in recent.size():
		if recent_slots[i] != CLEARED:
			out.append(recent[i])
	return out


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
