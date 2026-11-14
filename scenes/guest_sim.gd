class_name GuestSim
extends Node
## Runs the guests' day in Build and Play (E3-S5, D53): owns the GuestBrain of the course on show and turns
## real time into its simulated seconds at the chosen speed (docs/design.md Economy and time:
## pause, 1x, 3x). The brain steps once per simulated second (GuestBrain.advance_real), never
## per frame; this node only says how much real time went by and how fast.
##
## The day runs only while `running`: Main sets it in both modes since D53 (E3-S62; E3-S5 held
## it in Build), so it is off only before Main has shown a course. The first day is built the first time it runs, so loading a course
## or a test that never plays pays nothing (GuestClubTable.warm).
##
## The day clock (E4-S3): a day is `day_s` simulated seconds, 9 real minutes at 1x and 3 at 3x.
## Day end: at dusk the day ends once, through `day_ended(day, brain)`, with the finished
## day's brain still `brain` while it runs: the one hook a day's end settles through (E4-S4's
## upkeep attaches here). Then the next morning starts at once (`day_started`), with the next
## day's seed. Skip to morning (`skip_to_morning`) runs the rest of the day over frames, as
## fast as `skip_frame_ms` and `skip_steps_per_frame` allow (GuestBrain.advance_skip), the
## same steps as at any speed, so the end-of-day state is the same; the speed is kept, so a
## skip from pause lands on the morning paused, and choosing a speed stops a skip where it is.
##
## The same seed gives the same day: day `d` of a course is GuestBrain's day of
## day_seed(base_seed, d), whatever the speed, the frame rate or what the camera looks at.
##
## The feed (E3-S7): every reaction of every day goes into `feed` (ReactionFeed) with its day
## and second, for the HUD feed and the map tags; a new course empties it. Edits in Build
## (E3-S17): watch(builder) hands the feed every hole and tile change the builder makes, so a
## hole's tally is cleared when its tee, cup, par or the terrain on its line changes, and a hole
## undone away takes its tally and links with it. A guest playing the hole when it is edited
## judges the old version: its reaction comes in uncounted (E3-S17 review, _on_slot_edited),
## unless its group had not struck there yet: it replans on the new version and counts (E3-S49).
##
## The rating (E4-S5, D58): rating() is the feed's mean points over its full window
## (ReactionFeed.rating, EconomyTuning.rating_points); it moves with every reaction
## (rating_changed). E4-S13 (D59): stars() are the stars shown, set once a day, at dusk, from the
## mean then (to the half star, EconomyTuning.stars_of; stars_changed), as SimGolf's daily
## rating; a new course shows 3 until its first dusk. Each morning draws arrivals_today()
## guests, 8 + 4 a star at most 24 (EconomyTuning.arrivals) at the stars shown, replacing E3's
## flat `arrivals_per_day`. The same seed and the same feed give the same day, so a skip, a run
## and a load's replay agree.
##
## The fee (E4-S6, D56, D58): `fee` is the player's green fee a round, the fee slider's setting,
## from 0 to fee_ceiling() ($25 a star at the stars shown, whole dollars down); set_fee holds it
## there. A new course starts it at `start_fee`. The ceiling moves only at dusk (D59): when it
## falls under the fee, the fee comes down to it then, before the next morning draws (and stays
## there when the stars recover). The morning's arrivals take the fee's share of the ceiling
## through D58's curve (EconomyTuning.arrivals). Main.green_fee() reads it when a guest pays at
## the first tee.
##
## The replay (E4-S11): a load replays the saved day from its morning, so it must be the day the
## player saved. resume_at takes the arrivals that morning drew (morning_arrivals), not those
## the fee at the load would draw; restore_stars takes the stars shown that morning (Main: the
## last dusk's rating in its history). Since the ceiling holds all day, the fee the player left
## is under the loaded ceiling and loads as set_fee holds it.

