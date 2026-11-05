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


func _init() -> void:
	# Before the views in the frame, so they draw the step this frame ran.
	process_priority = -1


func _ready() -> void:
	if tuning == null:
		tuning = GuestTuning.load_default()


## The seed of day `d` of a course seeded `base`.
static func day_seed(base: int, d: int) -> int:
	return base * 1000 + d


## A new course: drops the old day; day 1 is built when the sim first runs.
func start(c: CourseData, p_base_seed: int = 0) -> void:
	course = c
	base_seed = p_base_seed
	brain = null
	day = 0


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
	if tuning == null:
		tuning = GuestTuning.load_default()
	day = d
	brain = GuestBrain.new(course, day_seed(base_seed, d), tuning)
	day_started.emit(day)
