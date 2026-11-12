class_name GoalList
extends RefCounted
## E10-S1: a New course's goal checklist, SimGolf-style early goals, so a new player always knows
## the next step (docs/playtests/2026-11-11-rc-testers.md, tester 2). Each goal has a title and a
## one-line "how" naming the real controls. The goals read the game: the course's holes (refresh),
## and three things Main tells it as they happen (mark): a guest arriving, a parcel bought, a dusk
## at the target stars. A goal once done stays done, whatever is built or undone after.
##
## Nothing here is course data: a game save carries the done goals and whether the panel is
## collapsed (GameSave.State.goals_*, to_save and from_save).

signal changed

const TEE: String = "tee"
const CUP: String = "cup"
const GREEN: String = "green"
const OPEN: String = "open"
const GUESTS: String = "guests"
const PARCEL: String = "parcel"
const HOLE2: String = "hole2"
const STARS: String = "stars"
## Every goal's id, in the checklist's order. D67: hole 2 before the parcel, since the 4 x 4
## starting block holds several holes and a par 5 is what first needs more land.
const ORDER: PackedStringArray = [TEE, CUP, GREEN, OPEN, GUESTS, HOLE2, PARCEL, STARS]


## One goal: its id, what to do and how.
class Goal:
	extends RefCounted
	var id: String
	var title: String
	var how: String

	func _init(p_id: String, p_title: String, p_how: String) -> void:
		id = p_id
		title = p_title
		how = p_how


var tuning: GoalsTuning
## The done goals' ids (id -> true).
var done: Dictionary = {}
## The player folded the panel to its one "Next: ..." line.
var collapsed: bool = false

var _goals: Array[Goal] = []


func _init(p_tuning: GoalsTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else GoalsTuning.load_default()
	var stars: int = roundi(tuning.target_stars)
	_goals = [
		Goal.new(TEE, "Place a tee",
				"Pick Tee on the bottom bar, then click on your land (the unhatched block)."),
		Goal.new(CUP, "Place the cup",
				"Pick Cup and click where the hole ends: the ruler shows its length in yards."),
		Goal.new(GREEN, "Paint a green round the cup",
				"Pick green on the bottom bar and drag over the cup and the tiles round it."),
		Goal.new(OPEN, "Open the hole",
				"It opens by itself once it passes every rule; the hole list says what is wrong."),
		Goal.new(GUESTS, "Guests arrive and pay",
				"Guests walk out of the clubhouse and pay the green fee (Fee) at the first tee: " +
				"that is your income. Each open hole costs upkeep at dusk."),
		Goal.new(HOLE2, "Build hole 2",
				"Press New hole in the hole list, then place its tee and cup and paint its green."),
		Goal.new(PARCEL, "Buy a parcel",
				"When your land is full (a par 5 needs more), pick Buy land, click a parcel " +
				"touching your land, then Buy (Enter)."),
		Goal.new(STARS, "Reach %d stars" % stars,
				"Guests rate each hole they play: end a day at %d stars or more (top left)." % stars),
	]


## Every goal, in order.
func goals() -> Array[Goal]:
	return _goals.duplicate()


func goal(id: String) -> Goal:
	for g: Goal in _goals:
		if g.id == id:
			return g
	return null


func is_done(id: String) -> bool:
	return done.has(id)


## The first goal not done, or null when every one is.
func next_goal() -> Goal:
	for g: Goal in _goals:
		if not done.has(g.id):
			return g
	return null


## How many goals are done.
func done_count() -> int:
	return done.size()


## Marks goal `id` done. True when it was not done before (and emits `changed`).
func mark(id: String) -> bool:
	if done.has(id) or goal(id) == null:
		return false
	done[id] = true
	changed.emit()
	return true


## Ticks every goal course `c`'s holes now meet: a tee placed, a hole with its tee and cup, a cup
## on green, an open hole, two open holes. Never unticks one.
func refresh(c: CourseData) -> void:
	if c == null:
		return
	var any: bool = false
	for id: String in meets(c):
		any = _tick(id) or any
	if any:
		changed.emit()


## The ids of the goals course `c`'s holes meet now (refresh).
static func meets(c: CourseData) -> PackedStringArray:
	var out: PackedStringArray = []
	var tee: bool = false
	var cup: bool = false
	var green: bool = false
	var open: int = 0
	for h: HoleData in c.holes:
		var has_tee: bool = c.in_bounds(h.tee.x, h.tee.y)
		var has_cup: bool = c.in_bounds(h.cup.x, h.cup.y)
		tee = tee or has_tee
		if has_tee and has_cup:
			cup = true
			if c.get_surface(h.cup.x, h.cup.y) == Surface.Type.GREEN:
				green = true
			if h.open:
				open += 1
	if tee:
		out.append(TEE)
	if cup:
		out.append(CUP)
	if green:
		out.append(GREEN)
	if open >= 1:
		out.append(OPEN)
	if open >= 2:
		out.append(HOLE2)
	return out


## True when course `c` has a hole with both its tee and its cup placed: one Play can start on.
static func has_playable_hole(c: CourseData) -> bool:
	if c == null:
		return false
	for h: HoleData in c.holes:
		if c.in_bounds(h.tee.x, h.tee.y) and c.in_bounds(h.cup.x, h.cup.y):
			return true
	return false


## The done ids, in the checklist's order, for a save.
func done_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for g: Goal in _goals:
		if done.has(g.id):
			out.append(g.id)
	return out


## Takes the done goals and the fold back from a save; ids it does not know are dropped.
func restore(ids: PackedStringArray, p_collapsed: bool) -> void:
	done.clear()
	for id: String in ids:
		if goal(id) != null:
			done[id] = true
	collapsed = p_collapsed
	changed.emit()


func _tick(id: String) -> bool:
	if done.has(id):
		return false
	done[id] = true
	return true
