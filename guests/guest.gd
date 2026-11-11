class_name Guest
extends RefCounted
## One guest of a day (E3-S4, docs/design.md Guests and reactions): who it is (skill,
## patience, taste, drawn by GuestSpawner from the day's seed) and what it is doing, which
## only GuestBrain changes, once per simulated second.
##
## State: WALKING (to its ball, the next tee or the cup), WAITING (standing: for the group
## ahead, a partner, its own ball, its plan, its turn), PLAYING (its stroke, `stroke_s`) and
## DONE (gone home: its round is over, or dusk came). `waiting_for` says what a WAITING guest
## waits for; only GROUP_AHEAD counts against pace (E3-S1, Pace; reading the green
## too until the E3-S8 review).

enum State { WALKING, WAITING, PLAYING, DONE }
enum Taste { PURIST, ADVENTURER, CASUAL }
enum Wait {
	NONE,
	## At the tee, or at its ball with a group ahead in reach of the stroke (counts against
	## pace).
	GROUP_AHEAD,
	## A partner is not at the tee yet, or still walking to its ball.
	PARTNERS,
	## A partner is away (farther from the cup), or striking.
	TURN,
	## Its own ball is still in the air or rolling.
	BALL,
	## Its turn, and its full-club plan is not finished (does not count against pace).
	PLANNING,
	## Its turn, and its putt solve is not finished (does not count against pace: the
	## engine's budget never fails pace by itself, E3-S8 review).
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
## E3-S38: where it stood when the step now running began (GuestBrain._update), so a guest
## that walks off a green in this second still holds the group behind for it.
var step_from: Vector2 = Vector2.ZERO
## The walk under way (null when standing).
var walk: GuestWalk
## The hole it is playing or about to play (null between holes).
var hole: GuestHole
## Simulated seconds left of the stroke being played (PLAYING).
var stroke_left: float = 0.0
## True from a strike until the guest has started walking to where that ball rested: the
## walk waits for the stroke's flight to end as drawn (E3-S20, GuestBrain.ball_shown_s).
var ball_moved: bool = false
## The simulated second of its latest strike (E3-S20: GuestView times the swing's impact and
## the flight's replay from it).
var strike_s: int = -1
## True once the hole under way has given its record (at hole-out or pick-up).
var hole_recorded: bool = false
## The last simulated second it walked (a guest walks at most once a second).
var last_walk_s: int = -1
## E3-S20: that second's leg runs at walk speed from `leg_start` to `leg_end`, shares of the
## second (0 to 1 for a whole leg; a walk's first leg after a stroke sets off as its ball comes
## to rest on screen, its last one ends when it gets there). `next_leg_start` is where the
## next leg sets off. GuestView draws the leg over them.
var leg_start: float = 0.0
var leg_end: float = 1.0
var next_leg_start: float = 0.0
## The finished holes, in the order played (a hole cut short by an edit or dusk has none).
var records: Array[HoleRecord] = []
## Pace on the hole under way: seconds waited that count, and the walk to its tee. E3-S22:
## of the counted wait, the seconds held for a group on another hole (GuestBrain.hold_for,
## CROSSING), and the other seconds held on the tee before its own tee shot (behind its own
## hole's queue); the rest was on the hole, behind the group ahead.
var wait_s: int = 0
var tee_wait_s: int = 0
var cross_wait_s: int = 0
var walk_yd: float = -1.0
## E9-S1: that walk's time, simulated seconds (-1 for none).
var walk_s: float = -1.0
## E9-S2: that walk's time were no cart path laid (GuestWalk.bare_s), its share of yards on
## cart path, and the hole whose green it left (0 from the clubhouse door).
var walk_bare_s: float = -1.0
var walk_path_share: float = 0.0
var walk_from_hole: int = 0
## E5-S11: `walk_yd` is the walk from the clubhouse door (the first hole of its round).
var walk_from_clubhouse: bool = false
## E5-S11: true once it has stood on the first tee of its round (GuestBrain.reached_first_tee).
var at_first_tee: bool = false
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
	## Seconds waited that count against pace: behind the group ahead (at the tee or on the hole).
	var wait_s: int = 0
	## E3-S22: of `wait_s`, the seconds held on the tee behind its own hole's queue, and those
	## held for a group on another hole (on the tee or the hole); the rest was on the hole,
	## behind the group ahead.
	var tee_wait_s: int = 0
	var cross_wait_s: int = 0
	## The walk from the previous hole's cup to this tee, yards; -1 on the first hole played.
	var walk_yd: float = -1.0
	## E9-S1 (D65): that walk's time, simulated seconds (-1 for none): what the Walk check
	## judges (E9-S2; pace until then).
	var walk_s: float = -1.0
	## E9-S2: the walk's time were no cart path laid (the straight line, its path tiles at the
	## base speed: GuestWalk.bare_s), the share of its yards on cart path, and the hole whose green
	## it left (0: from the clubhouse door).
	var walk_bare_s: float = -1.0
	var walk_path_share: float = 0.0
	var walk_from_hole: int = 0
	## E5-S11: `walk_yd` was the walk from the clubhouse door.
	var walk_from_clubhouse: bool = false
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