signal day_started(day: int)
## E4-S3: the day's end, before the next morning: `finished` is the day's brain (day_over).
signal day_ended(day: int, finished: GuestBrain)
## E4-S4: a guest of the day under way arrived at the first open hole's tee (since E5-S11 after
## its walk from the clubhouse: GuestBrain's reached_first_tee, forwarded): where it pays its
## green fee (Main). Connected before day_started
## fires, so it runs ahead of any handler a day_started listener connects to the brain itself.
signal guest_arrived(guest: Guest)
signal speed_changed(speed: float)
## E4-S3: a skip to morning started or stopped.
signal skip_changed(skipping: bool)
## E4-S5: the course rating may have moved (the feed's window changed).
signal rating_changed(rating: float)
## E4-S13 (D59): the stars shown changed (at dusk, a new course or a load).
signal stars_changed(stars: float)
## E4-S6: the fee changed (the slider, a new course, a load, or a falling ceiling).
signal fee_changed(fee: int)

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
## True once Main runs it (Build and Play, D53): real time moves the day.
var running: bool = false
## E4-S3: skipping to the morning (skip_to_morning): frames run the day as fast as they can.
var skipping: bool = false
var tuning: GuestTuning
## The reactions of the course's days, for the feed and the map tags (E3-S7).
var feed: ReactionFeed
## Null loads scenes/feed_tuning.tres.
var feed_tuning: FeedTuning
## E4-S5: the economy's numbers (rating points, arrivals). Null loads data/economy.json.
var economy: EconomyTuning
## E4-S5: the guests the day under way drew at its morning (arrivals_today then).
var day_arrivals: int = 0
## E4-S6: the green fee a round, dollars, 0 to fee_ceiling() (set_fee). -1 until the first start.
var fee: int = -1
## E4-S11: the arrivals a loaded day's morning drew (resume_at), -1 to draw them at the morning.
var _resume_arrivals: int = -1
## E8-S2: the late starts of a loaded day (resume_at), for its first brain.
var _resume_late_starts: Array[Vector3i] = []
## E18-S3 (D72): whether a loaded day's morning was an eighteen-hole day (resume_at; -1: read the
## course when the day is built).
var _resume_eighteen: int = -1
## E4-S13: the stars shown (stars()), set at dusk (D59). 3 until a course's first dusk.
var _stars: float = 3.0

## The builder whose edits clear the feed's tallies (watch), and the holes as it last left them.
var _watched: CourseBuilder
## The day built when the sim first runs (start: 1; resume_at: a loaded game's day, E4-S7).
var _first_day: int = 1
var _holes_seen: Array[HoleData] = []
## The plays under way when Build edited their slot ({GuestHole: true}): their reactions are
## pushed uncounted. Emptied with each day.
var _stale: Dictionary = {}
## E12-S1 (D68): the plays whose walk to the tee was judged before a cart path edit it can reach
## ({GuestHole: true}, GuestBrain.walked_to): a walk complaint of theirs is pushed uncounted.
## Emptied with each day.
var _walk_stale: Dictionary = {}
## E12-S1: the watched course's cart path tiles as the feed last read them (GuestWalk.path_grid)
## and that course's cart path revision then: a flush compares them to find the tiles that
## turned to or from cart path (ReactionFeed.walks_edited).
var _path_grid := PackedByteArray()
var _path_revision: int = -1
## E3-S61: the tiles the watched builder wrote since the feed last read them ({tile: true}),
## and each slot's line of play as it stood before them (CourseBuilder.slot_lines). The feed
## reads them once a frame (_flush_cells, deferred) and at every check, not once a paint: a
## drag paints a tile at a time, and each read measures every hole's line of play, a dogleg's
## a search through its fairway (52 ms drag frames on PlaytestNine).
var _cells: Dictionary = {}
var _cells_lines: Array[PackedVector2Array] = []


func _init() -> void:
	# Before the views in the frame, so they draw the step this frame ran.
	process_priority = -1


func _ready() -> void:
	_ensure_feed()


## E7-S4: while a skip runs, the next batch of the day's Ball work runs on the pool's threads
## as the frame is drawn (GuestBrain.serve_ahead), when no script runs, and is counted once the
## drawing is done (settle), so the threads are not idle while the frame waits for the screen.
func _enter_tree() -> void:
	RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)
	RenderingServer.frame_post_draw.connect(_settle)


func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(_on_frame_pre_draw)
	RenderingServer.frame_post_draw.disconnect(_settle)
	_settle()


func _on_frame_pre_draw() -> void:
	if skipping and brain != null and is_processing():
		brain.serve_ahead()


func _settle() -> void:
	if brain != null:
		brain.settle()


func _ensure_feed() -> void:
	if tuning == null:
		tuning = GuestTuning.load_default()
	if feed_tuning == null:
		feed_tuning = FeedTuning.load_default()
	if economy == null:
		economy = EconomyTuning.load_default()
	if feed == null:
		feed = ReactionFeed.new(tuning.rating_window, feed_tuning.max_entries)
		feed.slot_edited.connect(_on_slot_edited)
		feed.walk_edited.connect(_on_walk_edited)
		feed.changed.connect(_on_feed_changed)


