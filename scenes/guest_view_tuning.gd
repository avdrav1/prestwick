class_name GuestViewTuning
extends Resource
## Designer-tuned numbers for drawing guests (E3-S5, scenes/guest_view.gd). Loaded from
## res://scenes/guest_view_tuning.tres. How fast flights are drawn is `flight_draw_speed` in
## data/guests.json (D38), not here.

const PATH: String = "res://scenes/guest_view_tuning.tres"

## Idle frames a real second (art/specs/golfer.md: 2 frames, breathing).
@export var idle_fps: float = 2.0
## Walk frames a real second at 1x, times the sim speed (4-frame stride).
@export var walk_fps: float = 8.0
## Guests of one group stand this far apart, yards, so a group on a tee or a green does not
## draw as one figure: round the spot, none on it (GuestView.place_offset, E3-S38).
@export var group_spread_yd: float = 1.5
## After a stroke the group spread eases back in over this many simulated seconds (the
## swinging guest stands over its own ball, with no spread).
@export var spread_ease_s: float = 0.5
## E3-S38: while a groupmate swings beside them, the others step this far back up the screen,
## yards, in step with the striker's spread closing (GuestView.strike_room), so no standing
## partner is drawn over the striker on the tee.
@export var strike_room_yd: float = 1.5
## E3-S38: a groupmate walking past a striker sidesteps off its walk line so it passes at least
## this far from it, yards (GuestView.pass_room), in step with the striker's spread closing.
@export var pass_room_yd: float = 0.75
## The figure is never drawn under this share of its native 24 px on screen: at 0.5x zoom
## 1.0 draws it at twice its canvas size (art/specs/golfer.md: reads at 0.5x).
@export var figure_min_screen_scale: float = 1.0
## A guest's ball, as a share of the player's ball (ShotView's radius and minimum on screen),
## so the player's own ball is always the biggest ball on the course.
@export var ball_scale: float = 0.7
## A stroke's flight is drawn when its start is within this many screen px of the view
## (on screen); farther off, the ball just appears where it rests.
@export var on_screen_margin_px: float = 32.0


static func load_default() -> GuestViewTuning:
	return load(PATH) as GuestViewTuning
