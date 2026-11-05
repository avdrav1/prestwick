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
## D39), so a tag says what the course's rating is made of, hole by hole. A hole's tally is by
## the number its reactions named.

## A line was added (or, folded, its count grew); `entry` is the line.
signal added(entry: Entry)
## The feed was emptied (a new course).
signal cleared

## One line of the feed.
class Entry:
	## Arrival order, from 1; a folded line keeps its first id.
	var id: int = 0
	var day: int = 0
	var second: int = 0
	## The hole's number when the guest named it (the text says it).
	var hole_number: int = 0
	## The hole's slot in CourseData.holes when the guest named it, or -1 when unknown.
	var slot: int = -1
	var kind: GuestReaction.Kind = GuestReaction.Kind.NEUTRAL
	var text: String = ""
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
## The slot each of `recent` was given at (-1 when unknown), by index.
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
## `slot` of CourseData.holes (-1 when unknown: resolve_slot then goes by the number). Returns
## the line it made or grew, or null for a neutral (counted in the tags' window, not shown).
func push(reaction: GuestReaction, day: int, second: int, slot: int = -1) -> Entry:
	total += 1
	recent.append(reaction)
	recent_slots.append(slot)
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
## `slot` while the course still has it, else the first hole numbered `number`, else -1.
static func resolve_slot(c: CourseData, slot: int, number: int) -> int:
	if c == null:
		return -1
	if slot >= 0 and slot < c.holes.size():
		return slot
	for i: int in c.holes.size():
		if c.holes[i].number == number:
			return i
	return -1


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


## Hole `number`'s tally in the window, by the number guests named: Vector2i(praise, complaints).
func tally(number: int) -> Vector2i:
	var t := Vector2i.ZERO
	for r: GuestReaction in recent:
		if r.hole_number != number:
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
	for r: GuestReaction in recent:
		if r.kind == GuestReaction.Kind.NEUTRAL:
			continue
		var t: Vector2i = out.get(r.hole_number, Vector2i.ZERO)
		if r.kind == GuestReaction.Kind.PRAISE:
			t.x += 1
		else:
			t.y += 1
		out[r.hole_number] = t
	return out