## E4-S5: the course rating now, 1 to 5 (ReactionFeed.rating over `rating_window`, D58).
func rating() -> float:
	_ensure_feed()
	return feed.rating(economy.rating_points)


## E4-S5, E4-S13: the stars shown, to the half star: the mean at the last dusk (D59), or 3 on a
## new course before its first.
func stars() -> float:
	return _stars


## E4-S13: shows the stars of rating `r` (EconomyTuning.stars_of) and holds the fee under the
## ceiling they make. At dusk (_end_day), a new course (start) and a load (restore_stars).
func _show_stars(r: float) -> void:
	var st := EconomyTuning.stars_of(r)
	if st != _stars:
		_stars = st
		stars_changed.emit(_stars)
	if fee > fee_ceiling():
		set_fee(fee)


## E4-S13: a loaded game's stars shown: those of rating `r`, its last dusk's (Main.rating_history).
func restore_stars(r: float) -> void:
	_ensure_feed()
	_show_stars(r)


## E4-S5, E4-S6: the guests a day starting now draws: EconomyTuning.arrivals at stars() and the
## fee's share of the ceiling.
func arrivals_today() -> int:
	var ceiling := fee_ceiling()
	return economy.arrivals(stars(), 0.0 if ceiling <= 0 else float(maxi(fee, 0)) / ceiling)


## E4-S6: the most the fee can be now: fee_ceiling_per_star x the stars shown, whole dollars down.
func fee_ceiling() -> int:
	_ensure_feed()
	return floori(economy.fee_ceiling(stars()))


## E4-S6: sets the fee to `f` dollars, held from 0 to fee_ceiling(). Emits fee_changed when it
## moved.
func set_fee(f: int) -> void:
	var held := clampi(f, 0, fee_ceiling())
	if held == fee:
		return
	fee = held
	fee_changed.emit(fee)


## E4-S11: the arrivals of the day a save made now resumes at: those its morning drew, or a
## loaded day's still to come (-1 when its morning will draw them). Read after morning_day().
func morning_arrivals() -> int:
	return _resume_arrivals if brain == null else day_arrivals


## E18-S3 (D72): whether the day a save made now resumes at is an eighteen-hole day
## (GuestBrain.eighteen_day: all eighteen holes were open that morning), so its replay keeps the
## day's length and rounds whatever was edited since; -1 before a day is built (its morning reads
## the course). Read after morning_day().
func morning_eighteen() -> int:
	if brain == null:
		return _resume_eighteen
	return 1 if brain.eighteen_day else 0


## E18-S3 (D72): the green fee of a round of `holes` holes at the fee now: the fee slider's
## setting for nine (every round before E18-S3), `eighteen_fee_multiple` times it, whole dollars
## down, for eighteen (EconomyTuning.round_fee).
func round_fee(holes: int) -> int:
	_ensure_feed()
	return economy.round_fee(maxi(fee, 0), holes)


## E18-S3 (D72): the day's length, simulated seconds: the day under way's (GuestBrain.day_s),
## else `day_s`.
func day_length() -> float:
	_ensure_feed()
	return tuning.day_s if brain == null else brain.day_s


## E8-S2 (D64): the late starts of the day a save made now resumes at (GuestBrain.late_starts:
## the groups a closed course sent home and the first hole's opening sent out again), so its
## replay sends them at the same seconds. Read after morning_day().
func morning_late_starts() -> Array[Vector3i]:
	if brain == null:
		return _resume_late_starts.duplicate()
	return brain.late_starts.duplicate()


## The mean moves live; the stars shown, the ceiling and the fee wait for dusk (D59).
func _on_feed_changed() -> void:
	rating_changed.emit(rating())


## The seed of day `d` of a course seeded `base`.
static func day_seed(base: int, d: int) -> int:
	return base * 1000 + d


## A new course: drops the old day; day 1 is built when the sim first runs.
func start(c: CourseData, p_base_seed: int = 0) -> void:
	_ensure_feed()
	course = c
	base_seed = p_base_seed
	_settle()
	brain = null
	day = 0
	_set_skipping(false)
	_first_day = 1
	_stale.clear()
	_walk_stale.clear()
	feed.clear()
	_resume_arrivals = -1
	_resume_late_starts.clear()
	_resume_eighteen = -1
	_show_stars(rating())
	set_fee(economy.start_fee)


