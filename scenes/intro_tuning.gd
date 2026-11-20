class_name IntroTuning
extends Resource
## Designer-tuned numbers for the opening flyover (E21-S1, D77; scenes/opening_flyover.gd):
## the course and the drive, the camera path and every beat's timing. Loaded from
## res://scenes/intro_tuning.tres. Times are seconds of the intro's own clock, which starts at
## 0 as the screen begins to fade in from black.

const PATH: String = "res://scenes/intro_tuning.tres"

## Where the camera path's keys look, by name: the hole's tee, turn and cup, the clubhouse door,
## the hole's middle (the mean of tee, turn and cup), where the guest's walk starts ("from":
## the clubhouse door, or the cup of walk_from_hole), and the start of the walk (between "from"
## and the tee, so both show).
const ANCHORS: PackedStringArray = ["tee", "turn", "cup", "door", "hole", "from", "walk"]

@export_group("Course and drive")
## The famous course the intro plays on (FamousCourses id), loaded into a CourseData of its own.
@export var course_id: String = "dogleg_hollow_championship"
## The hole whose tee the guest walks to and drives from.
@export var hole_number: int = 18
## Where the guest walks from: the cup of this hole (walking off its green to the tee), or the
## clubhouse door when 0 or no such hole.
@export var walk_from_hole: int = 17
## The drive: club (ClubSet id), shot shape (ShotShapes id), power (1.0 = 100%) and aim, in
## degrees from the line from the tee to the hole's turn (GuestHole.turn_of), + to the right.
@export var club_id: String = "driver"
@export var shape_id: String = "slice"
@export var power: float = 0.95
@export var aim_offset_deg: float = -4.0
## The Ball's seed (ShotView.fire_launch), so the drive is the same every time.
@export var rng_seed: int = 7
## The guest's shirt (GolferArt.shirt_material).
@export var shirt: int = 2

@export_group("Dawn")
## The screen fades in from black over this long.
@export var fade_in_s: float = 1.2
## The light over the course: each colour multiplies the world at its time in dawn_times,
## eased between (smoothstep), white (day) after the last.
@export var dawn_colors: PackedColorArray = PackedColorArray([
	Color(0.42, 0.34, 0.5), Color(1.0, 0.72, 0.5), Color(1.0, 1.0, 1.0)])
@export var dawn_times: PackedFloat32Array = PackedFloat32Array([0.0, 3.5, 9.5])
## When the dawn beat hands over to the glide (the camera path runs through both).
@export var dawn_s: float = 3.5

