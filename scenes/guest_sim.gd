class_name GuestSim
extends Node
## Runs the guests' day in Play (E3-S5): owns the GuestBrain of the course on show and turns
## real time into its simulated seconds at the chosen speed (docs/design.md Economy and time:
## pause, 1x, 3x). The brain steps once per simulated second (GuestBrain.advance_real), never
## per frame; this node only says how much real time went by and how fast.
##
## The day runs only while `running` (Main sets it in Play); Build holds it where it is, and
## Play picks it up again. The first day is built the first time it runs, so loading a course
## or a test that never plays pays nothing (GuestClubTable.warm). At dusk the next day starts
## at once, with the next day's seed: skipping the night to the morning, and anything a day's
## end settles (fees, upkeep), waits for E4.
##
## The same seed gives the same day: day `d` of a course is GuestBrain's day of
## day_seed(base_seed, d), whatever the speed, the frame rate or what the camera looks at.
##
## The feed (E3-S7): every reaction of every day goes into `feed` (ReactionFeed) with its day
## and second, for the HUD feed and the map tags; a new course empties it. Edits in Build
## (E3-S17): watch(builder) hands the feed every hole and tile change the builder makes, so a
## hole's tally is cleared when its tee, cup, par or the terrain on its line changes, and a hole
## undone away takes its tally and links with it. A guest playing the hole when it is edited
## judges the old version: its reaction comes in uncounted (E3-S17 review, _on_slot_edited).

signal day_started(day: int)
signal speed_changed(speed: float)

## Pause, 1x, 3x.
const SPEEDS: Array[float] = [0.0, 1.0, 3.0]

var course: CourseData
var brain: GuestBrain
## The day being played, from 1 (0 before the first is built).
var day: int = 0
## The course's seed for its days (Main: the New course's land seed, else 0).
var base_seed: int = 0
## Simulated seconds a real second: 0 (paused), 1 or 3.
var speed: float = 1.0
## True in Play: real time moves the day.
var running: bool = false
var tuning: GuestTuning
## The reactions of the course's days, for the feed and the map tags (E3-S7).
var feed: ReactionFeed
## Null loads scenes/feed_tuning.tres.
var feed_tuning: FeedTuning

## The builder whose edits clear the feed's tallies (watch), and the holes as it last left them.
var _watched: CourseBuilder
var _holes_seen: Array[HoleData] = []
## The plays under way when Build edited their slot ({GuestHole: true}): their reactions are
## pushed uncounted. Emptied with each day.
var _stale: Dictionary = {}


func _init() -> void:
	# Before the views in the frame, so they draw the step this frame ran.
	process_priority = -1


func _ready() -> void:
	_ensure_feed()


func _ensure_feed() -> void:
	if tuning == null:
		tuning = GuestTuning.load_default()
	if feed_tuning == null:
		feed_tuning = FeedTuning.load_default()
	if feed == null:
		feed = ReactionFeed.new(tuning.rating_window, feed_tuning.max_entries)
		feed.slot_edited.connect(_on_slot_edited)


## The seed of day `d` of a course seeded `base`.
static func day_seed(base: int, d: int) -> int:
	return base * 1000 + d


## A new course: drops the old day; day 1 is built when the sim first runs.
func start(c: CourseData, p_base_seed: int = 0) -> void:
	_ensure_feed()
	course = c
	base_seed = p_base_seed
	brain = null
	day = 0
	_stale.clear()
	feed.clear()


## Clears the feed's tallies on the edits `builder` makes to the course (E3-S17): its holes'
## tees, cups and pars and the terrain on their lines (ReactionFeed.holes_edited, cells_edited).
## Main calls it with each course's builder; a builder watched before is let go.
func watch(builder: CourseBuilder) -> void:
	_ensure_feed()
	if _watched != null:
		_watched.holes_changed.disconnect(_on_holes_changed)
		_watched.tiles_changed.disconnect(_on_tiles_changed)
	_watched = builder
	_holes_seen = _copy_holes(builder.course)
	builder.holes_changed.connect(_on_holes_changed)
	builder.tiles_changed.connect(_on_tiles_changed)