## E4-S7: a loaded game resumes at the morning of day `d` (from 1): the next day built is `d`,
## from its own seed, as if the days before it had run. Guests out at the save are not kept.
## E4-S11: `arrivals` are the guests day `d`'s morning drew (morning_arrivals; -1: draw them).
## E8-S2: `late_starts` are that day's late starts (morning_late_starts), replayed as made.
## E18-S3: `eighteen` is whether it was an eighteen-hole day (morning_eighteen; -1: read the course).
func resume_at(d: int, arrivals: int = -1, late_starts: Array[Vector3i] = [],
		eighteen: int = -1) -> void:
	_settle()
	brain = null
	_set_skipping(false)
	_first_day = maxi(d, 1)
	day = _first_day
	_stale.clear()
	_walk_stale.clear()
	_resume_arrivals = arrivals
	_resume_late_starts = late_starts.duplicate()
	_resume_eighteen = eighteen


## E4-S7: the day a save made now resumes at the morning of: the day under way, or 1 (or a
## loaded game's day) before the first is built. A day whose dusk has come but has not ended yet
## (run_day) ends first (_end_day, so its day_ended accounting runs once), and the save is the
## next morning's.
func morning_day() -> int:
	if brain == null:
		return maxi(day, _first_day)
	if brain.day_over:
		_end_day()
	return day


## Clears the feed's tallies on the edits `builder` makes to the course (E3-S17): its holes'
## tees, cups and pars and the terrain on their lines (ReactionFeed.holes_edited, cells_edited).
## Main calls it with each course's builder; a builder watched before is let go.
func watch(builder: CourseBuilder) -> void:
	_ensure_feed()
	if _watched != null:
		_flush_cells()
		_watched.holes_changed.disconnect(_on_holes_changed)
		_watched.tiles_changed.disconnect(_on_tiles_changed)
		_watched.checked.disconnect(_on_checked)
	_watched = builder
	_holes_seen = _copy_holes(builder.course)
	_read_paths()
	builder.holes_changed.connect(_on_holes_changed)
	builder.tiles_changed.connect(_on_tiles_changed)
	builder.checked.connect(_on_checked)


func _on_holes_changed() -> void:
	var now: Array[HoleData] = _copy_holes(_watched.course)
	feed.holes_edited(_holes_seen, now)
	_holes_seen = now


func _on_tiles_changed(cells: Array[Vector2i]) -> void:
	if _cells.is_empty():
		_cells_lines = _watched.slot_lines()
		_flush_cells.call_deferred()
	for c: Vector2i in cells:
		_cells[c] = true


## Every edit and undo ends in a check (a drag at its release): the feed has its tiles by then.
func _on_checked(_issues: Dictionary) -> void:
	_flush_cells()


## Hands the feed the tiles written since it last read them (_cells), if any.
func _flush_cells() -> void:
	if _cells.is_empty() or _watched == null:
		return
	var cells: Array[Vector2i] = []
	cells.assign(_cells.keys())
	_cells.clear()
	feed.cells_edited(_watched.course, cells, _watched.validator, _cells_lines, _watched.lines_now())
	_flush_paths(cells)


## E12-S1 (D68): of `cells`, the tiles that turned to or from cart path since the last read
## (the course's cart path revision moved, and the path grid differs there) clear the walk
## complaints of the walks they can reach (ReactionFeed.walks_edited).
func _flush_paths(cells: Array[Vector2i]) -> void:
	var c: CourseData = _watched.course
	if c.surface_revision(Surface.Type.CART_PATH) == _path_revision:
		return
	var before := _path_grid
	_read_paths()
	var w := c.width + 2
	var changed: Array[Vector2i] = []
	for cell: Vector2i in cells:
		var i := (cell.y + 1) * w + cell.x + 1
		if i < 0 or i >= _path_grid.size():
			continue
		if before.size() != _path_grid.size() or before[i] != _path_grid[i]:
			changed.append(cell)
	feed.walks_edited(c, changed, tuning, 5.0, _path_grid)


## The watched course's cart path tiles and revision as they are now (_path_grid).
func _read_paths() -> void:
	_path_grid = GuestWalk.path_grid(_watched.course)
	_path_revision = _watched.course.surface_revision(Surface.Type.CART_PATH)


