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


func size() -> int:
	return guests.size()
