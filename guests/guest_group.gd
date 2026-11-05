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
	## Gone home.
	DONE,
}

## Arrival order over the day, from 0.
var index: int = 0
## The simulated second of the day it arrives at the first open hole's tee.
var arrive_s: float = 0.0
var guests: Array[Guest] = []
var phase: Phase = Phase.PENDING
## The hole it is heading for or playing (0 before it arrives).
var hole_number: int = 0
## The cup of the last hole it finished, yards (pace's walk from the previous cup).
var prev_cup: Vector2 = Vector2.ZERO
var has_prev_cup: bool = false
## The second it teed off `hole_number`.
var start_s: int = 0
## True once anyone in the group has struck a ball on `hole_number`.
var struck: bool = false
## Seconds in a row its next stroke has been held by groups on other holes alone (E3-S22,
## GuestBrain.hold_for): at `cross_hold_max_s` it plays on.
var cross_held_s: int = 0


func size() -> int:
	return guests.size()