## Build edited the hole in slot `slot`: a guest whose group has struck there, its verdict not
## yet given, is judging a version of the hole that is gone, so its reaction counts for none.
## A group that has not struck yet replans on the new version and counts (E3-S49,
## GuestBrain.slot_edited).
func _on_slot_edited(slot: int) -> void:
	if brain == null:
		return
	for play: GuestHole in brain.slot_edited(slot):
		_stale[play] = true


## E12-S1 (D68): cart path the walk to slot `slot`'s tee can reach changed: a guest that walked
## there before the edit, its verdict not yet given, gives its walk complaint uncounted.
func _on_walk_edited(slot: int) -> void:
	if brain == null:
		return
	for play: GuestHole in brain.walked_to(slot):
		_walk_stale[play] = true


static func _copy_holes(c: CourseData) -> Array[HoleData]:
	var out: Array[HoleData] = []
	for h: HoleData in c.holes:
		out.append(h.copy())
	return out


## Chooses a speed; a skip under way stops where it is, the day running on at `s` (E4-S3).
func set_speed(s: float) -> void:
	_set_skipping(false)
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
	if skipping:
		skip_frame()
	elif running:
		advance(delta)


## `delta` real seconds of Play: builds the day if needed, runs the brain at `speed`, and at
## dusk ends the day and starts the next morning. Returns the simulated seconds stepped.
func advance(delta: float) -> int:
	if not _ready_day():
		return 0
	var stepped := brain.advance_real(delta, speed)
	if brain.day_over:
		_end_day()
	return stepped


## Skip to morning (E4-S3): from the next frame the rest of the day runs as fast as a frame
## allows (skip_frame), whatever the speed, until the next morning starts.
func skip_to_morning() -> void:
	if skipping or not _ready_day():
		return
	_set_skipping(true)


## One frame of a skip: whole seconds until `skip_frame_ms` of real time has gone, at most
## `skip_steps_per_frame` (E7-S4); at dusk the day ends and the skip stops on the next morning.
## Returns the steps.
func skip_frame() -> int:
	if not skipping or not _ready_day():
		return 0
	var stepped := brain.advance_skip(tuning.skip_steps_per_frame,
			roundi(tuning.skip_frame_ms * 1000.0))
	if brain.day_over:
		_end_day()
		_set_skipping(false)
	return stepped


func _set_skipping(on: bool) -> void:
	_settle()
	if skipping == on:
		return
	skipping = on
	skip_changed.emit(on)


## Builds day 1 if none is yet, and ends a day its brain finished on its own (run_day). False
## with no course.
func _ready_day() -> bool:
	if course == null:
		return false
	if brain == null:
		_new_day(_first_day)
	elif brain.day_over:
		_end_day()
	return true


## The day's end (E4-S3): the stars shown take the mean (E4-S13, D59; a ceiling under the fee
## lowers it), then `day_ended` with the finished brain, then the next morning, which draws by
## them. The one place a day ends, so whatever a day's end settles (E4-S4's upkeep) runs once a
## day.
func _end_day() -> void:
	_show_stars(rating())
	day_ended.emit(day, brain)
	_new_day(day + 1)


## The simulated time of the day now, seconds (with the share of the second gone by).
func clock_s() -> float:
	return 0.0 if brain == null else minf(brain.second + brain.step_fraction(), brain.day_s)


func guests_on_course() -> int:
	return 0 if brain == null else brain.on_course().size()


func _new_day(d: int) -> void:
	_ensure_feed()
	day = d
	_stale.clear()
	_walk_stale.clear()
	var resumed := _resume_arrivals >= 0 and d == _first_day
	day_arrivals = _resume_arrivals if resumed else arrivals_today()
	var late: Array[Vector3i] = []
	var eighteen := -1
	if d == _first_day:
		late.assign(_resume_late_starts)
		eighteen = _resume_eighteen
	_resume_arrivals = -1
	_resume_late_starts.clear()
	_resume_eighteen = -1
	brain = GuestBrain.new(course, day_seed(base_seed, d), tuning, null, [], null, day_arrivals, late,
			eighteen)
	brain.reacted.connect(_on_reacted.bind(brain))
	brain.reached_first_tee.connect(func(g: Guest) -> void: guest_arrived.emit(g))
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
		# E12-S1: a walk judged before a cart path edit it could reach is not the walk now.
		if _walk_stale.has(play) and not reaction.passed[GuestReaction.Check.WALK]:
			counted = false
		_walk_stale.erase(play)
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