func _on_holes_changed() -> void:
	var now: Array[HoleData] = _copy_holes(_watched.course)
	feed.holes_edited(_holes_seen, now)
	_holes_seen = now


func _on_tiles_changed(cells: Array[Vector2i]) -> void:
	feed.cells_edited(_watched.course, cells, _watched.validator)


## Build edited the hole in slot `slot`: every guest playing it now, its verdict not yet
## given, is judging a version of the hole that is gone, so its reaction counts for none.
func _on_slot_edited(slot: int) -> void:
	if brain == null:
		return
	for guest: Guest in brain.guests:
		if guest.hole != null and not guest.hole_recorded and guest.hole.slot == slot:
			_stale[guest.hole] = true


static func _copy_holes(c: CourseData) -> Array[HoleData]:
	var out: Array[HoleData] = []
	for h: HoleData in c.holes:
		out.append(h.copy())
	return out


func set_speed(s: float) -> void:
	if is_equal_approx(s, speed):
		return
	speed = s
	speed_changed.emit(speed)


func is_paused() -> bool:
	return speed <= 0.0


## The speed the day moves at now: 0 when paused or not running.
func effective_speed() -> float:
	return speed if running else 0.0


func _process(delta: float) -> void:
	if running:
		advance(delta)


## `delta` real seconds of Play: builds the day if needed, starts the next one at dusk, and
## runs the brain at `speed`. Returns the simulated seconds stepped.
func advance(delta: float) -> int:
	if course == null:
		return 0
	if brain == null:
		_new_day(1)
	elif brain.day_over:
		_new_day(day + 1)
	return brain.advance_real(delta, speed)


## The simulated time of the day now, seconds (with the share of the second gone by).
func clock_s() -> float:
	return 0.0 if brain == null else minf(brain.second + brain.step_fraction(), tuning.day_s)


func guests_on_course() -> int:
	return 0 if brain == null else brain.on_course().size()


func _new_day(d: int) -> void:
	_ensure_feed()
	day = d
	_stale.clear()
	brain = GuestBrain.new(course, day_seed(base_seed, d), tuning)
	brain.reacted.connect(_on_reacted.bind(brain))
	day_started.emit(day)


## A guest of `from_brain`'s day reacted: into the feed, at the second the brain is playing,
## with the slot of the hole it played (GuestHole.slot, stamped as it started the hole; else
## hole_slot), so a later renumber keeps it on that hole. A play its slot was edited under
## (_stale) is pushed uncounted.
func _on_reacted(guest: Guest, reaction: GuestReaction, from_brain: GuestBrain) -> void:
	var play: GuestHole = guest.hole if guest != null else null
	var slot := -1
	if play != null and play.slot >= 0:
		slot = play.slot
	else:
		slot = hole_slot(course, reaction.hole_number, play.hole if play != null else null)
	var counted := play == null or not _stale.has(play)
	if play != null:
		_stale.erase(play)
	feed.push(reaction, day, from_brain.second, slot, counted)


## The slot of `c.holes` holding hole `number`. With `played` (the guest's copy of the hole):
## the hole with its tee and cup, the one numbered `number` first (two holes may share a
## number, E3-S11), whatever its number now; else the first with the number, else -1.
static func hole_slot(c: CourseData, number: int, played: HoleData = null) -> int:
	if c == null:
		return -1
	var first := -1
	var same_ground := -1
	for i: int in c.holes.size():
		var h: HoleData = c.holes[i]
		var on_ground := played != null and h.tee == played.tee and h.cup == played.cup
		if h.number == number and (played == null or on_ground):
			return i
		if on_ground and same_ground < 0:
			same_ground = i
		if h.number == number and first < 0:
			first = i
	return same_ground if same_ground >= 0 else first