@export_group("Camera path")
## The path's keys, each at a time, looking at an anchor (ANCHORS) plus an offset in yards,
## at a zoom. The camera passes through each key on a smooth curve (cubic Hermite, Catmull-Rom
## tangents by time), still at the first and last; the zoom eases the same way in log scale.
## The last key's time is when the guest steps out of the clubhouse. Dogleg Hollow
## (Championship)'s 1st runs to the map's north edge, so the path keeps the zoom close where it
## looks north (past the edge is the empty backdrop): a tile y of at least about 21 / zoom at the
## view's centre shows none of it.
@export var path_times: PackedFloat32Array = PackedFloat32Array([0.0, 3.5, 6.0, 8.5])
@export var path_anchors: PackedStringArray = PackedStringArray(["hole", "cup", "turn", "walk"])
@export var path_offsets: PackedVector2Array = PackedVector2Array([
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
@export var path_zooms: PackedFloat32Array = PackedFloat32Array([0.3, 0.8, 0.8, 0.7])

@export_group("Walk and swing")
## The guest's walk from where it starts (walk_from_hole) to the tee (GuestWalk.route) is
## played over this many seconds.
@export var walk_s: float = 4.0
## The camera eases toward what it follows (the ball) with this time constant (about 63% of the
## way in this time).
@export var follow_time_s: float = 0.4
## The zoom the camera eases to while the guest walks.
@export var walk_zoom: float = 0.75
## How quickly a following zoom eases to its goal, a time constant in seconds.
@export var zoom_time_s: float = 0.9
## The swing's six frames take this long; the ball leaves at GolferArt.swing_impact_frame.
@export var swing_s: float = 1.2

@export_group("Aim")
## Standing over the ball before the swing, while the camera frames the corner: the tee, the
## start line out to the trees and the fairway past the turn (the whole predicted drive, inside
## the view less aim_margin_px each side, never nearer than aim_zoom_max).
@export var address_s: float = 2.4
## The camera eases (smoothstep) from the tee to that frame over this long from the address.
@export var aim_ease_s: float = 1.6
@export var aim_margin_px: float = 60.0
@export var aim_zoom_max: float = 0.8
@export var aim_past_turn: float = 0.5
## The start line (the launch heading out to the carry) draws out from the tee over
## guide_grow_s, from guide_delay_s into the address.
@export var guide_delay_s: float = 0.5
@export var guide_grow_s: float = 0.7

@export_group("Flight")
## The Ball is stepped at 60 Hz of the intro's clock times this (1.0 is as in play), times the
## slow motion's rate.
@export var ball_speed: float = 1.0
## Slow motion through the bend: the presentation clock of the ball eases down to slow_rate
## over slow_ramp_s, holds it for slow_hold_s and eases back over slow_ramp_s (seconds of ball
## time), centred slow_center_s after the flight's apex. Only the playback slows: the Ball's
## ticks and its path are the same.
@export var slow_rate: float = 0.35
@export var slow_center_s: float = 0.4
@export var slow_hold_s: float = 0.7
@export var slow_ramp_s: float = 0.5
## From the touchdown the playback eases up to roll_rate over roll_ramp_s (ball seconds), so the
## roll out to rest runs a little quicker than in play.
@export var roll_rate: float = 1.5
@export var roll_ramp_s: float = 0.6
## The camera leads the ball: it looks at the ground track this far (ball seconds) ahead of the
## ball, lifted by half the ball's height.
@export var lead_s: float = 0.7
## The camera runs out along the start line and follows this share of the ball's drift off it
## (0: straight down the line, 1: on the ball), so the bend reads as the ball curving across
## the screen.
@export var lateral_follow: float = 0.15
## The zoom the camera eases to while it follows the ball; nearer, by up to slow_zoom times,
## in the slow motion; and out to land_zoom from the landing to the rest.
@export var flight_zoom: float = 0.9
@export var slow_zoom: float = 1.2
@export var land_zoom: float = 0.7
## Once the ball rests, the camera pulls back to frame the whole drive (the tee, the start line
## and the track to the ball) inside the view less this margin on each side, screen px, never
## nearer than flight_zoom.
@export var settle_margin_px: float = 90.0
## The band at the top of the view the title takes, screen px: the pull-back frames the drive
## below it.
@export var title_band_px: float = 190.0
## The drawn track: the ball's ground track in sun_yellow and its start line in chalk dots,
## screen px at every zoom. The start line is guide_alpha while the guest aims and fades to
## guide_flight_alpha over the flight's first guide_fade_s, so the track's bend away from it
## reads.
@export var track_width_px: float = 4.0
@export var guide_dot_px: float = 2.5
@export var guide_gap_px: float = 12.0
@export var guide_alpha: float = 0.8
@export var guide_flight_alpha: float = 0.35
@export var guide_fade_s: float = 1.5
## The track's height over the ground in flight is the ground under it averaged over this many
## yards each way (pinned to the tee and the landing), so it leaves a raised tee smoothly.
@export var track_smooth_yd: float = 20.0
## The flight's arc in the air (the ball at its height), trail_width_px wide: bright over the
## ball's last trail_s (ball seconds), fading to trail_alpha behind.
@export var trail_s: float = 0.9
@export var trail_width_px: float = 4.0
@export var trail_alpha: float = 0.4
## Where it lands, a ring grows to land_ring_px (screen) and fades over land_ring_s.
@export var land_ring_px: float = 44.0
@export var land_ring_s: float = 0.7

@export_group("Title")
## The title fades in this long after the ball rests, over title_in_s, holds title_hold_s, and
## then the screen fades to black over fade_out_s and the menu fades in over menu_fade_s.
@export var title_delay_s: float = 0.5
@export var title_in_s: float = 1.0
@export var title_hold_s: float = 2.4
@export var fade_out_s: float = 0.8
@export var menu_fade_s: float = 0.5
@export var title: String = "Prestwick"
@export var tagline: String = "Build a golf course, then play it."
@export var title_size: int = 72
@export var tagline_size: int = 24
## A frame's step of the clock is at most this, so a slow frame (the course view is built in
## the first) never skips a beat.
@export var max_step_s: float = 0.05


static func load_default() -> IntroTuning:
	return load(PATH) as IntroTuning
