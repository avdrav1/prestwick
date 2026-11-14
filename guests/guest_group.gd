class_name GuestGroup
extends RefCounted
## A group of 1 to 4 guests who arrive together and play every hole together (E3-S4): the
## group tees off a hole only when all of it stands on the tee and no group ahead is on that
## hole, and leaves the hole when every one of it has holed out or picked up.

enum Phase {
	## Not arrived yet (before `arrive_s`).
	PENDING,
	## Walking to, or standing on, the tee of `hole_number`, in its queue.
	TO_TEE,
	## Playing `hole_number`.
	ON_HOLE,
	## E5-S11: done with its last hole, walking back to the clubhouse door to leave.
	TO_CLUBHOUSE,
	## Gone home.
	DONE,
	## E18-S3 (D72): an eighteen-hole group at the turn: done with the front nine, walking from
	## its last green to the clubhouse door and stopping there (`turn_stop_s`) before it walks
	## out to `turn_to`'s tee.
	TURN,
}

## Arrival order over the day, from 0.
var index: int = 0
## The simulated second of the day it comes out of the clubhouse door (E5-S11; before, it
## appeared on the first open hole's tee).
var arrive_s: float = 0.0
var guests: Array[Guest] = []
var phase: Phase = Phase.PENDING
## The hole it is heading for or playing (0 before it arrives).
var hole_number: int = 0
## The cup of the last hole it finished, or the clubhouse door before its first hole (E5-S11),
## yards (pace's walk from the previous cup).
var prev_cup: Vector2 = Vector2.ZERO
var has_prev_cup: bool = false
## E5-S11: true from its arrival until it tees off its first hole: `prev_cup` is then the
## clubhouse door, and the first hole's pace walk is the walk from the clubhouse.
var from_clubhouse: bool = false
## The second it teed off `hole_number`.
var start_s: int = 0
## E3-S38: the hole it last left by holing out (0: none yet). Its guests still standing on
## that hole's green hold the group behind (GuestBrain.hold_for), though it left the queue.
var left_hole: int = 0
## The second it left `left_hole`.
var left_s: int = -1
## True once anyone in the group has struck a ball on `hole_number`.
var struck: bool = false
## Seconds in a row its next stroke has been held by groups on other holes alone (E3-S22,
## GuestBrain.hold_for): at `cross_hold_max_s` it plays on.
var cross_held_s: int = 0
## E8-S2 (D64): it arrived to no open hole (or no clubhouse) and went home (phase DONE, counted in
## GuestBrain.turned_away). A late start sends it out again when the first hole opens, unless
## `cut`: a late start found no time left for it before dusk, and it does not come today.
var turned_away: bool = false
var cut: bool = false
## E18-S3 (D72): drawn with the day (GuestSpawner, the share `eighteen_share`): it plays eighteen
## when it arrives to a course with all eighteen holes open on an eighteen-hole day.
var wants_eighteen: bool = false
## The round it chose on arriving: 9 or 18 holes (0 before it arrives), over the open holes
## numbered `round_from` to `round_to` (the front nine 1 to 9, the back nine 10 to 18, or both).
var round_holes: int = 0
var round_from: int = 0
var round_to: int = 0
## At the turn (Phase.TURN): the hole it walks out to from the clubhouse, and the seconds it has
## stopped at the door so far.
var turn_to: int = 0
var turn_stopped_s: int = 0


func size() -> int:
	return guests.size()
