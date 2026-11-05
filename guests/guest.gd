class_name Guest
extends RefCounted
## One guest of a day (E3-S4, docs/design.md Guests and reactions): who it is (skill,
## patience, taste, drawn by GuestSpawner from the day's seed) and what it is doing, which
## only GuestBrain changes, once per simulated second.
##
## State: WALKING (to its ball, the next tee or the cup), WAITING (standing: for the group
## ahead, a partner, its own ball, its plan, its turn), PLAYING (its stroke, `stroke_s`) and
## DONE (gone home: its round is over, or dusk came). `waiting_for` says what a WAITING guest
## waits for; only GROUP_AHEAD and READING_GREEN count against pace (E3-S1, Pace).

enum State { WALKING, WAITING, PLAYING, DONE }
enum Taste { PURIST, ADVENTURER, CASUAL }
enum Wait {
	NONE,
	## At the tee, behind another group on the hole (counts against pace).
	GROUP_AHEAD,
	## A partner is not at the tee yet, or still walking to its ball.
	PARTNERS,
	## A partner is away (farther from the cup), or striking.
	TURN,
	## Its own ball is still in the air or rolling.
	BALL,
	## Its turn, and its full-club plan is not finished (does not count against pace).
	PLANNING,
	## Its turn, and its putt solve is not finished (counts against pace).
	READING_GREEN,
	## Holed out or picked up; the group is still playing the hole.
	HOLED_OUT,
}

## Taste names as in data/guests.json `taste_weights`, in Taste order.
const TASTE_NAMES: PackedStringArray = ["purist", "adventurer", "casual"]

## Arrival order over the day, from 0: the order the sim serves Ball work in.
var id: int = 0
## Its group's index in the day (GuestBrain.groups), from 0. An index, not the group, so
## the group holding its guests is no reference cycle.
var group_id: int = 0
## Place in its group, from 0.
var place: int = 0
var skill: int = 1
var patience: int = 1
var taste: Taste = Taste.PURIST
## This guest's seed; each hole's GuestHole gets GuestHole.hole_seed(guest_seed, number).
var guest_seed: int = 0

var state: State = State.WAITING
var waiting_for: Wait = Wait.NONE
## Where the guest stands, yards (HeightField coordinates).
var position: Vector2 = Vector2.ZERO
## The walk under way (null when standing).
var walk: GuestWalk
## The hole it is playing or about to play (null between holes).
var hole: GuestHole
## Simulated seconds left of the stroke being played (PLAYING).
var stroke_left: float = 0.0
## True from a strike until the guest has started walking to where that ball rested.
var ball_moved: bool = false
## True once the hole under way has given its record (at hole-out or pick-up).
var hole_recorded: bool = false
## The last simulated second it walked (a guest walks at most once a second).
var last_walk_s: int = -1
## The finished holes, in the order played (a hole cut short by an edit or dusk has none).
var records: Array[HoleRecord] = []
## Pace on the hole under way: seconds waited that count, and the walk to its tee.
var wait_s: int = 0
var walk_yd: float = -1.0
## Ball ticks spent this simulated second (GuestBrain's budget), and in all.
var second_ticks: int = 0
var ticks: int = 0
## Second it arrived and left (-1 while on the course).
var arrived_s: int = 0
var left_s: int = -1
var left_at_dusk: bool = false


## One hole a guest finished (holed or picked up, D12): what E3-S6's checks read, and the
## reaction they gave.
class HoleRecord:
	var number: int = 0
	var par: int = 0
	## HoleScore total (strokes and penalties; double par on a pick-up).
	var score: int = 0
	var holed: bool = false
	var picked_up: bool = false
	## Seconds waited that count against pace: behind the group ahead, and reading the green.
	var wait_s: int = 0
	## The walk from the previous hole's cup to this tee, yards; -1 on the first hole played.
	var walk_yd: float = -1.0
	## Simulated seconds of the day it teed off and holed out.
	var start_s: int = 0
	var end_s: int = 0
	## The play itself: strokes, clubs, rests.
	var play: GuestHole
	## The guest's reaction to the hole (E3-S6, D39): the four checks and the verdict.
	var reaction: GuestReaction


func taste_name() -> String:
	return TASTE_NAMES[taste]


func is_done() -> bool:
	return state == State.DONE


func is_walking() -> bool:
	return state == State.WALKING
